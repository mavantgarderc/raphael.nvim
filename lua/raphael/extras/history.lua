local cache = require("raphael.core.cache")
local C = require("raphael.constants")

local M = {}

local function get_undo_state()
  local state = cache.read()
  local undo = state.undo_history or {}

  undo.stack = undo.stack or {}
  undo.index = undo.index or 0
  undo.max_size = undo.max_size or C.HISTORY_MAX_SIZE

  state.undo_history = undo
  return state, undo
end

local function save_undo_state(state)
  cache.write(state)
end

function M.add(theme)
  if not theme or theme == "" then
    return
  end

  local state, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0
  local max_size = undo.max_size or C.HISTORY_MAX_SIZE

  if idx < #stack then
    for i = #stack, idx + 1, -1 do
      table.remove(stack, i)
    end
  end

  for i = #stack, 1, -1 do
    if stack[i] == theme then
      table.remove(stack, i)
      if i <= idx then
        idx = idx - 1
      end
    end
  end

  table.insert(stack, theme)
  idx = #stack

  while #stack > max_size do
    table.remove(stack, 1)
    idx = idx - 1
  end

  undo.stack = stack
  undo.index = idx
  undo.max_size = max_size

  save_undo_state(state)
end

function M.undo(apply_fn)
  local state, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  if idx <= 1 or #stack == 0 then
    vim.notify(C.ICON.UNDO_ICON .. " Undo: no more history", vim.log.levels.INFO)
    return nil
  end

  idx = idx - 1
  undo.index = idx
  save_undo_state(state)

  local theme = stack[idx]
  if apply_fn and theme then
    apply_fn(theme)
  end

  vim.notify(string.format("%s Undo: %s (%d/%d)", C.ICON.UNDO_ICON, theme, idx, #stack), vim.log.levels.INFO)

  return theme
end

function M.redo(apply_fn)
  local state, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  if idx >= #stack or #stack == 0 then
    vim.notify(C.ICON.REDO_ICON .. " Redo: no more history", vim.log.levels.INFO)
    return nil
  end

  idx = idx + 1
  undo.index = idx
  save_undo_state(state)

  local theme = stack[idx]
  if apply_fn and theme then
    apply_fn(theme)
  end

  vim.notify(string.format("%s Redo: %s (%d/%d)", C.ICON.REDO_ICON, theme, idx, #stack), vim.log.levels.INFO)

  return theme
end

function M.current()
  local _, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  if idx > 0 and idx <= #stack then
    return stack[idx]
  end
  return nil
end

function M.can_undo()
  local _, undo = get_undo_state()
  return (undo.index or 0) > 1
end

function M.can_redo()
  local _, undo = get_undo_state()
  local stack = undo.stack
  return (undo.index or 0) < #stack
end

function M.show()
  local _, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  if #stack == 0 then
    vim.notify(C.ICON.HISTORY .. " No theme history", vim.log.levels.INFO)
    return
  end

  local lines = { C.ICON.HISTORY .. " Theme History:", "" }

  local start_idx = math.max(1, #stack - 9)
  for i = start_idx, #stack do
    local marker = (i == idx) and "→ " or "  "
    local num = string.format("[%d]", i)
    table.insert(lines, string.format("%s%s %s", marker, num, stack[i]))
  end

  table.insert(lines, "")
  table.insert(
    lines,
    string.format(
      "Position: %d/%d | Can undo: %s | Can redo: %s",
      idx,
      #stack,
      M.can_undo() and "yes" or "no",
      M.can_redo() and "yes" or "no"
    )
  )

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.jump(position, apply_fn)
  local state, undo = get_undo_state()
  local stack = undo.stack

  if position < 1 or position > #stack then
    vim.notify(string.format("Invalid position: %d (valid: 1-%d)", position, #stack), vim.log.levels.ERROR)
    return nil
  end

  undo.index = position
  save_undo_state(state)

  local theme = stack[position]
  if apply_fn and theme then
    apply_fn(theme)
  end

  vim.notify(string.format("Jumped to: %s (%d/%d)", theme, undo.index, #stack), vim.log.levels.INFO)

  return theme
end

function M.stats()
  local _, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  if #stack == 0 then
    return {
      total = 0,
      position = 0,
      can_undo = false,
      can_redo = false,
      unique_themes = 0,
      most_used = nil,
      most_used_count = 0,
      recent = nil,
    }
  end

  local counts = {}
  for _, theme in ipairs(stack) do
    counts[theme] = (counts[theme] or 0) + 1
  end

  local most_used, max_count = nil, 0
  for theme, count in pairs(counts) do
    if count > max_count then
      max_count = count
      most_used = theme
    end
  end

  return {
    total = #stack,
    position = idx,
    can_undo = M.can_undo(),
    can_redo = M.can_redo(),
    unique_themes = vim.tbl_count(counts),
    most_used = most_used,
    most_used_count = max_count,
    recent = stack[#stack],
  }
end

function M.reset()
  local state, undo = get_undo_state()
  undo.stack = {}
  undo.index = 0

  save_undo_state(state)

  vim.notify("Theme history cleared", vim.log.levels.INFO)
end

function M.serialize()
  local _, undo = get_undo_state()
  return {
    stack = vim.deepcopy(undo.stack),
    index = undo.index or 0,
    max_size = undo.max_size or C.HISTORY_MAX_SIZE,
  }
end

function M.deserialize(data)
  if type(data) ~= "table" then
    return
  end

  local state = cache.read()
  local undo = {
    stack = data.stack or {},
    index = data.index or 0,
    max_size = data.max_size or C.HISTORY_MAX_SIZE,
  }

  if undo.index > #undo.stack then
    undo.index = #undo.stack
  elseif undo.index < 0 then
    undo.index = 0
  end

  state.undo_history = undo
  cache.write(state)
end

function M.get_slice(count)
  count = count or 10
  local _, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  local start_idx = math.max(1, #stack - count + 1)
  local slice = {}

  for i = start_idx, #stack do
    table.insert(slice, {
      index = i,
      theme = stack[i],
      is_current = (i == idx),
    })
  end

  return slice
end

return M
