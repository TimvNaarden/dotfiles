 M = {}

M.dap = {
  plugin = true,
  n = {
    ["<leader>db"] = {
      "<cmd> DapToggleBreakpoint <CR>",
      "Add breakpoint at line",
    },
    ["<leader>dr"] = {
      "<cmd> DapContinue <CR>",
      "Start or continue the debugger",
    }
  }
}

M.harpoon = {
  n = {
    ["<leader>da"] = {
      function()
        local bufname = vim.api.nvim_buf_get_name(0)
        if bufname == "" then
          vim.notify("Cannot add unnamed buffer to Harpoon", vim.log.levels.WARN)
          return
        end
        require("harpoon"):list():add()
      end,
      "Harpoon add file",
    },
    ["<leader>d1"] = {
      function()
        require("harpoon"):list():select(1)
      end,
      "Harpoon go to file 1",
    },
    ["<leader>d2"] = {
      function()
        require("harpoon"):list():select(2)
      end,
      "Harpoon go to file 2",
    },
    ["<leader>d3"] = {
      function()
        require("harpoon"):list():select(3)
      end,
      "Harpoon go to file 1",
    },
    ["<leader>d4"] = {
      function()
        require("harpoon"):list():select(4)
      end,
      "Harpoon go to file 4",
    },
    ["<leader>d5"] = {
      function()
        require("harpoon"):list():select(5)
      end,
      "Harpoon go to file 5",
    },
    ["<leader>d6"] = {
      function()
        require("harpoon"):list():select(6)
      end,
      "Harpoon go to file 6",
    },
    ["<leader>d7"] = {
      function()
        require("harpoon"):list():select(7)
      end,
      "Harpoon go to file 7",
    },
    ["<leader>d8"] = {
      function()
        require("harpoon"):list():select(8)
      end,
      "Harpoon go to file 8",
    },
    ["<leader>d9"] = {
      function()
        require("harpoon"):list():select(9)
      end,
      "Harpoon go to file 9",
    },

    ["<leader>dp"] = {
      function()
        require("harpoon"):list():prev()
      end,
      "Harpoon go to previous file",
    },
    ["<leader>dn"] = {
      function()
        require("harpoon"):list():next()
      end,
      "Harpoon go to next file",
    },
    ["<leader>de"] = {
      function()
        local conf = require("telescope.config").values
        local function toggle_telescope(harpoon_files)
          local file_paths = {}
          for _, item in ipairs(harpoon_files.items) do
            table.insert(file_paths, item.value)
          end

          require("telescope.pickers").new({}, {
            prompt_title = "Harpoon",
            finder = require("telescope.finders").new_table({
              results = file_paths,
            }),
            previewer = conf.file_previewer({}),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, map)
              map("i", "<C-d>", function()
                local state = require("telescope.actions.state")
                local selected_entry = state.get_selected_entry()
                local current_picker = state.get_current_picker(prompt_bufnr)

                table.remove(harpoon_files.items, selected_entry.index)
                toggle_telescope(harpoon_files)
              end)
              return true
            end,
          }):find()
        end
        toggle_telescope(require("harpoon"):list())
      end,
      "Harpoon quick menu",
    }
  }
}
return M
