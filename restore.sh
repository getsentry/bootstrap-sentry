#!/bin/bash

[[ "$CI" ]] || read -p "Don't execute this unless you know what you're doing. ENTER to continue."
[[ "$CI" ]] || read -p "Seriously, don't execute this. ENTER to continue."

mv -v "${1}/homebrew" /opt/homebrew
# mv -v "${1}/Homebrew" /usr/local/Homebrew
mv -v "${1}/sentry" ~/code
mv -v "${1}/getsentry" ~/code
mv -v "${1}/".* ~
rmdir "$1"
