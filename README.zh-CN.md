# warp-ai-watchdog

[![CI](https://github.com/MichioY/warp-ai-watchdog/actions/workflows/ci.yml/badge.svg)](https://github.com/MichioY/warp-ai-watchdog/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/MichioY/warp-ai-watchdog)](https://github.com/MichioY/warp-ai-watchdog/releases)

English version: [README.md](README.md)

`warp-ai-watchdog` 是一个面向 Linux 主机的小型 WARP AI 出口巡检脚本。

它会通过 WARP 的 SOCKS 端口，对 OpenAI、Gemini 这类服务做接近真实浏览器行为的健康检查；如果发现当前出口 IP 已经退化，就自动重连 WARP 并重新验证。

这个项目的定位刻意保持很窄：

- 它不负责管理你的整套代理栈。
- 它不承诺永久拿到“干净”IP。
- 它只回答一个实际问题：
  “当前这个 WARP 出口，是否足够支撑我关心的 AI 服务？”

如果答案是否定的，它就轮换 WARP 会话并再次检查。

## 这个项目解决什么问题

有些 AI 服务对出口 IP 信誉和出站路径一致性非常敏感。

常见故障表现包括：

- Google Gemini 跳转到 `sorry/index`
- 持续出现 `google_abuse` 跳转
- OpenAI 不再显示 `warp=on`
- 一个之前可用的 WARP IP，过一段时间后又变差

这个项目的目标是把这类运维动作变成低干预流程：

- 探测
- 判断是健康还是退化
- 重连 WARP
- 再次验证
- 在有限次数内重复

## 它检查什么

当前 watchdog 会通过配置的 SOCKS 代理做两类健康检查：

- OpenAI trace 检查
  - 期望返回有效的 `ip=...`
  - 期望看到 `warp=on`
- Gemini 接近浏览器行为的检查
  - 跟随跳转并使用 cookie jar
  - 遇到 `sorry/index` 视为退化
  - 最终状态码是 `HTTP 200` 视为健康

这些判断都是实用型启发式，不是形式化保证。

## 运行要求

- 带 `systemd` 的 Linux 主机
- 已安装 Cloudflare WARP 客户端
- `warp-cli`
- `warp-svc`
- 一个由 WARP 提供的本地 SOCKS 监听
  - 默认：`127.0.0.1:40000`
- `bash`、`curl`、`flock`

## 适合什么场景

以下场景适合使用这个项目：

- WARP 已经在你的实际出站链路里
- AI 服务会因为当前出口信誉变差而间歇性失败
- 你希望用更安全、可控的本地自愈方式，替代手工重连

以下场景不适合把它当成解决方案：

- 通用代理管理器
- 面板替代品
- 跨平台桌面工具
- “永久保证 Gemini 或 OpenAI 可用”的方案

## 仓库结构

- `warp-ai-watchdog.sh`
  - 主 watchdog 脚本
- `install.sh`
  - 安装脚本、配置文件和 systemd 单元
- `uninstall.sh`
  - 卸载已安装组件
- `warp-ai-watchdog.env.example`
  - 环境变量配置样例
- `systemd/warp-ai-watchdog.service`
  - `oneshot` 服务单元
- `systemd/warp-ai-watchdog.timer`
  - 周期触发定时器

## 快速开始

```bash
git clone <repo-url>
cd warp-ai-watchdog
sudo ./install.sh
```

安装后，先检查生成的配置：

```bash
sudo sed -n '1,200p' /etc/default/warp-ai-watchdog
```

安装完成后可以执行：

```bash
sudo systemctl status warp-ai-watchdog.timer
sudo systemctl start warp-ai-watchdog.service
sudo tail -f /var/log/warp-ai-watchdog.log
```

## 配置说明

安装器会写入 `/etc/default/warp-ai-watchdog`。

你也可以从仓库自带样例开始：

```bash
cp warp-ai-watchdog.env.example /tmp/warp-ai-watchdog.env
```

支持的配置项如下：

```bash
SOCKS_HOST=127.0.0.1
SOCKS_PORT=40000
OPENAI_URL=https://chat.openai.com/cdn-cgi/trace
GEMINI_URL=https://gemini.google.com/
USER_AGENT=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36
MAX_ATTEMPTS=3
CURL_TIMEOUT=25
GEMINI_TIMEOUT=35
MAX_REDIRS=8
DISCONNECT_SLEEP=3
CONNECT_SLEEP=8
SERVICE_RESTART_SLEEP=8
WARP_CLI_BIN=warp-cli
WARP_SERVICE_NAME=warp-svc
LOG_FILE=/var/log/warp-ai-watchdog.log
STATE_DIR=/var/lib/warp-ai-watchdog
LOCK_FILE=/run/warp-ai-watchdog.lock
```

修改配置后执行：

```bash
sudo systemctl daemon-reload
sudo systemctl restart warp-ai-watchdog.timer
sudo systemctl start warp-ai-watchdog.service
```

定时频率定义在 [`systemd/warp-ai-watchdog.timer`](systemd/warp-ai-watchdog.timer)。
如果你要调整执行间隔，直接修改 timer 单元并重新加载 systemd。

## 健康检查逻辑

watchdog 的判断流程如下：

1. 通过 WARP 探测 OpenAI。
2. 通过 WARP 探测 Gemini，并跟随跳转、携带 cookie jar。
3. 如果两项都健康，则直接退出。
4. 只要任意一项退化，就执行：
   - 断开 WARP
   - 重连 WARP
   - 重启 `warp-svc`
   - 比较重连前后的出口 IP
   - 再次探测
5. 达到 `MAX_ATTEMPTS` 后停止。

这意味着它并不是在寻找“理论上最干净”的 IP，而是在寻找“当前真实站点检查能通过”的 IP。

## 如何验证

手动执行一次完整检查：

```bash
sudo /usr/local/bin/warp-ai-watchdog --run
echo $?
```

查看最近日志：

```bash
sudo tail -n 50 /var/log/warp-ai-watchdog.log
```

查看定时器状态：

```bash
sudo systemctl list-timers --all | grep warp-ai-watchdog
```

健康状态下，日志里通常会出现：

- `ok openai=1 gemini=1 ip=...`
- `recovered attempt=... openai=1 gemini=1 ip=...`

## 常用命令

立即手动跑一轮健康检查：

```bash
sudo /usr/local/bin/warp-ai-watchdog --run
```

查看当前 WARP 状态：

```bash
warp-cli status
```

检查当前 WARP 出口下的 OpenAI trace：

```bash
curl --socks5-hostname 127.0.0.1:40000 \
  -fsS https://chat.openai.com/cdn-cgi/trace
```

用跳转和 cookie jar 检查 Gemini：

```bash
tmp_cookie="$(mktemp)"
curl --socks5-hostname 127.0.0.1:40000 \
  -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36' \
  -sS -L -c "$tmp_cookie" -b "$tmp_cookie" -D - -o /dev/null \
  https://gemini.google.com/
rm -f "$tmp_cookie"
```

## 故障排查

### 定时器是 active，但看起来没有执行

- 检查 `sudo journalctl -u warp-ai-watchdog.service -n 50 --no-pager`
- 检查 `sudo tail -n 50 /var/log/warp-ai-watchdog.log`
- 确认 `warp-cli status`

### watchdog 一直在轮换，但始终恢复不了

- 确认 SOCKS 监听背后确实是 WARP
- 确认 `warp-cli connect` 在该主机上真的会改变连接状态
- 降低预期：这些探测结果与具体服务、具体时间窗口强相关

### 我想替换成别的检查目标

- 没有经过验证前，不要轻易改默认逻辑
- 如果你修改 `OPENAI_URL` 或 `GEMINI_URL`，需要自己确认语义是否仍然成立

## 局限性

- “健康”只代表当前探测通过。
- Google 或其他 AI 服务之后仍可能对当前会话限流。
- 有些服务在真实浏览器里的表现，和 `curl` 不完全一致。
- 如果 `warp-cli disconnect/connect` 一直拿回同样的差 IP，这个工具也无法强制 Cloudflare 分配更好的出口。

## 安全说明

- watchdog 使用锁文件避免并发运行。
- 它不会修改你的 WARP 注册信息。
- 它只通过以下本地动作轮换连接：
  - `warp-cli disconnect`
  - `warp-cli connect`
  - `systemctl restart warp-svc`
- 它只会把临时 cookie 保存在配置的状态目录里。

## 贡献

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 许可证

MIT
