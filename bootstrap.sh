#!/usr/bin/env bash
#
# bootstrap.sh — Stage 1
#
# One-shot bootstrapper. Safe to run either as:
#
#   curl -fsSL https://raw.githubusercontent.com/mxwlf/dotfiles/main/bootstrap.sh | bash
#
# or, after the repo is already cloned:
#
#   ~/.dotfiles/bootstrap.sh
#
# What it does, in order:
#   1. Detect OS.
#   2. Install a minimal C toolchain (needed by any fallback `cargo install`).
#   3. Install rustup + stable toolchain.
#   4. Install cargo-binstall (fast) then pacaptr; fall back to source build.
#   5. Install git via pacaptr.
#   6. Clone $DOTFILES_REPO into $DOTFILES_DIR (default ~/.dotfiles).
#   7. Exec $DOTFILES_DIR/install.sh.

set -euo pipefail

# ---------- config (overridable via env) ----------

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/mxwlf/dotfiles}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

# ---------- load helpers ----------
#
# When run from the cloned repo, `lib/common.sh` sits next to this script.
# When run via `curl | bash`, there's no file to source — we inline a tiny
# subset of helpers so stage 1 is fully self-contained.

_script_dir=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  _script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

if [ -n "$_script_dir" ] && [ -r "$_script_dir/lib/common.sh" ]; then
  # shellcheck disable=SC1091
  . "$_script_dir/lib/common.sh"
else
  # Minimal inline fallback (curl | bash case).
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _c_reset=$'\033[0m'; _c_red=$'\033[31m'; _c_green=$'\033[32m'
    _c_yellow=$'\033[33m'; _c_blue=$'\033[34m'; _c_bold=$'\033[1m'
  else
    _c_reset=""; _c_red=""; _c_green=""; _c_yellow=""; _c_blue=""; _c_bold=""
  fi
  log_info()  { printf '%s==>%s %s\n' "${_c_blue}${_c_bold}" "${_c_reset}" "$*"; }
  log_ok()    { printf '%s✓%s %s\n'    "${_c_green}${_c_bold}" "${_c_reset}" "$*"; }
  log_warn()  { printf '%s!%s %s\n'    "${_c_yellow}${_c_bold}" "${_c_reset}" "$*" >&2; }
  log_error() { printf '%sx%s %s\n'    "${_c_red}${_c_bold}"    "${_c_reset}" "$*" >&2; }
  die()       { log_error "$*"; exit 1; }
  have_cmd()  { command -v "$1" >/dev/null 2>&1; }

  detect_os() {
    local uname_s; uname_s=$(uname -s 2>/dev/null || echo unknown)
    case "$uname_s" in
      Darwin) OS_FAMILY="macos";   OS_DISTRO="macos";   OS_LABEL="macOS" ;;
      Linux)
        OS_FAMILY="linux"
        if [ -r /etc/os-release ]; then
          # shellcheck disable=SC1091
          . /etc/os-release
          OS_LABEL="${PRETTY_NAME:-Linux}"
          case "${ID:-}:${ID_LIKE:-}" in
            *debian*|*ubuntu*) OS_DISTRO="debian" ;;
            *arch*|*manjaro*)  OS_DISTRO="arch"   ;;
            *fedora*|*rhel*|*centos*) OS_DISTRO="fedora" ;;
            *) OS_DISTRO="unknown" ;;
          esac
        else
          OS_LABEL="Linux"; OS_DISTRO="unknown"
        fi
        ;;
      MINGW*|MSYS*|CYGWIN*)
        OS_FAMILY="windows"; OS_DISTRO="windows"; OS_LABEL="Windows ($uname_s)" ;;
      *) OS_FAMILY="unknown"; OS_DISTRO="unknown"; OS_LABEL="$uname_s" ;;
    esac
    export OS_FAMILY OS_DISTRO OS_LABEL
  }
fi

# ---------- stage 1 steps ----------

ensure_build_toolchain() {
  case "$OS_DISTRO" in
    macos)
      if ! xcode-select -p >/dev/null 2>&1; then
        log_info "Triggering Xcode Command Line Tools install…"
        xcode-select --install || true
        log_warn "A GUI prompt may have opened. Finish the install, then re-run this script."
        # If they're not installed yet, downstream cargo builds will fail.
        # We don't want to block forever, but we do want to stop early.
        if ! xcode-select -p >/dev/null 2>&1; then
          die "Xcode CLT not installed yet — rerun bootstrap after the install completes."
        fi
      fi
      ;;
    debian)
      log_info "Installing build prerequisites via apt…"
      sudo apt-get update -y
      sudo apt-get install -y --no-install-recommends \
        build-essential curl ca-certificates pkg-config libssl-dev git
      ;;
    arch)
      log_info "Installing build prerequisites via pacman…"
      sudo pacman -Sy --needed --noconfirm base-devel curl ca-certificates git
      ;;
    fedora)
      log_info "Installing build prerequisites via dnf…"
      sudo dnf install -y @development-tools curl ca-certificates openssl-devel git
      ;;
    windows)
      log_warn "Native Windows bootstrap is not supported by this script."
      log_warn "Please run it from WSL (Ubuntu recommended)."
      die "Unsupported OS for bash bootstrap."
      ;;
    *)
      log_warn "Unknown distro '$OS_LABEL' — skipping toolchain install, hoping for the best."
      ;;
  esac
}

ensure_rustup() {
  if have_cmd rustup && have_cmd cargo; then
    log_ok "rustup already installed ($(rustup --version 2>/dev/null | head -1))"
    return 0
  fi
  log_info "Installing rustup (stable toolchain)…"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --default-toolchain stable --profile minimal
}

# Make cargo available to THIS shell even if PATH hasn't been updated yet.
load_cargo_env() {
  if [ -r "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  if ! have_cmd cargo; then
    die "cargo not found on PATH after rustup install. Open a new shell and re-run."
  fi
}

ensure_cargo_binstall() {
  if have_cmd cargo-binstall; then
    log_ok "cargo-binstall already installed"
    return 0
  fi
  log_info "Installing cargo-binstall (prebuilt)…"
  # Official one-liner from the cargo-binstall project.
  if ! curl --proto '=https' --tlsv1.2 -sSfL \
        https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh \
        | bash; then
    log_warn "cargo-binstall install failed — will fall back to \`cargo install\`."
    return 1
  fi
  # The installer drops the binary in ~/.cargo/bin, already on our PATH via env.
  return 0
}

ensure_pacaptr() {
  if have_cmd pacaptr; then
    log_ok "pacaptr already installed ($(pacaptr --version 2>/dev/null | head -1))"
    return 0
  fi
  if have_cmd cargo-binstall; then
    log_info "Installing pacaptr via cargo-binstall…"
    if cargo binstall -y pacaptr; then
      return 0
    fi
    log_warn "cargo-binstall failed for pacaptr — falling back to source build."
  fi
  log_info "Installing pacaptr via \`cargo install\` (this can take a few minutes)…"
  cargo install pacaptr
}

ensure_git_via_pacaptr() {
  if have_cmd git; then
    log_ok "git already installed ($(git --version))"
    return 0
  fi
  log_info "Installing git via pacaptr…"
  pacaptr -S --noconfirm git
}

clone_or_update_repo() {
  if [ -d "$DOTFILES_DIR/.git" ]; then
    log_info "Dotfiles repo already at $DOTFILES_DIR — pulling latest…"
    git -C "$DOTFILES_DIR" fetch --quiet origin "$DOTFILES_BRANCH"
    git -C "$DOTFILES_DIR" checkout --quiet "$DOTFILES_BRANCH"
    git -C "$DOTFILES_DIR" pull --ff-only --quiet origin "$DOTFILES_BRANCH"
  elif [ -e "$DOTFILES_DIR" ]; then
    die "$DOTFILES_DIR exists but is not a git repo. Move it aside and re-run."
  else
    log_info "Cloning $DOTFILES_REPO -> $DOTFILES_DIR (branch: $DOTFILES_BRANCH)…"
    git clone --branch "$DOTFILES_BRANCH" --single-branch \
      "$DOTFILES_REPO" "$DOTFILES_DIR"
  fi
}

handoff_to_stage2() {
  local stage2="$DOTFILES_DIR/install.sh"
  if [ ! -x "$stage2" ]; then
    if [ -f "$stage2" ]; then
      chmod +x "$stage2"
    else
      die "Stage 2 script not found: $stage2"
    fi
  fi
  log_info "Handing off to $stage2"
  exec "$stage2" "$@"
}

# ---------- main ----------

main() {
  detect_os
  log_info "Detected OS: $OS_LABEL (family=$OS_FAMILY, distro=$OS_DISTRO)"

  ensure_build_toolchain
  ensure_rustup
  load_cargo_env
  ensure_cargo_binstall || true   # best effort
  ensure_pacaptr
  ensure_git_via_pacaptr
  clone_or_update_repo
  handoff_to_stage2 "$@"
}

main "$@"
