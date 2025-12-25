#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Load modules
# ==================================================

# load go / xcaddy module
source scripts/lib/40-go-xcaddy.sh

# load caddy module
source scripts/lib/30-caddy.sh

# load 3x-ui module
source scripts/lib/20-3xui.sh

# load mandatory input module
source scripts/lib/10-input.sh


# ==================================================
# 1) Collect user inputs (store only, NO changes)
# ==================================================
ask_domain
ask_install_mode
ask_naive_auth
ask_xui_auth


# ==================================================
# 2) Install phase (NO configuration)
# ==================================================
install_3xui
run_caddy


# ==================================================
# 3) Configure phase (AFTER all installs)
# ==================================================
configure_3xui_account


# ==================================================
# 4) Final Output
# ==================================================
source scripts/lib/90-output.sh