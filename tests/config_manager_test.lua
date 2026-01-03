-- tests/config_manager_test.lua
-- Integration tests for the configuration management features

local config_manager = require("raphael.config_manager")
local config = require("raphael.config")

describe("config_manager integration tests", function()
  describe("export and import functionality", function()
    it("should properly export and import configuration", function()
      -- Create a test config
      local test_config = {
        default_theme = "test-theme-export-import",
        leader = "<leader>tx",
        bookmark_group = true,
        recent_group = false,
        mappings = {
          picker = "p",
          next = ">",
          previous = "<",
        },
        enable_autocmds = false,
        enable_commands = true,
        enable_keymaps = true,
        enable_picker = true,
      }
      
      -- Validate the config first
      local validated_config = config.validate(test_config)
      
      -- Export the config
      local core_mock = {
        base_config = validated_config,
        state = { current_profile = nil },
        get_profile_config = function(profile_name)
          return validated_config
        end
      }
      
      local exported = config_manager.export_config(core_mock)
      assert.are.same(validated_config, exported)
    end)

    it("should save and load config from file", function()
      local test_config = {
        default_theme = "test-theme-file-io",
        leader = "<Leader>tf",
        bookmark_group = false,
      }
      
      local temp_file = os.tmpname() .. ".json"
      
      -- Save config to file
      local save_success = config_manager.save_config_to_file(test_config, temp_file)
      assert.is_true(save_success)
      
      -- Verify file exists and can be read
      local file = io.open(temp_file, "r")
      assert.truthy(file, "File should exist after save")
      file:close()
      
      -- Import config from file
      local imported_config = config_manager.import_config_from_file(temp_file)
      assert.truthy(imported_config, "Config should be imported successfully")
      assert.are.equal("test-theme-file-io", imported_config.default_theme)
      assert.are.equal("<Leader>tf", imported_config.leader)
      assert.is_false(imported_config.bookmark_group)
      
      -- Clean up
      os.remove(temp_file)
    end)
  end)

  describe("validation functionality", function()
    it("should validate correct configuration", function()
      local valid_config = {
        default_theme = "test-theme",
        leader = "<leader>t",
        bookmark_group = true,
        recent_group = false,
        mappings = { picker = "p" },
        enable_autocmds = true,
        enable_commands = true,
        enable_keymaps = true,
        enable_picker = true,
      }
      
      local is_valid, error_msg = config_manager.validate_config(valid_config)
      assert.is_true(is_valid)
      assert.is_nil(error_msg)
    end)

    it("should detect invalid configuration", function()
      local invalid_config = {
        default_theme = 123, -- should be string
        leader = 456, -- should be string
        bookmark_group = "not_boolean", -- should be boolean
      }
      
      local is_valid, error_msg = config_manager.validate_config(invalid_config)
      assert.is_false(is_valid)
      assert.truthy(error_msg)
    end)

    it("should validate configuration sections properly", function()
      local config_with_sections = {
        default_theme = "test-theme",
        leader = "<leader>t",
        bookmark_group = true,
        recent_group = false,
        mappings = { picker = "p", next = ">", previous = "<" },
        filetype_themes = { lua = "test-theme" },
        project_themes = { ["/test/path"] = "test-theme" },
        profiles = { test_profile = { default_theme = "other-theme" } },
        enable_autocmds = true,
        enable_commands = true,
        enable_keymaps = true,
        enable_picker = true,
      }
      
      local results = config_manager.validate_config_sections(config_with_sections)
      
      -- Check that all expected sections are validated
      assert.is_boolean(results.default_theme)
      assert.is_boolean(results.leader)
      assert.is_boolean(results.bookmark_group)
      assert.is_boolean(results.recent_group)
      assert.is_boolean(results.mappings)
      assert.is_boolean(results.filetype_themes)
      assert.is_boolean(results.project_themes)
      assert.is_boolean(results.profiles)
      assert.is_boolean(results.enable_autocmds)
      assert.is_boolean(results.enable_commands)
      assert.is_boolean(results.enable_keymaps)
      assert.is_boolean(results.enable_picker)
      
      -- All should be true for our valid config
      assert.is_true(results.default_theme)
      assert.is_true(results.leader)
      assert.is_true(results.bookmark_group)
      assert.is_true(results.recent_group)
      assert.is_true(results.mappings)
      assert.is_true(results.filetype_themes)
      assert.is_true(results.project_themes)
      assert.is_true(results.profiles)
      assert.is_true(results.enable_autocmds)
      assert.is_true(results.enable_commands)
      assert.is_true(results.enable_keymaps)
      assert.is_true(results.enable_picker)
    end)
  end)

  describe("preset functionality", function()
    it("should return available presets", function()
      local presets = config_manager.get_presets()
      
      assert.truthy(presets.minimal, "Should have minimal preset")
      assert.truthy(presets.full_featured, "Should have full_featured preset")
      assert.truthy(presets.presentation, "Should have presentation preset")
      
      -- Check that minimal preset has expected properties
      assert.is_false(presets.minimal.bookmark_group, "Minimal preset should have bookmark_group = false")
      assert.is_true(presets.minimal.enable_picker, "Minimal preset should have enable_picker = true")
      
      -- Check that presentation preset has expected properties
      assert.is_false(presets.presentation.bookmark_group, "Presentation preset should have bookmark_group = false")
      assert.is_false(presets.presentation.sample_preview.enabled, "Presentation preset should have sample_preview.enabled = false")
    end)

    it("should apply a preset correctly", function()
      -- Create a mock core module
      local mock_core = {
        base_config = { default_theme = "original-theme" },
        state = { current_profile = nil },
        config = { default_theme = "original-theme" },
        get_profile_config = function(profile_name)
          return mock_core.base_config
        end
      }
      
      -- Apply the minimal preset
      local success = config_manager.apply_preset("minimal", mock_core)
      
      assert.is_true(success, "Preset application should succeed")
      assert.is_false(mock_core.base_config.bookmark_group, "bookmark_group should be false after minimal preset")
      assert.is_true(mock_core.base_config.enable_picker, "enable_picker should be true after minimal preset")
    end)

    it("should handle invalid preset name", function()
      local mock_core = {
        base_config = { default_theme = "original-theme" },
        state = { current_profile = nil },
        config = { default_theme = "original-theme" },
        get_profile_config = function(profile_name)
          return mock_core.base_config
        end
      }
      
      local success = config_manager.apply_preset("non_existent_preset", mock_core)
      
      assert.is_false(success, "Should return false for invalid preset")
    end)
  end)

  describe("diagnostics functionality", function()
    it("should provide configuration diagnostics", function()
      local test_config = {
        default_theme = "test-theme",
        unknown_option = "should_not_exist",
        another_unknown = "also_should_not_exist",
      }
      
      local diagnostics = config_manager.get_config_diagnostics(test_config)
      
      assert.are.equal(3, diagnostics.total_keys, "Should count all keys")
      assert.are.equal(2, #diagnostics.unknown_keys, "Should find 2 unknown keys")
      assert.truthy(vim.tbl_contains(diagnostics.unknown_keys, "unknown_option"), "Should include unknown_option")
      assert.truthy(vim.tbl_contains(diagnostics.unknown_keys, "another_unknown"), "Should include another_unknown")
    end)
  end)
end)