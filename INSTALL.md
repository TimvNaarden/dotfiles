# Setting up a new machine

Everything here was verified against the machine this repo was last committed
from: CachyOS (Arch), Hyprland, kitty, zsh, tmux, Neovim 0.12.5.

Work top to bottom. Each step says how to check it worked.

---

## 0. How this repo is laid out

This is a **single flat stow package**: the repo root maps directly onto `$HOME`,
so `.config/nvim` in here becomes `~/.config/nvim`. There are no per-application
package directories.

That means the stow command is not the usual one:

```sh
stow -d ~/dotfiles -t ~ .
```

`stow -d ~ -t ~ dotfiles` silently does nothing, because stow refuses to treat a
directory as a package when it sits inside its own target. If stow reports
"skipping target which was current stow directory", you used the wrong form.

`INSTALL.md` and `packages/` are excluded from linking by `.stow-local-ignore`.

---

## 1. System packages

```sh
sudo pacman -S --needed - < packages/pacman-native.txt
```

That file is `pacman -Qqen`, the explicitly installed set. Some things the
configs depend on were pulled in as **dependencies** rather than explicitly, so
they are not in that list. Install them by name:

```sh
sudo pacman -S --needed zsh fd nodejs stow git curl unzip ripgrep \
                        clang gcc wl-clipboard zoxide noctalia hyprland kitty btop
```

AUR packages are in `packages/pacman-aur.txt`. Currently just `google-chrome`,
which needs an AUR helper such as `paru` or `yay`.

Check:

```sh
command -v zsh fd node stow rg fd zoxide
```

---

## 2. Clone and link

```sh
git clone <this-repo> ~/dotfiles
cd ~/dotfiles
stow -d ~/dotfiles -t ~ .
```

Stow refuses to overwrite real files. If it reports a conflict, the file already
exists in `$HOME`; move it aside and re-run.

Check that a few links resolve into the repo:

```sh
readlink ~/.zshrc ~/.tmux.conf ~/.config/nvim ~/.claude/settings.json
```

---

## 3. Shell

`.zshrc` expects oh-my-zsh plus two custom plugins that are **not** bundled with
it. Without them zsh prints an error on every start.

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --keep-zshrc
git clone https://github.com/zsh-users/zsh-autosuggestions \
  ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting \
  ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
chsh -s "$(command -v zsh)"
```

Pass `--keep-zshrc` so the installer does not replace the stowed `.zshrc` with
its own template, which would break the symlink.

`.zshrc` also puts `~/.cargo/bin` on `PATH`. That is harmless when Rust is not
installed; add `rustup` if you want it.

### Node via nvm

`.zshrc` sources nvm, and **coc.nvim needs node**. A system `nodejs` from pacman
also works; nvm just takes precedence on `PATH`.

```sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
# open a new shell, then:
nvm install --lts
```

Check: `node --version` returns v16 or newer.

---

## 4. tmux

TPM is **not** vendored in this repo. It used to be tracked as a git "gitlink"
with no `.gitmodules`, which meant a fresh clone produced empty plugin
directories and the plugins silently never loaded. `.tmux/plugins/` is now
gitignored and TPM installs everything itself.

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
tmux new -s main          # then press: prefix + I   (prefix is Ctrl-s)
```

Check: `ls ~/.tmux/plugins/` lists non-empty directories for every `@plugin`
line in `.tmux.conf`.

The status bar is styled directly in `.tmux.conf` using Catppuccin Mocha hex
values, so it does not depend on the catppuccin plugin being present. The
`@plugin "catppuccin/tmux"` line and the `@catppuccin_*` options are leftovers;
the config overrides them either way because it is sourced after `run tpm`.

### tmux status-bar scripts

`.config/tmux/scripts/` holds five Python/shell scripts the status bar calls.
They need `python3` and `git` (both already pacman dependencies) and nothing
else. They are stowed with the rest, so no extra step.

`claude-window-label.sh` names each window after the git branch of its first
Claude Code pane, falling back to the session title when several windows share a
branch, since three identical tabs identify nothing. Tab width is divided
between the windows on screen, so they shrink instead of overflowing.

---

## 5. Neovim

The config is NvChad v2.5 with **coc.nvim** as the only completion engine and
language client. nvim-lspconfig and nvim-cmp are explicitly disabled in
`lua/plugins/nvchad-lsp-off.lua`, because NvChad ships its own specs for both
and deleting local plugin files is not enough to stop lazy installing them.

```sh
nvim --headless "+Lazy! sync" +qa
```

Then open `nvim` once and leave it for a minute. Two things install on their own:

* **coc extensions**, from `g:coc_global_extensions` in `lua/plugins/coc.lua`.
  Twelve of them, including `@yaegassy/coc-tailwindcss3`. They land in
  `~/.config/coc/extensions/`.
* **mason packages**, from `ensure_installed` in `lua/plugins/mason.lua`.
  Plain mason.nvim has no `ensure_installed` support and NvChad v2.5 dropped the
  `:MasonInstallAll` command that used to read it, so `mason.lua` runs its own
  installer in its `config` function.

Check:

```sh
ls ~/.config/coc/extensions/node_modules          # 12 coc-* directories
ls ~/.local/share/nvim/mason/bin                  # stylua, prettier, prettierd,
                                                  # clang-format, codelldb,
                                                  # js-debug-adapter
nvim --headless "+lua print('ok')" +qa            # prints ok, no errors
```

Inside nvim, `:CocInfo` should report a running service. If it reports that node
is missing, coc falls back to the newest `~/.nvm/versions/node/*/bin/node`
automatically (see the `init` function in `lua/plugins/coc.lua`), which covers
launching nvim from a desktop entry where nvm has not been sourced.

### Optional language support

These are not installed by default and the config degrades quietly without them:

| Feature | Needs | Install |
| --- | --- | --- |
| C# LSP (`roslyn.nvim`) | `dotnet` | `sudo pacman -S dotnet-sdk` then `:MasonInstall roslyn` |
| C# debugging | `netcoredbg` | AUR |
| Arduino / ESP32 LSP | `arduino-cli`, `arduino-language-server` | `sudo pacman -S arduino-cli`, `:MasonInstall arduino-language-server` |

`roslyn.nvim` is the one remaining plugin that talks to Neovim's native LSP
rather than coc, because coc has no comparable C# extension. It only attaches to
`cs` files, so it never overlaps with coc.

---

## 6. Claude Code

`~/.claude/settings.json` is stowed and wires five hook events to the scripts in
`.config/tmux/scripts/`:

| Event | Script | Effect |
| --- | --- | --- |
| `SessionStart` / `SessionEnd` | `claude-pane-state.sh idle` | resets the tmux tab colour |
| `UserPromptSubmit` | `claude-pane-state.sh running` | tab turns blue |
| `UserPromptSubmit` | `claude-session-title.py` | retitles the session from your prompt |
| `PermissionRequest` | `claude-pane-state.sh needs-input` + `claude-notify.py` | tab turns yellow, desktop notification |
| `Stop` | `claude-pane-state.sh done` + `claude-notify.py` | tab turns green, desktop notification |

Notifications go through `notify-send`, which reaches whichever daemon owns
`org.freedesktop.Notifications`. On this setup that is noctalia. Check with:

```sh
busctl --user list | grep org.freedesktop.Notifications
notify-send -a "test" "hello" "world"
```

`prefix + N` in tmux mutes and unmutes them; a 🔕 appears in the status bar while
muted.

> **Watch this one.** Claude Code rewrites `settings.json` when you change model
> or theme. If it writes a new file rather than editing in place it will replace
> the symlink with a real file, and your changes stop reaching the repo. If
> `readlink ~/.claude/settings.json` comes back empty, copy the file back into
> the repo and re-run stow.

---

## 7. Not tracked here

Deliberately left out, listed so you know to redo them by hand:

* **kitty** (`~/.config/kitty/kitty.conf`). Holds the `shift+enter` and
  `ctrl+enter` mappings that send `\x1b\r`, which is what makes multi-line input
  work in Claude Code and at the zsh prompt. Without it Shift+Enter just submits.
  The matching zsh half (`bindkey '^[^M' self-insert-unmeta`) *is* tracked.
* **Browser profiles**, `gh` and `github-copilot` config. These hold auth tokens
  and must not be committed.
* **systemd coredump retention** (`/etc/tmpfiles.d/coredump.conf`,
  `/etc/systemd/coredump.conf.d/retention.conf`). Root-owned, outside `$HOME`.

---

## 8. Full verification

```sh
readlink ~/.zshrc ~/.tmux.conf ~/.config/nvim ~/.claude/settings.json
ls ~/.tmux/plugins/tpm/tpm
nvim --headless "+lua print('nvim ok')" +qa
ls ~/.config/coc/extensions/node_modules | wc -l      # expect 12
python3 ~/.config/tmux/scripts/claude-limits.py       # prints usage percentages
python3 ~/.config/tmux/scripts/claude-limits.py --debug   # cache freshness and token state
notify-send -a test "notifications work"
```

`claude-limits.py` reads its percentages from `GET /api/oauth/usage` directly,
using the OAuth token in `~/.claude/.credentials.json`, and caches the result in
`$XDG_CACHE_HOME/claude-limits/`. It does this because the
`cachedUsageUtilization` block in `~/.claude.json` is only rewritten on
infrequent triggers such as opening `/usage`, so it can sit twenty minutes stale
while you work. The status line render never blocks on the network: it prints the
cached figure and hands a stale cache off to a detached `--refresh` child. When
the access token has expired the fetch is skipped and it falls back to Claude
Code's block, so the worst case is the old behaviour rather than a hang.
