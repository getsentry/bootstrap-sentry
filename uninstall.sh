#!/bin/bash

stuff="/opt/homebrew /usr/local/Homebrew ${HOME}/.sentry ${HOME}/code/sentry ${HOME}/code/getsentry ${HOME}/.profile ${HOME}/.zprofile ${HOME}/.zshrc"

[[ "$CI" ]] && {
    rm -rf $stuff
    exit
}

[[ "$CI" ]] || read -p "Don't execute this unless you know what you're doing. ENTER to continue."
[[ "$CI" ]] || read -p "Seriously, don't execute this. ENTER to continue."

backup="${HOME}/.sentry-bootstrap-$(date +%s)"
mkdir "$backup"
mv -v $stuff "$backup"
