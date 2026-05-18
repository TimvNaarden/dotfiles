-- lazy.nvim / NvChad plugin spec for nvim-glslx.
--
-- Place at:  ~/.config/nvim/lua/plugins/glslx.lua
--
-- This plugin provides OpenGL GLSL diagnostics for .frag/.vert/.comp/.geom/
-- .tesc/.tese files by running glslangValidator on the buffer (after
-- expanding #include directives in pure Lua). It does NOT depend on
-- glslx or glsl_analyzer for these extensions.
--
-- Requirements (Arch Linux):
--   sudo pacman -S glslang     # provides glslangValidator
--
-- The plugin lives at ~/dev/nvim-glslx and is pure Lua: no `build` step.

local plugin_dir = vim.fn.expand "~/.config/nvim/plugins/nvim-glslx"

-- Register shader extensions as filetype `glsl` at spec-eval time so that
-- `nvim foo.frag` picks up the filetype before lazy.nvim defers the plugin.
local function register_filetypes()
  pcall(vim.filetype.add, {
    extension = {
      frag = "glsl",
      vert = "glsl",
      comp = "glsl",
      geom = "glsl",
      tesc = "glsl",
      tese = "glsl",
      glsl = "glsl",
    },
  })
end

register_filetypes()

-- Toggle: set this to false in your init.lua to disable validate-on-save.
if vim.g.glsl_validator_validate_on_save == nil then
  vim.g.glsl_validator_validate_on_save = true
end

return {
  {
    "nvim-glslx",
    dir = plugin_dir,
    name = "nvim-glslx",
    ft = { "glsl" },
    lazy = false, -- so :GlslValidate is available before any glsl buffer is opened

    init = function()
      register_filetypes()

      -- If nvim-treesitter is present, make sure the `glsl` parser is used.
      pcall(function()
        local ok, lang = pcall(require, "vim.treesitter.language")
        if ok and lang and lang.register then
          pcall(lang.register, "glsl", "glsl")
        end
      end)
    end,

    config = function()
      vim.g.glsl_validator_validate_on_save = true
      vim.g.glsl_validator_validate_on_normal_mode = true

      local group = vim.api.nvim_create_augroup("GlslAutoValidate", { clear = true })

      vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
        group = group,
        pattern = {
          "*.frag",
          "*.vert",
          "*.comp",
          "*.geom",
          "*.tesc",
          "*.tese",
          "*.glsl",
        },
        callback = function(args)
          if vim.fn.exists ":GlslValidate" ~= 2 then
            return
          end

          if vim.b[args.buf].glsl_disable_auto_validate then
            return
          end

          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(args.buf) then
              vim.api.nvim_buf_call(args.buf, function()
                vim.cmd "silent! GlslValidate"
              end)
            end
          end)
        end,
      })
    end,
  },
}
