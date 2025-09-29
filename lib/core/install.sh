#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
AUTO_YES=0
REPO_URL=""
OUTDIR="."
REQUIRED_CMDS=(ping curl dig whois wafw00f openssl nmap nc ruby)
OS_NAME="$(uname -s) $(uname -r || true)"
TIMESTAMP_NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SCRIPT_VERSION="1.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) AUTO_YES=1; shift ;;
    --repo) REPO_URL="$2"; shift 2 ;;
    --out) OUTDIR="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--yes] [--repo <repo_url>] [--out DIR]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

mkdir -p "$OUTDIR"

detect_pkg_mgr() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "brew"
  elif command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  elif command -v apk >/dev/null 2>&1; then
    echo "apk"
  else
    echo "unknown"
  fi
}

PKG_MGR=$(detect_pkg_mgr)

echo "giving 'chmod +x' access  to all module and core files"
chmod +x *.sh lib/*.sh lib/core/*.sh lib/module/*.sh
echo "done"
sleep 2
clear
echo "Detected package manager: $PKG_MGR"
echo "Output dir: $OUTDIR"
echo ""

#
# *	mapping: common package names by manager
#

declare -A PKG_MAP_apt=(
  [curl]=curl
  [dig]=dnsutils
  [whois]=whois
  [openssl]=openssl
  [nmap]=nmap
  [nc]=netcat-openbsd
  [ruby]=ruby
  [ping]=iputils-ping
)
declare -A PKG_MAP_dnf=(
  [curl]=curl
  [dig]=bind-utils
  [whois]=whois
  [openssl]=openssl
  [nmap]=nmap
  [nc]=nmap-ncat
  [ruby]=ruby
  [ping]=iputils
)
declare -A PKG_MAP_yum=()
for k in "${!PKG_MAP_dnf[@]}"; do PKG_MAP_yum[$k]="${PKG_MAP_dnf[$k]}"; done
declare -A PKG_MAP_pacman=(
  [curl]=curl
  [dig]=bind-tools
  [whois]=whois
  [openssl]=openssl
  [nmap]=nmap
  [nc]=openbsd-netcat
  [ruby]=ruby
  [ping]=inetutils
)
declare -A PKG_MAP_apk=(
  [curl]=curl
  [dig]=bind-tools
  [whois]=whois
  [openssl]=openssl
  [nmap]=nmap
  [nc]=netcat-openbsd
  [ruby]=ruby
  [ping]=iputils
)
declare -A PKG_MAP_brew=(
  [curl]=curl
  [dig]=bind
  [whois]=whois
  [openssl]=openssl@3
  [nmap]=nmap
  [nc]=netcat
  [ruby]=ruby
  [ping]=inetutils
)

case "$PKG_MGR" in
  apt) PKG_MAP=PKG_MAP_apt ;;
  dnf) PKG_MAP=PKG_MAP_dnf ;;
  yum) PKG_MAP=PKG_MAP_yum ;;
  pacman) PKG_MAP=PKG_MAP_pacman ;;
  apk) PKG_MAP=PKG_MAP_apk ;;
  brew) PKG_MAP=PKG_MAP_brew ;;
  *) PKG_MAP="" ;;
esac

declare -A INSTALLED_STATUS
check_commands() {
  for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      INSTALLED_STATUS["$cmd"]="yes"
    else
      INSTALLED_STATUS["$cmd"]="no"
    fi
  done
}

gather_missing_pkgs() {
  MISSING_PKGS=()
  if [[ -z "$PKG_MAP" ]]; then
    return
  fi
  local mapname="$PKG_MAP"
  for cmd in "${REQUIRED_CMDS[@]}"; do
    if [[ "${INSTALLED_STATUS[$cmd]}" == "no" ]]; then
      pkg="${mapname}[$cmd]"
      pkgname=$(eval "echo \${${mapname}[$cmd]-}")
      if [[ -n "$pkgname" ]]; then
        MISSING_PKGS+=("$pkgname")
      else
        MISSING_PKGS+=("$cmd")
      fi
    fi
  done
  MISSING_PKGS=($(printf "%s\n" "${MISSING_PKGS[@]}" | awk '!x[$0]++'))
}

install_pkgs() {
  local pkgs=("$@")
  if [[ "${#pkgs[@]}" -eq 0 ]]; then
    echo "No packages to install."
    return 0
  fi
  echo "Installing packages: ${pkgs[*]}"
  if [[ $AUTO_YES -eq 0 ]]; then
    read -rp "Proceed to install? [y/N]: " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      echo "Skipping install."
      return 1
    fi
  fi

  case "$PKG_MGR" in
    apt)
      sudo apt-get update
      sudo apt-get install -y "${pkgs[@]}"
      ;;
    dnf)
      sudo dnf install -y "${pkgs[@]}"
      ;;
    yum)
      sudo yum install -y "${pkgs[@]}"
      ;;
    pacman)
      sudo pacman -Sy --noconfirm "${pkgs[@]}"
      ;;
    apk)
      sudo apk add --no-cache "${pkgs[@]}"
      ;;
    brew)
      for p in "${pkgs[@]}"; do
        brew install "$p" || true
      done
      ;;
    *)
      echo "Unknown package manager. Manually install: ${pkgs[*]}"
      return 2
      ;;
  esac
}

write_config_yaml() {
  local cfgfile="$OUTDIR/config.yaml"
  echo "Writing config to $cfgfile"
  local now="$TIMESTAMP_NOW"
  declare -A VERSIONS
  for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ver="$($cmd --version 2>/dev/null | head -n1 || true)"
      if [[ -z "$ver" ]]; then
        ver="$($cmd -V 2>/dev/null | head -n1 || true)"
      fi
      VERSIONS["$cmd"]="${ver:-unknown}"
    else
      VERSIONS["$cmd"]="not_installed"
    fi
  done

  LATEST_AVAILABLE="unknown"
  if [[ -n "$REPO_URL" ]]; then
    if command -v curl >/dev/null 2>&1 ; then
      for p in "" "latest" "VERSION" "version.txt"; do
        if curl -fsSL "${REPO_URL%/}/$p" -m 6 -o /tmp/.recontol_version 2>/dev/null; then
          LATEST_AVAILABLE="$(head -n1 /tmp/.recontol_version || true)"
          break
        fi
      done
    fi
  fi

  {
  cat <<YAML
version: "${SCRIPT_VERSION}"
generated_at: "${now}"
os: "${OS_NAME}"
pkg_manager: "${PKG_MGR}"
repo_url: "${REPO_URL:-}"
latest_remote_version: "${LATEST_AVAILABLE}"
auto_update: ${AUTO_YES}
install_summary:
  output_dir: "${OUTDIR}"
  timestamp: "${now}"
modules:
YAML

  for cmd in "${REQUIRED_CMDS[@]}"; do
    installed="${INSTALLED_STATUS[$cmd]:-no}"
    ver="${VERSIONS[$cmd]}"
    cat <<YITEM
  - name: "${cmd}"
    installed: ${installed}
    version: "${ver}"
YITEM
  done

  cat <<YFOOT
notes:
  - "Packages 'sed','awk','grep','cut','tr','head','tail','printf','mkdir','date','cat' are expected from coreutils and are not listed above."
  - "If some packages remain uninstalled, run this script with --yes on a supported distro or install manually."
YFOOT
  } > "$cfgfile"

  echo "Done. Config written to $cfgfile"
}

echo "Checking commands..."
check_commands

echo "Status before install:"
for cmd in "${REQUIRED_CMDS[@]}"; do
  printf "  - %-8s : %s\n" "$cmd" "${INSTALLED_STATUS[$cmd]}"
done
echo ""

gather_missing_pkgs

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
  echo "Missing packages detected: ${MISSING_PKGS[*]}"
  install_pkgs "${MISSING_PKGS[@]}" || echo "Install skipped or failed; continuing to write config."
else
  echo "All required packages appear to be installed."
fi

check_commands
write_config_yaml

echo ""
echo "Validation summary:"
for cmd in "${REQUIRED_CMDS[@]}"; do
  status="${INSTALLED_STATUS[$cmd]}"
  if [[ "$status" == "yes" ]]; then
    echo " [OK] $cmd"
  else
    echo " [MISSING] $cmd  -> please install manually"
  fi
done

echo ""
echo "If you want a periodic update check, re-run this with --repo <repo_url> where the repo exposes a simple 'latest' or 'VERSION' file."
