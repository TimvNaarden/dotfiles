-- Register the OpenGL GLSL shader extensions as filetype `glsl`.
-- Loaded at startup by Neovim's filetype.lua mechanism.

vim.filetype.add({
  extension = {
    frag = 'glsl',
    vert = 'glsl',
    comp = 'glsl',
    geom = 'glsl',
    tesc = 'glsl',
    tese = 'glsl',
    glsl = 'glsl',
  },
})
