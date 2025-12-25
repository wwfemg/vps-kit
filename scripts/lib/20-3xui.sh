#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# 3x-ui installation (install only, NO configuration)
# ==================================================

install_3xui() {
  if command -v x-ui >/dev/null 2>&1; then
    echo "[INFO] 3x-ui already installed. Skipping installation."
    return
  fi

  echo "[INFO] Installing 3x-ui..."

  bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)

  if ! command -v x-ui >/dev/null 2>&1; then
    echo "[ERROR] 3x-ui installation failed"
    exit 1
  fi

  echo "[INFO] 3x-ui installed successfully."
}

# ==================================================
# 3x-ui automatic account configuration
# (must be called AFTER installation)
# ==================================================

configure_3xui_account() {
  if [[ -z "${XUI_USER:-}" || -z "${XUI_PASS:-}" ]]; then
    echo "[ERROR] XUI_USER / XUI_PASS not set"
    exit 1
  fi

  if ! command -v x-ui >/dev/null 2>&1; then
    echo "[ERROR] x-ui command not found. 3x-ui is not installed."
    exit 1
  fi

  echo "[INFO] Configuring 3x-ui panel account..."

  # Sequence validated on VPS:
  #  - initial Enter
  #  - menu 6
  #  - y (confirm)
  #  - username
  #  - password
  #  - y (apply & restart)
  #  - Enter (return)
  #  - 0, 0 (exit)
  printf "\n6\ny\n%s\n%s\ny\n\n0\n0\n" "$XUI_USER" "$XUI_PASS" | x-ui

  echo "[INFO] 3x-ui account configured and panel restarted."
}

# allow direct execution for testing (debug only)
if [[ "${1:-}" == "install" ]]; then
  install_3xui
elif [[ "${1:-}" == "configure" ]]; then
  configure_3xui_account
fi