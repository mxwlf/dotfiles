#!/usr/bin/env bash
#
# install.sh — Stage 2
#
# Orchestrates everything once bootstrap.sh has put rust, pacaptr, git,
# and the repo itself in place.
#
# Safe to re-run: pacaptr.toml sets `needed = true`, so installed packages
# are skipped.
#
# Intended to be invoked by bootstrap.sh, but also runnable standalone:
#
#   ~/.dotfiles/install.sh
#
# Environment overrides:
#   SKIP_PACKAGES=1   don't run pacaptr installs
#   SKIP_LINK=1       don't link dotfiles
#   SKIP_HOOKS=1      don't run post-install hooks

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"

# ---------- pacaptr config symlink ----------

link_pacaptr_config() {
  local src="$SCRIPT_DIR/config/pacaptr/pacaptr.toml"
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local dst="$xdg/pacaptr/pacaptr.toml"

  [ -r "$src" ] || { log_warn "No pacaptr.toml at $src — skipping symlink."; return 0; }

  mkdir -p "$(dirname "$dst")"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    log_ok "pacaptr.toml already linked"
    return 0
  fi

  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    local backup="$dst.backup.$(date +%s)"
    log_warn "Existing file at $dst — moving to $backup"
    mv "$dst" "$backup"
  fi

  ln -sfn "$src" "$dst"
  log_ok "Linked $dst -> $src"
}

# ---------- package install ----------
#
# Builds a package list based on OS_DISTRO and pipes it into a single
# `pacaptr -S --noconfirm` call.
#
# For macOS, a second pass installs GUI apps from packages/macos-cask.txt
# by passing `-- --cask` through to brew.

collect_packages_for_current_os() {
  local pkgdir="$SCRIPT_DIR/packages"
  read_pkg_list "$pkgdir/common.txt"

  case "$OS_DISTRO" in
    macos)    read_pkg_list "$pkgdir/macos.txt" ;;
    debian)   read_pkg_list "$pkgdir/linux-debian.txt" ;;
    arch)     read_pkg_list "$pkgdir/linux-arch.txt" ;;
    fedora)   read_pkg_list "$pkgdir/linux-fedora.txt" ;;
    windows)  read_pkg_list "$pkgdir/windows.txt" ;;
    *)        log_warn "No package overlay for distro=$OS_DISTRO" ;;
  esac
}

install_packages() {
  if [ "${SKIP_PACKAGES:-0}" = "1" ]; then
    log_warn "SKIP_PACKAGES=1 — skipping package install"
    return 0
  fi

  local pkgs
  # shellcheck disable=SC2207
  pkgs=( $(collect_packages_for_current_os | sort -u) )

  if [ "${#pkgs[@]}" -eq 0 ]; then
    log_warn "No packages resolved for this OS — nothing to install."
  else
    log_info "Installing ${#pkgs[@]} package(s) via pacaptr: ${pkgs[*]}"
    pacaptr -S --noconfirm "${pkgs[@]}"
  fi

  # macOS casks (GUI apps) — separate call with pass-through flag.
  if [ "$OS_DISTRO" = "macos" ]; then
    local casks
    # shellcheck disable=SC2207
    casks=( $(read_pkg_list "$SCRIPT_DIR/packages/macos-cask.txt" | sort -u) )
    if [ "${#casks[@]}" -gt 0 ]; then
      log_info "Installing ${#casks[@]} macOS cask(s): ${casks[*]}"
      pacaptr -S --noconfirm "${casks[@]}" -- --cask
    fi
  fi
}

# ---------- post-install hooks ----------

run_post_hooks() {
  if [ "${SKIP_HOOKS:-0}" = "1" ]; then
    log_warn "SKIP_HOOKS=1 — skipping post hooks"
    return 0
  fi
  local hook="$SCRIPT_DIR/hooks/${OS_DISTRO}-post.sh"
  if [ -x "$hook" ]; then
    log_info "Running post-install hook: $hook"
    "$hook"
  elif [ -f "$hook" ]; then
    log_info "Running post-install hook (sourced): $hook"
    # shellcheck disable=SC1090
    bash "$hook"
  else
    log_info "No post hook for $OS_DISTRO (looked for $hook)"
  fi
}

# ---------- dotfile linking (deferred) ----------
#
# Placeholder. Implement once you've decided on stow / hand-rolled / chezmoi.

link_dotfiles() {
  if [ "${SKIP_LINK:-0}" = "1" ]; then
    log_warn "SKIP_LINK=1 — skipping dotfile linking"
    return 0
  fi
  log_info "link_dotfiles(): not implemented yet — dotfile linking deferred."
}

# ---------- main ----------

main() {
  detect_os
  log_info "Stage 2 running for: $OS_LABEL (distro=$OS_DISTRO)"

  have_cmd pacaptr || die "pacaptr is not on PATH. Run bootstrap.sh first."

  link_pacaptr_config
  install_packages
  run_post_hooks
  link_dotfiles

  log_ok "Done. Open a new shell to pick up any PATH changes."
}

main "$@"
