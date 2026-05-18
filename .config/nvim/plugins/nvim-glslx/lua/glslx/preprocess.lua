-- Preprocessor: expands #include directives in a GLSL buffer.
--
-- Supported include forms (on a line by themselves, optionally indented):
--   #include "path"
--   #include("path");
--   #include('path');
--
-- Resolution: relative to the including file's directory. Recursive.
-- Duplicate includes (by normalized absolute path) are skipped.
-- The very first #version line from the root file is kept at the top;
-- any #version lines encountered in included files are stripped.

local M = {}

local uv = vim.uv or vim.loop

local function read_file(path)
  local fd = uv.fs_open(path, 'r', 420)
  if not fd then return nil end
  local stat = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return nil
  end
  local data = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  return data
end

local function buf_lines_or_file(path)
  -- Prefer an open buffer's contents over the on-disk copy so unsaved edits
  -- are reflected in diagnostics.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= '' and uv.fs_realpath(name) == path then
        return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
      end
    end
  end
  return read_file(path)
end

-- Parse one of the supported include forms. Returns the include path (string)
-- or nil if the line is not an include directive.
local function parse_include(line)
  -- Function-style: #include("foo");  or  #include('foo');
  local p = line:match('^%s*#%s*include%s*%(%s*"([^"]+)"%s*%)%s*;?%s*$')
  if p then return p end
  p = line:match("^%s*#%s*include%s*%(%s*'([^']+)'%s*%)%s*;?%s*$")
  if p then return p end
  -- Native form: #include "foo"  (also tolerate a trailing semicolon)
  p = line:match('^%s*#%s*include%s+"([^"]+)"%s*;?%s*$')
  if p then return p end
  p = line:match("^%s*#%s*include%s+'([^']+)'%s*;?%s*$")
  if p then return p end
  return nil
end

local function is_version_line(line)
  return line:match('^%s*#%s*version%s+%S') ~= nil
end

-- Source map entry: one per output line.
--   { file = absolute_path, line = 1-based-line-in-that-file }
local function new_map_entry(file, lineno)
  return { file = file, line = lineno }
end

-- Recursive expander.
--   text:     string contents of current unit
--   path:     absolute path of current unit (used to resolve includes)
--   visited:  table of normalized paths already included; mutated
--   diags:    array of { file, line, message } accumulated include errors
--   is_root:  whether this is the top-level file (controls #version handling)
local function expand(text, path, visited, diags, is_root, depth)
  if depth > 64 then
    diags[#diags + 1] = { file = path, line = 1, message = 'include depth exceeded (>64)' }
    return {}, {}
  end

  local out_lines, out_map = {}, {}
  local dir = vim.fs.dirname(path)
  local saw_version = false
  local lineno = 0

  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    lineno = lineno + 1
    local inc = parse_include(line)
    if inc then
      -- Resolve relative to current file's directory.
      local resolved
      if inc:sub(1, 1) == '/' then
        resolved = inc
      else
        resolved = dir .. '/' .. inc
      end
      local abs = uv.fs_realpath(resolved) or resolved

      if visited[abs] then
        -- Duplicate include: skip silently, but emit a blank line so line
        -- numbers in the *current* file stay aligned with anything below.
        out_lines[#out_lines + 1] = ''
        out_map[#out_map + 1] = new_map_entry(path, lineno)
      else
        visited[abs] = true
        local inc_text = buf_lines_or_file(abs)
        if not inc_text then
          diags[#diags + 1] = {
            file = path,
            line = lineno,
            message = "cannot open include '" .. inc .. "'",
          }
          out_lines[#out_lines + 1] = ''
          out_map[#out_map + 1] = new_map_entry(path, lineno)
        else
          local sub_lines, sub_map = expand(inc_text, abs, visited, diags, false, depth + 1)
          for i = 1, #sub_lines do
            out_lines[#out_lines + 1] = sub_lines[i]
            out_map[#out_map + 1] = sub_map[i]
          end
        end
      end
    elseif is_version_line(line) then
      if is_root and not saw_version then
        saw_version = true
        out_lines[#out_lines + 1] = line
        out_map[#out_map + 1] = new_map_entry(path, lineno)
      else
        -- Strip #version from included files; replace with blank to keep
        -- the included file's own line numbers aligned.
        out_lines[#out_lines + 1] = ''
        out_map[#out_map + 1] = new_map_entry(path, lineno)
      end
    else
      out_lines[#out_lines + 1] = line
      out_map[#out_map + 1] = new_map_entry(path, lineno)
    end
  end

  return out_lines, out_map
end

-- Public entry. Given the root file's path and its text, return:
--   text:     the fully expanded shader source as a single string
--   sourcemap: array; sourcemap[i] = { file=..., line=... } for output line i
--   diags:    array of include-resolution errors as { file, line, message }
function M.expand(root_path, root_text)
  local visited = {}
  local diags = {}
  local abs_root = uv.fs_realpath(root_path) or root_path
  visited[abs_root] = true
  local lines, map = expand(root_text, abs_root, visited, diags, true, 0)
  return table.concat(lines, '\n'), map, diags
end

return M
