# Neovim on Debian (WSL2)

Gets the Neovim setup in this repo working on Debian under WSL2, plus tmux and
zsh so the editor sits in the same shell it does on the desktop machine.

Verified against the Arch machine this repo is committed from: Neovim 0.12.5,
NvChad v2.5, coc.nvim as the only language client.

Work top to bottom. Each step says how to check it worked.

---

## 0. What this guide does not do

This repo is a **single flat stow package**: the root maps straight onto `$HOME`.
Running `stow .` on WSL would therefore link Hyprland, waybar, wofi, noctalia,
gtk and qt configuration into a machine with no display server at all. Harmless
but pointless, and it makes `git status` noisy on a box where you will never
touch those files.

So this guide links the four things you actually want by hand, and leaves stow
for the Arch machine. See [INSTALL-arch.md](INSTALL-arch.md) for that.

---

## 1. Neovim itself

This is the step that will bite you. `init.lua` calls `vim.uv`, which did not
exist before Neovim 0.10, and NvChad v2.5 wants a recent 0.10+ anyway. Debian's
packaged Neovim is far too old: bookworm ships 0.7.2, and even trixie is behind
what this config was written against.

Install upstream's static build instead:

```sh
NVIM_VERSION=v0.12.5
curl -fsSLO "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz"
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz
sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
rm nvim-linux-x86_64.tar.gz
```

On ARM (a Windows-on-ARM host) swap `x86_64` for `arm64` in both the asset name
and the extracted directory.

Do **not** `apt install neovim` alongside this. Two Neovims on `PATH` is how you
end up debugging a config against the wrong binary for an hour.

Check:

```sh
nvim --version | head -1        # expect v0.12.5 or newer
command -v nvim                 # expect /usr/local/bin/nvim
```

---

## 2. System packages

```sh
sudo apt update
sudo apt install -y \
  git curl unzip tar gzip build-essential \
  zsh tmux stow \
  ripgrep fd-find \
  python3 python3-venv \
  glslang-tools \
  wslu
```

Why each of the less obvious ones:

| Package | Needed by |
| --- | --- |
| `build-essential` | nvim-treesitter compiles every parser from C at install time. Without a compiler `:Lazy sync` looks fine and then no highlighting works. |
| `ripgrep`, `fd-find` | NvChad's telescope pickers |
| `python3` | the tmux status-bar scripts in `.config/tmux/scripts/` |
| `glslang-tools` | provides `glslangValidator`, which `lua/plugins/glslx.lua` shells out to for shader diagnostics. Skip if you do not write GLSL. |
| `wslu` | provides `wslview`, used in step 7 to open a browser on the Windows side |

### Debian renames two binaries

`fd` is called `fdfind` on Debian because of a name clash, and telescope looks
for `fd`. Bridge it:

```sh
mkdir -p ~/.local/bin
ln -sf "$(command -v fdfind)" ~/.local/bin/fd
```

`.zshrc` already puts `~/.local/bin` on `PATH`. If you also use `bat`, the same
applies: Debian installs it as `batcat`.

Check:

```sh
command -v gcc rg fd python3 glslangValidator wslview
```

---

## 3. Node, or coc.nvim will not start

coc.nvim is the only completion engine and language client in this config, and
it is a Node program. `lua/plugins/coc.lua` pins `branch = "release"`, so it is
prebuilt and needs no npm build step, but it still needs a Node runtime.

`.zshrc` sources nvm, so use nvm and the two agree:

```sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
exec zsh -l          # or open a new shell
nvm install --lts
```

`coc.lua` also has a fallback: when nothing named `node` is on `PATH` it globs
`~/.nvm/versions/node/*/bin/node` and pins the newest. That covers launching
Neovim from somewhere nvm was never sourced.

Check: `node --version` returns v18 or newer.

---

## 4. Clone and link

```sh
git clone https://github.com/timvnaarden/dotfiles ~/dotfiles
cd ~/dotfiles
git checkout Cachy-os
```

Then link only what makes sense here. These are relative links, matching the
form stow uses, so a later `stow` run on this machine recognises them as its own
rather than reporting a conflict:

```sh
mkdir -p ~/.config ~/.claude
ln -s ../dotfiles/.config/nvim  ~/.config/nvim
ln -s ../dotfiles/.config/tmux  ~/.config/tmux
ln -s dotfiles/.tmux.conf       ~/.tmux.conf
ln -s dotfiles/.zshrc           ~/.zshrc
ln -s ../dotfiles/.claude/settings.json ~/.claude/settings.json
```

Check that all five resolve into the repo:

```sh
readlink -f ~/.config/nvim ~/.config/tmux ~/.tmux.conf ~/.zshrc ~/.claude/settings.json
```

### Shell

`.zshrc` expects oh-my-zsh plus two custom plugins that oh-my-zsh does not
bundle. Without them zsh prints an error on every start:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --keep-zshrc
git clone https://github.com/zsh-users/zsh-autosuggestions \
  ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting \
  ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
chsh -s "$(command -v zsh)"
```

`--keep-zshrc` matters: without it the installer replaces the symlink with its
own template and your edits stop reaching the repo.

### tmux

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
tmux new -s main          # then press prefix + I, where prefix is Ctrl-s
```

---

## 5. Fix the hardcoded paths in coc-settings.json

`.config/nvim/coc-settings.json` has two absolute paths baked in from the Arch
machine. Both are under `languageserver`, so a mismatch fails silently: the
server simply never starts.

```sh
cd ~/dotfiles

# Haskell: let $PATH resolve it. coc.lua already prepends mason's bin directory
# before coc loads, precisely so mason binaries are visible to it.
sed -i 's#"/home/tim/.local/share/nvim/mason/bin/haskell-language-server-wrapper"#"haskell-language-server-wrapper"#' \
  .config/nvim/coc-settings.json
```

The `arduino` block below it points at `/usr/bin/clangd`, `/usr/bin/arduino-cli`
and `/home/tim/.arduinoIDE/arduino-cli.yaml`. WSL has no USB serial access
without extra kernel work, so Arduino development is not happening here. Delete
that whole `"arduino": { ... }` entry rather than trying to repoint it.

> **Do not commit these edits to a shared branch.** `coc-settings.json` is
> tracked, so changing it here and pushing to `Cachy-os` breaks the Arch
> machine. Either keep the edits local, or branch:
> `git checkout -b debian-wsl`.

### Haskell

`coc-settings.json` registers `haskell-language-server-wrapper` as a
`languageserver`, and `nvim-treesitter.lua` pulls the `haskell` parser, so the
editor half needs nothing extra. The toolchain does:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
exec zsh -l
```

Then install HLS through mason, which is where the wrapper is expected to live
after the `sed` above puts it back on `PATH`:

```
:MasonInstall haskell-language-server
```

Note that `.zshrc` sources ghcup with a hardcoded path:

```sh
[ -f "/home/tim/.ghcup/env" ] && . "/home/tim/.ghcup/env"
```

The `[ -f ]` guard means it fails silently rather than erroring, so if your WSL
username is not `tim` ghcup simply never loads and `ghc` is missing from `PATH`
with no explanation. Either match the path or change it to `$HOME/.ghcup/env`,
on a branch, per the warning above.

Check: `ghc --version`, then open a `.hs` file and confirm `:CocInfo` lists the
haskell service as running.

### clangd, if you want C or C++

`coc-clangd` can fetch its own binary, which is simpler than matching Debian's
versioned packages:

```
:CocCommand clangd.install
```

Otherwise `sudo apt install clangd` and confirm `command -v clangd` resolves.

---

## 6. First launch

```sh
nvim --headless "+Lazy! sync" +qa
```

Then open `nvim` and leave it for a minute. Two sets of things install on their
own, and neither is part of `Lazy sync`:

* **coc extensions**, the twelve names in `g:coc_global_extensions` in
  `lua/plugins/coc.lua`, into `~/.config/coc/extensions/`. This is where Node
  gets used, so a missing Node shows up here first.
* **mason packages**, the six in `ensure_installed` in `lua/plugins/mason.lua`.
  These are formatters and debug adapters only, not language servers, since coc
  manages its own. mason.nvim has no `ensure_installed` of its own and NvChad
  v2.5 dropped `:MasonInstallAll`, so `mason.lua` runs its own installer in its
  `config` function.

Check:

```sh
ls ~/.config/coc/extensions/node_modules | wc -l   # expect 12
ls ~/.local/share/nvim/mason/bin                   # stylua, prettier, prettierd,
                                                   # clang-format, codelldb,
                                                   # js-debug-adapter
nvim --headless "+lua print('ok')" +qa             # prints ok, no errors
```

Inside Neovim, `:CocInfo` should report a running service and `:checkhealth` no
errors under `nvim-treesitter`.

---

## 7. WSL-specific fixes

### Clipboard

Neovim cannot reach the Windows clipboard on its own. `win32yank` is what
Neovim's own WSL support looks for:

```sh
curl -fsSLO https://github.com/equalsraf/win32yank/releases/latest/download/win32yank-x64.zip
unzip -j win32yank-x64.zip win32yank.exe -d ~/.local/bin
chmod +x ~/.local/bin/win32yank.exe
rm win32yank-x64.zip
```

Check: `:checkhealth provider` reports a clipboard tool, and `"+yy` then pasting
into a Windows app works.

Do not bother with `wl-clipboard` or `xclip` here. Both need a display server
that plain WSL2 does not have.

### markdown-preview

`lua/plugins/markdown-preview.lua` does two things that assume the Arch desktop.
Its `build` step runs `cd app && yarn install`, so yarn has to exist:

```sh
npm install -g yarn
```

And its `OpenMarkdownPreview` function hardcodes `google-chrome-stable`, which
is not installed on WSL. Point it at the Windows browser instead by adding this
to the bottom of `~/.config/nvim/lua/options.lua`:

```lua
-- WSL: hand preview URLs to the Windows default browser.
vim.g.mkdp_browserfunc = ""
vim.g.mkdp_open_to_the_world = 0
vim.g.mkdp_browser = "wslview"
```

Same warning as step 5 about committing that to a shared branch.

### Copilot

`copilot.lua` runs with `auto_trigger` on and ghost text enabled, accepted with
`Alt-l`. It needs a one-time device login:

```
:Copilot auth
```

Auth lands in `~/.config/github-copilot/`, which is **deliberately not tracked**
in this repo because it holds a token. Do not add it.

---

## 8. Deliberately absent on WSL

Not bugs, just things with no meaning on a machine without a desktop:

| Not installed | Why |
| --- | --- |
| Hyprland, waybar, wofi, noctalia, kitty | no display server |
| `roslyn.nvim` C# LSP | needs `dotnet`; install `dotnet-sdk` and `:MasonInstall roslyn` if you want it |
| Arduino language server | no USB serial in plain WSL2 |
| The tmux desktop notifications | `notify-send` has no daemon to reach. The tab colouring in `.tmux.conf` still works; only the popups are gone. |

---

## 9. Full verification

```sh
nvim --version | head -1
readlink -f ~/.config/nvim ~/.tmux.conf ~/.zshrc
node --version
command -v gcc rg fd python3
nvim --headless "+Lazy! check" +qa
ls ~/.config/coc/extensions/node_modules | wc -l      # expect 12
# mason's bin count is not 6: clang-format alone installs three binaries, so
# check the six by name instead.
for b in stylua prettier prettierd clang-format codelldb js-debug-adapter; do
  [ -e ~/.local/share/nvim/mason/bin/$b ] || echo "missing: $b"
done
nvim --headless "+checkhealth nvim-treesitter" "+w! /tmp/th.txt" +qa && grep -i error /tmp/th.txt
```

Open a real TypeScript or Python file and confirm completion appears on typing
and `gd` jumps to a definition. That exercises Node, coc and the extension
install in one go, which is where nearly every failure on this platform ends up.
