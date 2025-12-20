return {
  "mavantgarderc/raphael.nvim",
  lazy = false,
  priority = 1000,

  dependencies = {
    "mavantgarderc/prismpunk.nvim",
  },

  opts = {
    leader = "<leader>t",

    mappings = {
      picker = "p",
      others = "/",
      auto = "a",
      refresh = "R",
      status = "s",
      random = "r",
      next = ">",
      previous = "<",
    },

    default_theme = "kanagawa-paper-edo",

    bookmark_group = true,
    recent_group = true,

    theme_map = {
      ["New Gods"] = {
        "apokolips-yugakhan",
        "new-genesis-big-barda",
      },

      ["Super Family"] = {
        "super-family-clark-kent",
        "super-family-martha-kent",
        "super-family-lucy-lane",
        "super-family-superman-kingdomcome",
      },

      ["Emotional Entities"] = {
        "emotional-entities-entity",
        "emotional-entities-umbrax",
      },

      ["Watchmen"] = {
        "watchmen-ozymandias",
      },

      ["Injustice League"] = {
        "injustice-league-brainiac",
        "injustice-league-twoface",
        "injustice-league-deathstroke",
      },

      ["Justice League"] = {
        "justice-league-cyborg",
        "justice-league-mera",
      },

      ["Arkham Asylum"] = {
        "arkham-asylum-deathshot",
        "arkham-asylum-white-knight",
      },

      ["Kanagawa Paper"] = {
        "kanagawa-paper-crimsonnight",
        "kanagawa-paper-eclipse",
        "kanagawa-paper-edo",
        "kanagawa-paper-obsidian",
      },

      ["TMNT"] = {
        "tmnt-last-ronin",
        "tmnt-raphael",
      },
    },

    filetype_themes = {
      lua = "kanagawa-paper-edo",
      vim = "kanagawa-paper-edo",
      markdown = "tmnt-last-ronin",
      text = "tmnt-last-ronin",

      javascript = "super-family-clark-kent",
      typescript = "super-family-clark-kent",
      tsx = "super-family-clark-kent",

      rust = "kanagawa-paper-crimsonnight",
      go = "kanagawa-paper-eclipse",
      python = "justice-league-mera",
      sh = "arkham-asylum-white-knight",
    },

    project_themes = {
      ["~/**/nvim-plugins/"] = "kanagawa-paper-edo",
      ["~/**/nvim-plugins/prismpunk.nvim/"] = "tmnt-raphael",
      ["~/dotfiles"] = "kanagawa-paper-obsidian",
      ["~/.config/nvim/"] = "kanagawa-paper-nightfall",
    },

    filetype_overrides_project = false,
    project_overrides_filetype = true,

    profiles = {
      work = {
        default_theme = "kanagawa-paper-edo",
        filetype_themes = {
          markdown = "tmnt-last-ronin",
          lua = "kanagawa-paper-edo",
        },
      },

      night = {
        default_theme = "tmnt-last-ronin",
        filetype_themes = {
          markdown = "tmnt-last-ronin",
          lua = "kanagawa-paper-obsidian",
        },
        sample_preview = {
          enabled = false,
          relative_size = 0.4,
        },
      },

      hero = {
        default_theme = "super-family-superman-kingdomcome",
        filetype_themes = {
          javascript = "super-family-clark-kent",
          typescript = "super-family-clark-kent",
          rust = "justice-league-cyborg",
        },
        sample_preview = {
          enabled = true,
          relative_size = 0.55,
          languages = { "lua", "typescript", "rust" },
        },
      },

      villain = {
        default_theme = "watchmen-ozymandias",
        filetype_themes = {
          lua = "injustice-league-brainiac",
          rust = "injustice-league-deathstroke",
        },
        sample_preview = {
          enabled = true,
          relative_size = 0.5,
          languages = { "lua", "python" },
        },
      },
    },

    current_profile = "work",
    profile_scoped_state = true,

    sort_mode = "alpha",

    custom_sorts = {
      kanagawa_first = function(a, b)
        local function score(name)
          if name:match("^kanagawa%-paper") then
            return 0
          end
          if name:match("^super%-family") then
            return 1
          end
          if name:match("^justice%-league") then
            return 2
          end
          if name:match("^injustice%-league") then
            return 3
          end
          return 4
        end
        local sa, sb = score(a), score(b)
        if sa ~= sb then
          return sa < sb
        end
        return a < b
      end,
    },

    theme_aliases = {
      workday = "kanagawa-paper-edo",
      late_night = "tmnt-last-ronin",
      coding_super = "super-family-clark-kent",
      coding_villain = "injustice-league-brainiac",
      tmnt = "tmnt-raphael",
    },

    history_max_size = 20,

    sample_preview = {
      enabled = true,
      relative_size = 0.45,
      languages = { "lua", "typescript", "rust", "vim" },
    },

    icons = {
      HEADER = "Colorschemes",
      RECENT_HEADER = "Recent",
      BOOKMARKS_HEADER = "Bookmarks",
    },

    on_apply = function()
      vim.schedule(function()
        local ok, lualine = pcall(require, "lualine")
        if not ok then
          return
        end

        local cfg = lualine.get_config()
        cfg.options = cfg.options or {}
        cfg.options.theme = "auto"
        lualine.setup(cfg)
      end)
    end,

    enable_autocmds = true,
    enable_commands = true,
    enable_keymaps = false,
    enable_picker = true,
  },

  keys = function(_, opts)
    local leader = (opts and opts.leader) or "<leader>t"
    local m = (opts and opts.mappings) or {}
    local raphael = require("raphael")

    local function map(suffix, fn, desc)
      return { leader .. suffix, fn, desc = "Raphael: " .. desc }
    end

    return {
      map(m.picker or "p", function()
        raphael.open_picker()
      end, "Picker (configured themes)"),

      map(m.others or "/", function()
        raphael.open_picker({ exclude_configured = true })
      end, "Picker (other themes)"),

      map(m.auto or "a", function()
        raphael.toggle_auto()
      end, "Toggle auto‑apply"),

      map(m.refresh or "R", function()
        raphael.refresh_and_reload()
      end, "Refresh & reload"),

      map(m.status or "s", function()
        raphael.show_status()
      end, "Show status"),

      map(m.random or "r", function()
        vim.cmd.RaphaelRandom()
      end, "Random theme"),

      map(m.next or ">", function()
        vim.cmd.RaphaelNext()
      end, "Next theme"),

      map(m.previous or "<", function()
        vim.cmd.RaphaelPrev()
      end, "Previous theme"),
    }
  end,
}
