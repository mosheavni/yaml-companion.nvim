--- Unified notification helper for yaml-companion
--- Eliminates repeated { title = "yaml-companion" } across modules

local M = {}

local TITLE = "yaml-companion"

---@param msg string
function M.info(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = TITLE })
end

---@param msg string
function M.warn(msg)
  vim.notify(msg, vim.log.levels.WARN, { title = TITLE })
end

---@param msg string
function M.error(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = TITLE })
end

---@param msg string
function M.debug(msg)
  vim.notify(msg, vim.log.levels.DEBUG, { title = TITLE })
end

return M
