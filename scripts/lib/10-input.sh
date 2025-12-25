#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Mandatory user inputs / 必填用户输入
# ==================================================

# Global variables (exported)
INSTALL_DOMAIN=""
INSTALL_MODE=""        # stage1 | stage2
NAIVE_USERNAME=""
NAIVE_PASSWORD=""
XUI_USER=""
XUI_PASS=""

ask_domain() {
  while true; do
    read -rp "请输入域名 / Enter domain (required): " INSTALL_DOMAIN
    if [[ -z "$INSTALL_DOMAIN" ]]; then
      echo "域名不能为空 / Domain cannot be empty."
      continue
    fi
    if [[ "$INSTALL_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      export INSTALL_DOMAIN
      break
    else
      echo "域名格式不正确，请重新输入 / Invalid domain format."
    fi
  done
}

ask_install_mode() {
  while true; do
    echo
    echo "请选择安装模式 / Select installation mode:"
    echo "  1) 3x-ui + Caddy（仅 HTTPS / HTTPS only）"
    echo "  2) 3x-ui + Caddy + NaiveProxy"
    read -rp "请输入 1 或 2 / Enter choice [1 or 2]: " choice
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
        echo "无效选择，请输入 1 或 2 / Invalid choice."
        ;;
    esac
  done
}

ask_naive_auth() {
  if [[ "$INSTALL_MODE" != "stage2" ]]; then
    return
  fi

  while true; do
    read -rp "请输入 NaiveProxy 用户名 / Enter NaiveProxy username (required): " NAIVE_USERNAME
    [[ -n "$NAIVE_USERNAME" ]] && break
    echo "用户名不能为空 / Username cannot be empty."
  done

  while true; do
    read -rsp "请输入 NaiveProxy 密码 / Enter NaiveProxy password (required): " NAIVE_PASSWORD
    echo
    [[ -n "$NAIVE_PASSWORD" ]] && break
    echo "密码不能为空 / Password cannot be empty."
  done

  export NAIVE_USERNAME
  export NAIVE_PASSWORD
}

ask_xui_auth() {
  while true; do
    read -rp "请输入 3x-ui 面板用户名 / Enter 3x-ui panel username (required): " XUI_USER
    [[ -n "$XUI_USER" ]] && break
    echo "用户名不能为空 / Username cannot be empty."
  done

  while true; do
    read -rsp "请输入 3x-ui 面板密码 / Enter 3x-ui panel password (required): " XUI_PASS
    echo
    [[ -n "$XUI_PASS" ]] && break
    echo "密码不能为空 / Password cannot be empty."
  done

  export XUI_USER
  export XUI_PASS
}