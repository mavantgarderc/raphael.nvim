-- tests/minimal_init.lua
-- Minimal init file for testing raphael.nvim

-- Add the current directory to runtime path so we can require the modules
vim.cmd("set rtp+=" .. vim.fn.getcwd())

-- Setup plenary if available
local plenary_avail = pcall(require, "plenary")
if plenary_avail then
  require("plenary.test_harness"):setup()
end
