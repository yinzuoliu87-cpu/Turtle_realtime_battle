class_name SaveIso
extends RefCounted
## 存档隔离闸(2026-11-13)—— 测试 / 台子进程在**玩家真目录**上一律不写存档。
##
## 起因: 11-12 用户电脑「无法连接服务器」—— 真存档被测试假号覆盖(account_id 11111111-2222-4333-8444-555555555555,
##   昵称「小雪」; 备份在 user:// 的 `污染备份-20261112-假账号/`)。23 条测试为了量存档会主动
##   `test_mode = false` 再 `save()`(例: verify_ghost_upload_retry, 用的正是这个号); 门禁里每条测试一份临时 user://,
##   不出事, 但只要有人不带 APPDATA / XDG_DATA_HOME 单跑其中一条, 就写进玩家真存档。
##   「每次记得带隔离」这道防线已经塌过三次(`.bak-20260710-被测试污染` / `污染备份-20261029` / `污染备份-20261112-假账号`)。
## ⇒ GameState 开机判出「这是测试 / 台子进程」(save_guard_reason 非空: 无头 / NO_SAVE / 命令行指定场景)时记在 `harness`;
##   之后不管 test_mode 被谁关掉, 只要 user:// 还是这台机器的默认目录, `save()` 就拒写并报错。
##   真玩家进程开机判据为空 ⇒ `blocks_save()` 恒 false, 行为不变。服务器上的裁判 / 陪练号都把 XDG_DATA_HOME 指到自己的目录。
## ★零依赖(只用 OS): GameState 是开机就载的 autoload, 这里不许牵出别的系统(11-13 EquipCk 那次的教训)。

## 开机时 GameState.apply_save_guard 记下的原因("" = 不是测试 / 台子进程)。
static var harness := ""
static var _warned := false
## 门禁专用: 让 on_default_dir() 当作「是默认目录」, **不动环境变量**。
## ★别在测试里改 APPDATA / XDG_DATA_HOME 来模拟: Windows 上 Godot 每次访问 user:// 都按当时的 APPDATA 重新解析,
##   进程里把它改成真目录 = 之后的读写真的落到玩家目录(11-13 第一版 verify_save_iso 就这样覆盖了用户真存档)。
static var assume_default_for_test := false


## 纯判据: 这组环境变量下, user:// 是不是这台机器上玩家的默认目录(没被 APPDATA / XDG_DATA_HOME 指走)。
##   Windows: user:// = %APPDATA%/Godot/app_userdata/<项目>; 默认 APPDATA = %USERPROFILE%\AppData\Roaming。
##   其余: user:// = $XDG_DATA_HOME/godot/…; 没设就是 $HOME/.local/share。
##   拿不准(变量缺)一律当默认目录 —— 宁可测试里少写一次, 也不写玩家的档。
static func is_default_dir(os_name: String, appdata: String, userprofile: String, xdg: String, home: String) -> bool:
	if os_name == "Windows":
		var ad := appdata.replace("\\", "/").trim_suffix("/").to_lower()
		var up := userprofile.replace("\\", "/").trim_suffix("/").to_lower()
		return ad == "" or up == "" or ad == up + "/appdata/roaming"
	var x := xdg.trim_suffix("/")
	return x == "" or x == home.trim_suffix("/") + "/.local/share"


## 本进程现在的环境下 user:// 是不是默认目录。
static func on_default_dir() -> bool:
	if assume_default_for_test:
		return true
	return is_default_dir(OS.get_name(), OS.get_environment("APPDATA"), OS.get_environment("USERPROFILE"),
		OS.get_environment("XDG_DATA_HOME"), OS.get_environment("HOME"))


## GameState.save() 调: true = 这次不许写(测试 / 台子进程 + 默认目录)。第一次拒写时报一次错。
static func blocks_save() -> bool:
	if harness == "" or not on_default_dir():
		return false
	if not _warned:
		_warned = true
		push_error("[存档隔离] 测试 / 台子进程(%s)关了 test_mode 但 user:// 是玩家真目录 ⇒ 拒写存档。单跑测试要带 APPDATA=<临时目录> XDG_DATA_HOME=<临时目录>(CLAUDE.md §2)" % harness)
	return true
