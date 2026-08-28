-- NvChad v2.5 declares its own nvim-lspconfig and nvim-cmp specs, pulled in by
-- `import = "nvchad.plugins"` in init.lua. Deleting the local plugin files was
-- not enough: lazy kept installing both from upstream. Disabling the specs is
-- what actually removes them, leaving coc as the only completion engine and
-- language client.
--
-- Safe to do here because the only NvChad code that calls require("cmp") lives
-- inside those specs, and its nvim-autopairs config (the other cmp consumer) is
-- already disabled in nvim-autopairs.lua.
return {
  { "neovim/nvim-lspconfig", enabled = false },
  { "hrsh7th/nvim-cmp", enabled = false },
  { "hrsh7th/cmp-nvim-lsp", enabled = false },
  { "hrsh7th/cmp-nvim-lua", enabled = false },
  { "hrsh7th/cmp-buffer", enabled = false },
  { "saadparwaiz1/cmp_luasnip", enabled = false },
}
