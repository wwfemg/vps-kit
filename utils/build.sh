#!/bin/bash
# 1. 安装 xcaddy (官方推荐的插件编译器)
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
export PATH=$PATH:$(go env GOPATH)/bin

# 2. 关键：必须带上这个特定的 naive 分支插件进行编译
echo "开始编译 NaiveProxy 专用 Caddy..."
xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive

# 3. 替换系统文件
if [ -f "./caddy" ]; then
    chmod +x ./caddy
    mv ./caddy /usr/bin/caddy
    echo "Caddy 编译并替换成功！"
else
    echo "错误：编译失败，请检查服务器内存是否足够(建议1G以上)"
    exit 1
fi
