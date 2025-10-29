local M = {}

local colors = require("raphael.colors")

M.theme_map = colors.theme_map
M.filetype_themes = colors.filetype_themes
M.toml_map = colors.toml_map
M.installed = {}

function M.merge_user_config(cfg)
  if cfg.filetype_themes then
    for ft, theme in pairs(cfg.filetype_themes) do
      M.filetype_themes[ft] = theme
    end
  end
end

function M.refresh()
  M.installed = {}
  local rtp = vim.api.nvim_list_runtime_paths()
  for _, p in ipairs(rtp) do
    local glob1 = vim.fn.globpath(p, "colors/*.vim", 0, 1)
    local glob2 = vim.fn.globpath(p, "colors/*.lua", 0, 1)
    for _, f in ipairs(vim.tbl_flatten({ glob1, glob2 })) do
      M.installed[vim.fn.fnamemodify(f, ":t:r")] = true
    end
  end
end

function M.is_available(theme)
  return M.installed[theme] == true
end

return M
