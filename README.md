# vps-kit

Debian 一键部署 **3x-ui + Caddy（+ NaiveProxy）**。单文件脚本，装完自检。

## 一键安装

```bash
apt update -y && apt install -y curl && bash <(curl -Ls https://raw.githubusercontent.com/wwfemg/vps-kit/main/install.sh)
```

> ⚠️ **前面的 `apt install -y curl` 不能省** —— 全新 DD 的 Debian 13 不带 curl 也不带 wget，
> 直接跑 `bash <(curl ...)` 会报 `curl: command not found`，脚本根本不会启动。

## 安装模式

| 模式 | 内容 | 说明 |
|------|------|------|
| **A** 标准安装 | 3x-ui + Caddy | 仅 HTTPS，Caddy 反代面板。Caddy 走官方 apt 源 |
| **B** 标准安装 + NaiveProxy | 3x-ui + Caddy + NaiveProxy | 下载预编译的 Caddy（含 forwardproxy） |

## 安装前准备

- [ ] 域名 A 记录**已解析到本机公网 IP**
- [ ] Cloudflare 用户注意：**关闭橙云代理（设为「仅 DNS」）**，否则证书申请失败
- [ ] 端口 80 / 443 未被占用
- [ ] 建议先 DD 成干净系统

安装时会要求输入：

```
安装模式:     A / B
域名:         必须已解析
3x-ui 端口:   建议自己设定高位端口
3x-ui 根路径: 建议自己设定隐蔽路径
订阅路径:     建议自己设定
3x-ui 用户名: 建议自己设定
3x-ui 密码:   必填，无默认
Naive 账号:   仅 B 模式
```

> **端口、路径、用户名请自己设定，不要直接回车用内置默认值。**
> 本项目是公开的，内置默认值等于公开信息 —— 所有图省事没改的机器会被一起扫到。
> 自己设定的值请记牢，装完在服务器上跑 `vps` 也能查回来。

## 安装后

服务器上执行 `vps` 查看全部配置信息：

```bash
vps
```

输出账号密码、面板地址、订阅地址、证书短路径、服务状态，以及广告拦截是否仍然生效。

## 去掉 3x-ui 自带广告

3x-ui 自 **v3.9.0**（2026-10-03）起内置赞助商广告子系统：

- 面板每小时向 `raw.githubusercontent.com/MHSanaei/sponsors` 拉广告内容，失败每 10 分钟重试
- 广告位含 **登录页**（`dashboard` / `page` / `login` 三处）
- `/sponsors` 与 `/sponsors/logo/*` 两个路由**免鉴权**，上游注释写明
  "sponsors is public so the login page can render its slot" ——
  对伪装部署来说，这等于向任何摸到面板路径的人确认「这是 3x-ui」
- **配置里没有任何环境变量能关掉它**，面板里「关闭」只在 localStorage 记 24 小时

本脚本在 **Caddy 层**拦截，不改 3x-ui、不 fork：

```caddyfile
handle <面板路径>/sponsors/* {
    respond 404
}
handle <面板路径>/sponsors {
    header Content-Type application/json
    respond `{"success":false}` 200
}
```

上游前端在接口返回 `success=false` 时渲染空且不重试，这是它自己的降级路径。
请求不转发给 x-ui，所以广告没了，**每小时的外联也一起没了**。

因为拦截在反代层，**升级 3x-ui 不会让广告回来**。

### 已经装好的机器

不必重装，跑 `tools/remove-ads.sh` 即可。它会备份 Caddyfile、`caddy validate` 校验、
优雅重载并验证结果，校验不通过自动回滚；找不到插入点会安全中止而不乱改。

```bash
curl -fsSLo remove-ads.sh https://raw.githubusercontent.com/wwfemg/vps-kit/main/tools/remove-ads.sh
bash remove-ads.sh
```

## Caddy 从哪来

模式 B 需要带 `forwardproxy` 的 Caddy，官方 apt 源里没有，只能自己构建。

**默认下载预编译的**，不在目标机器上编译：

```
本仓库 Actions 交叉编译 amd64/arm64  →  Release（tag: caddy-v2.11.7-naive）
                                      ↓
install.sh 下载 → 强制校验 sha256 → 验 forward_proxy 插件 → 安装
```

低配机器（1-2 核、1G 内存以下）本机编译既慢也不可靠：2 核冷缓存约 4 分钟，1 核更久；
`xcaddy` 要先 `go mod download` 拉几百个模块，而 Go 默认没有积极的超时，
网络差时可能长时间毫无进展。问题的性质不是「慢」而是「无界」—— 几分钟可以等，
不确定的卡死没法等。预编译把它变成「下载一个 50MB 文件」：有界、可重试、
所有机器拿到同一份 bit。

参考耗时（2 核 1G 以下机器）：下载约半分钟，本机编译约五分钟。

### 下载失败会自动回落到本机编译

下载不通、sha256 不匹配、插件缺失、该架构没有产物 —— 任何一种情况都回落编译，
**不留死路**。最坏情况就是回到纯编译的体验。

不信任预编译的二进制时，强制走编译：

```bash
VPS_KIT_BUILD=1 bash <(curl -Ls .../install.sh)
```

编译各步骤都包了 `timeout`（默认 1500 秒），把「无限卡死」变成「到点干净失败」。

构建信息会留在机器上 `/etc/vps-kit/caddy-build-info.txt`，记录这个二进制是哪次
Actions 构建、用什么源码编出来的。

### 怎么出新的二进制

```
GitHub 仓库 → Actions → Build Caddy (NaiveProxy) → Run workflow
```

版本留空就自动取「配对好的最新」。**只手动触发，不设定时** —— 自动发布会让版本在
没人看的情况下移动，而「能编译、能加载插件、隧道却不通」这类问题只有装机自检才能发现。

每次构建发布到新的 tag（`caddy-<naive tag>`），已发布的不会被覆盖。出了新的二进制后，
要把 `install.sh` 里 `BIN_TAG` 的默认值改成新 tag，装机才会用上；改之前仍下载原来那一版。

## 版本策略

**不硬编码任何版本号**，构建时探测「配对好的最新」：

| 组件 | 怎么定 | 在哪定 |
|---|---|---|
| forwardproxy | klzgrad 最新 `vX.Y.Z-naive` tag 所指的 **commit SHA** | Actions（编译时）／本机（回落时） |
| Caddy | 由上面那个 tag 的**名字**推出（`v2.11.7-naive` → `v2.11.7`） | 同上 |
| Go | go.dev 最新稳定版 | 同上 |
| 3x-ui | GitHub 最新 release，下载后校验上游自带的 `.sha256` | 装机时 |

klzgrad 按 Caddy 的每个 release 打配对 tag，所以这样拿到的是**上游验证过能配对**的组合。

> **为什么不直接用 `@naive` 分支**：分支 HEAD 随时在动，两台机器隔一个月装编出来的不是
> 同一份代码；再配上一个自己选的 Caddy 版本，等于赌两个独立漂移的东西能对上。
>
> **为什么不能直接用 tag 名**：Go modules 规定模块路径不带 `/vN` 后缀的模块只能是 v0 或 v1
> 版本，而这些 tag 叫 `v2.11.7-naive`，`go get` 会直接报
> `version "v2.11.7-naive" invalid: should be v0 or v1, not v2`。
> 所以用 tag 指向的 commit，Go 会解析成 `v0.0.0-<日期>-<sha>` 伪版本。

手动指定：

```bash
VPS_KIT_NAIVE_TAG=v2.11.2-naive bash <(curl -Ls .../install.sh)   # 换一组配对
VPS_KIT_NAIVE_REF=naive         bash <(curl -Ls .../install.sh)   # 退回分支 HEAD
VPS_KIT_GO_VER=1.24.1 VPS_KIT_CADDY_VER=v2.9.1 ...                # 全手动
```

## 安装后自检

脚本结尾自动检查并输出（模式 B 九项，模式 A 八项）：

```
[OK] caddy / x-ui 运行中
[OK] 面板经 Caddy 可访问
[OK] 伪装站正常（根路径 200）
[OK] 广告接口已拦截（返回本机空响应）
[OK] 面板端口仅监听本机
[OK] 订阅端口仅监听本机
[OK] 订阅服务经 Caddy 可达
[OK] NaiveProxy 隧道实连（curl 走代理实测 204，不是只看服务状态）
```

广告那一项断言的是**返回内容**而不只是状态码：上游 `entity.Msg` 没有 `omitempty`，
它自己拉取失败时返回 `{"success":false,"msg":"","obj":null}`，被本脚本拦截后是
`{"success":false}` —— 字符串不同，可以区分「拦截生效」和「上游恰好没拉到」。

## 版本

当前版本：`2026.10.23`

## 环境

Debian 12 / 13，x86_64 与 arm64。
