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

echo "Installing gnome-shell-extension-prefs..."
apt install -y gnome-shell-extension-prefs

echo "Done."
