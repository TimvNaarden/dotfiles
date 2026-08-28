-- nvim-cmp used to render Copilot's suggestions, so they were disabled here and
-- surfaced through the cmp menu instead. coc owns the completion popup now and
-- has no Copilot source, so inline ghost-text suggestions are turned back on.
return {
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    config = function()
      require("copilot").setup {
        suggestion = {
          enabled = true,
          auto_trigger = true,
          keymap = {
            -- <Tab> belongs to coc's popup, so Copilot gets its own keys.
            accept = "<M-l>",
            next = "<M-]>",
            prev = "<M-[>",
            dismiss = "<M-h>",
          },
        },
        panel = { enabled = false },
      }
    end,
  },
}
