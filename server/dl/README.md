# 安卓直装包下载跳转（dl.turtlearena.xyz）

方案书：`docs/plans/20261118b-安卓直装包.md` A3。

```
https://dl.turtlearena.xyz/android  ──302──▶  https://github.com/<仓库>/releases/download/v<版本>/turtle-arena-<版本>.apk
```

- 给玩家 / 主站的链接永远是 `https://dl.turtlearena.xyz/android`，不随版本变；游戏里强更挡墙的安卓按钮也是它（`version_wall.gd` `STORE_URL_ANDROID`）。
- 安装包本体放在推 tag 时 `android.yml` 建的 GitHub Release 上，下载流量走 GitHub 的 CDN，不经过裁判机。
- 裁判机上两份文件：
  - `/etc/caddy/turtle-dl.caddy`：本目录 `turtle-dl.caddy` 原样（站点块）；`/etc/caddy/Caddyfile` 末尾 `import` 它一次。
  - `/etc/caddy/turtle-dl-target.caddy`：一行 `redir @android <网址> 302`；空 ⇒ `/android` 回「即将开放」(404)。

## 怎么换版本

换版窗口里（周一 21:00–23:00 英国时间，CLAUDE.md §3），TestFlight 进组之后：

```bash
python tools/deploy.py <版本> --only android --dry-run   # 只读：Release 上有没有包、DNS、现在跳到哪
python tools/deploy.py <版本> --only android             # 传片段 + 写目标 → caddy validate 过了才 reload → 回读 302 Location 与安装包大小
```

- 前置检查不过（Release 上没有 `turtle-arena-<版本>.apk` / 包小于 50 MB / DNS 没指向裁判机 / 周末）⇒ 不碰服务器。
- `caddy validate` 不过 ⇒ 三个文件按备份（`*.bak-<时间>`）还原，线上不变。
- 还没放过任何版本、只想先把站点搭起来：`python tools/deploy.py <任意版本> --only android --init`（目标为空，回读 404「即将开放」）。

## 一次性前置：DNS

Porkbun（`turtlearena.xyz`）加一条 A 记录：`dl` → 裁判机 IP。Porkbun 登录有人机验证 + 两步验证码，要用户本人登录。
没加之前 `dl.turtlearena.xyz` 落在 Porkbun 的停放页上，`deploy.py --only android` 前置检查会拦。

自测：`python tools/dl_android_selftest.py`（不连网，进门禁）。
