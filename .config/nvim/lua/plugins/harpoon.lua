return {
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    lazy = false,
    dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
    config = function()
      local harpoon = require "harpoon"
      local map = vim.keymap.set
      map("n", "<leader>da", function()
        local bufname = vim.api.nvim_buf_get_name(0)
        if bufname == "" then
          vim.notify("Cannot add unnamed buffer to Harpoon", vim.log.levels.WARN)
          return
        end
        harpoon:list():add()
      end, { desc = "Harpoon add file" })

      for i = 1, 9 do
        map("n", "<leader>d" .. i, function()
          harpoon:list():select(i)
        end, { desc = "Harpoon go to file " .. i })
      end

      map("n", "<leader>dp", function()
        harpoon:list():prev()
      end, { desc = "Harpoon go to previous file" })

      map("n", "<leader>dn", function()
        harpoon:list():next()
      end, { desc = "Harpoon go to next file" })

      map("n", "<leader>de", function()
        local conf = require("telescope.config").values
        local harpoon_files = harpoon:list()

        local function toggle_telescope(list)
          local file_paths = {}
          for _, item in ipairs(list.items) do
            table.insert(file_paths, item.value)
          end

          require("telescope.pickers")
            .new({}, {
              prompt_title = "Harpoon",
              finder = require("telescope.finders").new_table { results = file_paths },
              previewer = conf.file_previewer {},
              sorter = conf.generic_sorter {},
              attach_mappings = function(prompt_bufnr, tmap)
                tmap("i", "<C-d>", function()
                  local state = require "telescope.actions.state"
                  local selected = state.get_selected_entry()
                  table.remove(list.items, selected.index)
                  toggle_telescope(list)
                end)
                return true
              end,
            })
            :find()
        end

        toggle_telescope(harpoon_files)
      end, { desc = "Harpoon quick menu (Telescope)" })
    end,
  },
}
