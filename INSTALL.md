# Install guides

Pick the platform. Both assume you have already cloned this repo to `~/dotfiles`.

| Guide | Covers |
| --- | --- |
| [INSTALL-arch.md](INSTALL-arch.md) | The full desktop on Arch / CachyOS: Hyprland with hotplug monitor profiles, kitty, zsh, tmux, Neovim, Claude Code hooks. Stows the whole repo. |
| [INSTALL-debian-wsl.md](INSTALL-debian-wsl.md) | Neovim, tmux and zsh on Debian under WSL2. No display server, so it links only those four things by hand rather than stowing. |

## The one thing worth knowing before you start

This repo is a **single flat stow package**. The root maps straight onto `$HOME`,
so `.config/nvim` here becomes `~/.config/nvim`. There are no per-application
package directories, which means the stow invocation is not the usual one:

```sh
stow -d ~/dotfiles -t ~ .
```

`stow -d ~ -t ~ dotfiles` silently does nothing, because stow refuses to treat a
directory as a package when it sits inside its own target.

The flat layout is also why the WSL guide links files by hand: `stow .` there
would drag Hyprland, waybar and wofi configuration onto a machine that has no
display server to use it.

`INSTALL*.md` and `packages/` are excluded from linking by `.stow-local-ignore`.

## Branches

`Cachy-os` is the desktop machine. Keep machine-specific edits on their own
branch: `.config/nvim/coc-settings.json` in particular has absolute paths in its
`languageserver` block, so editing it on one machine and pushing to a shared
branch breaks the other. The WSL guide covers which paths and why.
