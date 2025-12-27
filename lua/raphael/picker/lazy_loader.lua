-- lua/raphael/picker/lazy_loader.lua
-- Lazy loading system for picker components to improve startup performance

local M = {}

-- Cache for loaded modules
local loaded_modules = {}

-- Load a picker module lazily
function M.load_module(module_name)
  if loaded_modules[module_name] then
    return loaded_modules[module_name]
  end

  local success, module = pcall(require, module_name)
  if success then
    loaded_modules[module_name] = module
    return module
  else
    vim.notify("raphael: failed to load module " .. module_name .. ": " .. tostring(module), vim.log.levels.WARN)
    return nil
  end
end

-- Lazy load the render module
function M.get_render()
  return M.load_module("raphael.picker.render")
end

-- Lazy load the search module
function M.get_search()
  return M.load_module("raphael.picker.search")
end

-- Lazy load the preview module
function M.get_preview()
  return M.load_module("raphael.picker.preview")
end

-- Lazy load the keymaps module
function M.get_keymaps()
  return M.load_module("raphael.picker.keymaps")
end

-- Lazy load the bookmarks module
function M.get_bookmarks()
  return M.load_module("raphael.picker.bookmarks")
end

-- Clear the module cache (for debugging or reloading)
function M.clear_cache()
  loaded_modules = {}
end

-- Get statistics about loaded modules
function M.get_stats()
  local count = 0
  for _ in pairs(loaded_modules) do
    count = count + 1
  end
  return {
    loaded_modules_count = count,
    loaded_modules = vim.tbl_keys(loaded_modules),
  }
end

return M
