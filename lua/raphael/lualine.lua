-- lua/raphael/lualine.lua
-- Lualine component for raphael.nvim
--
-- Usage:
--   require('lualine').setup({
--     sections = {
--       lualine_c = {
--         { require('raphael').lualine_component() }
--       }
--     }
--   })
--
-- Options:
--   icon: string (default: "󰉼")
--   show_profile: boolean (default: true)
--   separator: string (default: " ")
--   dynamic_color: boolean (default: true) - auto light/dark color
--   brackets: table (default: {"[", "]"}) - profile brackets

local M = {}

local core = nil

local function get_core()
  if not core then
    core = require("raphael.core")
  end
  return core
end

local function detect_theme_type()
  local ok, bg = pcall(vim.api.nvim_get_option, "bg")
  if ok and bg then
    return bg
  end
  return "unknown"
end

local function get_dynamic_color()
  local theme_type = detect_theme_type()

  if theme_type == "light" then
    return { fg = "#1a1a1a", bg = "#d0d0d0", gui = "bold" }
  elseif theme_type == "dark" then
    return { fg = "#e0e0e0", bg = "#3a3a3a", gui = "bold" }
  end
  return "lualine_c_normal"
end

function M.component(opts)
  opts = opts or {}
  local icon = opts.icon or "󰉼"
  local show_profile = opts.show_profile
  if show_profile == nil then
    show_profile = true
  end
  local separator = opts.separator or " "
  local dynamic_color = opts.dynamic_color
  if dynamic_color == nil then
    dynamic_color = true
  end
  local brackets = opts.brackets or { "[", "]" }

  return function()
    local c = get_core()
    if not c then
      return ""
    end

    local theme = c.get_current_theme() or "none"
    local profile = c.get_current_profile()

    local text = icon .. separator .. theme
    if show_profile and profile then
      text = text .. " " .. brackets[1] .. profile .. brackets[2]
    end

    if dynamic_color then
      return { text, color = get_dynamic_color() }
    end

    return text
  end
end

return M
