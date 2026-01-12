--- Cluster CRD selection UI for yaml-companion
--- Provides vim.ui.select interface for browsing and selecting CRDs from Kubernetes cluster

local notify = require("yaml-companion.util.notify")
local buffer_util = require("yaml-companion.util.buffer")

local M = {}

--- Open vim.ui.select to select from detected CRDs in buffer
---@param crds table[] List of detected CRDs
---@param callback fun(selection: table|nil) Callback with selected CRD
function M.select_detected_crd(crds, callback)
  vim.ui.select(crds, {
    prompt = "Select CRD to fetch from cluster: ",
    format_item = function(crd)
      return string.format("%s (%s)", crd.kind, crd.apiVersion)
    end,
  }, callback)
end

--- Open vim.ui.select to browse all CRDs in cluster
---@param action? SchemaAction Optional action to apply. If nil, prompts user to choose.
function M.open(action)
  local kubectl = require("yaml-companion.kubectl")

  if not kubectl.is_available() then
    notify.error("kubectl not found. Install kubectl to use cluster CRD features")
    return
  end

  local bufnr, err = buffer_util.current_yaml_buffer()
  if not bufnr then
    notify.warn(err)
    return
  end

  notify.info("Fetching CRDs from cluster...")

  kubectl.list_all_crds(function(crds, list_err)
    if list_err then
      notify.error("Failed to list CRDs: " .. list_err)
      return
    end

    if not crds or #crds == 0 then
      notify.warn("No CRDs found in cluster")
      return
    end

    vim.ui.select(crds, {
      prompt = "Select Cluster CRD: ",
      format_item = function(crd)
        return string.format("[cluster] %s", crd.name)
      end,
    }, function(selection)
      if not selection then
        return
      end

      -- If action is specified, apply it directly
      if action then
        kubectl.fetch_and_add_modeline(bufnr, selection.name, 1, action)
        return
      end

      -- Otherwise, prompt user to choose action
      kubectl.fetch_and_add_modeline_with_action_select(bufnr, selection.name)
    end)
  end)
end

return M
