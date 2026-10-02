#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Evan Fiddler
#
# Zero-to-bootstrapped on a machine that has nothing but an OS.
#
#   /bin/bash -c "$(curl -fsSL <url-to-this-file>)"
#
# Use that form, not `curl | bash`: piping leaves stdin attached to the script,
# so `gh auth login` has no terminal to read from and the run dies halfway.
#
# This script is standalone on purpose. It runs before cold-brew is cloned, so
# it cannot source anything from scripts/. It stops where it must, hands the
# rest to ./bootstrap.sh, and is safe to re-run.
set -euo pipefail

COLD_BREW_SSH_URL=${COLD_BREW_SSH_URL:-"git@github.com:SudoEvan/cold-brew.git"}
COLD_BREW_REPO=${COLD_BREW_REPO:-"SudoEvan/cold-brew"}
REPO_DIR=${REPO_DIR:-"$HOME/Developer/repos/cold-brew"}
SSH_KEY=${SSH_KEY:-"$HOME/.ssh/id_ed25519"}
RUN_BOOTSTRAP=${RUN_BOOTSTRAP:-1}

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
err()  { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }
step() { echo; echo -e "\033[1;36m==>\033[0m $*"; }

die() { err "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: install.sh [options]

  --repo-dir DIR    Where to clone cold-brew (default: $REPO_DIR)
  --no-bootstrap    Clone and configure auth, but do not run ./bootstrap.sh
  -h, --help        Show this help

Environment overrides: COLD_BREW_SSH_URL, COLD_BREW_REPO, REPO_DIR, SSH_KEY
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir) REPO_DIR="${2:?--repo-dir needs a path}"; shift 2 ;;
    --no-bootstrap) RUN_BOOTSTRAP=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

# An interactive terminal is required for `gh auth login`. Fail now with the
# right command rather than halfway through.
have_tty() { [[ -t 0 ]]; }

step "Checking the host"

OS="$(uname)"
case "$OS" in
  Darwin) info "macOS detected" ;;
  Linux)  info "Linux detected" ;;
  *) die "Unsupported OS: $OS" ;;
esac

command -v curl >/dev/null 2>&1 || die "curl is required and was not found"

step "Installing Homebrew (and, on macOS, the Command Line Tools)"

find_brew() {
  local candidate
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  command -v brew 2>/dev/null && return 0
  return 1
}

if brew_bin="$(find_brew)"; then
  info "Homebrew already installed at $brew_bin"
else
  if [[ "$OS" == "Linux" ]]; then
    # Homebrew on Linux needs a compiler and git before it will install.
    if command -v apt-get >/dev/null 2>&1; then
      info "Installing Homebrew prerequisites via apt"
      sudo apt-get update -y
      sudo apt-get install -y build-essential procps curl file git
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf groupinstall -y 'Development Tools'
      sudo dnf install -y procps-ng curl file git
    else
      warn "Unknown package manager; install git and a compiler toolchain first if Homebrew fails"
    fi
  fi

  # On macOS this installs the Command Line Tools headlessly, which is what
  # provides a usable git. Homebrew is the bootstrap primitive here, not a
  # dependency of it.
  info "Running the Homebrew installer"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  brew_bin="$(find_brew)" || die "Homebrew installed but brew not found; see https://brew.sh"
fi

eval "$("$brew_bin" shellenv)"
info "brew $("$brew_bin" --version | head -n1 | awk '{print $2}')"

step "Verifying git"

# /usr/bin/git exists on macOS as a Command Line Tools shim before the tools
# are installed, so `command -v git` proves nothing. Run it.
if git --version >/dev/null 2>&1; then
  info "git $(git --version | awk '{print $3}')"
else
  die "git is present but not usable. Run: xcode-select --install"
fi

step "Installing the GitHub CLI"

if command -v gh >/dev/null 2>&1; then
  info "gh already installed: $(gh --version | head -n1)"
else
  brew install gh
fi

step "Authenticating to GitHub"

if gh auth status >/dev/null 2>&1; then
  info "gh is already authenticated as $(gh api user --jq .login 2>/dev/null || echo 'unknown')"
else
  have_tty || die "gh needs an interactive terminal. Re-run as:
  /bin/bash -c \"\$(curl -fsSL <url-to-this-file>)\""
  info "Opening a browser login. Copy the one-time code when prompted."
  # admin:public_key is not a default scope, and without it `gh ssh-key add`
  # below fails and forces a `gh auth refresh` detour. --skip-ssh-key stops gh
  # offering its own key prompt, so the key path and name stay deterministic.
  gh auth login --hostname github.com --git-protocol ssh --web \
    --scopes admin:public_key --skip-ssh-key
  gh auth status >/dev/null 2>&1 || die "gh authentication did not complete"
fi

step "Setting up an SSH key"

if [[ -f "$SSH_KEY" ]]; then
  info "Using existing key $SSH_KEY"
else
  info "Generating $SSH_KEY"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  # No passphrase: this key is unlocked non-interactively by every later step.
  ssh-keygen -t ed25519 -N "" -C "$(whoami)@$(hostname -s)-$(date +%Y%m%d)" -f "$SSH_KEY"
fi

# Uploading the public key is what makes every git@github.com clone work. It is
# the step that otherwise forces a manual detour through the GitHub web UI.
key_title="$(hostname -s) (cold-brew $(date +%Y-%m-%d))"
if gh ssh-key list 2>/dev/null | grep -qF "$(awk '{print $2}' "$SSH_KEY.pub")"; then
  info "This public key is already registered with GitHub"
elif gh ssh-key add "$SSH_KEY.pub" --title "$key_title" 2>/dev/null; then
  info "Added $SSH_KEY.pub to GitHub as '$key_title'"
else
  warn "Could not upload the SSH key automatically."
  warn "The token may lack the 'admin:public_key' scope. Fix with:"
  warn "  gh auth refresh -h github.com -s admin:public_key"
  warn "Or add it manually: https://github.com/settings/keys"
fi

step "Verifying SSH access to GitHub"

ssh_ok=0
for _ in 1 2 3; do
  # GitHub always exits 1 for a shell attempt, and `set -o pipefail` would make
  # `ssh | grep` fail even when grep matches. Capture first, then match.
  ssh_out="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    -T git@github.com 2>&1 || true)"
  if [[ "$ssh_out" == *"successfully authenticated"* ]]; then
    ssh_ok=1
    break
  fi
  sleep 2
done

if [[ $ssh_ok -eq 1 ]]; then
  info "SSH to GitHub works"
else
  warn "SSH to GitHub is not working yet; falling back to gh for the clone"
fi

step "Cloning cold-brew"

if [[ -d "$REPO_DIR/.git" ]]; then
  info "cold-brew already cloned at $REPO_DIR"
else
  mkdir -p "$(dirname "$REPO_DIR")"
  if [[ $ssh_ok -eq 1 ]]; then
    git clone "$COLD_BREW_SSH_URL" "$REPO_DIR"
  else
    # gh clone carries its own auth, so this works even when SSH does not.
    gh repo clone "$COLD_BREW_REPO" "$REPO_DIR"
  fi

  # A clone command that exits 0 without producing a repo would otherwise fail
  # confusingly several steps later.
  [[ -d "$REPO_DIR/.git" ]] || die "Clone reported success but $REPO_DIR is not a git repo"
  info "Cloned to $REPO_DIR"
fi

step "Handing off to bootstrap"

cd "$REPO_DIR"

if [[ ! -f .env ]]; then
  cp .env.example .env
  info "Created .env from .env.example (GITEA_TOKEN stays empty: Gitea uses SSH)"
fi

if [[ $RUN_BOOTSTRAP -eq 0 ]]; then
  info "Skipping bootstrap (--no-bootstrap). Run it with: cd $REPO_DIR && ./bootstrap.sh"
  exit 0
fi

./bootstrap.sh

step "Authenticating the non-GitHub remotes"

# Delegated to the repo's own script rather than reimplemented here, so the
# glab and Gitea logic lives in exactly one place. It has to run after
# bootstrap.sh, which installs the ~/.ssh/config aliases it probes.
if [[ -x scripts/git/setup-remote-auth.sh ]]; then
  if ! ./scripts/git/setup-remote-auth.sh; then
    warn "Some remotes still need attention. Re-run later with: cd $REPO_DIR && make auth"
  fi
else
  warn "scripts/git/setup-remote-auth.sh not found; run 'make auth' manually"
fi

step "Checking the result"

# Run the diagnosis here rather than only suggesting it: the whole point of
# this script is that the machine ends up in a known state, and that claim
# should be demonstrated, not left as an exercise. A failing check must not
# fail the install, though, since everything above already succeeded.
doctor_rc=0
./scripts/doctor.sh || doctor_rc=$?

step "Done"

cat <<EOF

  cold-brew is installed at $REPO_DIR

  Next:
    1. Open a NEW terminal. The shell config in ~/.zshrc.d only applies to
       shells started after this run.
    2. Re-check the machine any time:
         cd $REPO_DIR && make doctor
    3. See everything available:
         cd $REPO_DIR && make help

  Before ever wiping or rebuilding this machine:
    cd $REPO_DIR && make check-unsaved

EOF

if [[ $doctor_rc -ne 0 ]]; then
  warn "doctor reported failures above. The install finished, but fix those before relying on it."
  warn "Most are resolved by: cd $REPO_DIR && make auth"
fi
