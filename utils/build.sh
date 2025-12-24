#!/bin/bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

echo -e "${GREEN}=============================================${PLAIN}"
echo -e "${GREEN}      开始编译 NaiveProxy 专用 Caddy         ${PLAIN}"
echo -e "${GREEN}=============================================${PLAIN}"

# 1. 检查并安装 Go 环境
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}检测到未安装 Go，正在安装最新版 Go...${PLAIN}"
    wget -q -O - https://git.io/vQhTU | bash
    source ~/.bashrc
    export PATH=$PATH:/root/go/bin
else
    echo -e "${GREEN}Go 环境已存在: $(go version)${PLAIN}"
fi

# 2. 安装 xcaddy 编译工具
echo -e "${GREEN}正在安装 xcaddy 编译工具...${PLAIN}"
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# 确保 go bin 在路径中
export PATH=$PATH:$(go env GOPATH)/bin

# 3. 开始编译 (包含 forwardproxy 模块)
echo -e "${GREEN}正在编译 Caddy (这可能需要几分钟)...${PLAIN}"
xcaddy build \
    --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive

# 4. 替换系统文件
if [ -f "./caddy" ]; then
    echo -e "${GREEN}编译成功！正在替换系统 Caddy...${PLAIN}"
    
    # 停止服务
    systemctl stop caddy
    
    # 替换文件
    mv ./caddy /usr/bin/caddy
    chmod +x /usr/bin/caddy
    
    echo -e "${GREEN}Caddy 替换完成！版本信息：${PLAIN}"
    /usr/bin/caddy version
else
    echo -e "${RED}编译失败，未找到 caddy 文件！${PLAIN}"
    exit 1
fi

# 5. 清理垃圾 (这步很重要，节省 VPS 空间)
echo -e "${GREEN}正在清理编译缓存...${PLAIN}"
go clean -modcache
rm -rf /root/go

echo -e "${GREEN}编译模块执行完毕。${PLAIN}"
