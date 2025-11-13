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
  sample_preview = { enabled = true, relative_size = 0.5 },

  enable_autocmds = true,
  enable_commands = true,
  enable_keymaps = true,
  enable_picker = true,
}

return M
