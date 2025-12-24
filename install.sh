#!/usr/bin/env bash
set -e

# ================== 0. 强制输入并校验域名 ==================
read -rp "请输入【已解析】的域名（例如 jp.idns.top）: " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "❌ 未输入域名，退出"
  exit 1
fi

if ! getent hosts "$DOMAIN" >/dev/null 2>&1; then
  echo "❌ 域名未解析或 DNS 尚未生效：$DOMAIN"
  exit 1
fi

echo "✅ 域名校验通过：$DOMAIN"

# ================== 1. 极简依赖 ==================
apt update -y
apt install -y \
  curl \
  ca-certificates \
  gnupg \
  lsb-release

# ================== 2. 安装 3x-ui（自动回车，默认配置） ==================
INSTALL_LOG="/tmp/3x-ui-install.log"
echo "🚀 开始安装 3x-ui（自动回车，全部默认）..."

yes "" | bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) \
  | tee "$INSTALL_LOG"

echo "✅ 3x-ui 安装完成"

# ================== 3. 解析 3x-ui 官方输出 ==================
PORT=$(grep -Eo 'Port[: ]+[0-9]+' "$INSTALL_LOG" | awk '{print $NF}' | tail -1)
WEB_PATH=$(grep -Eo 'Path[: ]+/[^ ]+' "$INSTALL_LOG" | awk '{print $NF}' | tail -1)
USERNAME=$(grep -Eo 'Username[: ]+[^ ]+' "$INSTALL_LOG" | awk '{print $NF}' | tail -1)
PASSWORD=$(grep -Eo 'Password[: ]+[^ ]+' "$INSTALL_LOG" | awk '{print $NF}' | tail -1)

if [[ -z "$PORT" || -z "$WEB_PATH" ]]; then
  echo "❌ 无法从官方输出中解析端口或路径"
  exit 1
fi

# ================== 4. 安装 Caddy（官方源） ==================
apt install -y debian-keyring debian-archive-keyring apt-transport-https

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list

apt update -y
apt install -y caddy

# ================== 5. 写入 Caddyfile ==================
cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    reverse_proxy :$PORT
}
EOF

# ================== 6. 启动 Caddy ==================
systemctl reload caddy

# ================== 7. 输出最终结果 ==================
echo "=========================================="
echo "🎉 3x-ui + Caddy 部署完成"
echo "------------------------------------------"
echo "访问地址: https://$DOMAIN$WEB_PATH"
echo "用户名  : $USERNAME"
echo "密  码  : $PASSWORD"
echo "------------------------------------------"
echo "3x-ui 端口: $PORT"
echo "日志文件 : $INSTALL_LOG"
echo "=========================================="
