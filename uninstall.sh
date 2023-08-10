#!/bin/bash
# WARNING: You take full resposibility of what could happen to your host when executing
#          this script. This script has only been tested on Armen's MBP arm64 machine
#
# This script tries to remove as much as reasonable to allow for re-testing
# bootstrap.sh multiple times on the same host

remove_brew_setup() {
    # Removes all packages
    brew list -1 | xargs brew rm
    # Execute the official uninstall command
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
    # This is not removed by the script.
    [ -d /opt/homebrew ] && sudo rm -rf /opt/homebrew
}

command -v brew &>/dev/null && remove_brew_setup
rm -rf ~/.pyenv
rm -rf ~/.sentry
rm -rf ~/code/sentry/{.venv,node_modules}
rm -rf ~/code/getsentry/{.venv,node_modules}
[ -f ~/.zprofile ] && rm ~/.zprofile

echo "Successfully uninstalled brew and other"
