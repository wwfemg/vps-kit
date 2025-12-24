#!/bin/bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

echo -e "${GREEN}[build.sh] 正在启动编译模块...${PLAIN}"

# 1. 智能判断架构 (x86 还是 ARM)
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "amd64" ]; then
    GO_ARCH="linux-amd64"
elif [ "$ARCH" = "arm64" ]; then
    GO_ARCH="linux-arm64"
else
    echo -e "${RED}错误：不支持的系统架构: $ARCH${PLAIN}"
    exit 1
fi

# 2. 检查是否需要安装 Go (防重复安装)
# 只有当 go 命令不存在，或者 go 版本太老时才重装
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}未检测到 Go 环境，正在准备安装...${PLAIN}"
    
    # 自动获取最新版本号
    GO_LATEST=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
    if [ -z "$GO_LATEST" ]; then
        GO_LATEST="go1.22.5" # 备用默认值
    fi
    
    echo -e "下载 Go 版本: ${GO_LATEST}.${GO_ARCH}"
    
    rm -rf /usr/local/go
    wget -q "https://go.dev/dl/${GO_LATEST}.${GO_ARCH}.tar.gz"
    tar -C /usr/local -xzf "${GO_LATEST}.${GO_ARCH}.tar.gz"
    rm -f "${GO_LATEST}.${GO_ARCH}.tar.gz"
    
    # 设置环境变量
    export PATH=$PATH:/usr/local/go/bin
else
    echo -e "${GREEN}检测到 Go 环境已存在，跳过安装。${PLAIN}"
fi

# 确保环境变量生效
export PATH=$PATH:/usr/local/go/bin

# 3. 检查并添加虚拟内存 (防止小内存机器编译卡死)
# 如果内存少于 1GB，就加 1GB 的 Swap
MEM_AVAIL=$(free -m | grep Mem | awk '{print $2}')
if [ "$MEM_AVAIL" -lt 1000 ]; then
    echo -e "${YELLOW}检测到内存较小 (${MEM_AVAIL}MB)，正在添加临时虚拟内存...${PLAIN}"
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    IS_SWAP_ADDED=true
fi

# 4. 安装编译工具 xcaddy
echo -e "${GREEN}正在安装 xcaddy 编译工具...${PLAIN}"
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# 5. 开始编译 (带 NaiveProxy 插件)
echo -e "${GREEN}正在编译 Caddy (这可能需要几分钟)...${PLAIN}"
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive

# 6. 替换系统文件
if [ -f "./caddy" ]; then
    echo -e "${GREEN}编译成功！正在替换系统文件...${PLAIN}"
    rm -f /usr/bin/caddy
    mv ./caddy /usr/bin/caddy
    chmod +x /usr/bin/caddy
else
    echo -e "${RED}编译失败！未找到 caddy 文件。${PLAIN}"
    # 如果失败，清理 swap
    if [ "$IS_SWAP_ADDED" = "true" ]; then
        swapoff /swapfile
        rm /swapfile
    fi
    exit 1
fi

# 7. 清理工作
# 删掉临时 Swap
if [ "$IS_SWAP_ADDED" = "true" ]; then
    echo -e "${YELLOW}清理临时虚拟内存...${PLAIN}"
    swapoff /swapfile
    rm /swapfile
fi

echo -e "${GREEN}[build.sh] 编译模块执行完毕！${PLAIN}"
