return {
  "tpope/vim-obsession",
  lazy = false, -- load immediately, don't wait for an event
  config = function()
    vim.api.nvim_create_autocmd("VimEnter", {
      nested = true,
      once = true,
      callback = function()
        vim.schedule(function()
          if vim.fn.argc() ~= 0 then
            return
          end

          local session = vim.fn.getcwd() .. "/Session.vim"

          if vim.fn.filereadable(session) == 1 then
            vim.cmd("silent source " .. vim.fn.fnameescape(session))
          end
        end)
      end,
    })
  end,
}
