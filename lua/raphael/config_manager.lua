-- lua/raphael/config_manager.lua
-- Configuration export/import and management utilities for raphael.nvim

local M = {}

local config = require("raphael.config")

--- Export current configuration to a table that can be serialized
---
---@param core_module table The core module containing the current config
---@return table|nil export The exported configuration
function M.export_config(core_module)
  if not core_module or not core_module.base_config then
    vim.notify("raphael: core module not available for config export", vim.log.levels.ERROR)
    return nil
  end

  local export = vim.deepcopy(core_module.base_config)

  export.on_apply = nil

  if core_module.state and core_module.state.current_profile then
    export.current_profile = core_module.state.current_profile
  end

  return export
end

--- Import configuration from a file path
---
---@param file_path string Path to the configuration file
---@return table|nil config The imported configuration, or nil on failure
function M.import_config_from_file(file_path)
  local full_path = vim.fn.expand(file_path)

  local file = io.open(full_path, "r")
  if not file then
    vim.notify("raphael: config file not found: " .. full_path, vim.log.levels.ERROR)
    return nil
  end

  local content = file:read("*a")
  file:close()

  if not content or content:match("^%s*$") then
    vim.notify("raphael: config file is empty: " .. full_path, vim.log.levels.ERROR)
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    vim.notify("raphael: failed to decode config file: " .. full_path, vim.log.levels.ERROR)
    return nil
  end

  return decoded
end

--- Import configuration from a table
---
---@param config_data table The configuration data to import
---@return table|nil validated_config The validated configuration, or nil on failure
function M.import_config_from_table(config_data)
  if type(config_data) ~= "table" then
    vim.notify("raphael: config data must be a table", vim.log.levels.ERROR)
    return nil
  end

  local validated = config.validate(config_data)
  return validated
end

--- Save configuration to a file
---
---@param config_data table The configuration to save
---@param file_path string Path to save the configuration file
---@return boolean success Whether the save was successful
function M.save_config_to_file(config_data, file_path)
  local full_path = vim.fn.expand(file_path)

  local dir = vim.fn.fnamemodify(full_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  local ok, encoded = pcall(vim.json.encode, config_data)
  if not ok then
    vim.notify("raphael: failed to encode config for saving", vim.log.levels.ERROR)
    return false
  end

  local file = io.open(full_path, "w")
  if not file then
    vim.notify("raphael: failed to open file for writing: " .. full_path, vim.log.levels.ERROR)
    return false
  end

  file:write(encoded)
  file:close()

  vim.notify("raphael: configuration saved to " .. full_path, vim.log.levels.INFO)
  return true
end

--- Get a list of available config files in the raphael config directory
---
---@return string[] List of config file paths
function M.list_config_files()
  local config_dir = vim.fn.stdpath("config") .. "/raphael/configs"
  local files = vim.fn.globpath(config_dir, "*.json", false, true)
  return files
end

--- Validate a configuration table
---
---@param config_data table The configuration to validate
---@return boolean is_valid Whether the configuration is valid
---@return string|nil error_msg Error message if validation failed
function M.validate_config(config_data)
  if type(config_data) ~= "table" then
    return false, "Configuration must be a table"
  end

  local ok, result = pcall(config.validate, config_data)
  if not ok then
    return false, "Configuration validation failed: " .. tostring(result)
  end

  return true, nil
end

--- Validate specific configuration sections
---
---@param config_data table The configuration to validate
---@return table validation_results Results for each section
function M.validate_config_sections(config_data)
  if type(config_data) ~= "table" then
    return { error = "Configuration must be a table" }
  end

  local results = {}

  results.leader = type(config_data.leader) == "string" and config_data.leader ~= ""
  results.default_theme = type(config_data.default_theme) == "string" and config_data.default_theme ~= ""
  results.bookmark_group = type(config_data.bookmark_group) == "boolean"
  results.recent_group = type(config_data.recent_group) == "boolean"

  if type(config_data.mappings) == "table" then
    results.mappings = true
    for key, val in pairs(config_data.mappings) do
      if type(val) ~= "string" then
        results.mappings = false
        break
      end
    end
  else
    results.mappings = false
  end

  if config_data.theme_map ~= nil then
    results.theme_map = type(config_data.theme_map) == "table" or config_data.theme_map == nil
  else
    results.theme_map = true
  end

  if type(config_data.filetype_themes) == "table" then
    results.filetype_themes = true
    for ft, theme in pairs(config_data.filetype_themes) do
      if type(ft) ~= "string" or type(theme) ~= "string" or theme == "" then
        results.filetype_themes = false
        break
      end
    end
  else
    results.filetype_themes = false
  end

  if type(config_data.project_themes) == "table" then
    results.project_themes = true
    for path, theme in pairs(config_data.project_themes) do
      if type(path) ~= "string" or type(theme) ~= "string" or theme == "" then
        results.project_themes = false
        break
      end
    end
  else
    results.project_themes = false
  end

  if config_data.profiles ~= nil then
    if type(config_data.profiles) == "table" then
      results.profiles = true
      for name, prof in pairs(config_data.profiles) do
        if type(name) ~= "string" or type(prof) ~= "table" then
          results.profiles = false
          break
        end
      end
    else
      results.profiles = false
    end
  else
    results.profiles = true
  end

  local feature_toggles = { "enable_autocmds", "enable_commands", "enable_keymaps", "enable_picker" }
  for _, toggle in ipairs(feature_toggles) do
    if config_data[toggle] ~= nil then
      results[toggle] = type(config_data[toggle]) == "boolean"
    else
      results[toggle] = true
    end
  end

  return results
end

--- Get configuration diagnostics
---
---@param config_data table The configuration to analyze
---@return table diagnostics Information about the configuration
function M.get_config_diagnostics(config_data)
  if type(config_data) ~= "table" then
    return { error = "Configuration must be a table" }
  end

  local diagnostics = {
    total_keys = 0,
    unknown_keys = {},
    missing_defaults = {},
  }

  for k, _ in pairs(config_data) do
    diagnostics.total_keys = diagnostics.total_keys + 1
  end

  for key in pairs(config_data) do
    if not config.defaults[key] then
      table.insert(diagnostics.unknown_keys, key)
    end
  end

  for key, default_val in pairs(config.defaults) do
    if config_data[key] == nil then
      table.insert(diagnostics.missing_defaults, key)
    end
  end

  return diagnostics
end

--- Get available configuration presets
---
---@return table presets A table of available presets
function M.get_presets()
  local presets = {
    minimal = {
      leader = "<leader>t",
      mappings = {
        picker = "p",
        next = ">",
        previous = "<",
        auto = "a",
      },
      default_theme = "default",
      bookmark_group = false,
      recent_group = false,
      enable_picker = true,
      enable_commands = true,
      enable_keymaps = true,
      enable_autocmds = false,
      icons = config.defaults.icons,
    },
    full_featured = {
      leader = "<leader>t",
      mappings = config.defaults.mappings,
      default_theme = "kanagawa-paper-ink",
      bookmark_group = true,
      recent_group = true,
      theme_map = nil,
      filetype_themes = {},
      project_themes = {},
      filetype_overrides_project = false,
      project_overrides_filetype = true,
      profiles = {},
      current_profile = nil,
      profile_scoped_state = false,
      sort_mode = "alpha",
      custom_sorts = {},
      theme_aliases = {},
      group_aliases = {},
      history_max_size = 13,
      sample_preview = {
        enabled = true,
        relative_size = 0.5,
        languages = nil,
      },
      group_indent = 2,
      icons = config.defaults.icons,
      on_apply = config.defaults.on_apply,
      enable_autocmds = true,
      enable_commands = true,
      enable_keymaps = true,
      enable_picker = true,
    },
    presentation = {
      leader = "<leader>t",
      mappings = {
        picker = "p",
        next = ">",
        previous = "<",
        others = "/",
        auto = "a",
        refresh = "R",
        status = "s",
      },
      default_theme = "default",
      bookmark_group = false,
      recent_group = false,
      theme_map = nil,
      filetype_themes = {},
      project_themes = {},
      filetype_overrides_project = false,
      project_overrides_filetype = true,
      profiles = {},
      current_profile = nil,
      profile_scoped_state = false,
      sort_mode = "alpha",
      custom_sorts = {},
      theme_aliases = {},
      group_aliases = {},
      history_max_size = 5,
      sample_preview = {
        enabled = false,
        relative_size = 0.5,
        languages = nil,
      },
      group_indent = 2,
      icons = config.defaults.icons,
      on_apply = config.defaults.on_apply,
      enable_autocmds = false,
      enable_commands = true,
      enable_keymaps = true,
      enable_picker = true,
    },
  }

  return presets
end

--- Apply a preset configuration
---
---@param preset_name string Name of the preset to apply
---@param core_module table The core module to update
---@return boolean success Whether the preset was applied successfully
function M.apply_preset(preset_name, core_module)
  local presets = M.get_presets()
  local preset = presets[preset_name]

  if not preset then
    vim.notify("raphael: unknown preset '" .. preset_name .. "'", vim.log.levels.ERROR)
    return false
  end

  local validated_config = config.validate(preset)
  if not validated_config then
    vim.notify("raphael: failed to validate preset '" .. preset_name .. "'", vim.log.levels.ERROR)
    return false
  end

  core_module.base_config = validated_config
  local profile_name = core_module.state and core_module.state.current_profile or nil
  core_module.config = core_module.get_profile_config and core_module.get_profile_config(profile_name)
    or validated_config

  vim.notify("raphael: applied preset '" .. preset_name .. "'", vim.log.levels.INFO)
  return true
end

return M
