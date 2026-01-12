--- Unified cache operations for yaml-companion
--- Consolidates cache logic from datree.lua and kubectl/init.lua

local M = {}

--- Get base cache directory from config (creates if needed)
---@return string
local function get_base_dir()
  local config = require("yaml-companion.config")
  return config.options.cache_dir or (vim.fn.stdpath("data") .. "/yaml-companion.nvim/")
end

--- Get cache directory path for a subdirectory (creates if needed)
---@param subdir string Subdirectory name (e.g., "datree", "crd-cache/context-name")
---@return string
function M.get_dir(subdir)
  local dir = get_base_dir() .. subdir .. "/"
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Get full path for a cache file
---@param subdir string Subdirectory name
---@param filename string File name
---@return string
function M.get_path(subdir, filename)
  return M.get_dir(subdir) .. filename
end

--- Check if cache file is valid based on TTL
---@param path string Full path to cache file
---@param ttl number TTL in seconds (0 = never expire, <0 = disabled)
---@return boolean
function M.is_valid(path, ttl)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return false
  end

  if ttl == 0 then
    return true -- Never expire
  end
  if ttl < 0 then
    return false -- Disabled
  end

  return (os.time() - stat.mtime.sec) < ttl
end

--- Load JSON from cache file
---@param path string Full path to cache file
---@return table|nil data, string|nil error
function M.load_json(path)
  local file = io.open(path, "r")
  if not file then
    return nil, "Cache file not found"
  end

  local content = file:read("*a")
  file:close()

  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok or not data then
    return nil, "Failed to parse cached JSON"
  end

  return data, nil
end

--- Save JSON to cache file
---@param path string Full path to cache file
---@param data table Data to serialize
---@return boolean success, string|nil error
function M.save_json(path, data)
  local ok, json = pcall(vim.fn.json_encode, data)
  if not ok then
    return false, "Failed to encode data to JSON"
  end

  local file = io.open(path, "w")
  if not file then
    return false, "Failed to open cache file for writing"
  end

  file:write(json)
  file:close()

  return true, nil
end

--- Clear cache file if it exists
---@param path string Full path to cache file
function M.clear(path)
  local stat = vim.uv.fs_stat(path)
  if stat then
    os.remove(path)
  end
end

return M
