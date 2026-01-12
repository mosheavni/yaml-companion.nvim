local config = require("yaml-companion.config")
local modeline = require("yaml-companion.modeline")

local M = {}

-- Cache for api-resources lookup
M._api_resources_cache = {}

--- Check if kubectl is available
---@return boolean
function M.is_available()
  return vim.fn.executable("kubectl") == 1
end

--- Get the current kubectl context name
---@return string|nil context_name, string|nil error
function M.get_context_name()
  local result = vim.system({ "kubectl", "config", "current-context" }, { text = true }):wait()
  if result.code ~= 0 then
    return nil, result.stderr or "Failed to get kubectl context"
  end
  local context = vim.trim(result.stdout or "")
  if context == "" then
    return nil, "Empty context name"
  end
  return context, nil
end

--- Get cache directory path (creates if needed)
---@return string
function M.get_cache_dir()
  local base_dir = config.options.cluster_crds.cache_dir
    or (vim.fn.stdpath("data") .. "/yaml-companion.nvim/crd-cache/")

  -- Include context name in path for isolation
  local context = M.get_context_name() or "default"
  -- Sanitize context name for filesystem
  context = context:gsub("[^%w%-_.]", "_")

  local dir = base_dir .. context .. "/"

  -- Create directory if it doesn't exist
  vim.fn.mkdir(dir, "p")

  return dir
end

--- Get path to cached schema file
---@param crd_name string
---@return string
function M.get_cache_path(crd_name)
  return M.get_cache_dir() .. crd_name .. ".json"
end

--- Check if cache is still valid
---@param crd_name string
---@return boolean
function M.is_cache_valid(crd_name)
  local path = M.get_cache_path(crd_name)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return false
  end

  local ttl = config.options.cluster_crds.cache_ttl
  if ttl == 0 then
    return true -- Never expire
  end

  return (os.time() - stat.mtime.sec) < ttl
end

--- Get cached schema from disk
---@param crd_name string
---@return table|nil schema, string|nil error
function M.get_cached_schema(crd_name)
  local path = M.get_cache_path(crd_name)

  local file = io.open(path, "r")
  if not file then
    return nil, "Cache file not found"
  end

  local content = file:read("*a")
  file:close()

  local ok, schema = pcall(vim.fn.json_decode, content)
  if not ok then
    return nil, "Failed to parse cached schema"
  end

  return schema, nil
end

--- Cache schema to disk
---@param crd_name string
---@param schema table
---@return string|nil path, string|nil error
function M.cache_schema(crd_name, schema)
  local path = M.get_cache_path(crd_name)

  local ok, json = pcall(vim.fn.json_encode, schema)
  if not ok then
    return nil, "Failed to encode schema to JSON"
  end

  local file = io.open(path, "w")
  if not file then
    return nil, "Failed to open cache file for writing"
  end

  file:write(json)
  file:close()

  return path, nil
end

--- Extract the stored version's schema from CRD JSON
---@param crd_json table Parsed CRD JSON
---@return table|nil schema, string|nil version
local function extract_stored_schema(crd_json)
  local versions = crd_json.spec and crd_json.spec.versions
  if not versions or #versions == 0 then
    return nil, nil
  end

  -- Find version with storage=true
  for _, v in ipairs(versions) do
    if v.storage then
      return v.schema and v.schema.openAPIV3Schema, v.name
    end
  end

  -- Fallback to first served version
  for _, v in ipairs(versions) do
    if v.served then
      return v.schema and v.schema.openAPIV3Schema, v.name
    end
  end

  -- Last resort: first version
  local v = versions[1]
  return v.schema and v.schema.openAPIV3Schema, v.name
end

--- List all CRDs in cluster
---@param callback fun(crds: {name: string}[]|nil, error: string|nil)
function M.list_all_crds(callback)
  vim.system(
    { "kubectl", "get", "crd", "-o", "jsonpath={.items[*].metadata.name}" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(nil, result.stderr or "kubectl failed")
          return
        end

        local names = vim.split(vim.trim(result.stdout or ""), " ")
        local crds = {}
        for _, name in ipairs(names) do
          if name ~= "" then
            table.insert(crds, { name = name })
          end
        end
        callback(crds, nil)
      end)
    end
  )
end

--- Fetch CRD schema from cluster
---@param crd_name string e.g., "applications.argoproj.io"
---@param callback fun(result: {name: string, schema: table, version: string}|nil, error: string|nil)
function M.fetch_crd_schema(crd_name, callback)
  vim.system({ "kubectl", "get", "crd", crd_name, "-o", "json" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local err = result.stderr or "kubectl failed"
        if err:find("NotFound") or err:find("not found") then
          callback(nil, string.format("CRD '%s' not found in cluster", crd_name))
        else
          callback(nil, err)
        end
        return
      end

      local ok, crd_json = pcall(vim.fn.json_decode, result.stdout)
      if not ok or not crd_json then
        callback(nil, "Failed to parse CRD JSON")
        return
      end

      local schema, version = extract_stored_schema(crd_json)
      if not schema then
        callback(nil, string.format("CRD '%s' has no OpenAPI schema", crd_name))
        return
      end

      callback({
        name = crd_name,
        schema = schema,
        version = version,
      }, nil)
    end)
  end)
end

--- Get CRD name from kind and apiGroup using api-resources
--- CRD naming convention: <plural>.<group> (e.g., "applications.argoproj.io")
---@param api_group string e.g., "argoproj.io"
---@param kind string e.g., "Application"
---@param callback fun(crd_name: string|nil, error: string|nil)
function M.get_crd_name(api_group, kind, callback)
  -- Check cache first
  local cache_key = api_group .. "/" .. kind
  if M._api_resources_cache[cache_key] then
    callback(M._api_resources_cache[cache_key], nil)
    return
  end

  vim.system(
    { "kubectl", "api-resources", "--api-group=" .. api_group, "-o", "name" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(nil, result.stderr or "Failed to query api-resources")
          return
        end

        local resources = vim.split(vim.trim(result.stdout or ""), "\n")
        local kind_lower = kind:lower()

        for _, resource in ipairs(resources) do
          -- resource format: "applications.argoproj.io" or "pods"
          -- We need to match the kind (singular form) to the resource name (plural form)
          local resource_name = resource:match("^([^.]+)")
          if resource_name then
            -- Simple pluralization check: kind matches start of resource name
            -- e.g., "Application" -> "applications", "Certificate" -> "certificates"
            if resource_name:lower():find("^" .. kind_lower) then
              M._api_resources_cache[cache_key] = resource
              callback(resource, nil)
              return
            end
          end
        end

        -- Fallback: try constructing the name directly
        -- Common pattern: lowercase(kind) + "s" + "." + group
        local guessed_name = kind_lower .. "s." .. api_group
        M._api_resources_cache[cache_key] = guessed_name
        callback(guessed_name, nil)
      end)
    end
  )
end

--- Fetch CRD schema and add modeline to buffer
---@param bufnr number
---@param crd_name string
---@param line_number? number Line number for modeline (default: 1)
function M.fetch_and_add_modeline(bufnr, crd_name, line_number)
  line_number = line_number or 1

  -- Check cache first
  if M.is_cache_valid(crd_name) then
    local cached_path = M.get_cache_path(crd_name)
    local url = "file://" .. cached_path
    local success = modeline.set_modeline(bufnr, url, line_number, false)
    if success then
      vim.notify(
        string.format("Added modeline for %s (cached)", crd_name),
        vim.log.levels.INFO,
        { title = "yaml-companion" }
      )
    end
    return
  end

  vim.notify(
    string.format("Fetching schema for %s...", crd_name),
    vim.log.levels.INFO,
    { title = "yaml-companion" }
  )

  M.fetch_crd_schema(crd_name, function(result, err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "yaml-companion" })
      return
    end

    if not result then
      vim.notify("No schema returned", vim.log.levels.ERROR, { title = "yaml-companion" })
      return
    end

    -- Cache the schema
    local cached_path, cache_err = M.cache_schema(crd_name, result.schema)
    if cache_err then
      vim.notify(
        "Failed to cache schema: " .. cache_err,
        vim.log.levels.WARN,
        { title = "yaml-companion" }
      )
      return
    end

    -- Add modeline with file:// URL
    local url = "file://" .. cached_path
    local success = modeline.set_modeline(bufnr, url, line_number, false)
    if success then
      vim.notify(
        string.format("Added modeline for %s", crd_name),
        vim.log.levels.INFO,
        { title = "yaml-companion" }
      )
    else
      vim.notify("Failed to add modeline", vim.log.levels.ERROR, { title = "yaml-companion" })
    end
  end)
end

--- Detect CRDs in current buffer and fetch schemas from cluster
---@param bufnr? number
function M.fetch_from_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not M.is_available() then
    vim.notify(
      "kubectl not found. Install kubectl to use cluster CRD features",
      vim.log.levels.ERROR,
      { title = "yaml-companion" }
    )
    return
  end

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

  local crd_detector = require("yaml-companion.modeline.crd_detector")
  local crds = crd_detector.detect_crds(bufnr)

  local non_core_crds = vim.tbl_filter(function(crd)
    return not crd.is_core
  end, crds)

  if #non_core_crds == 0 then
    vim.notify("No CRDs detected in buffer", vim.log.levels.INFO, { title = "yaml-companion" })
    return
  end

  -- If single CRD, fetch directly
  if #non_core_crds == 1 then
    local crd = non_core_crds[1]
    M.get_crd_name(crd.apiGroup, crd.kind, function(crd_name, err)
      if err then
        vim.notify(
          "Failed to determine CRD name: " .. err,
          vim.log.levels.ERROR,
          { title = "yaml-companion" }
        )
        return
      end
      M.fetch_and_add_modeline(bufnr, crd_name, crd.line_number)
    end)
    return
  end

  -- Multiple CRDs: let user choose
  vim.ui.select(non_core_crds, {
    prompt = "Select CRD to fetch from cluster: ",
    format_item = function(crd)
      return string.format("%s (%s)", crd.kind, crd.apiVersion)
    end,
  }, function(selection)
    if not selection then
      return
    end
    M.get_crd_name(selection.apiGroup, selection.kind, function(crd_name, err)
      if err then
        vim.notify(
          "Failed to determine CRD name: " .. err,
          vim.log.levels.ERROR,
          { title = "yaml-companion" }
        )
        return
      end
      M.fetch_and_add_modeline(bufnr, crd_name, selection.line_number)
    end)
  end)
end

--- Browse all CRDs in cluster and select one
function M.open_crd_select()
  if not M.is_available() then
    vim.notify(
      "kubectl not found. Install kubectl to use cluster CRD features",
      vim.log.levels.ERROR,
      { title = "yaml-companion" }
    )
    return
  end

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

  vim.notify("Fetching CRDs from cluster...", vim.log.levels.INFO, { title = "yaml-companion" })

  M.list_all_crds(function(crds, err)
    if err then
      vim.notify("Failed to list CRDs: " .. err, vim.log.levels.ERROR, { title = "yaml-companion" })
      return
    end

    if not crds or #crds == 0 then
      vim.notify("No CRDs found in cluster", vim.log.levels.WARN, { title = "yaml-companion" })
      return
    end

    vim.ui.select(crds, {
      prompt = "Select Cluster CRD: ",
      format_item = function(crd)
        return string.format("[cluster] %s", crd.name)
      end,
    }, function(selection)
      if not selection then
        return
      end
      M.fetch_and_add_modeline(bufnr, selection.name, 1)
    end)
  end)
end

--- Clear the api-resources cache
function M.clear_cache()
  M._api_resources_cache = {}
end

--- Health check for kubectl integration
function M.health()
  local health = vim.health

  if not config.options.cluster_crds or not config.options.cluster_crds.enabled then
    health.info("Cluster CRD features disabled")
    return
  end

  -- Check kubectl availability
  if M.is_available() then
    health.ok("kubectl is available")

    -- Check cluster access
    local context = M.get_context_name()
    if context then
      health.ok("kubectl context: " .. context)
    else
      health.warn("Could not determine kubectl context")
    end
  else
    health.warn("kubectl is not available", { "Install kubectl to use cluster CRD features" })
  end

  -- Check cache directory
  local cache_dir = M.get_cache_dir()
  local stat = vim.uv.fs_stat(cache_dir)
  if stat then
    health.ok("Cache directory exists: " .. cache_dir)
  else
    health.info("Cache directory will be created: " .. cache_dir)
  end
end

return M
