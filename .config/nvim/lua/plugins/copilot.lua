return {
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    config = function()
      require("copilot").setup {
        suggestion = { enabled = false }, -- disable inline suggestions (cmp handles it)
        panel = { enabled = false },
      }
    end,
  },
}
