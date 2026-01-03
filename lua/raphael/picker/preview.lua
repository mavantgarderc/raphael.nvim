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
--   - toggle_compare(ctx, candidate_theme) -- compare current vs candidate
--   - close_code_preview()
--   - close_palette()
--   - close_all()
--   - get_cache_stats()

local M = {}

local themes = require("raphael.themes")
local samples = require("raphael.core.samples")
local palette_cache = require("raphael.core.palette_cache")
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

local compare_mode = false
local compare_base_theme = nil
local compare_candidate_theme = nil
local compare_active_side = "candidate"
local active_preview_theme = nil

local function reset_compare_state()
  compare_mode = false
  compare_base_theme = nil
  compare_candidate_theme = nil
  compare_active_side = "candidate"
  active_preview_theme = nil
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
--- Uses the enhanced caching system for improved performance.
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

  local palette_data = palette_cache.get_palette_with_cache(theme)
  if not palette_data then
    pcall(vim.api.nvim_buf_clear_namespace, palette_buf, ns, 0, -1)
    vim.cmd("redraw!")
    return
  end

  for i, hl_name in ipairs(PALETTE_HL) do
    local hl_info = palette_data[hl_name]
    if hl_info and hl_info.fg then
      local gname = ensure_palette_hl(i, hl_info.fg)
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
  vim.notify("DEBUG: preview_theme called with theme: " .. tostring(theme), vim.log.levels.INFO)
  if not theme or not themes.is_available(theme) then
    vim.notify("DEBUG: preview_theme - theme is nil or not available", vim.log.levels.INFO)
    return
  end

  if compare_mode then
    compare_candidate_theme = theme
    compare_active_side = "candidate"
  end

  vim.notify("DEBUG: preview_theme - about to load theme: " .. theme, vim.log.levels.INFO)
  local ok, err = pcall(load_theme_raw, theme, false)
  if not ok then
    vim.notify("raphael: failed to preview theme: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  vim.notify("DEBUG: preview_theme - theme loaded successfully: " .. theme, vim.log.levels.INFO)

  active_preview_theme = theme
  palette_hl_cache = {}
  local ok2, err2 = pcall(M.update_palette, ctx, theme)
  if not ok2 then
    vim.notify("raphael: failed to update palette: " .. tostring(err2), vim.log.levels.ERROR)
  end
  vim.notify("DEBUG: preview_theme - completed for theme: " .. theme, vim.log.levels.INFO)
end

--- Expose raw load_theme for UI revert logic / compare.
---@param theme string
---@param set_name boolean
function M.load_theme(theme, set_name)
  local ok, err = pcall(load_theme_raw, theme, set_name)
  if not ok then
    return false, err
  end
  if not set_name then
    active_preview_theme = theme
  end
  return true
end

local function ensure_code_buf()
  if code_buf and vim.api.nvim_buf_is_valid(code_buf) then
    return
  end
  code_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = code_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = code_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = code_buf })
end

local function get_active_theme_label(ctx)
  if compare_mode then
    if compare_active_side == "base" then
      return compare_base_theme or "?"
    else
      return compare_candidate_theme or "?"
    end
  end

  return active_preview_theme or (ctx.core.state and ctx.core.state.current) or "?"
end

-- Debounce utility for preview updates
local debounce_utils = require("raphael.utils.debounce")
local debounced_code_preview = nil

--- Update code preview buffer based on current_lang and preview/compare state.
---@param ctx table
function M.update_code_preview(ctx)
  if not is_preview_visible then
    return
  end

  if not debounced_code_preview then
    debounced_code_preview = debounce_utils.debounce(function(ctx_copy)
      ensure_code_buf()

      local lang_info = samples.get_language_info(current_lang or "lua")
      local sample_code = samples.get_sample(current_lang or "lua")

      if not sample_code then
        vim.api.nvim_buf_set_lines(code_buf, 0, -1, false, {
          "Sample unavailable - fallback to basic text.",
        })
        return
      end

      local theme_label = get_active_theme_label(ctx_copy)
      local header
      if compare_mode then
        header = string.format(
          "[%s] - compare base=%s | cand=%s | showing=%s",
          lang_info.display,
          compare_base_theme or "?",
          compare_candidate_theme or "?",
          theme_label or "?"
        )
      else
        header = string.format("[%s] - [%s]", lang_info.display, theme_label or "?")
      end

      local lines = vim.split(sample_code, "\n")
      local all = { header, "" }
      for _, l in ipairs(lines) do
        table.insert(all, l)
      end

      vim.api.nvim_buf_set_lines(code_buf, 0, -1, false, all)
      vim.api.nvim_set_option_value("filetype", lang_info.ft, { buf = code_buf })

      vim.cmd(string.format("silent! syntax on | syntax enable | setlocal syntax=%s", lang_info.ft))
    end, 75)
  end

  debounced_code_preview(ctx)
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

--- Toggle compare mode between current theme (base) and candidate under cursor.
---
--- Behavior:
---   - First press:
---       * base   = ctx.core.state.current
---       * cand   = candidate_theme
---       * mode   = compare, showing candidate
---   - Move cursor: candidate updates automatically via preview_theme()
---   - Press C again:
---       * If same candidate: toggle between base ⇄ candidate
---       * If different candidate: update candidate and show it
---
---@param ctx table
---@param candidate_theme string
function M.toggle_compare(ctx, candidate_theme)
  if not candidate_theme or not themes.is_available(candidate_theme) then
    vim.notify("raphael: candidate theme not available for compare", vim.log.levels.WARN)
    return
  end

  local base = (ctx.core.state and ctx.core.state.current) or vim.g.colors_name or ctx.core.config.default_theme

  if not base or not themes.is_available(base) then
    vim.notify("raphael: no valid current theme to compare against", vim.log.levels.WARN)
    return
  end

  if not is_preview_visible then
    local allowed_langs = get_allowed_langs(ctx.core)
    current_lang = current_lang or allowed_langs[1] or "lua"
    open_code_window(ctx)
  end

  if not compare_mode then
    compare_mode = true
    compare_base_theme = base
    compare_candidate_theme = candidate_theme
    compare_active_side = "candidate"

    local ok, err = pcall(load_theme_raw, candidate_theme, false)
    if not ok then
      vim.notify("raphael: failed to enter compare mode: " .. tostring(err), vim.log.levels.ERROR)
      reset_compare_state()
      return
    end
    active_preview_theme = candidate_theme
  else
    if candidate_theme ~= compare_candidate_theme then
      compare_candidate_theme = candidate_theme
      compare_active_side = "candidate"
      local ok, err = pcall(load_theme_raw, candidate_theme, false)
      if not ok then
        vim.notify("raphael: failed to update candidate theme: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      active_preview_theme = candidate_theme
    else
      if compare_active_side == "candidate" then
        compare_active_side = "base"
        if compare_base_theme and themes.is_available(compare_base_theme) then
          local ok, err = pcall(load_theme_raw, compare_base_theme, false)
          if not ok then
            vim.notify("raphael: failed to show base theme: " .. tostring(err), vim.log.levels.ERROR)
            return
          end
          active_preview_theme = compare_base_theme
        end
      else
        compare_active_side = "candidate"
        if compare_candidate_theme and themes.is_available(compare_candidate_theme) then
          local ok, err = pcall(load_theme_raw, compare_candidate_theme, false)
          if not ok then
            vim.notify("raphael: failed to show candidate theme: " .. tostring(err), vim.log.levels.ERROR)
            return
          end
          active_preview_theme = compare_candidate_theme
        end
      end
    end
  end

  palette_hl_cache = {}
  ---@diagnostic disable-next-line: param-type-mismatch
  M.update_palette(ctx, active_preview_theme)
  M.update_code_preview(ctx)
end

--- Close the code preview window if present.
function M.close_code_preview()
  if code_win and vim.api.nvim_win_is_valid(code_win) then
    pcall(vim.api.nvim_win_close, code_win, true)
  end
  code_win = nil
  is_preview_visible = false
  reset_compare_state()
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
---     enhanced_cache_stats = table, -- stats from the new caching system
---   }
function M.get_cache_stats()
  local legacy_palette_size = 0
  for k, _ in pairs(palette_hl_cache) do
    if type(k) == "string" then
      legacy_palette_size = legacy_palette_size + 1
    end
  end

  local enhanced_stats = palette_cache.get_stats()

  return {
    palette_cache_size = legacy_palette_size,
    active_timers = 0,
    enhanced_cache_stats = enhanced_stats,
  }
end

return M
