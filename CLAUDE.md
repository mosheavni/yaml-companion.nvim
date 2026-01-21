<!-- markdownlint-disable MD013 -->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

yaml-companion.nvim is a Neovim plugin that enhances YAML editing by
automatically detecting and managing JSON schemas for YAML files. It acts as a
companion to the yaml-language-server (yamlls), providing intelligent schema
detection and selection capabilities.

## Development Commands

```bash
make lint                # Check code style with StyLua and Selene
make test                # Run Plenary test suite (headless Neovim)
make prepare             # Setup dev environment (clone deps, install stylua, yaml-language-server)
make generate-kubernetes # Regenerate Kubernetes schema files
```

To run a single test file:

```bash
nvim --headless --noplugin -u tests/minimal_init.vim \
  -c "PlenaryBustedFile tests/schema_spec.lua"
```

## Architecture

### Core Flow

1. User opens YAML file → LSP client (yamlls) attaches
2. LSP sends `yaml/schema/store/initialized` event
3. `context.autodiscover()` tries schema sources in order:
   - LSP-provided schema
   - User-defined schemas from config
   - Matcher-detected schemas (Kubernetes, cloud-init)
   - SchemaStore schemas from LSP
4. If matched, updates LSP config with schema override
5. User can manually select via `vim.ui.select`

### Module Responsibilities

| Module                                   | Purpose                                                                           |
| ---------------------------------------- | --------------------------------------------------------------------------------- |
| `lua/yaml-companion/init.lua`            | Public API: `setup()`, `get_buf_schema()`, `set_buf_schema()`, `open_ui_select()` |
| `lua/yaml-companion/context/init.lua`    | Buffer state management, autodiscovery, LSP sync                                  |
| `lua/yaml-companion/schema.lua`          | Schema resolution from multiple sources                                           |
| `lua/yaml-companion/lsp/`                | LSP communication (requests, handlers, utils)                                     |
| `lua/yaml-companion/_matchers/init.lua`  | Matcher loading/registration (lazy loading via metatable)                         |
| `lua/yaml-companion/builtin/kubernetes/` | K8s detection (searches for `kind:` field)                                        |
| `lua/yaml-companion/builtin/cloud_init/` | cloud-config detection (searches for `#cloud-config` header)                      |

### Matcher Interface

Custom matchers must implement:

```lua
{
  match = function(bufnr) -> Schema | nil,   -- Return schema if file matches
  handles = function() -> Schema[],          -- List schemas this matcher handles
  health = function() -> nil,                -- Optional: :checkhealth integration
}
```

### Schema Object Structure

```lua
{
  name = "Schema Name",
  uri = "https://example.com/schema.json"
}
```

## Code Style

- Formatter: StyLua (config in `stylua.toml`)
- Linter: Selene (config in `selene.toml`, Neovim globals in `neovim.yaml`)
- 2-space indentation, 100 column width
- The `undefined-global vim` warnings are expected in Neovim plugins

## Testing

Tests use Plenary's busted-style test framework. Test files are in `tests/` directory:

- `yaml-companion_spec.lua` - Integration tests
- `schema_spec.lua` - Schema resolution tests

Tests require `plenary.nvim` cloned as a sibling to this repo (done by `make prepare`). Neovim 0.11+ is required for `vim.lsp.config` support.

## EmmyLua Annotations

**CRITICAL:** Documentation is auto-generated from EmmyLua annotations. Every
public function, configuration option, and data structure MUST be properly
annotated. Missing or incorrect annotations will result in incomplete or wrong
documentation.

### What Goes Where

#### In `lua/yaml-companion/meta.lua` (Shared Types)

Add to `meta.lua` when the type is:

- **Shared across modules** (used in multiple files)
- **Part of the public API** (configuration, return types, callback parameters)
- **Complex data structures** (classes with multiple fields)

```lua
---@class MyNewConfig
---@field enabled boolean Enable the feature
---@field timeout number Timeout in milliseconds

---@class MyReturnType
---@field success boolean Whether operation succeeded
---@field data string|nil Result data if successful
```

#### In-Place (Source Files)

Add annotations directly in source files for:

- **Function signatures** (parameters, return types, descriptions)
- **Local types** only used within that file
- **Module-level variables**

### Function Annotation Format

**Every public function MUST have complete annotations:**

```lua
--- Brief description of what the function does.
--- Additional details can go on subsequent lines.
---@param bufnr number Buffer number to operate on
---@param schema Schema Schema to apply
---@param opts? ApplySchemaOpts Optional configuration
---@return boolean success Whether the operation succeeded
---@return string|nil error Error message if failed
function M.apply_schema(bufnr, schema, opts)
  -- implementation
end
```

### Annotation Requirements

1. **Description line** - First line(s) without `@` describe the function
2. **All parameters** - Use `@param name type Description`
3. **Optional params** - Use `?` suffix: `@param opts? table`
4. **Return values** - Use `@return type description` for each return value
5. **Nilable types** - Use `type|nil` for values that can be nil

### Examples

**Adding a new configuration option:**

1. Add the type class in `meta.lua`:

   ```lua
   ---@class ClusterCrdsConfig
   ---@field enabled? boolean Enable cluster CRD features
   ---@field fallback? boolean Auto-fallback to cluster when Datree fails
   ---@field cache_ttl? number Cache expiration in seconds (default: 24h)
   ```

2. Add it to `ConfigOptions` in `meta.lua`:

   ```lua
   ---@class ConfigOptions
   ---@field cluster_crds ClusterCrdsConfig Cluster CRD fetching configuration
   ```

**Adding a new public function:**

```lua
--- Fetch CRD schema from the connected Kubernetes cluster.
--- Queries the cluster API server for the CRD definition and converts
--- it to a JSON schema that can be used for validation.
---@param kind string The CRD kind (e.g., "Application")
---@param api_group string The API group (e.g., "argoproj.io")
---@param version string The API version (e.g., "v1alpha1")
---@return Schema|nil schema The schema if found
---@return string|nil error Error message if fetch failed
function M.fetch_cluster_crd(kind, api_group, version)
  -- implementation
end
```

### Checklist for Changes

When modifying Lua code, verify:

- [ ] All new functions have `---` description lines
- [ ] All parameters documented with `@param`
- [ ] All return values documented with `@return`
- [ ] New data structures added to `meta.lua` with `@class`
- [ ] Optional fields marked with `?` suffix
- [ ] Field descriptions explain purpose, not just type

## Documentation

**IMPORTANT:** When adding new features, always document them in `README.md`:

1. Add new commands to the **Commands** table
2. Add new Lua API functions to the **Lua API** table
3. Add new configuration options to the **Configuration** section
4. For major features, add a subsection under **Features & Usage**

The README structure is:

- Requirements / Features / Installation
- Configuration (with full defaults example)
- Features & Usage (consolidated feature documentation)
  - Schema Selection (auto-detection, manual selection, statusline)
  - Key Navigation (quickfix list, key at cursor)
  - Modeline Features (Datree browsing, auto-detect CRDs)
  - Cluster CRD Integration (fetch, browse, auto-fallback)
  - Caching (locations, TTL, clearing)
- Commands (quick reference table)
- Lua API (all public functions)
- Health Check

## Generated Files

These files are auto-generated and should not be manually edited:

- `lua/yaml-companion/builtin/kubernetes/version.lua`
- `lua/yaml-companion/builtin/kubernetes/resources.lua`

Regenerate with `make generate-kubernetes` or via the GitHub Actions workflow.
