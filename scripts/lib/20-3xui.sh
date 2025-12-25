#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# 3x-ui automatic account configuration
# Uses printf | x-ui (NO heredoc interaction)
# ==================================================

configure_3xui_account() {
  if [[ -z "${XUI_USER:-}" || -z "${XUI_PASS:-}" ]]; then
    echo "[ERROR] XUI_USER / XUI_PASS not set"
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

# allow direct execution for testing
if [[ "${1:-}" == "run" ]]; then
  configure_3xui_account
fi
