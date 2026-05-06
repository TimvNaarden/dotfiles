local base = require("plugins.configs.lspconfig")
local on_attach = base.on_attach
local capabilities = base.capabilities

local lspconfig = require("lspconfig")

lspconfig.clangd.setup {
  on_attach = function(client, bufnr)
    client.server_capabilities.signatureHelpProvider = false
    on_attach(client, bufnr)
  end,
  capabilities = capabilities,
}
lspconfig.arduino_language_server.setup({
    cmd = {
        "arduino-language-server",
        "-clangd",      "/usr/bin/clangd",
        "-cli",         "/usr/bin/arduino-cli",
        "-cli-config",  "/home/tim/.arduinoIDE/arduino-cli.yaml",
        "-fqbn",  "esp32:esp32:esp32s3"
    }
})

local servers = { "ts_ls", "tailwindcss", "eslint", "lua_ls", "dockerls", "pyright"}

for _, lsp in ipairs(servers) do
  lspconfig[lsp].setup {
    on_attach = on_attach,
    capabilities = capabilities,
  }
end

