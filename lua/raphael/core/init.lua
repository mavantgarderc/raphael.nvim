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

local M = {}

--- Runtime configuration (validated by raphael.config.validate()).
---@type table
M.config = {}

--- In-memory state mirror of what is persisted via cache.
--- This is NOT the only source of truth; cache is canonical.
---@class RaphaelState
---@field current?  string  -- currently active theme
---@field saved?    string  -- last manually saved theme
---@field previous? string  -- theme before current (for quick revert)
---@field auto_apply boolean -- whether BufEnter/FileType auto-apply is enabled
---@field bookmarks string[] -- list of bookmarked themes
---@field history   string[] -- recent themes (newest first)
---@field usage     table<string, integer> -- usage count per theme
---@field collapsed table<string, boolean> -- group collapse state
---@field sort_mode string   -- current sort mode ("alpha", "recent", "usage", or custom)
---@field undo_history  table    -- detailed undo stack (managed by extras.history/cache)
---@field quick_slots   table<string,string> -- quick favorite slots 0–9
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
}

M.picker = picker

local function reload_state_from_cache()
  local s = cache.read()
  M.state = s
end

local function save_state_to_cache()
  cache.write(M.state)
end

--- Safely apply a colorscheme using :colorscheme.
--- Performs a basic hl clear / syntax reset to emulate :colorscheme behavior.
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

--- Record a manual theme change in usage + recent history + undo stack.
--- IMPORTANT: This is only for manual actions (picker, commands, keymaps),
--- not for auto-applies (BufEnter/FileType).
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

--- Setup core orchestrator.
---
--- This is typically called once from `require("raphael").setup(opts)`,
--- after `opts` has been validated by raphael.config.validate().
---
--- Responsibilities:
---   - Store validated config in M.config
---   - Initialize themes.theme_map and themes.filetype_themes
---   - Refresh installed themes list
---   - Load persisted state from cache (current/saved/etc.)
---   - Apply startup theme (saved theme or default_theme)
---@param config table
function M.setup(config)
  M.config = config or {}

  themes.filetype_themes = config.filetype_themes or {}
  themes.theme_map = config.theme_map or {}

  themes.refresh()

  M.state = cache.read()

  local startup_theme = M.state.saved or M.state.current or config.default_theme

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
---
--- Semantics:
---   - Validates theme availability via raphael.themes.
---   - Applies colorscheme and calls config.on_apply(theme) on success.
---   - Updates:
---       * state.previous (for quick revert)
---       * state.current
---       * state.saved (if from_manual is true)
---       * usage, history, undo stack (if from_manual is true)
---   - Persists state to cache.
---
--- @param theme string         Theme to apply (can be alias-resolved by caller)
--- @param from_manual boolean? Whether this is a manual change (picker/command/keymap)
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

--- Persist current state explicitly.
--- Used by picker to save collapsed/sort_mode changes.
function M.save_state()
  if not M.state then
    return
  end
  save_state_to_cache()
end

--- Toggle auto-apply on/off (used by :RaphaelToggleAuto and keymaps).
function M.toggle_auto()
  M.state.auto_apply = not (M.state.auto_apply == true)

  cache.set_auto_apply(M.state.auto_apply)
  vim.api.nvim_set_var("raphael_auto_theme", M.state.auto_apply)

  local msg = M.state.auto_apply and "raphael auto-theme: ON" or "raphael auto-theme: OFF"
  vim.notify(msg, vim.log.levels.INFO)
end

--- Toggle bookmark for a given theme name.
---@param theme string
function M.toggle_bookmark(theme)
  if not theme or theme == "" then
    return
  end

  local is_bookmarked = cache.toggle_bookmark(theme)

  M.state.bookmarks = cache.get_bookmarks()

  if is_bookmarked then
    vim.notify("raphael: bookmarked " .. theme, vim.log.levels.INFO)
  else
    vim.notify("raphael: removed bookmark " .. theme, vim.log.levels.INFO)
  end
end

--- Set a quick favorite slot (0–9) to a theme.
---@param slot string|number
---@param theme string
function M.set_quick_slot(slot, theme)
  if not theme or theme == "" then
    return
  end

  local s = tostring(slot)
  cache.set_quick_slot(s, theme)
  M.state.quick_slots = cache.get_quick_slots()

  vim.notify(string.format("raphael: quick slot %s -> %s", s, theme), vim.log.levels.INFO)
end

--- Get theme assigned to a quick slot.
---@param slot string|number
---@return string|nil
function M.get_quick_slot(slot)
  local s = tostring(slot)
  local slots = M.state.quick_slots or cache.get_quick_slots()
  return slots[s]
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

  vim.notify(
    string.format("raphael: current - %s%s | auto-apply: %s", M.state.current or "none", saved_info, auto_status),
    vim.log.levels.INFO
  )
end

-- TODO: FINISH HELP DOC
function M.show_help()
  vim.notify("raphael.nvim: see README for usage and keybindings.", vim.log.levels.INFO)
end

--- Export theme info suitable for embedding into session files.
--- This returns Vimscript lines that set:
---   g:raphael_session_theme
---   g:raphael_session_saved
---   g:raphael_session_auto
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

--- Restore theme from session variables (if they exist).
--- Looks at:
---   g:raphael_session_theme
---   g:raphael_session_saved
---   g:raphael_session_auto
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

--- Add a theme to the lightweight "recent" history (separate from undo stack).
--- which calls record_manual_change() instead.)
---@param theme string
function M.add_to_history(theme)
  if not theme or theme == "" then
    return
  end
  cache.add_to_history(theme)
  M.state.history = cache.get_history()
end

--- Open the theme picker UI.
---@param opts table|nil
function M.open_picker(opts)
  return picker.open(M, opts or {})
end

return M
