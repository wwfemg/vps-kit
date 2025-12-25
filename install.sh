#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# VPS-KIT (Debian Only) - 3x-ui + Caddy (+ NaiveProxy)
# Single-file installer with BBR & 'vps' Command
# ==========================================================

# -----------------------------
# Helpers
# -----------------------------
hr() { printf "%s\n" "=================================================="; }
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
warn_box() {
  hr
  echo "正在进行最终配置，请耐心等待"
  echo "Configuring services, please DO NOT interrupt"
  hr
}

# -----------------------------
# Global Vars
# -----------------------------
MODE=""
DOMAIN=""
XUI_USER=""
XUI_PASS=""
XUI_SET_ENABLED="no"
NAIVE_USER=""
NAIVE_PASS=""
XUI_PORT=""
XUI_WEBBASEPATH=""
ARCH=""
GO_VER_PRIMARY=""
GO_VER_FALLBACK=""

# -----------------------------
# 1. Input Section
# -----------------------------
ask_mode() {
  hr
  echo "请选择安装模式 / Select install mode:"
  echo "  A) 3x-ui + Caddy (HTTPS Only)"
  echo "  B) 3x-ui + Caddy + NaiveProxy (Full Performance)"
  hr
  while true; do
    read -rp "请输入 A 或 B / Enter A or B: " MODE
    MODE="$(echo "${MODE}" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
    case "${MODE}" in
      A|B) return 0 ;;
      *) echo "输入无效 / Invalid input." ;;
    esac
  done
}

ask_domain_required() {
  hr
  echo "【必须输入】域名 / Domain (REQUIRED)"
  echo "不输入将无法继续 / Cannot continue without domain"
  hr
  while true; do
    read -rp "请输入已解析到本机的域名 / Enter domain: " DOMAIN
    DOMAIN="$(echo "${DOMAIN}" | tr -d ' ')"
    [[ -n "${DOMAIN}" ]] && break
    echo "域名不能为空 / Domain cannot be empty."
  done
}

ask_xui_auth_optional_3tries() {
  hr
  echo "【可选】3x-ui 面板账号 / 3x-ui credentials (OPTIONAL)"
  echo "最多 3 次，空输入跳过 / Up to 3 tries, blank to skip"
  hr
  local tries=0
  while (( tries < 3 )); do
    tries=$((tries + 1))
    read -rp "3x-ui 用户名 (空跳过) / Username (blank to skip) [${tries}/3]: " XUI_USER
    XUI_USER="$(echo "${XUI_USER}" | tr -d ' ')"
    
    if [[ -z "${XUI_USER}" ]]; then
      echo "已跳过 3x-ui 设置 / Skipped."
      XUI_SET_ENABLED="no"
      XUI_USER=""
      XUI_PASS=""
      return 0
    fi

    read -rsp "3x-ui 密码 (必填) / Password (required): " XUI_PASS
    echo
    if [[ -n "${XUI_PASS}" ]]; then
      XUI_SET_ENABLED="yes"
      return 0
    fi
    echo "密码不能为空 / Password empty."
  done
  XUI_SET_ENABLED="no"
  XUI_USER=""
  XUI_PASS=""
}

ask_naive_auth_required() {
  if [[ "${MODE}" != "B" ]]; then return 0; fi
  hr
  echo "【必须输入】NaiveProxy 账号 / NaiveProxy credentials"
  hr
  while true; do
    read -rp "Naive 用户名 / Username: " NAIVE_USER
    NAIVE_USER="$(echo "${NAIVE_USER}" | tr -d ' ')"
    [[ -n "${NAIVE_USER}" ]] && break
    echo "不能为空 / Cannot be empty."
  done
  while true; do
    read -rsp "Naive 密码 / Password: " NAIVE_PASS
    echo
    [[ -n "${NAIVE_PASS}" ]] && break
    echo "不能为空 / Cannot be empty."
  done
}

# -----------------------------
# 2. System Tune (BBR)
# -----------------------------
enable_bbr() {
  hr
  log "正在开启 BBR 加速 / Enabling BBR..."
  
  # Remove old lines if present to avoid duplicates
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  
  sysctl -p >/dev/null 2>&1 || true
  log "BBR 已开启 / BBR Enabled."
  hr
}

# -----------------------------
# 3. Installation
# -----------------------------
install_base_deps() {
  log "Updating apt & installing tools..."
  apt update -y
  apt install -y curl wget socat vim git
}

install_3xui_default() {
  if command -v x-ui >/dev/null 2>&1; then
    log "3x-ui already installed."
    return 0
  fi
  log "Installing 3x-ui (default)..."
  local tmp="/tmp/3xui_install.sh"
  curl -fsSL "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh" -o "${tmp}"
  chmod +x "${tmp}"
  # Force default install
  ( yes "" | timeout 1800 bash "${tmp}" ) || true
  rm -f "${tmp}"
}

install_caddy_official() {
  if command -v caddy >/dev/null 2>&1; then
    log "Caddy already installed."
    return 0
  fi
  log "Installing Official Caddy..."
  apt install -y debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt update -y
  apt install -y caddy
}

# -----------------------------
# 4. Mode B Extras (Go + xcaddy)
# -----------------------------
detect_arch() {
  local m
  m="$(uname -m)"
  case "${m}" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) err "Unsupported arch: ${m}"; exit 1 ;;
  esac
}

install_go_xcaddy_naive() {
  if [[ "${MODE}" != "B" ]]; then return 0; fi

  detect_arch
  
  # Fetch Go versions
  local json
  json="$(curl -fsSL "https://go.dev/dl/?mode=json" || true)"
  GO_VER_PRIMARY="$(echo "${json}" | grep -oE '"version":"go[0-9]+\.[0-9]+\.[0-9]+"' | head -n1 | cut -d'"' -f4 || echo "go1.22.6")"
  GO_VER_FALLBACK="$(echo "${json}" | grep -oE '"version":"go[0-9]+\.[0-9]+\.[0-9]+"' | head -n2 | tail -n1 | cut -d'"' -f4 || echo "go1.22.5")"
  
  local url="https://go.dev/dl/${GO_VER_PRIMARY}.linux-${ARCH}.tar.gz"
  log "Downloading Go: ${url}"
  
  if ! curl -fL --retry 3 -o "/tmp/go.tar.gz" "${url}"; then
    log "Primary Go failed, trying fallback: ${GO_VER_FALLBACK}"
    curl -fL --retry 3 -o "/tmp/go.tar.gz" "https://go.dev/dl/${GO_VER_FALLBACK}.linux-${ARCH}.tar.gz" || { err "Go download failed"; exit 1; }
  fi

  rm -rf /usr/local/go
  tar -C /usr/local -xzf "/tmp/go.tar.gz"
  rm -f "/tmp/go.tar.gz"
  export PATH="$PATH:/usr/local/go/bin"
  
  log "Installing xcaddy..."
  /usr/local/go/bin/go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
  export PATH="$PATH:$HOME/go/bin"

  log "Building Naive Caddy..."
  local bdir="/tmp/caddy-build"
  mkdir -p "${bdir}" && cd "${bdir}"
  "$HOME/go/bin/xcaddy" build --with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive
  
  mv -f "${bdir}/caddy" /usr/bin/caddy
  chmod +x /usr/bin/caddy
  cd / && rm -rf "${bdir}"
  log "Naive Caddy Installed."
}

# -----------------------------
# 5. Configuration Phase
# -----------------------------
configure_xui() {
  if [[ "${XUI_SET_ENABLED}" == "yes" ]]; then
    timeout 90 bash -c "printf '\n6\ny\n%s\n%s\ny\n\n0\n0\n' \"${XUI_USER}\" \"${XUI_PASS}\" | x-ui" >/dev/null || true
  fi
  
  # Read settings dynamically
  local settings
  settings="$(x-ui settings 2>/dev/null || true)"
  
  XUI_PORT="$(echo "${settings}" | awk -F': ' 'tolower($1) ~ /listen_port/ {print $2}' | head -n1)"
  XUI_WEBBASEPATH="$(echo "${settings}" | awk -F': ' 'tolower($1) ~ /web_base_path/ {print $2}' | head -n1)"
  
  # Fallback parse
  if [[ -z "${XUI_PORT}" ]]; then
     XUI_PORT="$(x-ui 2>/dev/null | grep -i 'Port:' | head -n1 | awk '{print $2}')"
  fi
  if [[ -z "${XUI_WEBBASEPATH}" ]]; then
     XUI_WEBBASEPATH="$(x-ui 2>/dev/null | grep -i 'WebBasePath:' | head -n1 | awk '{print $2}')"
  fi
  
  # Cleanup variables if empty
  XUI_PORT="${XUI_PORT:-}"
  XUI_WEBBASEPATH="${XUI_WEBBASEPATH:-}"
}

write_caddyfile() {
  mkdir -p /etc/caddy
  if [[ "${MODE}" == "A" ]]; then
    cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    root * /usr/share/caddy
    file_server
    reverse_proxy localhost:${XUI_PORT}
}
EOF
  else
    cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    route {
        forward_proxy {
            basic_auth ${NAIVE_USER} ${NAIVE_PASS}
            hide_ip
            hide_via
            probe_resistance
        }
        reverse_proxy localhost:${XUI_PORT}
    }
}
EOF
  fi
}

# -----------------------------
# 6. Create Helper Command (vps)
# -----------------------------
create_info_command() {
  # Save static info for the helper script
  cat > /etc/vps-kit.conf <<EOF
MODE="${MODE}"
DOMAIN="${DOMAIN}"
NAIVE_USER="${NAIVE_USER}"
NAIVE_PASS="${NAIVE_PASS}"
EOF

  # Create the executable script
  cat > /usr/bin/vps <<'EOF'
#!/bin/bash
source /etc/vps-kit.conf 2>/dev/null || exit 1

# Read dynamic 3x-ui info
settings=$(x-ui settings 2>/dev/null || true)
port=$(echo "$settings" | awk -F': ' 'tolower($1) ~ /listen_port/ {print $2}' | head -n1)
path=$(echo "$settings" | awk -F': ' 'tolower($1) ~ /web_base_path/ {print $2}' | head -n1)
[[ -z "$port" ]] && port="Unknown"
[[ -z "$path" ]] && path="/"

echo "=================================================="
echo "               VPS-KIT INFO RECAP                 "
echo "=================================================="
echo "Domain:       ${DOMAIN}"
echo "X-UI URL:     https://${DOMAIN}/${path}"
echo "X-UI Port:    ${port}"
echo "--------------------------------------------------"
if [[ "${MODE}" == "B" ]]; then
echo "Naive Proxy:  ENABLED"
echo "Naive User:   ${NAIVE_USER}"
echo "Naive Pass:   ${NAIVE_PASS}"
echo "Naive Probe:  https://${NAIVE_USER}:${NAIVE_PASS}@${DOMAIN}"
else
echo "Naive Proxy:  DISABLED (Mode A)"
fi
echo "=================================================="
echo "Cert Path: /var/lib/caddy/.local/share/caddy/certificates/"
echo "=================================================="
EOF

  chmod +x /usr/bin/vps
}

# -----------------------------
# Main Execution
# -----------------------------
ask_mode
ask_domain_required
ask_xui_auth_optional_3tries
ask_naive_auth_required

enable_bbr   # <--- BBR First

hr
echo "[INSTALL] 开始安装 / Installing..."
hr

install_base_deps
install_3xui_default
install_caddy_official
install_go_xcaddy_naive

warn_box
echo "[CONFIG 1/5] Updating 3x-ui settings..."
configure_xui

if [[ -z "${XUI_PORT}" ]]; then
  err "Failed to detect 3x-ui port. Installation aborted."
  exit 1
fi

echo "[CONFIG 2/5] Writing Caddyfile..."
write_caddyfile

echo "[CONFIG 3/5] Creating shortcut command 'vps'..."
create_info_command

echo "[CONFIG 4/5] Restarting Caddy..."
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy

echo "[CONFIG 5/5] Done."

# Final Print using the new helper
/usr/bin/vps

echo
echo "提示：如果以后忘记信息，请在终端输入 'vps' 查看"
echo "Tip: Type 'vps' anytime to show this information again."
echo
