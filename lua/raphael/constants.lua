-- lua/raphael/constants.lua
--- Centralized constants for raphael.nvim
--- All magic values, paths, limits and UI icons live here.

local M = {}

-- ── File paths ────────────────────────────────────────────────────────
M.STATE_FILE = vim.fn.stdpath("data") .. "/raphael/state.json" -- main persistent state
M.CACHE_DIR = vim.fn.stdpath("cache") .. "/raphael" -- optional cache (future use)

-- ── Limits ─────────────────────────────────────────────────────────────
M.HISTORY_MAX_SIZE = 100 -- maximum entries in undo/redo history
M.RECENT_THEMES_MAX = 12 -- how many recent themes to show in picker
M.MAX_BOOKMARKS = 50 -- sanity limit (you probably won't hit it)

-- ── UI Icons (Nerd Font required) ─────────────────────────────────────
M.ICON = {
  HEADER = "󰏘 ",
  SEARCH = " ",
  CURRENT = " ",
  BOOKMARK = "★",
  WARN = " ",
  EXPANDED = " ",
  COLLAPSED = " ",
  RECENT = " ",
  PREVIEW = " ",
  APPLY = "󰄬 ",
  RANDOM = " ",
  NEXT = " ",
  PREVIOUS = " ",
  UNDO = " ",
  REDO = " ",
  CLOSE = "󰅖 ",
  TOGGLE = " ",
  REFRESH = " ",
  PALETTE = " ", -- sample code preview header
  EMPTY_GROUP = " ", -- for empty groups (will be suffix after refactor)
}

-- ── Extmark namespaces ───────────────────────────────────────────────
M.NS = {
  PICKER = vim.api.nvim_create_namespace("raphael_picker"),
  SEARCH_HL = vim.api.nvim_create_namespace("raphael_search_hl"),
  BOOKMARK = vim.api.nvim_create_namespace("raphael_bookmark"),
}

-- ── Highlight groups used in picker ───────────────────────────────────
M.HL = {
  HEADER = "RaphaelHeader",
  CURRENT = "RaphaelCurrent",
  BOOKMARK = "RaphaelBookmark",
  WARN = "RaphaelWarning",
  GROUP = "RaphaelGroup",
  PREVIEW_BG = "RaphaelPreviewBg",
  SEARCH_MATCH = "Search",
}

-- ── Default key hints shown in footer ─────────────────────────────────
M.FOOTER_HINTS = "<CR> apply • b bookmark • / search • s sort • q close"

-- ── Sort modes ─────────────────────────────────────────────────────────
M.SORT_MODES = {
  "alphabetical",
  "recent",
  "usage",
  "bookmarks_first",
}

return M
