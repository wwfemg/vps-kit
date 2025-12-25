#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# 3x-ui installation (NON-interactive, safe return)
# ==================================================

install_3xui() {
  if command -v x-ui >/dev/null 2>&1; then
    echo "[INFO] 3x-ui already installed. Skipping installation."
    return
  fi

  echo "[INFO] Installing 3x-ui (non-interactive)..."

  export DEBIAN_FRONTEND=noninteractive
  TMP_INSTALLER="/tmp/3xui_install.sh"

  curl -fsSL https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TMP_INSTALLER"
  chmod +x "$TMP_INSTALLER"

  # 强制所有 y/n 走默认（n），避免阻塞 & 吃掉主流程
  sed -i 's/read -r answer/answer=n/g' "$TMP_INSTALLER"

  bash "$TMP_INSTALLER"

  rm -f "$TMP_INSTALLER"

  if ! command -v x-ui >/dev/null 2>&1; then
    echo "[ERROR] 3x-ui installation failed"
    exit 1
  fi

  echo "[INFO] 3x-ui installed successfully, returning to main installer."
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

  printf "\n6\ny\n%s\n%s\ny\n\n0\n0\n" "$XUI_USER" "$XUI_PASS" | x-ui

  echo "[INFO] 3x-ui account configured and panel restarted."
}

# debug hooks
if [[ "${1:-}" == "install" ]]; then
  install_3xui
elif [[ "${1:-}" == "configure" ]]; then
  configure_3xui_account
fi