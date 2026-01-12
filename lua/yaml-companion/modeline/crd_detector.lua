local modeline = require("yaml-companion.modeline")
local config = require("yaml-companion.config")

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
        -- Calculate target line (accounting for previously added modelines)
        local target_line = crd.line_number + offset

        -- Check if modeline already exists at this position
        local existing = modeline.find_modeline(bufnr, target_line, target_line + 3)

        if existing and not options.overwrite then
          result.skipped = result.skipped + 1
        else
          if options.dry_run then
            vim.notify(
              string.format("Would add modeline for %s at line %d", crd.kind, target_line),
              vim.log.levels.INFO,
              { title = "yaml-companion" }
            )
            result.added = result.added + 1
          else
            local modeline_text = modeline.format_modeline(url)

            if existing and options.overwrite then
              -- Replace existing
              local ok = pcall(
                vim.api.nvim_buf_set_lines,
                bufnr,
                existing.line_number - 1,
                existing.line_number,
                false,
                { modeline_text }
              )
              if ok then
                result.added = result.added + 1
                table.insert(added_kinds, crd.kind)
              else
                table.insert(result.errors, "Failed to replace modeline for " .. crd.kind)
              end
            else
              -- Insert new modeline
              local ok = pcall(
                vim.api.nvim_buf_set_lines,
                bufnr,
                target_line - 1,
                target_line - 1,
                false,
                { modeline_text }
              )
              if ok then
                result.added = result.added + 1
                offset = offset + 1
                table.insert(added_kinds, crd.kind)
              else
                table.insert(result.errors, "Failed to add modeline for " .. crd.kind)
              end
            end
          end
        end
      end
    end
  end

  -- Notify user of what was added
  local opts = config.options
  local should_notify = opts.modeline and opts.modeline.notify ~= false
  if not options.dry_run and #added_kinds > 0 and should_notify then
    vim.notify(
      "Added modelines for: " .. table.concat(added_kinds, ", "),
      vim.log.levels.INFO,
      { title = "yaml-companion" }
    )
  end

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
---@param bufnr number
---@param crd CRDInfo
---@param target_line number
---@param callback fun(success: boolean, error: string|nil)
function M.try_cluster_fallback(bufnr, crd, target_line, callback)
  local kubectl = require("yaml-companion.kubectl")

  if not kubectl.is_available() then
    callback(false, "kubectl not available")
    return
  end

  -- Get CRD name from kind
  kubectl.get_crd_name(crd.apiGroup, crd.kind, function(crd_name, err)
    if err or not crd_name then
      callback(false, err or "Could not determine CRD name")
      return
    end

    -- Check cache first
    if kubectl.is_cache_valid(crd_name) then
      local cached_path = kubectl.get_cache_path(crd_name)
      local url = "file://" .. cached_path
      local success = modeline.set_modeline(bufnr, url, target_line, false)
      callback(success, nil)
      return
    end

    -- Fetch from cluster
    kubectl.fetch_crd_schema(crd_name, function(result, fetch_err)
      if fetch_err or not result then
        callback(false, fetch_err or "Failed to fetch CRD schema")
        return
      end

      -- Cache the schema
      local cached_path, cache_err = kubectl.cache_schema(crd_name, result.schema)
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

  -- Process CRDs sequentially to handle line offsets correctly
  local offset = 0
  local added_kinds = {}
  local idx = 1

  local function process_next()
    if idx > #non_core_crds then
      -- Done processing all CRDs
      local opts = config.options
      local should_notify = opts.modeline and opts.modeline.notify ~= false
      if not options.dry_run and #added_kinds > 0 and should_notify then
        vim.notify(
          "Added modelines for: " .. table.concat(added_kinds, ", "),
          vim.log.levels.INFO,
          { title = "yaml-companion" }
        )
      end
      callback(result)
      return
    end

    local crd = non_core_crds[idx]
    local target_line = crd.line_number + offset
    local existing = modeline.find_modeline(bufnr, target_line, target_line + 3)

    if existing and not options.overwrite then
      result.skipped = result.skipped + 1
      idx = idx + 1
      process_next()
      return
    end

    if options.dry_run then
      vim.notify(
        string.format("Would add modeline for %s at line %d", crd.kind, target_line),
        vim.log.levels.INFO,
        { title = "yaml-companion" }
      )
      result.added = result.added + 1
      idx = idx + 1
      process_next()
      return
    end

    -- First try Datree URL
    local datree_url = M.build_crd_schema_url(crd)

    -- Helper to add modeline with given URL
    local function add_modeline_for_url(url)
      local modeline_text = modeline.format_modeline(url)

      if existing and options.overwrite then
        local ok = pcall(
          vim.api.nvim_buf_set_lines,
          bufnr,
          existing.line_number - 1,
          existing.line_number,
          false,
          { modeline_text }
        )
        if ok then
          result.added = result.added + 1
          table.insert(added_kinds, crd.kind)
        else
          table.insert(result.errors, "Failed to replace modeline for " .. crd.kind)
        end
      else
        local ok = pcall(
          vim.api.nvim_buf_set_lines,
          bufnr,
          target_line - 1,
          target_line - 1,
          false,
          { modeline_text }
        )
        if ok then
          result.added = result.added + 1
          offset = offset + 1
          table.insert(added_kinds, crd.kind)
        else
          table.insert(result.errors, "Failed to add modeline for " .. crd.kind)
        end
      end
    end

    if datree_url then
      -- Validate URL exists before using it (when validate_urls is enabled)
      if config.options.modeline and config.options.modeline.validate_urls then
        M.validate_url(datree_url, function(exists)
          if exists then
            add_modeline_for_url(datree_url)
            idx = idx + 1
            process_next()
          else
            -- Datree URL doesn't exist, try cluster fallback
            M.try_cluster_fallback(bufnr, crd, target_line, function(success, err)
              if success then
                result.added = result.added + 1
                offset = offset + 1
                table.insert(added_kinds, crd.kind)
              else
                result.skipped = result.skipped + 1
                if err then
                  table.insert(
                    result.errors,
                    string.format(
                      "Datree URL not found and cluster fallback failed for %s: %s",
                      crd.kind,
                      err
                    )
                  )
                end
              end
              idx = idx + 1
              process_next()
            end)
          end
        end)
      else
        -- No URL validation, just use Datree URL directly
        add_modeline_for_url(datree_url)
        idx = idx + 1
        process_next()
      end
    else
      -- No Datree URL available (empty apiGroup), try cluster fallback
      M.try_cluster_fallback(bufnr, crd, target_line, function(success, err)
        if success then
          result.added = result.added + 1
          offset = offset + 1
          table.insert(added_kinds, crd.kind)
        else
          result.skipped = result.skipped + 1
          if err then
            table.insert(result.errors, string.format("Fallback failed for %s: %s", crd.kind, err))
          end
        end
        idx = idx + 1
        process_next()
      end)
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
