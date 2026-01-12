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
make lint                # Check code style with StyLua
make test                # Run lint + Plenary test suite (headless Neovim)
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

## Type Definitions

**IMPORTANT:** When adding new configuration options or data structures, always
update `lua/yaml-companion/meta.lua` with the corresponding `@class` type
definitions. This file provides LSP type hints for the entire codebase.

For example, when adding a new config section like `cluster_crds`:

1. Add the type class in `meta.lua`:
   ```lua
   ---@class ClusterCrdsConfig
   ---@field enabled boolean
   ---@field fallback boolean
   ```

2. Add it to `ConfigOptions`:
   ```lua
   ---@class ConfigOptions
   ---@field cluster_crds ClusterCrdsConfig
   ```

## Generated Files

These files are auto-generated and should not be manually edited:

- `lua/yaml-companion/builtin/kubernetes/version.lua`
- `lua/yaml-companion/builtin/kubernetes/resources.lua`

Regenerate with `make generate-kubernetes` or via the GitHub Actions workflow.
