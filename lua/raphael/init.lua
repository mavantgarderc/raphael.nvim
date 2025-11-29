local M = {}

local core = require("raphael.core")
local config = require("raphael.config")

M.config = nil

function M.apply(theme, from_manual)
  return core.apply(theme, from_manual)
end

function M.toggle_auto()
  return core.toggle_auto()
end

function M.toggle_bookmark(theme)
  return core.toggle_bookmark(theme)
end

function M.refresh_and_reload()
  return core.refresh_and_reload()
end

function M.show_status()
  return core.show_status()
end

function M.export_for_session()
  return core.export_for_session()
end

function M.restore_from_session()
  return core.restore_from_session()
end

function M.add_to_history(theme)
  return core.add_to_history(theme)
end

function M.open_picker(opts)
  if not M.config or not M.config.enable_picker then
    vim.notify("raphael: picker disabled in config", vim.log.levels.WARN)
    return
  end
  return core.open_picker(opts or {})
end

function M.setup(user_config)
  M.config = config.validate(user_config or {})

  core.setup(M.config)

  if M.config.enable_autocmds ~= false then
    local autocmds = require("raphael.core.autocmds")
    autocmds.setup(core)
  end

  if M.config.enable_commands ~= false then
    local cmds = require("raphael.core.cmds")
    cmds.setup(core)
  end

  if M.config.enable_keymaps ~= false then
    local keymaps = require("raphael.core.keymaps_global")
    keymaps.setup(core)
  end
end

return M
