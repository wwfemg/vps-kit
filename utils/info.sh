#!/bin/bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 1. 获取公网 IP
PUBLIC_IP=$(curl -s ipv4.icanhazip.com)

# 2. 从 Caddyfile 读取 Naive 配置
# 我们假设 Caddyfile 在 /etc/caddy/Caddyfile
if [ -f "/etc/caddy/Caddyfile" ]; then
    DOMAIN=$(grep "{" /etc/caddy/Caddyfile | head -n 1 | awk '{print $1}')
    NAIVE_USER=$(grep "basic_auth" /etc/caddy/Caddyfile | awk '{print $2}')
    NAIVE_PASS=$(grep "basic_auth" /etc/caddy/Caddyfile | awk '{print $3}')
else
    DOMAIN="未知 (Caddyfile 未找到)"
fi

# 3. 从 3x-ui 数据库读取实时信息
DB_FILE="/etc/x-ui/x-ui.db"
if ! command -v sqlite3 &> /dev/null; then
    UI_INFO="${RED}错误：未检测到 sqlite3，无法读取面板信息${PLAIN}"
    UI_USER="未知"
    UI_PASS="未知"
    UI_PORT="未知"
elif [ ! -f "$DB_FILE" ]; then
    UI_INFO="${RED}错误：未找到 3x-ui 数据库文件${PLAIN}"
else
    UI_PORT=$(sqlite3 $DB_FILE "select value from settings where key='port';")
    UI_BASE=$(sqlite3 $DB_FILE "select value from settings where key='webBasePath';")
    UI_USER=$(sqlite3 $DB_FILE "select value from settings where key='username';")
    UI_PASS=$(sqlite3 $DB_FILE "select value from settings where key='password';")
    
    # 修正路径显示 (如果没有设置路径，默认为空，我们加个 /)
    if [ -z "$UI_BASE" ]; then UI_BASE="/"; fi
    UI_INFO="https://${DOMAIN}${UI_BASE}"
fi

# 4. 定位证书路径
CERT_DIR="/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}"

# === 打印输出 ===
clear
echo -e "${GREEN}=============================================${PLAIN}"
echo -e "${GREEN}          VPS 配置信息查询 (vps-kit)${PLAIN}"
echo -e "${GREEN}=============================================${PLAIN}"

echo -e "${YELLOW}[1] 3x-ui 面板信息 (实时读取数据库)${PLAIN}"
echo -e "    面板地址 : ${UI_INFO}"
echo -e "    登录用户 : ${GREEN}${UI_USER}${PLAIN}"
echo -e "    登录密码 : ${GREEN}${UI_PASS}${PLAIN}"
echo -e "    面板端口 : ${UI_PORT}"

echo -e "\n${YELLOW}[2] NaiveProxy 配置 (读取 Caddyfile)${PLAIN}"
echo -e "    服务器地址 : ${DOMAIN}"
echo -e "    端口       : 443"
echo -e "    用户名     : ${GREEN}${NAIVE_USER}${PLAIN}"
echo -e "    密码       : ${GREEN}${NAIVE_PASS}${PLAIN}"
echo -e "    客户端链接 : https://${NAIVE_USER}:${NAIVE_PASS}@${DOMAIN}"

echo -e "\n${YELLOW}[3] 证书文件路径 (Caddy)${PLAIN}"
if [ -f "${CERT_DIR}/${DOMAIN}.crt" ]; then
    echo -e "    公钥 (crt) : ${CERT_DIR}/${DOMAIN}.crt"
    echo -e "    私钥 (key) : ${CERT_DIR}/${DOMAIN}.key"
else
    echo -e "    ${RED}证书未找到，可能正在申请中或路径有变。${PLAIN}"
fi
echo -e "${GREEN}=============================================${PLAIN}"
