#!/usr/bin/env bash
set -e

# ================== 前置：输入并校验域名（不影响原步骤） ==================
read -rsp "请输入【已解析】的域名: " DOMAIN
echo

if [[ -z "$DOMAIN" ]]; then
  echo "❌ 未输入域名，退出"
  exit 1
fi

if ! getent hosts "$DOMAIN" >/dev/null 2>&1; then
  echo "❌ 域名未解析或 DNS 尚未生效"
  exit 1
fi

echo "✅ 域名校验通过"

# ================== 原第一步 ==================
apt update -y
apt install -y curl wget socat vim git

# ================== 原第二步 ==================
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
lsmod | grep bbr || true

# ================== 原第三步 ==================
# 原行为：你手动一路回车
# 现在：系统自动回车，等价于你人工默认
INSTALL_LOG="/tmp/3x-ui-install.log"
yes "" | bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) \
  | tee "$INSTALL_LOG"

# ================== 原第四步 ==================
apt update -y

# ================== 原第五步 ==================
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl

# ================== 原第六步 ==================
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

# ================== 原第七步 ==================
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list

# ================== 原第八步 ==================
apt update -y

# ================== 原第九步 ==================
apt install -y caddy

# ================== 原第十步 ==================
# 原行为：cd /etc/caddy + vim Caddyfile
# 这里保持逻辑一致，用程序写文件
CONFIG_FILE="/etc/x-ui/config.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "❌ 未找到 3x-ui 配置文件：$CONFIG_FILE"
  exit 1
fi

PORT=$(grep -o '"port":[ ]*[0-9]\+' "$CONFIG_FILE" | grep -o '[0-9]\+')
WEB_PATH=$(grep -o '"webBasePath":[ ]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)

if [[ -z "$PORT" || -z "$WEB_PATH" ]]; then
  echo "❌ 无法读取 3x-ui 端口或路径"
  exit 1
fi

cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    reverse_proxy :$PORT
}
EOF

# ================== 原第十一步 ==================
systemctl reload caddy

# ================== 结果输出（不影响原步骤） ==================
echo "=========================================="
echo "🎉 全部步骤已完成（未删减任何一步）"
echo "------------------------------------------"
echo "访问地址: https://$DOMAIN$WEB_PATH"
echo "3x-ui 端口: $PORT"
echo "------------------------------------------"
echo "3x-ui 安装日志: $INSTALL_LOG"
echo "=========================================="

# ================== 最终状态打印（真实、不误导） ==================

CADDY_STATUS=$(systemctl is-active caddy || true)
BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')

echo
echo "============= 部署完成状态 ============="
echo "面板地址       : https://$DOMAIN$WEB_PATH"
echo "3x-ui 端口     : $PORT"
echo "----------------------------------------"
echo "Caddy 状态     : $CADDY_STATUS"
echo "BBR 拥塞控制   : $BBR_STATUS"
echo "----------------------------------------"
echo "x-ui 数据库    : /etc/x-ui/x-ui.db"
echo "Caddy 配置     : /etc/caddy/Caddyfile"
echo "安装日志       : $INSTALL_LOG"
echo "========================================"
