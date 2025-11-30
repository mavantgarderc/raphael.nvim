-- lua/raphael/config.lua
-- Defaults + validation for raphael.nvim configuration.
--
-- Responsibilities:
--   - Define a single source of truth for all default options (M.defaults)
--   - Provide a validate(user_opts) function that:
--       * merges user options with defaults
--       * normalizes & clamps values
--       * drops invalid entries
--       * updates constants.ICON in-place using config.icons overrides

local constants = require("raphael.constants")

local M = {}

--- Default configuration for raphael.nvim.
---
--- Fields:
---   leader           : string
---   mappings         : table (keys: picker, next, previous, others, auto, refresh, status, [random])
---   default_theme    : string
---   bookmark_group   : boolean       -- show/hide "Bookmarks" section in picker
---   recent_group     : boolean       -- show/hide "Recent" section in picker
---   theme_map        : table|nil     -- list/map/nested; used by raphael.themes
---   filetype_themes  : table         -- ft -> theme_name
---   project_themes   : table         -- dir-prefix -> theme_name
---   filetype_overrides_project : boolean -- when both a filetype + project theme match, filetype wins if true
---   project_overrides_filetype : boolean -- when both a filetype + project theme match, project wins if true
---   profiles         : table         -- name -> partial config (overlays base config)
---   current_profile  : string|nil    -- active profile name at startup (optional)
---   profile_scoped_state : boolean   -- if true, bookmarks/slots are scoped per profile
---   sort_mode        : string        -- "alpha"|"recent"|"usage"|custom
---   custom_sorts     : table         -- sort_mode -> comparator(a,b) -> boolean
---   theme_aliases    : table         -- alias -> real theme name
---   history_max_size : integer       -- in-memory undo/redo size (extras/history)
---   sample_preview   : table         -- code sample preview config
---   icons            : table         -- icon overrides, merged into constants.ICON
---   on_apply         : function      -- hook after theme applied
---   enable_*         : booleans      -- feature toggles
M.defaults = {
  leader = "<leader>t",

  mappings = {
    picker = "p",
    next = ">",
    previous = "<",
    others = "/",
    auto = "a",
    refresh = "R",
    status = "s",
    random = "r",
  },

  default_theme = "kanagawa-paper-ink",

  bookmark_group = true,
  recent_group = true,

  theme_map = nil,
  filetype_themes = {},
  project_themes = {},

  -- Priority flags for auto-theme (filetype vs project).
  -- Exactly one of these should be true, or both false for "default priority".
  -- Default priority = project first, then filetype (matches historical behavior).
  filetype_overrides_project = false,
  project_overrides_filetype = false,

  -- Theme profiles (work / night / presentation, etc.)
  -- Each profile is a partial config:
  --   profiles = {
  --     work = { default_theme = "...", filetype_themes = { ... }, ... },
  --     night = { default_theme = "..." },
  --   }
  -- current_profile is the profile name to activate at startup (optional).
  profiles = {},
  current_profile = nil,

  -- If true, bookmarks and quick_slots are stored per-profile:
  --   bookmarks   = { __global = {...}, work = {...}, ... }
  --   quick_slots = { __global = {...}, work = {...}, ... }
  -- If false, everything uses __global only.
  profile_scoped_state = false,

  sort_mode = "alpha",
  custom_sorts = {},

  theme_aliases = {},

  history_max_size = 13,

  sample_preview = {
    enabled = true,
    relative_size = 0.5,
    languages = nil,
  },

  icons = vim.deepcopy(constants.ICON),

  on_apply = function(theme)
    vim.schedule(function()
      local ok, lualine = pcall(require, "lualine")
      if ok then
        local lualine_theme = "auto"
        local cfg = lualine.get_config()
        cfg.options = cfg.options or {}
        cfg.options.theme = lualine_theme
        lualine.setup(cfg)
      end
    end)
  end,

  enable_autocmds = true,
  enable_commands = true,
  enable_keymaps = true,
  enable_picker = true,
}

local SIMPLE_TYPE_SCHEMA = {
  leader = "string",
  mappings = "table",
  default_theme = "string",

  bookmark_group = "boolean",
  recent_group = "boolean",

  theme_map = { "table", "nil" },
  filetype_themes = "table",
  project_themes = "table",

  filetype_overrides_project = "boolean",
  project_overrides_filetype = "boolean",

  profiles = { "table", "nil" },
  current_profile = { "string", "nil" },

  profile_scoped_state = "boolean",

  sort_mode = "string",
  custom_sorts = "table",

  theme_aliases = "table",

  history_max_size = "number",

  sample_preview = "table",

  icons = { "table", "nil" },

  on_apply = "function",

  enable_autocmds = "boolean",
  enable_commands = "boolean",
  enable_keymaps = "boolean",
  enable_picker = "boolean",
}

local KNOWN_KEYS = {}
for k in pairs(M.defaults) do
  KNOWN_KEYS[k] = true
end
for k in pairs(SIMPLE_TYPE_SCHEMA) do
  KNOWN_KEYS[k] = true
end

local function warn(msg)
  vim.notify("raphael: " .. msg, vim.log.levels.WARN)
end

local function is_callable(fn)
  return type(fn) == "function"
end

local function type_matches(val, expected)
  if type(expected) == "string" then
    return type(val) == expected
  end
  if type(expected) == "table" then
    local t = type(val)
    for _, e in ipairs(expected) do
      if t == e then
        return true
      end
    end
    return false
  end
  return true
end

local function apply_schema(cfg, user)
  user = user or {}

  for key in pairs(user) do
    if not KNOWN_KEYS[key] then
      warn(string.format("Unknown config key '%s'; ignoring (not used by raphael)", tostring(key)))
    end
  end

  for key, expected in pairs(SIMPLE_TYPE_SCHEMA) do
    local val = cfg[key]
    local default_val = M.defaults[key]

    local allows_nil = default_val == nil and type(expected) == "table" and vim.tbl_contains(expected, "nil")

    if val == nil then
      if default_val ~= nil then
        cfg[key] = vim.deepcopy(default_val)
      elseif not allows_nil then
        warn(string.format("config.%s is nil; keeping nil (no default)", key))
      end
    else
      if not type_matches(val, expected) then
        warn(string.format("config.%s has wrong type (got %s); using default", key, type(val)))
        cfg[key] = vim.deepcopy(default_val)
      end
    end
  end
end

--- Validate and normalize user configuration.
---
---@param user table|nil  User-provided configuration
---@return table cfg      Normalized + merged config
function M.validate(user)
  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user or {})

  apply_schema(cfg, user or {})

  if type(cfg.leader) ~= "string" or cfg.leader == "" then
    warn("config.leader must be a non-empty string; using default")
    cfg.leader = M.defaults.leader
  end

  if type(cfg.mappings) ~= "table" then
    warn("config.mappings must be a table; using defaults")
    cfg.mappings = vim.deepcopy(M.defaults.mappings)
  else
    local default_map = M.defaults.mappings
    for key, def_val in pairs(default_map) do
      local val = cfg.mappings[key]
      if val ~= nil and type(val) ~= "string" then
        warn(string.format("config.mappings.%s must be a string; using default", key))
        cfg.mappings[key] = def_val
      elseif val == nil then
        cfg.mappings[key] = def_val
      end
    end
  end

  if type(cfg.default_theme) ~= "string" or cfg.default_theme == "" then
    warn("config.default_theme must be a non-empty string; using default")
    cfg.default_theme = M.defaults.default_theme
  end

  for _, field in ipairs({ "bookmark_group", "recent_group" }) do
    local val = cfg[field]
    if type(val) ~= "boolean" then
      if val ~= nil then
        warn(string.format("config.%s must be a boolean; using default", field))
      end
      cfg[field] = M.defaults[field]
    end
  end

  if cfg.filetype_overrides_project and cfg.project_overrides_filetype then
    warn(
      "config.filetype_overrides_project and config.project_overrides_filetype are both true; "
        .. "defaulting to project_overrides_filetype"
    )
    cfg.filetype_overrides_project = false
  end

  if cfg.theme_map ~= nil and type(cfg.theme_map) ~= "table" then
    warn("config.theme_map must be a table (or nil); ignoring value")
    cfg.theme_map = nil
  end

  if type(cfg.filetype_themes) ~= "table" then
    warn("config.filetype_themes must be a table; using empty table")
    cfg.filetype_themes = {}
  else
    local cleaned = {}
    for ft, theme in pairs(cfg.filetype_themes) do
      if type(ft) == "string" and type(theme) == "string" and theme ~= "" then
        cleaned[ft] = theme
      else
        warn(string.format("Invalid filetype_themes entry (%s = %s), ignoring", tostring(ft), tostring(theme)))
      end
    end
    cfg.filetype_themes = cleaned
  end

  if type(cfg.project_themes) ~= "table" then
    warn("config.project_themes must be a table; using empty table")
    cfg.project_themes = {}
  else
    local cleaned = {}
    for path, theme in pairs(cfg.project_themes) do
      if type(path) == "string" and type(theme) == "string" and theme ~= "" then
        cleaned[path] = theme
      else
        warn(string.format("Invalid project_themes entry (%s = %s), ignoring", tostring(path), tostring(theme)))
      end
    end
    cfg.project_themes = cleaned
  end

  if cfg.profiles ~= nil and type(cfg.profiles) ~= "table" then
    warn("config.profiles must be a table of name -> table; ignoring")
    cfg.profiles = {}
  else
    local cleaned_profiles = {}
    for name, prof in pairs(cfg.profiles or {}) do
      if type(name) == "string" and type(prof) == "table" then
        cleaned_profiles[name] = prof
      else
        warn(string.format("Invalid profiles entry (%s = %s), ignoring", tostring(name), tostring(prof)))
      end
    end
    cfg.profiles = cleaned_profiles
  end

  if cfg.current_profile ~= nil and type(cfg.current_profile) ~= "string" then
    warn("config.current_profile must be a string or nil; ignoring")
    cfg.current_profile = nil
  end

  if cfg.current_profile ~= nil and not cfg.profiles[cfg.current_profile] then
    warn(
      string.format(
        "config.current_profile '%s' has no matching entry in config.profiles; ignoring",
        tostring(cfg.current_profile)
      )
    )
    cfg.current_profile = nil
  end

  if type(cfg.sort_mode) ~= "string" then
    cfg.sort_mode = M.defaults.sort_mode
  end
  local mode = cfg.sort_mode
  if mode == "alphabetical" then
    mode = "alpha"
  end

  local built_in_modes = { alpha = true, recent = true, usage = true }
  local is_builtin = built_in_modes[mode] == true
  local has_custom = (type(cfg.custom_sorts) == "table") and is_callable(cfg.custom_sorts[mode])

  if not is_builtin and not has_custom then
    warn(
      string.format(
        "config.sort_mode '%s' is not a built-in mode and has no custom_sorts entry; using '%s'",
        tostring(cfg.sort_mode),
        M.defaults.sort_mode
      )
    )
    mode = M.defaults.sort_mode
  end
  cfg.sort_mode = mode

  if type(cfg.custom_sorts) ~= "table" then
    cfg.custom_sorts = {}
  else
    for k, v in pairs(cfg.custom_sorts) do
      if not is_callable(v) then
        warn(string.format("config.custom_sorts['%s'] is not a function; ignoring", tostring(k)))
        cfg.custom_sorts[k] = nil
      end
    end
  end

  if type(cfg.theme_aliases) ~= "table" then
    cfg.theme_aliases = {}
  else
    local cleaned = {}
    for alias, real in pairs(cfg.theme_aliases) do
      if type(alias) == "string" and type(real) == "string" and real ~= "" then
        cleaned[alias] = real
      else
        warn(string.format("Invalid theme_aliases entry (%s = %s), ignoring", tostring(alias), tostring(real)))
      end
    end
    cfg.theme_aliases = cleaned
  end

  if type(cfg.history_max_size) ~= "number" or cfg.history_max_size < 1 then
    warn("config.history_max_size must be a positive integer; using default")
    cfg.history_max_size = M.defaults.history_max_size
  else
    cfg.history_max_size = math.floor(cfg.history_max_size)
  end

  if type(cfg.sample_preview) ~= "table" then
    warn("config.sample_preview must be a table; using defaults")
    cfg.sample_preview = vim.deepcopy(M.defaults.sample_preview)
  else
    if type(cfg.sample_preview.enabled) ~= "boolean" then
      cfg.sample_preview.enabled = M.defaults.sample_preview.enabled
    end
    if type(cfg.sample_preview.relative_size) ~= "number" then
      cfg.sample_preview.relative_size = M.defaults.sample_preview.relative_size
    else
      if cfg.sample_preview.relative_size < 0.1 then
        cfg.sample_preview.relative_size = 0.1
      elseif cfg.sample_preview.relative_size > 1.0 then
        cfg.sample_preview.relative_size = 1.0
      end
    end
    if cfg.sample_preview.languages ~= nil and not vim.islist(cfg.sample_preview.languages) then
      warn("config.sample_preview.languages must be a list of names or nil; ignoring")
      cfg.sample_preview.languages = nil
    end
  end

  if not is_callable(cfg.on_apply) then
    warn("config.on_apply must be a function; using default")
    cfg.on_apply = M.defaults.on_apply
  end

  for _, field in ipairs({ "enable_autocmds", "enable_commands", "enable_keymaps", "enable_picker" }) do
    local val = cfg[field]
    if type(val) ~= "boolean" then
      if val ~= nil then
        warn(string.format("config.%s must be a boolean; using default", field))
      end
      cfg[field] = M.defaults[field]
    end
  end

  do
    local icon_table = constants.ICON
    if type(cfg.icons) == "table" then
      for key, val in pairs(cfg.icons) do
        if type(val) == "string" and val ~= "" then
          icon_table[key] = val
        else
          warn(string.format("config.icons['%s'] must be a non-empty string; ignoring", tostring(key)))
        end
      end
    end
    cfg.icons = icon_table
  end

  return cfg
end

return M
