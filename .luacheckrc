-- Luacheck configuration for Neovim plugin

ignore = {
  "631", -- max_line_length (handled by stylua)
}

-- vim is both read and written to (vim.g, vim.b, etc.)
globals = {
  "vim",
}

-- Test files use plenary.nvim busted-style globals
files["tests/**/*.lua"] = {
  globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "pending",
    "SetupYamlls", -- defined in minimal_init.vim
    assert = {
      fields = {
        are = { fields = { same = {} } },
        is_true = {},
        is_not_nil = {},
        is_boolean = {},
      },
    },
  },
}
