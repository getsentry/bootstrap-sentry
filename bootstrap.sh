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
  # The workflow sets the SHELL to zsh
  touch "${HOME}/.zshrc"
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

  if [ -z "$GITHUB_USER" ]; then
    SKIP_GETSENTRY=1
    echo "You are not identified with GitHub, skipping \`getsentry\`"
  fi

  record_metric "bootstrap_start"
  logk
}

get_code_root_path() {
  if [ -z "$CODE_ROOT" ]; then
    read -rp "--> Enter the absolute path to your code [$HOME/code]: " CODE_ROOT
  else
    echo "Installing into $CODE_ROOT"
  fi

  if [ -z "$CODE_ROOT" ]; then
    CODE_ROOT="$HOME/code"
  fi

  [ -d "$CODE_ROOT" ] || mkdir -p "$CODE_ROOT"
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
  # Setup Homebrew directory and permissions.
  logn "Installing Homebrew:"
  HOMEBREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  HOMEBREW_REPOSITORY="$(brew --repository 2>/dev/null || true)"
  if [ -z "$HOMEBREW_PREFIX" ] || [ -z "$HOMEBREW_REPOSITORY" ]; then
    UNAME_MACHINE="$(/usr/bin/uname -m)"
    if [[ "$UNAME_MACHINE" == "arm64" ]]; then
      HOMEBREW_PREFIX="/opt/homebrew"
      HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}"
    else
      HOMEBREW_PREFIX="/usr/local"
      HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}/Homebrew"
    fi
  fi
  [ -d "$HOMEBREW_PREFIX" ] || sudo_askpass mkdir -p "$HOMEBREW_PREFIX"
  if [ "$HOMEBREW_PREFIX" = "/usr/local" ]; then
    sudo_askpass chown "root:wheel" "$HOMEBREW_PREFIX" 2>/dev/null || true
  fi
  (
    cd "$HOMEBREW_PREFIX"
    sudo_askpass mkdir -p Cellar Caskroom Frameworks bin etc include lib opt sbin share var
    sudo_askpass chown "$USER:admin" Cellar Caskroom Frameworks bin etc include lib opt sbin share var
  )

  [ -d "$HOMEBREW_REPOSITORY" ] || sudo_askpass mkdir -p "$HOMEBREW_REPOSITORY"
  sudo_askpass chown -R "$USER:admin" "$HOMEBREW_REPOSITORY"

  if [ $HOMEBREW_PREFIX != $HOMEBREW_REPOSITORY ]; then
    ln -sf "$HOMEBREW_REPOSITORY/bin/brew" "$HOMEBREW_PREFIX/bin/brew"
  fi

  # Download Homebrew.
  export GIT_DIR="$HOMEBREW_REPOSITORY/.git" GIT_WORK_TREE="$HOMEBREW_REPOSITORY"
  git init $Q
  git config remote.origin.url "https://github.com/Homebrew/brew"
  git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  git fetch $Q --tags --force
  git reset $Q --hard origin/master
  unset GIT_DIR GIT_WORK_TREE
  logk

  # Update Homebrew.
  export PATH="$HOMEBREW_PREFIX/bin:$PATH"
  logn "Updating Homebrew:"
  [ -z "$QUICK" ] && brew update --quiet
  logk

  # On Apple M1 machines we need to add this to the profile
  if [[ "$(uname -m)" == "arm64" ]]; then
    shell_profile=$(get_brew_profile)
    eval "$(/opt/homebrew/bin/brew shellenv)"
    if ! grep -qF "brew shellenv" "${shell_profile}"; then
      #shellcheck disable=SC2016
      echo -e 'eval "$(/opt/homebrew/bin/brew shellenv)"' >>${shell_profile}
    fi
  fi

  # Install Homebrew Bundle, Cask and Services tap.
  log "Installing Homebrew taps and extensions:"
  brew bundle --quiet --file=- <<RUBY
tap "homebrew/cask"
tap "homebrew/core"
tap "homebrew/services"
RUBY
  logk
}

# Check and install any remaining software updates.
software_update() {
  logn "Checking for software updates:"
  updates=$(softwareupdate -l 2>&1)
  if echo "$updates" | grep "$Q" "No new software available."; then
    logk
  else
    echo
    if [ "$1" == "reminder" ]; then
      log "You have system updates to install. Please check for updates if you wish to install them."
      log "$updates"
    elif [ -z "$CI" ]; then
      log "Installing software updates:"
      sudo_askpass softwareupdate --install --all
      xcode_license
    else
      echo "Skipping software updates for CI"
    fi
    logk
  fi
}

get_shell_name() {
  case "$SHELL" in
  /bin/bash)
    echo "bash"
    ;;
  /bin/zsh)
    echo "zsh"
    ;;
  esac
}

# From https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
get_brew_profile() {
  case "${SHELL}" in
  */bash*)
    if [[ -r "${HOME}/.bash_profile" ]]; then
      shell_profile="${HOME}/.bash_profile"
    else
      shell_profile="${HOME}/.profile"
    fi
    ;;
  */zsh*)
    shell_profile="${HOME}/.zprofile"
    ;;
  *)
    shell_profile="${HOME}/.profile"
    ;;
  esac
  echo $shell_profile
}

get_shell_startup_script() {
  local _shell
  _shell=$(get_shell_name)

  if [ -n "$_shell" ]; then
    # TODO find correct startup script to source
    echo "$HOME/.${_shell}rc"
  fi
}

# Install Sentry CLI so that we can track errors that happen in this bootstrap script
# This requires xcode CLI to be installed
install_sentry_cli() {
  log "Installing sentry-cli"
  if ! command -v sentry-cli &>/dev/null; then
    curl -sL https://sentry.io/get-cli/ | bash
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
    git clone -q "${GIT_URL_PREFIX}$1.git" "$2"
    logk
  fi
}

# Open Docker.app and wait for docker server to be ready
ensure_docker_server() {
  if [ -d "/Applications/Docker.app" ]; then
    log "Starting Docker.app, if necessary..."
    log "We will not continue the installation until you have completed the UI prompts that Docker has."
    # We will open Docker on behalf of the user
    # This will allow the user to interact with Docker UI prompts
    open -g -a Docker.app

    # taken from https://github.com/docker/for-mac/issues/2359#issuecomment-607154849
    # Wait for the server to start up, if applicable.
    local i=0
    while ! docker system info &>/dev/null; do
      ((i++ == 0)) && printf %s '-- Waiting for Docker to finish starting up...' || printf '.'
      sleep 1
    done
    ((i)) && printf '\n'
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
      export PIP_NO_CACHE_DIR=on
      # The fallback is useful when trying to run the script on a non-clean machine multiple times
      cd "$1" && (make prerequisites || log "Something failed during brew bundle but let's try to continue")
    else
      log "Installing minimal set of requirements"
      export HOMEBREW_NO_AUTO_UPDATE=on
      brew install libxmlsec1 pyenv
      brew install --cask docker
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
  local _script
  _script=$(get_shell_startup_script)

  logn "Installing sentry env vars to startup script..."

  if [ -n "$_script" ]; then
    # This will be used to measure webpack
    if ! grep -qF "SENTRY_INSTRUMENTATION" "$_script"; then
      echo "export SENTRY_INSTRUMENTATION=1" >>"$_script"
    fi
    if ! grep -qF "SENTRY_POST_MERGE_AUTO_UPDATE" "$_script"; then
      echo "export SENTRY_POST_MERGE_AUTO_UPDATE=1" >>"$_script"
    fi
    if ! grep -qF "SENTRY_SPA_DSN" "$_script"; then
      echo "export SENTRY_SPA_DSN=https://863de587a34a48c4a4ef1a9238fdb0b1@o19635.ingest.sentry.io/5270453" >>"$_script"
    fi
  fi

  logk
}

install_volta() {
  if ! command -v volta &>/dev/null; then
    log "Install volta"
    curl https://get.volta.sh | bash
    # shellcheck disable=SC1090
    source "$(get_shell_startup_script)"
    logk
  fi
}

install_direnv_startup() {
  local _script
  _script=$(get_shell_startup_script)

  logn "Installing direnv startup script..."

  if [ -n "$_script" ]; then
    if ! grep -qF "direnv hook" "$_script"; then
      echo "eval \"\$(direnv hook $(get_shell_name))\"" >>"$_script"
    else
      logn " skipping (already installed)... "
    fi
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
  if docker system info &>/dev/null; then
    log "Bootstrapping env: $1"
    # shellcheck disable=SC1091
    cd "$1" && source .venv/bin/activate

    # Only run `make bootstrap` if config file does not exist
    if [ ! -f "$HOME/.sentry/sentry.conf.py" ]; then
      cd "$1" && make bootstrap
    fi

    logk
  else
    abort "!!! docker is not running, skipping bootstrapping...
!!! To continue, \`open /Applications/Docker.app\` and follow the GUI instructions
!!! Then re-run the bootstrap script or \`cd $1 && make bootstrap\`"
  fi
}

############################
## Beginning of execution ##
############################

OSNAME="$(uname -s)"
# TODO: Support other OSes
if [ "$OSNAME" != "Darwin" ]; then
  echo "'$OSNAME' not supported"
  exit 1
fi

trap "cleanup" EXIT

if [ -n "$STRAP_DEBUG" ]; then
  set -x
else
  STRAP_QUIET_FLAG="-q"
  Q="$STRAP_QUIET_FLAG"
fi

STDIN_FILE_DESCRIPTOR="0"
[ -t "$STDIN_FILE_DESCRIPTOR" ] && STRAP_INTERACTIVE="1"

# We want to always prompt for sudo password at least once rather than doing
# root stuff unexpectedly.
sudo_refresh

# Before starting, get the user's code location root where we will clone sentry repos to
get_code_root_path

[ -z "$CI" ] && [ -z "$QUICK" ] && check_github_access

[ "$USER" = "root" ] && abort "Run as yourself, not root."
groups | grep $Q -E "\b(admin)\b" || abort "Add $USER to the admin group."

# Prevent sleeping during script execution, as long as the machine is on AC power
caffeinate -s -w $$ &

install_xcode_cli
xcode_license
[ -z "$QUICK" ] && install_homebrew

### Sentry stuff ###
SENTRY_ROOT="$CODE_ROOT/sentry"
GETSENTRY_ROOT="$CODE_ROOT/getsentry"

install_sentry_cli
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

# We need docker running before bootstrapping sentry
ensure_docker_server

# bootstrap sentry
bootstrap "$SENTRY_ROOT"

# Installing direnv after we boostrap to make sure our dev env does not depend on it
install_direnv

# bootstrap getsentry now
if [ -z "$SKIP_GETSENTRY" ] && [ -d "$GETSENTRY_ROOT" ]; then
  # Shutdown devservices so that we can install getsentry
  sentry devservices down
  direnv allow
  deactivate

  setup_virtualenv "$GETSENTRY_ROOT"
  bootstrap "$GETSENTRY_ROOT"
  direnv allow

  cd "$GETSENTRY_ROOT"
  log "You'll need to restart your shell and then run getsentry: \`exec $SHELL && getsentry devserver\`"
else
  # shellcheck disable=SC2093
  exec "$SHELL"
  cd "$SENTRY_ROOT"
  log "You'll need to restart your shell and then run sentry: \`exec $SHELL && sentry devserver\`"
fi

record_metric "bootstrap_passed"
STRAP_SUCCESS="1"
log "Your system is now bootstrapped! 🌮"

software_update "reminder"
