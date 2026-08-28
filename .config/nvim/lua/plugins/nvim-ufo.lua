return {
  { "kevinhwang91/promise-async" },
  {
    "kevinhwang91/nvim-ufo",
    dependencies = "kevinhwang91/promise-async",
    event = "BufReadPost",
    config = function()
      vim.o.foldcolumn = "1"
      vim.o.foldlevel = 99
      vim.o.foldlevelstart = 99
      vim.o.foldenable = true

      -- ufo defaults to the LSP fold provider, which no longer exists now that
      -- coc replaced the native clients. Treesitter provides the same ranges,
      -- with indent as the fallback for filetypes without a parser.
      require("ufo").setup {
        provider_selector = function()
          return { "treesitter", "indent" }
        end,
      }
    end,
  },
}
