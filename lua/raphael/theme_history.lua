local M = {}

M.stack = {}
M.index = 0
M.max_size = 13

function M.add(theme)
  if not theme then
    return
  end

  if M.index < #M.stack then
    for i = #M.stack, M.index + 1, -1 do
      table.remove(M.stack, i)
    end
  end

  for i = #M.stack, 1, -1 do
    if M.stack[i] == theme then
      table.remove(M.stack, i)
      if i <= M.index then
        M.index = M.index - 1
      end
    end
  end

  table.insert(M.stack, theme)
  M.index = #M.stack

  while #M.stack > M.max_size do
    table.remove(M.stack, 1)
    M.index = M.index - 1
  end
end

function M.undo(apply_fn)
  if M.index <= 1 then
    vim.notify("󰓕 Undo: no more history", vim.log.levels.INFO)
    return nil
  end
  M.index = M.index - 1
  local theme = M.stack[M.index]
  if apply_fn then
    apply_fn(theme)
  end
  vim.notify("󰓕 Undo: " .. theme .. " (" .. M.index .. "/" .. #M.stack .. ")", vim.log.levels.INFO)
  return theme
end

function M.redo(apply_fn)
  if M.index >= #M.stack then
    vim.notify("󰓗 Redo: no more history", vim.log.levels.INFO)
    return nil
  end
  M.index = M.index + 1
  local theme = M.stack[M.index]
  if apply_fn then
    apply_fn(theme)
  end
  vim.notify("󰓗 Redo: " .. theme .. " (" .. M.index .. "/" .. #M.stack .. ")", vim.log.levels.INFO)
  return theme
end

function M.current()
  if M.index > 0 and M.index <= #M.stack then
    return M.stack[M.index]
  end
  return nil
end

function M.can_undo()
  return M.index > 1
end

function M.can_redo()
  return M.index < #M.stack
end

function M.show()
  if #M.stack == 0 then
    vim.notify("󰋚 No theme history", vim.log.levels.INFO)
    return
  end

  local lines = { "󰋚 Theme History:", "" }

  local start_idx = math.max(1, #M.stack - 9)

  for i = start_idx, #M.stack do
    local marker = i == M.index and "→ " or "  "
    local num = string.format("[%d]", i)
    table.insert(lines, string.format("%s%s %s", marker, num, M.stack[i]))
  end

  table.insert(lines, "")
  table.insert(
    lines,
    string.format(
      "Position: %d/%d | Can undo: %s | Can redo: %s",
      M.index,
      #M.stack,
      M.can_undo() and "yes" or "no",
      M.can_redo() and "yes" or "no"
    )
  )

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.jump(position, apply_fn)
  if position < 1 or position > #M.stack then
    vim.notify(string.format("Invalid position: %d (valid: 1-%d)", position, #M.stack), vim.log.levels.ERROR)
    return nil
  end

  M.index = position
  local theme = M.stack[M.index]

  if apply_fn then
    apply_fn(theme)
  end

  vim.notify(string.format("Jumped to: %s (%d/%d)", theme, M.index, #M.stack), vim.log.levels.INFO)
  return theme
end

function M.stats()
  if #M.stack == 0 then
    return { total = 0, position = 0, can_undo = false, can_redo = false }
  end

  local counts = {}
  for _, theme in ipairs(M.stack) do
    counts[theme] = (counts[theme] or 0) + 1
  end

  local most_used = nil
  local max_count = 0
  for theme, count in pairs(counts) do
    if count > max_count then
      max_count = count
      most_used = theme
    end
  end

  return {
    total = #M.stack,
    position = M.index,
    can_undo = M.can_undo(),
    can_redo = M.can_redo(),
    unique_themes = vim.tbl_count(counts),
    most_used = most_used,
    most_used_count = max_count,
    recent = M.stack[#M.stack],
  }
end

function M.reset()
  M.stack = {}
  M.index = 0
  vim.notify("Theme history cleared", vim.log.levels.INFO)
end

function M.serialize()
  return {
    stack = vim.deepcopy(M.stack),
    index = M.index,
    max_size = M.max_size,
  }
end

function M.deserialize(data)
  if not data or type(data) ~= "table" then
    return
  end

  M.stack = data.stack or {}
  M.index = data.index or 0
  M.max_size = data.max_size or 50

  if M.index > #M.stack then
    M.index = #M.stack
  elseif M.index < 0 then
    M.index = 0
  end
end

function M.get_slice(count)
  count = count or 10
  local start_idx = math.max(1, #M.stack - count + 1)
  local slice = {}

  for i = start_idx, #M.stack do
    table.insert(slice, {
      index = i,
      theme = M.stack[i],
      is_current = i == M.index,
    })
  end

  return slice
end

return M
