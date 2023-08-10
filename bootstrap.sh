#!/bin/bash
#/ Usage: bin/strap.sh [--debug]
#/ Install development dependencies on macOS.
#/ Heavily inspired by https://github.com/MikeMcQuaid/strap
# shellcheck disable=SC2086
set -e

# Default cloning value.
GIT_URL_PREFIX="git@github.com:"

if [ -n "$CI" ]; then
  echo "Running within CI..."
  CODE_ROOT="$HOME/code"
  SKIP_METRICS=1
  GIT_URL_PREFIX="https://github.com/"
  SKIP_GETSENTRY=1
fi

bootstrap_sentry="$HOME/.sentry/bootstrap-sentry"
mkdir -p "$bootstrap_sentry"
cd "$bootstrap_sentry"

# Keep a log. h/t https://stackoverflow.com/a/25319102
cp bootstrap.log bootstrap.log.bak 2>/dev/null || true
exec > >(tee bootstrap.log)
exec 2>&1

[[ "$1" = "--debug" || -o xtrace ]] && STRAP_DEBUG="1"
STRAP_SUCCESS=""
STRAP_ISSUES_URL='https://github.com/getsentry/bootstrap-sentry/issues/new'

# NOTE: Now jump to "Beginning of execution" to skip over all these functions

record_metric() {
  if [ -n "$SKIP_METRICS" ]; then
    return 0
  fi

  if [ -z "$METRIC_USER" ]; then
    if [ -n "$GITHUB_USER" ]; then
      METRIC_USER=$GITHUB_USER
    else
      METRIC_USER=$(uuidgen)
    fi
  fi

  curl -s -d "{\"event\": \"$1\", \"name\": \"$METRIC_USER\", \"step\": \"$2\"}" -H 'Content-Type: application/json' https://product-eng-webhooks-vmrqv3f7nq-uw.a.run.app/metrics/bootstrap-dev-env/webhook >/dev/null
}

# Run this early to ensure that the user is identified w/ github
check_github_access() {
  local resp
  local regex

  log "Checking GitHub access"

  local github_message="Make sure that you set up your SSH keys correctly with Github. Read more in \
https://docs.github.com/en/free-pro-team@latest/github/authenticating-to-github/connecting-to-github-with-ssh"

  if ! [[ -d $HOME/.ssh ]]; then
    echo >&2 "$github_message"
    exit 1
  fi

  # Need to ignore exit code as it will always fail, need to parse stdout
  resp=$(ssh -T git@github.com 2>&1 || true)
  regex="Hi (.*)! You've successfully authenticated, but GitHub does not provide shell access\."

  if [[ "$resp" =~ $regex ]]; then
    GITHUB_USER=${BASH_REMATCH[1]}
  else
    echo >&2 "$resp"
    echo >&2 "$github_message"
    exit 1
  fi

  record_metric "bootstrap_start"
  logk
}

sudo_askpass() {
  if [ -n "$SUDO_ASKPASS" ]; then
    sudo --askpass "$@"
  else
    sudo "$@"
  fi
}

cleanup() {
  set +e
  sudo_askpass rm -rf "$CLT_PLACEHOLDER" "$SUDO_ASKPASS" "$SUDO_ASKPASS_DIR"
  sudo --reset-timestamp
  if [ -z "$STRAP_SUCCESS" ]; then
    echo
    if [ -n "$STRAP_STEP" ]; then
      echo "!!! $STRAP_STEP FAILED"
      record_metric "bootstrap_failed" "$STRAP_STEP"
    else
      echo "!!! FAILED"
      record_metric "bootstrap_failed"
    fi
    if [ -z "$STRAP_DEBUG" ]; then
      echo "!!! Run with '--debug' for debugging output."
      echo "!!! If you're stuck: file an issue with debugging output at:"
      echo "!!!   $STRAP_ISSUES_URL"
    fi
  fi
}

# functions for turning off debug for use when handling the user password
clear_debug() {
  set +x
}

reset_debug() {
  if [ -n "$STRAP_DEBUG" ]; then
    set -x
  fi
}

# Initialise (or reinitialise) sudo to save unhelpful prompts later.
sudo_init() {
  if [ -z "$STRAP_INTERACTIVE" ]; then
    return
  fi

  local SUDO_PASSWORD SUDO_PASSWORD_SCRIPT

  if ! sudo --validate --non-interactive &>/dev/null; then
    while true; do
      read -rsp "--> Enter your password (for sudo access):" SUDO_PASSWORD
      echo
      if sudo --validate --stdin 2>/dev/null <<<"$SUDO_PASSWORD"; then
        break
      fi

      unset SUDO_PASSWORD
      echo "!!! Wrong password!"
    done

    clear_debug
    SUDO_PASSWORD_SCRIPT="$(
      cat <<BASH
#!/bin/bash
echo "$SUDO_PASSWORD"
BASH
    )"
    unset SUDO_PASSWORD
    SUDO_ASKPASS_DIR="$(mktemp -d)"
    SUDO_ASKPASS="$(mktemp "$SUDO_ASKPASS_DIR"/strap-askpass-XXXXXXXX)"
    chmod 700 "$SUDO_ASKPASS_DIR" "$SUDO_ASKPASS"
    bash -c "cat > '$SUDO_ASKPASS'" <<<"$SUDO_PASSWORD_SCRIPT"
    unset SUDO_PASSWORD_SCRIPT
    reset_debug

    export SUDO_ASKPASS
  fi
}

sudo_refresh() {
  clear_debug
  if [ -n "$SUDO_ASKPASS" ]; then
    sudo --askpass --validate
  else
    sudo_init
  fi
  reset_debug
}

abort() {
  STRAP_STEP=""
  echo "!!! $*"
  exit 1
}
log() {
  STRAP_STEP="$*"
  sudo_refresh
  echo "--> $*"
}
logn() {
  STRAP_STEP="$*"
  sudo_refresh
  printf -- "--> %s " "$*"
}
logk() {
  STRAP_STEP=""
  echo "OK"
}
escape() {
  printf '%s' "${1//\'/\'}"
}

# Install the Xcode Command Line Tools.
install_xcode_cli() {
  if ! [ -f "/Library/Developer/CommandLineTools/usr/bin/git" ]; then
    log "Installing the Xcode Command Line Tools:"
    CLT_PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
    sudo_askpass touch "$CLT_PLACEHOLDER"

    CLT_PACKAGE=$(softwareupdate -l |
      grep -B 1 "Command Line Tools" |
      awk -F"*" '/^ *\*/ {print $2}' |
      sed -e 's/^ *Label: //' -e 's/^ *//' |
      sort -V |
      tail -n1)
    sudo_askpass softwareupdate -i "$CLT_PACKAGE"
    sudo_askpass rm -f "$CLT_PLACEHOLDER"
    if ! [ -f "/Library/Developer/CommandLineTools/usr/bin/git" ]; then
      if [ -n "$STRAP_INTERACTIVE" ]; then
        echo
        logn "Requesting user install of Xcode Command Line Tools:"
        xcode-select --install
      else
        echo
        abort "Run 'xcode-select --install' to install the Xcode Command Line Tools."
      fi
    fi
    logk
  fi
}

# Check if the Xcode license is agreed to and agree if not.
xcode_license() {
  if /usr/bin/xcrun clang 2>&1 | grep $Q license; then
    if [ -n "$STRAP_INTERACTIVE" ]; then
      logn "Asking for Xcode license confirmation:"
      sudo_askpass xcodebuild -license
      logk
    else
      abort "Run 'sudo xcodebuild -license' to agree to the Xcode license."
    fi
  fi
}

install_homebrew() {
  logn "Installing Homebrew:"
  sudo_askpass chown "$USER" /opt
  where="/opt/homebrew"
  [ -n "$CI" ] && where="/usr/local/Homebrew"
  [ -d "$where" ] || git clone --depth=1 "https://github.com/Homebrew/brew" "$where"
  export PATH="${where}/bin:${PATH}"
  [ -z "$QUICK" ] && {
    logn "Updating Homebrew"
    brew update --quiet
  }
  logk

  if ! grep -qF "brew shellenv" "${HOME}/.zshrc"; then
    #shellcheck disable=SC2016
    echo -e 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "${HOME}/.zshrc"
  fi
  logk
}

# Install Sentry CLI so that we can track errors that happen in this bootstrap script
# This requires xcode CLI to be installed
install_sentry_cli() {
  log "Installing sentry-cli"
  if ! command -v sentry-cli &>/dev/null; then
    # This ensures that sentry-cli has a directory to install under
    [ ! -d /usr/local/bin ] && (
      sudo_askpass mkdir /usr/local/bin
      sudo_askpass chown "$USER" /usr/local/bin
    )
    curl -sL https://sentry.io/get-cli/ | SENTRY_CLI_VERSION=2.0.4 bash
  fi
  if [ -z "$CI" ]; then
    # This is used to report issues when a new engineer encounters issues with this script
    export SENTRY_DSN=https://b70e44882d494c68a78ea1e51c2b17f0@o1.ingest.sentry.io/5480435
    eval "$(sentry-cli bash-hook)"
  fi
  logk
}

# Clone repo ($1) to path ($2)
git_clone_repo() {
  if [ ! -d "$2" ]; then
    log "Cloning $1 to $2"
    flags=
    [ -n "$CI" ] && flags='--depth=1'
    git clone $flags "${GIT_URL_PREFIX}$1.git" "$2"
    logk
  fi
}

# Install required libraries of dir ($1)
install_prerequisites() {
  if [ -d "$1" ]; then
    if [ -z "$QUICK" ]; then
      log "Installing from sentry Brewfile (very slow)"
      # This makes sure that we don't try to install Python packages from the cache
      # This is useful when verifying a new platform and multiple executions of bootstrap.sh is required
      export PIP_NO_CACHE_DIR=1
      # The fallback is useful when trying to run the script on a non-clean machine multiple times
      cd "$1" && (make prerequisites || log "Something failed during brew bundle but let's try to continue")
    else
      log "Installing minimal set of requirements"
      export HOMEBREW_NO_AUTO_UPDATE=1
      export HOMEBREW_NO_ANALYTICS=1
      brew install libxmlsec1 pyenv
    fi
    logk
  fi
}

# Setup pyenv of path
setup_pyenv() {
  if command -v pyenv &>/dev/null; then
    logn "Install python via pyenv"
    make setup-pyenv
    eval "$(pyenv init --path)"

    # TODO make sure `python` is shimmed by pyenv e.g. = ~/.pyenv/shims/python
    logk
  else
    echo "!!! pyenv not found, try running bootstrap script again or run \`brew bundle\` in the sentry repo"
  fi
}

install_sentry_env_vars() {
  logn "Installing sentry env vars to startup script..."

  # This will be used to measure webpack
  if ! grep -qF "SENTRY_INSTRUMENTATION" "${HOME}/.zshrc"; then
    echo "export SENTRY_INSTRUMENTATION=1" >>"${HOME}/.zshrc"
  fi
  if ! grep -qF "SENTRY_POST_MERGE_AUTO_UPDATE" "${HOME}/.zshrc"; then
    echo "export SENTRY_POST_MERGE_AUTO_UPDATE=1" >> "${HOME}/.zshrc"
  fi
  if ! grep -qF "SENTRY_SPA_DSN" "${HOME}/.zshrc"; then
    echo "export SENTRY_SPA_DSN=https://863de587a34a48c4a4ef1a9238fdb0b1@o19635.ingest.sentry.io/5270453" >> "${HOME}/.zshrc"
  fi

  logk
}

install_volta() {
  if ! command -v volta &>/dev/null; then
    log "Install volta"
    curl https://get.volta.sh | bash
    export VOLTA_HOME="${HOME}/.volta"
    export PATH="${VOLTA_HOME}/bin:$PATH"
    logk
  fi
}

install_direnv_startup() {
  logn "Installing direnv startup script..."

  if ! grep -qF "direnv hook" "${HOME}/.zshrc"; then
    echo "eval \"\$(direnv hook zsh)\"" >> "${HOME}/.zshrc"
  fi

  logk
}

install_direnv() {
  if ! command -v direnv &>/dev/null; then
    log "Installing direnv"
    brew install direnv
    install_direnv_startup
    logk
  fi
}

setup_virtualenv() {
  log "Creating virtualenv in $1"
  cd "$1" && python -m venv .venv
  logk
}

bootstrap() {
  log "Bootstrapping env: $1"
  # shellcheck disable=SC1091
  cd "$1" && source .venv/bin/activate

  # Only run `make bootstrap` if config file does not exist
  if [ ! -f "$HOME/.sentry/sentry.conf.py" ]; then
    # sentry devservices will try to start and wait for the container runtime,
    # so this should just work
    cd "$1" && make bootstrap
  fi

  logk
}

############################
## Beginning of execution ##
############################

OSNAME="$(uname -s)"
if [ "$OSNAME" != "Darwin" ]; then
  echo "'$OSNAME' not supported"
  exit 1
fi

[ "$USER" = "root" ] && abort "Run as yourself, not root."

trap "cleanup" EXIT

if [ -n "$STRAP_DEBUG" ]; then
  set -x
else
  STRAP_QUIET_FLAG="-q"
  Q="$STRAP_QUIET_FLAG"
fi

STDIN_FILE_DESCRIPTOR="0"
[ -t "$STDIN_FILE_DESCRIPTOR" ] && STRAP_INTERACTIVE="1"

# Prevent sleeping during script execution, as long as the machine is on AC power
caffeinate -s -w $$ &

if [ -z "$CODE_ROOT" ]; then
    read -rp "--> Enter absolute path where we'll clone source code [$HOME/code]: " CODE_ROOT
else
    echo "Installing into $CODE_ROOT"
fi

if [ -z "$CODE_ROOT" ]; then
    CODE_ROOT="$HOME/code"
fi

[ -d "$CODE_ROOT" ] || mkdir -p "$CODE_ROOT"

touch "${HOME}/.zshrc"

sudo_refresh
sudo networksetup -setv6off "Wi-Fi"
install_xcode_cli
xcode_license
install_sentry_cli
[ -z "$CI" ] && [ -z "$QUICK" ] && check_github_access
[ -z "$QUICK" ] && install_homebrew

### Sentry stuff ###
SENTRY_ROOT="$CODE_ROOT/sentry"
GETSENTRY_ROOT="$CODE_ROOT/getsentry"

git_clone_repo "getsentry/sentry" "$SENTRY_ROOT"
if [ -z "$SKIP_GETSENTRY" ] && ! git_clone_repo "getsentry/getsentry" "$GETSENTRY_ROOT" 2>/dev/null; then
  # git clone failed, assume no access to getsentry and skip further getsentry steps
  SKIP_GETSENTRY=1
fi

# Most of the following actions require to be within the Sentry checkout
cd "$SENTRY_ROOT"
install_prerequisites "$SENTRY_ROOT"
setup_pyenv "$SENTRY_ROOT"
# Run it here to make sure pyenv's Python is selected
eval "$(pyenv init --path)"
setup_virtualenv "$SENTRY_ROOT"
install_sentry_env_vars

# Sadly, there's not much left to test on Macs. Perhaps, in the future, we can test on Linux
[ -n "$CI" ] && STRAP_SUCCESS=1 && exit 0

install_volta

# bootstrap sentry
bootstrap "$SENTRY_ROOT"

# Installing direnv after we boostrap to make sure our dev env does not depend on it
install_direnv
direnv allow

if [ -z "$SKIP_GETSENTRY" ] && [ -d "$GETSENTRY_ROOT" ]; then
  setup_virtualenv "$GETSENTRY_ROOT"
  bootstrap "$GETSENTRY_ROOT"
  direnv allow

  cd "$GETSENTRY_ROOT"
  log "You'll need to restart your shell and then run getsentry: \`exec $SHELL && getsentry devserver\`"
else
  cd "$SENTRY_ROOT"
  log "You'll need to restart your shell and then run sentry: \`exec $SHELL && sentry devserver\`"
fi

record_metric "bootstrap_passed"
STRAP_SUCCESS="1"
log "Your system is now bootstrapped! 🌮"
