#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Final output (ONLY after install + configure)
# ==================================================

echo
echo "=================================================="
echo "✅ 安装完成 / Installation Complete"
echo "=================================================="
echo

# --------------------------------------------------
# Basic info
# --------------------------------------------------
echo "📌 域名 / Domain:"
echo "  ${INSTALL_DOMAIN}"
echo

echo "📌 安装模式 / Install Mode:"
if [[ "$INSTALL_MODE" == "stage1" ]]; then
  echo "  1) 3x-ui + Caddy (HTTPS only)"
elif [[ "$INSTALL_MODE" == "stage2" ]]; then
  echo "  2) 3x-ui + Caddy + NaiveProxy"
fi
echo

# --------------------------------------------------
# 3x-ui panel info
# --------------------------------------------------
echo "🧩 3x-ui 面板信息 / 3x-ui Panel"
echo "  面板地址 / Panel URL:"
echo "    https://${INSTALL_DOMAIN}"
echo
echo "  用户名 / Username:"
echo "    ${XUI_USER}"
echo
echo "  密码 / Password:"
echo "    ${XUI_PASS}"
echo

# --------------------------------------------------
# NaiveProxy info (only for stage2)
# --------------------------------------------------
if [[ "$INSTALL_MODE" == "stage2" ]]; then
  echo "🧩 NaiveProxy 信息 / NaiveProxy"
  echo "  用户名 / Username:"
  echo "    ${NAIVE_USERNAME}"
  echo
  echo "  密码 / Password:"
  echo "    ${NAIVE_PASSWORD}"
  echo
fi

# --------------------------------------------------
# TLS certificate info (Caddy)
# --------------------------------------------------
echo "🔐 TLS 证书位置 / TLS Certificate (Caddy Auto-Generated)"
echo "  证书根目录 / Certificate Root:"
echo "    /var/lib/caddy/.local/share/caddy/certificates/"
echo
echo "  当前域名证书路径 / Domain Certificate Path:"
echo "    /var/lib/caddy/.local/share/caddy/certificates/"
echo "      acme-v02.api.letsencrypt.org-directory/"
echo "      ${INSTALL_DOMAIN}/"
echo
echo "  常用文件 / Common Files:"
echo "    fullchain.pem   (证书链 / certificate chain)"
echo "    private.key     (私钥 / private key)"
echo
echo "  ⚠️ 说明 / Note:"
echo "    证书由 Caddy 在首次成功 HTTPS 访问域名后自动生成。"
echo "    如目录暂不存在，请先访问一次："
echo "    https://${INSTALL_DOMAIN}"
echo

# --------------------------------------------------
# Helpful commands
# --------------------------------------------------
echo "🔧 常用命令 / Useful Commands"
echo "  启动 3x-ui: systemctl start x-ui"
echo "  停止 3x-ui: systemctl stop x-ui"
echo "  查看状态: systemctl status x-ui"
echo "  重启 Caddy: systemctl restart caddy"
echo

echo "=================================================="
echo "🎉 请妥善保存以上信息 / Please save the info above"
echo "=================================================="
echo