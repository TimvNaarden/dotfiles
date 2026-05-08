-- Global defaults (on_attach, capabilities, semantic tokens)
vim.lsp.config('*', {
  capabilities = vim.tbl_deep_extend("force",
    vim.lsp.protocol.make_client_capabilities(),
    {
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
    }
  ),
  root_markers = { ".git" },
})

-- Keymaps + signature on attach
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    require("core.utils").load_mappings("lspconfig", { buffer = args.buf })
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.server_capabilities.signatureHelpProvider then
      require("nvchad.signature").setup(client)
    end
    -- Disable semantic tokens (NvChad setting)
    if client and not require("core.utils").load_config().ui.lsp_semantic_tokens then
      client.server_capabilities.semanticTokensProvider = nil
    end
    -- if client.name == "roslyn" then
    --   client.server_capabilities.documentFormattingProvider = false
    --   client.server_capabilities.documentRangeFormattingProvider = false
    -- end
  end,
})

-- lua_ls specific settings
vim.lsp.config('lua_ls', {
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
vim.lsp.config('clangd', {
  capabilities = vim.tbl_deep_extend("force",
    vim.lsp.protocol.make_client_capabilities(),
    { offsetEncoding = { "utf-16" } }
  ),
})

-- arduino: custom cmd
vim.lsp.config('arduino_language_server', {
  cmd = {
    "arduino-language-server",
    "-clangd", "/usr/bin/clangd",
    "-cli", "/usr/bin/arduino-cli",
    "-cli-config", "/home/tim/.arduinoIDE/arduino-cli.yaml",
    "-fqbn", "esp32:esp32:esp32s3"
  },
})

-- Enable all servers (nvim-lspconfig provides the cmd/filetypes/root_markers)
vim.lsp.enable({
  "clangd",
  "arduino_language_server",
  "ts_ls",
  "tailwindcss",
  "eslint",
  "lua_ls",
  "dockerls",
  "pyright",
})

vim.diagnostic.config({
  signs = false,
  virtual_text = {
    severity = { min = vim.diagnostic.severity.ERROR },
  },
  underline = {
    severity = { min = vim.diagnostic.severity.ERROR },
  },
  jump = {
    severity = { min = vim.diagnostic.severity.ERROR },
  },
  severity_sort = true,
})
