#!/bin/bash

# ==========================================
# 核心配置區 (Core Config)
# ==========================================
GITHUB_USER="wwfemg"
REPO_NAME="vps-kit"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}"

# 定義顏色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

clear
echo -e "${GREEN}=============================================${PLAIN}"
echo -e "${GREEN}      Debian VPS 全自動部署 (vps-kit) ${PLAIN}"
echo -e "${GREEN}   集成: NaiveProxy + 3x-ui + Caddy + BBR ${PLAIN}"
echo -e "${GREEN}=============================================${PLAIN}"

# ==========================================
# 1. 強制收集用戶輸入 (User Inputs)
# ==========================================

# 1.1 域名
while [[ -z "$DOMAIN" ]]; do
    read -p "1. 請輸入你的域名 (必填): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then echo -e "${RED}域名不能為空！${PLAIN}"; fi
done

# 1.2 Naive 用戶名
while [[ -z "$NAIVE_USER" ]]; do
    read -p "2. 請設置 NaiveProxy 用戶名 (必填): " NAIVE_USER
    if [[ -z "$NAIVE_USER" ]]; then echo -e "${RED}用戶名不能為空！${PLAIN}"; fi
done

# 1.3 Naive 密碼
while [[ -z "$NAIVE_PASS" ]]; do
    read -p "3. 請設置 NaiveProxy 密碼 (必填): " NAIVE_PASS
    if [[ -z "$NAIVE_PASS" ]]; then echo -e "${RED}密碼不能為空！${PLAIN}"; fi
done

# 1.4 面板端口
while [[ -z "$UI_PORT" ]]; do
    read -p "4. 請設置 3x-ui 面板端口 (必填，建議 10000-65000): " UI_PORT
    if [[ -z "$UI_PORT" ]]; then echo -e "${RED}端口不能為空！${PLAIN}"; fi
done

# 1.5 面板安全路徑 (關鍵修復邏輯)
echo -e "5. 請設置 3x-ui 面板的根路徑 (必須以 / 開頭，例如 /admin)"
read -p "   若直接回車(留空)，腳本將自動生成一個隨機安全路徑: " CUSTOM_PATH

# 路徑處理邏輯
if [[ -z "$CUSTOM_PATH" ]]; then
    FINAL_PATH="/$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9')"
    echo -e "${YELLOW}   用戶未輸入，已自動生成路徑: ${FINAL_PATH}${PLAIN}"
else
    # 確保以 / 開頭
    if [[ "${CUSTOM_PATH:0:1}" != "/" ]]; then
        FINAL_PATH="/${CUSTOM_PATH}"
    else
        FINAL_PATH="$CUSTOM_PATH"
    fi
    echo -e "${GREEN}   使用用戶自定義路徑: ${FINAL_PATH}${PLAIN}"
fi

EMAIL="admin@${DOMAIN}"
echo -e "${YELLOW}配置收集完畢，即將開始安裝...${PLAIN}"
sleep 2

# ==========================================
# 2. 系統初始化 & BBR (System Init)
# ==========================================
echo -e "${GREEN}[1/7] 系統初始化 & 開啟 BBR...${PLAIN}"
apt update -y && apt install -y curl wget socat vim git sqlite3
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
fi

# ==========================================
# 3. 安裝 3x-ui (Database Surgery)
# ==========================================
echo -e "${GREEN}[2/7] 安裝 3x-ui 面板...${PLAIN}"
# 使用官方腳本安裝
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

echo -e "${YELLOW}正在注入數據庫配置...${PLAIN}"
# 關鍵步驟：停止服務以解鎖數據庫文件
systemctl stop x-ui
sleep 2

DB_FILE="/etc/x-ui/x-ui.db"
if [ -f "$DB_FILE" ]; then
    # 3.1 注入端口 (先刪舊後插新)
    sqlite3 "$DB_FILE" "DELETE FROM settings WHERE key='port';"
    sqlite3 "$DB_FILE" "INSERT INTO settings (key, value) VALUES ('port', '${UI_PORT}');"

    # 3.2 注入路徑 (關鍵：確保路徑存在)
    sqlite3 "$DB_FILE" "DELETE FROM settings WHERE key='webBasePath';"
    sqlite3 "$DB_FILE" "INSERT INTO settings (key, value) VALUES ('webBasePath', '${FINAL_PATH}');"

    # 3.3 修正賬號密碼 (直接修改 users 表)
    sqlite3 "$DB_FILE" "UPDATE users SET username='${NAIVE_USER}', password='${NAIVE_PASS}' WHERE id=1;"
    # 兜底插入：防止表為空
    sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO users (id, username, password) VALUES (1, '${NAIVE_USER}', '${NAIVE_PASS}');"
else
    echo -e "${RED}嚴重錯誤：數據庫未找到，面板配置可能失敗！${PLAIN}"
fi

# ==========================================
# 4. 安裝官方 Caddy (Official Caddy)
# ==========================================
echo -e "${GREEN}[3/7] 安裝 Caddy 基礎環境...${PLAIN}"
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install caddy -y
systemctl stop caddy

# ==========================================
# 5. 調用編譯腳本 (Compile Naive)
# ==========================================
echo -e "${GREEN}[4/7] 正在調用編譯模塊 (構建 NaiveProxy)...${PLAIN}"
# 調用 build.sh
wget -O /tmp/build.sh "${BASE_URL}/utils/build.sh"
chmod +x /tmp/build.sh
bash /tmp/build.sh

# ==========================================
# 6. 生成 Caddy 配置文件 (Config Generation)
# ==========================================
echo -e "${GREEN}[5/7] 正在寫入 Caddy 配置...${PLAIN}"
# 直接寫入驗證過的最佳配置 (route 模塊)
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
# 7. 生成 vp 查詢工具 (VP Tool)
# ==========================================
echo -e "${GREEN}[6/7] 生成快捷命令 'vp'...${PLAIN}"
# 寫入查詢腳本，直接讀取數據庫
cat > /usr/local/bin/vp <<EOF
#!/bin/bash
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

show_config_info() {
    domain="${DOMAIN}"
    
    # 從數據庫讀取真實配置 (Source of Truth)
    xui_port=\$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='port'")
    xui_path=\$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='webBasePath'")
    
    # 路徑格式化
    if [[ -z "\$xui_path" || "\$xui_path" == "/" ]]; then
        xui_path_str=""
    else
        [[ "\${xui_path:0:1}" != "/" ]] && xui_path="/\$xui_path"
        xui_path_str="\$xui_path"
    fi

    xui_user=\$(sqlite3 /etc/x-ui/x-ui.db "SELECT username FROM users LIMIT 1")
    xui_pass=\$(sqlite3 /etc/x-ui/x-ui.db "SELECT password FROM users LIMIT 1")

    # 證書檢測
    cert_path="/root/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.crt"
    if [[ ! -f "\$cert_path" ]]; then
         cert_status="\${RED}未檢測到(Caddy自動管理中)\${PLAIN}"
    else
         cert_status="\${GREEN}正常\${PLAIN}"
    fi

    echo -e "================================================================"
    echo -e "                 VPS 配置信息查詢 (vp)             "
    echo -e "================================================================"
    
    echo -e "\${GREEN}[1] 3x-ui 面板管理\${PLAIN}"
    echo -e "    面板地址 : \${GREEN}https://\${domain}:\${xui_port}\${xui_path_str}\${PLAIN}"
    echo -e "    面板賬戶 : \${GREEN}\${xui_user}\${PLAIN}"
    echo -e "    面板密碼 : \${GREEN}\${xui_pass}\${PLAIN}"
    echo -e ""

    echo -e "\${YELLOW}[2] NaiveProxy 客戶端配置\${PLAIN}"
    echo -e "    服務器(Server) : \${domain}"
    echo -e "    端口(Port)     : 443"
    echo -e "    用戶(User)     : \${GREEN}\${xui_user}\${PLAIN}"
    echo -e "    密碼(Password) : \${GREEN}\${xui_pass}\${PLAIN}"
    echo -e "    (注意：客戶端 Probe Resistance 建議留空或設為密碼)"
    echo -e ""
    echo -e "================================================================"
}
show_config_info
EOF

chmod +x /usr/local/bin/vp

# ==========================================
# 結束：啟動服務
# ==========================================
echo -e "${GREEN}[7/7] 正在啟動所有服務...${PLAIN}"
systemctl daemon-reload
systemctl enable x-ui
systemctl start x-ui
systemctl restart caddy

echo -e "${GREEN}安裝全部完成！${PLAIN}"
sleep 1
vp
