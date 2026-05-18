# nvim-glslx

A small Neovim plugin that gives you **diagnostics for OpenGL GLSL shaders**
(`.frag`, `.vert`, `.comp`, `.geom`, `.tesc`, `.tese`) by driving
`glslangValidator` over the buffer. It also expands `#include` directives in
pure Lua before validation so multi-file shader projects validate cleanly.

This is **not** an LSP. There is no language server, no node, no npm, no
TypeScript build step. The whole plugin is Lua plus a couple of Vim files.

## What you get

- `#version 430 core`, `layout(local_size_x = ...) in;`, layout qualifiers,
  UBOs, SSBOs, and every other piece of desktop OpenGL GLSL syntax — because
  the underlying validator is Khronos `glslangValidator`, which is the
  reference parser.
- `#include` directive support, in three forms:

  ```glsl
  #include "common.glsl"
  #include("common.glsl");
  #include('common.glsl');
  ```

  Includes resolve **relative to the file that contains the directive**.
  Includes are expanded recursively. Duplicate includes (same normalized
  absolute path) are skipped. `#version` lines inside included files are
  stripped so only the root file's `#version` survives at the top of the
  expanded unit. Include errors (file not found, depth overflow) are
  reported as Neovim diagnostics on the root buffer.

- Diagnostics on the original buffer via `vim.diagnostic`. Errors from the
  root file map to the correct line. Errors from inside an included file
  are reported on line 1 of the root buffer with `included_file:line:` in
  the message so you can navigate to them.

- User commands:

  - `:GlslValidate` — run the validator on the current buffer.
  - `:GlslBuild` — alias for `:GlslValidate`.
  - `:GlslClear` — clear diagnostics on the current buffer.

- Validate-on-save autocmd for the registered shader extensions. Toggle
  with `vim.g.glsl_validator_validate_on_save = true / false`.

- A `:compiler glslang` definition so `:make %` works if you'd rather use
  the quickfix list.

## Note on `.glslx`

This plugin replaces the old `.glslx`-LSP version. If you author files
specifically in the [GLSLX](https://github.com/evanw/glslx) dialect (a
distinct WebGL-targeted dialect with its own parser), use the upstream
`glslx-vscode` server separately — it is not bundled here anymore.

## Install — Arch Linux + NvChad / lazy.nvim

1. Install the validator:

   ```sh
   sudo pacman -S glslang
   ```

   This provides `/usr/bin/glslangValidator`. Verify:

   ```sh
   glslangValidator -v
   ```

2. Unzip the package and put the plugin where lazy.nvim expects it:

   ```sh
   cd ~/Downloads
   unzip nvim-glslx-package.zip          # creates nvim-glslx/ and glslx.lua
   mkdir -p ~/dev
   mv nvim-glslx ~/dev/nvim-glslx
   mv glslx.lua ~/.config/nvim/lua/plugins/glslx.lua
   ```

3. Restart Neovim. Lazy will pick up the spec; the plugin is pure Lua so
   there is no `build` step. Confirm with:

   ```vim
   :Lazy
   ```

   You should see `nvim-glslx` listed. Open a `.frag` or `.comp` file and
   run `:GlslValidate` — diagnostics should appear (or no diagnostics, if
   the shader is clean).

## Example shaders

A minimal compute shader with an include — drop both files in a directory
and open `compute.comp`:

```glsl
// compute.comp
#version 430 core

#include("common.glsl");

layout(local_size_x = 16, local_size_y = 16) in;

layout(std430, binding = 0) buffer Data {
    float values[];
};

void main() {
    uint i = gl_GlobalInvocationID.x;
    values[i] = scale(values[i]);
}
```

```glsl
// common.glsl
float scale(float x) {
    return x * 2.0;
}
```

A minimal fragment shader:

```glsl
// basic.frag
#version 430 core

layout(location = 0) out vec4 fragColor;

in vec2 vUV;

void main() {
    fragColor = vec4(vUV, 0.0, 1.0);
}
```

Open either file and run `:GlslValidate`. Introduce a typo (e.g. change
`fragColor` to `fragclor`) and re-run — you should see an error diagnostic
on the offending line.

## Configuration

The plugin spec already calls `require('glslx').setup({})` with sensible
defaults. To customize, edit `~/.config/nvim/lua/plugins/glslx.lua`:

```lua
config = function()
  require('glslx').setup({
    validator = {
      executable = 'glslangValidator',
      extra_args = { '--target-env', 'opengl' }, -- example
    },
    validate_on_save = true,
  })
end,
```

To disable validate-on-save globally without touching the plugin spec:

```vim
:let g:glsl_validator_validate_on_save = v:false
```

## How it works

`require('glslx.preprocess').expand(path, text)` walks the shader text,
recursively expanding the three supported `#include` forms. It records a
per-output-line source map so diagnostics can be remapped back to the
original buffer. The expanded source is written to a temp file and
`glslangValidator -S <stage> <tmp>` is invoked. Output is parsed with a
small regex, severities are mapped to `vim.diagnostic.severity`, and
diagnostics are published via `vim.diagnostic.set` against the original
buffer.

The stage is chosen from the file extension:

| Extension | Stage  |
| --------- | ------ |
| `.frag`   | `frag` |
| `.vert`   | `vert` |
| `.comp`   | `comp` |
| `.geom`   | `geom` |
| `.tesc`   | `tesc` |
| `.tese`   | `tese` |

## Troubleshooting

**`glslx: glslangValidator not found on $PATH`.**

Install it: `sudo pacman -S glslang`. The binary should land at
`/usr/bin/glslangValidator`. If you have a custom build, point the plugin
at it:

```lua
require('glslx').setup({ validator = { executable = '/opt/glslang/bin/glslangValidator' } })
```

**No diagnostics appear even though the shader is broken.**

1. Confirm the buffer's filetype: `:set ft?` should print `filetype=glsl`.
   If it's empty, the ftdetect file did not run — make sure the plugin
   spec is loaded (`:Lazy`).
2. Run `:GlslValidate` manually and watch for `:messages`. The plugin
   prints a notification if the executable is missing or the extension
   is not registered.
3. Make sure the file is saved if you're relying on validate-on-save —
   the autocmd is `BufWritePost`.

**Diagnostics from an included file point to line 1 of the root buffer.**

That's by design: glslangValidator reports line numbers against the
preprocessed unit, and the plugin's source map remaps each diagnostic
back. When the line originates inside an included file, the plugin
surfaces it at line 1 of the root buffer and prefixes the message with
the included file's absolute path and original line number so you can
jump to it.

**Compute shader fails with `'#version' : compute shaders require...`**

`glslangValidator` requires `#version 430` or higher (or `#version 310 es`)
for compute shaders. Use `#version 430 core` as shown in the example.

**Validate manually from the shell to rule out plugin issues.**

```sh
glslangValidator -S comp compute.comp
```

If the shell invocation also fails, the issue is in the shader, not the
plugin.

## Layout

```
~/dev/nvim-glslx/
├─ README.md
├─ ftdetect/glsl.lua          # register .frag/.vert/.comp/... as filetype=glsl
├─ ftplugin/glsl.lua          # buffer-local options for glsl
├─ syntax/glsl.vim            # overlay for function-style #include(...) syntax
├─ compiler/glslang.vim       # :compiler glslang for :make %
├─ plugin/glslx.lua           # commands + validate-on-save autocmd
└─ lua/glslx/
   ├─ init.lua                # public API: setup(), validate(), clear()
   ├─ preprocess.lua          # #include expansion + source map
   └─ validator.lua           # glslangValidator runner + diagnostic parser
```
