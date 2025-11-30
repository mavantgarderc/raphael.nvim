-- lua/raphael/health.lua
-- Health checks for raphael.nvim:
--   - Environment / Neovim version
--   - Core module loading
--   - Theme discovery
--   - Config validation sanity
--   - Circular dependency detection between raphael.* modules

local M = {}

local health = vim.health

local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error

--- Environment checks (Neovim version, basic APIs).
local function check_environment()
  start("Environment")

  local has_nvim_09 = vim.fn.has("nvim-0.9") == 1
  if has_nvim_09 then
    ok("Neovim version >= 0.9")
  else
    warn("Neovim < 0.9; raphael.nvim is developed against 0.9+ (some things may still work)")
  end
end

--- Core modules can be required without errors.
local function check_core_modules()
  start("Core modules")

  local core_modules = {
    "raphael.config",
    "raphael.constants",
    "raphael.themes",
    "raphael.core.autocmds",
    "raphael.picker.render",
    "raphael.picker.keymaps",
    "raphael.picker.search",
    "raphael.extras.history",
  }

  for _, mod in ipairs(core_modules) do
    local ok_req, res = pcall(require, mod)
    if ok_req then
      ok(string.format("Loaded module '%s'", mod))
    else
      error(string.format("Failed to load module '%s': %s", mod, tostring(res)))
    end
  end
end

--- Themes: ensure theme discovery works and we can see at least one theme.
local function check_themes()
  start("Themes")

  local ok_req, themes = pcall(require, "raphael.themes")
  if not ok_req then
    error("Failed to require raphael.themes: " .. tostring(themes))
    return
  end

  local ok_refresh, err = pcall(themes.refresh)
  if not ok_refresh then
    error("raphael.themes.refresh() failed: " .. tostring(err))
    return
  end

  local installed = themes.installed or {}
  local count = 0
  for _ in pairs(installed) do
    count = count + 1
  end

  if count == 0 then
    warn("No installed themes detected by raphael.themes (check your 'runtimepath' / colors/ directory)")
  else
    ok(string.format("Detected %d installed themes", count))
  end
end

--- Config sanity: we can at least validate defaults & a trivial override.
local function check_config()
  start("Config")

  local ok_req, cfg_mod = pcall(require, "raphael.config")
  if not ok_req then
    error("Failed to require raphael.config: " .. tostring(cfg_mod))
    return
  end

  local ok_def, cfg = pcall(cfg_mod.validate, nil)
  if not ok_def then
    error("config.validate(nil) failed on defaults: " .. tostring(cfg))
    return
  end
  ok("config.validate(nil) succeeded on defaults")

  local ok_override, _ = pcall(cfg_mod.validate, { default_theme = "raphael-healthcheck-test-theme" })
  if ok_override then
    ok("config.validate(user_opts) succeeded with a trivial override")
  else
    warn("config.validate(user_opts) failed with a trivial override (check validation logic)")
  end
end

--- Find raphael.nvim root dir based on config.lua on runtimepath.
---@return string|nil root
local function find_root()
  -- This uses Neovim's runtimepath loader, same as the built-in Lua loader.
  local paths = vim.api.nvim_get_runtime_file("lua/raphael/config.lua", false)
  local cfg_path = paths[1]
  if not cfg_path then
    return nil
  end

  -- Normalize path separators to '/' so patterns are simple.
  local norm = cfg_path:gsub("\\", "/")

  -- Expect something like: /.../raphael.nvim/lua/raphael/config.lua
  local root = norm:match("^(.*)/lua/raphael/config%.lua$")
  if root then
    return root
  end

  -- Fallback: go three dirs up (config.lua -> raphael -> lua -> plugin root)
  local fallback = vim.fn.fnamemodify(cfg_path, ":h:h:h")
  return fallback
end

--- Recursively collect all raphael.* module files under lua/raphael.
---@return table modules   -- set-like table: [modname] = filepath
local function collect_modules()
  local root = find_root()
  if not root then
    return {}
  end

  -- Use normalized '/' separators consistently.
  root = root:gsub("\\", "/")
  local base_dir = root .. "/lua/raphael"
  local modules = {}

  local function scan_dir(dir)
    local fs = vim.loop.fs_scandir(dir)
    if not fs then
      return
    end

    while true do
      local name, t = vim.loop.fs_scandir_next(fs)
      if not name then
        break
      end
      local full = dir .. "/" .. name
      if t == "directory" then
        scan_dir(full)
      elseif t == "file" and name:sub(-4) == ".lua" then
        -- Derive module name: base_dir/xyz.lua -> raphael.xyz
        local rel = full:sub(#base_dir + 2) -- skip base_dir + "/"
        rel = rel:gsub("\\", "/")
        rel = rel:gsub("%.lua$", "")
        rel = rel:gsub("/", ".")
        local mod = "raphael." .. rel
        modules[mod] = full
      end
    end
  end

  scan_dir(base_dir)
  return modules
end

--- Build dependency graph between raphael.* modules by static scanning for require("raphael.*").
---@param modules table  -- [modname] = filepath
---@return table graph   -- graph[modname] = { dep1, dep2, ... }
local function build_dep_graph(modules)
  local graph = {}

  for mod, path in pairs(modules) do
    -- We'll collect deps in a set to avoid duplicates and self-edges.
    local deps_set = {}
    graph[mod] = {}

    local ok_read, lines = pcall(vim.fn.readfile, path)
    if not ok_read or not lines then
      goto continue
    end

    local content = table.concat(lines, "\n")

    local function add_dep(name)
      -- Only track raphael.* modules we actually discovered,
      -- skip self-dependencies and duplicates.
      if name ~= mod and modules[name] and not deps_set[name] then
        deps_set[name] = true
      end
    end

    -- Pattern: require("raphael.xxx") or require 'raphael.xxx'
    for req in content:gmatch("require%s*%(%s*['\"](raphael[%w_%.]*)['\"]%s*%)") do
      add_dep(req)
    end
    for req in content:gmatch("require%s*['\"](raphael[%w_%.]*)['\"]") do
      add_dep(req)
    end

    for dep in pairs(deps_set) do
      table.insert(graph[mod], dep)
    end

    ::continue::
  end

  return graph
end

--- Detect cycles in dependency graph using DFS.
---@param graph table
---@return table cycles  -- list of {mod1, mod2, ..., mod1}
local function detect_cycles(graph)
  local visiting = {}
  local visited = {}
  local stack = {}
  local cycles = {}

  local function push(x)
    stack[#stack + 1] = x
  end
  local function pop()
    stack[#stack] = nil
  end

  local function copy_cycle(from_mod)
    local cycle = {}
    for i = #stack, 1, -1 do
      table.insert(cycle, 1, stack[i])
      if stack[i] == from_mod then
        break
      end
    end
    table.insert(cycles, cycle)
  end

  local function dfs(node)
    visiting[node] = true
    push(node)

    for _, dep in ipairs(graph[node] or {}) do
      if not visited[dep] then
        if visiting[dep] then
          -- Found a back-edge: cycle
          copy_cycle(dep)
        else
          dfs(dep)
        end
      end
    end

    visiting[node] = nil
    visited[node] = true
    pop()
  end

  for mod in pairs(graph) do
    if not visited[mod] then
      dfs(mod)
    end
  end

  return cycles
end

local function check_circular_dependencies()
  start("Circular dependency check (raphael.* modules)")

  local modules = collect_modules()
  local count = 0
  for _ in pairs(modules) do
    count = count + 1
  end

  if count == 0 then
    warn("No raphael.* modules found under lua/raphael (is raphael.nvim on &runtimepath?)")
    return
  end

  local graph = build_dep_graph(modules)
  local cycles = detect_cycles(graph)

  if #cycles == 0 then
    ok("No circular dependencies detected between raphael.* modules")
  else
    for i, cycle in ipairs(cycles) do
      local line = table.concat(cycle, " -> ")
      error(string.format("Circular dependency #%d: %s -> %s", i, line, cycle[1]))
      if i >= 5 then
        warn("More than 5 cycles detected; showing only the first 5")
        break
      end
    end
  end
end

--- Entry point for :checkhealth raphael
function M.check()
  check_environment()
  check_core_modules()
  check_themes()
  check_config()
  check_circular_dependencies()
end

return M
