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
# 1. 强制收集用户输入 (严禁留空)
# ==========================================

# --- 1. 域名 (死循环检查) ---
while [[ -z "$DOMAIN" ]]; do
    read -p "1. 请输入你的域名 (必填，例如 example.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        echo -e "${RED}错误：域名不能为空！请重新输入。${PLAIN}"
    fi
done

# --- 2. Naive 用户名 ---
while [[ -z "$NAIVE_USER" ]]; do
    read -p "2. 请设置 NaiveProxy 用户名 (必填): " NAIVE_USER
    if [[ -z "$NAIVE_USER" ]]; then
        echo -e "${RED}错误：用户名不能为空！${PLAIN}"
    fi
done

# --- 3. Naive 密码 ---
while [[ -z "$NAIVE_PASS" ]]; do
    read -p "3. 请设置 NaiveProxy 密码 (必填): " NAIVE_PASS
    if [[ -z "$NAIVE_PASS" ]]; then
        echo -e "${RED}错误：密码不能为空！${PLAIN}"
    fi
done

# --- 4. 3x-ui 面板端口 ---
while [[ -z "$UI_PORT" ]]; do
    read -p "4. 请设置 3x-ui 面板端口 (必填，建议 10000-65000): " UI_PORT
    if [[ -z "$UI_PORT" ]]; then
        echo -e "${RED}错误：端口不能为空！${PLAIN}"
    fi
done

# --- 邮箱自动生成 (这个可以偷懒，不影响登录) ---
EMAIL="admin@${DOMAIN}"

echo -e "${YELLOW}======================================${PLAIN}"
echo -e "请核对信息："
echo -e "域名: ${GREEN}${DOMAIN}${PLAIN}"
echo -e "用户: ${GREEN}${NAIVE_USER}${PLAIN}"
echo -e "密码: ${GREEN}${NAIVE_PASS}${PLAIN}"
echo -e "端口: ${GREEN}${UI_PORT}${PLAIN}"
echo -e "${YELLOW}======================================${PLAIN}"
echo -e "${YELLOW}即将开始安装，请勿关闭窗口...${PLAIN}"
sleep 3

# ==========================================
# 2. 系统初始化 & BBR
# ==========================================
echo -e "${GREEN}[1/7] 系统初始化 & 开启 BBR...${PLAIN}"
apt update -y && apt install -y curl wget socat vim git sqlite3
# 开启 BBR
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
fi

# ==========================================
# 3. 安装 3x-ui
# ==========================================
echo -e "${GREEN}[2/7] 安装 3x-ui 面板...${PLAIN}"
# 使用非交互模式安装 x-ui，传入刚才强制收集的变量
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<EOF
y
${NAIVE_USER}
${NAIVE_PASS}
${UI_PORT}
EOF
# 注意：这里为了方便记忆，直接把 3x-ui 的账号密码设置成和 Naive 一样

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
echo -e "${GREEN}[4/7] 正在调用编译模块 (耗时较长)...${PLAIN}"
wget -O /tmp/build.sh "${BASE_URL}/utils/build.sh"
chmod +x /tmp/build.sh
bash /tmp/build.sh

# ==========================================
# 6. 下载配置并替换变量
# ==========================================
echo -e "${GREEN}[5/7] 正在应用配置...${PLAIN}"
wget -O /etc/caddy/Caddyfile "${BASE_URL}/configs/Caddyfile"

# 使用 sed 批量替换 Caddyfile 占位符
sed -i "s/MY_DOMAIN/${DOMAIN}/g" /etc/caddy/Caddyfile
sed -i "s/MY_EMAIL/${EMAIL}/g" /etc/caddy/Caddyfile
sed -i "s/NAIVE_USER/${NAIVE_USER}/g" /etc/caddy/Caddyfile
sed -i "s/NAIVE_PASS/${NAIVE_PASS}/g" /etc/caddy/Caddyfile
sed -i "s/UI_PORT/${UI_PORT}/g" /etc/caddy/Caddyfile

# 重启 Caddy
systemctl restart caddy

# ==========================================
# 7. 安装查询工具 vpsinfo
# ==========================================
echo -e "${GREEN}[6/7] 安装快捷查询命令 'vpsinfo'...${PLAIN}"
wget -O /usr/local/bin/vpsinfo "${BASE_URL}/utils/info.sh"
chmod +x /usr/local/bin/vpsinfo

# ==========================================
# 结束 & 展示信息
# ==========================================
echo -e "${GREEN}[7/7] 安装完成！正在抓取信息...${PLAIN}"
sleep 2
vpsinfo
