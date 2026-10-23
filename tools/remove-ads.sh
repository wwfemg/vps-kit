#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# remove-ads.sh — 去掉 3x-ui 面板广告（Caddy 层拦截）
#
# 适用：已用 vps-kit 装好、正在运行的机器。
# 不改 3x-ui、不重装、不停机（Caddy 优雅 reload）。可重复执行。
# 原理见 README「去掉 3x-ui 自带广告」。
# ============================================================

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[INFO] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
err()  { echo -e "${RED}[ERROR] $*${NC}" >&2; }

CF="/etc/caddy/Caddyfile"
CONF="/etc/vps-kit.conf"

[[ "$(id -u)" -eq 0 ]] || { err "必须用 root 运行"; exit 1; }
[[ -f "${CONF}" ]] || { err "未找到 ${CONF}，这台机器不是用 vps-kit 装的？"; exit 1; }
[[ -f "${CF}" ]]   || { err "未找到 ${CF}"; exit 1; }

# shellcheck source=/dev/null
source "${CONF}"
: "${DOMAIN:?${CONF} 里缺 DOMAIN}"
: "${XUI_PATH:?${CONF} 里缺 XUI_PATH}"

probe() { curl -s --max-time 15 "https://${DOMAIN}${XUI_PATH}/sponsors" 2>/dev/null || true; }

# ---- 1. 先看这台机器现在什么状况 ----
log "检查 ${DOMAIN}${XUI_PATH}/sponsors ..."
BEFORE="$(probe)"
case "${BEFORE}" in
  *'"success":true'*)
    warn "广告正在投放中（接口返回了赞助商数据）" ;;
  '{"success":false,"msg":"","obj":null}')
    warn "接口存在（3x-ui ≥ v3.9.0），当前恰好没有活动广告或拉取失败——仍需拦掉" ;;
  '{"success":false}')
    log "接口已被拦截，无需处理。"; exit 0 ;;
  *)
    log "未检测到该接口（可能是 v3.8.5 及更早的干净版本）"
    log "仍然打上拦截规则，日后升级 3x-ui 就不会再冒出来。" ;;
esac

# ---- 2. 幂等检查 ----
if grep -qF "handle ${XUI_PATH}/sponsors" "${CF}"; then
  log "Caddyfile 里已有拦截规则，跳过写入。"
else
  # ---- 3. 备份后插入规则（必须在通用面板 handle 之前）----
  BAK="${CF}.bak-$(date +%Y%m%d-%H%M%S)"
  cp -a "${CF}" "${BAK}"
  log "已备份: ${BAK}"

  TMP="$(mktemp)"
  awk -v target="handle ${XUI_PATH}*" -v path="${XUI_PATH}" '
    !inserted && index($0, target) {
      match($0, /^[ \t]*/)
      ind = substr($0, 1, RLENGTH)
      print ind "# 拦掉 3x-ui 自带广告接口：不转发给面板，顺带掐断每小时外联"
      print ind "# logo 路径回 404，与上游对未知 logo 的行为一致"
      print ind "handle " path "/sponsors/* {"
      print ind "    respond 404"
      print ind "}"
      print ind "handle " path "/sponsors {"
      print ind "    header Content-Type application/json"
      print ind "    respond `{\"success\":false}` 200"
      print ind "}"
      inserted = 1
    }
    { print }
  ' "${CF}" > "${TMP}"

  if ! grep -qF "handle ${XUI_PATH}/sponsors" "${TMP}"; then
    rm -f "${TMP}"
    err "在 ${CF} 里没找到面板的 handle ${XUI_PATH}* 这一行，不敢乱改。"
    err "请把下面这份 Caddyfile 内容发给我看一下："
    echo "---------------- ${CF} ----------------"
    cat "${CF}"
    echo "--------------------------------------"
    exit 1
  fi

  cat "${TMP}" > "${CF}"
  rm -f "${TMP}"

  # ---- 4. 校验，不通过立刻回滚 ----
  if ! caddy validate --adapter caddyfile --config "${CF}" >/dev/null 2>&1; then
    err "Caddyfile 校验不通过，已回滚到 ${BAK}"
    caddy validate --adapter caddyfile --config "${CF}" 2>&1 | tail -20 >&2 || true
    cp -a "${BAK}" "${CF}"
    exit 1
  fi
  log "Caddyfile 校验通过"

  systemctl reload caddy 2>/dev/null || systemctl restart caddy
  sleep 2
fi

# ---- 5. 验证 ----
echo
log "验证结果:"
fail=0

AFTER="$(probe)"
if [[ "${AFTER}" == '{"success":false}' ]]; then
  echo "  [OK] 广告接口已拦截，返回本地空响应（未透传给 x-ui）"
else
  echo "  [FAIL] 广告接口仍在透传，实际返回: ${AFTER:-<空>}"
  fail=1
fi

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://${DOMAIN}${XUI_PATH}/" 2>/dev/null || echo 000)"
if [[ "${code}" == "200" || "${code}" == "302" ]]; then
  echo "  [OK] 面板仍可正常访问 (HTTP ${code})"
else
  echo "  [FAIL] 面板访问异常 (HTTP ${code})"
  fail=1
fi

systemctl is-active --quiet caddy && echo "  [OK] caddy 运行中" || { echo "  [FAIL] caddy 未运行"; fail=1; }

echo
if [[ "${fail}" -eq 0 ]]; then
  log "完成 ✅ 广告已去除，面板正常。"
else
  warn "存在失败项。如需回滚："
  warn "  cp -a ${CF}.bak-* ${CF} && systemctl reload caddy"
  exit 1
fi
