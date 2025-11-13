local M = {}

M.lua = [[
-- Configuration module
local config = require("module.config")

---@class MyClass
---@field name string
---@field count number
local MyClass = {}

-- Constructor
function MyClass:new(name)
  local instance = setmetatable({}, { __index = self })
  instance.name = name or "default"
  instance.count = 0
  return instance
end

-- Process data with error handling
function MyClass:process(data)
  if not data then
    error("Data cannot be nil")
  end

  self.count = self.count + 1
  local result = string.format("Processed: %s", data)

  -- TODO: Add validation
  return result
end

-- Deprecated function
---@deprecated Use process() instead
function MyClass:old_method()
  vim.notify("This is deprecated!", vim.log.levels.WARN)
end

return MyClass
]]

M.python = [[
# Data processing module
import asyncio
from typing import List, Optional, Dict
from dataclasses import dataclass

@dataclass
class Config:
    """Configuration settings"""
    name: str
    timeout: int = 30
    enabled: bool = True

class DataProcessor:
    def __init__(self, config: Config):
        self.config = config
        self._cache: Dict[str, any] = {}

    async def process(self, items: List[str]) -> Optional[List]:
        """Process items asynchronously"""
        if not items:
            raise ValueError("Items cannot be empty")

        results = []
        for item in items:
            # TODO: Optimize this loop
            result = await self._fetch_data(item)
            results.append(result)

        return results

    def _fetch_data(self, key: str) -> dict:
        """Fetch from cache or generate"""
        return self._cache.get(key, {"status": "new"})

# FIXME: Handle edge cases
]]

M.javascript = [[
// API service module
import { Config } from './config';
import type { User, Response } from './types';

/**
 * Service for handling API requests
 * @class ApiService
 */
export class ApiService {
  private readonly baseUrl: string;
  private cache: Map<string, any>;

  constructor(config: Config) {
    this.baseUrl = config.apiUrl;
    this.cache = new Map();
  }

  /**
   * Fetch user data
   * @deprecated Use fetchUserV2 instead
   */
  async fetchUser(id: number): Promise<User | null> {
    if (id <= 0) {
      throw new Error('Invalid user ID');
    }

    const cached = this.cache.get(`user_${id}`);
    if (cached) return cached;

    // TODO: Add retry logic
    const response = await fetch(`${this.baseUrl}/users/${id}`);
    return response.json();
  }
}

// FIXME: Add error boundary
]]

M.rust = [[
// Data structure module
use std::collections::HashMap;
use serde::{Deserialize, Serialize};

/// Configuration struct
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub name: String,
    pub count: u32,
    pub enabled: bool,
}

/// Main processor
pub struct Processor {
    config: Config,
    cache: HashMap<String, Vec<u8>>,
}

impl Processor {
    /// Create new processor
    pub fn new(config: Config) -> Self {
        Self {
            config,
            cache: HashMap::new(),
        }
    }

    /// Process data with error handling
    pub fn process(&mut self, data: &str) -> Result<String, Box<dyn std::error::Error>> {
        if data.is_empty() {
            return Err("Data cannot be empty".into());
        }

        // TODO: Optimize allocation
        let result = format!("Processed: {}", data);
        Ok(result)
    }
}

// FIXME: Add lifetime parameters
]]

M.go = [[
// Package processor handles data processing
package processor

import (
	"context"
	"errors"
	"fmt"
)

// Config holds configuration
type Config struct {
	Name    string
	Timeout int
	Enabled bool
}

// Processor handles data operations
type Processor struct {
	config Config
	cache  map[string]interface{}
}

// NewProcessor creates a new processor
func NewProcessor(cfg Config) *Processor {
	return &Processor{
		config: cfg,
		cache:  make(map[string]interface{}),
	}
}

// Process processes the input data
// Deprecated: Use ProcessV2 instead
func (p *Processor) Process(ctx context.Context, data string) (string, error) {
	if data == "" {
		return "", errors.New("data cannot be empty")
	}

	// TODO: Add validation
	result := fmt.Sprintf("Processed: %s", data)
	return result, nil
}

// FIXME: Handle context cancellation
]]

M.ruby = [[
# Data processing module
require 'json'
require 'logger'

module DataProcessor
  # Configuration class
  class Config
    attr_accessor :name, :timeout, :enabled

    def initialize(name)
      @name = name
      @timeout = 30
      @enabled = true
    end
  end

  # Main processor class
  class Processor
    def initialize(config)
      @config = config
      @cache = {}
      @logger = Logger.new(STDOUT)
    end

    # Process data with validation
    # @deprecated Use process_v2 instead
    def process(data)
      raise ArgumentError, 'Data cannot be nil' if data.nil?

      @logger.info "Processing: #{data}"

      # TODO: Add retry logic
      result = "Processed: #{data}"
      @cache[data] = result

      result
    rescue StandardError => e
      @logger.error "Error: #{e.message}"
      nil
    end
  end
end

# FIXME: Add thread safety
]]

M.sh = [[
#!/bin/bash
# Data processing script

set -euo pipefail

# Configuration
readonly CONFIG_NAME="processor"
readonly TIMEOUT=30
ENABLED=true

# Cache directory
CACHE_DIR="/tmp/cache"

# Initialize logging
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Process data with validation
# DEPRECATED: Use process_v2 instead
process_data() {
    local data="$1"

    if [[ -z "$data" \]\]; then
        log_error "Data cannot be empty"
        return 1
    fi

    # TODO: Add retry logic
    local result="Processed: $data"
    echo "$result" > "$CACHE_DIR/$data"

    echo "$result"
}

# Main execution
main() {
    process_data "example"
}

# FIXME: Add error handling
main "$@"
]]

M.sql = [[
-- Database schema and queries

-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for faster lookups
CREATE INDEX idx_users_email ON users(email);

-- Insert sample data
INSERT INTO users (username, email)
VALUES ('john_doe', 'john@example.com')
ON CONFLICT (username) DO NOTHING;

-- Complex query with joins
SELECT
    u.username,
    u.email,
    COUNT(o.id) as order_count,
    SUM(o.total) as total_spent
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.created_at > '2024-01-01'
    AND u.email LIKE '%@example.com'
GROUP BY u.id, u.username, u.email
HAVING COUNT(o.id) > 0
ORDER BY total_spent DESC
LIMIT 10;

-- TODO: Add materialized view
-- FIXME: Optimize query performance
]]

M.languages = {
  { name = "lua", display = "Lua", ft = "lua" },
  { name = "python", display = "Python", ft = "python" },
  { name = "javascript", display = "JavaScript", ft = "javascript" },
  { name = "rust", display = "Rust", ft = "rust" },
  { name = "go", display = "Go", ft = "go" },
  { name = "ruby", display = "Ruby", ft = "ruby" },
  { name = "sh", display = "Shell", ft = "sh" },
  { name = "sql", display = "SQL", ft = "sql" },
}

function M.get_sample(lang_name)
  return M[lang_name] or M.lua
end

function M.get_language_info(lang_name)
  for _, lang in ipairs(M.languages) do
    if lang.name == lang_name then
      return lang
    end
  end
  return M.languages[1]
end

function M.get_next_language(current_lang)
  for i, lang in ipairs(M.languages) do
    if lang.name == current_lang then
      local next_idx = (i % #M.languages) + 1
      return M.languages[next_idx].name
    end
  end
  return M.languages[1].name
end

function M.get_previous_language(current_lang)
  for i, lang in ipairs(M.languages) do
    if lang.name == current_lang then
      local prev_idx = (i - 2) % #M.languages + 1
      return M.languages[prev_idx].name
    end
  end
  return M.languages[#M.languages].name
end

return M
