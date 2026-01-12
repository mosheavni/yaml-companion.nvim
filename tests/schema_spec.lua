local eq = assert.are.same

local function wait_until(fn)
  for _ = 1, 10 do
    vim.wait(900)
    local r = fn()
    if r then
      return true
    end
  end
  vim.notify("wait_until: timeout exceeded", vim.log.levels.ERROR)
  return false
end

local function buf(input, ft, name)
  local b = vim.api.nvim_create_buf(false, false)
  -- Set lines BEFORE name/filetype to ensure content is available when LSP attaches
  vim.api.nvim_buf_set_lines(b, 0, -1, true, vim.split(input, "\n"))
  vim.api.nvim_buf_set_name(b, name)
  vim.api.nvim_set_option_value("filetype", ft, { buf = b })
  vim.api.nvim_command("buffer " .. b)
  return wait_until(function()
    local clients = vim.lsp.get_clients()
    if #clients > 0 then
      return true
    end
  end)
end

local function wait_for_schemas()
  return wait_until(function()
    local r = require("yaml-companion.schema").all()
    if r and #r > 1 then
      return true
    end
  end)
end

describe("user defined schemas:", function()
  after_each(function()
    vim.api.nvim_buf_delete(0, { force = true })
    vim.fn.delete("foo.yaml", "rf")
    assert(wait_until(function()
      local clients = vim.lsp.get_clients()
      if #clients == 0 then
        return true
      end
      for _, client in ipairs(clients) do
        client:stop(true)
      end
    end))
  end)

  local custom_schema = {
    name = "Some custom schema",
    uri = "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.32.1-standalone-strict/all.json",
  }

  it("options.schemas.result should add the schema to the list (legacy)", function()
    local test_schema = vim.deepcopy(custom_schema)
    test_schema.name = test_schema.name .. " (legacy)"
    local result = {}

    local yamlconfig = require("yaml-companion").setup({ schemas = { result = { test_schema } } })
    SetupYamlls(yamlconfig)

    assert(buf("---\nfoo: bar\n", "yaml", "foo.yaml"))
    assert(wait_for_schemas())

    local all_schemas = require("yaml-companion.schema").all()

    for _, schema in ipairs(all_schemas) do
      if schema.name == test_schema.name then
        result = schema
        break
      end
    end

    eq(test_schema.uri, result.uri)
  end)

  it("options.schemas should add the schemas to the list (new)", function()
    local test_schema = vim.deepcopy(custom_schema)
    test_schema.name = test_schema.name .. " (new)"
    local result = {}

    local yamlconfig = require("yaml-companion").setup({ schemas = { test_schema } })
    SetupYamlls(yamlconfig)

    assert(buf("---\nfoo: bar\n", "yaml", "foo.yaml"))
    assert(wait_for_schemas())

    local all_schemas = require("yaml-companion.schema").all()

    for _, schema in ipairs(all_schemas) do
      if schema.name == test_schema.name then
        result = schema
        break
      end
    end

    eq(test_schema.uri, result.uri)
  end)
end)
