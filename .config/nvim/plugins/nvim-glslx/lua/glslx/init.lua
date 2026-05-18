-- Public Lua API for nvim-glslx.
--
-- Usage:
--   require('glslx').setup({ ... })            -- optional
--   require('glslx').validate()                -- current buffer
--   require('glslx').validate(bufnr)
--   require('glslx').clear(bufnr)

local M = {}

local validator = require('glslx.validator')
local preprocess = require('glslx.preprocess')

M.validator = validator
M.preprocess = preprocess

function M.setup(opts)
  opts = opts or {}
  if opts.validator then validator.setup(opts.validator) end
  if opts.validate_on_save ~= nil then
    vim.g.glsl_validator_validate_on_save = opts.validate_on_save
  end
end

function M.validate(bufnr)
  validator.validate_buffer(bufnr)
end

function M.clear(bufnr)
  validator.clear(bufnr)
end

return M
