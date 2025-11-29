local M = {}

M.theme_map = {}

M.filetype_themes = {}

M.installed = {}

function M.refresh()
  M.installed = {}

  local rtp = vim.api.nvim_list_runtime_paths()
  for _, p in ipairs(rtp) do
    local vim_files = vim.fn.globpath(p, "colors/*.vim", false, true)
    local lua_files = vim.fn.globpath(p, "colors/*.lua", false, true)
    local all = vim.list_extend(vim_files, lua_files)

    for _, f in ipairs(all) do
      local theme_name = vim.fn.fnamemodify(f, ":t:r")
      M.installed[theme_name] = true
    end
  end
end

function M.is_available(theme)
  return M.installed[theme] == true
end

local function collect_themes(node, acc)
  local t = type(node)
  if t == "string" then
    table.insert(acc, node)
    return
  end

  if t ~= "table" then
    return
  end

  if vim.islist(node) then
    for _, v in ipairs(node) do
      collect_themes(v, acc)
    end
    return
  end

  for _, v in pairs(node) do
    collect_themes(v, acc)
  end
end

function M.get_all_themes()
  local acc = {}

  if not M.theme_map or next(M.theme_map) == nil then
    for name, _ in pairs(M.installed) do
      table.insert(acc, name)
    end
    table.sort(acc)
    return acc
  end

  collect_themes(M.theme_map, acc)
  return acc
end

return M
