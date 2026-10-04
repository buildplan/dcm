#!/bin/sh
# shellcheck shell=sh
#
# install.sh - Installer for Docker Compose Manager (dcm)
#
set -eu

REPO_URL="https://raw.githubusercontent.com/buildplan/dcm/refs/heads/main/docker-compose-manager.sh"
INSTALL_DEST="/usr/local/bin/dcm"

# Terminal colors
if [ -t 1 ]; then
    RED='\033[31m' GREEN='\033[32m' CYAN='\033[36m' BOLD='\033[1m' RESET='\033[0m'
else
    RED='' GREEN='' CYAN='' BOLD='' RESET=''
fi

printf '%bInstalling Docker Compose Manager (dcm)...%b\n' "${BOLD}" "${RESET}"

# Check download tool
if command -v curl >/dev/null 2>&1; then
    DOWNLOAD_CMD="curl -sSL"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOAD_CMD="wget -qO-"
else
    printf '%bError:%b curl or wget is required to install dcm.\n' "${RED}" "${RESET}" >&2
    exit 1
fi

# Download to temporary file
tmp_file="$(mktemp 2>/dev/null || echo "/tmp/dcm_install_$$")"

if [ "$DOWNLOAD_CMD" = "curl -sSL" ]; then
    curl -sSL "$REPO_URL" -o "$tmp_file"
else
    wget -qO "$tmp_file" "$REPO_URL"
fi

if ! head -n 1 "$tmp_file" | grep -q "^#!/bin/sh"; then
    printf '%bError:%b Downloaded file is invalid.\n' "${RED}" "${RESET}" >&2
    rm -f "$tmp_file"
    exit 1
fi

# Check destination directory write permissions
dest_dir="${INSTALL_DEST%/*}"
if [ ! -w "$dest_dir" ]; then
    printf '%bError:%b No write permission to %s. Please run with sudo:\n' "${RED}" "${RESET}" "$dest_dir" >&2
    printf '  curl -sSL https://raw.githubusercontent.com/buildplan/dcm/refs/heads/main/install.sh | sudo sh\n' >&2
    rm -f "$tmp_file"
    exit 1
fi

cat "$tmp_file" > "$INSTALL_DEST"
chmod +x "$INSTALL_DEST"
rm -f "$tmp_file"

printf '%bSuccess:%b Installed %b%s%b\n' "${GREEN}" "${RESET}" "${CYAN}" "$INSTALL_DEST" "${RESET}"

# Install shell completions
if [ -x "$INSTALL_DEST" ]; then
    "$INSTALL_DEST" --install-completion || true
fi

printf '\n%b%bInstallation complete!%b Run %bdcm --help%b to get started.\n' \
    "${BOLD}" "${GREEN}" "${RESET}" "${CYAN}" "${RESET}"
