-- lua/raphael/constants.lua
-- Centralised constants for raphael.nvim:
--   - paths
--   - limits
--   - icons
--   - namespaces
--   - highlight groups
--
-- This module is the single place where "magic values" live.
-- Most of these are read by config.lua and other modules, and in the case
-- of ICON, are mutated by config.validate() to apply user overrides.

local M = {}

--- Main JSON state file (persistent state).
--- This is the single source of truth for:
---   - current/saved/previous theme
---   - bookmarks
---   - history
---   - usage
---   - undo stack
---   - sort mode
---   - collapsed groups
---@type string
M.STATE_FILE = vim.fn.stdpath("data") .. "/raphael/state.json"

--- Optional cache directory for any future heavy data (palettes, etc.)
---@type string
M.CACHE_DIR = vim.fn.stdpath("cache") .. "/raphael"

--- Maximum entries in undo/redo history stack.
---@type integer
M.HISTORY_MAX_SIZE = 100

--- How many recent themes to keep in `state.history` (for Recent section).
---@type integer
M.RECENT_THEMES_MAX = 12

--- Max number of bookmarks before we refuse new ones (sanity limit).
---@type integer
M.MAX_BOOKMARKS = 50

--- Icon set used across the picker and status messages.
--- These values are the defaults; users may override any subset via
--- `require("raphael").setup({ icons = { KEY = "…" } })`, and config.validate()
--- will mutate this table in-place.
---@type table<string, string>
M.ICON = {
  HEADER = "Colorschemes",
  RECENT_HEADER = "Recent",
  BOOKMARKS_HEADER = "Bookmarks",

  BOOKMARK = "  ",
  CURRENT_ON = "  ",
  CURRENT_OFF = "  ",
  WARN = " 󰝧 ",

  GROUP_EXPANDED = "  ",
  GROUP_COLLAPSED = "  ",

  BLOCK = "  ",
  SEARCH = "   ",
  STATS = "  ",

  UNDO_ICON = "󰓕",
  REDO_ICON = "󰓗",
  HISTORY = "󰋚 ",
}

--- Namespaces used for extmarks in the picker UI.
---@type table<string, integer>
M.NS = {
  PICKER_CURSOR = vim.api.nvim_create_namespace("raphael_picker_cursor"),
  PALETTE = vim.api.nvim_create_namespace("raphael_palette"),
  SEARCH_MATCH = vim.api.nvim_create_namespace("raphael_search_match"),
}

--- Highlight groups used by the picker.
---@type table<string, string>
M.HL = {
  PICKER_CURSOR = "Visual",
  SEARCH_MATCH = "Search",
}

--- Default key hints (for future footer / status lines).
---@type string
M.FOOTER_HINTS = "<CR> apply • b bookmark • / search • s sort • q close"

return M
