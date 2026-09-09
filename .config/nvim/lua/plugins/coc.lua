-- coc.nvim: replaces nvim-lspconfig / vim.lsp.config setup
return {
  {
    "neoclide/coc.nvim",
    branch = "release", -- prebuilt, no npm build step required
    lazy = false,
    priority = 1000,
    init = function()
      -- Mason prepends its bin dir to $PATH in its own config, but that runs on
      -- VeryLazy, long after coc has already spawned its node process. Servers
      -- coc starts inherit that stale env, so mason-installed binaries are
      -- invisible to them. haskell-language-server-wrapper fails outright this
      -- way: it re-resolves "haskell-language-server-<ghc version>" off $PATH
      -- and dies with "Failed to find a HLS version for GHC 9.10.3". Prepend it
      -- here instead, where it lands before coc loads.
      local mason_bin = vim.fn.stdpath "data" .. "/mason/bin"
      if vim.fn.isdirectory(mason_bin) == 1 and not vim.env.PATH:find(mason_bin, 1, true) then
        vim.env.PATH = mason_bin .. ":" .. vim.env.PATH
      end

      -- node is installed through nvm, so it is only on $PATH inside a login
      -- shell. Launched from a desktop entry, coc would fail to start. Pin the
      -- newest nvm node when nothing is on $PATH.
      if vim.fn.executable "node" == 0 then
        local nodes = vim.fn.glob(vim.fn.expand "~/.nvm/versions/node/*/bin/node", false, true)
        table.sort(nodes)
        if #nodes > 0 then
          vim.g.coc_node_path = nodes[#nodes]
        end
      end

      vim.g.coc_global_extensions = {
        "coc-tsserver", -- ts_ls replacement (handles large TS monorepos well)
        "coc-eslint",
        "coc-html",
        "coc-css",
        "@yaegassy/coc-tailwindcss3", -- tailwindcss replacement, was missing
        "coc-json",
        "coc-emmet",
        "coc-pyright", -- pyright replacement
        "coc-clangd", -- clangd replacement
        "coc-sumneko-lua", -- lua_ls replacement
        "coc-docker", -- dockerls replacement
        "coc-prisma", -- prisma replacement
      }
    end,
    config = function()
      vim.o.updatetime = 300
      vim.opt.shortmess:append "c"
      vim.g.coc_snippet_next = "<tab>"

      local keyset = vim.keymap.set

      -- Tab-driven completion (mirrors default coc setup)
      local function check_back_space()
        local col = vim.fn.col "." - 1
        return col == 0 or vim.fn.getline("."):sub(col, col):match "%s" ~= nil
      end

      keyset("i", "<TAB>", function()
        if vim.fn["coc#pum#visible"]() ~= 0 then
          return vim.fn["coc#pum#next"](1)
        elseif check_back_space() then
          return "<TAB>"
        else
          return vim.fn["coc#refresh"]()
        end
      end, { expr = true, silent = true })

      keyset("i", "<S-TAB>", function()
        if vim.fn["coc#pum#visible"]() ~= 0 then
          return vim.fn["coc#pum#prev"](1)
        else
          return "<C-h>"
        end
      end, { expr = true, silent = true })

      keyset("i", "<cr>", function()
        if vim.fn["coc#pum#visible"]() ~= 0 then
          return vim.fn["coc#pum#confirm"]()
        else
          return "<C-g>u<CR><c-r>=coc#on_enter()<CR>"
        end
      end, { expr = true, silent = true })

      -- Navigation / actions (kept close to your old on_attach mappings)
      keyset("n", "gd", "<Plug>(coc-definition)", { silent = true })
      keyset("n", "gy", "<Plug>(coc-type-definition)", { silent = true })
      keyset("n", "gi", "<Plug>(coc-implementation)", { silent = true })
      keyset("n", "gr", "<Plug>(coc-references)", { silent = true })

      keyset("n", "K", function()
        if vim.fn.CocAction("hasProvider", "hover") then
          vim.fn.CocActionAsync "doHover"
        else
          vim.cmd 'execute "!" . &keywordprg . " " . expand("<cword>")'
        end
      end, { silent = true })

      keyset("n", "<leader>cr", "<Plug>(coc-rename)", { desc = "Rename symbol" })
      keyset({ "n", "x" }, "<leader>ca", "<Plug>(coc-codeaction-cursor)", { desc = "Code action" })
      keyset("n", "<leader>cf", ":call CocActionAsync('format')<CR>", { desc = "Format buffer" })

      -- Diagnostics navigation
      keyset("n", "[g", "<Plug>(coc-diagnostic-prev)", { silent = true })
      keyset("n", "]g", "<Plug>(coc-diagnostic-next)", { silent = true })

      -- Highlight symbol under cursor on hold
      vim.api.nvim_create_augroup("CocGroup", {})
      vim.api.nvim_create_autocmd("CursorHold", {
        group = "CocGroup",
        command = "silent call CocActionAsync('highlight')",
        desc = "Highlight symbol under cursor on CursorHold",
      })

      -- Setup formatexpr specified filetype(s)
      vim.api.nvim_create_autocmd("FileType", {
        group = "CocGroup",
        pattern = "typescript,json",
        command = [[setl formatexpr=CocAction('formatSelected')]],
        desc = "Setup formatexpr specified filetype(s)",
      })

      -- Custom filetypes/treesitter registration kept from your old config
      vim.filetype.add {
        extension = {
          glslx = "glsl",
          glsl = "glsl",
          vert = "glsl",
          frag = "glsl",
          comp = "glsl",
          tesc = "glsl",
          tese = "glsl",
          geom = "glsl",
        },
      }
      vim.treesitter.language.register("glsl", "glslx")
    end,
  },
}
