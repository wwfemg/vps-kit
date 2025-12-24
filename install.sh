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

# 1. 收集必要输入
while [[ -z "$DOMAIN" ]]; do read -p "1. 请输入域名 (必填): " DOMAIN; done
while [[ -z "$UI_PORT" ]]; do read -p "2. 请设置面板内部端口 (例如 65000): " UI_PORT; done
while [[ -z "$CUSTOM_PATH" ]]; do read -p "3. 请设置根路径 (必须以 / 开头，例如 /okokjpen): " CUSTOM_PATH; done

# 2. 静默安装 3x-ui
echo -e "${GREEN}[1/4] 正在静默安装 3x-ui...${PLAIN}"
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<< "n"

# 3. 关键手术：只改端口和路径，不碰账号密码
echo -e "${YELLOW}[2/4] 正在对齐端口与根路径...${PLAIN}"
systemctl stop x-ui
sleep 2

DB_FILE="/etc/x-ui/x-ui.db"
if [ -f "$DB_FILE" ]; then
    # 只删除并重新插入端口和根路径
    sqlite3 "$DB_FILE" "DELETE FROM settings WHERE key IN ('port', 'webBasePath');"
    sqlite3 "$DB_FILE" "INSERT INTO settings (key, value) VALUES ('port', '${UI_PORT}'), ('webBasePath', '${CUSTOM_PATH}');"
fi

# 4. 编译 Caddy 并生成配置 (引用 build.sh)
echo -e "${GREEN}[3/4] 正在准备 Caddy 环境...${PLAIN}"
wget -O /tmp/build.sh "${BASE_URL}/utils/build.sh"
chmod +x /tmp/build.sh
bash /tmp/build.sh

# 生成 Caddyfile (NaiveProxy 的账号密码在 Caddy 层设定，面板账号在 3x-ui 层)
# 为了方便，NaiveProxy 的认证我们沿用你输入的域名相关信息，或者你可以之后手动改
cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    tls admin@${DOMAIN}
    route {
        forward_proxy {
            basic_auth user pass123456
            hide_ip
            hide_via
            probe_resistance
        }
        reverse_proxy localhost:${UI_PORT}
    }
}
EOF

# 5. 生成“抓取型” vp 工具
cat > /usr/local/bin/vp <<EOF
#!/bin/bash
# 实时从数据库抓取 3x-ui 自动生成的账号密码
USER=\$(sqlite3 /etc/x-ui/x-ui.db "SELECT username FROM users LIMIT 1;")
PASS=\$(sqlite3 /etc/x-ui/x-ui.db "SELECT password FROM users LIMIT 1;")

echo -e "\033[32m================================================================"
echo -e "                 VPS 配置信息查询 (vp)             "
echo -e "================================================================\033[0m"
echo -e "\033[32m[1] 3x-ui 面板地址:\033[0m https://${DOMAIN}${CUSTOM_PATH}"
echo -e "\033[32m    面板登录账号:\033[0m \$USER"
echo -e "\033[32m    面板登录密码:\033[0m \$PASS"
echo -e ""
echo -e "\033[33m[2] NaiveProxy 节点信息:\033[0m"
echo -e "    服务器: ${DOMAIN} | 端口: 443"
echo -e "    Naive 认证: user / pass123456 (在 Caddyfile 中修改)"
echo -e "\033[32m================================================================\033[0m"
EOF
chmod +x /usr/local/bin/vp

systemctl daemon-reload
systemctl enable x-ui && systemctl start x-ui
systemctl restart caddy
vp
