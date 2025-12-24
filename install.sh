#!/usr/bin/env bash
set -e

# ================== 前置：输入并校验域名（不回显） ==================
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

# ================== 原第一步 ==================
apt update -y
apt install -y curl wget socat vim git sqlite3

# ================== 原第二步 ==================
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
lsmod | grep bbr || true

# ================== 原第三步 ==================
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

# ================== 原第十步（自动化 vim 行为） ==================
DB_FILE="/etc/x-ui/x-ui.db"

if [[ ! -f "$DB_FILE" ]]; then
  echo "❌ 未找到 x-ui 数据库文件：$DB_FILE"
  exit 1
fi

PORT=$(sqlite3 "$DB_FILE" "select value from settings where key='port';")
WEB_PATH=$(sqlite3 "$DB_FILE" "select value from settings where key='webBasePath';")

if [[ -z "$PORT" || -z "$WEB_PATH" ]]; then
  echo "❌ 无法从 x-ui.db 读取端口或路径"
  exit 1
fi

cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    reverse_proxy :$PORT
}
EOF

# ================== 原第十一步 ==================
systemctl reload caddy

# ================== 打印结果 ==================
CADDY_STATUS=$(systemctl is-active caddy || true)
BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')

echo "=========================================="
echo "部署完成"
echo "访问地址 : https://$DOMAIN$WEB_PATH"
echo "端口     : $PORT"
echo "Caddy    : $CADDY_STATUS"
echo "BBR      : $BBR_STATUS"
echo "x-ui DB  : /etc/x-ui/x-ui.db"
echo "日志     : $INSTALL_LOG"
echo "=========================================="
