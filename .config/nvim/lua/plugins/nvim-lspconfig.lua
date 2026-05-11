-- Global defaults (on_attach, capabilities, semantic tokens)
return {
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    priority = 1000,
    config = function()
      vim.lsp.config("*", {
        capabilities = vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), {
          textDocument = {
            completion = {
              completionItem = {
                documentationFormat = { "markdown", "plaintext" },
                snippetSupport = true,
                preselectSupport = true,
                insertReplaceSupport = true,
                labelDetailsSupport = true,
                deprecatedSupport = true,
                commitCharactersSupport = true,
                tagSupport = { valueSet = { 1 } },
                resolveSupport = {
                  properties = { "documentation", "detail", "additionalTextEdits" },
                },
              },
            },
          },
        }),
        root_markers = { ".git" },
      })
      -- lua_ls specific settings
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
            workspace = {
              library = {
                [vim.fn.expand "$VIMRUNTIME/lua"] = true,
                [vim.fn.expand "$VIMRUNTIME/lua/vim/lsp"] = true,
                [vim.fn.stdpath "data" .. "/lazy/ui/nvchad_types"] = true,
                [vim.fn.stdpath "data" .. "/lazy/lazy.nvim/lua/lazy"] = true,
              },
              maxPreload = 100000,
              preloadFileSize = 10000,
            },
          },
        },
      })

      -- clangd: fix offset encoding warning
      vim.lsp.config("clangd", {
        capabilities = vim.tbl_deep_extend(
          "force",
          vim.lsp.protocol.make_client_capabilities(),
          { offsetEncoding = { "utf-16" } }
        ),
      })

      -- arduino: custom cmd
      vim.lsp.config("arduino_language_server", {
        cmd = {
          "arduino-language-server",
          "-clangd",
          "/usr/bin/clangd",
          "-cli",
          "/usr/bin/arduino-cli",
          "-cli-config",
          "/home/tim/.arduinoIDE/arduino-cli.yaml",
          "-fqbn",
          "esp32:esp32:esp32s3",
        },
      })

      vim.filetype.add {
        extension = {
          vert = "glsl",
          tesc = "glsl",
          tese = "glsl",
          frag = "glsl",
          geom = "glsl",
          comp = "glsl",
        },
      }
      vim.lsp.config("glsl_analyzer", {
        filetypes = { "glsl" },
      })
      -- Enable all servers (nvim-lspconfig provides the cmd/filetypes/root_markers)
      vim.lsp.enable {
        "clangd",
        "arduino_language_server",
        "ts_ls",
        "tailwindcss",
        "eslint",
        "lua_ls",
        "dockerls",
        "pyright",
        "roslyn",
        "glsl_analyzer",
      }

      vim.diagnostic.config {
        signs = false,
        virtual_text = {
          severity = { min = vim.diagnostic.severity.WARN },
        },
        underline = {
          severity = { min = vim.diagnostic.severity.WARN },
        },
        jump = {
          severity = { min = vim.diagnostic.severity.ERROR },
        },
        severity_sort = true,
      }
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local opts = { buffer = args.buf }
          vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)

          vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, { desc = "Rename symbol" })
          -- or use <leader>ca if ca conflicts
        end,
      })
    end,
  },
}
