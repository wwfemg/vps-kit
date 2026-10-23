#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# VPS-KIT 2026.10.23 (Debian) - 3x-ui + Caddy (+ NaiveProxy)
#
# 用法: apt update -y && apt install -y curl && bash <(curl -Ls <本脚本地址>)
#
# 版本不硬编码，安装时探测上游配对好的最新组合。可选环境变量：
#   VPS_KIT_BUILD=1                              强制本机编译，跳过下载
#   VPS_KIT_BIN_REPO / VPS_KIT_BIN_TAG           换预编译二进制的来源
#   VPS_KIT_GO_VER / VPS_KIT_CADDY_VER
#   VPS_KIT_NAIVE_REF                            手动钉版本
#   VPS_KIT_DL_TIMEOUT / VPS_KIT_BUILD_TIMEOUT   超时上限（秒）
# ==========================================================

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
hr() { printf "%s\n" "=================================================="; }
log() { echo -e "${GREEN}[INFO] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
err() { echo -e "${RED}[ERROR] $*${NC}" >&2; }
ask_red() { echo -e -n "${RED}$* ${NC}"; }

MODE=""; DOMAIN=""; XUI_USER=""; XUI_PASS=""; XUI_PORT=""; XUI_PATH=""
NAIVE_USER=""; NAIVE_PASS=""; ARCH=""; SUB_PATH=""; SUB_PORT="2096"

GO_VER=""; CADDY_VER=""; NAIVE_REF=""; NAIVE_TAG=""
BUILD_TMP="/var/tmp/vps-kit-build"

BIN_REPO="${VPS_KIT_BIN_REPO:-wwfemg/vps-kit}"
BIN_TAG="${VPS_KIT_BIN_TAG:-caddy-v2.11.7-naive}"

DL_TIMEOUT="${VPS_KIT_DL_TIMEOUT:-180}"
BUILD_TIMEOUT="${VPS_KIT_BUILD_TIMEOUT:-1500}"

# ---- 0. 前置检查 ----
preflight() {
  [[ "$(id -u)" -eq 0 ]] || { err "必须用 root 运行"; exit 1; }
  case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) err "不支持的架构: $(uname -m)"; exit 1 ;;
  esac
  if ! command -v curl >/dev/null 2>&1; then
    log "curl 未安装，正在安装..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -y >/dev/null 2>&1 || true
    apt install -y curl >/dev/null 2>&1 || { err "curl 安装失败，请先手动执行: apt update -y && apt install -y curl"; exit 1; }
  fi
  log "架构: ${ARCH}"
}

# ---- 1. 用户输入 ----
ask_inputs() {
  hr; echo ">>> 第一步：配置收集"; hr

  echo "请选择安装模式:"
  echo "  A) 标准安装"
  echo "  B) 标准安装 + NaiveProxy"
  while true; do
    ask_red "请输入模式 (A/B):"; read -r MODE
    MODE="$(echo "${MODE}" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
    case "${MODE}" in A|B) break ;; *) echo "输入无效。" ;; esac
  done

  while true; do
    ask_red "请输入域名 (必须已解析到本机):"; read -r DOMAIN
    DOMAIN="$(echo "${DOMAIN}" | tr -d ' ')"
    [[ -z "${DOMAIN}" ]] && { echo "域名不能为空。"; continue; }
    local myip resolved
    myip="$(curl -fsS4 --max-time 10 https://api.ipify.org 2>/dev/null || true)"
    resolved="$(getent hosts "${DOMAIN}" 2>/dev/null | awk '{print $1}' | head -1 || true)"
    if [[ -z "${resolved}" ]]; then
      warn "域名未解析或 DNS 未生效。"
      ask_red "仍要继续？(y/N):"; read -r c; [[ "${c}" =~ ^[Yy]$ ]] && break || continue
    fi
    if [[ -n "${myip}" && "${resolved}" != "${myip}" ]]; then
      warn "域名解析到 ${resolved}，本机公网 IP 是 ${myip}，不一致（Cloudflare 开了橙云代理？证书会申请失败）。"
      ask_red "仍要继续？(y/N):"; read -r c; [[ "${c}" =~ ^[Yy]$ ]] && break || continue
    fi
    log "域名解析正常: ${DOMAIN} -> ${resolved}"
    break
  done

  echo "------------------------------------------------"
  warn "提示：建议使用高位端口，避免被扫描。"
  ask_red "设置 3x-ui 端口 (回车默认 61999):"; read -r input_port
  XUI_PORT="${input_port:-61999}"
  [[ "$XUI_PORT" =~ ^[0-9]+$ ]] || { warn "端口必须是数字，已重置为 61999"; XUI_PORT="61999"; }

  echo "------------------------------------------------"
  warn "提示：设置隐蔽路径可增加安全性。默认 /Macbook"
  ask_red "设置 3x-ui 根路径 (回车默认 /Macbook):"; read -r input_path
  XUI_PATH="${input_path:-/Macbook}"
  [[ "${XUI_PATH}" != /* ]] && XUI_PATH="/${XUI_PATH}"
  XUI_PATH="${XUI_PATH%/}"

  echo "------------------------------------------------"
  warn "提示：3x-ui 默认订阅路径 /sub/ 广为人知（官方也建议修改），"
  warn "      这里默认按面板路径派生，便于记忆。"
  ask_red "设置订阅路径 (回车默认 ${XUI_PATH}-sub):"; read -r input_sub
  SUB_PATH="${input_sub:-${XUI_PATH}-sub}"
  [[ "${SUB_PATH}" != /* ]] && SUB_PATH="/${SUB_PATH}"
  SUB_PATH="${SUB_PATH%/}"

  echo "------------------------------------------------"
  ask_red "设置 3x-ui 用户名 (默认 admin):"; read -r input_user
  XUI_USER="${input_user:-admin}"
  while true; do
    ask_red "设置 3x-ui 密码 (输入时不显示):"; read -r -s XUI_PASS; echo ""
    [[ -n "${XUI_PASS}" ]] && break; echo "密码不能为空。"
  done

  if [[ "${MODE}" == "B" ]]; then
    echo "------------------------------------------------"
    while true; do
      ask_red "设置 Naive 代理用户名:"; read -r NAIVE_USER
      [[ -n "${NAIVE_USER}" ]] && break
    done
    while true; do
      ask_red "设置 Naive 代理密码 (输入时不显示):"; read -r -s NAIVE_PASS; echo ""
      [[ -n "${NAIVE_PASS}" ]] && break
    done
  fi
}

# ---- 2. 系统优化 (BBR) ----
enable_bbr() {
  log "启用 BBR..."
  touch /etc/sysctl.conf
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1 || true
}

# ---- 3. 基础依赖 + 防火墙 ----
install_base() {
  log "更新系统并安装依赖..."
  export DEBIAN_FRONTEND=noninteractive
  apt update -y
  apt install -y curl wget socat vim git coreutils libcap2-bin ca-certificates gpg sqlite3

  log "清理防火墙规则..."
  iptables -P INPUT ACCEPT 2>/dev/null || true
  iptables -P FORWARD ACCEPT 2>/dev/null || true
  iptables -P OUTPUT ACCEPT 2>/dev/null || true
  iptables -F 2>/dev/null || true
  iptables -X 2>/dev/null || true
  command -v nft >/dev/null 2>&1 && nft flush ruleset 2>/dev/null || true
}

# ---- 4. 3x-ui（手动安装，跳过官方脚本的 SSL 交互） ----
install_xui() {
  if [[ -x /usr/local/x-ui/x-ui ]]; then
    log "3x-ui 已安装，跳过。"
    return 0
  fi
  log "安装 3x-ui（手动模式）..."

  local tag
  tag="$(curl -fsSL https://api.github.com/repos/MHSanaei/3x-ui/releases/latest \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')"
  [[ -n "${tag}" ]] || { err "获取 3x-ui 版本失败"; exit 1; }
  log "3x-ui 版本: ${tag}"

  local url="https://github.com/MHSanaei/3x-ui/releases/download/${tag}/x-ui-linux-${ARCH}.tar.gz"
  curl -fL --retry 3 -o /tmp/x-ui.tar.gz "${url}" || { err "下载 3x-ui 失败"; exit 1; }

  if curl -fL --retry 2 --max-time 30 -o /tmp/x-ui.tar.gz.sha256 "${url}.sha256" 2>/dev/null; then
    local want got
    want="$(awk 'NR==1{print $1}' /tmp/x-ui.tar.gz.sha256)"
    got="$(sha256sum /tmp/x-ui.tar.gz | awk '{print $1}')"
    if [[ -n "${want}" && "${want}" != "${got}" ]]; then
      err "3x-ui 包 sha256 校验失败（下载损坏？）"; err "期望 ${want}"; err "实际 ${got}"
      rm -f /tmp/x-ui.tar.gz /tmp/x-ui.tar.gz.sha256; exit 1
    fi
    log "3x-ui 包校验通过"
    rm -f /tmp/x-ui.tar.gz.sha256
  else
    warn "未取到 .sha256，跳过校验"
  fi

  rm -rf /usr/local/x-ui
  tar -C /usr/local -xzf /tmp/x-ui.tar.gz
  rm -f /tmp/x-ui.tar.gz

  chmod +x /usr/local/x-ui/x-ui
  chmod +x /usr/local/x-ui/bin/xray-linux-${ARCH} 2>/dev/null || true

  install -m755 /usr/local/x-ui/x-ui.sh /usr/bin/x-ui
  install -m644 /usr/local/x-ui/x-ui.service.debian /etc/systemd/system/x-ui.service

  /usr/local/x-ui/x-ui migrate >/dev/null 2>&1 || true

  systemctl daemon-reload
  systemctl enable x-ui >/dev/null 2>&1
  systemctl start x-ui
  sleep 2
  log "3x-ui 安装完成（不配 SSL，走 Caddy 反代）。"
}

configure_xui() {
  hr; log "写入 3x-ui 配置..."; hr
  /usr/local/x-ui/x-ui setting \
    -username "${XUI_USER}" \
    -password "${XUI_PASS}" \
    -port "${XUI_PORT}" \
    -listenIP 127.0.0.1 \
    -webBasePath "${XUI_PATH}" >/dev/null 2>&1 || true
  systemctl restart x-ui
  sleep 3
}

# ---- 订阅服务：改为只监听本机 + 自定义路径 + 走 Caddy ----
configure_sub() {
  local db="/etc/x-ui/x-ui.db"
  [[ -f "${db}" ]] || { warn "未找到 x-ui 数据库，跳过订阅配置"; return 0; }

  log "配置订阅服务（仅本机监听 + 自定义路径）..."
  sqlite3 "${db}" <<SQL >/dev/null 2>&1 || { warn "订阅配置写入失败"; return 0; }
INSERT OR REPLACE INTO settings (key,value) VALUES ('subEnable','true');
INSERT OR REPLACE INTO settings (key,value) VALUES ('subListen','127.0.0.1');
INSERT OR REPLACE INTO settings (key,value) VALUES ('subPort','${SUB_PORT}');
INSERT OR REPLACE INTO settings (key,value) VALUES ('subPath','${SUB_PATH}/');
INSERT OR REPLACE INTO settings (key,value) VALUES ('subURI','https://${DOMAIN}${SUB_PATH}/');
SQL

  systemctl restart x-ui
  sleep 4
}

# ---- 5. Caddy（模式 A：官方源） ----
install_caddy_official() {
  command -v caddy >/dev/null 2>&1 && { log "Caddy 已安装。"; return 0; }
  log "安装 Caddy（官方源）..."
  apt install -y debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt update -y
  apt install -y caddy
}

# ---- 6. NaiveProxy 核心（模式 B：xcaddy 编译 forwardproxy） ----

resolve_build_versions() {
  local json

  NAIVE_TAG="${VPS_KIT_NAIVE_TAG:-}"
  if [[ -z "${NAIVE_TAG}" ]]; then
    json="$(curl -fsSL --max-time 20 https://api.github.com/repos/klzgrad/forwardproxy/tags 2>/dev/null)" || json=""
    NAIVE_TAG="$(printf '%s\n' "${json}" | tr ',{}' '\n\n\n' \
      | sed -nE 's/.*"name": *"(v[0-9]+\.[0-9]+\.[0-9]+-naive)".*/\1/p' | awk 'NR==1')"
  fi
  [[ -n "${NAIVE_TAG}" ]] || { err "无法取得 forwardproxy 的配对 tag（网络问题？）"; exit 1; }

  CADDY_VER="${VPS_KIT_CADDY_VER:-${NAIVE_TAG%-naive}}"

  NAIVE_REF="${VPS_KIT_NAIVE_REF:-}"
  if [[ -z "${NAIVE_REF}" ]]; then
    json="$(curl -fsSL --max-time 20 \
      "https://api.github.com/repos/klzgrad/forwardproxy/git/ref/tags/${NAIVE_TAG}" 2>/dev/null)" || json=""
    NAIVE_REF="$(printf '%s\n' "${json}" | tr ',{}' '\n\n\n' \
      | sed -nE 's/.*"sha": *"([0-9a-f]{40})".*/\1/p' | awk 'NR==1')"
  fi
  [[ -n "${NAIVE_REF}" ]] || { err "无法取得 ${NAIVE_TAG} 的 commit（网络问题？）"; exit 1; }

  GO_VER="${VPS_KIT_GO_VER:-}"
  if [[ -z "${GO_VER}" ]]; then
    json="$(curl -fsSL --max-time 20 'https://go.dev/dl/?mode=json' 2>/dev/null)" || json=""
    GO_VER="$(printf '%s\n' "${json}" | tr ',{}' '\n\n\n' \
      | sed -nE 's/.*"version": *"go([0-9.]+)".*/\1/p' | awk 'NR==1')"
  fi
  [[ -n "${GO_VER}" ]] || { err "无法取得 Go 最新版本（网络问题？）"; exit 1; }

  log "版本组合: Go ${GO_VER} + Caddy ${CADDY_VER} + forwardproxy ${NAIVE_TAG} (${NAIVE_REF:0:12})"
}

fetch_prebuilt_caddy() {
  local base="https://github.com/${BIN_REPO}/releases/download/${BIN_TAG}"
  local bin="caddy-linux-${ARCH}"
  local tmp="${BUILD_TMP}/dl"

  log "下载预编译 Caddy（${BIN_REPO} @ ${BIN_TAG}，${ARCH}）..."
  rm -rf "${tmp}"; mkdir -p "${tmp}"

  curl -fL --retry 3 --max-time "${DL_TIMEOUT}" -o "${tmp}/${bin}" "${base}/${bin}" || {
    warn "二进制下载失败: ${base}/${bin}"; return 1; }

  curl -fL --retry 2 --max-time 60 -o "${tmp}/checksums.txt" "${base}/checksums.txt" || {
    warn "校验文件下载失败，拒绝使用未校验的二进制"; return 1; }

  local want got
  want="$(awk -v f="${bin}" '$2 ~ f {print $1; exit}' "${tmp}/checksums.txt")"
  got="$(sha256sum "${tmp}/${bin}" | awk '{print $1}')"
  if [[ -z "${want}" ]]; then
    warn "校验文件里没有 ${bin} 的条目"; return 1
  fi
  if [[ "${want}" != "${got}" ]]; then
    warn "sha256 不匹配（期望 ${want:0:16}… 实际 ${got:0:16}…）"; return 1
  fi
  log "sha256 校验通过"

  chmod +x "${tmp}/${bin}"
  "${tmp}/${bin}" list-modules 2>/dev/null | grep -q 'http.handlers.forward_proxy' || {
    warn "预编译产物里没有 forward_proxy 插件"; return 1; }

  install -m755 "${tmp}/${bin}" /usr/bin/caddy
  setcap cap_net_bind_service=+ep /usr/bin/caddy
  log "预编译 Caddy 安装完成: $(/usr/bin/caddy version 2>/dev/null | awk '{print $1}')"

  mkdir -p /etc/vps-kit
  curl -fsL --max-time 30 -o /etc/vps-kit/caddy-build-info.txt "${base}/build-info.txt" 2>/dev/null || true
  rm -rf "${tmp}"
  return 0
}

build_naive_caddy() {
  log "编译: Go ${GO_VER} + Caddy ${CADDY_VER} + forwardproxy ${NAIVE_REF}"

  rm -rf "${BUILD_TMP}" /usr/local/go
  mkdir -p "${BUILD_TMP}/caddy-build"
  export TMPDIR="${BUILD_TMP}" GOTMPDIR="${BUILD_TMP}" GOCACHE="${BUILD_TMP}/gocache" GOMODCACHE="${BUILD_TMP}/gomod"

  curl -fL --retry 3 --max-time "${DL_TIMEOUT}" -o "${BUILD_TMP}/go.tar.gz" \
    "https://go.dev/dl/go${GO_VER}.linux-${ARCH}.tar.gz" || { err "Go ${GO_VER} 下载失败"; return 1; }
  tar -C /usr/local -xzf "${BUILD_TMP}/go.tar.gz" || { err "Go 解压失败"; return 1; }
  rm -f "${BUILD_TMP}/go.tar.gz"
  export PATH="/usr/local/go/bin:${PATH}"

  timeout "${BUILD_TIMEOUT}" /usr/local/go/bin/go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest \
    || { err "xcaddy 安装失败或超时（${BUILD_TIMEOUT}s）"; return 1; }
  local xcaddy_bin
  xcaddy_bin="$(/usr/local/go/bin/go env GOPATH)/bin/xcaddy"
  [[ -x "${xcaddy_bin}" ]] || { err "xcaddy 不可执行"; return 1; }

  ( cd "${BUILD_TMP}/caddy-build" && timeout "${BUILD_TIMEOUT}" "${xcaddy_bin}" build "${CADDY_VER}" \
      --with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@"${NAIVE_REF}" ) \
      || { err "编译失败或超时（${BUILD_TIMEOUT}s）"; return 1; }

  [[ -x "${BUILD_TMP}/caddy-build/caddy" ]] || { err "编译产物缺失"; return 1; }
  "${BUILD_TMP}/caddy-build/caddy" list-modules 2>/dev/null | grep -q 'http.handlers.forward_proxy' \
    || { err "forward_proxy 插件缺失"; return 1; }

  install -m755 "${BUILD_TMP}/caddy-build/caddy" /usr/bin/caddy
  setcap cap_net_bind_service=+ep /usr/bin/caddy
  log "编译成功"
}

cleanup_build() {
  log "清理编译残留..."
  rm -rf "${BUILD_TMP}" /usr/local/go "${HOME}/go" "${HOME}/.cache/go-build"
  sed -i '\#export PATH=\$PATH:/usr/local/go/bin#d' ~/.bashrc 2>/dev/null || true
}

setup_caddy_service() {
  id caddy >/dev/null 2>&1 || useradd --system --home /var/lib/caddy --shell /usr/sbin/nologin caddy
  mkdir -p /var/lib/caddy /etc/caddy
  chown -R caddy:caddy /var/lib/caddy
  chmod 755 /etc/caddy

  cat > /etc/systemd/system/caddy.service <<'UNIT'
[Unit]
Description=Caddy
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
}

install_naive_core() {
  [[ "${MODE}" == "B" ]] || return 0

  if [[ -x /usr/bin/caddy ]] \
     && /usr/bin/caddy list-modules 2>/dev/null | grep -q 'http.handlers.forward_proxy'; then
    log "Caddy（含 forward_proxy）已安装，跳过编译。"
    setup_caddy_service
    return 0
  fi

  if [[ -z "${VPS_KIT_BUILD:-}" ]]; then
    mkdir -p "${BUILD_TMP}"
    if fetch_prebuilt_caddy; then
      rm -rf "${BUILD_TMP}"
      setup_caddy_service
      return 0
    fi
    warn "预编译下载不可用，回落到本机编译（会慢，1 核机器可能十分钟以上）。"
  else
    log "VPS_KIT_BUILD=1，跳过下载，直接本机编译。"
  fi

  resolve_build_versions
  build_naive_caddy || { err "编译失败。可手动指定版本重试："; \
    err "  # 回到较早的配对（NAIVE_REF 必须是 commit SHA 或分支名，不能用 tag 名）"; \
    err "  VPS_KIT_NAIVE_TAG=v2.11.2-naive bash install.sh"; \
    err "  # 或直接用 naive 分支 HEAD"; \
    err "  VPS_KIT_NAIVE_REF=naive bash install.sh"; \
    cleanup_build; exit 1; }
  cleanup_build
  setup_caddy_service
}

# ---- 7. Caddyfile ----
write_decoy_site() {
  mkdir -p /var/www/html
  chmod 755 /var/www /var/www/html
  if [[ ! -f /var/www/html/index.html ]]; then
  cat > /var/www/html/index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Welcome</title>
<style>
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
         font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
         background:#fafafa; color:#333; }
  .box { text-align:center; padding:40px; }
  h1 { font-weight:400; font-size:28px; margin:0 0 12px; }
  p { color:#888; font-size:15px; margin:0; }
</style>
</head>
<body>
  <div class="box">
    <h1>Welcome</h1>
    <p>This site is under construction.</p>
  </div>
</body>
</html>
HTML
  fi
  chmod -R 755 /var/www/html
}

write_caddyfile() {
  log "写入 Caddyfile..."
  mkdir -p /etc/caddy
  chmod 755 /etc/caddy
  write_decoy_site

  if [[ "${MODE}" == "A" ]]; then
    cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    header -Server
    # 拦广告接口（v3.9.0 起内置），必须在通用面板 handle 之前
    handle ${XUI_PATH}/sponsors/* {
        respond 404
    }
    handle ${XUI_PATH}/sponsors {
        header Content-Type application/json
        respond \`{"success":false}\` 200
    }
    handle ${XUI_PATH}* {
        reverse_proxy localhost:${XUI_PORT}
    }
    handle ${SUB_PATH}/* {
        reverse_proxy localhost:${SUB_PORT}
    }
    handle {
        root * /var/www/html
        file_server
    }
}
EOF
  else
    cat > /etc/caddy/Caddyfile <<EOF
:443, ${DOMAIN} {
    header -Server
    route {
        forward_proxy {
            basic_auth ${NAIVE_USER} ${NAIVE_PASS}
            hide_ip
            hide_via
            probe_resistance
        }
        # 拦广告接口。route 块按字面顺序匹配，必须放在面板 handle 之前
        handle ${XUI_PATH}/sponsors/* {
            respond 404
        }
        handle ${XUI_PATH}/sponsors {
            header Content-Type application/json
            respond \`{"success":false}\` 200
        }
        handle ${XUI_PATH}* {
            reverse_proxy localhost:${XUI_PORT}
        }
        handle ${SUB_PATH}/* {
            reverse_proxy localhost:${SUB_PORT}
        }
        handle {
            root * /var/www/html
            file_server
        }
    }
}
EOF
  fi
}

# ---- 证书短路径：固定软链接 /etc/vps-kit/cert.crt | cert.key ----
setup_cert_links() {
  mkdir -p /etc/vps-kit
  local crt key
  crt="$(find /var/lib/caddy -name "${DOMAIN}.crt" 2>/dev/null | awk 'NR==1')"
  key="$(find /var/lib/caddy -name "${DOMAIN}.key" 2>/dev/null | awk 'NR==1')"
  if [[ -n "${crt}" && -n "${key}" ]]; then
    ln -sfn "${crt}" /etc/vps-kit/cert.crt
    ln -sfn "${key}" /etc/vps-kit/cert.key
    log "证书短路径已建立: /etc/vps-kit/cert.crt | /etc/vps-kit/cert.key"
  else
    warn "未找到证书文件，短路径未建立（证书签发后可执行 vps 自动修复）"
  fi
}

wait_for_cert() {
  log "等待证书签发..."
  local i
  for i in $(seq 1 30); do
    if ss -tln 2>/dev/null | grep -q ':443' \
       && find /var/lib/caddy/.local/share/caddy/certificates -name "${DOMAIN}.crt" 2>/dev/null | grep -q .; then
      log "证书已签发。"; return 0
    fi
    sleep 5
  done
  if journalctl -u caddy --no-pager --since "20 min ago" 2>/dev/null \
     | grep -q 'rateLimited\|too many certificates'; then
    err "证书申请被 Let's Encrypt 限流（同一组域名 7 天上限 5 张）。"
    err "原因通常是同一个域名反复重装。解决办法二选一："
    err "  1) 换一个子域名重装（新域名额度是独立的，推荐）"
    err "  2) 等限额窗口过去，具体时间见："
    err "     journalctl -u caddy | grep -o 'retry after [^\\\"]*' | tail -1"
  else
    warn "证书等待超时，请用 'journalctl -u caddy | tail -30' 看具体原因。"
  fi
  return 1
}

# ---- 8. vps 查看命令 ----
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
SUB_PATH="${SUB_PATH}"
SUB_PORT="${SUB_PORT}"
EOF
  chmod 600 /etc/vps-kit.conf

  cat > /usr/bin/vps <<'EOF'
#!/bin/bash
source /etc/vps-kit.conf 2>/dev/null || exit 1

# 自愈：每次运行都刷新证书软链接（Caddy 换 CA 或续期导致路径变化时自动修正）
mkdir -p /etc/vps-kit
_crt="$(find /var/lib/caddy -name "${DOMAIN}.crt" 2>/dev/null | head -1)"
_key="$(find /var/lib/caddy -name "${DOMAIN}.key" 2>/dev/null | head -1)"
[[ -n "${_crt}" ]] && ln -sfn "${_crt}" /etc/vps-kit/cert.crt
[[ -n "${_key}" ]] && ln -sfn "${_key}" /etc/vps-kit/cert.key

echo
echo "###############################################"
echo "3x-ui 登录信息，妥善保管。"
echo "Username:    ${XUI_USER}"
echo "Password:    ${XUI_PASS}"
echo "Port:        ${XUI_PORT} (Internal)"
echo "WebBasePath: ${XUI_PATH}"
echo "Access URL:  https://${DOMAIN}${XUI_PATH}"
echo "-----------------------------------------------"
echo "订阅地址（面板里每个客户端的订阅 ID 接在后面）:"
echo "  https://${DOMAIN}${SUB_PATH}/<订阅ID>"
echo "-----------------------------------------------"
echo "证书路径（在 3x-ui 面板配 TLS 时填这两行）:"
echo "  公钥: /etc/vps-kit/cert.crt"
echo "  私钥: /etc/vps-kit/cert.key"
echo "###############################################"
if [[ "${MODE}" == "B" ]]; then
echo
echo "###############################################"
echo "NaiveProxy 账号，妥善保管"
echo "Username: ${NAIVE_USER}"
echo "Password: ${NAIVE_PASS}"
echo "Proxy:    https://${NAIVE_USER}:${NAIVE_PASS}@${DOMAIN}"
echo "###############################################"
fi
echo
echo "服务状态:"
systemctl is-active caddy >/dev/null 2>&1 && echo "  caddy: 运行中" || echo "  caddy: 未运行"
systemctl is-active x-ui >/dev/null 2>&1 && echo "  x-ui:  运行中" || echo "  x-ui:  未运行"

# 复查广告拦截：上游若改了接口路径，拦截会静默失效。
_ads="$(curl -s --max-time 8 "https://${DOMAIN}${XUI_PATH}/sponsors" 2>/dev/null || true)"
_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "https://${DOMAIN}${XUI_PATH}/sponsors" 2>/dev/null || true)"
if [[ "${_ads}" == '{"success":false}' ]]; then
  echo "  广告拦截: 生效"
elif [[ -z "${_code}" || "${_code}" == "000" ]]; then
  # HTTPS 整个不通时无从判断，不能报成"拦截失效"
  echo "  广告拦截: 无法判断（HTTPS 不通，先看上面的服务状态和证书）"
else
  echo "  广告拦截: 已失效！HTTP ${_code}，返回 ${_ads:-<空>}"
  echo "            上游可能改了接口路径，需要更新 Caddyfile 里的 handle 规则。"
fi
echo
EOF
  chmod +x /usr/bin/vps
}

# ---- 9. 安装后自检 ----
self_check() {
  hr; log "安装后自检..."; hr
  local fail=0

  systemctl is-active --quiet caddy && echo "  [OK] caddy 运行中" || { echo "  [FAIL] caddy 未运行"; fail=1; }
  systemctl is-active --quiet x-ui && echo "  [OK] x-ui 运行中" || { echo "  [FAIL] x-ui 未运行"; fail=1; }

  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://${DOMAIN}${XUI_PATH}/" 2>/dev/null || true)"
  [[ "${code}" == "200" || "${code}" == "302" ]] \
    && echo "  [OK] 面板可访问 (HTTP ${code})" \
    || { echo "  [FAIL] 面板不可访问 (HTTP ${code})"; fail=1; }

  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://${DOMAIN}/" 2>/dev/null || true)"
  [[ "${code}" == "200" ]] \
    && echo "  [OK] 伪装站正常 (根路径 HTTP 200)" \
    || { echo "  [FAIL] 伪装站异常 (根路径 HTTP ${code})"; fail=1; }

  local ads
  ads="$(curl -s --max-time 15 "https://${DOMAIN}${XUI_PATH}/sponsors" 2>/dev/null || true)"
  [[ "${ads}" == '{"success":false}' ]] \
    && echo "  [OK] 广告接口已拦截（返回本机空响应）" \
    || { echo "  [FAIL] 广告接口仍在透传: ${ads:-<空>}"; fail=1; }

  if ss -tln 2>/dev/null | grep -qE "0\.0\.0\.0:${XUI_PORT}|\*:${XUI_PORT}|\[::\]:${XUI_PORT}"; then
    echo "  [FAIL] 面板端口 ${XUI_PORT} 对公网暴露（应只监听 127.0.0.1）"
    fail=1
  else
    echo "  [OK] 面板端口仅监听本机 (${XUI_PORT})"
  fi

  if ss -tln 2>/dev/null | grep -qE "0\.0\.0\.0:${SUB_PORT}|\*:${SUB_PORT}|\[::\]:${SUB_PORT}"; then
    echo "  [FAIL] 订阅端口 ${SUB_PORT} 对公网暴露（应只监听 127.0.0.1）"
    fail=1
  else
    echo "  [OK] 订阅端口仅监听本机 (${SUB_PORT})"
  fi

  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://${DOMAIN}${SUB_PATH}/" 2>/dev/null || true)"
  [[ -n "${code}" && "${code}" != "000" ]] \
    && echo "  [OK] 订阅服务经 Caddy 可达 (HTTP ${code})" \
    || { echo "  [FAIL] 订阅服务不可达 (HTTP ${code:-000})"; fail=1; }

  if [[ "${MODE}" == "B" ]]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 \
            -x "https://${NAIVE_USER}:${NAIVE_PASS}@${DOMAIN}:443" \
            https://www.google.com/generate_204 2>/dev/null || true)"
    if [[ "${code}" == "204" ]]; then
      echo "  [OK] NaiveProxy 隧道实连成功 (HTTP 204)"
    else
      echo "  [FAIL] NaiveProxy 隧道不通 (HTTP ${code})"
      warn "可指定较早的配对组合重装："
      warn "  VPS_KIT_CADDY_VER=v2.11.2 VPS_KIT_NAIVE_REF=v2.11.2-naive bash install.sh"
      fail=1
    fi
  fi

  [[ "${fail}" -eq 0 ]] && log "自检全部通过 ✅" || warn "自检存在失败项，请查看上方明细。"
}

# ==========================================================
# 主流程
# ==========================================================
preflight
ask_inputs
enable_bbr

echo ">>> 开始安装（模式 B 先下载预编译 Caddy，下载不可用才本机编译）..."
install_base

if [[ "${MODE}" == "A" ]]; then
  install_xui
  install_caddy_official
  configure_xui
  configure_sub
  write_caddyfile
  create_vps_command
  systemctl enable caddy >/dev/null 2>&1
  systemctl restart caddy
  wait_for_cert || true
  setup_cert_links
else
  install_naive_core
  write_caddyfile
  create_vps_command
  systemctl enable caddy >/dev/null 2>&1
  systemctl start caddy
  wait_for_cert || true
  install_xui
  configure_xui
  configure_sub
  write_caddyfile
  systemctl reload caddy 2>/dev/null || systemctl restart caddy
  setup_cert_links
fi

self_check
/usr/bin/vps
echo "安装完成！输入 'vps' 可随时查看配置信息。"
