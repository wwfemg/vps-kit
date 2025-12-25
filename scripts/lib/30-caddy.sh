#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Caddy install & configuration
# FINAL – controlled by install.sh
# ==================================================

CADDYFILE_PATH="/etc/caddy/Caddyfile"

# --------------------------------------------------
# Install Caddy (SERVICE ONLY, NO CONFIG)
# --------------------------------------------------
install_caddy() {
  if command -v caddy >/dev/null 2>&1; then
    echo "[INFO] Caddy already installed. Skipping."
    return
  fi

  echo "[INFO] Installing Caddy..."

  apt update
  apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gpg

  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list

  apt update
  apt install -y caddy

  echo "[INFO] Caddy installed."
}

# --------------------------------------------------
# Get 3x-ui listen port AFTER installation
# --------------------------------------------------
get_xui_port() {
  if command -v x-ui >/dev/null 2>&1; then
    XUI_PORT="$(x-ui settings 2>/dev/null | awk -F': ' '/listen_port/{print $2}' | head -n1)"
  fi

  if [[ -z "${XUI_PORT:-}" ]]; then
    XUI_PORT="2053"
  fi

  export XUI_PORT
}

# --------------------------------------------------
# Stage 1: HTTPS + static + reverse_proxy
# --------------------------------------------------
configure_caddy_stage1() {
  get_xui_port

  if [[ -z "${INSTALL_DOMAIN:-}" ]]; then
    echo "[ERROR] INSTALL_DOMAIN not set"
    exit 1
  fi

  echo "[INFO] Writing Caddyfile (stage1)"

  cat > "$CADDYFILE_PATH" <<CADDY
${INSTALL_DOMAIN} {
    root * /usr/share/caddy
    file_server
    reverse_proxy localhost:${XUI_PORT}
}
CADDY
}

# --------------------------------------------------
# Stage 2: NaiveProxy + reverse_proxy
# (NO stage1 config, NO static)
# --------------------------------------------------
configure_caddy_stage2() {
  get_xui_port

  if [[ -z "${INSTALL_DOMAIN:-}" || -z "${NAIVE_USERNAME:-}" || -z "${NAIVE_PASSWORD:-}" ]]; then
    echo "[ERROR] Missing required variables for stage2"
    exit 1
  fi

  echo "[INFO] Writing Caddyfile (stage2 / NaiveProxy)"

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
}

# --------------------------------------------------
# Reload / start Caddy (CALLED ONCE by install.sh)
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