#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# 3x-ui runtime information (read-only)
# ==================================================

XUI_DB="/etc/x-ui/x-ui.db"

require_xui_db() {
  if [[ ! -f "$XUI_DB" ]]; then
    echo "ERROR: x-ui database not found at $XUI_DB"
    exit 1
  fi
}

load_3xui_info() {
  require_xui_db
  XUI_PORT="$(sqlite3 "$XUI_DB" "select value from settings where key='webPort';")"
  XUI_BASE_PATH="$(sqlite3 "$XUI_DB" "select value from settings where key='webBasePath';")"

  if [[ -z "${XUI_PORT:-}" || -z "${XUI_BASE_PATH:-}" ]]; then
    echo "ERROR: Failed to read 3x-ui port or web base path"
    exit 1
  fi

  export XUI_PORT
  export XUI_BASE_PATH
}

get_3xui_port() {
  echo "$XUI_PORT"
}

get_3xui_web_base_path() {
  echo "$XUI_BASE_PATH"
}
