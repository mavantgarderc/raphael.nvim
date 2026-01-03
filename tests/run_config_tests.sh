#!/bin/bash
# run_config_tests.sh
# Script to run the configuration management tests (safe version)

echo "Running configuration management tests for raphael.nvim..."

# Run the safe test runner that doesn't modify the real cache
nvim --headless -c "luafile tests/safe_test_runner.lua" -c "qa"

if [ $? -eq 0 ]; then
    echo "All configuration management tests passed!"
    echo "Note: These tests don't modify the real cache, so your configuration is safe."
else
    echo "Some configuration management tests failed!"
    exit 1
fi