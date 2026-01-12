local modeline = require("yaml-companion.modeline")
local config = require("yaml-companion.config")
local notify = require("yaml-companion.util.notify")

local M = {}

--- Parse apiVersion to extract group and version
---@param api_version string e.g., "argoproj.io/v1alpha1" or "v1"
---@return string group, string version
function M.parse_api_version(api_version)
  if not api_version then
    return "", ""
  end

  if api_version:find("/") then
    local group, version = api_version:match("(.+)/(.+)")
    return group or "", version or ""
  else
    -- Core API version like "v1"
    return "", api_version
  end
end

--- Check if an API group is a core Kubernetes group
---@param api_group string
---@return boolean
function M.is_core_api_group(api_group)
  return config.options.core_api_groups[api_group] == true
end

--- Detect all CRDs in a buffer
---@param bufnr number
---@return CRDInfo[]
function M.detect_crds(bufnr)
  local lines = modeline.get_buf_lines(bufnr)
  if not lines then
    return {}
  end

  local resources = {}
  local current = { line_number = 1 }
  local first_line_is_separator = lines[1] and lines[1]:match("^%-%-%-")

  for i, line in ipairs(lines) do
    if line:match("^kind:") then
      current.kind = line:match("^kind:%s*(.+)")
    elseif line:match("^apiVersion:") then
      current.apiVersion = line:match("^apiVersion:%s*(.+)")
    elseif line:match("^%-%-%-") then
      -- Document separator - save current and start new
      if current.kind and current.apiVersion then
        local group, version = M.parse_api_version(current.apiVersion)
        table.insert(resources, {
          kind = current.kind,
          apiVersion = current.apiVersion,
          apiGroup = group,
          version = version,
          line_number = current.line_number,
          end_line = i - 1, -- Line before the separator
          is_core = M.is_core_api_group(group),
        })
      end
      current = { line_number = i + 1 }
    end
  end

  -- Handle last document
  if current.kind and current.apiVersion then
    local group, version = M.parse_api_version(current.apiVersion)
    table.insert(resources, {
      kind = current.kind,
      apiVersion = current.apiVersion,
      apiGroup = group,
      version = version,
      line_number = current.line_number,
      end_line = #lines, -- End of buffer
      is_core = M.is_core_api_group(group),
    })
  end

  -- Adjust line numbers if first line was a separator
  if first_line_is_separator then
    for _, resource in ipairs(resources) do
      if resource.line_number == 1 then
        resource.line_number = 1
      end
    end
  end

  return resources
end

--- Build Datree schema URL for a CRD
---@param crd CRDInfo
---@return string|nil nil if core resource
function M.build_crd_schema_url(crd)
  if crd.is_core or crd.apiGroup == "" then
    return nil
  end

  -- Format: {apiGroup}/{kind}_{version}.json
  local path = string.format("%s/%s_%s.json", crd.apiGroup, crd.kind:lower(), crd.version)
  return config.options.datree.raw_content_base .. path
end

--- Helper: Notify about added modelines if enabled
---@param added_kinds string[]
---@param dry_run boolean
local function notify_added_kinds(added_kinds, dry_run)
  local opts = config.options
  local should_notify = opts.modeline and opts.modeline.notify ~= false
  if not dry_run and #added_kinds > 0 and should_notify then
    notify.info("Added modelines for: " .. table.concat(added_kinds, ", "))
  end
end

--- Add modelines for all detected non-core CRDs
---@param bufnr number
---@param options? { dry_run: boolean, overwrite: boolean }
---@return AddModelinesResult
function M.add_modelines(bufnr, options)
  options = options or {}

  local result = {
    added = 0,
    skipped = 0,
    errors = {},
  }

  if not vim.api.nvim_buf_is_valid(bufnr) then
    table.insert(result.errors, "Invalid buffer")
    return result
  end

  local crds = M.detect_crds(bufnr)
  if #crds == 0 then
    return result
  end

  -- Track line offset as we insert modelines
  local offset = 0
  local added_kinds = {}

  for _, crd in ipairs(crds) do
    if crd.is_core then
      result.skipped = result.skipped + 1
    else
      local url = M.build_crd_schema_url(crd)
      if not url then
        result.skipped = result.skipped + 1
      else
        -- Calculate target line and document end (accounting for previously added modelines)
        local target_line = crd.line_number + offset
        local end_line = crd.end_line + offset

        -- Check if modeline for this SPECIFIC URL already exists in this document
        local existing = modeline.find_modeline_with_url(bufnr, url, target_line, end_line)

        if existing and not options.overwrite then
          result.skipped = result.skipped + 1
        else
          if options.dry_run then
            notify.info(
              string.format("Would add modeline for %s at line %d", crd.kind, target_line)
            )
            result.added = result.added + 1
          else
            local success, offset_delta =
              modeline.set_modeline_in_range(bufnr, url, target_line, end_line, options.overwrite)
            if success then
              result.added = result.added + 1
              offset = offset + offset_delta
              table.insert(added_kinds, crd.kind)
            else
              table.insert(result.errors, "Failed to add modeline for " .. crd.kind)
            end
          end
        end
      end
    end
  end

  notify_added_kinds(added_kinds, options.dry_run)

  return result
end

--- Validate if a URL exists via HTTP HEAD request (async)
---@param url string
---@param callback fun(exists: boolean)
function M.validate_url(url, callback)
  vim.system({
    "curl",
    "--head",
    "--silent",
    "--fail",
    "--location",
    "-o",
    "/dev/null",
    "-w",
    "%{http_code}",
    url,
  }, { text = true }, function(result)
    vim.schedule(function()
      local http_code = vim.trim(result.stdout or "")
      local exists = result.code == 0
        and (http_code == "200" or http_code == "302" or http_code == "301")
      callback(exists)
    end)
  end)
end

--- Try to add modeline from cluster for a single CRD (async)
--- Used when Datree fallback is enabled
--- Checks cache first (without cluster access), then falls back to cluster if needed
---@param bufnr number
---@param crd CRDInfo
---@param target_line number
---@param callback fun(success: boolean, error: string|nil)
function M.try_cluster_fallback(bufnr, crd, target_line, callback)
  local kubectl = require("yaml-companion.kubectl")

  -- First, try to use cached schema without any cluster calls
  -- Construct likely CRD name using common naming convention
  local guessed_crd_name = kubectl.construct_crd_name(crd.apiGroup, crd.kind)

  -- Check cache with guessed name (no cluster access required)
  if kubectl.is_cache_valid(guessed_crd_name) then
    local cached_path = kubectl.get_cache_path(guessed_crd_name)
    local url = "file://" .. cached_path
    local success = modeline.set_modeline(bufnr, url, target_line, false)
    callback(success, nil)
    return
  end

  -- Cache miss - now we need cluster access
  if not kubectl.is_available() then
    callback(false, "kubectl not available and no cached schema found")
    return
  end

  -- Get exact CRD name from cluster (may differ from guessed name for irregular plurals)
  kubectl.get_crd_name(crd.apiGroup, crd.kind, function(crd_name, err)
    if err or not crd_name then
      callback(false, err or "Could not determine CRD name")
      return
    end

    -- Check cache again with exact name (in case it differs from guessed name)
    if crd_name ~= guessed_crd_name and kubectl.is_cache_valid(crd_name) then
      local cached_path = kubectl.get_cache_path(crd_name)
      local url = "file://" .. cached_path
      local success = modeline.set_modeline(bufnr, url, target_line, false)
      callback(success, nil)
      return
    end

    -- Fetch from cluster
    kubectl.fetch_crd_schema(crd_name, function(fetch_result, fetch_err)
      if fetch_err or not fetch_result then
        callback(false, fetch_err or "Failed to fetch CRD schema")
        return
      end

      -- Cache the schema
      local cached_path, cache_err = kubectl.cache_schema(crd_name, fetch_result.schema)
      if cache_err or not cached_path then
        callback(false, cache_err or "Failed to cache schema")
        return
      end

      -- Add modeline with file:// URL
      local url = "file://" .. cached_path
      local success = modeline.set_modeline(bufnr, url, target_line, false)
      callback(success, nil)
    end)
  end)
end

--- Add modelines with cluster fallback support (async)
--- If fallback is enabled and Datree URL doesn't exist, tries to fetch from cluster
---@param bufnr number
---@param options? { dry_run: boolean, overwrite: boolean }
---@param callback? fun(result: AddModelinesResult)
function M.add_modelines_with_fallback(bufnr, options, callback)
  options = options or {}
  callback = callback or function() end

  -- If fallback is not enabled, use sync version
  if not config.options.cluster_crds or not config.options.cluster_crds.fallback then
    local result = M.add_modelines(bufnr, options)
    callback(result)
    return
  end

  local result = {
    added = 0,
    skipped = 0,
    errors = {},
  }

  if not vim.api.nvim_buf_is_valid(bufnr) then
    table.insert(result.errors, "Invalid buffer")
    callback(result)
    return
  end

  local crds = M.detect_crds(bufnr)
  if #crds == 0 then
    callback(result)
    return
  end

  -- Filter to non-core CRDs
  local non_core_crds = {}
  for _, crd in ipairs(crds) do
    if crd.is_core then
      result.skipped = result.skipped + 1
    else
      table.insert(non_core_crds, crd)
    end
  end

  if #non_core_crds == 0 then
    callback(result)
    return
  end

  -- State for sequential processing
  local offset = 0
  local added_kinds = {}
  local idx = 1

  -- Handler for successful modeline addition
  local function on_modeline_added(kind, offset_delta)
    result.added = result.added + 1
    offset = offset + offset_delta
    table.insert(added_kinds, kind)
  end

  -- Handler for when fallback fails
  local function on_fallback_failed(kind, err)
    result.skipped = result.skipped + 1
    if err then
      table.insert(result.errors, string.format("Fallback failed for %s: %s", kind, err))
    end
  end

  -- Forward declaration
  local process_next

  -- Process CRD with Datree URL (validates and falls back if needed)
  local function process_with_datree_url(crd, target_line, end_line, datree_url)
    local should_validate = config.options.modeline and config.options.modeline.validate_urls

    local function use_datree_url()
      local success, offset_delta =
        modeline.set_modeline_in_range(bufnr, datree_url, target_line, end_line, options.overwrite)
      if success then
        on_modeline_added(crd.kind, offset_delta)
      else
        table.insert(result.errors, "Failed to add modeline for " .. crd.kind)
      end
      idx = idx + 1
      process_next()
    end

    local function try_fallback()
      M.try_cluster_fallback(bufnr, crd, target_line, function(success, err)
        if success then
          on_modeline_added(crd.kind, 1)
        else
          on_fallback_failed(crd.kind, err and "Datree URL not found and " .. err or nil)
        end
        idx = idx + 1
        process_next()
      end)
    end

    if should_validate then
      M.validate_url(datree_url, function(exists)
        if exists then
          use_datree_url()
        else
          try_fallback()
        end
      end)
    else
      use_datree_url()
    end
  end

  -- Process CRD with cluster fallback only (no Datree URL)
  local function process_with_fallback_only(crd, target_line)
    M.try_cluster_fallback(bufnr, crd, target_line, function(success, err)
      if success then
        on_modeline_added(crd.kind, 1)
      else
        on_fallback_failed(crd.kind, err)
      end
      idx = idx + 1
      process_next()
    end)
  end

  -- Main processing loop (recursive to handle async)
  process_next = function()
    if idx > #non_core_crds then
      -- Done processing all CRDs
      notify_added_kinds(added_kinds, options.dry_run)
      callback(result)
      return
    end

    local crd = non_core_crds[idx]
    local target_line = crd.line_number + offset
    local end_line = crd.end_line + offset

    -- Build URL to check for matching modeline
    local datree_url = M.build_crd_schema_url(crd)

    -- If we have a datree URL, check if this exact modeline already exists
    if datree_url then
      local existing = modeline.find_modeline_with_url(bufnr, datree_url, target_line, end_line)

      -- Skip if exists and not overwriting
      if existing and not options.overwrite then
        result.skipped = result.skipped + 1
        idx = idx + 1
        process_next()
        return
      end
    end

    -- Handle dry run
    if options.dry_run then
      notify.info(string.format("Would add modeline for %s at line %d", crd.kind, target_line))
      result.added = result.added + 1
      idx = idx + 1
      process_next()
      return
    end

    -- Try Datree URL first, then fallback to cluster
    if datree_url then
      process_with_datree_url(crd, target_line, end_line, datree_url)
    else
      process_with_fallback_only(crd, target_line)
    end
  end

  process_next()
end

--- Health check
function M.health()
  local health = vim.health

  health.ok("CRD detector loaded")

  local count = 0
  for _ in pairs(config.options.core_api_groups) do
    count = count + 1
  end
  health.info(string.format("%d core API groups configured", count))
end

return M
