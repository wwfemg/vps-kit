#!/bin/bash

# ==========================================
# 核心配置区 (如果你的 GitHub 用户名变了，请改这里)
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

# 1. 收集用户输入
read -p "请输入你的域名 (例如: example.com): " DOMAIN
read -p "请输入 NaiveProxy 用户名: " NAIVE_USER
read -p "请输入 NaiveProxy 密码: " NAIVE_PASS
read -p "请输入 3x-ui 面板的端口 (记住这个数字!): " UI_PORT
read -p "请输入你的邮箱 (用于申请证书): " EMAIL

echo -e "${YELLOW}正在开始安装... 请喝杯咖啡等待...${PLAIN}"
sleep 2

# 2. 系统初始化 & BBR
echo -e "${GREEN}[1/7] 系统初始化 & 开启 BBR...${PLAIN}"
apt update -y && apt install -y curl wget socat vim git sqlite3
# 开启 BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p > /dev/null 2>&1

# 3. 安装 3x-ui
echo -e "${GREEN}[2/7] 安装 3x-ui 面板...${PLAIN}"
echo -e "${RED}>>> 请务必在接下来的设置中，将端口设置为: ${UI_PORT} <<<${PLAIN}"
sleep 3
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# 4. 安装官方 Caddy (获取服务文件)
echo -e "${GREEN}[3/7] 安装 Caddy 基础环境...${PLAIN}"
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install caddy -y
systemctl stop caddy

# 5. 调用编译脚本 (从 GitHub 下载你的 build.sh)
echo -e "${GREEN}[4/7] 正在调用编译模块...${PLAIN}"
wget -O /tmp/build.sh "${BASE_URL}/utils/build.sh"
chmod +x /tmp/build.sh
bash /tmp/build.sh

# 6. 下载配置并替换变量 (从 GitHub 下载你的 Caddyfile)
echo -e "${GREEN}[5/7] 正在应用配置...${PLAIN}"
wget -O /etc/caddy/Caddyfile "${BASE_URL}/configs/Caddyfile"

# 使用 sed 批量替换占位符
sed -i "s/MY_DOMAIN/${DOMAIN}/g" /etc/caddy/Caddyfile
sed -i "s/MY_EMAIL/${EMAIL}/g" /etc/caddy/Caddyfile
sed -i "s/NAIVE_USER/${NAIVE_USER}/g" /etc/caddy/Caddyfile
sed -i "s/NAIVE_PASS/${NAIVE_PASS}/g" /etc/caddy/Caddyfile
sed -i "s/UI_PORT/${UI_PORT}/g" /etc/caddy/Caddyfile

# 重启 Caddy
systemctl restart caddy

# 7. 安装查询工具 vpsinfo (从 GitHub 下载你的 info.sh)
echo -e "${GREEN}[6/7] 安装快捷查询命令 'vpsinfo'...${PLAIN}"
wget -O /usr/local/bin/vpsinfo "${BASE_URL}/utils/info.sh"
chmod +x /usr/local/bin/vpsinfo

# ==========================================
# 结束 & 展示信息
# ==========================================
echo -e "${GREEN}[7/7] 安装完成！正在抓取信息...${PLAIN}"
sleep 2
# 直接调用刚才安装好的 vpsinfo 显示结果
vpsinfo
