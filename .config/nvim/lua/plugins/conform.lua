-- none-ls used to own formatting for c/cpp and the prettier filetypes. It was
-- an LSP client under the hood, so it went with nvim-lspconfig and conform
-- picked up its sources.
local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    c = { "clang_format" },
    cpp = { "clang_format" },
    css = { "prettierd", "prettier", stop_after_first = true },
    scss = { "prettierd", "prettier", stop_after_first = true },
    html = { "prettierd", "prettier", stop_after_first = true },
    json = { "prettierd", "prettier", stop_after_first = true },
    yaml = { "prettierd", "prettier", stop_after_first = true },
    markdown = { "prettierd", "prettier", stop_after_first = true },
    javascript = { "prettierd", "prettier", stop_after_first = true },
    javascriptreact = { "prettierd", "prettier", stop_after_first = true },
    typescript = { "prettierd", "prettier", stop_after_first = true },
    typescriptreact = { "prettierd", "prettier", stop_after_first = true },
  },

  formatters = {
    clang_format = { prepend_args = { "--style=file" } },
  },

  format_on_save = {
    timeout_ms = 500,
    -- Was lsp_fallback = true, which called vim.lsp.buf.format. There are no
    -- native LSP clients left, so that was a silent no-op. Filetypes without a
    -- formatter above are handled by coc through :CocCommand format.
    lsp_format = "never",
  },
}

return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    opts = options,
  },
}
