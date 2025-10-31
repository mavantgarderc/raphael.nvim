# raphael.nvim

A Neovim theme manager plugin for easy switching, configuring, and auto-applying colorschemes.

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
luaopts = {
  leader = "<leader>t",
  mappings = {
    next = ">",
    previous = "<",
    random = "r",
  },
  default_theme = "kanagawa-paper-ink",
  theme_map = {  -- Grouped or flat list of themes
    pantheon = { ... },
    kanagawa = { "kanagawa-paper-ink" },
    -- ...
  },
  filetype_themes = {  -- Auto-apply per filetype
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
`<leader>th`: Show help

Inside picker:

`<CR>`: Apply theme
`/`: Search
`b`: Toggle bookmark
`c`: Collapse/expand group
`q` / ``<Esc>`: Cancel and revert

### Commands

`:RaphaelPicker`: Open configured picker
`:RaphaelPickerAll`: Open other themes picker
`:RaphaelApply <theme>`: Apply a theme
`:RaphaelToggleAuto`: Toggle auto-apply
`:RaphaelRefresh`: Refresh and reload
`:RaphaelStatus`: Show status
`:RaphaelHelp`: Show help

