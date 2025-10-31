-- raphael.nvim/plugin/raphael.lua
if vim.fn.has("nvim-0.9.0") == 0 then
	vim.api.nvim_err_writeln("raphael.nvim requires Neovim >= 0.9.0")
	return
end

-- Hook into session saving to export theme state
vim.api.nvim_create_autocmd("SessionWritePost", {
	callback = function()
		-- Get the session file path
		local session_file = vim.v.this_session
		if session_file and session_file ~= "" then
			local ok, raphael = pcall(require, "raphael")
			if ok and raphael.export_for_session then
				-- Read current session
				local f = io.open(session_file, "r")
				if not f then
					return
				end
				local content = f:read("*a")
				f:close()

				-- Append Raphael state if not already present
				if not content:match("g:raphael_session_theme") then
					local export = raphael.export_for_session()
					f = io.open(session_file, "a")
					if f then
						f:write(export)
						f:close()
					end
				end
			end
		end
	end,
})
