#!/bin/bash

# 1. 收集域名
read -p "请输入域名 (例如 jp.idns.top): " DOMAIN

# 2. 安装基础工具和官方 Caddy
apt update && apt install -y curl debian-keyring debian-archive-keyring apt-transport-https sqlite3
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install caddy -y

# 3. 安装 3x-ui (原汁原味)
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<< "n"

# 4. 抓取 3x-ui 实时生成的端口和路径
systemctl stop x-ui
REAL_PORT=$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='port';")
REAL_PATH=$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='webBasePath';")
systemctl start x-ui

# 5. 配置 Caddy 转发
cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    reverse_proxy localhost:$REAL_PORT
}
EOF

systemctl restart caddy

# 6. 自动生成 vp 查询工具
cat > /usr/local/bin/vp <<EOF
#!/bin/bash
DB="/etc/x-ui/x-ui.db"
U=\$(sqlite3 \$DB "SELECT username FROM users LIMIT 1;")
P=\$(sqlite3 \$DB "SELECT password FROM users LIMIT 1;")
W_PATH=\$(sqlite3 \$DB "SELECT value FROM settings WHERE key='webBasePath';")
echo "=========================================="
echo "      3x-ui 面板访问信息"
echo "=========================================="
echo "访问地址: https://${DOMAIN}\$W_PATH"
echo "用户名  : \$U"
echo "密  码  : \$P"
echo "=========================================="
EOF

# 这里就是自动赋予权限的代码，你不用手动操作
chmod +x /usr/local/bin/vp

# 安装完直接显示一次
vp
