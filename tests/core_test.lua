-- tests/core_test.lua
-- Unit tests for raphael.nvim core functionality

local core = require("raphael.core")
local themes = require("raphael.themes")
local cache = require("raphael.core.cache")

describe("raphael.nvim core functionality", function()
  -- Setup function to run before each test
  local original_state = nil
  setup(function()
    -- Save original state
    original_state = cache.read()
  end)

  -- Teardown function to run after each test
  teardown(function()
    -- Restore original state
    if original_state then
      cache.write(original_state)
    end
  end)

  describe("theme discovery", function()
    it("should discover installed themes", function()
      themes.refresh()
      local installed = themes.installed
      assert.truthy(type(installed) == "table")
      assert.truthy(next(installed) ~= nil) -- Should have at least one theme
    end)

    it("should check if a theme is available", function()
      themes.refresh()
      local all_themes = themes.get_all_themes()
      if #all_themes > 0 then
        local first_theme = all_themes[1]
        assert.truthy(themes.is_available(first_theme))
      end
    end)

    it("should get all configured themes", function()
      themes.theme_map = { test_theme = { "default" } }
      local all_themes = themes.get_all_themes()
      assert.truthy(vim.tbl_contains(all_themes, "default"))
    end)
  end)

  describe("configuration validation", function()
    it("should validate default configuration", function()
      local config = require("raphael.config")
      local validated = config.validate(nil)
      assert.truthy(type(validated) == "table")
      assert.truthy(validated.default_theme ~= nil)
      assert.truthy(validated.leader ~= nil)
    end)

    it("should handle user overrides", function()
      local config = require("raphael.config")
      local user_config = {
        default_theme = "test-theme",
        leader = "<leader>tt",
      }
      local validated = config.validate(user_config)
      assert.equals("test-theme", validated.default_theme)
      assert.equals("<leader>tt", validated.leader)
    end)
  end)

  describe("core state management", function()
    it("should initialize with default state", function()
      local state = core.state
      assert.truthy(type(state) == "table")
      assert.truthy(state.bookmarks ~= nil)
      assert.truthy(state.history ~= nil)
      assert.truthy(state.usage ~= nil)
    end)

    it("should have working setup function", function()
      -- Test that setup doesn't error with minimal config
      local success, err = pcall(core.setup, { default_theme = "default" })
      assert.truthy(success, "Setup should not error: " .. tostring(err))
    end)
  end)

  describe("cache functionality", function()
    it("should read and write state", function()
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
    end)

    it("should handle bookmark toggling", function()
      local theme = "test-bookmark-theme"
      local scope = "__global"

      -- Initially should not be bookmarked
      local is_bookmarked = cache.is_bookmarked(theme, scope)
      assert.falsy(is_bookmarked)

      -- Toggle on
      local new_state = cache.toggle_bookmark(theme, scope)
      assert.truthy(new_state)

      -- Should now be bookmarked
      is_bookmarked = cache.is_bookmarked(theme, scope)
      assert.truthy(is_bookmarked)

      -- Toggle off
      local new_state2, _ = cache.toggle_bookmark(theme, scope)
      assert.falsy(new_state2)
    end)

    it("should handle history", function()
      local theme = "test-history-theme"

      cache.add_to_history(theme)
      local history = cache.get_history()

      assert.truthy(vim.tbl_contains(history, theme))
    end)

    it("should handle usage counts", function()
      local theme = "test-usage-theme"

      cache.increment_usage(theme)
      local count = cache.get_usage(theme)

      assert.equals(1, count)

      cache.increment_usage(theme)
      local count2 = cache.get_usage(theme)

      assert.equals(2, count2)
    end)
  end)

  describe("theme application", function()
    it("should have apply function", function()
      assert.truthy(type(core.apply) == "function")
    end)

    it("should have toggle_auto function", function()
      assert.truthy(type(core.toggle_auto) == "function")
    end)

    it("should have toggle_bookmark function", function()
      assert.truthy(type(core.toggle_bookmark) == "function")
    end)
  end)

  describe("picker functionality", function()
    it("should have open_picker function", function()
      assert.truthy(type(core.open_picker) == "function")
    end)

    it("should have get_current_theme function", function()
      assert.truthy(type(core.get_current_theme) == "function")
    end)
  end)

  describe("configuration management", function()
    local config_manager = require("raphael.config_manager")

    it("should export configuration correctly", function()
      local export = config_manager.export_config(core)
      assert.truthy(type(export) == "table")
      assert.truthy(export.default_theme ~= nil)
      assert.truthy(export.leader ~= nil)
    end)

    it("should validate configuration correctly", function()
      local test_config = {
        default_theme = "test-theme",
        leader = "<leader>tt",
        bookmark_group = true,
        recent_group = true,
        mappings = { picker = "p", next = ">", previous = "<" },
        enable_autocmds = true,
        enable_commands = true,
        enable_keymaps = true,
        enable_picker = true,
      }

      local is_valid, error_msg = config_manager.validate_config(test_config)
      assert.truthy(is_valid)
      assert.truthy(error_msg == nil)
    end)

    it("should detect invalid configuration", function()
      local invalid_config = {
        default_theme = 123, -- should be string
        leader = 456, -- should be string
        bookmark_group = "not_boolean", -- should be boolean
      }

      local is_valid, error_msg = config_manager.validate_config(invalid_config)
      assert.falsy(is_valid)
      assert.truthy(type(error_msg) == "string")
    end)

    it("should validate configuration sections correctly", function()
      local test_config = {
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
      }

      local results = config_manager.validate_config_sections(test_config)
      assert.truthy(type(results) == "table")
      assert.truthy(results.default_theme == true)
      assert.truthy(results.leader == true)
      assert.truthy(results.bookmark_group == true)
      assert.truthy(results.mappings == true)
      assert.truthy(results.filetype_themes == true)
      assert.truthy(results.project_themes == true)
      assert.truthy(results.profiles == true)
    end)

    it("should get configuration diagnostics", function()
      local test_config = {
        default_theme = "test-theme",
        unknown_key = "should_not_exist",
        another_unknown_key = "also_should_not_exist",
      }

      local diagnostics = config_manager.get_config_diagnostics(test_config)
      assert.truthy(type(diagnostics) == "table")
      assert.truthy(diagnostics.total_keys == 3)
      assert.truthy(#diagnostics.unknown_keys == 2)
      assert.truthy(vim.tbl_contains(diagnostics.unknown_keys, "unknown_key"))
      assert.truthy(vim.tbl_contains(diagnostics.unknown_keys, "another_unknown_key"))
    end)

    it("should save and load config to/from file", function()
      local test_config = {
        default_theme = "test-theme-save",
        leader = "<leader>ts",
        bookmark_group = false,
      }

      local temp_file = os.tmpname() .. ".json"

      -- Save config to file
      local save_success = config_manager.save_config_to_file(test_config, temp_file)
      assert.truthy(save_success)

      -- Import config from file
      local imported_config = config_manager.import_config_from_file(temp_file)
      assert.truthy(type(imported_config) == "table")
      assert.equals("test-theme-save", imported_config.default_theme)
      assert.equals("<leader>ts", imported_config.leader)
      assert.falsy(imported_config.bookmark_group)

      -- Clean up
      os.remove(temp_file)
    end)

    it("should handle invalid config file import", function()
      local non_existent_file = "/non/existent/path/config.json"
      local imported_config = config_manager.import_config_from_file(non_existent_file)
      assert.falsy(imported_config)

      local empty_file = os.tmpname()
      local f = io.open(empty_file, "w")
      f:write("")
      f:close()

      local imported_empty = config_manager.import_config_from_file(empty_file)
      assert.falsy(imported_empty)

      -- Clean up
      os.remove(empty_file)
    end)

    it("should get available presets", function()
      local presets = config_manager.get_presets()
      assert.truthy(type(presets) == "table")
      assert.truthy(presets.minimal ~= nil)
      assert.truthy(presets.full_featured ~= nil)
      assert.truthy(presets.presentation ~= nil)
    end)

    it("should apply a preset configuration", function()
      -- Save original config
      local original_config = vim.deepcopy(core.base_config)

      local success = config_manager.apply_preset("minimal", core)
      assert.truthy(success)

      -- Check that the preset values were applied (bookmark_group should be false for minimal preset)
      assert.falsy(core.base_config.bookmark_group)

      -- Restore original config
      core.base_config = original_config
      local profile_name = core.state.current_profile
      core.config = core.get_profile_config and
        core.get_profile_config(profile_name) or original_config
    end)

    it("should handle invalid preset", function()
      local success = config_manager.apply_preset("non_existent_preset", core)
      assert.falsy(success)
    end)
  end)
end)
