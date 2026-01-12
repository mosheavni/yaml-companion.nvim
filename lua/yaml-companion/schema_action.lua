--- Schema application UI and actions for yaml-companion
--- Consolidates apply_schema and action selection from datree.lua and kubectl/init.lua

local notify = require("yaml-companion.util.notify")
local modeline = require("yaml-companion.modeline")

local M = {}

--- Available schema actions
M.ACTIONS = {
  { id = "modeline", label = "Add as modeline (persisted in file)" },
  { id = "lsp", label = "Set as LSP schema (session only)" },
}

---@class ApplySchemaOpts
---@field line_number? number Line number for modeline insertion (default: 1)
---@field notify? boolean Whether to show notification (default: true)
---@field cached? boolean Whether schema came from cache (for messaging)

--- Apply a schema to buffer with specified action
---@param bufnr number
---@param schema { name: string, uri: string }
---@param action SchemaAction "modeline" | "lsp"
---@param opts? ApplySchemaOpts
function M.apply(bufnr, schema, action, opts)
  opts = opts or {}
  local line_number = opts.line_number or 1
  local should_notify = opts.notify ~= false
  local suffix = opts.cached and " (cached)" or ""

  if action == "modeline" then
    local success, was_modified = modeline.set_modeline(bufnr, schema.uri, line_number, false)
    if should_notify then
      if not success then
        notify.error("Failed to add modeline")
      elseif was_modified then
        notify.info("Added schema modeline: " .. schema.name .. suffix)
      else
        notify.info("Modeline already exists (not modified)")
      end
    end
    return success
  elseif action == "lsp" then
    local context = require("yaml-companion.context")
    local schema_obj = { name = schema.name, uri = schema.uri }
    context.schema(bufnr, schema_obj)
    if should_notify then
      notify.info("Set LSP schema: " .. schema.name .. suffix)
    end
    return true
  end

  return false
end

--- Prompt user to select an action, then apply schema
---@param bufnr number
---@param schema { name: string, uri: string }
---@param opts? ApplySchemaOpts
---@param callback? fun(success: boolean, action: SchemaAction|nil) Optional callback after action
function M.select_and_apply(bufnr, schema, opts, callback)
  vim.ui.select(M.ACTIONS, {
    prompt = "How to apply schema?",
    format_item = function(a)
      return a.label
    end,
  }, function(chosen_action)
    if not chosen_action then
      notify.info("Action selection cancelled")
      if callback then
        callback(false, nil)
      end
      return
    end

    local success = M.apply(bufnr, schema, chosen_action.id, opts)
    if callback then
      callback(success, chosen_action.id)
    end
  end)
end

return M
