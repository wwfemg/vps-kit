#!/bin/bash

# 定義顏色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

echo -e "${GREEN}=============================================${PLAIN}"
echo -e "${GREEN}      開始編譯 NaiveProxy 專用 Caddy         ${PLAIN}"
echo -e "${GREEN}=============================================${PLAIN}"

# 1. 檢查並安裝 Go 環境
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}檢測到未安裝 Go，正在安裝最新版 Go...${PLAIN}"
    wget -q -O - https://git.io/vQhTU | bash
    source ~/.bashrc
    export PATH=$PATH:/root/go/bin
else
    echo -e "${GREEN}Go 環境已存在: $(go version)${PLAIN}"
fi

# 2. 安裝 xcaddy 編譯工具
echo -e "${GREEN}正在安裝 xcaddy 編譯工具...${PLAIN}"
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# 確保 go bin 在路徑中
export PATH=$PATH:$(go env GOPATH)/bin

# 3. 開始編譯 (包含 forwardproxy 模塊)
echo -e "${GREEN}正在編譯 Caddy (這可能需要幾分鐘)...${PLAIN}"
xcaddy build \
    --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive

# 4. 替換系統文件
if [ -f "./caddy" ]; then
    echo -e "${GREEN}編譯成功！正在替換系統 Caddy...${PLAIN}"
    
    # 停止服務
    systemctl stop caddy
    
    # 替換文件
    mv ./caddy /usr/bin/caddy
    chmod +x /usr/bin/caddy
    
    echo -e "${GREEN}Caddy 替換完成！版本信息：${PLAIN}"
    /usr/bin/caddy version
else
    echo -e "${RED}編譯失敗，未找到 caddy 文件！${PLAIN}"
    exit 1
fi

# 5. 清理垃圾
echo -e "${GREEN}正在清理編譯緩存...${PLAIN}"
go clean -modcache
rm -rf /root/go

echo -e "${GREEN}編譯模塊執行完畢。${PLAIN}"
