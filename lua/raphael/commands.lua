local M = {}

function M.setup(core)
  vim.api.nvim_create_user_command("RaphaelToggle", function()
    core.toggle()
  end, {})
  vim.api.nvim_create_user_command("RaphaelPicker", function()
    core.pick()
  end, {})
  vim.api.nvim_create_user_command("RaphaelApply", function(opts)
    core.apply(opts.args)
  end, {
    nargs = 1,
    complete = function()
      return require("raphael.util").flatten(require("raphael.themes").theme_map)
    end,
  })
end

return M
