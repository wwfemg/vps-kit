#!/usr/bin/env bash
set -euo pipefail

# load go / xcaddy module
source scripts/lib/40-go-xcaddy.sh

# load caddy module
source scripts/lib/30-caddy.sh

# load 3x-ui module
source scripts/lib/20-3xui.sh

# load mandatory input module
source scripts/lib/10-input.sh


# === mandatory inputs (ask once) ===
ask_domain
ask_install_mode
ask_naive_auth
ask_xui_auth


# configure 3x-ui admin account (auto)
configure_3xui_account


# ==================================================
# start caddy (with naive proxy if enabled)
run_caddy
# Entry point for VPS 3x-ui + Caddy (+ NaiveProxy)
# ==================================================


# ===== Final Output =====
source scripts/lib/90-output.sh