-- Entry point for nvim-glslx (the OpenGL GLSL diagnostics plugin).
--
-- Registers user commands and an autocmd group that runs glslangValidator
-- on save for shader buffers. Loaded once at startup by Neovim.

if vim.g.loaded_nvim_glslx then
  return
end
vim.g.loaded_nvim_glslx = 1

-- Default: validate on save unless the user explicitly disables it.
if vim.g.glsl_validator_validate_on_save == nil then
  vim.g.glsl_validator_validate_on_save = true
end

local function lazy_validator()
  return require('glslx.validator')
end

vim.api.nvim_create_user_command('GlslValidate', function(opts)
  local bufnr = (opts.args and opts.args ~= '' and tonumber(opts.args)) or 0
  lazy_validator().validate_buffer(bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr)
end, { nargs = '?', desc = 'Validate current GLSL buffer with glslangValidator' })

vim.api.nvim_create_user_command('GlslBuild', function()
  lazy_validator().validate_buffer(vim.api.nvim_get_current_buf())
end, { desc = 'Alias for :GlslValidate on the current buffer' })

vim.api.nvim_create_user_command('GlslClear', function()
  lazy_validator().clear(vim.api.nvim_get_current_buf())
end, { desc = 'Clear glslangValidator diagnostics on the current buffer' })

local group = vim.api.nvim_create_augroup('NvimGlslxValidate', { clear = true })

vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
  group = group,
  pattern = { '*.frag', '*.vert', '*.comp', '*.geom', '*.tesc', '*.tese' },
  callback = function(args)
    if vim.g.glsl_validator_validate_on_save == false then return end
    -- Defer slightly so the file is fully flushed before glslang reads it.
    vim.schedule(function()
      pcall(function()
        lazy_validator().validate_buffer(args.buf)
      end)
    end)
  end,
})
