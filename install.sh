#!/bin/bash

# ==========================================
# 核心配置区
# ==========================================
GITHUB_USER="wwfemg"
REPO_NAME="vps-kit"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

clear
echo -e "${GREEN}=============================================${PLAIN}"
echo -e "${GREEN}      Debian VPS 全自动部署 (vps-kit) ${PLAIN}"
echo -e "${GREEN}=============================================${PLAIN}"

# 1. 强制收集用户输入
while [[ -z "$DOMAIN" ]]; do read -p "1. 请输入域名 (必填): " DOMAIN; done
while [[ -z "$NAIVE_USER" ]]; do read -p "2. 请设置 Naive 用户名 (必填): " NAIVE_USER; done
while [[ -z "$NAIVE_PASS" ]]; do read -p "3. 请设置 Naive 密码 (必填): " NAIVE_PASS; done
while [[ -z "$UI_PORT" ]]; do read -p "4. 请设置面板内部端口 (建议 65000): " UI_PORT; done
read -p "5. 请设置面板根路径 (必须以 / 开头，例如 /admin): " CUSTOM_PATH

# 路径处理
if [[ -z "$CUSTOM_PATH" ]]; then
    FINAL_PATH="/$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')"
else
    [[ "${CUSTOM_PATH:0:1}" != "/" ]] && FINAL_PATH="/${CUSTOM_PATH}" || FINAL_PATH="$CUSTOM_PATH"
fi

# 2. 开启 BBR & 安装 3x-ui
apt update -y && apt install -y curl wget sqlite3
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
fi

echo -e "${GREEN}正在静默安装 3x-ui...${PLAIN}"
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<< "n"

# 3. 强制对齐端口与路径 (停机操作)
systemctl stop x-ui
sleep 2
DB_FILE="/etc/x-ui/x-ui.db"
if [ -f "$DB_FILE" ]; then
    sqlite3 "$DB_FILE" "DELETE FROM settings WHERE key IN ('port', 'webBasePath');"
    sqlite3 "$DB_FILE" "INSERT INTO settings (key, value) VALUES ('port', '${UI_PORT}'), ('webBasePath', '${FINAL_PATH}');"
fi

# 4. 编译 Caddy (调用 build.sh)
wget -O /tmp/build.sh "${BASE_URL}/utils/build.sh"
chmod +x /tmp/build.sh
bash /tmp/build.sh

# 生成纯净 Caddyfile (不显式指定 TLS Email)
cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    tls {
    }
    route {
        forward_proxy {
            basic_auth ${NAIVE_USER} ${NAIVE_PASS}
            hide_ip
            hide_via
            probe_resistance
        }
        reverse_proxy localhost:${UI_PORT}
    }
}
EOF

# 5. 生成抓取型 vp 命令 (不显示 65000 端口)
cat > /usr/local/bin/vp <<EOF
#!/bin/bash
USER=\$(sqlite3 /etc/x-ui/x-ui.db "SELECT username FROM users LIMIT 1;")
PASS=\$(sqlite3 /etc/x-ui/x-ui.db "SELECT password FROM users LIMIT 1;")
echo -e "\033[32m================================================================\033[0m"
echo -e "                 VPS 配置信息查询 (vp)             "
echo -e "\033[32m================================================================\033[0m"
echo -e "\033[32m[1] 3x-ui 面板地址:\033[0m https://${DOMAIN}${FINAL_PATH}"
echo -e "\033[32m    面板登录账号:\033[0m \$USER"
echo -e "\033[32m    面板登录密码:\033[0m \$PASS"
echo -e ""
echo -e "\033[33m[2] NaiveProxy 节点参数:\033[0m"
echo -e "    域名: ${DOMAIN} | 端口: 443"
echo -e "    用户: ${NAIVE_USER} | 密码: ${NAIVE_PASS}"
echo -e "\033[32m================================================================\033[0m"
EOF
chmod +x /usr/local/bin/vp

systemctl daemon-reload
systemctl enable x-ui && systemctl start x-ui
systemctl restart caddy
vp
