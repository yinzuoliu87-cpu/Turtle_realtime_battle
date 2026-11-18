# 网页录像播放器性能测量台（2026-11-18 · 方案书 docs/plans/20261118d-网页播放器卡顿.md）

只读、只在本机跑；不连正式服写任何东西。

| 脚本 | 做什么 |
|---|---|
| `bench.py fetch <仓库根> <对局号>` | 从正式播放器站点把一局的 end.json + 全部块拉到 `.out/webperf/streams/<对局号>/`（只发 GET） |
| `bench.py serve <仓库根> [端口]` | 本机静态站：`/player/<版本>/` = `build/webplayer/`（`bash build-web.sh player` 出的），`/player/streams/` = 上面拉下来的 |
| `gputrace.py <仓库根> <网址> [秒]` | 另起一个独立 Chrome（`.out/webperf/chrome_profile`、静音、右屏），用 DevTools 协议抓 GPU 追踪到 `.out/webperf/gputrace.json`；删掉那个配置目录 = 模拟第一次来看的人 |
| `analyze.py <gputrace.json>` | 按事件名汇总：着色器编译（D3DCompile）、链接等待、贴图上传…… 列最长的 |
| `vfps.py <输出前缀> [秒]` | 录右屏一块区域数「画面真变了」的帧数。**注意：gdigrab 自己只录得到约 35 帧/秒，量不了高帧率，只用来比较** |

播放器网址带 `perf=1` ⇒ 左上角性能读数（长帧拆脚本段 / 其余段）；桌面原生跑同一页：环境变量 `WEBPLAYER_PERF=1 WEBPLAYER_MATCH=<对局号> WEBPLAYER_ORIGIN=http://127.0.0.1:8765`，长帧打 `[hitch]` 行到标准输出。
