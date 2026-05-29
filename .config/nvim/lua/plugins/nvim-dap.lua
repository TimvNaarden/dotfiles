return {
  {
    "mfussenegger/nvim-dap",
    config = function(_, _)
      local map = vim.keymap.set
      map("n", "<leader>db", "<cmd> DapToggleBreakpoint <CR>", { desc = "Add breakpoint at line" })
      map("n", "<leader>dr", "<cmd> DapContinue <CR>", { desc = "Start or continue the debugger" })

      local dap = require "dap"

      dap.adapters["pwa-node"] = {
        type = "server",
        host = "127.0.0.1",
        port = 8123,
        executable = {
          command = "js-debug-adapter",
        },
      }
      dap.adapters.coreclr = {
        type = "executable",
        command = vim.fn.exepath "netcoredbg",
        args = { "--interpreter=vscode" },
      }
      dap.adapters.codelldb = {
        type = "executable",
        command = "codelldb",
      }
      for _, language in ipairs { "typescript", "javascript" } do
        dap.configurations[language] = {
          {
            type = "pwa-node",
            request = "launch",
            name = "Launch file",
            program = "${file}",
            cwd = "${workspaceFolder}",
            runtimeExecutable = "node",
          },
        }
      end

      dap.configurations.cpp = {
        {
          name = "Launch file",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
      }
      dap.configurations.c = dap.configurations.cpp

      dap.configurations.cs = {
        {
          type = "coreclr",
          name = "Launch SpectralRenderer",
          request = "launch",
          program = function()
            -- Always build before debugging
            vim.fn.system "dotnet build -c Debug"
            return vim.fn.getcwd() .. "/bin/Debug/net10.0/SpectralRenderer.dll"
          end,
          cwd = vim.fn.getcwd() .. "/bin/Debug/net10.0/",
        },
      }
    end,
  },
}
