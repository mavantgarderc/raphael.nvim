local M = {}

local map = vim.keymap.set

function M.setup(core)
  local leader = "<leader>t"

  map("n", leader .. "p", function()
    core.pick()
  end, { desc = "Raphael picker" })
  map("n", leader .. "r", function()
    vim.notify("Next theme TBD")
  end, { desc = "Next theme" })
  map("n", leader .. "R", function()
    vim.notify("Previous theme TBD")
  end, { desc = "Previous theme" })
  map("n", leader .. "r", function()
    vim.notify("Random theme TBD")
  end, { desc = "Random theme" })
end

return M
