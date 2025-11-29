-- lua/raphael/picker/preview.lua
-- Palette preview + (optional) code sample window for Raphael picker.
--
-- Exposed API:
--   - update_palette(ctx, theme)
--   - preview_theme(ctx, theme)
--   - load_theme(theme, set_name)      -- raw colorscheme loader
--   - update_code_preview(ctx)
--   - toggle_and_iterate_preview(ctx)
--   - iterate_backward_preview(ctx)
--   - close_code_preview()
--   - close_palette()
--   - close_all()
--   - get_cache_stats()

local M = {}

local themes = require("raphael.themes")
local samples = require("raphael.core.samples")
local C = require("raphael.constants")

-- Palette preview (top mini bar)
local palette_buf, palette_win
local palette_hl_cache = {}

local PALETTE_HL = {
  "Normal",
  "Comment",
  "String",
  "Keyword",
  "Function",
  "Type",
  "Constant",
  "Special",
}

-- Code sample preview (right side)
local code_buf, code_win
local current_lang
local is_preview_visible = false

-- ────────────────────────────────────────────────────────────────────────
-- Palette helpers
-- ────────────────────────────────────────────────────────────────────────

local function get_hl_rgb(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and hl then
    return hl
  end
  return nil
end

local function ensure_palette_hl(idx, color_int)
  if not color_int then
    return nil
  end
  local key = ("raphaelPalette_%d_%x"):format(idx, color_int)
  if palette_hl_cache[key] then
    return key
  end
  local ok = pcall(vim.api.nvim_set_hl, 0, key, { fg = color_int })
  if not ok then
    return nil
  end
  palette_hl_cache[key] = true
  return key
end

--- Close the palette preview window (top icons bar), if present.
function M.close_palette()
  if palette_win and vim.api.nvim_win_is_valid(palette_win) then
    pcall(vim.api.nvim_win_close, palette_win, true)
  end
  palette_win, palette_buf = nil, nil
end

--- Update the top palette bar based on the given theme.
---
--- Draws a single-line window above the picker, consisting of BLOCK icons
--- colored by various highlight groups (Normal, Comment, String, etc.)
---
---@param ctx table  # picker context
---@param theme string
function M.update_palette(ctx, theme)
  if not theme or not themes.is_available(theme) then
    M.close_palette()
    return
  end

  if not ctx.win or not vim.api.nvim_win_is_valid(ctx.win) or not ctx.w then
    return
  end

  if not palette_buf or not vim.api.nvim_buf_is_valid(palette_buf) then
    palette_buf = vim.api.nvim_create_buf(false, true)
    pcall(vim.api.nvim_set_option_value, "buftype", "nofile", { buf = palette_buf })
    pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = palette_buf })
    pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = palette_buf })
  end

  local blocks = {}
  for i = 1, #PALETTE_HL do
    blocks[i] = C.ICON.BLOCK
  end
  local blocks_str = table.concat(blocks, " ")
  local display_w = vim.fn.strdisplaywidth(blocks_str)
  local pad = math.max(math.floor((ctx.w - display_w) / 2), 0)
  local line = string.rep(" ", pad) .. blocks_str

  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = palette_buf })
  pcall(vim.api.nvim_buf_set_lines, palette_buf, 0, -1, false, { line })
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = palette_buf })

  local bufline = (vim.api.nvim_buf_get_lines(palette_buf, 0, 1, false) or { "" })[1] or ""
  local ns = C.NS.PALETTE
  pcall(vim.api.nvim_buf_clear_namespace, palette_buf, ns, 0, -1)

  if not palette_hl_cache[theme] or type(palette_hl_cache[theme]) ~= "table" then
    palette_hl_cache[theme] = {}
    for _, hl_name in ipairs(PALETTE_HL) do
      local hl = get_hl_rgb(hl_name)
      if hl then
        palette_hl_cache[theme][hl_name] = hl.fg or hl.bg
      end
    end
  end

  for i, hl_name in ipairs(PALETTE_HL) do
    local color_int = palette_hl_cache[theme][hl_name]
    if color_int then
      local gname = ensure_palette_hl(i, color_int)
      if gname then
        local search_pos, occurrence = 1, 0
        while true do
          local s, e = string.find(bufline, C.ICON.BLOCK, search_pos, true)
          if not s then
            break
          end
          occurrence = occurrence + 1
          if occurrence == i then
            pcall(
              vim.api.nvim_buf_set_extmark,
              palette_buf,
              ns,
              0,
              s - 1,
              { end_col = e, hl_group = gname, strict = false }
            )
            break
          end
          search_pos = e + 1
        end
      end
    end
  end

  vim.cmd("redraw!")

  local pal_row = math.max(ctx.row - 2, 0)
  local pal_col = ctx.col
  local pal_width = ctx.w

  if palette_win and vim.api.nvim_win_is_valid(palette_win) then
    pcall(vim.api.nvim_win_set_buf, palette_win, palette_buf)
    pcall(vim.api.nvim_win_set_config, palette_win, {
      relative = "editor",
      width = pal_width,
      height = 1,
      row = pal_row,
      col = pal_col,
      style = "minimal",
    })
  else
    palette_win = vim.api.nvim_open_win(palette_buf, false, {
      relative = "editor",
      width = pal_width,
      height = 1,
      row = pal_row,
      col = pal_col,
      style = "minimal",
      zindex = 50,
    })
    pcall(vim.api.nvim_set_option_value, "winhl", "Normal:Normal", { win = palette_win })
  end
end

-- ────────────────────────────────────────────────────────────────────────
-- Raw theme loader (for previews & revert only)
-- ────────────────────────────────────────────────────────────────────────

local function load_theme_raw(theme, set_name)
  if not theme or not themes.is_available(theme) then
    return
  end

  vim.cmd("hi clear")
  if vim.fn.exists("syntax_on") == 1 then
    vim.cmd("syntax reset")
  end
  pcall(vim.api.nvim_set_var, "colors_name", nil)

  local lua_path = vim.api.nvim_get_runtime_file("colors/" .. theme .. ".lua", false)[1]
  local vim_path = vim.api.nvim_get_runtime_file("colors/" .. theme .. ".vim", false)[1]
  local path = lua_path or vim_path

  if path then
    if lua_path then
      dofile(path)
    else
      vim.cmd("source " .. vim.fn.fnameescape(path))
    end
  else
    vim.cmd.colorscheme(theme)
  end

  vim.cmd("syntax on")
  vim.cmd("doautocmd ColorScheme")
  vim.cmd("redraw!")

  if set_name then
    pcall(vim.api.nvim_set_var, "colors_name", theme)
  else
    pcall(vim.api.nvim_set_var, "colors_name", nil)
  end
end

--- Preview a theme (apply temporarily, update palette only).
---@param ctx table
---@param theme string
function M.preview_theme(ctx, theme)
  if not theme or not themes.is_available(theme) then
    return
  end

  local ok, err = pcall(load_theme_raw, theme, false)
  if not ok then
    vim.notify("raphael: failed to preview theme: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  palette_hl_cache = {}
  local ok2, err2 = pcall(M.update_palette, ctx, theme)
  if not ok2 then
    vim.notify("raphael: failed to update palette: " .. tostring(err2), vim.log.levels.ERROR)
  end
end

--- Expose raw load_theme for UI revert logic.
---@param theme string
---@param set_name boolean
function M.load_theme(theme, set_name)
  return load_theme_raw(theme, set_name)
end

-- ────────────────────────────────────────────────────────────────────────
-- Code sample preview
-- ────────────────────────────────────────────────────────────────────────

local function ensure_code_buf()
  if code_buf and vim.api.nvim_buf_is_valid(code_buf) then
    return
  end
  code_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = code_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = code_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = code_buf })
end

--- Update code preview buffer based on current_lang.
--- Uses the currently active theme from ctx.core.state.current in header.
---@param ctx table
function M.update_code_preview(ctx)
  if not is_preview_visible then
    return
  end

  ensure_code_buf()

  local lang_info = samples.get_language_info(current_lang)
  local sample_code = samples.get_sample(current_lang)

  if not sample_code then
    vim.api.nvim_buf_set_lines(code_buf, 0, -1, false, {
      "Sample unavailable - fallback to basic text.",
    })
    return
  end

  local lines = vim.split(sample_code, "\n")
  local theme = ctx.core.state.current or "?"
  local header = string.format("[%s] - [%s]", lang_info.display, theme)

  vim.api.nvim_buf_set_lines(code_buf, 0, -1, false, vim.list_extend({ header, "" }, lines))
  vim.api.nvim_set_option_value("filetype", lang_info.ft, { buf = code_buf })

  vim.cmd(string.format("silent! syntax on | syntax enable | setlocal syntax=%s", lang_info.ft))
end

local function open_code_window(ctx)
  if is_preview_visible then
    return
  end

  ensure_code_buf()

  local code_col = ctx.col + ctx.w + 2
  local rel_size = ctx.core.config.sample_preview.relative_size or 0.5
  local code_width = math.floor(ctx.w * rel_size) * 2
  local code_height = ctx.h

  code_win = vim.api.nvim_open_win(code_buf, false, {
    relative = "editor",
    width = code_width,
    height = code_height,
    row = ctx.row,
    col = code_col,
    style = "minimal",
    border = "rounded",
    zindex = 50,
  })

  vim.api.nvim_set_current_win(ctx.win)

  is_preview_visible = true
  M.update_code_preview(ctx)
end

local function get_allowed_langs(core)
  local cfg = core.config.sample_preview or {}
  local custom = cfg.languages
  if custom and vim.islist(custom) and #custom > 0 then
    return custom
  end
  return vim.tbl_map(function(lang)
    return lang.name
  end, samples.languages)
end

--- Toggle code preview / iterate language forward (used by 'i' mapping).
---@param ctx table
function M.toggle_and_iterate_preview(ctx)
  local allowed_langs = get_allowed_langs(ctx.core)

  if not is_preview_visible then
    current_lang = allowed_langs[1] or "lua"
    open_code_window(ctx)
  else
    local function get_next_lang(current, langs)
      for i, l in ipairs(langs) do
        if l == current then
          return langs[(i % #langs) + 1]
        end
      end
      return langs[1] or "lua"
    end

    current_lang = get_next_lang(current_lang, allowed_langs)
    M.update_code_preview(ctx)
  end
end

--- Iterate language backward (used by 'I' mapping).
---@param ctx table
function M.iterate_backward_preview(ctx)
  if not is_preview_visible then
    return
  end
  local allowed_langs = get_allowed_langs(ctx.core)

  local function get_prev_lang(current, langs)
    for i, l in ipairs(langs) do
      if l == current then
        return langs[((i - 2) % #langs) + 1]
      end
    end
    return langs[#langs] or "lua"
  end

  current_lang = get_prev_lang(current_lang, allowed_langs)
  M.update_code_preview(ctx)
end

--- Close the code preview window if present.
function M.close_code_preview()
  if code_win and vim.api.nvim_win_is_valid(code_win) then
    pcall(vim.api.nvim_win_close, code_win, true)
  end
  code_win = nil
  is_preview_visible = false
end

--- Close both palette + code preview windows.
function M.close_all()
  M.close_palette()
  M.close_code_preview()
end

--- Get cache stats for :RaphaelCacheStats.
---
--- @return table
---   {
---     palette_cache_size = integer,
---     active_timers      = integer, -- currently always 0
---   }
function M.get_cache_stats()
  local palette_size = 0
  for k, _ in pairs(palette_hl_cache) do
    if type(k) == "string" then
      palette_size = palette_size + 1
    end
  end
  return {
    palette_cache_size = palette_size,
    active_timers = 0,
  }
end

return M
