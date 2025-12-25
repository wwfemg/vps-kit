#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Final Output
# ==================================================

print_final_output() {
  if [[ -z "${INSTALL_DOMAIN:-}" || -z "${XUI_BASE_PATH:-}" ]]; then
    echo "[ERROR] Missing required variables for final output"
    exit 1
  fi

  echo
  echo "========================================"
  echo " Access URL (HTTPS):"
  echo " https://${INSTALL_DOMAIN}${XUI_BASE_PATH}"
  echo
  echo " Note:"
  echo " - Username & Password were printed once during 3x-ui installation."
  echo " - Please scroll back in your terminal to retrieve them."
  echo
  echo " 说明："
  echo " - 3x-ui 的用户名和密码只在安装完成时输出一次"
  echo " - 请向上滚动终端查看当时的原始输出"
  echo "========================================"
  echo
}

print_final_output
