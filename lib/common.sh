# shellcheck shell=bash
# Common helpers: OS detection and logging.
# Intended to be sourced, not executed.

# ---------- logging ----------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  _c_reset=$'\033[0m'
  _c_red=$'\033[31m'
  _c_green=$'\033[32m'
  _c_yellow=$'\033[33m'
  _c_blue=$'\033[34m'
  _c_bold=$'\033[1m'
else
  _c_reset=""
  _c_red=""
  _c_green=""
  _c_yellow=""
  _c_blue=""
  _c_bold=""
fi

log_info()  { printf '%s==>%s %s\n' "${_c_blue}${_c_bold}" "${_c_reset}" "$*"; }
log_ok()    { printf '%s✓%s %s\n'    "${_c_green}${_c_bold}" "${_c_reset}" "$*"; }
log_warn()  { printf '%s!%s %s\n'    "${_c_yellow}${_c_bold}" "${_c_reset}" "$*" >&2; }
log_error() { printf '%sx%s %s\n'    "${_c_red}${_c_bold}"    "${_c_reset}" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

# ---------- OS detection ----------
#
# Sets the following globals after `detect_os`:
#
#   OS_FAMILY   one of: macos | linux | windows
#   OS_DISTRO   one of: macos | debian | arch | fedora | windows | unknown
#   OS_LABEL    human-readable label, for logging
#
# "debian" covers Debian, Ubuntu, and derivatives (Pop, Mint, WSL Ubuntu...).
# "arch"   covers Arch, Manjaro, EndeavourOS, etc.

detect_os() {
  local uname_s
  uname_s=$(uname -s 2>/dev/null || echo unknown)

  case "$uname_s" in
    Darwin)
      OS_FAMILY="macos"
      OS_DISTRO="macos"
      OS_LABEL="macOS $(sw_vers -productVersion 2>/dev/null || echo '')"
      ;;
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
          *)
            OS_DISTRO="unknown"
            ;;
        esac
      else
        OS_LABEL="Linux"
        OS_DISTRO="unknown"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      OS_FAMILY="windows"
      OS_DISTRO="windows"
      OS_LABEL="Windows ($uname_s)"
      ;;
    *)
      OS_FAMILY="unknown"
      OS_DISTRO="unknown"
      OS_LABEL="$uname_s"
      ;;
  esac

  export OS_FAMILY OS_DISTRO OS_LABEL
}

# ---------- misc helpers ----------

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Read a package list file: strip comments and blank lines.
# Usage: read_pkg_list <path>
read_pkg_list() {
  local f=$1
  [ -r "$f" ] || return 0
  # Strip full-line comments, inline "# ..." tails, and trim whitespace.
  sed -E 's/[[:space:]]*#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//' "$f" \
    | grep -v '^$' \
    || true
}
