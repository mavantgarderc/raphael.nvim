-- raphael.nvim/plugin/raphael.lua
if vim.fn.has("nvim-0.9.0") == 0 then
  vim.api.nvim_err_writeln("raphael.nvim requires Neovim >= 0.9.0")
  return
end

-- Defer loading until after plugin initialization
vim.schedule(function()
  local ok, raphael = pcall(require, "raphael")
  if ok and raphael.state and raphael.state.current then
    local themes = require("raphael.themes")
    if themes.is_available(raphael.state.current) then
      pcall(vim.cmd.colorscheme, raphael.state.current)
    end
  end
end)
