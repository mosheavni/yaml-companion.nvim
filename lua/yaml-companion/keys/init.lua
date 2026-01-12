---@brief Key navigation features for YAML files

local M = {}

local document = require("yaml-companion.treesitter.document")
local ts = require("yaml-companion.treesitter")

--- Get all keys and populate quickfix list
---@param bufnr? number Buffer number (defaults to current buffer)
---@param opts? { open: boolean } Options (open=true to open quickfix window, default: true)
---@return YamlQuickfixEntry[] entries List of quickfix entries
M.quickfix = function(bufnr, opts)
  -- Convert 0 or nil to actual buffer number (0 means current buffer in Neovim API but not in quickfix)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  opts = opts or {}
  if opts.open == nil then
    opts.open = true
  end

  -- Get configuration
  local config = require("yaml-companion.config")
  local cfg = config.options.keys or {}
  local max_len = cfg.max_value_length or 50
  local include_values = cfg.include_values ~= false

  local keys = document.all_keys(bufnr)
  local entries = {}

  for _, key_info in ipairs(keys) do
    local text = key_info.key
    if include_values and key_info.value then
      ---@type string
      local value = key_info.value
      if #value > max_len then
        value = value:sub(1, max_len) .. "..."
      end
      text = text .. " = " .. value
    end

    table.insert(entries, {
      bufnr = bufnr,
      lnum = key_info.line,
      col = key_info.col,
      text = text,
    })
  end

  vim.fn.setqflist(entries, "r")
  vim.fn.setqflist({}, "a", { title = "YAML Keys" })

  if opts.open then
    vim.cmd("copen")
  end

  return entries
end

--- Get key at cursor position
---@return YamlKeyInfo|nil info Key info at cursor, or nil if not found
M.at_cursor = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]

  return document.get_key_at_line(bufnr, line)
end

--- Health check for key navigation features
M.health = function()
  local health = vim.health

  if ts.has_parser() then
    health.ok("Treesitter YAML parser available")
  else
    health.error("Treesitter YAML parser not found", {
      "Install it with: :TSInstall yaml",
      "Or add 'yaml' to your treesitter ensure_installed list",
    })
  end
end

return M
