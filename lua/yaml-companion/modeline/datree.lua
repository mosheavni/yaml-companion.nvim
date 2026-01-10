local modeline = require("yaml-companion.modeline")
local config = require("yaml-companion.config")

local M = {}

-- Cache storage
---@type DatreeCache|nil
M._cache = nil

local GITHUB_TREE_URL =
  "https://api.github.com/repos/datreeio/CRDs-catalog/git/trees/main?recursive=1"

--- Check if cache is still valid
---@return boolean
local function is_cache_valid()
  if not M._cache then
    return false
  end
  local ttl = config.options.datree.cache_ttl
  if ttl <= 0 then
    return false
  end
  return (os.time() - M._cache.timestamp) < ttl
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
---@param callback fun(entries: DatreeCatalogEntry[]|nil, error: string|nil)
---@param force_refresh? boolean
function M.fetch_catalog(callback, force_refresh)
  -- Return cached entries if valid
  if not force_refresh and is_cache_valid() then
    callback(M._cache.entries, nil)
    return
  end

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

      -- Update cache
      M._cache = {
        entries = entries,
        timestamp = os.time(),
      }

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

--- Open vim.ui.select with Datree CRD catalog
--- Adds modeline to current buffer on selection
function M.open_select()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Check if buffer is valid YAML file
  local ft = vim.bo[bufnr].filetype
  if not ft:match("^yaml") then
    vim.notify(
      "Current buffer is not a YAML file",
      vim.log.levels.WARN,
      { title = "yaml-companion" }
    )
    return
  end

  vim.notify("Fetching Datree CRD catalog...", vim.log.levels.INFO, { title = "yaml-companion" })

  M.fetch_catalog(function(entries, err)
    if err then
      vim.notify(
        "Failed to fetch catalog: " .. err,
        vim.log.levels.ERROR,
        { title = "yaml-companion" }
      )
      return
    end

    if not entries or #entries == 0 then
      vim.notify("No schemas found in catalog", vim.log.levels.WARN, { title = "yaml-companion" })
      return
    end

    vim.ui.select(entries, {
      prompt = "Select CRD Schema: ",
      format_item = function(entry)
        return entry.name
      end,
    }, function(selection)
      if not selection then
        vim.notify("Schema selection cancelled", vim.log.levels.INFO, { title = "yaml-companion" })
        return
      end

      local success = modeline.set_modeline(bufnr, selection.url, 1, false)
      if success then
        vim.notify(
          "Added schema modeline: " .. selection.name,
          vim.log.levels.INFO,
          { title = "yaml-companion" }
        )
      else
        vim.notify("Failed to add modeline", vim.log.levels.ERROR, { title = "yaml-companion" })
      end
    end)
  end)
end

--- Clear the cached catalog
function M.clear_cache()
  M._cache = nil
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
end

return M
