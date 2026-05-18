-- glslangValidator wrapper for OpenGL GLSL diagnostics.
--
-- Public API:
--   M.validate_buffer(bufnr)   run validator on a buffer, publish diagnostics
--   M.stage_for_path(path)     return glslang stage ("frag","vert","comp",...) or nil
--   M.setup(opts)              optional one-time configuration

local M = {}

local preprocess = require('glslx.preprocess')

local ns = vim.api.nvim_create_namespace('glslx_validator')

local config = {
  executable = 'glslangValidator',
  extra_args = {},
  -- map extension -> glslang -S stage
  stages = {
    frag = 'frag',
    vert = 'vert',
    comp = 'comp',
    geom = 'geom',
    tesc = 'tesc',
    tese = 'tese',
  },
}

function M.setup(opts)
  opts = opts or {}
  if opts.executable then config.executable = opts.executable end
  if opts.extra_args then config.extra_args = opts.extra_args end
  if opts.stages then
    for k, v in pairs(opts.stages) do config.stages[k] = v end
  end
end

local function ext_of(path)
  return (path:match('%.([%w]+)$') or ''):lower()
end

function M.stage_for_path(path)
  return config.stages[ext_of(path)]
end

-- glslangValidator emits lines like:
--   ERROR: 0:12: 'foo' : undeclared identifier
--   WARNING: 0:7: '#extension' : ...
--   ERROR: tmpfile:12: 'foo' : undeclared identifier   (some versions)
-- followed by summary lines we discard.
local function parse_glslang_output(output, tmp_path)
  local diags = {}
  for raw in output:gmatch('[^\r\n]+') do
    -- Try the common forms in order. We don't anchor with ^ because some
    -- builds prefix the line with the temp file basename.
    local severity_str, line_no, msg

    severity_str, line_no, msg =
      raw:match('^(%u+):%s*[^:]*:(%d+):%s*(.*)$')
    if not severity_str then
      -- "ERROR: 0:12: foo" without extra colon
      severity_str, line_no, msg =
        raw:match('^(%u+):%s*%d+:(%d+):%s*(.*)$')
    end

    if severity_str and line_no and msg then
      local sev = vim.diagnostic.severity.ERROR
      if severity_str == 'WARNING' then
        sev = vim.diagnostic.severity.WARN
      elseif severity_str == 'INFO' or severity_str == 'NOTE' then
        sev = vim.diagnostic.severity.INFO
      end
      diags[#diags + 1] = {
        lnum = tonumber(line_no) - 1,
        col = 0,
        severity = sev,
        message = msg,
        source = 'glslangValidator',
      }
    elseif raw:match('^ERROR:') or raw:match('^WARNING:') then
      -- Catch-all for lines we couldn't pattern-match: report on line 1.
      diags[#diags + 1] = {
        lnum = 0,
        col = 0,
        severity = vim.diagnostic.severity.ERROR,
        message = raw,
        source = 'glslangValidator',
      }
    end
  end
  return diags
end

-- Map a diagnostic produced against the expanded file to the original buffer
-- using the sourcemap from preprocess.expand().
local function remap_diagnostic(d, sourcemap, root_path, bufnr)
  local entry = sourcemap[d.lnum + 1]
  if not entry then
    -- Default to last line of the original buffer.
    local n = vim.api.nvim_buf_line_count(bufnr)
    return {
      bufnr = bufnr,
      lnum = math.max(0, n - 1),
      col = 0,
      severity = d.severity,
      message = d.message,
      source = d.source,
    }
  end
  if entry.file == root_path then
    return {
      bufnr = bufnr,
      lnum = math.max(0, entry.line - 1),
      col = 0,
      severity = d.severity,
      message = d.message,
      source = d.source,
    }
  end
  -- Error originates inside an included file. Surface it on the root buffer
  -- at line 1 with the included file path prepended to the message so the
  -- user can jump to it.
  return {
    bufnr = bufnr,
    lnum = 0,
    col = 0,
    severity = d.severity,
    message = string.format('%s:%d: %s', entry.file, entry.line, d.message),
    source = d.source,
  }
end

local function write_tmp(text)
  local tmp = vim.fn.tempname() .. '.glsl'
  local fd = assert(io.open(tmp, 'w'))
  fd:write(text)
  fd:close()
  return tmp
end

local function run_glslang(stage, tmp_path)
  local cmd = { config.executable, '-S', stage }
  for _, a in ipairs(config.extra_args) do cmd[#cmd + 1] = a end
  cmd[#cmd + 1] = tmp_path

  -- vim.system is preferred (0.10+); fall back to systemlist.
  if vim.system then
    local res = vim.system(cmd, { text = true }):wait()
    return (res.stdout or '') .. (res.stderr or ''), res.code
  end
  local out = vim.fn.systemlist(cmd)
  return table.concat(out, '\n'), vim.v.shell_error
end

function M.validate_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' then
    vim.notify('glslx: buffer has no file name; save it first', vim.log.levels.WARN)
    return
  end

  local stage = M.stage_for_path(path)
  if not stage then
    vim.notify('glslx: unsupported extension for ' .. path, vim.log.levels.WARN)
    return
  end

  if vim.fn.executable(config.executable) ~= 1 then
    vim.notify(
      'glslx: ' .. config.executable .. ' not found on $PATH. Install glslang (e.g. `sudo pacman -S glslang`).',
      vim.log.levels.ERROR
    )
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local root_text = table.concat(lines, '\n')

  local expanded, sourcemap, inc_errors = preprocess.expand(path, root_text)

  local tmp = write_tmp(expanded)
  local output, _code = run_glslang(stage, tmp)
  pcall(os.remove, tmp)

  local raw_diags = parse_glslang_output(output, tmp)
  local final = {}
  for _, d in ipairs(inc_errors) do
    final[#final + 1] = {
      bufnr = bufnr,
      lnum = math.max(0, (d.line or 1) - 1),
      col = 0,
      severity = vim.diagnostic.severity.ERROR,
      message = d.message,
      source = 'glslx-include',
    }
  end
  for _, d in ipairs(raw_diags) do
    final[#final + 1] = remap_diagnostic(d, sourcemap, path, bufnr)
  end

  vim.diagnostic.set(ns, bufnr, final)
end

function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.diagnostic.set(ns, bufnr, {})
end

M._ns = ns
M._config = config

return M
