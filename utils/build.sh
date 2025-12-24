#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 1. 检查并安装 Go
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}正在安装 Go 环境...${PLAIN}"
    wget -q -O - https://git.io/vQhTU | bash
    source ~/.bashrc
    export PATH=$PATH:/root/go/bin
fi

# 2. 安装 xcaddy
echo -e "${GREEN}安装 xcaddy 编译工具...${PLAIN}"
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
export PATH=$PATH:$(go env GOPATH)/bin

# 3. 核心编译动作 (必须带上 @naive 插件)
echo -e "${GREEN}正在编译 NaiveProxy 专用 Caddy (耗时约 3-5 分钟)...${PLAIN}"
xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive

# 4. 替换并清理
if [ -f "./caddy" ]; then
    systemctl stop caddy
    mv ./caddy /usr/bin/caddy
    chmod +x /usr/bin/caddy
    
    # 清理 Go 缓存，节省磁盘空间
    echo -e "${GREEN}编译成功，正在清理缓存...${PLAIN}"
    go clean -modcache
    rm -rf /root/go
else
    echo -e "${RED}编译失败，请检查服务器内存！${PLAIN}"
    exit 1
fi
