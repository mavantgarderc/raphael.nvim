-- lua/raphael/core/cache.lua
--- Read/write persistent state: themes, bookmarks, history, undo stack, etc.
--- Uses JSON format for human-readability and a single STATE_FILE path.
---
--- This module is intentionally "stateless":
---   - Every helper reads the JSON, mutates, and writes it back.
---   - The in-memory "authoritative" state lives in raphael.core; this
---     module is the disk-backed source of truth.

local constants = require("raphael.constants")

local M = {}

local uv = vim.loop

local decode_failed_once = false

local function ensure_dir()
  local dir = vim.fn.fnamemodify(constants.STATE_FILE, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

--- Default state structure (pure, no side effects).
---
--- @return table state
local function default_state()
  return {
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
      max_size = constants.HISTORY_MAX_SIZE,
    },

    quick_slots = {},

    current_profile = nil,
  }
end

--- Normalize and merge decoded JSON into a full state table.
--- Ensures that:
---   - All keys exist (even if file is old / partial)
---   - undo_history is structurally valid
---   - sort_mode is normalized ("alphabetical" -> "alpha")
---
--- @param decoded table|nil
--- @return table state
local function normalize_state(decoded)
  local base = default_state()

  if type(decoded) ~= "table" then
    return base
  end

  for k, v in pairs(decoded) do
    base[k] = v
  end

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

  local mode = base.sort_mode or "alpha"
  if mode == "alphabetical" then
    mode = "alpha"
  end
  base.sort_mode = mode

  base.bookmarks = base.bookmarks or {}
  base.history = base.history or {}
  base.usage = base.usage or {}
  base.collapsed = base.collapsed or {}

  if type(base.quick_slots) ~= "table" then
    base.quick_slots = {}
  end

  if base.current_profile ~= nil and type(base.current_profile) ~= "string" then
    base.current_profile = nil
  end

  return base
end

--- Async write helper.
---
--- Writes `data` to `path` asynchronously using libuv, and notifies on error.
---
--- @param path string  Absolute path to state file
--- @param data string  JSON-encoded string
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

--- Read state from disk (or return defaults if file doesn't exist / is invalid).
---
--- This is the canonical entry for reading the on-disk state.
---
--- @return table state
function M.read()
  local file = io.open(constants.STATE_FILE, "r")
  if not file then
    return default_state()
  end

  local content = file:read("*a")
  file:close()

  if not content or content:match("^%s*$") then
    return default_state()
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    if not decode_failed_once then
      vim.notify("raphael.nvim: Failed to decode state file, using defaults", vim.log.levels.WARN)
      decode_failed_once = true
    end
    return default_state()
  end

  return normalize_state(decoded)
end

--- Write full state to disk (async).
---
--- This function:
---   - Normalizes the state (defensive against missing keys)
---   - Encodes as JSON
---   - Kicks off an async write to constants.STATE_FILE
---
--- @param state table  State table to persist
--- @return boolean success
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
---
--- @return table state
function M.get_state()
  return M.read()
end

--- Clear everything and reset to defaults (overwrites JSON file).
function M.clear()
  local state = default_state()
  M.write(state)
end

--- Get current theme from persistent state.
---
--- @return string|nil
function M.get_current()
  local state = M.read()
  return state.current
end

--- Get saved theme (manually persisted theme) from persistent state.
---
--- @return string|nil
function M.get_saved()
  local state = M.read()
  return state.saved
end

--- Set current theme (and optionally mark as saved) in persistent state.
---
--- Also updates `previous` to the old current theme.
---
--- @param theme string
--- @param save  boolean
function M.set_current(theme, save)
  local state = M.read()
  state.previous = state.current
  state.current = theme

  if save then
    state.saved = theme
  end

  M.write(state)
end

--- Get bookmarks from persistent state.
---
--- @return string[] bookmarks
function M.get_bookmarks()
  local state = M.read()
  return state.bookmarks or {}
end

--- Toggle bookmark for a theme in persistent state.
---
--- Semantics:
---   - If theme is already bookmarked, it is removed and returns false.
---   - Otherwise, it is added (if under MAX_BOOKMARKS) and returns true.
---
--- @param theme string
--- @return boolean is_bookmarked  true if now bookmarked, false if removed or rejected
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

--- Check if theme is bookmarked in persistent state.
---
--- @param theme string
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

--- Add theme to history (most recent first) in persistent state.
---
--- Ensures:
---   - The theme is unique in history (removes previous occurrence)
---   - The list is capped to RECENT_THEMES_MAX
---
--- @param theme string
function M.add_to_history(theme)
  local state = M.read()
  state.history = state.history or {}

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

--- Get history (most recent first) from persistent state.
---
--- @return string[]
function M.get_history()
  local state = M.read()
  return state.history or {}
end

--- Increment usage count for theme in persistent state.
---
--- @param theme string
function M.increment_usage(theme)
  local state = M.read()
  state.usage = state.usage or {}
  state.usage[theme] = (state.usage[theme] or 0) + 1
  M.write(state)
end

--- Get usage count for theme from persistent state.
---
--- @param theme string
--- @return number
function M.get_usage(theme)
  local state = M.read()
  return (state.usage or {})[theme] or 0
end

--- Get full usage map from persistent state.
---
--- @return table<string, number>
function M.get_all_usage()
  local state = M.read()
  return state.usage or {}
end

--- Get or set collapsed state for a group key in persistent state.
---
--- If `collapsed` is provided, it sets the value and writes to disk.
--- Otherwise, it just returns the current collapsed state (default false).
---
--- @param group_key string
--- @param collapsed boolean|nil
--- @return boolean collapsed_state
function M.collapsed(group_key, collapsed)
  local state = M.read()
  state.collapsed = state.collapsed or {}

  if collapsed ~= nil then
    state.collapsed[group_key] = collapsed
    M.write(state)
  end

  return state.collapsed[group_key] or false
end

--- Get current sort mode ("alpha", "recent", "usage", etc.) from persistent state.
---
--- Normalizes legacy "alphabetical" to "alpha".
---
--- @return string
function M.get_sort_mode()
  local state = M.read()
  local mode = state.sort_mode or "alpha"
  if mode == "alphabetical" then
    mode = "alpha"
  end
  return mode
end

--- Set current sort mode in persistent state.
---
--- @param mode string
function M.set_sort_mode(mode)
  local state = M.read()
  state.sort_mode = mode
  M.write(state)
end

--- Get auto-apply flag from persistent state.
---
--- @return boolean
function M.get_auto_apply()
  local state = M.read()
  return state.auto_apply or false
end

--- Set auto-apply flag in persistent state.
---
--- @param enabled boolean
function M.set_auto_apply(enabled)
  local state = M.read()
  state.auto_apply = enabled and true or false
  M.write(state)
end

local function normalize_slot(slot)
  if type(slot) == "number" then
    slot = tostring(slot)
  end
  if type(slot) ~= "string" then
    return nil
  end
  if not slot:match("^[0-9]$") then
    return nil
  end
  return slot
end

--- Get all quick slots map from persistent state.
---
--- @return table<string, string>
function M.get_quick_slots()
  local state = M.read()
  return state.quick_slots or {}
end

--- Set a quick slot (0–9) to a theme name.
---
--- @param slot string|number
--- @param theme string
function M.set_quick_slot(slot, theme)
  slot = normalize_slot(slot)
  if not slot then
    vim.notify("raphael.nvim: quick slot must be 0–9", vim.log.levels.WARN)
    return
  end
  if not theme or theme == "" then
    vim.notify("raphael.nvim: quick slot theme must be non-empty", vim.log.levels.WARN)
    return
  end

  local state = M.read()
  state.quick_slots = state.quick_slots or {}
  state.quick_slots[slot] = theme
  M.write(state)
  return theme
end

--- Clear a quick slot (0–9).
---
--- @param slot string|number
function M.clear_quick_slot(slot)
  slot = normalize_slot(slot)
  if not slot then
    return
  end
  local state = M.read()
  if not state.quick_slots then
    return
  end
  state.quick_slots[slot] = nil
  M.write(state)
end

--- Get a single quick slot theme.
---
--- @param slot string|number
--- @return string|nil
function M.get_quick_slot(slot)
  slot = normalize_slot(slot)
  if not slot then
    return nil
  end
  local state = M.read()
  return (state.quick_slots or {})[slot]
end

--- Push theme onto undo stack in persistent state.
---
--- Semantics:
---   - Drops any "future" entries if we've undone (branch cut)
---   - Removes older duplicates of this theme
---   - Appends theme and moves index to the end
---   - Trims stack to max_size, dropping oldest entries
---
--- @param theme string
function M.undo_push(theme)
  local state = M.read()
  local undo = state.undo_history or {
    stack = {},
    index = 0,
    max_size = constants.HISTORY_MAX_SIZE,
  }

  while #undo.stack > undo.index do
    table.remove(undo.stack)
  end

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

  local max_size = undo.max_size or constants.HISTORY_MAX_SIZE
  while #undo.stack > max_size do
    table.remove(undo.stack, 1)
    undo.index = undo.index - 1
  end

  state.undo_history = undo
  M.write(state)
end

--- Undo to previous theme in persistent state.
---
--- Decrements the undo index and returns the new "current" theme from stack.
--- Returns nil if no further undo is possible.
---
--- @return string|nil theme
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

--- Redo to next theme in persistent state.
---
--- Increments the undo index and returns the new "current" theme from stack.
--- Returns nil if no further redo is possible.
---
--- @return string|nil theme
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
