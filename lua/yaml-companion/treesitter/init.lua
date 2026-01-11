---@brief Treesitter utilities for YAML parsing

local M = {}

--- Check if treesitter YAML parser is available
---@return boolean
M.has_parser = function()
  local ok, _ = pcall(vim.treesitter.language.inspect, "yaml")
  return ok
end

--- Get the YAML parse tree for a buffer
---@param bufnr number Buffer number
---@return TSTree|nil tree The parse tree, or nil if parser unavailable
M.get_tree = function(bufnr)
  if not M.has_parser() then
    return nil
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "yaml")
  if not ok or not parser then
    return nil
  end

  local trees = parser:parse()
  if trees and trees[1] then
    return trees[1]
  end

  return nil
end

--- Get text content of a treesitter node
---@param node TSNode The treesitter node
---@param bufnr number Buffer number
---@return string text The text content of the node
M.get_node_text = function(node, bufnr)
  return vim.treesitter.get_node_text(node, bufnr)
end

return M
