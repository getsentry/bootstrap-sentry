#!/bin/bash
# This script removes brew and artifacts installed by it
# It is used in CI to get the Github workers into a closer state
# as new laptops come in.
# This can also be used in development to test executions of bootstrap.sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
