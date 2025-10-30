-- lua/raphael/themes.lua
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
    for _, f in ipairs(vim.tbl_extend("force", vim_files, lua_files)) do
      local theme_name = vim.fn.fnamemodify(f, ":t:r")
      M.installed[theme_name] = true
    end
  end
end

function M.is_available(theme)
  return M.installed[theme] == true
end

function M.get_all_themes()
  local all = {}
  if vim.tbl_islist(M.theme_map) then
    -- Flat list
    all = vim.deepcopy(M.theme_map)
  else
    -- Grouped
    for _, group_themes in pairs(M.theme_map) do
      vim.list_extend(all, group_themes)
    end
  end
  return all
end

return M
