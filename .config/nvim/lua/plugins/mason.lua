return {
  {
    "mason-org/mason.nvim",
    dependencies = { "mason-org/mason-registry" },
    -- NvChad lazy-loads mason on :Mason*, but the installer below has to run at
    -- startup for ensure_installed to mean anything.
    event = "VeryLazy",
    opts = {
      -- Language servers are gone from this list: coc installs and manages its
      -- own through g:coc_global_extensions. What remains is tooling nothing
      -- else provides, namely conform's formatters and nvim-dap's adapters.
      ensure_installed = {
        "stylua", -- conform: lua
        "prettier", -- conform: css, html, json, yaml, markdown, js, ts
        "prettierd", -- conform: faster prettier daemon, tried first
        "clang-format", -- conform: c, cpp
        "codelldb", -- nvim-dap: c, cpp
        "js-debug-adapter", -- nvim-dap: javascript, typescript
      },
      registries = {
        "github:mason-org/mason-registry",
        "github:Crashdummyy/mason-registry", -- provides roslyn, for roslyn.nvim
      },
    },
    config = function(_, opts)
      require("mason").setup(opts)

      -- mason.nvim has no ensure_installed of its own, and NvChad v2.5 dropped
      -- the :MasonInstallAll command that used to read it, so the list above was
      -- silently inert. Install anything missing instead.
      local registry = require "mason-registry"
      registry.refresh(function()
        for _, name in ipairs(opts.ensure_installed or {}) do
          local ok, pkg = pcall(registry.get_package, name)
          if ok and not pkg:is_installed() then
            pkg:install()
          end
        end
      end)
    end,
  },
}
