return {
  {
    "nvimtools/none-ls.nvim",
    event = "VeryLazy",
    opts = function()
      local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
      local null_ls = require "null-ls"

      return {
        sources = {
          null_ls.builtins.formatting.prettierd,
          null_ls.builtins.formatting.clang_format.with {
            extra_args = { "--style=file" },
            filetypes = { "c", "cpp", "h", "hpp" },
          },
          null_ls.builtins.formatting.csharpier.with {
            command = vim.fn.stdpath "data" .. "/mason/bin/csharpier",
            args = { "format", "--write-stdout" },
          },
        },
        on_attach = function(client, bufnr)
          if client:supports_method "textDocument/formatting" then
            vim.api.nvim_clear_autocmds { group = augroup, buffer = bufnr }
            vim.api.nvim_create_autocmd("BufWritePre", {
              group = augroup,
              buffer = bufnr,
              callback = function()
                vim.lsp.buf.format { bufnr = bufnr }
              end,
            })
          end
        end,
      }
    end,
  },
}
