# 实时龟战 V1 · Android APK 打包（2026-07-05）

> ## ⚠ 2026-07-19 核实：出包命令与现行铁律**冲突**
> 本文「二、重新出 APK」给的是 `--export-debug`，而铁律是 **出包必须 `--export-release`**
> （见 `docs/design/实时版-系统机制权威.md` §10）。debug 构建会带调试场按钮与符号。
> 另「对手：bot 兜底（真人快照 ghost 后续接）」已过期 —— ghost 早已接上（`backend.gd` + `ghost_seed.json` 146 支）。
> 环境/SDK 路径、ETC2 开关等流程说明**仍然有效**。


> ✅ **APK 已成功产出**：`桌面\turtle-realtime-v1.apk`（181MB，包名 com.turtlebattle.realtime，应用名「斗龟场 实时版」，arm64-v8a，minSdk24/targetSdk36，debug 签名 verifies）。传手机允许「未知来源」直接装。
>
> **真因（曾卡很久）**：Android 导出一直报「配置错误」但**正文空白**——因为 Godot 只在**导出对话框 UI**里显示错误正文，headless 命令行不打印。用截图+点击驱动编辑器 GUI 打开导出对话框，才看到真提示：**「目标平台需要 ETC2/ASTC 纹理压缩，请在项目设置启用 导入 ETC2 ASTC」**。启用 `rendering/textures/vram_compression/import_etc2_astc=true`(已入库) 后，headless 一条命令就能出 APK。

## 一、已安装 / 已配置（都在 `C:\Users\Louis\tools\`，不在仓库里）
| 组件 | 位置 | 说明 |
|---|---|---|
| JDK 17 (Temurin 17.0.19) | `tools\jdk17` | keytool/apksigner 用 |
| Android SDK | `tools\android-sdk` | cmdline-tools/latest + platform-tools |
| build-tools | `…\build-tools\34.0.0` + `36.0.0` | 含 apksigner / zipalign / aapt2 |
| platforms | `…\platforms\android-34` + `android-36` | 模板 targetSdk=**36**（关键：只装34会报错） |
| debug 签名 | `AppData\Roaming\Godot\keystores\debug.keystore` | JKS，alias=androiddebugkey，pass=android |
| Godot 编辑器设置 | `editor_settings-4.6.tres` | 已填 `android_sdk_path` / `java_sdk_path` / `debug_keystore` |
| Android 导出预设 | `export_presets.cfg` [preset.1] | 包名 `com.turtlebattle.realtime`，应用名「斗龟场 实时版」，arm64-v8a，预置模板(非gradle)，沉浸式 |
| Android 导出模板 | `AppData\Roaming\Godot\export_templates\4.6.3.stable\android_*.apk` | 用户 6-22 已下载 |

## 二、重新出 APK（一条命令，headless 就行）
设置修好后不再需要 GUI。改了代码后重新打包：
```bash
export JAVA_HOME="C:\\Users\\Louis\\tools\\jdk17"
export PATH="/c/Users/Louis/tools/jdk17/bin:$PATH"
cd ~/Documents/GitHub/turtle-realtime-godot
Godot_v4.6.3-stable_win64.exe --headless --import                                      # 首次/纹理设置变了才需要
Godot_v4.6.3-stable_win64.exe --headless --export-debug "Android" "桌面路径\turtle-realtime-v1.apk"
```
产出 debug APK（debug 签名，直接可装）。传手机允许「未知来源」安装。
> 编辑器 GUI 也行：项目 → 导出 → Android → 导出项目。SDK/JDK 路径已写进 editor_settings，正常直接绿。

## 三、坑记录：那条「空白配置错误」怎么破的
- `--headless --export-debug "Android"` 一直报 `Cannot export ... due to configuration errors:` **正文空白**；排除了预设选项/build-tools/keystore/模板/图标/SDK，删 keystore 报错仍空 → **headless 不打印 Android 配置错误正文，只在导出对话框 UI 显示**。
- **破法**：这台机器其实有显示器（跑非 headless 时初始化了 RTX4070）。用 PowerShell 截屏 + 按坐标点击**驱动编辑器 GUI**打开导出对话框，一眼看到真提示：**目标平台需要 ETC2/ASTC 纹理压缩**。
- **真因 = `rendering/textures/vram_compression/import_etc2_astc` 未启用**（移动端导出必须）。启用(已入库 project.godot) → headless 一条命令成功出 APK。
- 教训：Godot 导出报「配置错误」正文空白时，别在 headless 里瞎猜，直接开编辑器导出对话框看红字。

## 四、备选：Web 版（手机浏览器直接玩，不用装）
- 已成功导出：`build/web/`（index.html + index.pck 161MB，单线程，iOS/安卓 Safari/Chrome 都能跑）。
- 玩法：把 `build/web/` 传到 itch.io（或任意静态托管）→ 手机浏览器打开网址即玩。本地直接双击 index.html 不行（需 http 服务）。
- 这是「立刻能在手机上试」的最快路径，但不是能安装的 APK。

## 五、本次 V1 里有什么（可测内容）
- **双路对局**：主菜单「开始战斗」→ 上半场 → 下半场 →（1-1）终极战场；6单位(3统领+3小将)分上/下路；龟蛋+全息围栏(AoE穿栏)；团灭破蛋10秒窗口；谁蛋先破谁输。
- **统领**：带登场被动 + 局外 `persistent_equipped` 装备（本次修复：之前双路 leader 没被动没装备）。
- **小将**：前排挥砍×1.4 / 后排射击×1.5；某路0统领→首个小将精英；装备管线已预埋（局外UI给小将配装的入口是后续项）。
- 对手：bot 兜底（真人快照 ghost 后续接）。

## 六、后续（V1 之后，需你 F5 眼验手感）
地图+障碍(navmesh绕障)、小将装备局外UI、场内自由放置阶段、蛋破碎动画、数值平衡（当前 lane 偏长/3普攻偏弱）、3版地图主题美术。
