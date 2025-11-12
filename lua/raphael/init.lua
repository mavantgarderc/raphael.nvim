local M = {}

local core = require("raphael.core")
local config = require("raphael.config")

M.setup = core.setup
M.apply = core.apply
M.toggle_auto = core.toggle_auto
M.toggle_bookmark = core.toggle_bookmark
M.open_picker = core.open_picker
M.refresh_and_reload = core.refresh_and_reload
M.show_status = core.show_status
M.export_for_session = core.export_for_session
M.restore_from_session = core.restore_from_session
M.add_to_history = core.add_to_history

M.config = nil

function M.open_picker(opts)
  if not M.config or not M.config.enable_picker then
    vim.notify("raphael: picker disabled in config", vim.log.levels.WARN)
    return
  end
  local picker = require("raphael.picker")
  picker.open(core, opts)
end

function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", config.defaults, user_config or {})

  core.setup(M.config)

  if M.config.enable_autocmds then
    local autocmds = require("raphael.autocmds")
    autocmds.setup(M)
  end

  if M.config.enable_commands then
    local cmds = require("raphael.cmds")
    cmds.setup(M)
  end

  if M.config.enable_keymaps then
    local keymaps = require("raphael.keymaps")
    keymaps.setup(M)
  end
end

return M
