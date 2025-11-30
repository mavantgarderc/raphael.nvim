# raphael.nvim

A Neovim theme manager plugin for easy switching, configuring, and auto-applying colorschemes.

Among La Italia's finest painters, Raphael stood out for his harmony in color — just like your interface should.

## Features

- **Theme Picker**: Interactive floating window to browse and preview configured or other installed themes.

- **Grouped Themes**: Organize themes into groups (e.g., "justice-league", "lantern-corps") with collapse/expand functionality.  
  Supports **nested groups** in `theme_map` (tables inside tables), with per‑group cursor memory.

- **Auto-Apply by Filetype & Project**:
  - Automatically switch themes based on:
    - Buffer **filetype** via `filetype_themes`.
    - **Project root** via `project_themes` (match by absolute path prefix; longest prefix wins).
  - Priority flags:
    - `project_overrides_filetype = true` → project wins when both match.
    - `filetype_overrides_project = true` → filetype wins when both match.
  - Integrates with **oil.nvim** (uses `oil.get_current_dir()` for project detection).  
    Auto-applied themes are **temporary** and do not participate in manual history/undo.

- **Persistence**: Saves manually selected themes across sessions:
  - `current`, `saved`, `previous` themes
  - `bookmarks`, `history`, `usage`, `sort_mode`, `collapsed` state
  - `quick_slots` (0–9 favorites)
  - `current_profile` (active profile)
  - when `profile_scoped_state = true`, bookmarks & quick_slots are stored per profile scope (with a `__global` bucket)  
    All stored in a single JSON file:
    `stdpath("data") .. "/raphael/state.json"`.

- **Bookmarks and History**: Bookmark favorites and track recent themes.
  - Dedicated **Bookmarks** and **Recent** sections at the top of the picker.
  - Full undo/redo stack with `u`, `<C-r>`, `H`, `J`, `T` in the picker and `:RaphaelUndo` / `:RaphaelRedo` commands.

- **Profiles (work / night / presentation)**:
  - Define multiple theme “profiles” as partial configs:
    - `profiles = { work = { default_theme = "..." }, night = { ... }, ... }`
    - `current_profile = "work"` at startup.
  - Switch with `:RaphaelProfile work`, `:RaphaelProfile night`, `:RaphaelProfile base` (clear profile).
  - Optionally scope bookmarks and quick slots per profile with `profile_scoped_state = true`.

- **Quick Favorite Slots (0–9)**:
  - In picker:
    - `m0`..`m9` → assign current theme to quick slot `0`..`9`.
    - `0`..`9` → jump to that slot’s theme in the picker and preview it.
  - Stored in state as `quick_slots = { ["1"] = "kanagawa-paper-edo", ... }`.

- **Compare with Current**:
  - In picker:
    - `C` → enter compare mode between:
      - Base = current active theme.
      - Candidate = theme under cursor.
    - Move with `j`/`k` to change candidate.
    - Press `C` again to flip between **base ⇄ candidate** in the preview.

- **Preview Palette**: Visual color blocks for key highlight groups during selection.
  - A top mini-bar of colored blocks representing `Normal`, `Comment`, `String`, etc.

- **Sample Code Preview**: Optional right-side floating window showing code samples in multiple languages (Lua, Python, JS, TS, Rust, Go, Ruby, Shell), updating as you move in the picker.

- **Keymaps and Commands**: Leader-based shortcuts and user commands for management.

- **Session Support**: Integrates with session managers for theme restoration via helpers like `raphael.extras.session`.

- **Configurable Icons**: All icons used in the picker (bookmarks, group arrows, history markers, etc.) are configurable via `opts.icons` (see below).

---

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

---

## Configuration

Configure in your plugin spec's opts table. Examples below:

```lua
local raphael = require("raphael")

return {
  "mavantgarderc/raphael.nvim",

  keys = {
    { "<leader>tp", raphael.open_picker,        desc = "Raphael: Configured themes" },
    {
      "<leader>t/",
      function() raphael.open_picker({ exclude_configured = true }) end,
      desc = "Raphael: All other themes",
    },
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

    -- Match by directory prefix (longest prefix wins).
    -- Use absolute paths or paths with ~; they’re normalized.
    project_themes = {
      -- Example:
      ["~/projects/work"]      = "kanagawa-paper-edo",
      ["~/projects/dc-themes"] = "kanagawa-paper-sunset",

      -- e.g. your dotfiles repo:
      ["~/dotfiles"] = "detox-ink",
    },

    -- Priority when both a project and a filetype mapping match:
    --   project_overrides_filetype = true  → project wins
    --   filetype_overrides_project = true  → filetype wins
    project_overrides_filetype = true,
    filetype_overrides_project = false,

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

    profiles = {
      work = {
        default_theme = "kanagawa-paper-ink",
        -- you can also override filetype_themes/project_themes per profile
      },
      night = {
        default_theme = "detox-ink",
      },
      presentation = {
        default_theme = "kanagawa-paper-obsidian",
      },
    },

    -- Active profile at startup (or nil for base config)
    current_profile = "work",

    -- If true, bookmarks & quick_slots are stored per-profile (with a __global fallback)
    profile_scoped_state = false,

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
          local cfg = lualine.get_config()
          cfg.options = cfg.options or {}
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

---

## Keymaps

### Global (normal mode, with `leader = "<leader>t"`)

- `<leader>tp`: Open picker for configured themes
- `<leader>t/`: Open picker for other installed themes
- `<leader>ta`: Toggle auto-apply
- `<leader>tR`: Refresh themes and reload current
- `<leader>ts`: Show status
- `<leader>t<` / `<leader>t>`: Previous / next theme (via `mappings.previous` / `mappings.next`)

### Inside picker

#### Core actions

- `<CR>`: Select theme
- `q` / `<Esc>`: Quit (revert theme)
- `/`: Search themes
- `a`: Clear search / show all themes
- `b`: Toggle bookmark
- `c`: Collapse/expand group
- `s`: Cycle sort mode
- `S`: Toggle sorting on/off
- `R`: Toggle reverse sorting (descending)

#### Navigation & sections

- `j` / `k`: Navigate (wraps around)
- `<C-j>` / `<C-k>`: Jump to next/prev group header (wraps)
- `<C-l>` / `<C-h>`: Jump into / out of group (header/child)
- `[g` / `]g`: Jump to prev/next group header (wraps)
- `gg` / `G`: Go to top / bottom
- `<C-u>` / `<C-d>`: Half-page up/down
- `zt` / `zz` / `zb`: Scroll current line to top/center/bottom
- `ga`: Jump to first theme (All)
- `gb`: Jump to Bookmarks section
- `gr`: Jump to Recent section
- `[b` / `]b`: Jump to prev/next bookmark (skips Bookmark group section)
- `[r` / `]r`: Jump to prev/next history state (skips Recent group section)

#### History & random

- `u`: Undo theme change
- `<C-r>`: Redo theme change
- `H`: Show full history
- `J`: Jump to a history position
- `T`: Show quick history stats
- `r`: Apply random theme

#### Preview & compare

- `i`: Show code sample preview / iterate languages forward
- `I`: Iterate languages backward
- `C`: **Compare candidate with current theme** in preview:
  - First `C`: base = current active theme, candidate = line under cursor.
  - Move with `j`/`k` to change candidate.
  - Further `C`: toggle between showing base ⇄ candidate.

#### Quick favorite slots

- `m0`..`m9`: Assign current theme to quick slot 0..9.
- `0`..`9`: Jump to that slot’s theme in the picker and preview it.

#### Help

- `?`: Show this help.

---

## Commands

- `:RaphaelPicker`
  Open picker (configured themes).

- `:RaphaelPickerAll`
  Open picker (all except configured).

- `:RaphaelApply {theme}`
  Apply a theme by name (supports aliases).

- `:RaphaelToggleAuto`
  Toggle auto-apply by filetype/project.

- `:RaphaelRefresh`
  Refresh theme list and reload current.

- `:RaphaelStatus`
  Show current theme status (includes profile name if any).

- `:RaphaelHelp`
  Show Raphael help.

- `:RaphaelHistory`
  Show full theme history.

- `:RaphaelUndo` / `:RaphaelRedo`
  Undo / redo last theme change.

- `:RaphaelRandom`
  Apply a random theme.

- `:RaphaelBookmarkToggle`
  Toggle bookmark for the theme under the cursor (opens picker if needed).

- `:RaphaelProfile [name]`
  Manage profiles:
  - `:RaphaelProfile` → list all profiles and mark current with `*`.
  - `:RaphaelProfile work` / `night` / `presentation` → switch to that profile.
  - `:RaphaelProfile base` → clear profile (use base config only).

---

## Picker internals (module paths)

```vim
:lua require("raphael.picker.ui").toggle_debug()
:lua print(vim.inspect(require("raphael.picker.ui").get_cache_stats()))
```
