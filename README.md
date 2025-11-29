# raphael.nvim

A Neovim theme manager plugin for easy switching, configuring, and auto-applying colorschemes.

Among La Italia's finest painters, Raphael stood out for his harmony in color — just like your interface should.

## Features

- **Theme Picker**: Interactive floating window to browse and preview configured or other installed themes.

- **Grouped Themes**: Organize themes into groups (e.g., "justice-league", "lantern-corps") with collapse/expand functionality.  
  Supports **nested groups** in `theme_map` (tables inside tables), with per‑group cursor memory.

- **Auto-Apply by Filetype**: Automatically switch themes based on buffer filetype (e.g., "kanagawa-paper-ink" for Lua).  
  Auto-applied themes are **temporary** and do not participate in manual history/undo.

- **Persistence**: Saves manually selected themes across sessions:
  - `current`, `saved`, `previous` themes
  - `bookmarks`, `history`, `usage`, `sort_mode`, `collapsed` state  
    All stored in a single JSON file:
    `stdpath("data") .. "/raphael/state.json"`.

- **Bookmarks and History**: Bookmark favorites and track recent themes.
  - Dedicated **Bookmarks** and **Recent** sections at the top of the picker.
  - Full undo/redo stack with `u`, `<C-r>`, `H`, `J`, `T` in the picker and `:RaphaelUndo` / `:RaphaelRedo` commands.

- **Preview Palette**: Visual color blocks for key highlight groups during selection.
  - A top mini-bar of colored blocks representing `Normal`, `Comment`, `String`, etc.

- **Sample Code Preview**: Optional right-side floating window showing code samples in multiple languages (Lua, Python, JS, TS, Rust, Go, Ruby, Shell), updating as you move in the picker.

- **Keymaps and Commands**: Leader-based shortcuts and user commands for management.

- **Session Support**: Integrates with session managers for theme restoration via helpers like `raphael.extras.session`.

- **Configurable Icons**: All icons used in the picker (bookmarks, group arrows, history markers, etc.) are configurable via `opts.icons` (see below).

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

Configure in your plugin spec's opts table. Examples below:

```lua
local raphael = require("raphael")

return {
  "mavantgarderc/raphael.nvim",

  keys = {
    { "<leader>tp", raphael.open_picker,        desc = "Raphael: Configured themes" },
    { "<leader>t/", function() raphael.open_picker({ exclude_configured = true }) end, desc = "Raphael: All other themes" },
    { "<leader>ta", raphael.toggle_auto,        desc = "Raphael: Toggle auto-apply" },
    { "<leader>tR", raphael.refresh_and_reload, desc = "Raphael: Refresh themes" },
    { "<leader>ts", raphael.show_status,        desc = "Raphael: Show status" },
  },

  opts = {
    leader = "<leader>t",
    mappings = {
      picker   = "p",
      next     = ">",
      previous = "<",
      others   = "/",
      auto     = "a",
      refresh  = "R",
      status   = "s",
      -- ...
    },

    theme_aliases = {
      ["evergardern-fall"] = "Garden-Fall",
    },

    default_theme = "kanagawa-paper-ink",

    -- Grouped or flat or nested theme_map
    theme_map = {
      pantheon = { "justice-league-batman", "justice-league-superman" },
      kanagawa = { "kanagawa-paper-ink" },

      prism = {
        emotional_entities = {
          "emotional-entities-entity",
          "emotional-entities-umbrax",
        },
        tmnt = {
          "tmnt-raphael",
          "tmnt-leonardo",
        },
      },
    },

    -- Auto-apply per filetype
    filetype_themes = {
      lua    = "kanagawa-paper-ink",
      python = "kanagawa-wave",
      -- ...
    },

    -- Optional right-side code sample preview
    sample_preview = {
      enabled       = true,
      relative_size = 0.5,      -- fraction of picker width (0.1–1.0)
      languages     = nil,      -- or { "lua", "python", "rust" } to restrict
    },

    -- Sort modes: "alpha" | "recent" | "usage" | custom
    sort_mode   = "alpha",
    custom_sorts = {
      -- my_sort = function(a, b) return a < b end
    },

    history_max_size = 13,

    -- Icon overrides (all keys optional)
    icons = {
      -- sections
      -- HEADER           = "🎨 Colorschemes",
      -- RECENT_HEADER    = "⏱  Recent",
      -- BOOKMARKS_HEADER = "★  Bookmarks",

      -- markers
      -- BOOKMARK    = "★ ",
      -- CURRENT_ON  = "● ",
      -- CURRENT_OFF = "○ ",
      -- WARN        = "⚠ ",

      -- groups
      -- GROUP_EXPANDED  = "▾ ",
      -- GROUP_COLLAPSED = "▸ ",
    },

    -- on_apply hook (e.g. refresh lualine)
    on_apply = function(theme)
      vim.schedule(function()
        local ok, lualine = pcall(require, "lualine")
        if ok then
          local cfg        = lualine.get_config()
          cfg.options      = cfg.options or {}
          cfg.options.theme = "auto"
          lualine.setup(cfg)
        end
      end)
    end,

    enable_autocmds = true,
    enable_commands = true,
    enable_keymaps  = true,
    enable_picker   = true,
  },
}
```

### Keymaps

Global (normal mode, with `leader = "<leader>t"`):

- `<leader>tp`: Open picker for configured themes
- `<leader>t/`: Open picker for other installed themes
- `<leader>ta`: Toggle auto-apply
- `<leader>tR`: Refresh themes and reload current
- `<leader>ts`: Show status
- `<leader>t<`: Previous theme
- `<leader>t>`: Next theme

Inside picker:

- `<CR>`: Apply theme
- `/`: Search
- `b`: Toggle bookmark
- `c`: Collapse/expand group
- `q` / `<Esc>`: Cancel and revert to previous theme

Navigation & sections:

- `<C-j>` / `<C-k>` & `[g` / `]g`: Next/previous header group
- `[b` / `]b`: Jump to prev/next bookmark (skips bookmarks section when needed)
- `[r` / `]r`: Jump to prev/next history state (skips recent section)
- `gg` / `G`: Top / bottom
- `<C-u>` / `<C-d>`: Half page up/down
- `zt` / `zz` / `zb`: Scroll current line to top/center/bottom
- `ga`: Jump to first theme

History & random:

- `u` / `<C-r>`: Undo/redo theme change
- `H`: Show history snapshot
- `J`: Jump to history position
- `T`: Show quick stats
- `r`: Random theme

Preview:

- `i` / `I`: Toggle and iterate inline code sample languages

Misc:

- `?`: Show help

### Commands

- `:RaphaelPicker`: Open configured picker
- `:RaphaelPickerAll`: Open other themes picker
- `:RaphaelApply <theme>`: Apply a theme (supports aliases)
- `:RaphaelToggleAuto`: Toggle auto-apply
- `:RaphaelRefresh`: Refresh and reload
- `:RaphaelStatus`: Show status
- `:RaphaelHelp`: Show help
- `:RaphaelHistory`: Show theme history
- `:RaphaelUndo`: Undo last theme change
- `:RaphaelRedo`: Redo last undone theme change
- `:RaphaelRandom`: Apply a random theme

Picker internals (new module paths):

```vim
:lua require("raphael.picker.ui").toggle_animations()
:lua require("raphael.picker.ui").toggle_debug()
:lua print(vim.inspect(require("raphael.picker.ui").get_cache_stats()))
```
