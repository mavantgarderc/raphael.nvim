-- safe_test_runner.lua
-- A safe test runner that doesn't modify the real cache

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

print("Safe Test Runner for raphael.nvim Configuration Features")
print("========================================================")

-- Load the modules we need to test (without affecting cache)
local config_manager = require("raphael.config_manager")
local config = require("raphael.config")
local themes = require("raphael.themes")

-- Run tests for configuration management functionality only
local total_passed = 0
local total_tests = 0

print_header("Testing Configuration Management Features")

do
  print("\nConfiguration export/import tests:")

  -- Test export with a mock object
  local export = config_manager.export_config({
    base_config = { default_theme = "test-theme", leader = "<leader>te" },
    state = { current_profile = nil },
  })
  assert.truthy(type(export) == "table")
  assert.equals("test-theme", export.default_theme)
  print("  ✓ Config export works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  -- Test validation
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

  -- Test that validation handles fixable configs properly
  local is_valid_fixable, error_msg_fixable = config_manager.validate_config({
    default_theme = 123, -- should be string, but will be fixed
    leader = 456, -- should be string, but will be fixed
  })
  assert.truthy(is_valid_fixable, "Should return true since validation fixes issues")
  assert.truthy(error_msg_fixable == nil, "Should not return error message for fixable config")
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

  -- Test save
  local save_success = config_manager.save_config_to_file(test_config, temp_file)
  assert.truthy(save_success)
  print("  ✓ Config save works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  -- Test load
  local imported_config = config_manager.import_config_from_file(temp_file)
  assert.truthy(type(imported_config) == "table")
  assert.equals("test-theme-save", imported_config.default_theme)
  assert.equals("<leader>ts", imported_config.leader)
  assert.falsy(imported_config.bookmark_group)
  print("  ✓ Config load works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  -- Clean up
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

  -- Test applying a preset with a mock
  local mock_core = {
    base_config = { default_theme = "original-theme" },
    state = { current_profile = nil },
    config = { default_theme = "original-theme" },
  }

  -- Define get_profile_config function that has access to the mock_core
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

-- Test basic functionality without affecting cache
do
  print("\nBasic functionality tests:")

  -- Test theme discovery (this doesn't affect cache)
  themes.refresh()
  local installed = themes.installed
  assert.truthy(type(installed) == "table", "Installed themes should be a table")
  print("  ✓ Theme discovery works")
  total_tests = total_tests + 1
  total_passed = total_passed + 1

  -- Test configuration validation (this doesn't affect cache)
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

print_header(string.format("Final Results: %d/%d tests passed", total_passed, total_tests))

if total_passed == total_tests then
  print("🎉 All tests passed! Configuration management features are working correctly.")
  print("   (No real cache was modified during these tests)")
else
  print("⚠️  Some tests failed. Please review the output above.")
end
