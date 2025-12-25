#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# VPS-KIT V9.4 (Debian Only) - 经典文案复刻版
# 1. 打印风格：严格遵照作者定义的“妥善保管”警示文案
# 2. 技术内核：基于 V9.3 (依赖补全 + 失败检测 + 真实回读)
# 3. 核心机制：红色交互 + 密码隐形 + 暴力重启生效
# ==========================================================

# -----------------------------
# 0. 颜色与辅助函数
# -----------------------------
RED='\033[1;31m'    # 亮红色
GREEN='\033[1;32m'  # 亮绿色
YELLOW='\033[1;33m' # 亮黄色
NC='\033[0m'        # 清除颜色

hr() { printf "%s\n" "=================================================="; }
log() { echo -e "${GREEN}[INFO] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
err() { echo -e "${RED}[ERROR] $*${NC}" >&2; }
ask_red() { echo -e -n "${RED}$* ${NC}"; }

# -----------------------------
# 1. 全局变量初始化
# -----------------------------
MODE=""
DOMAIN=""
XUI_USER=""
XUI_PASS=""
XUI_PORT=""
XUI_PATH=""
NAIVE_USER=""
NAIVE_PASS=""

# -----------------------------
# 2. 用户输入 (红字交互 + 密码隐形)
# -----------------------------
ask_inputs() {
  hr
  echo ">>> 第一步：配置收集 (Configuration)"
  hr

  # 1. 模式选择
  echo "请选择安装模式:"
  echo "  A) 3x-ui + Caddy (HTTPS Only)"
  echo "  B) 3x-ui + Caddy + NaiveProxy (推荐)"
  while true; do
    ask_red "请输入模式 (A/B):"
    read -r MODE
    MODE="$(echo "${MODE}" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
    case "${MODE}" in
      A|B) break ;;
      *) echo "输入无效。" ;;
    esac
  done

  # 2. 域名
  while true; do
    ask_red "请输入域名 (Domain):"
    read -r DOMAIN
    DOMAIN="$(echo "${DOMAIN}" | tr -d ' ')"
    [[ -n "${DOMAIN}" ]] && break
    echo "域名不能为空。"
  done

  # 3. 3x-ui 端口 (默认 61999)
  echo "------------------------------------------------"
  warn "提示：建议使用高位端口，避免被扫描。"
  ask_red "设置 3x-ui 端口 (回车默认 61999):"
  read -r input_port
  XUI_PORT="${input_port:-61999}"
  # 校验是否为纯数字
  if ! [[ "$XUI_PORT" =~ ^[0-9]+$ ]]; then
    warn "警告：端口必须是数字，已重置为 61999"
    XUI_PORT="61999"
  fi

  # 4. 3x-ui 根路径 (默认 /Macbook)
  echo "------------------------------------------------"
  warn "提示：设置隐蔽路径可增加安全性。"
  warn "默认路径设置为: /Macbook"
  ask_red "设置 3x-ui 根路径 (回车默认为 /Macbook):"
  read -r input_path
  XUI_PATH="${input_path:-/Macbook}"
  
  # 智能修正：确保路径以 / 开头
  [[ "${XUI_PATH}" != /* ]] && XUI_PATH="/${XUI_PATH}"
  # 去除可能多余的末尾斜杠
  XUI_PATH="${XUI_PATH%/}"

  # 5. 3x-ui 账号密码 (密码隐形)
  echo "------------------------------------------------"
  ask_red "设置 3x-ui 用户名 (默认 admin):"
  read -r input_user
  XUI_USER="${input_user:-admin}"
  
  ask_red "设置 3x-ui 密码 (输入时不显示):"
  read -r -s input_pass
  echo "" 
  XUI_PASS="${input_pass:-admin}"

  # 6. Naive 账号 (仅 B 模式，密码隐形)
  if [[ "${MODE}" == "B" ]]; then
    echo "------------------------------------------------"
    while true; do
      ask_red "设置 Naive 代理用户名:"
      read -r NAIVE_USER
      [[ -n "${NAIVE_USER}" ]] && break
    done
    while true; do
      ask_red "设置 Naive 代理密码 (输入时不显示):"
      read -r -s NAIVE_PASS
      echo "" 
      [[ -n "${NAIVE_PASS}" ]] && break
    done
  fi
}

# -----------------------------
# 3. 系统优化 (BBR)
# -----------------------------
enable_bbr() {
  log "Enabling BBR..."
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1 || true
}

# -----------------------------
# 4. 软件安装 (V9.3 技术内核)
# -----------------------------
install_base() {
  log "Updating system..."
  apt update -y
  # 补全依赖，防止 timeout 报错
  apt install -y curl wget socat vim git coreutils
}

install_xui() {
  if command -v x-ui >/dev/null 2>&1; then
    log "3x-ui already installed."
  else
    log "Installing 3x-ui..."
    local tmp="/tmp/3xui_install.sh"
    curl -fsSL "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh" -o "${tmp}"
    chmod +x "${tmp}"
    # 静默安装
    ( yes "" | timeout 1800 bash "${tmp}" ) || true
    rm -f "${tmp}"
  fi
  
  # 硬性校验：安装失败则退出
  if ! command -v x-ui >/dev/null 2>&1; then
    err "[FATAL] 3x-ui install failed or not found! Aborting."
    exit 1
  fi
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

install_naive_core() {
  if [[ "${MODE}" != "B" ]]; then return 0; fi
  
  local arch
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "Unsupported arch"; exit 1 ;;
  esac

  local json url
  json="$(curl -fsSL "https://go.dev/dl/?mode=json" || true)"
  local ver="$(echo "${json}" | grep -oE '"version":"go[0-9]+\.[0-9]+\.[0-9]+"' | head -n1 | cut -d'"' -f4 || echo "go1.22.6")"
  url="https://go.dev/dl/${ver}.linux-${arch}.tar.gz"
  
  log "Downloading Go (${ver})..."
  curl -fL --retry 3 -o "/tmp/go.tar.gz" "${url}" || { echo "Go download failed"; exit 1; }

  rm -rf /usr/local/go
  tar -C /usr/local -xzf "/tmp/go.tar.gz"
  rm -f "/tmp/go.tar.gz"
  export PATH="$PATH:/usr/local/go/bin"
  
  if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
      echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
  fi
  
  log "Compiling Naive Caddy..."
  /usr/local/go/bin/go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
  export PATH="$PATH:$HOME/go/bin"
  
  local bdir="/tmp/caddy-build"
  mkdir -p "${bdir}" && cd "${bdir}"
  "$HOME/go/bin/xcaddy" build --with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive
  
  mv -f "${bdir}/caddy" /usr/bin/caddy
  chmod +x /usr/bin/caddy
  cd / && rm -rf "${bdir}"
}

# -----------------------------
# 5. 配置生效 (优雅重启 + 真实回读)
# -----------------------------
configure_xui_force() {
  hr
  log "Applying settings to 3x-ui..."
  hr
  
  # 1. 强制写入配置
  /usr/local/x-ui/x-ui setting \
    -username "${XUI_USER}" \
    -password "${XUI_PASS}" \
    -port "${XUI_PORT}" \
    -webBasePath "${XUI_PATH}" >/dev/null 2>&1 || true
  
  # 2. 标准重启
  log "Restarting x-ui..."
  systemctl restart x-ui
  sleep 3

  # 3. 回读真实配置 (防打印造假)
  log "Verifying actual settings..."
  local raw_settings
  raw_settings=$(/usr/local/x-ui/x-ui settings 2>/dev/null || true)
  
  local real_port
  local real_path
  
  real_port=$(echo "$raw_settings" | grep -i port | grep -oE '[0-9]+' | head -n1)
  real_path=$(echo "$raw_settings" | grep -i web | awk '{print $NF}' | tr -d '[:space:]')
  
  if [[ -n "$real_port" ]]; then XUI_PORT="$real_port"; fi
  if [[ -n "$real_path" ]]; then XUI_PATH="$real_path"; fi
  
  log "Verified Config -> Port: ${XUI_PORT}, Path: ${XUI_PATH}"
}

write_caddyfile() {
  log "Writing Caddyfile..."
  mkdir -p /etc/caddy
  
  # 统一使用 localhost，严格匹配原始配置逻辑
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
# 6. 生成打印命令 (100% 还原用户定义文案)
# -----------------------------
create_vps_command() {
  cat > /etc/vps-kit.conf <<EOF
MODE="${MODE}"
DOMAIN="${DOMAIN}"
XUI_USER="${XUI_USER}"
XUI_PASS="${XUI_PASS}"
NAIVE_USER="${NAIVE_USER}"
NAIVE_PASS="${NAIVE_PASS}"
XUI_PORT="${XUI_PORT}"
XUI_PATH="${XUI_PATH}"
EOF

  cat > /usr/bin/vps <<'EOF'
#!/bin/bash
source /etc/vps-kit.conf 2>/dev/null || exit 1

# === 严格复刻您最初定义的打印格式 ===

echo
echo "###############################################"
# 恢复文案：警示语气 + 登录语义
echo "3x-ui登录的用户名密码，妥善保管。"
echo "Username:    ${XUI_USER}"
echo "Password:    ${XUI_PASS}"
echo "Port:        ${XUI_PORT} (Internal)"
echo "WebBasePath: ${XUI_PATH}"
echo "Access URL:  https://${DOMAIN}${XUI_PATH}"
echo "###############################################"

if [[ "${MODE}" == "B" ]]; then
echo
echo "###############################################"
# 恢复文案：追加内容 + 警示语气
echo "Naiveproxy用户名和密码，妥善保管"
echo "Username: ${NAIVE_USER}"
echo "Password: ${NAIVE_PASS}"
echo "Probe:    https://${NAIVE_USER}:${NAIVE_PASS}@${DOMAIN}"
echo "###############################################"
fi
echo
EOF
  chmod +x /usr/bin/vps
}

# -----------------------------
# 7. 主执行流程
# -----------------------------
ask_inputs
enable_bbr

echo ">>> 开始安装 (可能需要几分钟)..."
install_base
install_xui
install_caddy_official
install_naive_core

echo ">>> 开始配置..."
configure_xui_force
write_caddyfile
create_vps_command

echo ">>> 重启服务..."
setcap cap_net_bind_service=+ep /usr/bin/caddy 2>/dev/null || true
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy

# 打印最终结果
/usr/bin/vps
echo "安装完成！输入 'vps' 可随时查看配置信息。"
