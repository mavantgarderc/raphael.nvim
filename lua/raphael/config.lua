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
---   animate          : table         -- { enabled:boolean, duration:number, steps:number }
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
  recent_group = false,

  theme_map = nil,
  filetype_themes = {},

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

local function warn(msg)
  vim.notify("raphael: " .. msg, vim.log.levels.WARN)
end

local function is_callable(fn)
  return type(fn) == "function"
end

--- Validate and normalize user configuration.
---
--- Responsibilities:
---   - Deep-merge user opts into M.defaults
---   - Validate:
---       * leader, mappings
---       * default_theme, bookmark_group, recent_group
---       * theme_map, filetype_themes
---       * animate, sort_mode, custom_sorts
---       * theme_aliases, history_max_size
---       * sample_preview
---       * on_apply
---       * enable_* toggles
---       * icons (merges into constants.ICON)
---   - Returns a safe, normalized config table used by raphael.core.
---
---@param user table|nil  User-provided configuration
---@return table cfg      Normalized + merged config
function M.validate(user)
  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user or {})

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

  if type(cfg.animate) ~= "table" then
    warn("config.animate must be a table; using defaults")
    cfg.animate = vim.deepcopy(M.defaults.animate)
  else
    if type(cfg.animate.enabled) ~= "boolean" then
      cfg.animate.enabled = M.defaults.animate.enabled
    end
    if type(cfg.animate.duration) ~= "number" or cfg.animate.duration < 0 then
      cfg.animate.duration = M.defaults.animate.duration
    end
    if type(cfg.animate.steps) ~= "number" or cfg.animate.steps < 1 then
      cfg.animate.steps = M.defaults.animate.steps
    end
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

  if cfg.icons ~= nil and type(cfg.icons) ~= "table" then
    warn("config.icons must be a table; ignoring")
    cfg.icons = {}
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
