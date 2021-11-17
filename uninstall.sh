#!/bin/bash
# WARNING: You take full resposibility of what could happen to your host when executing
#          this script. This script has only been tested on Armen's MBP arm64 machine
#
# This script tries to remove as much as reasonable to allow for re-testing
# bootstrap.sh multiple times on the same host

remove_other() {
    # Remove Sentry and dependencies
    rm -rf ~/.sentry
    rm -rf ~/code/sentry/{.venv,node_modules}
    rm -rf ~/code/getsentry/{.venv,node_modules}
    [ -f ~/.zprofile ] && rm ~/.zprofile
}

remove_brew_setup() {
    # Removes all packages
    brew list -1 | xargs brew rm
    # brew's uninstall script does not remove some things
    [ -d /Applications/Docker.app ] && rm -rf /Applications/Docker.app
    # Execute the official uninstall command
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
    # This is not removed by the script.
    [ -d /opt/homebrew ] && sudo rm -rf /opt/homebrew
    [ -d /usr/local/bin ] && sudo rm -rf /usr/local/bin
}

# Uninstall brew
command -v brew &>/dev/null && remove_brew_setup

remove_other

echo "Successfully uninstalled brew and other"
