local config = require("yaml-companion.config")
local cache = require("yaml-companion.cache")
local notify = require("yaml-companion.util.notify")

local M = {}

local GITHUB_TREE_URL =
  "https://api.github.com/repos/datreeio/CRDs-catalog/git/trees/main?recursive=1"

local CACHE_SUBDIR = "datree"
local CACHE_FILENAME = "datree-catalog.json"

--- Get cache directory path (creates if needed)
---@return string
function M.get_cache_dir()
  return cache.get_dir(CACHE_SUBDIR)
end

--- Get path to cached catalog file
---@return string
function M.get_cache_path()
  return cache.get_path(CACHE_SUBDIR, CACHE_FILENAME)
end

--- Check if file cache is still valid
---@return boolean
local function is_file_cache_valid()
  local path = M.get_cache_path()
  local ttl = config.options.datree.cache_ttl
  return cache.is_valid(path, ttl)
end

--- Load cache from file
---@return DatreeCache|nil cache_data, string|nil error
local function load_file_cache()
  return cache.load_json(M.get_cache_path())
end

--- Save cache to file
---@param cache_data DatreeCache
---@return boolean success, string|nil error
local function save_file_cache(cache_data)
  return cache.save_json(M.get_cache_path(), cache_data)
end

--- Build a display name from a catalog path
---@param path string
---@return string
local function build_display_name(path)
  -- Convert "argoproj.io/application_v1alpha1.json" to "[datreeio] argoproj.io-application-v1alpha1"
  local name = path:gsub("%.json$", ""):gsub("/", "-"):gsub("_", "-")
  return "[datreeio] " .. name
end

--- Build a schema URL from a catalog path
---@param path string
---@return string
function M.build_schema_url(path)
  return config.options.datree.raw_content_base .. path
end

--- Parse GitHub API tree response and extract JSON schema entries
---@param json_str string
---@return DatreeCatalogEntry[]|nil, string|nil error
local function parse_tree_response(json_str)
  local ok, data = pcall(vim.fn.json_decode, json_str)
  if not ok or not data then
    return nil, "Failed to parse JSON response"
  end

  if not data.tree then
    return nil, "No tree field in response"
  end

  local entries = {}
  for _, item in ipairs(data.tree) do
    if item.type == "blob" and item.path:match("%.json$") then
      table.insert(entries, {
        path = item.path,
        name = build_display_name(item.path),
        url = M.build_schema_url(item.path),
      })
    end
  end

  return entries, nil
end

--- Fetch the catalog from GitHub API (async)
--- Uses two-tier caching: file -> network
---@param callback fun(entries: DatreeCatalogEntry[]|nil, error: string|nil)
---@param force_refresh? boolean
function M.fetch_catalog(callback, force_refresh)
  -- 1. Check file cache (avoids network request)
  if not force_refresh and is_file_cache_valid() then
    local file_cache, err = load_file_cache()
    if file_cache and file_cache.entries then
      callback(file_cache.entries, nil)
      return
    end
    -- If file cache failed to load, continue to network fetch
    if err then
      notify.debug("Failed to load cached catalog, fetching from network: " .. err)
    end
  end

  -- 2. Fetch from network
  local headers_args = {
    "-H",
    "Accept: application/vnd.github+json",
    "-H",
    "X-GitHub-Api-Version: 2022-11-28",
  }

  local cmd = vim.list_extend({ "curl", "--location", "--silent", "--fail" }, headers_args)
  table.insert(cmd, GITHUB_TREE_URL)

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "Failed to fetch catalog: " .. (result.stderr or "unknown error"))
        return
      end

      local entries, err = parse_tree_response(result.stdout)
      if err then
        callback(nil, err)
        return
      end

      if not entries then
        callback(nil, "No entries returned from catalog")
        return
      end

      -- Save to file cache
      local cache_data = {
        entries = entries,
        timestamp = os.time(),
      }
      local save_ok, save_err = save_file_cache(cache_data)
      if not save_ok and save_err then
        notify.debug("Failed to save catalog cache: " .. save_err)
      end

      callback(entries, nil)
    end)
  end)
end

--- Filter catalog entries by search term
---@param entries DatreeCatalogEntry[]
---@param query string
---@return DatreeCatalogEntry[]
function M.filter_entries(entries, query)
  if not query or query == "" then
    return entries
  end

  local query_lower = query:lower()
  local filtered = {}

  for _, entry in ipairs(entries) do
    if
      entry.path:lower():find(query_lower, 1, true) or entry.name:lower():find(query_lower, 1, true)
    then
      table.insert(filtered, entry)
    end
  end

  return filtered
end

--- Clear the cached catalog file
function M.clear_cache()
  cache.clear(M.get_cache_path())
end

--- Health check for Datree integration
function M.health()
  local health = vim.health

  -- Check curl availability
  if vim.fn.executable("curl") == 1 then
    health.ok("curl is available")
  else
    health.error("curl is not available", { "Install curl to use Datree CRD catalog" })
  end

  -- Check cache directory
  local cache_dir = M.get_cache_dir()
  local stat = vim.uv.fs_stat(cache_dir)
  if stat then
    health.ok("Cache directory exists: " .. cache_dir)

    -- Check if file cache exists
    local cache_path = M.get_cache_path()
    local cache_stat = vim.uv.fs_stat(cache_path)
    if cache_stat then
      local age = os.time() - cache_stat.mtime.sec
      local ttl = config.options.datree.cache_ttl
      local status = (ttl == 0 or age < ttl) and "valid" or "expired"
      health.ok(string.format("Catalog cache: %s (age: %ds, ttl: %ds)", status, age, ttl))
    else
      health.info("Catalog cache not yet created")
    end
  else
    health.info("Cache directory will be created: " .. cache_dir)
  end
end

return M
