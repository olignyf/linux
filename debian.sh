#!/bin/bash
set -e

# Step 1: Verify we are on Debian 13 (Trixie)
if [ ! -f /etc/os-release ]; then
  echo "Error: /etc/os-release not found. This does not look like Debian." >&2
  exit 1
fi
# shellcheck source=/dev/null
. /etc/os-release
if [ "${ID}" != "debian" ] || [ "${VERSION_CODENAME}" != "trixie" ]; then
  echo "Error: This script is for Debian 13 (Trixie). Found: ${ID:-unknown} ${VERSION_CODENAME:-unknown}" >&2
  exit 1
fi
echo "Detected Debian 13 (Trixie)."

# Require root for modifying /etc/apt and running apt
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root (e.g. sudo $0)." >&2
  exit 1
fi

# Colored splash screen (fixed-width lines so box aligns)
show_splash() {
  local bold cyan green yellow dim reset
  bold=$(tput bold)
  cyan=$(tput setaf 6)
  green=$(tput setaf 2)
  yellow=$(tput setaf 3)
  dim=$(tput dim)
  reset=$(tput sgr0)
  clear
  echo ""
  local w=58
  local pad
  printf -v pad '%-*s' "$w" "  Debian 13 (Trixie) — Setup"
  echo -e "${bold}${cyan}╔══════════════════════════════════════════════════════════════╗${reset}"
  echo -e "${bold}${cyan}║${reset}${bold}${pad}${reset}${bold}${cyan}      ║${reset}"
  echo -e "${bold}${cyan}╠══════════════════════════════════════════════════════════════╣${reset}"
  printf -v pad '%-*s' "$w" "  • Configure apt sources (main, security, updates)"
  echo -e "${bold}${cyan}║${reset}${pad:0:2}${green}${pad:2:1}${reset}${pad:3}${bold}${cyan}      ║${reset}"
  printf -v pad '%-*s' "$w" "  • Install GNOME extensions: prefs + Dash to Panel"
  echo -e "${bold}${cyan}║${reset}${pad:0:2}${green}${pad:2:1}${reset}${pad:3}${bold}${cyan}      ║${reset}"
  printf -v pad '%-*s' "$w" "  • Optional: full system upgrade (you will be asked)"
  echo -e "${bold}${cyan}║${reset}${pad:0:2}${green}${pad:2:1}${reset}${pad:3}${bold}${cyan}      ║${reset}"
  printf -v pad '%-*s' "$w" "  • Install kernel headers for current kernel"
  echo -e "${bold}${cyan}║${reset}${pad:0:2}${green}${pad:2:1}${reset}${pad:3}${bold}${cyan}      ║${reset}"
  printf -v pad '%-*s' "$w" "  • Install nvm (Node Version Manager)"
  echo -e "${bold}${cyan}║${reset}${pad:0:2}${green}${pad:2:1}${reset}${pad:3}${bold}${cyan}      ║${reset}"
  echo -e "${bold}${cyan}╚══════════════════════════════════════════════════════════════╝${reset}"
  echo ""
  echo -e "  ${dim}${yellow}Press ${bold}Space${reset}${dim} to continue or ${bold}Esc${reset}${dim} to exit.${reset}"
  echo ""
  local key
  while true; do
    read -n 1 -s -r key
    if [[ "$key" == ' ' ]]; then
      break
    fi
    if [[ "$key" == 'q' || "$key" == 'Q' || "$key" == $'\e' ]]; then
      echo -e "${reset}"
      echo "Exiting."
      exit 0
    fi
  done
  echo -e "${reset}"
}
show_splash

SOURCES_LIST="/etc/apt/sources.list"

# Step 2: Show current sources.list
echo "Current ${SOURCES_LIST}:"
echo "---"
cat "${SOURCES_LIST}"
echo "---"

# Add a line to sources.list only if it is not already present
add_if_missing() {
  local line="$1"
  if ! grep -qF -- "${line}" "${SOURCES_LIST}"; then
    echo "${line}" >> "${SOURCES_LIST}"
    echo "Added: ${line}"
  fi
}

# Step 3: Add the missing lines for main, security, and updates
add_if_missing "deb http://deb.debian.org/debian/ trixie main non-free-firmware contrib non-free"
add_if_missing "deb-src http://deb.debian.org/debian/ trixie main non-free-firmware contrib non-free"
add_if_missing "deb http://security.debian.org/debian-security trixie-security main non-free-firmware contrib non-free"
add_if_missing "deb-src http://security.debian.org/debian-security trixie-security main non-free-firmware contrib non-free"
add_if_missing "deb http://deb.debian.org/debian/ trixie-updates main non-free-firmware contrib non-free"
add_if_missing "deb-src http://deb.debian.org/debian/ trixie-updates main non-free-firmware contrib non-free"

echo "Running apt update..."
apt update

echo "Installing gnome-shell-extension-prefs and dash-to-panel..."
apt install -y gnome-shell-extension-prefs gnome-shell-extension-dash-to-panel

# promp user if he wants to upgrade the system
read -p "Do you want to upgrade the system? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    apt upgrade
else
    echo "Skipping system upgrade."
fi

# install kernel headers
apt install -y linux-headers-$(uname -r)

wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

echo "Done."
