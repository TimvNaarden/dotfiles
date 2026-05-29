local M = {}
M.macros = {}
M._active_keymaps = {} -- track registered keys for cleanup

local function load_file(path)
  local f = loadfile(path)
  if f then
    local ok, result = pcall(f)
    if ok and type(result) == "table" then
      return result
    end
  end
end

local function clear_keymaps()
  for _, map in ipairs(M._active_keymaps) do
    pcall(vim.keymap.del, "n", map)
  end
  M._active_keymaps = {}
end

local function apply_keymaps(keymaps)
  clear_keymaps()
  for lhs, rhs in pairs(keymaps or {}) do
    if type(rhs) == "string" then
      vim.keymap.set("n", lhs, rhs, { desc = "Project macro", silent = true })
    elseif type(rhs) == "table" then
      -- Support { "cmd", "description" } format — same as NvChad style
      vim.keymap.set("n", lhs, rhs[1], { desc = rhs[2] or "Project macro", silent = true })
    end
    table.insert(M._active_keymaps, lhs)
  end
end

function M.setup()
  -- Load global defaults (~/.nvim-project.lua)
  local g = load_file(vim.fn.expand "~/.nvim-project.lua")
  if g then
    M.macros = vim.tbl_deep_extend("force", M.macros, g.macros or {})
    apply_keymaps(g.keymaps)
  end

  -- Load local cwd config (.nvim-project.lua) — overrides global
  local function load_local()
    local path = vim.fn.getcwd() .. "/.nvim-project.lua"
    local l = load_file(path)
    if l then
      M.macros = vim.tbl_deep_extend("force", M.macros, l.macros or {})
      apply_keymaps(l.keymaps)
      if l.on_load then
        l.on_load()
      end
      --vim.notify("📁 Project config loaded", vim.log.levels.INFO)
    else
      clear_keymaps()
    end
  end

  load_local()

  -- Re-load when cwd changes (e.g. :cd into another project)
  vim.api.nvim_create_autocmd("DirChanged", {
    callback = function()
      M.macros = {}
      load_local()
    end,
    desc = "Reload project config on directory change",
  })

  vim.api.nvim_create_user_command("ReloadProject", function()
    M.macros = {}
    load_local()
    vim.notify("Project macros reloaded", vim.log.levels.INFO)
  end, { desc = "Reload .nvim-project.lua" })

  vim.keymap.set("n", "<leader>rp", "<cmd>ReloadProject<CR>", { desc = "Reload project macros" })

  -- Commands that launch interactive apps — run async in a terminal split
  local async_cmds = { run = true, debug = true, release = true }

  for cmd, key in pairs {
    RunCompile = "compile",
    RunTest = "test",
    RunRun = "run",
    RunLint = "lint",
    RunUpload = "upload",
    RunDebug = "debug",
    RunRelease = "release",
    RunBuild = "build",
    RunClean = "clean",
  } do
    local k = key
    vim.api.nvim_create_user_command(cmd, function()
      if M.macros[k] then
        if async_cmds[k] then
          -- Open a terminal split, run there — non-blocking
          vim.cmd("split | terminal " .. M.macros[k])
        else
          vim.cmd("!" .. M.macros[k])
        end
      else
        vim.notify("No '" .. k .. "' macro set in .nvim-project.lua", vim.log.levels.WARN)
      end
    end, { desc = "Run project " .. k })
  end
end

return {
  {
    dir = vim.fn.stdpath "config",
    name = "project-macros",
    lazy = false,
    priority = 900,
    config = M.setup,
  },
}
