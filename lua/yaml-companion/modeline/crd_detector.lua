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
