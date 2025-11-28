-- lua/raphael/core/cache.lua
--- Read/write persistent state: themes, bookmarks, history, undo stack, etc.
--- Uses JSON format for human-readability and a single STATE_FILE path.

local constants = require("raphael.constants")

local M = {}

-- ────────────────────────────────────────────────────────────────────────
-- Internals
-- ────────────────────────────────────────────────────────────────────────

local uv = vim.loop

--- Ensure the directory for STATE_FILE exists.
local function ensure_dir()
  local dir = vim.fn.fnamemodify(constants.STATE_FILE, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

--- Default state structure.
local function default_state()
  return {
    current = nil, -- currently active theme
    saved = nil, -- last manually saved theme
    previous = nil, -- theme before current (for quick revert)
    auto_apply = false, -- auto-apply enabled/disabled

    bookmarks = {}, -- array of bookmarked theme names
    history = {}, -- array of recently used themes (newest first)
    usage = {}, -- map of theme_name -> usage_count

    collapsed = {}, -- map of group_key -> boolean (collapsed state)

    -- canonical short sort modes: "alpha", "recent", "usage"
    sort_mode = "alpha",

    undo_history = {
      stack = {}, -- undo stack of themes
      index = 0, -- current position in stack
      max_size = constants.HISTORY_MAX_SIZE, -- max stack size
    },
  }
end

--- Normalize and merge decoded JSON into a full state table.
---@param decoded table|nil
---@return table
local function normalize_state(decoded)
  local base = default_state()

  if type(decoded) ~= "table" then
    return base
  end

  for k, v in pairs(decoded) do
    base[k] = v
  end

  -- Ensure nested undo_history exists and is well-formed
  if type(base.undo_history) ~= "table" then
    base.undo_history = {
      stack = {},
      index = 0,
      max_size = constants.HISTORY_MAX_SIZE,
    }
  else
    base.undo_history.stack = base.undo_history.stack or {}
    base.undo_history.index = base.undo_history.index or 0
    base.undo_history.max_size = base.undo_history.max_size or constants.HISTORY_MAX_SIZE
  end

  -- Normalize sort_mode:
  --  - prefer short names: "alpha", "recent", "usage"
  --  - map legacy "alphabetical" -> "alpha"
  local mode = base.sort_mode or "alpha"
  if mode == "alphabetical" then
    mode = "alpha"
  end
  base.sort_mode = mode

  -- Ensure containers exist
  base.bookmarks = base.bookmarks or {}
  base.history = base.history or {}
  base.usage = base.usage or {}
  base.collapsed = base.collapsed or {}

  return base
end

--- Async write helper.
---@param path string
---@param data string
local function async_write(path, data)
  ensure_dir()

  uv.fs_open(path, "w", 438, function(open_err, fd)
    if open_err or not fd then
      vim.schedule(function()
        vim.notify("raphael.nvim: Failed to open state file for writing: " .. tostring(open_err), vim.log.levels.ERROR)
      end)
      return
    end

    uv.fs_write(fd, data, -1, function(write_err)
      if write_err and write_err ~= 0 then
        vim.schedule(function()
          vim.notify("raphael.nvim: Failed to write state file: " .. tostring(write_err), vim.log.levels.ERROR)
        end)
      end
      uv.fs_close(fd)
    end)
  end)
end

-- ────────────────────────────────────────────────────────────────────────
-- Core API: full read/write
-- ────────────────────────────────────────────────────────────────────────

--- Read state from disk (or return defaults if file doesn't exist / is invalid).
---@return table state
function M.read()
  local file = io.open(constants.STATE_FILE, "r")
  if not file then
    return default_state()
  end

  local content = file:read("*a")
  file:close()

  if not content or content == "" then
    return default_state()
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    vim.notify("raphael.nvim: Failed to decode state file, using defaults", vim.log.levels.WARN)
    return default_state()
  end

  return normalize_state(decoded)
end

--- Write full state to disk (async).
---@param state table
---@return boolean success
function M.write(state)
  local normalized = normalize_state(state)

  local ok, encoded = pcall(vim.json.encode, normalized)
  if not ok then
    vim.notify("raphael.nvim: Failed to encode state", vim.log.levels.ERROR)
    return false
  end

  async_write(constants.STATE_FILE, encoded)
  return true
end

--- For debugging only: return current state from disk.
---@return table
function M.get_state()
  return M.read()
end

--- Clear everything and reset to defaults.
function M.clear()
  local state = default_state()
  M.write(state)
end

-- ────────────────────────────────────────────────────────────────────────
-- Convenience helpers (stateless, always go via read/write)
-- ────────────────────────────────────────────────────────────────────────

--- Get current theme.
---@return string|nil
function M.get_current()
  local state = M.read()
  return state.current
end

--- Get saved theme (manually persisted theme).
---@return string|nil
function M.get_saved()
  local state = M.read()
  return state.saved
end

--- Set current theme (and optionally mark as saved).
---@param theme string
---@param save boolean
function M.set_current(theme, save)
  local state = M.read()
  state.previous = state.current
  state.current = theme

  if save then
    state.saved = theme
  end

  M.write(state)
end

--- Get bookmarks.
---@return string[] bookmarks
function M.get_bookmarks()
  local state = M.read()
  return state.bookmarks or {}
end

--- Toggle bookmark for a theme.
---@param theme string
---@return boolean is_bookmarked  -- true if now bookmarked, false if removed
function M.toggle_bookmark(theme)
  local state = M.read()
  state.bookmarks = state.bookmarks or {}

  local idx = nil
  for i, name in ipairs(state.bookmarks) do
    if name == theme then
      idx = i
      break
    end
  end

  if idx then
    table.remove(state.bookmarks, idx)
    M.write(state)
    return false
  else
    if #state.bookmarks >= constants.MAX_BOOKMARKS then
      vim.notify(
        string.format("raphael.nvim: Max bookmarks (%d) reached!", constants.MAX_BOOKMARKS),
        vim.log.levels.WARN
      )
      return false
    end
    table.insert(state.bookmarks, theme)
    M.write(state)
    return true
  end
end

--- Check if theme is bookmarked.
---@param theme string
---@return boolean
function M.is_bookmarked(theme)
  local bookmarks = M.get_bookmarks()
  for _, name in ipairs(bookmarks) do
    if name == theme then
      return true
    end
  end
  return false
end

--- Add theme to history (most recent first).
---@param theme string
function M.add_to_history(theme)
  local state = M.read()
  state.history = state.history or {}

  -- Remove existing occurrence
  for i, name in ipairs(state.history) do
    if name == theme then
      table.remove(state.history, i)
      break
    end
  end

  table.insert(state.history, 1, theme)

  while #state.history > constants.RECENT_THEMES_MAX do
    table.remove(state.history)
  end

  M.write(state)
end

--- Get history (most recent first).
---@return string[]
function M.get_history()
  local state = M.read()
  return state.history or {}
end

--- Increment usage count for theme.
---@param theme string
function M.increment_usage(theme)
  local state = M.read()
  state.usage = state.usage or {}
  state.usage[theme] = (state.usage[theme] or 0) + 1
  M.write(state)
end

--- Get usage count for theme.
---@param theme string
---@return number
function M.get_usage(theme)
  local state = M.read()
  return (state.usage or {})[theme] or 0
end

--- Get full usage map.
---@return table<string, number>
function M.get_all_usage()
  local state = M.read()
  return state.usage or {}
end

--- Get or set collapsed state for a group key.
---@param group_key string
---@param collapsed boolean|nil
---@return boolean collapsed_state
function M.collapsed(group_key, collapsed)
  local state = M.read()
  state.collapsed = state.collapsed or {}

  if collapsed ~= nil then
    state.collapsed[group_key] = collapsed
    M.write(state)
  end

  return state.collapsed[group_key] or false
end

--- Get current sort mode ("alpha", "recent", "usage", etc.).
---@return string
function M.get_sort_mode()
  local state = M.read()
  local mode = state.sort_mode or "alpha"
  if mode == "alphabetical" then
    mode = "alpha"
  end
  return mode
end

--- Set current sort mode.
---@param mode string
function M.set_sort_mode(mode)
  local state = M.read()
  state.sort_mode = mode
  M.write(state)
end

--- Get auto-apply flag.
---@return boolean
function M.get_auto_apply()
  local state = M.read()
  return state.auto_apply or false
end

--- Set auto-apply flag.
---@param enabled boolean
function M.set_auto_apply(enabled)
  local state = M.read()
  state.auto_apply = enabled and true or false
  M.write(state)
end

-- ────────────────────────────────────────────────────────────────────────
-- Undo stack helpers
-- ────────────────────────────────────────────────────────────────────────

--- Push theme onto undo stack.
---@param theme string
function M.undo_push(theme)
  local state = M.read()
  local undo = state.undo_history or {
    stack = {},
    index = 0,
    max_size = constants.HISTORY_MAX_SIZE,
  }

  -- Remove everything after current index (branching)
  while #undo.stack > undo.index do
    table.remove(undo.stack)
  end

  -- Remove duplicates from stack (keep most recent position)
  for i = #undo.stack, 1, -1 do
    if undo.stack[i] == theme then
      table.remove(undo.stack, i)
      if i <= undo.index then
        undo.index = undo.index - 1
      end
    end
  end

  table.insert(undo.stack, theme)
  undo.index = #undo.stack

  -- Trim to max size
  local max_size = undo.max_size or constants.HISTORY_MAX_SIZE
  while #undo.stack > max_size do
    table.remove(undo.stack, 1)
    undo.index = undo.index - 1
  end

  state.undo_history = undo
  M.write(state)
end

--- Undo to previous theme.
---@return string|nil theme
function M.undo_pop()
  local state = M.read()
  local undo = state.undo_history
  if not undo or undo.index <= 1 then
    return nil
  end

  undo.index = undo.index - 1
  state.undo_history = undo
  M.write(state)

  return undo.stack[undo.index]
end

--- Redo to next theme.
---@return string|nil theme
function M.redo_pop()
  local state = M.read()
  local undo = state.undo_history
  if not undo or undo.index >= #undo.stack then
    return nil
  end

  undo.index = undo.index + 1
  state.undo_history = undo
  M.write(state)

  return undo.stack[undo.index]
end

return M
