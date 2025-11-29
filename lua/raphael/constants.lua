local M = {}

M.STATE_FILE = vim.fn.stdpath("data") .. "/raphael/state.json"

M.CACHE_DIR = vim.fn.stdpath("cache") .. "/raphael"

M.HISTORY_MAX_SIZE = 100

M.RECENT_THEMES_MAX = 12

M.MAX_BOOKMARKS = 50

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
  HISTORY = "󰋚",
}

M.NS = {
  PICKER_CURSOR = vim.api.nvim_create_namespace("raphael_picker_cursor"),
  PALETTE = vim.api.nvim_create_namespace("raphael_palette"),
  SEARCH_MATCH = vim.api.nvim_create_namespace("raphael_search_match"),
}

M.HL = {
  PICKER_CURSOR = "Visual",
  SEARCH_MATCH = "Search",
}

M.FOOTER_HINTS = "<CR> apply • b bookmark • / search • s sort • q close"

return M
