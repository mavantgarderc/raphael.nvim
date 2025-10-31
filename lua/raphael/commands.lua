-- lua/raphael/commands.lua
local M = {}

function M.setup(core)
	vim.api.nvim_create_user_command("RaphaelToggleAuto", function()
		core.toggle_auto()
	end, { desc = "Toggle auto-apply by filetype" })

	vim.api.nvim_create_user_command("RaphaelPicker", function()
		core.open_picker({ only_configured = true })
	end, { desc = "Open theme picker (configured themes)" })

	vim.api.nvim_create_user_command("RaphaelPickerAll", function()
		core.open_picker({ exclude_configured = true })
	end, { desc = "Open theme picker (all except configured)" })

	vim.api.nvim_create_user_command("RaphaelApply", function(opts)
		core.apply(opts.args)
	end, {
		nargs = 1,
		complete = function()
			local themes = require("raphael.themes")
			return themes.get_all_themes()
		end,
		desc = "Apply a theme by name",
	})

	vim.api.nvim_create_user_command("RaphaelRefresh", function()
		core.refresh_and_reload()
	end, { desc = "Refresh theme list and reload current" })

	vim.api.nvim_create_user_command("RaphaelStatus", function()
		core.show_status()
	end, { desc = "Show current theme status" })

	vim.api.nvim_create_user_command("RaphaelHelp", function()
		core.show_help()
	end, { desc = "Show Raphael help" })
end

return M
