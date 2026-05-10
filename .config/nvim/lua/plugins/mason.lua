return {
  {
    "williamboman/mason.nvim",
    dependencies = { "mason-org/mason-registry" },
    opts = {
      ensure_installed = {
        "clangd",
        "clang-format",
        "codelldb",
        "eslint-lsp",
        "prettierd",
        "tailwindcss-language-server",
        "typescript-language-server",
        "dockerfile-language-server",
        "arduino-language-server",
        "pyright",
      },
      registries = {
        "github:mason-org/mason-registry",
        "github:Crashdummyy/mason-registry", -- ← provides roslyn
      },
    },
  },
}
