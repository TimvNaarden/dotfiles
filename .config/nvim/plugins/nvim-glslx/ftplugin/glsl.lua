-- ftplugin for filetype=glsl (OpenGL GLSL shaders).
--
-- Sets buffer-local options sensible for shader files and triggers the
-- syntax overlay that adds the function-style `#include(...)` highlight.

if vim.b.did_ftplugin_glsl_nvim_glslx then
  return
end
vim.b.did_ftplugin_glsl_nvim_glslx = 1

local bo = vim.bo
local opt_local = vim.opt_local

bo.commentstring = '// %s'
bo.comments = 's1:/*,mb:*,ex:*/,://'

opt_local.suffixesadd:prepend('.glsl')
opt_local.suffixesadd:prepend('.frag')
opt_local.suffixesadd:prepend('.vert')
opt_local.suffixesadd:prepend('.comp')

opt_local.include = [[^\s*#\s*include]]

opt_local.expandtab = true
bo.shiftwidth = 2
bo.softtabstop = 2

-- Layered syntax: source Vim's built-in GLSL syntax (if not already active)
-- and then add overlays for function-style #include from syntax/glsl.vim
-- shipped with this plugin.
if vim.fn.exists(':compiler') == 2 then
  pcall(vim.cmd, 'compiler glslang')
end

vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
  .. '|setl commentstring< comments< include< suffixesadd< expandtab< shiftwidth< softtabstop<'
