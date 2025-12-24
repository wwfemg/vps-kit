#!/bin/bash

# ==========================================
# 核心配置区
# ==========================================
GITHUB_USER="wwfemg"
REPO_NAME="vps-kit"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}"

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

clear
echo -e "${GREEN}=============================================${PLAIN}"
echo -e "${GREEN}      Debian VPS 全自动部署 (vps-kit) ${PLAIN}"
echo -e "${GREEN}   集成: NaiveProxy + 3x-ui + Caddy + BBR ${PLAIN}"
echo -e "${GREEN}=============================================${PLAIN}"

# ==========================================
# 1. 强制收集用户输入
# ==========================================

# 1.1 域名
while [[ -z "$DOMAIN" ]]; do
    read -p "1. 请输入你的域名 (必填): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then echo -e "${RED}域名不能为空！${PLAIN}"; fi
done

# 1.2 Naive 用户名
while [[ -z "$NAIVE_USER" ]]; do
    read -p "2. 请设置 NaiveProxy 用户名 (必填): " NAIVE_USER
    if [[ -z "$NAIVE_USER" ]]; then echo -e "${RED}用户名不能为空！${PLAIN}"; fi
done

# 1.3 Naive 密码
while [[ -z "$NAIVE_PASS" ]]; do
    read -p "3. 请设置 NaiveProxy 密码 (必填): " NAIVE_PASS
    if [[ -z "$NAIVE_PASS" ]]; then echo -e "${RED}密码不能为空！${PLAIN}"; fi
done

# 1.4 面板端口
while [[ -z "$UI_PORT" ]]; do
    read -p "4. 请设置 3x-ui 面板端口 (必填，建议 10000-65000): " UI_PORT
    if [[ -z "$UI_PORT" ]]; then echo -e "${RED}端口不能为空！${PLAIN}"; fi
done

# 1.5 面板安全路径
echo -e "5. 请设置 3x-ui 面板的根路径 (必须以 / 开头，例如 /admin)"
read -p "   若直接回车(留空)，脚本将自动生成一个随机安全路径: " CUSTOM_PATH

# 路径处理
if [[ -z "$CUSTOM_PATH" ]]; then
    FINAL_PATH="/$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9')"
    echo -e "${YELLOW}   用户未输入，已自动生成路径: ${FINAL_PATH}${PLAIN}"
else
    if [[ "${CUSTOM_PATH:0:1}" != "/" ]]; then
        FINAL_PATH="/${CUSTOM_PATH}"
    else
        FINAL_PATH="$CUSTOM_PATH"
    fi
    echo -e "${GREEN}   使用用户自定义路径: ${FINAL_PATH}${PLAIN}"
fi

EMAIL="admin@${DOMAIN}"
echo -e "${YELLOW}配置收集完毕，即将开始安装...${PLAIN}"
sleep 2

# ==========================================
# 2. 系统初始化 & BBR
# ==========================================
echo -e "${GREEN}[1/7] 系统初始化 & 开启 BBR...${PLAIN}"
apt update -y && apt install -y curl wget socat vim git sqlite3
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
fi

# ==========================================
# 3. 安装 3x-ui (已修复：自动跳过交互弹窗)
# ==========================================
echo -e "${GREEN}[2/7] 安装 3x-ui 面板...${PLAIN}"

# 关键修改：<<< "n" 表示自动回答 "no"，跳过官方脚本的设置向导
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<< "n"

echo -e "${YELLOW}正在注入数据库配置...${PLAIN}"
systemctl stop x-ui
sleep 2

DB_FILE="/etc/x-ui/x-ui.db"
if [ -f "$DB_FILE" ]; then
    # 3.1 注入端口
    sqlite3 "$DB_FILE" "DELETE FROM settings WHERE key='port';"
    sqlite3 "$DB_FILE" "INSERT INTO settings (key, value) VALUES ('port', '${UI_PORT}');"

    # 3.2 注入路径
    sqlite3 "$DB_FILE" "DELETE FROM settings WHERE key='webBasePath';"
    sqlite3 "$DB_FILE" "INSERT INTO settings (key, value) VALUES ('webBasePath', '${FINAL_PATH}');"

    # 3.3 修正账号密码
    sqlite3 "$DB_FILE" "UPDATE users SET username='${NAIVE_USER}', password='${NAIVE_PASS}' WHERE id=1;"
    sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO users (id, username, password) VALUES (1, '${NAIVE_USER}', '${NAIVE_PASS}');"
else
    echo -e "${RED}严重错误：数据库未找到，面板配置可能失败！${PLAIN}"
fi

# ==========================================
# 4. 安装官方 Caddy
# ==========================================
echo -e "${GREEN}[3/7] 安装 Caddy 基础环境...${PLAIN}"
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install caddy -y
systemctl stop caddy

# ==========================================
# 5. 调用编译脚本
# ==========================================
echo -e "${GREEN}[4/7] 正在调用编译模块...${PLAIN}"
wget -O /tmp/build.sh "${BASE_URL}/utils/build.sh"
chmod +x /tmp/build.sh
bash /tmp/build.sh

# ==========================================
# 6. 生成 Caddy 配置文件
# ==========================================
echo -e "${GREEN}[5/7] 正在写入 Caddy 配置...${PLAIN}"
cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    tls ${EMAIL}
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

# ==========================================
# 7. 生成 vp 查询工具 (已修复：隐藏端口，合并显示)
# ==========================================
echo -e "${GREEN}[6/7] 生成快捷命令 'vp'...${PLAIN}"
cat > /usr/local/bin/vp <<EOF
#!/bin/bash
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

show_config_info() {
    domain="${DOMAIN}"
    
    # 从数据库读取真实配置
    xui_path=\$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='webBasePath'")
    
    # 路径格式化
    if [[ -z "\$xui_path" || "\$xui_path" == "/" ]]; then
        xui_path_str=""
    else
        [[ "\${xui_path:0:1}" != "/" ]] && xui_path="/\$xui_path"
        xui_path_str="\$xui_path"
    fi

    xui_user=\$(sqlite3 /etc/x-ui/x-ui.db "SELECT username FROM users LIMIT 1")
    xui_pass=\$(sqlite3 /etc/x-ui/x-ui.db "SELECT password FROM users LIMIT 1")

    # 证书检测
    cert_path="/root/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.crt"
    if [[ ! -f "\$cert_path" ]]; then
         cert_status="\${RED}申请中...\${PLAIN}"
    else
         cert_status="\${GREEN}正常\${PLAIN}"
    fi

    echo -e "================================================================"
    echo -e "                 VPS 配置信息查询 (vp)             "
    echo -e "================================================================"
    
    echo -e "\${GREEN}[1] 3x-ui 面板 (Panel)\${PLAIN}"
    # 修改点：只显示域名+路径 (隐藏 65000 端口)
    echo -e "    登录地址 : \${GREEN}https://\${domain}\${xui_path_str}\${PLAIN}"
    # 修改点：账号密码合并一行，方便复制
    echo -e "    账号密码 : \${GREEN}\${xui_user}\${PLAIN} / \${GREEN}\${xui_pass}\${PLAIN}"
    echo -e ""

    echo -e "\${YELLOW}[2] NaiveProxy 节点 (Node)\${PLAIN}"
    echo -e "    Host(域名) : \${domain}"
    echo -e "    Port(端口) : 443"
    echo -e "    Auth(认证) : \${GREEN}\${xui_user}\${PLAIN} : \${GREEN}\${xui_pass}\${PLAIN}"
    echo -e "================================================================"
}
show_config_info
EOF

chmod +x /usr/local/bin/vp

# ==========================================
# 结束：启动服务
# ==========================================
echo -e "${GREEN}[7/7] 正在启动所有服务...${PLAIN}"
systemctl daemon-reload
systemctl enable x-ui
systemctl start x-ui
systemctl restart caddy

echo -e "${GREEN}安装全部完成！${PLAIN}"
sleep 1
vp
