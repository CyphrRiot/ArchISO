#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Default Arch Linux prompt
PS1='[\u@\h \W]\$ '

# Aliases
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# ArchRiot first boot setup reminder
if [[ -f ~/.archriot-first-boot.sh ]]; then
    source ~/.archriot-first-boot.sh
fi
