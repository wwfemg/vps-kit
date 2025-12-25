#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Load modules (ONLY functions, no logic here)
# ==================================================

source scripts/lib/10-input.sh
source scripts/lib/20-3xui.sh
source scripts/lib/30-caddy.sh
source scripts/lib/40-go-xcaddy.sh

# ==================================================
# 1) Collect user inputs (STORE ONLY)
# ==================================================
ask_domain
ask_install_mode
ask_naive_auth
ask_xui_auth

# ==================================================
# 2) Install phase (STRICTLY no custom config)
# ==================================================
echo
echo "==============================================="
echo "[INSTALL] Installing required software..."
echo "==============================================="

# 2.1 install 3x-ui (non-interactive)
install_3xui

# 2.2 install caddy (base service only)
install_caddy

# 2.3 stage2 only: install go / xcaddy / naive dependencies
if [[ "$INSTALL_MODE" == "stage2" ]]; then
  prepare_go_xcaddy
  install_naiveproxy || true
fi

# ==================================================
# 3) Configure phase (ALL custom config happens HERE)
# ==================================================
echo
echo "==============================================="
echo "[CONFIG] Configuring services, please wait..."
echo "==============================================="

# 3.1 configure 3x-ui panel account (BOTH stage1 & stage2)
echo "[CONFIG] (1/3) Configuring 3x-ui panel..."
configure_3xui_account

# 3.2 configure caddy
# - stage1: configure stage1 caddy
# - stage2: SKIP stage1 config, directly configure stage2
if [[ "$INSTALL_MODE" == "stage1" ]]; then
  echo "[CONFIG] (2/3) Generating Caddy config (stage1)..."
  configure_caddy_stage1
fi

if [[ "$INSTALL_MODE" == "stage2" ]]; then
  echo "[CONFIG] (2/3) Generating Caddy config (stage2 / NaiveProxy)..."
  configure_caddy_stage2
fi

# 3.3 reload services (ONCE, after final config)
echo "[CONFIG] (3/3) Reloading services..."
reload_caddy

# ==================================================
# 4) Final output (ONLY after everything is done)
# ==================================================
source scripts/lib/90-output.sh