if vim.fn.has("nvim-0.9.0") == 0 then
  vim.api.nvim_err_writeln("raphael.nvim requires Neovim >= 0.9.0")
  return
end
