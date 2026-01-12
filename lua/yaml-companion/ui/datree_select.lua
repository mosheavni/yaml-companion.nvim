--- Datree CRD catalog selection UI for yaml-companion
--- Provides vim.ui.select interface for browsing Datree CRD catalog

local notify = require("yaml-companion.util.notify")
local buffer_util = require("yaml-companion.util.buffer")
local schema_action = require("yaml-companion.schema_action")

local M = {}

--- Open vim.ui.select with Datree CRD catalog
---@param action? SchemaAction Optional action to apply. If nil, prompts user to choose.
function M.open(action)
  local datree = require("yaml-companion.modeline.datree")

  local bufnr, err = buffer_util.current_yaml_buffer()
  if not bufnr then
    notify.warn(err)
    return
  end

  notify.info("Fetching Datree CRD catalog...")

  datree.fetch_catalog(function(entries, fetch_err)
    if fetch_err then
      notify.error("Failed to fetch catalog: " .. fetch_err)
      return
    end

    if not entries or #entries == 0 then
      notify.warn("No schemas found in catalog")
      return
    end

    vim.ui.select(entries, {
      prompt = "Select CRD Schema: ",
      format_item = function(entry)
        return entry.name
      end,
    }, function(selection)
      if not selection then
        notify.info("Schema selection cancelled")
        return
      end

      local schema = { name = selection.name, uri = selection.url }

      -- If action is specified, apply it directly
      if action then
        schema_action.apply(bufnr, schema, action)
        return
      end

      -- Otherwise, prompt user to choose action
      schema_action.select_and_apply(bufnr, schema)
    end)
  end)
end

return M
