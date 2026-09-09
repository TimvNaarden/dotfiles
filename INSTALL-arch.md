# Setting up a new machine: Arch / CachyOS

The full desktop: Hyprland, kitty, zsh, tmux, Neovim. Everything here was
verified against the machine this repo was last committed from: CachyOS (Arch),
Hyprland 0.56.2, Neovim 0.12.5.

For Neovim on Debian under WSL2, where there is no display server and the flat
stow layout needs handling differently, see
[INSTALL-debian-wsl.md](INSTALL-debian-wsl.md).

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
                        clang gcc wl-clipboard zoxide noctalia hyprland kitty btop \
                        wdisplays glslang
```

`wdisplays` is the display arrangement GUI driven by section 5. `glslang`
provides `glslangValidator`, which the GLSL plugin shells out to; skip it if you
do not write shaders.

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

Session titles are set twice per prompt. `claude-session-title.py` strips the
conversational filler off what you typed and returns that immediately, then
spawns `claude-title-refine.sh`, which asks Claude Haiku 4.5 for a real 2-4 word
name and replaces it about seven seconds later. The second pass costs a small
Haiku turn against your subscription on every prompt; `prefix + T` turns it off
and leaves the free heuristic in place.

The refiner runs a nested `claude -p`, which inherits `TMUX_PANE` and would
otherwise re-enter these same hooks, recursing and firing spurious
notifications. Every hook script therefore exits early when
`CLAUDE_TITLE_REFINER` is set. The `--bare` flag would also skip hooks but drops
the OAuth credentials, so it is not usable here.

---

## 5. Hyprland: monitors and workspaces

Monitor positions are **not** hardcoded in the config. `.config/hypr/lib/monitors.lua`
applies a layout for whatever set of displays is currently connected, and hands
every one of them `NUM_WPM` workspaces of its own.

Two generated files carry the state, and both are tracked:

| File | Holds |
| --- | --- |
| `monitor-profiles.lua` | one saved arrangement per combination of displays, keyed by their descriptions |
| `monitor-slots.lua` | which block of workspaces each display owns |

Displays are identified by `desc:`, which includes the serial, so a screen keeps
its position and its workspaces after you move its cable to a different port.
That also means **the entries in both files are specific to the monitors they
were saved on** and mean nothing on new hardware. Delete them on a fresh machine
and let them regenerate:

```sh
rm -f ~/.config/hypr/monitor-profiles.lua ~/.config/hypr/monitor-slots.lua
hyprctl reload
```

An unknown combination gets an automatic layout: externals in a row ordered by
port name, built-in panel centred underneath. To arrange them properly:

```sh
hypr-monitors gui       # wdisplays: drag the screens, then Apply
hypr-monitors save      # remember that arrangement for this combination
hypr-monitors status    # what is connected, and which workspaces each screen owns
```

`hypr-monitors` lives at `.local/bin/hypr-monitors` in this repo and is stowed
onto `PATH`. Note that `hyprctl keyword` does **not** work against a Lua
Hyprland config, which is why the script goes through `hyprctl repl` and why
nwg-displays is not usable here: its apply path is built on `keyword`.

Workspace blocks are handed out as: built-in panel first, then externals left to
right. With `NUM_WPM = 3` and three externals that is `1-3` for the laptop then
`4-6`, `7-9`, `10-12`. A display keeps its block once allocated, so numbering
does not shuffle when you re-dock. You rarely need those numbers though:
`SUPER + 1/2/3` uses Hyprland's `m~N` selector, which always means the first,
second or third workspace **of the screen you are looking at**.

Closing the lid drops the built-in panel out of the layout, but only while an
external screen is connected, so you can never end up with no display.

Check:

```sh
hypr-monitors status                  # every screen should show a 3-wide ws range
hyprctl workspaces -j | grep -c '"id"'   # expect 3 x number of connected screens
hyprctl configerrors                  # expect empty
```

---

## 6. Neovim

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

## 7. Claude Code

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

## 8. Not tracked here

Deliberately left out, listed so you know to redo them by hand:

* **kitty** (`~/.config/kitty/kitty.conf`). Holds the `shift+enter` and
  `ctrl+enter` mappings that send `\x1b\r`, which is what makes multi-line input
  work in Claude Code and at the zsh prompt. Without it Shift+Enter just submits.
  The matching zsh half (`bindkey '^[^M' self-insert-unmeta`) *is* tracked.
* **dunst, kanshi, waybar, wofi** and `.profile`. Tracked until the move to
  CachyOS, then removed: noctalia owns notifications, the bar and the launcher,
  and the monitor handling in section 5 replaced kanshi. They remain in git
  history if you ever want them back.
* **Browser profiles**, `gh` and `github-copilot` config. These hold auth tokens
  and must not be committed.
* **systemd coredump retention** (`/etc/tmpfiles.d/coredump.conf`,
  `/etc/systemd/coredump.conf.d/retention.conf`). Root-owned, outside `$HOME`.

---

## 9. Full verification

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
