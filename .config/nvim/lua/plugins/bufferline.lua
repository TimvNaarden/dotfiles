return {
	"afonsocarlos/nvim-bufferline.lua",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		vim.opt.termguicolors = true
		require("bufferline").setup({
			options = {
				diagnostics = "nvim_lsp",
				diagnostics_indicator = function(count, level, diagnostics_dict, context)
					local s = " "
					for e, n in pairs(diagnostics_dict) do
						local sym = e == "error" and " " or (e == "warning" and " " or "")
						s = s .. n .. sym
					end
					return s
				end,
				offsets = {
					{
						filetype = "neo-tree",
						text = "File Explorer",
						text_align = "center",
					},
				},
			},
		})

		vim.keymap.set("n", "<leader>1", ":BufferLineGoToBuffer 1<CR>", { silent = true })
		vim.keymap.set("n", "<leader>2", ":BufferLineGoToBuffer 2<CR>", { silent = true })
		vim.keymap.set("n", "<leader>3", ":BufferLineGoToBuffer 3<CR>", { silent = true })
		vim.keymap.set("n", "<leader>4", ":BufferLineGoToBuffer 4<CR>", { silent = true })
		vim.keymap.set("n", "<leader>5", ":BufferLineGoToBuffer 5<CR>", { silent = true })
		vim.keymap.set("n", "<leader>6", ":BufferLineGoToBuffer 6<CR>", { silent = true })
		vim.keymap.set("n", "<leader>7", ":BufferLineGoToBuffer 7<CR>", { silent = true })
		vim.keymap.set("n", "<leader>8", ":BufferLineGoToBuffer 8<CR>", { silent = true })
		vim.keymap.set("n", "<leader>9", ":BufferLineGoToBuffer 9<CR>", { silent = true })

		vim.keymap.set("n", "<tab>", ":BufferLineCycleNext<CR>", { silent = true })
		vim.keymap.set("n", "<S-tab>", ":BufferLineCyclePrev<CR>", { silent = true })
		vim.keymap.set("n", "<leader>db", function()
			local buf = vim.api.nvim_get_current_buf()
            vim.cmd("BufferLineCyclePrev")
			vim.api.nvim_buf_delete(buf, { force = true })
		end)
	end,
}
