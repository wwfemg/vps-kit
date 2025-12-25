#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Caddy configuration
# stage1 / stage2 FINAL LOGIC
# ==================================================

CADDYFILE_PATH="/etc/caddy/Caddyfile"

# --------------------------------------------------
# Get 3x-ui actual listen port AFTER installation
# --------------------------------------------------
get_xui_port() {
  # Try x-ui settings output (preferred)
  if command -v x-ui >/dev/null 2>&1; then
    XUI_PORT="$(x-ui settings 2>/dev/null | awk -F': ' '/listen_port/{print $2}' | head -n1)"
  fi

  # Fallback: default 2053 if still empty
  if [[ -z "${XUI_PORT:-}" ]]; then
    XUI_PORT="2053"
  fi

  export XUI_PORT
}

# --------------------------------------------------
# Stage 1: simple HTTPS + static + reverse_proxy
# --------------------------------------------------
setup_caddy_stage1() {
  get_xui_port

  if [[ -z "${INSTALL_DOMAIN:-}" ]]; then
    echo "[ERROR] INSTALL_DOMAIN not set"
    exit 1
  fi

  echo "[INFO] Writing Caddyfile for stage1 (simple mode)"

  cat > "$CADDYFILE_PATH" <<CADDY
${INSTALL_DOMAIN} {
    root * /usr/share/caddy
    file_server
    reverse_proxy localhost:${XUI_PORT}
}
CADDY

  reload_caddy
}

# --------------------------------------------------
# Stage 2: NaiveProxy + reverse_proxy (NO static)
# --------------------------------------------------
setup_caddy_stage2() {
  get_xui_port

  if [[ -z "${INSTALL_DOMAIN:-}" || -z "${NAIVE_USERNAME:-}" || -z "${NAIVE_PASSWORD:-}" ]]; then
    echo "[ERROR] Missing required variables for stage2"
    exit 1
  fi

  echo "[INFO] Writing Caddyfile for stage2 (NaiveProxy mode)"

  cat > "$CADDYFILE_PATH" <<CADDY
${INSTALL_DOMAIN} {
    route {
        forward_proxy {
            basic_auth ${NAIVE_USERNAME} ${NAIVE_PASSWORD}
            hide_ip
            hide_via
            probe_resistance
        }
        reverse_proxy localhost:${XUI_PORT}
    }
}
CADDY

  reload_caddy
}

# --------------------------------------------------
# Reload / start Caddy
# --------------------------------------------------
reload_caddy() {
  if systemctl is-active --quiet caddy; then
    systemctl reload caddy
    echo "[INFO] Caddy reloaded"
  else
    systemctl start caddy
    echo "[INFO] Caddy started"
  fi
}

# --------------------------------------------------
# Dispatcher
# --------------------------------------------------
run_caddy() {
  case "$INSTALL_MODE" in
    stage1)
      setup_caddy_stage1
      ;;
    stage2)
      setup_caddy_stage2
      ;;
    *)
      echo "[ERROR] Unknown INSTALL_MODE: $INSTALL_MODE"
      exit 1
      ;;
  esac
}