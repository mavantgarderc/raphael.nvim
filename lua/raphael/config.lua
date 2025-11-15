-- config.lua
local M = {}

M.defaults = {
  leader = "<leader>t",
  mappings = {
    picker = "p",
    next = ">",
    previous = "<",
    others = "/",
    auto = "a",
    refresh = "R",
    status = "s",
  },
  default_theme = "kanagawa-paper-ink",
  bookmark_group = true,
  recent_group = false,
  state_file = vim.fn.stdpath("data") .. "/raphael/state.json",
  theme_map = nil,
  filetype_themes = {},
  animate = { enabled = false, duration = 200, steps = 10 },
  sort_mode = "alpha",
  custom_sorts = {},
  theme_aliases = {},
  history_max_size = 13,

  sample_preview = {
    enabled = true,
    relative_size = 0.5,
    languages = nil,
  },

  on_apply = function(theme)
    vim.schedule(function()
      local ok, lualine = pcall(require, "lualine")
      if ok then
        local lualine_theme = "auto"
        local config = lualine.get_config()
        config.options = config.options or {}
        config.options.theme = lualine_theme
        lualine.setup(config)
      end
    end)
  end,

  enable_autocmds = true,
  enable_commands = true,
  enable_keymaps = true,
  enable_picker = true,
}

return M
