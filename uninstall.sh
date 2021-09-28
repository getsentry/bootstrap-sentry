#!/bin/bash
# This script removes brew and artifacts installed by it.
# This is used in development before executions of bootstrap.sh
set -e

# brew's uninstall script does not properly remove casks
command -v brew &>/dev/null && brew uninstall --cask docker
[ -d /Applications/Docker.app ] && rm -rf /Applications/Docker.app

# Since we install pre-commit via brew, we need to restore the hooks
[ -f .git/hooks/pre-commit ] && pre-commit uninstall

# Uninstall brew
if command -v brew; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
fi

echo "Successfully uninstalled brew and related packages"
