#!/bin/bash
# This script removes brew and artifacts installed by it.
# This can be used in development to before executions of bootstrap.sh
set -e
[ -d /Applications/Docker.app ] && (
    brew uninstall --cask docker
    rm -rf /Applications/Docker.app
)
# Since we install pre-commit via brew
[ -f .git/hooks/pre-commit ] && pre-commit uninstall
# if command -v brew; then
#     /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
# fi
echo "Successfully uninstalled brew and related packages"
