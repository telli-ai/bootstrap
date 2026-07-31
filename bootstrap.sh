#!/usr/bin/env bash
set -euo pipefail

# This script is intentionally secret-free so it can be published at a public URL.

repository_slug="${TELLI_BOOTSTRAP_REPOSITORY:-telli-ai/telli}"
checkout_path="${TELLI_BOOTSTRAP_CHECKOUT:-$HOME/Developer/telli}"
homebrew_install_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

log() {
  printf '%s\n' "$*"
}

section() {
  printf '\n==> %s\n' "$*"
}

run() {
  printf '+ %s\n' "$*"
  "$@"
}

fail() {
  log "$*"
  exit 1
}

require_supported_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "This bootstrap supports macOS only."

  case "$(uname -m)" in
    arm64 | x86_64)
      return
      ;;
    *)
      fail "Unsupported Mac architecture: $(uname -m)"
      ;;
  esac
}

require_interactive_terminal() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    fail "Run this bootstrap from an interactive Terminal with /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/telli-ai/bootstrap/main/bootstrap.sh)\"."
  fi
}

activate_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    eval "$(brew shellenv)"
    return
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return
  fi

  if [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_github_cli() {
  section "Checking GitHub CLI"

  if command -v gh >/dev/null 2>&1; then
    log "GitHub CLI is already installed."
    return
  fi

  activate_homebrew
  if ! command -v brew >/dev/null 2>&1; then
    log "+ /bin/bash -c \"\$(curl -fsSL $homebrew_install_url)\""
    /bin/bash -c "$(curl --proto '=https' --tlsv1.2 -fsSL "$homebrew_install_url")"
    activate_homebrew
  fi

  command -v brew >/dev/null 2>&1 || fail "Homebrew installed, but it is not available in this shell. Open a new shell and rerun this script."
  run brew install gh
  command -v gh >/dev/null 2>&1 || fail "GitHub CLI installed, but it is not available in this shell. Open a new shell and rerun this script."
}

authenticate_github() {
  section "Checking GitHub login"

  if gh auth status --hostname github.com >/dev/null 2>&1; then
    log "GitHub CLI is already logged in."
  else
    run gh auth login --hostname github.com --git-protocol https --web
  fi

  if ! gh repo view "$repository_slug" --json nameWithOwner --jq .nameWithOwner >/dev/null; then
    fail "GitHub authentication succeeded, but you cannot access $repository_slug. Accept the organization invitation and rerun this script."
  fi
}

require_safe_checkout_path() {
  [[ "$checkout_path" == /* ]] || fail "TELLI_BOOTSTRAP_CHECKOUT must be an absolute path."
  [[ "$checkout_path" != "/" ]] || fail "Refusing to use / as the checkout path."
  [[ "$checkout_path" != "$HOME" ]] || fail "Refusing to use your home directory as the checkout path."
}

clone_repository() {
  section "Checking telli checkout"
  require_safe_checkout_path

  if [[ -e "$checkout_path" ]]; then
    [[ -e "$checkout_path/.git" ]] || fail "$checkout_path already exists and is not a Git checkout."

    local remote
    remote="$(git -C "$checkout_path" remote get-url origin)"
    case "$remote" in
      "git@github.com:${repository_slug}.git" | "https://github.com/${repository_slug}" | "https://github.com/${repository_slug}.git" | "ssh://git@github.com/${repository_slug}.git")
        log "Using existing checkout: $checkout_path"
        return
        ;;
      *)
        fail "$checkout_path points to a different repository: $remote"
        ;;
    esac
  fi

  run mkdir -p "$(dirname "$checkout_path")"
  run gh repo clone "$repository_slug" "$checkout_path"
}

main() {
  require_supported_macos
  require_interactive_terminal
  install_github_cli
  authenticate_github
  clone_repository

  section "Checkout ready"
  log "$checkout_path"
}

main "$@"
