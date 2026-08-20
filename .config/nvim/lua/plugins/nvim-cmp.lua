return {
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      -- optional Tailwind completion addons:
      -- "roobert/tailwindcss-colorizer-cmp.nvim",
    },
    config = function()
      local cmp = require "cmp"
      local luasnip = require "luasnip"

      cmp.setup {
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },

        preselect = cmp.PreselectMode.None,
        completion = {
          completeopt = "menu,menuone,noinsert,noselect",
        },

        mapping = cmp.mapping.preset.insert {
          ["<C-Space>"] = cmp.mapping.complete(),

          ["<CR>"] = cmp.mapping.confirm {
            select = false,
          },

          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            else
              fallback()
            end
          end, { "i", "s" }),

          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            else
              fallback()
            end
          end, { "i", "s" }),
        },

        sources = cmp.config.sources {
          {
            name = "nvim_lsp",
            entry_filter = function(entry, ctx)
              local client = entry.source.source.client
              if not client then
                return true
              end

              if
                client.name == "emmet_ls"
                and (ctx.filetype == "javascriptreact" or ctx.filetype == "typescriptreact")
              then
                return false
              end

              return true
            end,
          },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
          { name = "coc" },
        },
      }

      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      vim.lsp.config("*", {
        capabilities = vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), capabilities),
        root_markers = { ".git" },
      })
    end,
  },
}
