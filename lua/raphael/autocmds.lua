local themes = require("raphael.themes")

local M = {}

function M.setup(core)
  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function()
      if not core.state.enabled then
        return
      end
      local ft = vim.bo.filetype
      local theme = themes.filetype_themes[ft]
      if theme and themes.is_available(theme) then
        core.apply(theme)
      else
        core.apply("kanagawa-paper-ink")
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function()
      vim.api.nvim_set_hl(0, "LspReferenceText", { link = "CursorLine" })
      vim.api.nvim_set_hl(0, "LspReferenceRead", { link = "CursorLine" })
      vim.api.nvim_set_hl(0, "LspReferenceWrite", { link = "Visual" })
    end,
  })
end

return M
