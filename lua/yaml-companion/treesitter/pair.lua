---@brief Key-value pair parsing for YAML treesitter nodes

local M = {}

local ts = require("yaml-companion.treesitter")

--- Reverse a table in place
---@param t table
local function reverse(t)
  local n = #t
  for i = 1, math.floor(n / 2) do
    t[i], t[n - i + 1] = t[n - i + 1], t[i]
  end
end

--- Check if a node is a sequence/array block
---@param node TSNode|nil
---@return boolean
local function is_sequence_block(node)
  if not node then
    return false
  end
  local node_type = node:type()
  return node_type == "block_sequence" or node_type == "flow_sequence"
end

--- Get the index of a node within a sequence
---@param sequence_node TSNode The sequence parent node
---@param target_node TSNode The node to find the index of
---@return number|nil index 0-based index, or nil if not found
local function get_sequence_index(sequence_node, target_node)
  local idx = 0
  for child in sequence_node:iter_children() do
    local child_type = child:type()
    if child_type == "block_sequence_item" or child_type == "flow_sequence_item" then
      -- Check if target_node is a descendant of this sequence item
      ---@type TSNode|nil
      local check = target_node
      while check do
        if check:id() == child:id() then
          return idx
        end
        check = check:parent()
      end
      idx = idx + 1
    end
  end
  return nil
end

--- Clean a YAML value string (remove quotes, trim whitespace, handle block scalars)
---@param value string|nil The raw value string
---@return string cleaned The cleaned value
M.clean_value = function(value)
  if not value then
    return ""
  end

  value = vim.trim(value)

  -- Remove surrounding double quotes
  if value:sub(1, 1) == '"' and value:sub(-1) == '"' and #value >= 2 then
    return value:sub(2, -2)
  end

  -- Remove surrounding single quotes
  if value:sub(1, 1) == "'" and value:sub(-1) == "'" and #value >= 2 then
    return value:sub(2, -2)
  end

  -- Handle block scalar indicators (| or >)
  if value:sub(1, 1) == "|" or value:sub(1, 1) == ">" then
    -- Remove the indicator and clean up the multiline content
    local content = value:sub(2)
    content = vim.trim(content)
    -- Replace multiple whitespace/newlines with single space
    content = content:gsub("%s+", " ")
    return content
  end

  -- Replace newlines with spaces for multiline values
  value = value:gsub("\n", " ")
  value = value:gsub("%s+", " ")
  value = vim.trim(value)

  return value
end

--- Build the full key path by walking up the parent chain
---@param pair_node TSNode The block_mapping_pair or flow_pair node
---@param bufnr number Buffer number
---@return string path The full dotted key path (e.g., "root.parent.child" or "items[0].name")
M.build_key_path = function(pair_node, bufnr)
  local parts = {}
  ---@type TSNode|nil
  local current = pair_node

  while current do
    local node_type = current:type()

    if node_type == "block_mapping_pair" or node_type == "flow_pair" then
      local key_nodes = current:field("key")
      if key_nodes and key_nodes[1] then
        local key_text = ts.get_node_text(key_nodes[1], bufnr)
        table.insert(parts, key_text)
      end
    end

    -- Check if we're inside a sequence item
    local parent = current:parent()
    if parent then
      local parent_type = parent:type()
      if parent_type == "block_sequence_item" or parent_type == "flow_sequence_item" then
        -- Find the sequence and get our index
        local sequence = parent:parent()
        if sequence and is_sequence_block(sequence) then
          local idx = get_sequence_index(sequence, current)
          if idx then
            -- Prepend index notation to the last part
            if #parts > 0 then
              parts[#parts] = "[" .. idx .. "]." .. parts[#parts]
            else
              parts[1] = "[" .. idx .. "]"
            end
          end
        end
      end
    end

    current = current:parent()
  end

  reverse(parts)

  -- Join and clean up the path
  local path = table.concat(parts, ".")
  -- Fix double dots
  path = path:gsub("%.%.", ".")
  -- Fix patterns like "key.[0]" to "key[0]"
  path = path:gsub("%.%[", "[")
  -- Add leading dot
  if path ~= "" and path:sub(1, 1) ~= "." then
    path = "." .. path
  end

  return path
end

--- Get the value node from a pair node
---@param pair_node TSNode
---@return TSNode|nil
local function get_value_node(pair_node)
  local value_nodes = pair_node:field("value")
  if value_nodes and value_nodes[1] then
    return value_nodes[1]
  end
  return nil
end

--- Check if a value node represents a scalar (leaf) value
---@param value_node TSNode|nil
---@return boolean
local function is_scalar_value(value_node)
  if not value_node then
    return false
  end

  local node_type = value_node:type()

  -- Direct scalar types
  local scalar_types = {
    "plain_scalar",
    "double_quote_scalar",
    "single_quote_scalar",
    "boolean_scalar",
    "integer_scalar",
    "float_scalar",
    "null_scalar",
    "block_scalar",
  }

  for _, scalar_type in ipairs(scalar_types) do
    if node_type == scalar_type then
      return true
    end
  end

  -- flow_node can contain a scalar
  if node_type == "flow_node" then
    local child = value_node:child(0)
    if child then
      return is_scalar_value(child)
    end
  end

  return false
end

--- Parse a key-value pair node into a YamlKeyInfo structure
---@param pair_node TSNode The block_mapping_pair or flow_pair node
---@param bufnr number Buffer number
---@return YamlKeyInfo|nil
M.parse = function(pair_node, bufnr)
  local key_nodes = pair_node:field("key")
  if not key_nodes or not key_nodes[1] then
    return nil
  end

  local key_node = key_nodes[1]
  local key_path = M.build_key_path(pair_node, bufnr)
  local row, col = key_node:start()

  local value_node = get_value_node(pair_node)
  local value = nil
  local human = key_path .. ":"

  if value_node and is_scalar_value(value_node) then
    local raw_value = ts.get_node_text(value_node, bufnr)
    value = M.clean_value(raw_value)
    if value and value ~= "" then
      human = key_path .. " = " .. value
    end
  end

  return {
    key = key_path,
    value = value,
    human = human,
    line = row + 1, -- Convert to 1-indexed
    col = col + 1, -- Convert to 1-indexed
  }
end

return M
