---@brief Document traversal for YAML treesitter trees

local M = {}

local ts = require("yaml-companion.treesitter")
local pair = require("yaml-companion.treesitter.pair")

-- Query for all key-value pairs (cached)
local YAML_PAIR_QUERY = [[
  (block_mapping_pair) @pair
  (flow_pair) @pair
]]

local cached_query = nil

--- Get the parsed YAML pair query (cached)
---@return vim.treesitter.Query|nil
local function get_pair_query()
  if cached_query then
    return cached_query
  end
  local ok, query = pcall(vim.treesitter.query.parse, "yaml", YAML_PAIR_QUERY)
  if ok then
    cached_query = query
  end
  return cached_query
end

--- Get all key-value pairs in a buffer
---@param bufnr number Buffer number
---@return YamlKeyInfo[] keys List of all keys in the document
M.all_keys = function(bufnr)
  local tree = ts.get_tree(bufnr)
  if not tree then
    return {}
  end

  local root = tree:root()
  local keys = {}

  local query = get_pair_query()
  if not query then
    return {}
  end

  for _, node in query:iter_captures(root, bufnr, 0, -1) do
    local info = pair.parse(node, bufnr)
    if info then
      table.insert(keys, info)
    end
  end

  -- Sort by line number
  table.sort(keys, function(a, b)
    if a.line == b.line then
      return a.col < b.col
    end
    return a.line < b.line
  end)

  return keys
end

--- Get the key at or containing a specific line
---@param bufnr number Buffer number
---@param line number 1-indexed line number
---@return YamlKeyInfo|nil key The key info at the line, or nil if not found
M.get_key_at_line = function(bufnr, line)
  local tree = ts.get_tree(bufnr)
  if not tree then
    return nil
  end

  local root = tree:root()
  local target_row = line - 1 -- Convert to 0-indexed

  local query = get_pair_query()
  if not query then
    return nil
  end

  local best_pair = nil
  local best_size = math.huge

  for _, node in query:iter_captures(root, bufnr, 0, -1) do
    local start_row, _, end_row, _ = node:range()

    -- Check if cursor line is within this pair's range
    if target_row >= start_row and target_row <= end_row then
      -- Prefer the smallest (most specific) matching node
      local size = end_row - start_row
      if size < best_size then
        best_pair = node
        best_size = size
      end
    end
  end

  if best_pair then
    return pair.parse(best_pair, bufnr)
  end

  -- If no direct match, find the closest preceding key
  local all = M.all_keys(bufnr)
  local preceding = nil

  for _, key_info in ipairs(all) do
    if key_info.line <= line then
      preceding = key_info
    else
      break
    end
  end

  return preceding
end

return M
