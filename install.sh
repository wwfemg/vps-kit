#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# VPS-KIT V5.0 (Debian Only) - Auto-Discovery Edition
# 1. 尊重原厂默认设置 (使用官方随机生成的端口)
# 2. 自动抓取配置 (不强制修改，而是自动读取)
# 3. 彻底解决交互卡死问题
# ==========================================================

# -----------------------------
# Helpers
# -----------------------------
hr() { printf "%s\n" "=================================================="; }
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
warn_box() {
  hr
  echo "正在进行最终配置，请耐心等待..."
  echo "Configuring services..."
  hr
}

# -----------------------------
# Global Vars
# -----------------------------
MODE=""
DOMAIN=""
XUI_USER=""
XUI_PASS=""
NAIVE_USER=""
NAIVE_PASS=""
# 这一版我们不预设端口，而是稍后抓取
REAL_PORT=""
REAL_PATH=""

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
  hr
  while true; do
    read -rp "请输入域名: " DOMAIN
    DOMAIN="$(echo "${DOMAIN}" | tr -d ' ')"
    [[ -n "${DOMAIN}" ]] && break
  done
}

ask_xui_auth_optional() {
  hr
  echo "【设置】3x-ui 面板账号"
  hr
  local tries=0
  while (( tries < 3 )); do
    tries=$((tries + 1))
    read -rp "设置 3x-ui 用户名 (空跳过) [${tries}/3]: " XUI_USER
    XUI_USER="$(echo "${XUI_USER}" | tr -d ' ')"
    
    if [[ -z "${XUI_USER}" ]]; then
      echo "使用默认账号 (admin/admin)。"
      XUI_USER="admin"
      XUI_PASS="admin"
      return 0
    fi

    read -rp "设置 3x-ui 密码 (必填): " XUI_PASS
    XUI_PASS="$(echo "${XUI_PASS}" | tr -d ' ')"
    if [[ -n "${XUI_PASS}" ]]; then return 0; fi
  done
  XUI_USER="admin"
  XUI_PASS="admin"
}

ask_naive_auth_required() {
  if [[ "${MODE}" != "B" ]]; then return 0; fi
  hr
  echo "【设置】NaiveProxy 代理账号"
  hr
  while true; do
    read -rp "设置 Naive 用户名: " NAIVE_USER
    NAIVE_USER="$(echo "${NAIVE_USER}" | tr -d ' ')"
    [[ -n "${NAIVE_USER}" ]] && break
  done
  while true; do
    read -rp "设置 Naive 密码: " NAIVE_PASS
    NAIVE_PASS="$(echo "${NAIVE_PASS}" | tr -d ' ')"
    [[ -n "${NAIVE_PASS}" ]] && break
  done
}

# -----------------------------
# 2. System & Install
# -----------------------------
enable_bbr() {
  log "Enabling BBR..."
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1 || true
}

install_base_deps() {
  log "Updating apt..."
  apt update -y
  apt install -y curl wget socat vim git
}

install_3xui_default() {
  if command -v x-ui >/dev/null 2>&1; then
    log "3x-ui already installed."
    return 0
  fi
  log "Installing 3x-ui..."
  local tmp="/tmp/3xui_install.sh"
  curl -fsSL "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh" -o "${tmp}"
  chmod +x "${tmp}"
  # 自动回车，接受官方的所有默认值（包括随机端口）
  ( yes "" | timeout 1800 bash "${tmp}" ) || true
  rm -f "${tmp}"
}

install_caddy_official() {
  if command -v caddy >/dev/null 2>&1; then return 0; fi
  log "Installing Caddy..."
  apt install -y debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt update -y
  apt install -y caddy
}

detect_arch() {
  local m
  m="$(uname -m)"
  case "${m}" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Error: Arch ${m} not supported"; exit 1 ;;
  esac
}

install_go_xcaddy_naive() {
  if [[ "${MODE}" != "B" ]]; then return 0; fi
  detect_arch
  
  local json
  json="$(curl -fsSL "https://go.dev/dl/?mode=json" || true)"
  GO_VER_PRIMARY="$(echo "${json}" | grep -oE '"version":"go[0-9]+\.[0-9]+\.[0-9]+"' | head -n1 | cut -d'"' -f4 || echo "go1.22.6")"
  
  local url="https://go.dev/dl/${GO_VER_PRIMARY}.linux-${ARCH}.tar.gz"
  log "Downloading Go: ${url}"
  
  if ! curl -fL --retry 3 -o "/tmp/go.tar.gz" "${url}"; then
     err "Go download failed"; exit 1
  fi

  rm -rf /usr/local/go
  tar -C /usr/local -xzf "/tmp/go.tar.gz"
  rm -f "/tmp/go.tar.gz"
  export PATH="$PATH:/usr/local/go/bin"
  
  if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
      echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
  fi
  
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
# 5. Configuration (Auto-Discovery Mode)
# -----------------------------
configure_xui_autodetect() {
  # 1. 仅修改账号密码 (如果用户设置了)
  # 端口和路径保持默认（即随机生成的）
  if [[ "${XUI_USER}" != "admin" || "${XUI_PASS}" != "admin" ]]; then
      log "Updating 3x-ui credentials..."
      /usr/local/x-ui/x-ui setting -username "${XUI_USER}" -password "${XUI_PASS}" >/dev/null 2>&1 || true
      /usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true
      sleep 3
  fi

  # 2. 核心：自动发现端口 (Auto-Discovery)
  log "Detecting 3x-ui port..."
  
  # 获取设置输出
  local raw_output
  raw_output="$(/usr/local/x-ui/x-ui settings 2>/dev/null)"
  
  # 使用强力正则抓取端口 (忽略颜色代码)
  REAL_PORT=$(echo "${raw_output}" | grep -i "port" | grep -oE '[0-9]+' | head -n1)
  
  # 抓取路径
  REAL_PATH=$(echo "${raw_output}" | grep -i "web_base_path" | awk '{print $NF}' | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
  
  # 保底 (万一万一抓取失败，回退到默认值)
  if [[ -z "${REAL_PORT}" ]]; then REAL_PORT=2053; fi
  if [[ -z "${REAL_PATH}" ]]; then REAL_PATH="/"; fi
  
  log "Detected Port: ${REAL_PORT}, Path: ${REAL_PATH}"
}

write_caddyfile() {
  log "Writing Caddyfile..."
  mkdir -p /etc/caddy
  
  # 使用刚才自动侦测到的 REAL_PORT
  if [[ "${MODE}" == "A" ]]; then
    cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    root * /usr/share/caddy
    file_server
    reverse_proxy localhost:${REAL_PORT}
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
        reverse_proxy localhost:${REAL_PORT}
    }
}
EOF
  fi
}

create_info_command() {
  # 写入配置文件
  cat > /etc/vps-kit.conf <<EOF
MODE="${MODE}"
DOMAIN="${DOMAIN}"
XUI_USER="${XUI_USER}"
XUI_PASS="${XUI_PASS}"
NAIVE_USER="${NAIVE_USER}"
NAIVE_PASS="${NAIVE_PASS}"
REAL_PORT="${REAL_PORT}"
REAL_PATH="${REAL_PATH}"
EOF

  cat > /usr/bin/vps <<'EOF'
#!/bin/bash
source /etc/vps-kit.conf 2>/dev/null || exit 1

echo
echo "###############################################"
echo "3x-ui登录的用户名密码，妥善保管。"
echo "Username:    ${XUI_USER}"
echo "Password:    ${XUI_PASS}"
echo "Port:        ${REAL_PORT} (Internal)"
echo "WebBasePath: ${REAL_PATH}"
echo "Access URL:  https://${DOMAIN}${REAL_PATH}"
echo "###############################################"

if [[ "${MODE}" == "B" ]]; then
echo
echo "###############################################"
echo "Naiveproxy用户名和密码，妥善保管"
echo "Username: ${NAIVE_USER}"
echo "Password: ${NAIVE_PASS}"
echo "###############################################"
fi
echo
EOF
  chmod +x /usr/bin/vps
}

# -----------------------------
# Main Execution
# -----------------------------
ask_mode
ask_domain_required
ask_xui_auth_optional
ask_naive_auth_required

enable_bbr

hr
echo "[INSTALL] Installing..."
hr

install_base_deps
install_3xui_default
install_caddy_official
install_go_xcaddy_naive

warn_box
echo "[CONFIG 1/4] Detecting 3x-ui Config..."
configure_xui_autodetect

echo "[CONFIG 2/4] Writing Caddyfile..."
write_caddyfile

echo "[CONFIG 3/4] Creating 'vps' command..."
create_info_command

echo "[CONFIG 4/4] Restarting Caddy..."
setcap cap_net_bind_service=+ep /usr/bin/caddy 2>/dev/null || true
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy

# Final Print
/usr/bin/vps

echo "Tip: Type 'vps' to show info."
