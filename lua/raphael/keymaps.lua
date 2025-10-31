local M = {}
local map = vim.keymap.set

function M.setup(core)
  local leader = core.config.leader
  local themes = require("raphael.themes")

  -- Picker for configured themes only
  map("n", leader .. "p", function()
    core.open_picker({ only_configured = true })
  end, { desc = "raphael: picker (configured themes)" })

  -- Picker for all installed except configured
  map("n", leader .. "/", function()
    core.open_picker({ exclude_configured = true })
  end, { desc = "raphael: picker (all except configured)" })

  -- Toggle auto-apply
  map("n", leader .. "a", function()
    core.toggle_auto()
  end, { desc = "raphael: toggle auto-apply" })

  -- Refresh theme list and reload current
  map("n", leader .. "R", function()
    core.refresh_and_reload()
  end, { desc = "raphael: refresh and reload current" })

  -- Show status (current theme)
  map("n", leader .. "s", function()
    core.show_status()
  end, { desc = "raphael: show status" })

  -- Show help (keymaps)
  map("n", leader .. "h", function()
    core.show_help()
  end, { desc = "raphael: show help" })

  -- Optional: Keep next/previous/random if desired, using config.mappings
  local mappings = core.config.mappings or {}

  if mappings.next then
    map("n", leader .. mappings.next, function()
      local all_themes = themes.get_all_themes()
      if #all_themes == 0 then
        vim.notify("raphael: no themes available", vim.log.levels.WARN)
        return
      end
      local current = core.state.current
      local idx = vim.fn.index(all_themes, current) + 1
      if idx == 0 or idx > #all_themes then
        idx = 1
      else
        idx = idx + 1 > #all_themes and 1 or idx + 1
      end
      local next_theme = all_themes[idx]
      if themes.is_available(next_theme) then
        core.apply(next_theme)
      else
        vim.notify("raphael: next theme not available", vim.log.levels.WARN)
      end
    end, { desc = "raphael: next theme" })
  end

  if mappings.previous then
    map("n", leader .. mappings.previous, function()
      local all_themes = themes.get_all_themes()
      if #all_themes == 0 then
        vim.notify("raphael: no themes available", vim.log.levels.WARN)
        return
      end
      local current = core.state.current
      local idx = vim.fn.index(all_themes, current) + 1
      if idx == 0 or idx == 1 then
        idx = #all_themes
      else
        idx = idx - 1
      end
      local prev_theme = all_themes[idx]
      if themes.is_available(prev_theme) then
        core.apply(prev_theme)
      else
        vim.notify("raphael: previous theme not available", vim.log.levels.WARN)
      end
    end, { desc = "raphael: previous theme" })
  end

  if mappings.random then
    map("n", leader .. mappings.random, function()
      local all_themes = themes.get_all_themes()
      if #all_themes == 0 then
        vim.notify("raphael: no themes available", vim.log.levels.WARN)
        return
      end
      local random_idx = math.random(#all_themes)
      local random_theme = all_themes[random_idx]
      if themes.is_available(random_theme) then
        core.apply(random_theme)
      else
        vim.notify("raphael: random theme not available", vim.log.levels.WARN)
      end
    end, { desc = "raphael: random theme" })
  end
end

return M
