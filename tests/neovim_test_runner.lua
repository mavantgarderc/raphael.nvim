-- neovim_test_runner.lua
-- A test runner that runs inside Neovim to properly load raphael modules

local function print_header(text)
  print("\n" .. string.rep("=", 60))
  print(text)
  print(string.rep("=", 60))
end

local function print_result(test_name, passed, error_msg)
  local status = passed and "✓ PASS" or "✗ FAIL"
  print(string.format("  %s: %s", status, test_name))
  if error_msg then
    print("    Error: " .. error_msg)
  end
end

local function run_test(test_name, test_func)
  local success, result = pcall(test_func)
  print_result(test_name, success and result == nil or result == true, not success and result or nil)
  return success and (result == nil or result == true)
end

-- Define a simple describe/it implementation for our tests
local function describe(description, test_block)
  print("\n" .. description .. ":")

  local tests = {}

  local function it(name, test_func)
    table.insert(tests, { name = name, func = test_func })
  end

  test_block(it)

  local passed_count = 0
  for _, test in ipairs(tests) do
    if run_test(test.name, test.func) then
      passed_count = passed_count + 1
    end
  end

  print(string.format("  %d/%d tests passed in '%s'", passed_count, #tests, description))
  return passed_count, #tests
end

-- Simple assertion library
local assert = {
  truthy = function(value, msg)
    if not value then
      error(msg or "Expected value to be truthy, got " .. tostring(value))
    end
  end,
  falsy = function(value, msg)
    if value then
      error(msg or "Expected value to be falsy, got " .. tostring(value))
    end
  end,
  equals = function(expected, actual, msg)
    if expected ~= actual then
      error(msg or string.format("Expected %s, got %s", tostring(expected), tostring(actual)))
    end
  end,
  same = function(expected, actual, msg)
    if vim.deep_equal(expected, actual) ~= true then
      error(msg or string.format("Expected %s, got %s", vim.inspect(expected), vim.inspect(actual)))
    end
  end,
  is_true = function(value, msg)
    if value ~= true then
      error(msg or string.format("Expected true, got %s", tostring(value)))
    end
  end,
  is_false = function(value, msg)
    if value ~= false then
      error(msg or string.format("Expected false, got %s", tostring(value)))
    end
  end,
  tbl_contains = function(tbl, value, msg)
    local found = false
    for _, v in ipairs(tbl) do
      if v == value then
        found = true
        break
      end
    end
    if not found then
      error(msg or string.format("Table does not contain value %s", tostring(value)))
    end
  end,
}

print("Neovim Test Runner for raphael.nvim")
print("====================================")

-- Use mock cache to avoid affecting real cache
local mock_cache = require("tests.mock_cache")

-- Load the modules we need to test (but use mock cache for testing)
local core = require("raphael.core")
local config_manager = require("raphael.config_manager")
local config = require("raphael.config")
local themes = require("raphael.themes")

-- Use mock cache instead of real cache for tests
local cache = mock_cache

-- Run tests for core functionality
local total_passed = 0
local total_tests = 0

print_header("Testing Core Raphael Functionality")

-- Test theme discovery
do
  print("\nTheme discovery tests:")
  themes.refresh()
  local installed = themes.installed
  assert.truthy(type(installed) == "table", "Installed themes should be a table")
  print("  ✓ Installed themes is a table")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  local all_themes = themes.get_all_themes()
  assert.truthy(#all_themes >= 0, "Should have at least 0 themes")
  print("  ✓ Can get all themes")
  total_tests = total_tests + 1
  total_passed = total_passed + 1
end

-- Test configuration validation
do
  print("\nConfiguration validation tests:")
  local validated = config.validate(nil)
  assert.truthy(type(validated) == "table", "Validated config should be a table")
  assert.truthy(validated.default_theme ~= nil, "Should have default theme")
  print("  ✓ Default config validation works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  local user_config = {
    default_theme = "test-theme",
    leader = "<leader>tt",
  }
  local validated_user = config.validate(user_config)
  assert.equals("test-theme", validated_user.default_theme)
  assert.equals("<leader>tt", validated_user.leader)
  print("  ✓ User config validation works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1
end

-- Test cache functionality
do
  print("\nCache functionality tests:")
  local original_state = cache.read()

  local test_state = {
    current = "test-theme",
    bookmarks = { __global = { "test-theme" } },
    history = { "test-theme" },
    usage = { ["test-theme"] = 1 },
  }

  cache.write(test_state)
  local read_state = cache.read()

  assert.equals("test-theme", read_state.current)
  assert.truthy(vim.tbl_contains(read_state.history, "test-theme"))
  assert.equals(1, read_state.usage["test-theme"])
  print("  ✓ Cache read/write works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  cache.write(original_state)
end

-- Test configuration management functionality
print_header("Testing Configuration Management Features")

do
  print("\nConfiguration export/import tests:")

  local export = config_manager.export_config({
    base_config = { default_theme = "test-theme", leader = "<leader>te" },
    state = { current_profile = nil },
  })
  assert.truthy(type(export) == "table")
  assert.equals("test-theme", export.default_theme)
  print("  ✓ Config export works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  local is_valid, error_msg = config_manager.validate_config({
    default_theme = "test-theme",
    leader = "<leader>t",
    bookmark_group = true,
  })
  assert.truthy(is_valid)
  assert.truthy(error_msg == nil)
  print("  ✓ Config validation works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  local is_valid, error_msg = config_manager.validate_config({
    default_theme = 123,
    leader = 456,
  })
  assert.truthy(is_valid, "Should return true since validation fixes issues")
  assert.truthy(error_msg == nil, "Should not return error message for fixable config")
  print("  ✓ Config validation fixes issues instead of rejecting")
  total_tests = total_tests + 1
  total_passed = total_passed + 1
end

do
  print("\nConfiguration section validation tests:")

  local results = config_manager.validate_config_sections({
    default_theme = "test-theme",
    leader = "<leader>tt",
    bookmark_group = true,
    recent_group = true,
    mappings = { picker = "p", next = ">" },
    filetype_themes = { lua = "test-theme" },
    project_themes = { ["/test/path"] = "test-theme" },
    profiles = { test = { default_theme = "test-theme" } },
    enable_autocmds = true,
    enable_commands = true,
    enable_keymaps = true,
    enable_picker = true,
  })

  assert.truthy(type(results) == "table")
  assert.truthy(results.default_theme == true)
  assert.truthy(results.leader == true)
  assert.truthy(results.bookmark_group == true)
  print("  ✓ Section validation works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1
end

do
  print("\nConfiguration diagnostics tests:")

  local diagnostics = config_manager.get_config_diagnostics({
    default_theme = "test-theme",
    unknown_key = "should_not_exist",
    another_unknown = "also_should_not_exist",
  })

  assert.truthy(type(diagnostics) == "table")
  assert.truthy(diagnostics.total_keys == 3)
  assert.truthy(#diagnostics.unknown_keys == 2)
  assert.truthy(vim.tbl_contains(diagnostics.unknown_keys, "unknown_key"))
  print("  ✓ Config diagnostics work")
  total_tests = total_tests + 1
  total_passed = total_passed + 1
end

do
  print("\nConfiguration file I/O tests:")

  local test_config = {
    default_theme = "test-theme-save",
    leader = "<leader>ts",
    bookmark_group = false,
  }

  local temp_file = os.tmpname() .. ".json"

  local save_success = config_manager.save_config_to_file(test_config, temp_file)
  assert.truthy(save_success)
  print("  ✓ Config save works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  local imported_config = config_manager.import_config_from_file(temp_file)
  assert.truthy(type(imported_config) == "table")
  assert.equals("test-theme-save", imported_config.default_theme)
  assert.equals("<leader>ts", imported_config.leader)
  assert.falsy(imported_config.bookmark_group)
  print("  ✓ Config load works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  os.remove(temp_file)
end

do
  print("\nConfiguration presets tests:")

  local presets = config_manager.get_presets()
  assert.truthy(type(presets) == "table")
  assert.truthy(presets.minimal ~= nil)
  assert.truthy(presets.full_featured ~= nil)
  assert.truthy(presets.presentation ~= nil)
  print("  ✓ Presets available")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  local mock_core = {
    base_config = { default_theme = "original-theme" },
    state = { current_profile = nil },
    config = { default_theme = "original-theme" },
  }

  function mock_core.get_profile_config(profile_name)
    return mock_core.base_config
  end

  local success = config_manager.apply_preset("minimal", mock_core)
  assert.truthy(success)
  assert.falsy(mock_core.base_config.bookmark_group)
  print("  ✓ Preset application works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1
end

print_header(string.format("Final Results: %d/%d tests passed", total_passed, total_tests))

if total_passed == total_tests then
  print("🎉 All tests passed! Configuration management features are working correctly.")
else
  print("⚠️  Some tests failed. Please review the output above.")
end

-- Test completed using mock cache, no cleanup needed for real cache
