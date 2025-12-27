-- lua/raphael/utils/debounce.lua
-- Debouncing utility for Raphael.nvim
-- Provides debouncing functionality to improve performance during rapid events

local M = {}

--- Create a debounced function
--- @param fn function The function to debounce
--- @param delay number Delay in milliseconds
--- @return function The debounced function
function M.debounce(fn, delay)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      local ok = pcall(function() -- luacheck: ignore
        if timer and not timer:is_closing() then
          timer:stop()
          vim.schedule(function()
            if timer and not timer:is_closing() then
              timer:close()
            end
          end)
        end
      end)
      timer = nil
    end
    timer = vim.defer_fn(function()
      ---@diagnostic disable-next-line: deprecated
      pcall(fn, _G.unpack(args))
      timer = nil
    end, delay)
  end
end

--- Create a throttled function
--- @param fn function The function to throttle
--- @param delay number Delay in milliseconds
--- @return function The throttled function
function M.throttle(fn, delay)
  local timer = nil
  local last_run = 0
  local queued_args = nil

  return function(...)
    local args = { ... }
    local now = vim.loop.now()

    if now - last_run > delay then
      last_run = now
      ---@diagnostic disable-next-line: deprecated
      pcall(fn, _G.unpack(args))
    else
      queued_args = args
      if not timer then
        timer = vim.defer_fn(function()
          if queued_args then
            ---@diagnostic disable-next-line: deprecated
            pcall(fn, _G.unpack(queued_args))
            queued_args = nil
          end
          timer = nil
          last_run = vim.loop.now()
        end, delay - (now - last_run))
      end
    end
  end
end

return M
