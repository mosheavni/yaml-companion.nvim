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
---@return boolean success, boolean was_modified (true if modeline was actually added/changed)
function M.set_modeline(bufnr, schema_url, line_number, overwrite)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, false
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
      return ok, ok
    else
      -- Don't overwrite, modeline already exists (not an error, but nothing changed)
      return true, false
    end
  end

  -- Insert new modeline
  local ok =
    pcall(vim.api.nvim_buf_set_lines, bufnr, line_number - 1, line_number - 1, false, { modeline })
  return ok, ok
end

--- Find modeline with specific URL within document range
---@param bufnr number
---@param url string The schema URL to match exactly
---@param start_line number
---@param end_line number
---@return ModelineInfo|nil
function M.find_modeline_with_url(bufnr, url, start_line, end_line)
  local lines = M.get_buf_lines(bufnr)
  if not lines then
    return nil
  end

  start_line = math.max(1, start_line)
  end_line = math.min(#lines, end_line)

  for i = start_line, end_line do
    local line = lines[i]
    local existing_url = M.parse_modeline(line)
    if existing_url and existing_url == url then
      return {
        line_number = i,
        schema_url = existing_url,
        raw = line,
      }
    end
  end

  return nil
end

--- Set modeline within a document range, checking for duplicate URLs
--- Unlike set_modeline(), this checks for the SAME URL to prevent duplicates
--- while allowing different schemas in the same document
---@param bufnr number
---@param schema_url string
---@param target_line number Where to insert (1-indexed)
---@param end_line number End of document (for duplicate check)
---@param overwrite boolean Whether to replace existing modeline with same URL
---@return boolean success, number offset_delta (1 if line was added, 0 otherwise)
function M.set_modeline_in_range(bufnr, schema_url, target_line, end_line, overwrite)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, 0
  end

  -- Search for existing modeline with the SAME URL in document range
  local existing = M.find_modeline_with_url(bufnr, schema_url, target_line, end_line)

  if existing then
    if overwrite then
      local modeline_text = M.format_modeline(schema_url)
      local ok = pcall(
        vim.api.nvim_buf_set_lines,
        bufnr,
        existing.line_number - 1,
        existing.line_number,
        false,
        { modeline_text }
      )
      return ok, 0
    else
      -- Modeline for this URL already exists - skip
      return false, 0
    end
  end

  -- No existing modeline for this URL, insert new one at target line
  local modeline_text = M.format_modeline(schema_url)
  local ok = pcall(
    vim.api.nvim_buf_set_lines,
    bufnr,
    target_line - 1,
    target_line - 1,
    false,
    { modeline_text }
  )
  return ok, ok and 1 or 0
end

return M
