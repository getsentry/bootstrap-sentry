#!/bin/bash

mkdir -p "${HOME}/.sentry-dev/system-python"

# x86_64
platform=aarch64

curl -fsSL \
    "https://github.com/indygreg/python-build-standalone/releases/download/20230726/cpython-3.11.4+20230726-${platform}-apple-darwin-install_only.tar.gz" \
    -o- | \
tar --strip-components=1 -C "${HOME}/.sentry-dev/system-python" -x -f-

# meh, need temp file for sha sum
