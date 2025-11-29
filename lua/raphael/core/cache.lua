local constants = require("raphael.constants")

local M = {}

local uv = vim.loop

local function ensure_dir()
  local dir = vim.fn.fnamemodify(constants.STATE_FILE, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

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
  }
end

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

  return base
end

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

function M.get_state()
  return M.read()
end

function M.clear()
  local state = default_state()
  M.write(state)
end

function M.get_current()
  local state = M.read()
  return state.current
end

function M.get_saved()
  local state = M.read()
  return state.saved
end

function M.set_current(theme, save)
  local state = M.read()
  state.previous = state.current
  state.current = theme

  if save then
    state.saved = theme
  end

  M.write(state)
end

function M.get_bookmarks()
  local state = M.read()
  return state.bookmarks or {}
end

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

function M.is_bookmarked(theme)
  local bookmarks = M.get_bookmarks()
  for _, name in ipairs(bookmarks) do
    if name == theme then
      return true
    end
  end
  return false
end

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

function M.get_history()
  local state = M.read()
  return state.history or {}
end

function M.increment_usage(theme)
  local state = M.read()
  state.usage = state.usage or {}
  state.usage[theme] = (state.usage[theme] or 0) + 1
  M.write(state)
end

function M.get_usage(theme)
  local state = M.read()
  return (state.usage or {})[theme] or 0
end

function M.get_all_usage()
  local state = M.read()
  return state.usage or {}
end

function M.collapsed(group_key, collapsed)
  local state = M.read()
  state.collapsed = state.collapsed or {}

  if collapsed ~= nil then
    state.collapsed[group_key] = collapsed
    M.write(state)
  end

  return state.collapsed[group_key] or false
end

function M.get_sort_mode()
  local state = M.read()
  local mode = state.sort_mode or "alpha"
  if mode == "alphabetical" then
    mode = "alpha"
  end
  return mode
end

function M.set_sort_mode(mode)
  local state = M.read()
  state.sort_mode = mode
  M.write(state)
end

function M.get_auto_apply()
  local state = M.read()
  return state.auto_apply or false
end

function M.set_auto_apply(enabled)
  local state = M.read()
  state.auto_apply = enabled and true or false
  M.write(state)
end

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
