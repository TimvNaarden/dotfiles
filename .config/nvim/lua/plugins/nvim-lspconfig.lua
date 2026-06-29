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
      -- ts_ls
      vim.lsp.config("ts_ls", {
        cmd = { "typescript-language-server", "--stdio" },
        filetypes = {
          "javascript",
          "javascriptreact",
          "typescript",
          "typescriptreact",
        },
        root_markers = { "tsconfig.json", "package.json" },
        workspace_required = true,
      })

      -- tailwindcss
      vim.lsp.config("tailwindcss", {
        cmd = { "tailwindcss-language-server", "--stdio" },
        filetypes = {
          "html",
          "css",
          "scss",
          "javascript",
          "javascriptreact",
          "typescript",
          "typescriptreact",
          "vue",
        },
        root_markers = {
          "tailwind.config.js",
          "tailwind.config.cjs",
          "tailwind.config.ts",
          "package.json",
        },
        workspace_required = true,
        settings = {
          tailwindCSS = {
            hovers = true,
            suggestions = true,
            codeActions = true,
            experimental = {
              -- Tell Tailwind to treat strings inside default: ["..."] as class lists
              classRegex = {
                -- Example for something like cva({ variants: { tone: { default: ["..."] } } })
                'default:\\s*\\["([^"]*)"\\]',
              },
            },
          },
        },
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
          glslx = "glsl",
          glsl = "glsl",

          vert = "glsl",
          frag = "glsl",
          comp = "glsl",

          -- optional, but probably useful
          tesc = "glsl",
          tese = "glsl",
          geom = "glsl",
        },
      }

      vim.treesitter.language.register("glsl", "glslx")

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
        "prisma",
      }
      local capabilities = vim.lsp.protocol.make_client_capabilities()

      vim.lsp.config("emmet_ls", {
        capabilities = capabilities,
        filetypes = {
          "css",
          "eruby",
          "html",
          "javascript",
          "javascriptreact",
          "less",
          "sass",
          "scss",
          "svelte",
          "pug",
          "typescriptreact",
          "vue",
        },
        init_options = {
          html = {
            options = {
              ["bem.enabled"] = true,
            },
          },
        },
      })

      vim.lsp.enable "emmet_ls"
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
