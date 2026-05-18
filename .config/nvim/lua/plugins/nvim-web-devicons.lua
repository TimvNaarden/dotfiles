-- ~/.config/nvim/lua/plugins/devicons.lua
return {
  {
    "nvim-tree/nvim-web-devicons",
    opts = function(_, opts)
      opts.override = opts.override or {}

      local shader_icon = ""
      local shader_color = "#5586a6"
      -- Apply to all GLSL-ish extensions you care about
      opts.override.comp = {
        icon = shader_icon,
        color = shader_color,
        name = "GlslComp",
      }
      opts.override.geom = {
        icon = shader_icon,
        color = shader_color,
        name = "GlslGeom",
      }
      opts.override.tesc = {
        icon = shader_icon,
        color = shader_color,
        name = "GlslTesc",
      }
      opts.override.tese = {
        icon = shader_icon,
        color = shader_color,
        name = "GlslTese",
      }
      opts.override.glsl = {
        icon = shader_icon,
        color = shader_color,
        name = "GlslFile",
      }

      return opts
    end,
  },
}
