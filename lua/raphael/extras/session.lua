local M = {}

function M.export(core)
  if not core or type(core.export_for_session) ~= "function" then
    return ""
  end
  return core.export_for_session()
end

function M.setup_autocmd(core)
  if not core or type(core.restore_from_session) ~= "function" then
    return
  end

  vim.api.nvim_create_autocmd("SessionLoadPost", {
    callback = function()
      core.restore_from_session()
    end,
  })
end

return M
