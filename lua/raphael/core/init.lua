-- lua/raphael/core/init.lua
-- Core orchestrator for raphael.nvim (new architecture).
--
-- Responsibilities:
--   - Hold in‑memory state (current/saved/previous theme, config, etc.)
--   - Coordinate between:
--       * raphael.themes          (installed + configured themes)
--       * raphael.core.cache      (persistent JSON state)
--       * raphael.extras.history  (undo/redo stack)
--       * raphael.picker.ui       (UI, picker window)
--   - Provide the public Lua API used by:
--       * raphael.init            (public entrypoint)
--       * core.autocmds           (BufEnter/filetype auto-apply)
--       * core.cmds               (:RaphaelApply, :RaphaelToggleAuto, etc.)
--       * core.keymaps_global     (leader mappings)

local cache = require("raphael.core.cache")
local history = require("raphael.extras.history")
local themes = require("raphael.themes")
local picker = require("raphael.picker.ui")

local palette_cache = nil
local function get_palette_cache()
  if not palette_cache then
    palette_cache = require("raphael.core.palette_cache")
  end
  return palette_cache
end

local M = {}

--- Base configuration as provided by the user (after validation).
--- This is the "root" config, prior to applying any profile overlay.
---@type table
M.base_config = {}

--- Active configuration (base_config overlaid with current profile, if any).
--- This is what the rest of the plugin uses.
---@type table
M.config = {}

--- In-memory state mirror of what is persisted via cache.
--- This is NOT the only source of truth; cache is canonical.
---@class RaphaelState
---@field current?         string                      -- currently active theme
---@field saved?           string                      -- last manually saved theme
---@field previous?        string                      -- theme before current (for quick revert)
---@field auto_apply       boolean                     -- whether BufEnter/FileType auto-apply is enabled
---@field bookmarks        table<string, string[]>     -- scope -> list of bookmarked themes
---@field history          string[]                    -- recent themes (newest first)
---@field usage            table<string, integer>      -- usage count per theme
---@field collapsed        table<string, boolean>      -- group collapse state
---@field sort_mode        string                      -- current sort mode ("alpha", "recent", "usage", or custom)
---@field undo_history     table                       -- detailed undo stack (managed by extras.history/cache)
---@field quick_slots      table<string, table<string, string>>   -- scope -> slot("0"-"9")->theme_name
---@field current_profile? string                      -- active profile name (if any)
M.state = {
  current = nil,
  saved = nil,
  previous = nil,
  auto_apply = false,
  bookmarks = {},
  history = {},
  usage = {},
  collapsed = {},
  sort_mode = "alpha",
  undo_history = {
    stack = {},
    index = 0,
    max_size = 0,
  },
  quick_slots = {},
  current_profile = nil,
}

M.picker = picker

local function save_state_to_cache()
  cache.write(M.state)
end

--- Safely apply a colorscheme using :colorscheme.
---@param theme string
---@return boolean ok
local function apply_colorscheme_raw(theme)
  vim.cmd("hi clear")
  if vim.fn.exists("syntax_on") == 1 then
    vim.cmd("syntax reset")
  end

  local ok, err = pcall(vim.cmd.colorscheme, theme)
  if not ok then
    vim.notify(
      string.format("raphael: failed to apply theme '%s': %s", tostring(theme), tostring(err)),
      vim.log.levels.ERROR
    )
    return false
  end

  return true
end

---@param theme string
local function record_manual_change(theme)
  if not theme or theme == "" then
    return
  end

  M.state.usage = M.state.usage or {}
  M.state.usage[theme] = (M.state.usage[theme] or 0) + 1

  M.state.history = M.state.history or {}

  for i, name in ipairs(M.state.history) do
    if name == theme then
      table.remove(M.state.history, i)
      break
    end
  end

  table.insert(M.state.history, 1, theme)

  cache.add_to_history(theme)
  history.add(theme)
end

--- Build the effective config for a given profile name.
---@param base table
---@param profile_name string|nil
---@return table effective_config
local function make_effective_config(base, profile_name)
  local base_copy = vim.deepcopy(base or {})
  local profiles = base_copy.profiles or {}
  base_copy.profiles = profiles

  if not profile_name then
    base_copy.current_profile = nil
    return base_copy
  end

  local prof_cfg = profiles[profile_name]
  if type(prof_cfg) ~= "table" then
    base_copy.current_profile = nil
    return base_copy
  end

  local effective = vim.tbl_deep_extend("force", base_copy, prof_cfg)
  effective.profiles = profiles
  effective.current_profile = profile_name
  return effective
end

--- Determine scope key for bookmarks/quick slots based on config + profile.
---@return string
local function get_scope_key()
  local cfg = M.config or {}
  if cfg.profile_scoped_state then
    local profile = M.state.current_profile or cfg.current_profile
    if type(profile) == "string" and profile ~= "" then
      return profile
    end
  end
  return "__global"
end

--- Setup core orchestrator.
---@param config table
function M.setup(config)
  M.base_config = config or {}

  M.state = cache.read()

  local profiles = M.base_config.profiles or {}
  local requested_profile = M.state.current_profile or M.base_config.current_profile

  if requested_profile and type(profiles[requested_profile]) ~= "table" then
    vim.notify(
      string.format(
        "raphael: configured profile '%s' not found in config.profiles; using base config",
        requested_profile
      ),
      vim.log.levels.WARN
    )
    requested_profile = nil
  end

  M.config = make_effective_config(M.base_config, requested_profile)
  M.state.current_profile = requested_profile

  M.state.bookmarks = cache.get_bookmarks_table()
  M.state.quick_slots = cache.get_quick_slots_table()

  save_state_to_cache()

  themes.filetype_themes = M.config.filetype_themes or {}
  themes.theme_map = M.config.theme_map or {}

  themes.refresh()

  local startup_theme = M.state.saved or M.state.current or M.config.default_theme

  if startup_theme and themes.is_available(startup_theme) then
    if apply_colorscheme_raw(startup_theme) then
      M.state.current = startup_theme
      M.state.saved = startup_theme
      save_state_to_cache()
    end
  else
    vim.notify(string.format("raphael: startup theme '%s' not available", tostring(startup_theme)), vim.log.levels.WARN)
  end
end

--- Apply a theme by name.
---@param theme string
---@param from_manual boolean?
function M.apply(theme, from_manual)
  if not theme or theme == "" then
    vim.notify("raphael: no theme specified", vim.log.levels.WARN)
    return
  end

  if not themes.is_available(theme) then
    vim.notify("raphael: theme not available: " .. tostring(theme), vim.log.levels.WARN)
    return
  end

  M.state.previous = M.state.current

  if not apply_colorscheme_raw(theme) then
    return
  end

  M.state.current = theme

  if from_manual then
    M.state.saved = theme
    record_manual_change(theme)
  else
    cache.increment_usage(theme)
  end

  save_state_to_cache()

  if type(M.config.on_apply) == "function" then
    M.config.on_apply(theme)
  end
end

function M.save_state()
  if not M.state then
    return
  end
  save_state_to_cache()
end

function M.toggle_auto()
  M.state.auto_apply = not (M.state.auto_apply == true) -- luacheck: ignore

  cache.set_auto_apply(M.state.auto_apply)
  vim.api.nvim_set_var("raphael_auto_theme", M.state.auto_apply)

  local msg = M.state.auto_apply and "raphael auto-theme: ON" or "raphael auto-theme: OFF"
  vim.notify(msg, vim.log.levels.INFO)
end

---@param theme string
function M.toggle_bookmark(theme)
  if not theme or theme == "" then
    return
  end

  local scope = get_scope_key()
  local is_bookmarked = cache.toggle_bookmark(theme, scope)

  M.state.bookmarks = M.state.bookmarks or { __global = {} }
  if type(M.state.bookmarks[scope]) ~= "table" then
    M.state.bookmarks[scope] = {}
  end
  local list = M.state.bookmarks[scope]

  if is_bookmarked then
    local found = false
    for _, name in ipairs(list) do
      if name == theme then
        found = true
        break
      end
    end
    if not found then
      table.insert(list, theme)
    end
  else
    for i, name in ipairs(list) do
      if name == theme then
        table.remove(list, i)
        break
      end
    end
  end

  local scope_msg = (scope ~= "__global") and (" in profile '" .. scope .. "'") or ""
  if is_bookmarked then
    vim.notify("raphael: bookmarked " .. theme .. scope_msg, vim.log.levels.INFO)
  else
    vim.notify("raphael: removed bookmark " .. theme .. scope_msg, vim.log.levels.INFO)
  end
end

function M.refresh_and_reload()
  themes.refresh()

  local current = M.state.current
  if current and themes.is_available(current) then
    M.apply(current, false)
  else
    vim.notify("raphael: current theme not available after refresh", vim.log.levels.WARN)
  end
end

function M.show_status()
  local auto_status = M.state.auto_apply and "ON" or "OFF"
  local saved_info = ""
  if M.state.saved and M.state.saved ~= M.state.current then
    saved_info = string.format(" | saved: %s", M.state.saved)
  end

  local profile = M.state.current_profile
  local profile_info = profile and (" | profile: " .. profile) or ""

  vim.notify(
    string.format(
      "raphael: current - %s%s | auto-apply: %s%s",
      M.state.current or "none",
      saved_info,
      auto_status,
      profile_info
    ),
    vim.log.levels.INFO
  )
end

function M.show_help()
  vim.notify("raphael.nvim: see README for usage and keybindings.", vim.log.levels.INFO)
end

---@return string
function M.export_for_session()
  local current = M.state.current or M.config.default_theme
  local saved = M.state.saved or current
  local auto = M.state.auto_apply and "1" or "0"

  return string.format(
    [[
" Raphael theme persistence
let g:raphael_session_theme = '%s'
let g:raphael_session_saved = '%s'
let g:raphael_session_auto = %s
]],
    current,
    saved,
    auto
  )
end

function M.restore_from_session()
  local session_theme = vim.g.raphael_session_theme
  local session_saved = vim.g.raphael_session_saved
  local session_auto = vim.g.raphael_session_auto

  if not session_theme then
    return
  end

  M.state.current = session_theme
  M.state.saved = session_saved or session_theme
  M.state.auto_apply = (session_auto == 1)

  if themes.is_available(session_theme) then
    apply_colorscheme_raw(session_theme)
  end

  save_state_to_cache()
end

---@param theme string
function M.add_to_history(theme)
  if not theme or theme == "" then
    return
  end
  cache.add_to_history(theme)
  M.state.history = cache.get_history()
end

---@param opts table|nil
function M.open_picker(opts)
  opts = opts or {}

  local result = picker.open(M, opts or {})

  return result
end

--- Set a quick favorite slot (0–9) to a theme (profile-aware if profile_scoped_state=true).
---@param slot  string|number
---@param theme string
function M.set_quick_slot(slot, theme)
  slot = tostring(slot)
  if slot == "" or not theme or theme == "" then
    vim.notify("raphael: invalid quick slot or theme", vim.log.levels.WARN)
    return
  end

  local scope = get_scope_key()
  cache.set_quick_slot(slot, theme, scope)

  M.state.quick_slots = cache.get_quick_slots_table()

  local scope_msg = (scope ~= "__global") and (" in profile '" .. scope .. "'") or ""
  vim.notify(string.format("raphael: quick slot %s -> %s%s", slot, theme, scope_msg), vim.log.levels.INFO)
end

--- Get a quick favorite slot theme (profile-aware if profile_scoped_state=true).
---@param slot string|number
---@return string|nil
function M.get_quick_slot(slot)
  slot = tostring(slot)
  local scope = get_scope_key()
  local all = M.state.quick_slots or {}
  local scoped = all[scope] or all.__global or {}
  return scoped[slot]
end

--- Switch active profile.
---
--- @param name string|nil   profile name, or nil for base
--- @param apply_default boolean|nil  whether to apply profile's default theme on switch (default: true)
function M.set_profile(name, apply_default)
  local profiles = (M.base_config and M.base_config.profiles) or {}

  if apply_default == nil then
    apply_default = true
  end

  if name ~= nil then
    if type(name) ~= "string" or name == "" then
      vim.notify("raphael: profile name must be a non-empty string or nil", vim.log.levels.WARN)
      return
    end
    if type(profiles[name]) ~= "table" then
      vim.notify("raphael: unknown profile '" .. tostring(name) .. "'", vim.log.levels.WARN)
      return
    end
  end

  if M.state.current_profile == name then
    vim.notify("raphael: profile already active: " .. (name or "base"), vim.log.levels.INFO)
    return
  end

  local effective = make_effective_config(M.base_config, name)
  M.config = effective
  M.state.current_profile = name

  M.state.bookmarks = cache.get_bookmarks_table()
  M.state.quick_slots = cache.get_quick_slots_table()

  save_state_to_cache()

  themes.filetype_themes = M.config.filetype_themes or {}
  themes.theme_map = M.config.theme_map or {}
  themes.refresh()

  local profile_label = name or "base"

  local prof_theme = M.config.default_theme
  if apply_default and prof_theme and themes.is_available(prof_theme) then
    M.apply(prof_theme, true)
    vim.notify(
      string.format("raphael: activated profile '%s' (default_theme = %s)", profile_label, prof_theme),
      vim.log.levels.INFO
    )
  else
    vim.notify(
      string.format("raphael: activated profile '%s' (no default_theme applied)", profile_label),
      vim.log.levels.INFO
    )
  end
end

--- Get list of available profile names (sorted).
---@return string[]
function M.get_profiles()
  local profiles = (M.base_config and M.base_config.profiles) or {}
  local names = {}
  for name, _ in pairs(profiles) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

--- Get the currently active profile name (or nil for base config).
---@return string|nil
function M.get_current_profile()
  return M.state.current_profile or M.config.current_profile
end

--- Get the currently active theme name (or nil).
---@return string|nil
function M.get_current_theme()
  return M.state.current
end

--- Get information about the current profile (for statusline, etc.).
---
--- Returns a table:
--- {
---   name = "work" | nil,
---   default_theme = "kanagawa-paper-edo" | nil,
---   has_overrides = {
---     filetype_themes = boolean,
---     project_themes  = boolean,
---     theme_map       = boolean,
---   },
--- }
---@return table
function M.get_profile_info()
  local base = M.base_config or {}
  local profiles = base.profiles or {}
  local name = M.get_current_profile()

  local info = {
    name = name,
    default_theme = nil,
    has_overrides = {
      filetype_themes = false,
      project_themes = false,
      theme_map = false,
    },
  }

  local function has_nonempty_table(t)
    return type(t) == "table" and next(t) ~= nil
  end

  if not name then
    info.default_theme = base.default_theme
    info.has_overrides.filetype_themes = has_nonempty_table(base.filetype_themes)
    info.has_overrides.project_themes = has_nonempty_table(base.project_themes)
    info.has_overrides.theme_map = has_nonempty_table(base.theme_map)
    return info
  end

  local prof = profiles[name]
  if type(prof) ~= "table" then
    info.default_theme = base.default_theme
    return info
  end

  info.default_theme = prof.default_theme or base.default_theme
  info.has_overrides.filetype_themes = has_nonempty_table(prof.filetype_themes)
  info.has_overrides.project_themes = has_nonempty_table(prof.project_themes)
  info.has_overrides.theme_map = has_nonempty_table(prof.theme_map)

  return info
end

--- Get effective config for a given profile (or base when name=nil).
---
---@param name string|nil
---@return table|nil
function M.get_profile_config(name)
  if name == nil then
    return vim.deepcopy(M.base_config or {})
  end

  local profiles = (M.base_config and M.base_config.profiles) or {}
  if type(profiles[name]) ~= "table" then
    return nil
  end

  return make_effective_config(M.base_config, name)
end

-- Set up periodic cleanup of expired cache entries (lazy initialization)
local function setup_periodic_cleanup()
  vim.schedule(function()
    vim.defer_fn(function()
      local ok, palette_cache_mod = pcall(get_palette_cache)
      if ok and palette_cache_mod and palette_cache_mod.clear_expired then
        palette_cache_mod.clear_expired()
      end
      local ok2, cache_mod = pcall(require, "raphael.core.cache")
      if ok2 and cache_mod and cache_mod.clear_expired_palette_cache then
        cache_mod.clear_expired_palette_cache()
      end
      setup_periodic_cleanup()
    end, 300000) -- ~ 5 minutes
  end)
end

vim.defer_fn(setup_periodic_cleanup, 10000)

return M
