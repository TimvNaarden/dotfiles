export ZSH="$HOME/.oh-my-zsh"
export PATH="$PATH:/$HOME/.cargo/bin"

ZSH_THEME="refined" # set by `omz`
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

alias kanshiswitch="mv ~/.config/kanshi/config ~/.config/kanshi/config1 && mv ~/.config/kanshi/config2 ~/.config/kanshi/config && mv ~/.config/kanshi/config1 ~/.config/kanshi/config2 && kanshi &"
alias pi="sudo pacman -S"
alias pu="sudo pacman -Sy"

eval "$(zoxide init zsh)"
xrandr --auto

bindkey "\E[1~" beginning-of-line
bindkey "\E[4~" end-of-line
bindkey "\E[H" beginning-of-line
bindkey "\E[F" end-of-line
bindkey "\E[3~" delete-char

export PATH=$PATH:/home/tim/.spicetify
