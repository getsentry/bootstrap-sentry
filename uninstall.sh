#!/bin/bash
# WARNING: You take full resposibility of what could happen to your host when executing
#          this script. This script has only been tested on Armen's MBP arm64 machine
#
# This script tries to remove as much as reasonable to allow for re-testing
# bootstrap.sh multiple times on the same host

if [ -n "$CI" ]; then
  # macos in GHA is intel-only, so make sure we remove its brew
  sudo rm -rf /usr/local/Homebrew
  sudo rm -f /usr/local/bin/brew
fi

sudo rm -rf /opt/homebrew

rm -rf ~/.pyenv
rm -rf ~/.sentry
rm -rf ~/code/sentry/{.venv,node_modules}
rm -rf ~/code/getsentry/{.venv,node_modules}
rm -f ~/.profile ~/.zprofile ~/.zshrc
