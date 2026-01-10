local M = {}

-- Modeline format: # yaml-language-server: $schema=<url>
M.MODELINE_PATTERN = "^#%s*yaml%-language%-server:%s*%$schema=(.+)$"
M.MODELINE_FORMAT = "# yaml-language-server: $schema=%s"

--- Get all lines from a buffer safely
---@param bufnr number
---@return string[]|nil lines, nil on invalid buffer
function M.get_buf_lines(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  return ok and lines or nil
end

--- Parse an existing modeline from a line
---@param line string
---@return string|nil schema_url
function M.parse_modeline(line)
  if not line then
    return nil
  end
  local url = line:match(M.MODELINE_PATTERN)
  return url
end

--- Format a schema URL into a modeline comment
---@param schema_url string
---@return string
function M.format_modeline(schema_url)
  return string.format(M.MODELINE_FORMAT, schema_url)
end

--- Find existing modeline in buffer within optional line range
---@param bufnr number
---@param start_line? number Start line (1-indexed, defaults to 1)
---@param end_line? number End line (1-indexed, defaults to buffer end)
---@return ModelineInfo|nil
function M.find_modeline(bufnr, start_line, end_line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  start_line = start_line or 1
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  end_line = end_line or line_count

  -- Clamp to valid range
  start_line = math.max(1, start_line)
  end_line = math.min(line_count, end_line)

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line - 1, end_line, false)
  if not ok then
    return nil
  end

  for i, line in ipairs(lines) do
    local url = M.parse_modeline(line)
    if url then
      return {
        line_number = start_line + i - 1,
        schema_url = url,
        raw = line,
      }
    end
  end

  return nil
end

--- Add or replace modeline in buffer
---@param bufnr number
---@param schema_url string
---@param line_number? number Where to insert (1-indexed, defaults to 1)
---@param overwrite? boolean Whether to replace existing modeline (defaults to false)
---@return boolean success
function M.set_modeline(bufnr, schema_url, line_number, overwrite)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  line_number = line_number or 1
  local modeline = M.format_modeline(schema_url)

  -- Check if there's already a modeline at or near the target line
  local existing = M.find_modeline(bufnr, line_number, line_number + 5)

  if existing then
    if overwrite then
      -- Replace existing modeline
      local ok = pcall(
        vim.api.nvim_buf_set_lines,
        bufnr,
        existing.line_number - 1,
        existing.line_number,
        false,
        { modeline }
      )
      return ok
    else
      -- Don't overwrite, consider it a success (modeline exists)
      return true
    end
  end

  -- Insert new modeline
  local ok =
    pcall(vim.api.nvim_buf_set_lines, bufnr, line_number - 1, line_number - 1, false, { modeline })
  return ok
end

--- Find all document boundaries in a multi-doc YAML file
--- Documents are separated by "---"
---@param bufnr number
---@return DocumentBoundary[]
function M.find_document_boundaries(bufnr)
  local lines = M.get_buf_lines(bufnr)
  if not lines then
    return {}
  end

  -- Check for empty buffer (may have one empty string)
  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    return {}
  end

  local boundaries = {}
  local current_start = 1

  -- Handle leading "---" - it's part of the first document
  local first_line = lines[1] or ""
  if first_line:match("^%-%-%-") then
    current_start = 1
  end

  for i, line in ipairs(lines) do
    -- Skip the first line if it's a document separator
    if i > 1 and line:match("^%-%-%-") then
      -- End previous document and start new one
      if current_start <= i - 1 then
        table.insert(boundaries, {
          start_line = current_start,
          end_line = i - 1,
        })
      end
      current_start = i
    end
  end

  -- Add final document
  if current_start <= #lines then
    table.insert(boundaries, {
      start_line = current_start,
      end_line = #lines,
    })
  end

  -- If no separators found, entire file is one document
  if #boundaries == 0 and #lines > 0 then
    table.insert(boundaries, {
      start_line = 1,
      end_line = #lines,
    })
  end

  return boundaries
end

--- Check if a line is a document separator
---@param line string
---@return boolean
function M.is_document_separator(line)
  return line:match("^%-%-%-") ~= nil
end

return M
