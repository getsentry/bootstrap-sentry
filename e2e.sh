#!/bin/bash
# WARNING: You take full resposibility of what could happen to your host when executing
#          this script. This script has only been tested on Armen's MBP arm64 machine
#
# This script tries to remove as much as reasonable to allow for re-testing
# bootstrap.sh multiple times on the same host
#
# In order to automate this script we need to add sudo logic (extract from bootstap.sh)

remove_brew_setup() {
    # Uninstalling brew does not uninstall Docker, thus, uninstall all packages first
    brew list -1 | xargs brew rm
    # Execute the official uninstall command
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
    # This directory is not removed by the script.
    # On Intel machines, I would not dare removing /usr/local
    [ -d /opt/homebrew ] && sudo rm -rf /opt/homebrew
}

# This will cut some corners with bootstap.sh to test the most important parts
# For full e2e you can rely on the CI or comment this out
# XXX: Add a prompt to help the user decide the behavior of the script
export QUICK=on

if [ -z "$QUICK" ]; then
    export PIP_NO_CACHE_DIR=on

    # Since we install pre-commit via brew, we need to restore the hooks
    [ -f .git/hooks/pre-commit ] && command -v pre-commit &>/dev/null && pre-commit uninstall
    # This is where sentry init places files
    rm -rf ~/.sentry
    # Remove all Python & Yarn packages
    rm -rf ~/code/sentry/{.venv,node_modules}
    rm -rf ~/code/getsentry/{.venv,node_modules}
    # We place brew's & pyenv's eval in it
    [ -f ~/.zprofile ] && rm ~/.zprofile

    # Uninstall brew
    command -v brew &>/dev/null && remove_brew_setup
    echo "Successfully uninstalled brew and related packages"
fi

export CODE_ROOT="${HOME}/code"
# XXX: The script requests the users password
./bootstrap.sh
