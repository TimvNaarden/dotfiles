# Install guides

[INSTALL-arch.md](INSTALL-arch.md) sets up the full desktop on Arch / CachyOS:
Hyprland with hotplug monitor profiles, kitty, zsh, tmux, Neovim, Claude Code
hooks. It assumes you have already cloned this repo to `~/dotfiles`.

## The one thing worth knowing before you start

This repo is a **single flat stow package**. The root maps straight onto `$HOME`,
so `.config/nvim` here becomes `~/.config/nvim`. There are no per-application
package directories, which means the stow invocation is not the usual one:

```sh
stow -d ~/dotfiles -t ~ .
```

`stow -d ~ -t ~ dotfiles` silently does nothing, because stow refuses to treat a
directory as a package when it sits inside its own target.

`INSTALL*.md` and `packages/` are excluded from linking by `.stow-local-ignore`.

## JoJoschool

Work config (the `jojo-*` commands, the monorepo aliases, personal Claude Code
skills about the JoJoschool codebase) lives in `jojoschool/`, which is its own
**private** repo. This repo gitignores it and `.stow-local-ignore` keeps the
root package from linking it as `~/jojoschool`. Clone it there and stow it as
a second package:

```sh
stow -d ~/dotfiles -t ~ jojoschool
```

`.zshrc` sources `~/.zshrc.jojoschool` only when it exists, so a machine
without the private repo still gets a working shell.

## Branches

`Cachy-os` is the desktop machine. Keep machine-specific edits on their own
branch: `.config/nvim/coc-settings.json` in particular has absolute paths in its
`languageserver` block, so editing it on one machine and pushing to a shared
branch breaks the other.
