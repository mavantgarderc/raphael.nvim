#!/usr/bin/env lua

-- simple_test_runner.lua
-- A simple test runner for raphael.nvim tests that doesn't require plenary.nvim

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

local function run_testsuite(suite_name, test_func)
  print_header("Running " .. suite_name)
  
  local total_tests = 0
  local passed_tests = 0
  
  -- Capture test results by running the test function
  local success, err = pcall(test_func, 
    function(name, func)
      total_tests = total_tests + 1
      if run_test(name, func) then
        passed_tests = passed_tests + 1
      end
    end
  )
  
  if not success then
    print("Error running testsuite: " .. err)
    return 0, 0
  end
  
  print_header(string.format("Results: %d/%d tests passed", passed_tests, total_tests))
  return passed_tests, total_tests
end

-- Define a simple describe/it implementation for our tests
local function describe(description, test_block)
  print("\n" .. description .. ":")
  
  local tests = {}
  
  local function it(name, test_func)
    table.insert(tests, {name = name, func = test_func})
  end
  
  -- Run the test block to register tests
  test_block(it)
  
  -- Execute registered tests
  for _, test in ipairs(tests) do
    run_test(test.name, test.func)
  end
end

-- Load and run the test files
local function load_test_file(filepath)
  local env = {
    describe = describe,
    it = function(name, func) 
      run_test(name, func)
    end,
    assert = {
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
        if vim then
          if vim.deep_equal(expected, actual) ~= true then
            error(msg or string.format("Expected %s, got %s", vim.inspect(expected), vim.inspect(actual)))
          end
        else
          -- Fallback for basic comparison
          if expected ~= actual then
            error(msg or string.format("Expected %s, got %s", tostring(expected), tostring(actual)))
          end
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
    },
    type = type,
    pcall = pcall,
    os = os,
    io = io,
    string = string,
    table = table,
    pairs = pairs,
    ipairs = ipairs,
    next = next,
    tostring = tostring,
    tonumber = tonumber,
    print = print,
    require = require,
    vim = vim,
    math = math,
  }
  
  local chunk, err = loadfile(filepath, "t", env)
  if not chunk then
    error("Failed to load test file: " .. err)
  end
  
  local success, result = pcall(chunk)
  if not success then
    error("Error running test file: " .. result)
  end
end

-- Main execution
print("Simple Test Runner for raphael.nvim")
print("====================================")

local test_files = {
  "tests/core_test.lua",
  "tests/config_manager_test.lua"
}

local total_passed = 0
local total_tests = 0

for _, test_file in ipairs(test_files) do
  print_header("Loading test file: " .. test_file)
  
  local success, err = pcall(load_test_file, test_file)
  if not success then
    print("Failed to load " .. test_file .. ": " .. err)
  end
end

print("\n" .. string.rep("=", 60))
print("All tests completed!")
print(string.rep("=", 60))