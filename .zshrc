export ZSH="$HOME/.oh-my-zsh"
export PATH="$PATH:/$HOME/.cargo/bin:/$HOME/.local/bin"
export PATH="$PATH:/home/tim/.dotnet/tools"

ZSH_THEME="refined" # set by `omz`
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

alias kanshiswitch="mv ~/.config/kanshi/config ~/.config/kanshi/config1 && mv ~/.config/kanshi/config2 ~/.config/kanshi/config && mv ~/.config/kanshi/config1 ~/.config/kanshi/config2 && killall kanshi && kanshi &"
alias pi="sudo pacman -S"
alias pu="sudo pacman -Sy"
alias pr="sudo pacman -Rnc"
alias resource=". /home/tim/.zshrc"
alias p="pnpm"
eval "$(zoxide init zsh)"
eval "xrandr --auto &>/dev/null"

bindkey "\E[1~" beginning-of-line
bindkey "\E[4~" end-of-line
bindkey "\E[H" beginning-of-line
bindkey "\E[F" end-of-line
bindkey "\E[3~" delete-char

eval $(ssh-agent) > /dev/null

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
