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

# Auto-run ArchRiot installer on login
if [[ -t 0 && -t 1 && -t 2 ]]; then
    echo "Starting ArchRiot installer..."
    sleep 1
    exec riot
fi
