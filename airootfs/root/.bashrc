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

# ArchRiot live guidance (do not auto-start installer from bash)
if [[ -t 0 && -t 1 && -t 2 ]]; then
    echo
    echo "Welcome to ArchRiot live environment (bash)."
    echo "Type 'riot' to start the installer when the system is ready."
    echo "Logs: /tmp/riot_debug.log"
fi
