--- Buffer validation utilities for yaml-companion
--- Consolidates repeated YAML buffer checks

local M = {}

--- Check if buffer is a valid YAML file
---@param bufnr number
---@return boolean is_yaml
---@return string|nil error_message
function M.validate_yaml(bufnr)
  local ft = vim.bo[bufnr].filetype
  if not ft:match("^yaml") then
    return false, "Current buffer is not a YAML file"
  end
  return true, nil
end

--- Get current buffer, validating it's YAML
---@return number|nil bufnr, string|nil error
function M.current_yaml_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local is_yaml, err = M.validate_yaml(bufnr)
  if not is_yaml then
    return nil, err
  end
  return bufnr, nil
end

return M
