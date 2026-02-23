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
  local bold cyan green blue dim reset
  bold=$(tput bold)
  cyan=$(tput setaf 6)
  green=$(tput setaf 2)
  blue=$(tput setaf 12)
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
  printf -v pad '%-*s' "$w" "  • Install kernel headers for current kernel"
  echo -e "${bold}${cyan}║${reset}${pad:0:2}${green}${pad:2:1}${reset}${pad:3}${bold}${cyan}      ║${reset}"
  printf -v pad '%-*s' "$w" "  • Install dev tools: nvm, pyenv"
  echo -e "${bold}${cyan}║${reset}${pad:0:2}${green}${pad:2:1}${reset}${pad:3}${bold}${cyan}      ║${reset}"
  echo -e "${bold}${cyan}╚══════════════════════════════════════════════════════════════╝${reset}"
  echo ""
  echo -e "  ${dim}${green}${bold}Press Space${reset} or ${green}${bold}Enter${reset}${dim} to continue, ${bold}Esc${reset}${dim} or ${bold}Q${reset}${dim} to exit.${reset}"
  echo ""
  local key
  while true; do
    read -r -s -N 1 key < /dev/tty
    case "$key" in
      ' '|$'\x20'|$'\n'|$'\r') break ;;
      [qQ]|$'\e') echo -e "${reset}"; echo "Exiting."; exit 0 ;;
    esac
  done
  echo -e "${reset}"
}
show_splash

# Increase bash history size for all users (only if not already set)
BASHRC="/etc/bash.bashrc"
if ! grep -q 'HISTSIZE=' "${BASHRC}" 2>/dev/null && ! grep -q 'HISTFILESIZE=' "${BASHRC}" 2>/dev/null; then
  echo '' >> "${BASHRC}"
  echo '# Increase history size (added by debian.sh)' >> "${BASHRC}"
  echo 'HISTSIZE=50000' >> "${BASHRC}"
  echo 'HISTFILESIZE=50000' >> "${BASHRC}"
  echo "Added HISTSIZE=50000 and HISTFILESIZE=50000 to ${BASHRC}"
else
  echo "History size already configured in ${BASHRC}, skipping."
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

echo "Installing gnome-shell-extension-prefs and dash-to-panel..."
apt install -y gnome-shell-extension-prefs gnome-shell-extension-dash-to-panel terminator xfce4-terminal locate


# Create terminator config for the user who ran sudo (not root)
if [ -n "${SUDO_USER:-}" ]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  if [ -n "$USER_HOME" ]; then
    TERM_CONFIG_DIR="$USER_HOME/.config/terminator"
    mkdir -p "$TERM_CONFIG_DIR"
    cat <<EOF > "$TERM_CONFIG_DIR/config"
[global_config]
  copy_on_selection = True
[keybindings]
[profiles]
  [[default]]
    cursor_color = "#aaaaaa"
    use_system_font = True
    font = JetBrainsMono Nerd Font 14
[layouts]
  [[default]]
    [[[child1]]]
      parent = window0
      type = Terminal
    [[[window0]]]
      parent = ""
      type = Window
[plugins]
EOF
    chown -R "$SUDO_USER:$SUDO_USER" "$TERM_CONFIG_DIR"
    echo "Terminator config written to $TERM_CONFIG_DIR for $SUDO_USER."
  else
    echo "Could not find home for $SUDO_USER, skipping terminator config."
  fi
else
  echo "Not run via sudo: terminator config not written (run with: sudo $0)."
fi
echo "Terminator installed and 'Copy on Selection' enabled."

# xfce4-terminal: copy on select, paste on right click
if [ -n "${SUDO_USER:-}" ]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  if [ -n "$USER_HOME" ]; then
    XFCE_TERM_DIR="$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    mkdir -p "$XFCE_TERM_DIR"
    cat <<EOF > "$XFCE_TERM_DIR/xfce4-terminal.xml"
<?xml version="1.1" encoding="UTF-8"?>

<channel name="xfce4-terminal" version="1.0">
  <property name="misc-copy-on-select" type="bool" value="true"/>
  <property name="scrolling-lines" type="uint" value="999"/>
  <property name="scrolling-unlimited" type="bool" value="true"/>
  <property name="misc-default-geometry" type="string" value="100x44"/>
</channel>

EOF

    chown -R "$SUDO_USER:$SUDO_USER" "$XFCE_TERM_DIR"
    echo "xfce4-terminal config written to $XFCE_TERM_DIR (copy on select, paste on right click)."
  fi
fi

# install kernel headers
apt install -y linux-headers-$(uname -r)

# dev stuff
apt install -y build-essential checkinstall libssl-dev libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev liblzma-dev wget curl llvm libncurses-dev xz-utils git
curl https://pyenv.run | bash

# Ensure pyenv block is in the real user's .bashrc (if not already)
if [ -n "${SUDO_USER:-}" ]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  if [ -n "$USER_HOME" ]; then
    USER_BASHRC="$USER_HOME/.bashrc"
    if ! grep -q 'pyenv init' "$USER_BASHRC" 2>/dev/null; then
      cat <<'PYENV_EOF' >> "$USER_BASHRC"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"
PYENV_EOF
      echo "Added pyenv block to $USER_BASHRC for $SUDO_USER."
    else
      echo "pyenv already configured in $USER_BASHRC, skipping."
    fi
  fi
fi

wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

echo "Done."
