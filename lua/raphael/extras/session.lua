-- lua/raphael/extras/session.lua
-- Session integration helpers for raphael.nvim.
--
-- This module is optional but provides a clean way to:
--   - Generate a snippet to persist the current Raphael theme into session files.
--   - Hook SessionLoadPost to restore that theme automatically.
--
-- It relies only on the public core API:
--   core.export_for_session()
--   core.restore_from_session()

local M = {}

--- Generate Vimscript suitable for persisting Raphael's theme into a session.
---
--- Typical usage (from a session manager):
---   local session = require("raphael.extras.session")
---   local core    = require("raphael.core")
---   local snippet = session.export(core)
---   -- write snippet into the session file
---
--- The returned string:
---   - sets g:raphael_session_theme
---   - sets g:raphael_session_saved
---   - sets g:raphael_session_auto
---
--- If `core` does not implement export_for_session(), returns an empty string.
---
---@param core table  # usually require("raphael.core")
---@return string     # Vimscript snippet, or empty string if core missing
function M.export(core)
  if not core or type(core.export_for_session) ~= "function" then
    return ""
  end
  return core.export_for_session()
end

--- Setup a SessionLoadPost autocmd that calls core.restore_from_session().
---
--- This is a convenience helper for users who want automatic restoration
--- of the last theme when a session is loaded, but do not use an
--- external session manager that handles this explicitly.
---
--- Typical usage:
---   local core    = require("raphael.core")
---   local session = require("raphael.extras.session")
---   session.setup_autocmd(core)
---
---@param core table  # usually require("raphael.core")
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
