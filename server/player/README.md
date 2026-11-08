# 网页录像播放器 · 构建、部署与运维

> 方案书：[docs/plans/20261105c-主站对接偷袭.md](../../docs/plans/20261105c-主站对接偷袭.md) §4.7 · 约定 [docs/specs/主站对接约定.md](../../docs/specs/主站对接约定.md) §4.4 · [docs/plans/20261107-龟战主站对接.md](../../docs/plans/20261107-龟战主站对接.md) §4.5 / §4.7（`playerURL`）
> 上游：[server/stream/README.md](../stream/README.md)（状态流块与 end.json 怎么来、保留期）、[server/deploy/README.md](../deploy/README.md)（裁判机部署）
>
> **2026-11-08 只写了文件，没有部署。** 子域名 `arena` / `arena-beta` 的 A 记录与站点块由网关那一条线建（20261107 §4.7）。

## 它是什么

主站 iframe 内嵌 `https://arena.turtlearena.xyz/player?match=<对局号>`（内测 `arena-beta`），电脑浏览器里看一局已打完的服务器局。
Godot 网页版 + 状态流只播不算（与 App 里回放同一个 StreamPlayer、同一个战斗场，特效完整）；不登录、不走联网闸、不写任何数据。

```
/player?match=<id>            入口页 index.html（几 KB，先于游戏资源加载）
   ├ 手机浏览器               ⇒「请在小游戏内观看」（不下载游戏资源）
   ├ 读 /player/streams/<id>/end.json 的 client_version
   │    ├ /player/<版本>/ 在   ⇒ 跳 /player/<版本>/?match=<id>
   │    └ 这一版已清掉         ⇒「录像已过期」
   └ end.json 404 ⇒ /player/expired/<id> 200 ⇒「录像已过期」，否则「未找到该对局的录像」
/player/<版本>/?match=<id>    导出预设 WebPlayer（主场景 scenes/WebPlayer.tscn，脚本 scripts/scenes/WebPlayerScene.gd）
   ├ 自己再判一遍（直接打开版本目录也得对；版本不对 ⇒ 回入口页带 hop=1，第二次还不对 ⇒「录像版本与播放器版本不一致」）
   ├ 拉第 0 块读地图种子 → StreamWatch.enter_web → 战斗场（回放操作条：暂停 / 倍速 / 进度条）
   └ 播完 / 退出 ⇒ 回本页「播放结束」+「重新播放」
/player/streams/<id>/…        与 stream.turtlearena.xyz/streams 同一批文件（同源，不用跨域头；不过版本闸：版本由目录选）
/player/expired/<id>          stream_ops.py purge 删局目录时留的记号
```

| 文件 | 去哪 | 是什么 |
|---|---|---|
| `player.caddy` | `/etc/caddy/turtle-player.caddy` | Caddy 片段，三个参数（播放器根 / 流根 / 过期记号根），在 arena / arena-beta 站点块里各 `import` 一次（写法见文件头） |
| `index.html` | `<播放器根>/index.html` | 入口页（`player_ops.py install --entry` 换） |
| `player_ops.py` | `/root/deploy/player/player_ops.py`（`deploy.py` 每次上传） | `install` / `prune` / `status` / `selftest` |
| 导出产物 | `<播放器根>/<版本>/` | `bash build-web.sh player` 打的 `build/turtle-webplayer-<版本>.zip` |

播放器根：正式 `/var/www/turtle-player/prod`，内测 `/var/www/turtle-player/beta`（**不放 `/opt/turtle*/`**：`referee_poller.py` 把那一层带 `project.godot` 的子目录都当版本）。
过期记号根：`/var/lib/turtle-referee/streams-expired`、`/var/lib/turtle-referee-beta/streams-expired`（purge 自己建，755）。

## 保留期

- **录像**：普通局照旧「每周二删上周一之前的」；**偷袭局（end.json `mode = raid`）留 30 天**（`stream_ops.py` `RAID_KEEP_DAYS`）。
  删一局时先写过期记号再删目录；记号留 400 天。⇒ end.json 要带 `mode`（裁判 `referee_runner.gd` 2026-11-08 起写 `mode` / `names` / `fights`；**这三样要等装了带这次改动的版本的裁判机才有**，之前录的局按普通局清、名字左边留空）。
- **播放器版本**（约定 §4.4「保留期内各版本的录像都要能播」）：`player_ops.py prune`（每次 install 后自动跑）只删同时满足下面三条的版本目录：
  不是最新 3 个；流目录里没有一局的 end.json 是这个版本；被下一个版本取代满 35 天。
  先于这次改动装上去、清单里没有取代时刻的版本一律不删。

## 构建（本机 Windows）

```bash
git checkout v<版本>                       # ★在 tag 那一提交、工作区干净时打（产物戳 webplayer.json 记 sha 与 dirty，deploy.py 核）
PY=<本机 python 全路径> bash build-web.sh player
# ⇒ build/webplayer/（index.html / .js / .wasm / .pck / webplayer.json）+ build/turtle-webplayer-<版本>.zip
```

2026-11-08 第一次导出（0.22.9 + 本改动）：`index.pck` 142.1 MB、`index.wasm` 36.0 MB（gzip 后 9.1 MB）、其余不到 0.5 MB；
**首开约下载 151 MB**（pck 里 98 MB 是贴图、14 MB 背景乐、10 MB 字体；pck 不压缩，压了只省约 4%）。之后走浏览器缓存（版本目录 `no-cache` + ETag ⇒ 复访 304）。
方案书原定「先打一个包，实测首开太慢再按龟拆」—— 151 MB 偏大，拆包 / 去掉播放器用不到的菜单资源是下一步（见下「未决」）。

## 部署（第一次）

```bash
# 1. 目录
install -d -m 755 /var/www/turtle-player /var/www/turtle-player/prod /var/www/turtle-player/beta
install -d -m 755 -o turtle-referee -g turtle-referee /var/lib/turtle-referee/streams-expired /var/lib/turtle-referee-beta/streams-expired
# 2. purge 换成带偷袭 30 天与过期记号的版本（server/stream/stream_ops.py，CRLF 先转 LF；正式与内测各一份）
install -m 755 stream_ops.py /opt/turtle/stream/ && install -m 755 stream_ops.py /opt/turtle-beta/stream/
python3 /opt/turtle/stream/stream_ops.py purge-selftest           # ALL OK
STREAM_ROOT=/var/lib/turtle-referee/streams python3 /opt/turtle/stream/stream_ops.py purge --dry-run
# 3. Caddy 片段 + 站点块（站点块由网关那条线建；这里只加一行 import，见 player.caddy 文件头）
install -m 644 player.caddy /etc/caddy/turtle-player.caddy
caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
# 4. 装这一版（本机）
python tools/deploy.py <版本> --only player --env beta --dry-run    # 本机检查 + 服务器现状（只读）
python tools/deploy.py <版本> --only player --env beta
python tools/deploy.py <版本> --only player                         # 正式；周末拒绝（--allow-weekend 放行）
```

之后每次发版：`deploy.py` 的待办里会列「网页录像播放器」那一步；照第 4 步做。

## 检查

```bash
curl -sI https://arena.turtlearena.xyz/player/                              # 200 入口页
curl -sI https://arena.turtlearena.xyz/player/<版本>/index.html             # 200
curl -s  https://arena.turtlearena.xyz/player/streams/<id>/end.json | head -c 200   # 200，不带 Content-Encoding
curl -s -o /dev/null -w '%{http_code}\n' https://arena.turtlearena.xyz/player/expired/<id>   # 过期的 200 / 其余 404
python3 /root/deploy/player/player_ops.py status prod
```

2026-11-08 本机验过的（Caddy 2.10.2 Windows 版 + 这份片段 + 真导出产物 + 真状态流）：入口页 / 版本目录 / 块 / end.json / 过期记号的状态码与响应头逐条对；
入口页脚本在 node 里打桩跑过手机 / 有录像跳转 / 版本目录不在 / 过期 / 找不到 / hop 透传；
导出的 `index.pck` 用桌面 Godot `--main-pack` 无头跑：开机进了 WebPlayer（特性 web_player 的主场景生效）、拉完 166 块。
**发现**：`file_server { precompressed gzip }` 在 2.10.2 上对预压缩文件一律回 206 + Content-Range（请求没带 Range）⇒ 片段改用 `encode gzip`（200、ETag、304 都对）。

## 回滚

- 播放器某一版坏了：`mv -T /var/www/turtle-player/prod/<版本> /var/www/turtle-player/.prev/…`，同版本旧目录在 `/var/www/turtle-player/.prev/<env>-<版本>.prev-<时间>`，挪回去即可。
- 整个下线：站点块里删掉 `import /etc/caddy/turtle-player.caddy` 那一行 → validate → reload。主站拿不到 `playerURL` 时不显示「看录像」（20261107 §5），不挡别的。
- purge 退回：把旧 `stream_ops.py`（git 历史）装回去；过期记号目录可以直接删（之后过期的局会显示「未找到」而不是「已过期」）。

## 已知风险与未决

- **首开 151 MB**：主站内嵌页第一次打开要等。可做：WebPlayer 预设改「只导出选中的场景 + 依赖」会漏掉按路径字符串运行时 `load` 的特效资源（不可取）；可行的是按目录排除播放器用不到的菜单 / 商店 / 引导大图与背景乐，或按龟拆包（方案书原话）。
- **Godot 网页版 HTTPRequest 与 Content-Encoding**：end.json 走播放器路径时不压缩（片段里写死），块本来就不压；版本目录里 wasm / js 由 Caddy 压，那是浏览器自己解的（引擎加载器用 fetch），不经 HTTPRequest。
- **nothreads 模板**：与现有 Web 预设同一个模板（`variant/thread_support=false`），不需要 COOP / COEP。没在真浏览器里打开过（本任务规定不开浏览器）；桌面 `--main-pack` 只证明包能开机进播放器、能拉流播放，WebGL / 音频解锁 / 画布尺寸要在内测上用电脑浏览器看一次。
- **iframe**：没设 `frame-ancestors`（页面只读、没有操作，被谁嵌都无害）；要限制时在片段里加 `header Content-Security-Policy "frame-ancestors https://turtlepoll.com …"`（内测主站的域名只记在 turtlebet 仓库里，这里不写）。
- **对局号可猜性**：与 stream.turtlearena.xyz 同一个前提（uuid，录像本来就对所有人公开）。
