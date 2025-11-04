local M = {}

M.path = vim.fn.stdpath("data") .. "/raphael/theme_history.lua"
M.limit = 13
M.history = {}
M.index = 0

function M.load()
  local f = io.open(M.path, "r")
  if f then
    local ok, data = pcall(loadfile, M.path)
    if ok and type(data) == "function" then
      local tbl = data()
      if type(tbl) == "table" then
        M.history = tbl.history or {}
        M.index = tbl.index or #M.history
      end
    end
    f:close()
  end
end

function M.save()
  local f = io.open(M.path, "w")
  if not f then
    vim.schedule(function()
      vim.notify("raphael: failed to save theme history", vim.log.levels.WARN)
    end)
    return
  end
  f:write("return " .. vim.inspect({ history = M.history, index = M.index }))
  f:close()
end

function M.add(theme)
  if not theme then
    return
  end

  while M.index < #M.history do
    table.remove(M.history)
  end

  for i = #M.history, 1, -1 do
    if M.history[i] == theme then
      table.remove(M.history, i)
    end
  end

  table.insert(M.history, theme)
  M.index = #M.history

  if #M.history > M.limit then
    table.remove(M.history, 1)
    M.index = M.index - 1
  end

  M.save()
end

function M.undo()
  if M.index > 1 then
    M.index = M.index - 1
    local theme = M.history[M.index]
    pcall(vim.cmd.colorscheme, theme)
    vim.notify(string.format("󰓕  Undo: %s (%d/%d)", theme, M.index, #M.history))
    M.save()
  else
    vim.notify("  No more themes to undo", vim.log.levels.INFO)
  end
end

function M.redo()
  if M.index < #M.history then
    M.index = M.index + 1
    local theme = M.history[M.index]
    pcall(vim.cmd.colorscheme, theme)
    vim.notify(string.format("󰓗  Redo: %s (%d/%d)", theme, M.index, #M.history))
    M.save()
  else
    vim.notify("  No more themes to redo", vim.log.levels.INFO)
  end
end

M.load()

return M
