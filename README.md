# raphael.nvim

A Neovim theme manager plugin for easy switching, configuring, and auto-applying colorschemes.

Among La Italia's finest painters, Raphael stood out for his harmony in color — just like your interface should.

## Features

- **Theme Picker**: Interactive floating window to browse and preview configured or other installed themes.

- **Grouped Themes**: Organize themes into groups (e.g., "justice-league", "lantern-corps") with collapse/expand functionality.

- **Auto-Apply by Filetype**: Automatically switch themes based on buffer filetype (e.g., "kanagawa-paper-ink" for Lua).

- **Persistence**: Saves manually selected themes across sessions; auto-applies are temporary.

- **Bookmarks and History**: Bookmark favorites and track recent themes.

- **Preview Palette**: Visual color blocks for key highlight groups during selection.

- **Keymaps and Commands**: Leader-based shortcuts and user commands for management.

- **Session Support**: Integrates with session managers for theme restoration.

## Installation

Install via your preferred plugin manager. Example with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
-- ~/.config/nvim/lua/plugins/raphael.lua
return {
  "mavantgarderc/raphael.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    require("raphael").setup({
      -- Your config here
    })
  end,
}
```

### Configuration

Configure in your plugin spec's opts table. Defaults shown below:

```lua
  -- Method I for keymaps
  keys = {
    { "<leader>tp", function() raphael.open_picker({ only_configured = true }) end, desc = "Raphael: Configured themes", },
    { "<leader>t/", function() raphael.open_picker({ exclude_configured = true }) end, desc = "Raphael: All other themes", },
    { "<leader>ta", function() raphael.toggle_auto() end, desc = "Raphael: Toggle auto-apply", },
    { "<leader>tR", function() raphael.refresh_and_reload() end, desc = "Raphael: Refresh themes", },
    { "<leader>ts", function() raphael.show_status() end, desc = "Raphael: Show status", },
  },
  -- Method II for keymaps
  keys = {
    { "<leader>tp", raphael.open_picker, desc = "Raphael: Configured themes" },
    { "<leader>t/", raphael.open_picker, desc = "Raphael: All other themes" },
    { "<leader>ta", raphael.toggle_auto, desc = "Raphael: Toggle auto-apply" },
    { "<leader>tR", raphael.refresh_and_reload, desc = "Raphael: Refresh themes" },
    { "<leader>ts", raphael.show_status, desc = "Raphael: Show status" },
  },

  opts = {
    -- Method III for keymaps
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

    theme_aliases = {
      ["evergardern-fall"] = "Garden-Fall",
    },

    default_theme = "kanagawa-paper-ink",
    theme_map = {  -- Grouped or flat list of themes
      pantheon = { ... },
      kanagawa = { "kanagawa-paper-ink" },
      -- ...
    },
    filetype_themes = {  -- Auto-apply per filetype
      -- extension/filetype = "theme"
      lua = "kanagawa-paper-ink",
      python = "kanagawa-wave",
      -- ...
    },
  }
```

### Keymaps

`<leader>tp`: Open picker for configured themes

`<leader>t/`: Open picker for other installed themes

`<leader>ta`: Toggle auto-apply

`<leader>tR`: Refresh themes and reload current

`<leader>ts`: Show status

`<leader>t<`: Previous theme

`<leader>t>`: Next theme

Inside picker:

`<CR>`: Apply theme

`/`: Search

`b`: Toggle bookmark

`c`: Collapse/expand group

`q`/`<Esc>`: Cancel and revert

`<C-j>`/`<C-k>` & `[g`/`]g`: Next/previous header group

`[b`/`]b`: Jump to prev/next bookmark

`[r`/`]r`: Jump to prev/next history state

`i`/`I`: Iterate through inline sample codes

`u`/`<C-r>`: Undo/redo theme change

`s`: Change sort of theme list

`S`: Toggle sorting on/off

`R`: Toggle reverse sorting (descending)

`J`: Jump to history position

`T`: Show quick stats

`r`: Random theme

`?`: Show help

### Commands

`:RaphaelPicker`: Open configured picker

`:RaphaelPickerAll`: Open other themes picker

`:RaphaelApply <theme>`: Apply a theme

`:RaphaelToggleAuto`: Toggle auto-apply

`:RaphaelRefresh`: Refresh and reload

`:RaphaelStatus`: Show status

`:RaphaelHelp`: Show help

`:lua require('raphael.picker').toggle_animations()`: Animation toggle

`:lua require('raphael.picker').toggle_debug()`: Debug mode toggle

`:lua print(vim.inspect(require('raphael.picker').get_cache_stats()))`: Cache Statistics
