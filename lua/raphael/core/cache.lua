-- lua/raphael/core/cache.lua
--- Read/write persistent state: themes, bookmarks, history, undo stack, etc.
--- Uses JSON format for human-readability

local constants = require("raphael.constants")

local M = {}

--- Ensure cache directory exists
local function ensure_dir()
  local dir = vim.fn.fnamemodify(constants.STATE_FILE, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

--- Default state structure
local function default_state()
  return {
    current = nil, -- currently active theme
    saved = nil, -- last manually saved theme (persists across sessions)
    previous = nil, -- theme before current (for quick toggle)
    auto_apply = false, -- auto-apply enabled/disabled

    bookmarks = {}, -- array of bookmarked theme names
    history = {}, -- array of recently used themes (newest first)
    usage = {}, -- map of theme_name -> usage_count

    collapsed = {}, -- map of group_key -> boolean (collapsed state)
    sort_mode = "alphabetical", -- current sort mode

    undo_history = {
      stack = {}, -- undo stack of themes
      index = 0, -- current position in stack
      max_size = constants.HISTORY_MAX_SIZE,
    },
  }
end

--- Read state from disk
---@return table state The current state, or default if file doesn't exist
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

  -- Merge with defaults to ensure all fields exist (for backward compatibility)
  local state = default_state()
  for k, v in pairs(decoded) do
    state[k] = v
  end

  return state
end

--- Write state to disk
---@param state table State to persist
---@return boolean success Whether write succeeded
function M.write(state)
  ensure_dir()

  local ok, encoded = pcall(vim.json.encode, state)
  if not ok then
    vim.notify("raphael.nvim: Failed to encode state", vim.log.levels.ERROR)
    return false
  end

  local file = io.open(constants.STATE_FILE, "w")
  if not file then
    vim.notify("raphael.nvim: Failed to open state file for writing", vim.log.levels.ERROR)
    return false
  end

  file:write(encoded)
  file:close()
  return true
end

--- Get current theme
---@return string|nil theme Current theme name
function M.get_current()
  local state = M.read()
  return state.current
end

--- Get saved theme (manually set, persists across sessions)
---@return string|nil theme Saved theme name
function M.get_saved()
  local state = M.read()
  return state.saved
end

--- Set current theme (and optionally save it)
---@param theme string Theme name
---@param save boolean Whether to persist as saved theme
function M.set_current(theme, save)
  local state = M.read()
  state.previous = state.current
  state.current = theme

  if save then
    state.saved = theme
  end

  M.write(state)
end

--- Get bookmarks
---@return table bookmarks Array of bookmarked theme names
function M.get_bookmarks()
  local state = M.read()
  return state.bookmarks or {}
end

--- Toggle bookmark for a theme
---@param theme string Theme name
---@return boolean is_bookmarked Whether theme is now bookmarked
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
    -- Check max bookmarks limit
    if #state.bookmarks >= constants.MAX_BOOKMARKS then
      vim.notify(string.format("Max bookmarks (%d) reached!", constants.MAX_BOOKMARKS), vim.log.levels.WARN)
      return false
    end
    table.insert(state.bookmarks, theme)
    M.write(state)
    return true
  end
end

--- Check if theme is bookmarked
---@param theme string Theme name
---@return boolean is_bookmarked
function M.is_bookmarked(theme)
  local bookmarks = M.get_bookmarks()
  for _, name in ipairs(bookmarks) do
    if name == theme then
      return true
    end
  end
  return false
end

--- Add theme to history (most recent first)
---@param theme string Theme name
function M.add_to_history(theme)
  local state = M.read()
  state.history = state.history or {}

  -- Remove if already exists
  for i, name in ipairs(state.history) do
    if name == theme then
      table.remove(state.history, i)
      break
    end
  end

  -- Insert at front
  table.insert(state.history, 1, theme)

  -- Trim to max size
  while #state.history > constants.RECENT_THEMES_MAX do
    table.remove(state.history)
  end

  M.write(state)
end

--- Get history (most recent first)
---@return table history Array of theme names
function M.get_history()
  local state = M.read()
  return state.history or {}
end

--- Increment usage count for theme
---@param theme string Theme name
function M.increment_usage(theme)
  local state = M.read()
  state.usage = state.usage or {}
  state.usage[theme] = (state.usage[theme] or 0) + 1
  M.write(state)
end

--- Get usage count for theme
---@param theme string Theme name
---@return number count Usage count
function M.get_usage(theme)
  local state = M.read()
  return (state.usage or {})[theme] or 0
end

--- Get all usage data
---@return table usage Map of theme -> count
function M.get_all_usage()
  local state = M.read()
  return state.usage or {}
end

--- Get/set collapsed state for a group
---@param group_key string Group identifier
---@param collapsed boolean|nil If provided, sets the state; otherwise gets it
---@return boolean collapsed Current collapsed state
function M.collapsed(group_key, collapsed)
  local state = M.read()
  state.collapsed = state.collapsed or {}

  if collapsed ~= nil then
    state.collapsed[group_key] = collapsed
    M.write(state)
  end

  return state.collapsed[group_key] or false
end

--- Get current sort mode
---@return string sort_mode
function M.get_sort_mode()
  local state = M.read()
  return state.sort_mode or "alphabetical"
end

--- Set sort mode
---@param mode string Sort mode
function M.set_sort_mode(mode)
  local state = M.read()
  state.sort_mode = mode
  M.write(state)
end

--- Get auto-apply state
---@return boolean enabled
function M.get_auto_apply()
  local state = M.read()
  return state.auto_apply or false
end

--- Set auto-apply state
---@param enabled boolean
function M.set_auto_apply(enabled)
  local state = M.read()
  state.auto_apply = enabled
  M.write(state)
end

--- Push theme to undo stack
---@param theme string Theme name
function M.undo_push(theme)
  local state = M.read()
  local undo = state.undo_history

  -- Remove everything after current index (branching)
  while #undo.stack > undo.index do
    table.remove(undo.stack)
  end

  -- Push new theme
  table.insert(undo.stack, theme)
  undo.index = #undo.stack

  -- Trim to max size
  while #undo.stack > undo.max_size do
    table.remove(undo.stack, 1)
    undo.index = undo.index - 1
  end

  M.write(state)
end

--- Undo to previous theme
---@return string|nil theme Previous theme, or nil if at start
function M.undo_pop()
  local state = M.read()
  local undo = state.undo_history

  if undo.index > 1 then
    undo.index = undo.index - 1
    M.write(state)
    return undo.stack[undo.index]
  end

  return nil
end

--- Redo to next theme
---@return string|nil theme Next theme, or nil if at end
function M.redo_pop()
  local state = M.read()
  local undo = state.undo_history

  if undo.index < #undo.stack then
    undo.index = undo.index + 1
    M.write(state)
    return undo.stack[undo.index]
  end

  return nil
end

--- Get full state (for debugging)
---@return table state
function M.get_state()
  return M.read()
end

--- Clear all state (reset to defaults)
function M.clear()
  M.write(default_state())
end

return M
