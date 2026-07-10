# APK 交付 + 闪退排查（2026-07-10）

> 用户〖2026-07-10〗:「出个apk，我去测试，需要注意有没有闪退问题，我上次测试时玩到一半闪退了，是不是整个流程有漏洞」
> 用户〖2026-07-10〗:「你只要给出安装包就行，我自己在安卓机上跑」

## 交付物
- `C:/Users/Louis/Desktop/turtle-realtime-v2.apk` — **170.2 MB**，arm64-v8a，**release 构建**，debug keystore 签名（可直接安装）。
- 仓库内同一份：`build/android/turtle-realtime-v2.apk`（`build/` 已被 `.gitignore`/导出排除，不入库）。

## ★ 找到的闪退真因（实测复现，不是推理）

新建 `tests/smoke_scenes.gd`，用 `SHIP=1` 跑**真实对局** 60 秒：

```
ERROR: Max recursion reached          ×26564
  at: recursive_hash (core/variant/dictionary.cpp:375 / array.cpp:197)
  GDScript backtrace: [0] _eq_chain_lightning (RealtimeBattle3DScene.gd:11930)
```

**真因**：把**单位字典**当成 `Dictionary` 的 key（`hit[first] = true` / `hit.has(o)`）。
Godot 要对 key 求哈希，而单位字典里有 `summons` / `summon_owner` 这类**互相引用**的结构 →
`recursive_hash` 无限递归 → 每次查表刷一条带栈回溯的 ERROR。

2.6 万条报错本身就把帧率拖垮：**修之前 60 秒战斗跑 110 秒墙钟都跑不完；修之后正常跑完。**
手机上就是卡死 → ANR / 闪退。

同一个病共 **4 处**（其中一处我还写了注释「字典引用作键, each-once」）：
`RealtimeBattle3DScene.gd` 的 `6603 hit2` / `8059 hit`（熔岩浪）/ `8761 hit` / `11928 hit`（雷电法杖连锁闪电）。
修法：一律改成 `Array`（`.has()` 走 `==` 不哈希，`.append()` 代替 dict-key 写入）。

> 触发条件：任何一只龟带**雷电法杖 p2eq_026**（连锁闪电）就会每次触发时刷屏；熔岩龟变身横扫、以及另外两处也各自会刷。
> 所以「玩到一半闪退」= 打到某个带该装备/技能的时点开始持续刷错，越打越卡。

### 我的测试过滤器本身漏了这个模式
前面 24 组 sim 全报「0 errors」，因为我的 BAD 正则里**根本没有 `Max recursion`**。
过滤器漏一个模式 = 把 bug 判成绿灯。已把 FATAL 模式表固化进 `run-tests.sh`。

## ★ 另一个真 bug：REVIEW_DEMO 在导出包里恒为 true

旧实现 `REVIEW_DEMO_DEFAULT and not OS.has_environment("SHIP")`。
`OS.has_environment` 是**运行时**求值 —— 玩家手机/浏览器里没有 `SHIP` 环境变量，
所以**导出的 APK / Web 包里 `_review_demo()` 恒为 true**：
- 玩家打的是沙包假人（1 受审龟 vs 3 个永不死的 `basic` 假人）
- `_unit_level()` 直接 `return 1` → **赛季等级完全不生效**

`SHIP=1 bash build-web.sh` 只影响**导出那台机器的进程环境**，对导出后的游戏毫无作用。
（我此前把「上线必须 SHIP=1 构建」写进了文档与 memory，是错的，已订正。）

**新规则**（与主菜单调试场入口 `OS.is_debug_build()` 同一套口径）：

| 场景 | `_review_demo()` |
|---|---|
| release 导出包（玩家拿到的） | **false** |
| 编辑器 / F5 / debug 导出（你审龟用的） | `REVIEW_DEMO_DEFAULT`（当前 true）|
| `SHIP=1` 环境变量 | 强制 false |
| `REVIEW=1` 环境变量 | 强制 true |

**⚠ 陷阱：`--export-debug` 出来的 APK 是 debug 构建 → `is_debug_build()=true` → 评审模式又打开。
测试包必须 `--export-release`。** 本包用 debug keystore 给 release 版签名，可直接安装。

## 出包前自检（每次都要过）

| 项 | 本次结果 |
|---|---|
| 架构 | `arm64-v8a` ✓ |
| **是 release 模板**（决定 REVIEW_DEMO 关不关）| `libgodot_android.so` = 70322664 B，与 `android_release.apk` 模板**逐字节同尺寸**（debug 模板是 75345928 B）✓ |
| `tests/` `docs/` `build/` 未被打包 | 泄漏 0 条 ✓ |
| 签名 | `CN=Android Debug` ✓（apksigner verify 通过）|
| 体积 | 170.2 MB |

> `export_presets.cfg` 的 Android 段原本 `exclude_filter=""` —— 测试脚本与文档会被打进 APK。已补齐（Web 早就排除了，Android 漏了）。
> **注意**：Godot 的 ConfigFile 注释是 `;` 不是 `#`；我用 `#` 写注释导致后面的 `keystore/*` 键被吞，报「发布密钥库必须全部填写或全部留空」。

## 已验证到哪一步（不夸大）

✅ **能确定的**
- `bash run-tests.sh` → **ALL PASS (10/10)**，含全流程冒烟：9 个场景各进出 4 次、**战斗打到一半硬 `free()` 掉整个战斗场景 ×3**、`SHIP=1` 真实对局跑满 60 秒。
- 在**真正的 release 二进制**里跑同一套冒烟：`Max recursion = 0`、`SCRIPT ERROR = 0`、跑完并正常退出。
- 在 release 二进制里打印构建模式：`is_debug_build=false → _review_demo()=false`（编辑器里是 `true/true`），**证明玩家拿到的不是沙包场**。
- 静态扫描（带阳性/阴性自检探针）：`get_meta` 无默认值 0 处、`Dictionary` 裸下标读 0 处、7 处除法**全部**有 `is_empty()` 守卫。

❌ **不能确定的（没有真机/模拟器，不吹）**
- Android 上的 **GPU / 着色器编译 / 纹理压缩（ETC2）/ 内存** 相关崩溃，headless 一律测不到。
- 触摸输入、屏幕适配、后台切换（`NOTIFICATION_APPLICATION_PAUSED`）路径。
- 真机热量/低内存导致的系统级 kill。

### 如果真机上还是闪退，请这样抓日志

```bash
# 1) 手机开开发者模式 + USB 调试，连上电脑
C:/Users/Louis/tools/android-sdk/platform-tools/adb.exe devices

# 2) 清日志 → 打开游戏 → 复现闪退
adb logcat -c
adb logcat -v time > crash.txt      # 复现后 Ctrl+C

# 3) 只看关键行
adb logcat -d | grep -iE "godot|FATAL|AndroidRuntime|libc|tombstone|Max recursion"
```
把 `crash.txt` 给我，我按栈定位。**没有这个日志，我不会说「已确保不闪退」。**

## 我否定掉的假设（避免以后又绕回去）
- 「`await` / `create_timer` 回调时节点已被 `free()` → 崩」：**实测否定**。冒烟里战斗打到一半硬 `free()` 掉整个场景 ×3，零报错 —— Godot 会把协程直接丢弃。不拿推理当结论。
- 除零：7 处全部有 `is_empty()` 守卫，且浮点除零只产生 `inf` 不崩。
