#!/bin/bash
# Run tests for raphael.nvim using plenary.nvim

echo "Running raphael.nvim tests..."

# Check if plenary is available
nvim --headless -u tests/minimal_init.lua -c "lua require('plenary.test_harness').test_directory('.', {minimal_init = 'tests/minimal_init.lua'})" -c "qa"

if [ $? -eq 0 ]; then
    echo "All tests passed!"
else
    echo "Some tests failed!"
    exit 1
fi