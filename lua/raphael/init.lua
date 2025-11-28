-- lua/raphael/init.lua
--- Features:
---   • Live preview with real syntax-highlighted sample code
---   • Search, bookmarks, recent themes, collapsible groups
---   • Undo/redo history, random theme, next/prev navigation
---   • Filetype-based auto-apply
---   • Persistent state (bookmarks, history, current theme)
---   • Fully configurable via setup()

local M = {}

-- Global for people who still use the old style
_G.Raphael = _G.Raphael or M

-- Core modules (lazy-loaded when needed)
local cache = nil -- will be required on first setup()

--- Setup Raphael with your configuration
--- @param user_config table|nil Configuration table (see defaults in config.lua)
function M.setup(user_config)
  -- First-time require – everything else is lazy-loaded from here
  cache = require("raphael.core.cache")

  -- Merge user config with defaults and validate
  cache.setup(user_config or {})

  -- Expose the most-used API directly on the main module (backward compatible)
  M.apply = cache.apply
  M.toggle_auto = cache.toggle_auto
  M.toggle_bookmark = cache.toggle_bookmark
  M.open_picker = cache.open_picker
  M.refresh = cache.refresh_and_reload
  M.status = cache.show_status
  M.random = cache.random_theme
  M.next = cache.next_theme
  M.previous = cache.previous_theme
  M.undo = cache.undo_theme
  M.redo = cache.redo_theme

  -- Session persistence helpers
  M.export_for_session = cache.export_for_session
  M.restore_from_session = cache.restore_from_session

  -- Mark as loaded (some plugins check this)
  vim.g.raphael_loaded = true
end

--- Open the theme picker (same as <leader>tp by default)
--- @param opts table|nil Optional overrides (e.g. { only_configured = true })
function M.open_picker(opts)
  if not cache then
    cache = require("raphael.core.cache")
  end
  cache.open_picker(opts)
end

--- Apply a theme manually (used by commands, picker, etc.)
--- @param theme string Theme name
--- @param manual boolean|nil Whether this counts as a manual change (for history)
function M.apply(theme, manual)
  if not cache then
    cache = require("raphael.core.cache")
  end
  cache.apply(theme, manual ~= false)
end

--- Toggle filetype-based auto-apply
function M.toggle_auto()
  if not cache then
    cache = require("raphael.core.cache")
  end
  cache.toggle_auto()
end

--- Toggle bookmark for current or given theme
--- @param theme string|nil Theme name (defaults to current)
function M.toggle_bookmark(theme)
  if not cache then
    cache = require("raphael.core.cache")
  end
  cache.toggle_bookmark(theme)
end

--- Show current status in a notification
function M.status()
  if not cache then
    cache = require("raphael.core.cache")
  end
  cache.show_status()
end

return M
