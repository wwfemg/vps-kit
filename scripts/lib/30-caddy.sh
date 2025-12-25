#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Caddy configuration (placeholder only)
# ==================================================

setup_caddy_stage1() {
  :
}

setup_caddy_stage2() {
  :
}

run_caddy() {
  # placeholder: real caddy setup will be implemented in later steps
  echo "[INFO] run_caddy placeholder invoked (no-op)"
}

run_caddy() {
  echo "[INFO] INSTALL_DOMAIN = $INSTALL_DOMAIN"
  echo "[INFO] INSTALL_MODE   = $INSTALL_MODE"
  echo "[INFO] XUI_PORT       = $XUI_PORT"
  echo "[INFO] XUI_BASE_PATH  = $XUI_BASE_PATH"

  if [[ "$INSTALL_MODE" == "stage1" ]]; then
    echo "[INFO] Stage1 selected: 3x-ui + Caddy (HTTPS only)"
  elif [[ "$INSTALL_MODE" == "stage2" ]]; then
    echo "[INFO] Stage2 selected: 3x-ui + Caddy + NaiveProxy"
    echo "[INFO] NAIVE_USERNAME = $NAIVE_USERNAME"
  else
    echo "[ERROR] Unknown INSTALL_MODE: $INSTALL_MODE"
    exit 1
  fi
}

dispatch_caddy() {
  case "$INSTALL_MODE" in
    stage1)
      setup_caddy_stage1
      ;;
    stage2)
      setup_caddy_stage2
      ;;
    *)
      echo "[ERROR] Unknown INSTALL_MODE in dispatcher: $INSTALL_MODE"
      exit 1
      ;;
  esac
}

# override run_caddy to use dispatcher
run_caddy() {
  echo "[INFO] Dispatching Caddy setup..."
  dispatch_caddy
}

setup_caddy_stage1() {
  echo "[INFO] Setting up Caddy for stage1 (3x-ui + HTTPS only)"

  if [[ -z "${INSTALL_DOMAIN:-}" || -z "${XUI_PORT:-}" ]]; then
    echo "[ERROR] Missing required variables for stage1"
    exit 1
  fi

  local CADDYFILE_PATH="/etc/caddy/Caddyfile"

  # Overwrite Caddyfile completely (as required)
  cat > "$CADDYFILE_PATH" <<CADDY
${INSTALL_DOMAIN} {
    reverse_proxy localhost:${XUI_PORT}
}
CADDY

  echo "[INFO] Caddyfile written to ${CADDYFILE_PATH}"

  # Reload caddy to apply HTTPS automatically
  if systemctl is-active --quiet caddy; then
    systemctl reload caddy
    echo "[INFO] Caddy reloaded"
  else
    systemctl start caddy
    echo "[INFO] Caddy started"
  fi
}
