# 逐帧直播 · 传输与运维（S4）

> 方案书：[docs/plans/20261019-服务器逐帧直播.md](../../docs/plans/20261019-服务器逐帧直播.md)（§3 传输 ④、§6 S4、验收「传输」那一条）
> 上游：[server/referee/README.md](../referee/README.md)（裁判机本身、轮询器、密钥文件）
> 录流格式（块文件 / end.json）：方案书 §2.2，代码 `scripts/systems/stream/`
>
> **2026-10-19 已部署到裁判机 `turtle-referee-1`（49.13.166.188）**。轮询器的录流开关**还关着**：
> 服务器上在服役的 v0.20.1 工程没有录流代码（S1 之后的版本才有），开了也不会录。

## 它是什么

```
轮询器 referee_poller.py（STREAM_ROOT 设了才录）
  └ godot … Referee.tscn -- --job=… --out=… --stream=/var/lib/turtle-referee/streams-tmp/<match_id>
        每 1 秒（60 步）写一块 000000.bin, 000001.bin, …，收尾写 end.json
  └ 每 0.25 秒扫一次临时目录：块 N+1 出现 ⇒ 块 N 写完了 ⇒ os.replace 到
        /var/lib/turtle-referee/streams/<match_id>/000000.bin …（同一文件系统 ⇒ 原子；对外只会看到完整的文件）
    局算完：挪剩下的块，最后挪 end.json。局失败：撤掉对外目录里的半截（重领从头再录）。
    重领到的局对外目录里已有 end.json ⇒ 不再录（结果确定性相同，已发布那份仍有效）。

Caddy（stream.turtlearena.xyz，Let's Encrypt 自动证书）
  GET https://stream.turtlearena.xyz/streams/<match_id>/<6 位序号>.bin
  GET https://stream.turtlearena.xyz/streams/<match_id>/end.json
  GET https://stream.turtlearena.xyz/healthz                     ← 不过版本闸
```

| 规则 | 行为 |
|---|---|
| 版本闸 | `/streams/*` 要带请求头 `X-Client-Version` ≥ `service_status.min_client_version`，否则 **426** `{"message": "update_required", "min_client_version": "…"}`，响应头 `X-Min-Client-Version`。口径与 PostgREST 钩子 `check_client_version` 完全相同：**不带头 / 看不懂 ⇒ 按 0.0.0 ⇒ 拒**；最低版本本身看不懂或为 0 ⇒ 不设闸 |
| 地址 | 只认 `^/streams/<uuid>/<数字>.bin$` 与 `…/end.json$`；其余（目录、根、`..`、别的路径）一律 404。不列目录 |
| 方法 | 只许 GET / HEAD，其余 405 |
| 块 `.bin` | `Content-Type: application/octet-stream`，`Cache-Control: public, max-age=604800, immutable`（写完一个 rename 一个，之后不改）。**不再压缩**（块本身已是 ZSTD） |
| `end.json` | `application/json; charset=utf-8`，`Cache-Control: public, max-age=10`，客户端带 `Accept-Encoding: gzip` 时 gzip |
| 404 / 405 / 426 | `Cache-Control: no-store`（块还没写到时的 404 不能被缓存） |
| HTTP | 80 只做 ACME 与 308 跳 HTTPS；443 TCP（HTTP/1.1、HTTP/2）+ 443 UDP（HTTP/3） |

## 文件

| 文件 | 去哪 | 是什么 |
|---|---|---|
| `Caddyfile` | `/etc/caddy/Caddyfile`（装包时的默认版备份在 `/etc/caddy/Caddyfile.dist`） | 站点 + 本机自检口 `http://127.0.0.1:8081`（只听回环、不走 TLS） |
| `stream_ops.py` | `/opt/turtle/stream/stream_ops.py`（root 所有） | `minver` / `purge` / `selftest` / `regex <版本>` |
| `turtle-stream-minver.service` + `.timer` | `/etc/systemd/system/` | 每分钟：只读 GET `service_status` → 生成 `/etc/caddy/turtle-min-version.caddy`（变了才写，`caddy validate` 过了才 `systemctl reload caddy`，不过就还原）。读不到库 ⇒ 片段不动 |
| `turtle-stream-purge.service` + `.timer` | `/etc/systemd/system/` | 每小时 :05 UTC（`Persistent=true`）删过期局目录，以 `turtle-referee` 身份跑 |
| （生成的）`/etc/caddy/turtle-min-version.caddy` | 不进仓库 | `@stream_old` 匹配器 + 426 响应。别手改，下一分钟会被覆盖 |

目录：`/var/lib/turtle-referee/streams`（755，turtle-referee，Caddy 只读这里）与 `/var/lib/turtle-referee/streams-tmp`（700，不对外）。两者必须在同一文件系统。

## 版本闸为什么是正则

Caddy 没有「版本号比大小」的匹配器。`stream_ops.py` 按最低版本**生成**一条只匹配「≥ 最低版本」的 RE2 正则（1~4 段、每段 1~6 位、允许前导零，与 SQL `semver_arr` 同口径），用 `header_regexp` 挂上。
正则不用花括号量词（Caddyfile 会把 `{…}` 当占位符），重复一律展开。
`python3 stream_ops.py selftest`：生成的正则与 Python 版 `client_version_ok` 对拍约 8 万条，必须 0 条不一致（2026-10-19 反向验证：去掉前导零支持 ⇒ 6750 条不一致；「大于」差一 ⇒ 6022 条不一致）。

## 保留期

与库里录像同一条口径（`schema.sql` `purge_old_matches`，cron `0 0 * * 2`）：**每周二 00:00 UTC 删掉本周一 00:00 UTC 之前的**。
`purge` 每小时跑，截止线 =「(现在 − 1 天) 所在 ISO 周的周一 00:00 UTC」：周一全天截止线是上周一（上个周末的还在），周二 00:00 起变成本周一。局目录的时间取 mtime（= 最后一块写入时）。
只删名字是 UUID 的目录；临时目录里超过 1 天的残留一并删。按 R1 实测每局 0.9~2.5 MB，一周存量约 1~2.5 GB，盘 80 GB。

## 部署步骤（第一次；2026-10-19 已照此做过）

```bash
# 1. Caddy 官方 apt 源
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt -o /etc/apt/sources.list.d/caddy-stable.list
apt-get update && apt-get install -y caddy

# 2. 文件（仓库是 CRLF：先转 LF 再传，Caddyfile / systemd 单元带 \r 会坏）
install -d -m 755 /opt/turtle/stream && install -m 755 stream_ops.py /opt/turtle/stream/
install -d -m 755 -o turtle-referee -g turtle-referee /var/lib/turtle-referee/streams
install -d -m 700 -o turtle-referee -g turtle-referee /var/lib/turtle-referee/streams-tmp
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.dist && install -m 644 Caddyfile /etc/caddy/Caddyfile
python3 /opt/turtle/stream/stream_ops.py selftest
python3 /opt/turtle/stream/stream_ops.py minver          # 第一次生成片段 + reload
install -m 644 turtle-stream-*.service turtle-stream-*.timer /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now turtle-stream-minver.timer turtle-stream-purge.timer

# 3. 防火墙（Hetzner 云防火墙没建，只有 ufw）
ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 443/udp
```

DNS：Porkbun 的 A 记录 `stream.turtlearena.xyz → 49.13.166.188`。证书由 Caddy 自动申请 / 续期（存在 `/var/lib/caddy/.local/share/caddy/certificates/`），只走 Let's Encrypt。

## 打开录流（等服务器上装了带 `scripts/systems/stream/` 的版本之后）

```bash
echo 'STREAM_ROOT=/var/lib/turtle-referee/streams' >> /etc/turtle-referee/env
# 确认没有正在跑的局（pgrep -f '^/opt/godot/godot' 为空）再重启；停服时手上那局会跑完再退
systemctl restart turtle-referee
```

没带录流代码的版本（v0.20.1 及更早）即使开关开着也**不传 `--stream`**（轮询器按工程里有没有 `scripts/systems/stream/stream_recorder.gd` 判）。
关掉 = 删掉那一行再重启。已发布的目录照常按保留期清。

## 检查

```bash
curl -sI https://stream.turtlearena.xyz/healthz                                   # 200
curl -s -o /dev/null -w '%{http_code}\n' https://stream.turtlearena.xyz/streams/<id>/000000.bin                       # 426（不带头）
curl -s -o /dev/null -w '%{http_code}\n' -H 'X-Client-Version: 0.20.0' https://stream.turtlearena.xyz/streams/<id>/000000.bin   # 426
curl -sI -H 'X-Client-Version: 0.20.1' -H 'Accept-Encoding: gzip' https://stream.turtlearena.xyz/streams/<id>/000000.bin        # 200, 无 Content-Encoding
grep '^# min' /etc/caddy/turtle-min-version.caddy                                 # 当前生效的最低版本
systemctl list-timers 'turtle-*'; journalctl -u turtle-stream-minver -u turtle-stream-purge -n 20
```

## 回滚

- 只关录流：从 `/etc/turtle-referee/env` 删 `STREAM_ROOT` 行，`systemctl restart turtle-referee`（轮询器其余行为与以前相同）。
- 退回旧轮询器：`/root/s4deploy/referee_poller.py.bak-v0201` 是换之前那份（= 仓库 S4 之前的 `server/referee/referee_poller.py`），拷回 `/opt/turtle/referee/` 后重启。
- 整个下线：`systemctl disable --now caddy turtle-stream-minver.timer turtle-stream-purge.timer`，`ufw delete allow 80/tcp`（443/tcp、443/udp 同理）。`/var/lib/turtle-referee/streams*` 可直接删。

## 已知风险与未决点

- **重领时换了一份流**：局失败（超时 / 崩）会撤掉半截再从头录；而特效随机（`_juice_rng`）让同一局两次录出来的块字节不同。正在看半截的手机会拿到对不上的后续块 ⇒ 要靠 S2 播放端按块序号 / keyframe 重新同步（或显示「无法播放」）。写回失败（`referee_complete` 网络错误）后的重领不受影响：对外目录已有 `end.json` 就不再录。
- **块的长缓存**：上一条的重录如果发生在手机已缓存了旧块之后，旧块会被缓存 7 天。可接受的前提同上：播放端遇到前后对不上要从 keyframe 重来，而不是信缓存。
- **版本闸只是挡旧包**：请求头谁都能伪造，闸只保证「旧版本客户端不会去解一个它不认识的格式」，不是访问控制；match_id 不可猜才是（录像本来就对所有登录用户公开，方案书 §3）。
- **最低版本同步延迟 ≤ 1 分钟**；库读不到时沿用上次的值（不会因为 Supabase 抖一下就把人全关在门外，也不会放开闸）。
- **单机单点**：Hetzner 挂了既出不了结果也播不了（上游 R3），故障面没有变大。
- **没有访问日志**（Caddy 默认不记），出问题只能看 `journalctl -u caddy`。要记得先对隐私政策（IP 属个人数据）。
- 告警通道仍未定（与裁判 README 同一条）：minver 读不到库只进 journald。
