return {
  { "kevinhwang91/promise-async" },
  {
    "kevinhwang91/nvim-ufo",
    dependencies = "kevinhwang91/promise-async",
    event = "BufReadPost", -- Load the plugin when a buffer is read
    config = function()
      vim.o.foldcolumn = "1" -- Show fold indicator in the gutter
      vim.o.foldlevel = 99
      vim.o.foldlevelstart = 99
      vim.o.foldenable = true

      require("ufo").setup()
    end,
  },
}
