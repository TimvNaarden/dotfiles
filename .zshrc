export ZSH="$HOME/.oh-my-zsh"
export PATH="$PATH:/$HOME/.cargo/bin:/$HOME/.local/bin"
export PATH="$PATH:/home/tim/.dotnet/tools"

ZSH_THEME="refined" # set by `omz`
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

alias p="pnpm"
eval "$(zoxide init zsh)"

bindkey "\E[1~" beginning-of-line
bindkey "\E[4~" end-of-line
bindkey "\E[H" beginning-of-line
bindkey "\E[F" end-of-line
bindkey "\E[3~" delete-char

eval $(ssh-agent) > /dev/null

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Kitty maps Shift+Enter to Meta+Enter (ESC CR). At the zsh prompt, insert a
# real newline instead of accepting the line - self-insert-unmeta strips the
# meta bit and converts the ^M to ^J.
bindkey '^[^M' self-insert-unmeta

[ -f "/home/tim/.ghcup/env" ] && . "/home/tim/.ghcup/env" # ghcup-env
# JoJoschool config, a private repo at ~/dotfiles/jojoschool
[ -f "$HOME/.zshrc.jojoschool" ] && source "$HOME/.zshrc.jojoschool"
# Machine-local config, not tracked in dotfiles
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
