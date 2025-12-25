#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Mandatory user inputs
# ==================================================

# Global variables (exported)
INSTALL_DOMAIN=""
INSTALL_MODE=""        # stage1 | stage2
NAIVE_USERNAME=""
NAIVE_PASSWORD=""

ask_domain() {
  while true; do
    read -rp "Enter domain (required): " INSTALL_DOMAIN
    if [[ -z "$INSTALL_DOMAIN" ]]; then
      echo "Domain cannot be empty."
      continue
    fi
    # very basic domain format check
    if [[ "$INSTALL_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      export INSTALL_DOMAIN
      break
    else
      echo "Invalid domain format. Please enter a valid domain."
    fi
  done
}

ask_install_mode() {
  while true; do
    echo
    echo "Select installation mode:"
    echo "  1) 3x-ui + Caddy (HTTPS only)"
    echo "  2) 3x-ui + Caddy + NaiveProxy"
    read -rp "Enter choice [1 or 2]: " choice
    case "$choice" in
      1)
        INSTALL_MODE="stage1"
        export INSTALL_MODE
        break
        ;;
      2)
        INSTALL_MODE="stage2"
        export INSTALL_MODE
        break
        ;;
      *)
        echo "Invalid choice. Please enter 1 or 2."
        ;;
    esac
  done
}

ask_naive_auth() {
  if [[ "$INSTALL_MODE" != "stage2" ]]; then
    return
  fi

  while true; do
    read -rp "Enter NaiveProxy username (required): " NAIVE_USERNAME
    if [[ -n "$NAIVE_USERNAME" ]]; then
      break
    fi
    echo "Username cannot be empty."
  done

  while true; do
    read -rsp "Enter NaiveProxy password (required): " NAIVE_PASSWORD
    echo
    if [[ -n "$NAIVE_PASSWORD" ]]; then
      break
    fi
    echo "Password cannot be empty."
  done

  export NAIVE_USERNAME
  export NAIVE_PASSWORD
}
