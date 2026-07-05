# 实时龟战 V1 · Android APK 打包（2026-07-05）

> 目标：打包能装进安卓手机测试的 APK V1。**工具链已全部装好并配好**，但命令行(headless)导出被 Godot 一个「不显示具体内容的配置错误」挡住；**用 Godot 编辑器 GUI 一键导出即可**（GUI 会显示真正的错误或直接成功）。

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

## 二、一键出 APK（在你的电脑上，Godot 编辑器里）
1. 用 **Godot 4.6.3** 打开 `turtle-realtime-godot`。
2. 顶部菜单 **项目 → 导出…**。
3. 选左侧 **Android**（预设已建好，若显示红字错误——那就是 headless 看不到的那条，按提示点一下缺的东西，通常是自动补全 SDK/JDK 路径，我已填好应能直接绿）。
4. 点 **导出项目** → 存成 `turtle-realtime-v1.apk`（**取消勾选**「以调试模式导出」不影响，debug 版可直接装）。
5. 传到安卓手机，允许「未知来源」安装即可。

> 若 Android 预设里 SDK/JDK 路径为空：编辑器 **编辑器 → 编辑器设置 → 导出 → Android**，SDK 填 `C:\Users\Louis\tools\android-sdk`，JDK 填 `C:\Users\Louis\tools\jdk17`（已写入配置，正常无需再填）。

## 三、为什么命令行没直接出成
- `godot --headless --export-debug "Android" out.apk` 一直报 `Cannot export project ... due to configuration errors:` **但错误正文是空的**。
- 已逐一排除：预设选项（最小预设同样失败）、build-tools 版本（补了 36）、keystore 格式（PKCS12/JKS 都试）、模板缺失（Web 同目录模板能导出，证明模板在）、图标、SDK 工具齐全。
- **实测：把 keystore 删掉，报错正文依旧是空** → 证实 **4.6.3 的 headless 模式把 Android 配置错误正文全吞了**，只有编辑器 GUI 的导出对话框能显示。所以命令行这条路在这台环境（无显示器、跑 headless）走不通，**GUI 一键即可**。

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
