# 大陆中转 · 纯转发（第一阶段：现有 Hetzner）

> 方案书：[docs/plans/20261020-大陆中转.md](../../docs/plans/20261020-大陆中转.md)（§2 中转机、§3 客户端选路）
> 同机的直播站点：[server/stream/README.md](../stream/README.md)
> 客户端：`scripts/net/net_route.gd`（多入口选路）、`scripts/net/supabase.gd` `_http` / `_send`（唯一出口）

**2026-10-20 已部署到裁判机 `turtle-referee-1`（49.13.166.188）**，只做了添加：现有 `stream.turtlearena.xyz` 站点一个字没改，
部署前后 `http://127.0.0.1:8081/healthz` 都是 200。

## 它是什么

```
客户端 ──竞速选路──┬─→ 直连  https://cjefldecsfpnclhfwriw.supabase.co   +  https://stream.turtlearena.xyz/streams
                  └─→ 中转  https://cn.turtlearena.xyz（第一阶段临时入口 https://stream.turtlearena.xyz:8443）
                           /rest/v1/*  /auth/v1/*  ─反代→ cjefldecsfpnclhfwriw.supabase.co（只改 Host）
                           /streams/*              ─反代→ stream.turtlearena.xyz（版本闸在那边照常生效）
                           /healthz                → 200 ok
                           其余                     → 404
```

| 规则 | 行为 |
|---|---|
| 路径 | 只放 `/rest/v1/*`、`/auth/v1/*`、`/streams/*`、`/healthz`；其余（`/storage`、`/functions`、`/realtime`、`/graphql`、`/pg`、根）一律 404；原始路径里带 `..`（含 `%2e%2e`）一律 404 |
| 方法 | GET HEAD POST PATCH PUT DELETE OPTIONS 以外 405 |
| 改写 | 只改 `Host`（= 上游主机名），去掉 Caddy 自加的 `X-Forwarded-Host`；`apikey` / `Authorization` / `X-Client-Version` / `X-Rules-Ver` / 正文原样透传 |
| 请求体 | ≤ 10 MB，超了 413（不打上游） |
| 上游超时 | 连上 5 秒，等回包头 20 秒 |
| 速率 | 按来源 IP：新建 TCP 连接 ≤ 20/秒（突发 60）、同时连接 ≤ 64；超了丢新连接（nftables 表 `inet turtle_relay`）。Caddy 官方包没有按请求限速的模块，见「已知风险」 |
| 日志 | 不开访问日志；Caddy 错误日志默认把 `Authorization` 记成 REDACTED（10-20 实测，见「检查」） |
| 密钥 | 本机中转不持有任何密钥。公开 key 与玩家令牌由客户端自己带；service key 只在 `/etc/turtle-referee/env`（600，Caddy 以 `caddy` 用户运行读不到） |

## 文件

| 文件 | 去哪 | 是什么 |
|---|---|---|
| `relay.caddy` | `/etc/caddy/relay.caddy` | `(relay)` 片段 + 第一阶段入口 `stream.turtlearena.xyz:8443` + 本机自检口 `http://127.0.0.1:8082`；末尾 `import /etc/caddy/relay-cn*.caddy`（没有这个文件时 Caddy 不报错） |
| `relay-cn.caddy` | `/etc/caddy/relay-cn.caddy` | 正式入口 `cn.turtlearena.xyz`。**DNS 生效之后才装**（之前装 Caddy 会对解析不到的名字反复申请证书） |
| `turtle-relay.nft` | `/etc/turtle-relay.nft` | 按来源 IP 限连接（独立表，不碰 ufw 的表，不 flush ruleset） |
| `turtle-relay-nft.service` | `/etc/systemd/system/` | 开机加载上面那张表；stop = 删表 |
| `relay_check.sh` | 不装，哪里都能跑 | 白名单实测 24 条（只读请求） |
| `relay_logcheck.sh` | 服务器上跑 | 日志不记 `Authorization` 的实测（正式实例 + 开了访问日志的对照实例） |

`/etc/caddy/Caddyfile`（= `server/stream/Caddyfile`）末尾多了两行：

```
# 大陆中转（server/relay/README.md）
import /etc/caddy/relay.caddy
```

## 部署（2026-10-20 已照此做过）

```bash
# 仓库文件是 LF；若在 Windows 上被转成了 CRLF，先 tr -d '\r'
mkdir -p /root/relaydeploy && cp -p /etc/caddy/Caddyfile /root/relaydeploy/Caddyfile.bak-20261020
install -m 644 relay.caddy /etc/caddy/relay.caddy
cp /etc/caddy/Caddyfile /root/relaydeploy/Caddyfile.new
printf '\n# 大陆中转（server/relay/README.md）\nimport /etc/caddy/relay.caddy\n' >> /root/relaydeploy/Caddyfile.new
caddy validate --config /root/relaydeploy/Caddyfile.new --adapter caddyfile \
  && install -m 644 /root/relaydeploy/Caddyfile.new /etc/caddy/Caddyfile \
  && systemctl reload caddy            # validate 不过就停在这里，现有站点不受影响
ufw allow 8443/tcp comment "turtle relay phase1"
install -m 644 turtle-relay.nft /etc/turtle-relay.nft
install -m 644 turtle-relay-nft.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now turtle-relay-nft.service
```

`turtle-stream-minver.timer` 每分钟 validate + reload 时会一并带上中转配置；中转配置坏了它会验不过、还原自己的片段、不 reload（不会把现有站点带坏）。

## 切 DNS（正式入口 cn.turtlearena.xyz）

1. **Porkbun 加一条记录**（主会话在用户已登录的浏览器里操作，用户 10-20 授权）：

   | 主机名（Host） | 类型 | 值（Answer） | TTL |
   |---|---|---|---|
   | `cn` | `A` | `49.13.166.188` | `600` |

   （与 `stream` 那条同形状。不加 AAAA：stream 也没加，客户端走 IPv4 即可。以后换香港机只改这条的值。）
2. 等解析生效：`dig +short cn.turtlearena.xyz @1.1.1.1` 回 `49.13.166.188`。
3. 服务器上装正式入口并 reload（会自动申请 Let's Encrypt 证书，约 10 秒）：
   ```bash
   install -m 644 /root/relaydeploy/relay-cn.caddy /etc/caddy/relay-cn.caddy
   caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile && systemctl reload caddy
   # 中转现在也在 443 上 ⇒ 限连接把 443 加进去（同时作用于 stream 站点；阈值对它也足够宽）
   sed -i 's/elements = { 8443 }/elements = { 443, 8443 }/' /etc/turtle-relay.nft && systemctl restart turtle-relay-nft.service
   BASE=https://cn.turtlearena.xyz SB_ANON=<公开 key> bash /root/relaydeploy/relay_check.sh   # RELAY CHECK ALL PASS
   ```
4. 客户端不用改：`net_route.gd` 的默认中转就是 `https://cn.turtlearena.xyz`。确认新包在用之后，8443 入口可撤：
   删 `relay.caddy` 里 `stream.turtlearena.xyz:8443 { … }` 那一段 + `ufw delete allow 8443/tcp`（validate 过了再 reload）。

## 检查

```bash
curl -s http://127.0.0.1:8082/healthz                                                    # ok
BASE=http://127.0.0.1:8082 SB_ANON=<公开 key> bash relay_check.sh                        # 服务器上
BASE=https://stream.turtlearena.xyz:8443 SB_ANON=<公开 key> bash server/relay/relay_check.sh   # 本机（绕开本机代理）
SB_ANON=<公开 key> bash relay_logcheck.sh                                               # 服务器上
nft list table inet turtle_relay                                                         # 计数器看有没有丢过连接
journalctl -u caddy -n 50                                                                # 只有错误日志
```

10-20 实测：`relay_check.sh` 24/24（服务器回环口与本机经 8443 各一遍）；`relay_logcheck.sh`：正式实例 journal 新增 0 行、
含 Authorization 标记 0；对照实例（临时开访问日志）6 行全含 UA 标记、Authorization 标记 0、全部记成 REDACTED。
反向验证：第一版用 `path_regexp` 判 `..`，`/streams/../rest/v1/x` 被 Caddy 先清理成 `/rest/v1/x` 而放行（实测回 401 = 到了 Supabase）⇒
改成判原始路径 `{http.request.orig_uri.path}` 后 404。

## 回滚

- 只撤中转、保留直播：删 `/etc/caddy/Caddyfile` 末尾那两行（或 `cp /root/relaydeploy/Caddyfile.bak-20261020 /etc/caddy/Caddyfile`），
  `caddy validate … && systemctl reload caddy`；`rm /etc/caddy/relay.caddy /etc/caddy/relay-cn.caddy`；
  `systemctl disable --now turtle-relay-nft.service`；`ufw delete allow 8443/tcp`。
- 客户端不用动：中转连不上 = 竞速输掉 / 传输失败两次就换回直连。
- Porkbun 的 `cn` 记录可留可删。

## 已知风险与未决点

- **按请求限速没做**：只限了连接（HTTP/1.1 长连接里一条连接能发很多请求）。要按请求限速得换带 `caddy-ratelimit` 模块的 Caddy 二进制（`caddy add-package`，会**重启**而不是 reload ⇒ 直播断一下），留到搬香港机时一起做。
- **大 NAT**：大陆运营商很多玩家共用一个出口 IP；阈值已放宽，但人一多仍可能撞上。看 `nft list table inet turtle_relay` 的 drop 计数。
- **Supabase 侧按 IP 限流**（方案书 §4 / R4）：所有大陆玩家在 Supabase 看来都来自 49.13.166.188 ⇒ 匿名注册 / 发验证码会被按 IP 限流。要用户本人在 Supabase 面板 Auth → Rate Limits 调高。
- **Cloudflare 对单 IP 的挑战 / 429**（R3）：上线后看 journal 里 403 / 429。
- **同机**：中转与裁判同一台机（R6）；Hetzner 德国到大陆线路质量未实测（R2）——方案书第 1 步实测之后决定要不要搬香港。
- **直播块不缓存**：每块都回源到 stream（同机，几乎无成本）；搬香港后可加缓存。
