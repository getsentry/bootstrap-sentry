#!/bin/bash
# This script tries to remove as much as reasonable to allow for re-testing
# bootstrap.sh multiple times on the same host
set -e

# Since we install pre-commit via brew, we need to restore the hooks
[ -f .git/hooks/pre-commit ] && command -v pre-commit &>/dev/null && pre-commit uninstall

# Remove Sentry and dependencies
rm -rf ~/.sentry
rm -rf ~/code/sentry ~/code/getsentry

remove_brew_setup() {
    # Removes all packages
    brew list -1 | xargs brew rm
    # brew's uninstall script does not remove some things
    [ -d /Applications/Docker.app ] && rm -rf /Applications/Docker.app
    [ -f /opt/homebrew/bin/chromedriver ] && rm /opt/homebrew/bin/chromedriver
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
    # This is not removed by the script.
    # On Intel machines, I would not dare removing /usr/local
    [ -f /opt/homebrew ] && rm -rf /opt/homebrew
}

# Uninstall brew
command -v brew &>/dev/null && remove_brew_setup

echo "Successfully uninstalled brew and related packages"
