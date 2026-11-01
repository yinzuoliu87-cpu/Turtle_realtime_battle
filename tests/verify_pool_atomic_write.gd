extends Node
## verify_pool_atomic_write.gd —— 快照池缓存(user://ghost_pool.json)写到一半被杀, 盘上也不能是半截(2026-10-31)
##
## 起因: 正式服 client_errors 一周 4 次「JSON 解析失败」, 全是陪练号 —— 调度器停号 = 直接杀进程,
##   而 `Backend.save_pool` 原来先 open(WRITE)(当场清空)再拼 JSON ⇒ 拼的那段时间盘上是空文件。
## 改法: 先写 .tmp 再改名(原子)。
##
## ★判据量的是需求本身「任何时刻被杀, 盘上那份都能完整读出来」, 不是读源码:
##   起一个真的子进程不停 save_pool 一份几 MB 的池子, 在随机时刻硬杀(OS.kill), 再读盘。
##   每一轮先放好一份完整的旧池 ⇒ 子进程还没写完第一份就被杀也该读到旧的。
## ★整份测试在 _ready 里同步跑(OS.delay_msec 轮询), 不吃帧 ⇒ 与 --quit-after 帧预算无关。
## ★Windows 上 Godot 的改名是「先删旧文件再移动」(drivers/windows/dir_access_windows.cpp:303),
##   中间有微秒级的「文件不在」; 那不是半截文件(读池会回落空池, 不报解析错), 单独计数、不判红。
##   Linux(陪练号跑在这上面)/ iOS 的 rename(2) 是原子替换 ⇒ 那里应当一次都不缺。

const Backend := preload("res://scripts/net/backend.gd")
const Child := preload("res://tests/_pool_writer_child.gd")
const TRIALS := 6

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _rm(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## 读盘: "ok" = 完整(行数对) / "missing" = 文件不在 / "corrupt" = 读出来不是一份完整的池
func _check() -> String:
	if not FileAccess.file_exists(Child.PATH):
		return "missing"
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(Child.PATH)) != OK or not (j.data is Dictionary):
		return "corrupt"
	var by: Dictionary = (j.data as Dictionary).get(Backend.POOL_KEY, {})
	var arr = by.get("8", [])
	return "ok" if arr is Array and (arr as Array).size() == Child.ROWS else "corrupt"


## ② 盘上已经是坏的(旧版本被杀留下的空的 / 半截的, 或别的原因)⇒ 开机自愈(2026-11-01, Backend.heal_pool_cache):
##   挪到 .bad(原样一个字节不差)、自愈那一下**不报引擎错**; 挪完之后读池不再碰它(原来 `load_pool` 的 JSON.parse_string
##   每读一次报一条「Parse JSON failed」进 client_errors —— 正式服那 5 条)、按空池(+ 内置种子)走; 写一份好的之后照常读回。
##   对照: 完整的池 ⇒ 自愈不动它(原地、不产生 .bad), 读回行数对。
## ★不改 `load_pool` 本身: 它在积分赛读池 / 挑对手的路上, 被 verify_gauntlet_online_queue R 段逐字节钉着(用户「积分赛不许动」)。
## ③ 真开机: 子进程用一份放了坏缓存的空 user:// 起来(GameState._ready 里调自愈)⇒ 子进程退出后坏文件已挪到 .bad。
##   分母: 子进程真用的是这个目录(它写出了 running.flag / savegame.json)。
const HEAL_PATH := "user://pool_selfheal_test.json"


class _Cap extends Logger:
	var msgs: Array = []
	var _mx := Mutex.new()
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		msgs.append("%s %s" % [code, rationale])
		_mx.unlock()
	# zero-caller-ok: Logger 引擎虚函数, 由引擎调
	func _log_message(_message: String, _error: bool) -> void:
		pass
	func size() -> int:
		_mx.lock()
		var k := msgs.size()
		_mx.unlock()
		return k


## 一份能读回的小池: 场次 97 这一格(内置种子里没有这一格), 每行带当前 schema_ver(否则读池时当老版本整批丢掉)。
const HEAL_ROWS := 50


func _heal_pool(tag: int) -> Dictionary:
	var arr: Array = []
	for i in HEAL_ROWS:
		arr.append({"name": "heal-%02d" % i, "schema_ver": Backend.SCHEMA_VER, "season_total_battles": 97, "tag": tag})
	return {Backend.POOL_KEY: {"97": arr}}


func _heal_rows(pool: Dictionary) -> int:
	var arr = (pool.get(Backend.POOL_KEY, {}) as Dictionary).get("97", [])
	var k := 0
	if arr is Array:
		for g in arr:
			if g is Dictionary and str((g as Dictionary).get("name", "")).begins_with("heal-"):
				k += 1
	return k


func _bad_cases() -> Dictionary:
	var good := JSON.stringify(_heal_pool(7))
	return {
		"空文件(被杀在清空之后)": "",
		"半截(被杀在写到一半)": good.left(good.length() / 2),
		"乱码": "\u0001\u0002garbage{{{",
		"合法 JSON 但不是池(数组)": "[1, 2, 3]",
	}


func _part_self_heal() -> void:
	var cap := _Cap.new()
	OS.add_logger(cap)
	var cases := _bad_cases()
	var n_cases := 0
	for nm in cases:
		_rm(HEAL_PATH); _rm(HEAL_PATH + ".bad")
		var f := FileAccess.open(HEAL_PATH, FileAccess.WRITE)
		f.store_string(str(cases[nm])); f.close()
		var bytes0 := FileAccess.get_file_as_bytes(HEAL_PATH)
		var e0 := cap.size()
		var healed: bool = Backend.heal_pool_cache(HEAL_PATH)
		var e1 := cap.size()
		var moved: bool = not FileAccess.file_exists(HEAL_PATH) and FileAccess.file_exists(HEAL_PATH + ".bad") \
			and FileAccess.get_file_as_bytes(HEAL_PATH + ".bad") == bytes0
		var p1: Dictionary = Backend.load_pool(HEAL_PATH)
		var e2 := cap.size()
		n_cases += 1
		_ok("★② 坏文件「%s」: 自愈认出它是坏的、原样挪到 .bad、原位置不再有它" % nm, healed and moved)
		_ok("★★② 坏文件「%s」: 自愈那一下不报引擎错" % nm, e1 == e0, str(cap.msgs.slice(e0, e1)))
		_ok("★★② 坏文件「%s」: 自愈之后读池不报引擎错(原来每读一次报「Parse JSON failed」)、是一份能用的池" % nm,
			e2 == e1 and p1.has(Backend.POOL_KEY), str(cap.msgs.slice(e1, e2)))
	## 挪走之后写一份好的 ⇒ 照常读回(自愈的终点)
	Backend.save_pool(_heal_pool(9), HEAL_PATH)
	var e3 := cap.size()
	var n_back := _heal_rows(Backend.load_pool(HEAL_PATH))
	_ok("② 自愈之后写回一份完整的 ⇒ 读回 %d 行、没报错" % HEAL_ROWS, n_back == HEAL_ROWS and cap.size() == e3, "%d 行" % n_back)
	## 对照: 好文件自愈不动它、不产生 .bad
	_rm(HEAL_PATH + ".bad")
	var bytes_good := FileAccess.get_file_as_bytes(HEAL_PATH)
	var e4 := cap.size()
	var healed_good: bool = Backend.heal_pool_cache(HEAL_PATH)
	var n_again := _heal_rows(Backend.load_pool(HEAL_PATH))
	_ok("② 对照: 完整的池 ⇒ 自愈不动它(原地、字节不变、不产生 .bad)、读回行数对", not healed_good and n_again == HEAL_ROWS
		and FileAccess.get_file_as_bytes(HEAL_PATH) == bytes_good and not FileAccess.file_exists(HEAL_PATH + ".bad")
		and cap.size() == e4, "%d 行" % n_again)
	_ok("② 对照: 没有缓存文件 ⇒ 自愈什么都不做", not Backend.heal_pool_cache("user://pool_selfheal_absent.json"))
	_ok("② 分母: 坏文件 %d 种都量了" % cases.size(), n_cases == 4)
	OS.remove_logger(cap)
	_rm(HEAL_PATH); _rm(HEAL_PATH + ".bad"); _rm(HEAL_PATH + ".tmp")


## ③ 真开机: 一份空 user:// 里先放一个半截的 ghost_pool.json, 用它起一个子进程(空场景, 10 帧就退)。
func _part_boot_heal() -> void:
	var root := ProjectSettings.globalize_path("user://").path_join("pool_heal_boot_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(root)
	var appname := str(ProjectSettings.get_setting("application/config/name"))
	var ud := root.path_join("Godot/app_userdata").path_join(appname) if OS.get_name() == "Windows" \
		else root.path_join("godot/app_userdata").path_join(appname)
	DirAccess.make_dir_recursive_absolute(ud)
	var pool_file := ud.path_join(Backend.POOL_PATH.get_file())
	var raw: String = str(_bad_cases()["半截(被杀在写到一半)"])
	var f := FileAccess.open(pool_file, FileAccess.WRITE)
	f.store_string(raw); f.close()
	var bytes0 := FileAccess.get_file_as_bytes(pool_file)
	var keep := {}
	for k in ["APPDATA", "XDG_DATA_HOME", "TURTLE_SUPABASE"]:
		keep[k] = [OS.has_environment(k), OS.get_environment(k)]
	OS.set_environment("APPDATA", root)
	OS.set_environment("XDG_DATA_HOME", root)
	OS.set_environment("TURTLE_SUPABASE", " ")
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--audio-driver", "Dummy", "--path",
		ProjectSettings.globalize_path("res://"), "res://tests/_blank_scene.tscn", "--quit-after", "10"])
	for k in keep:
		if bool(keep[k][0]):
			OS.set_environment(k, str(keep[k][1]))
		else:
			OS.unset_environment(k)
	var t0 := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < 60000:
		OS.delay_msec(50)
	## 引擎开机就在 user://logs 下写 godot.log(与自愈无关)⇒ 它在 = 子进程真用的是这个目录
	var used: bool = FileAccess.file_exists(ud.path_join("logs/godot.log"))
	_ok("③ 分母: 子进程起来并退出了、用的就是这个 user://(引擎在这里写了 logs/godot.log)", pid > 0 and used and not OS.is_process_running(pid),
		"pid=%d dir=%s" % [pid, ud])
	var moved: bool = not FileAccess.file_exists(pool_file) and FileAccess.file_exists(pool_file + ".bad") \
		and FileAccess.get_file_as_bytes(pool_file + ".bad") == bytes0
	_ok("★★③ 真开机: 上次留下的半截快照池缓存已挪到 .bad(GameState._ready 调了自愈)", moved)
	for sub in ["logs", ""]:
		for fn in DirAccess.get_files_at(ud.path_join(sub)):
			DirAccess.remove_absolute(ud.path_join(sub).path_join(fn))


func _ready() -> void:
	print("=== 快照池缓存原子写(写到一半被杀) ===")
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var started := 0
	var tally := {"ok": 0, "missing": 0, "corrupt": 0}
	var writes_seen: Array = []
	for i in TRIALS:
		_rm(Child.MARK)
		_rm(Child.PATH + ".tmp")
		Backend.save_pool(Child.big_pool(-1), Child.PATH)   # 一份完整的旧池
		var pid := OS.create_process(exe, ["--headless", "--audio-driver", "Dummy", "--path", proj,
			"res://tests/_pool_writer_child.tscn"])
		if pid <= 0:
			print("  第 %d 轮: 起不了子进程" % i)
			continue
		## 等子进程至少完整写过 2 份(说明它已进入「不停写」的循环), 最多 40 秒
		var t0 := Time.get_ticks_msec()
		var n := 0
		while Time.get_ticks_msec() - t0 < 40000:
			if FileAccess.file_exists(Child.MARK):
				n = int(FileAccess.get_file_as_string(Child.MARK))
				if n >= 2:
					break
			OS.delay_msec(20)
		if n < 2:
			OS.kill(pid)
			print("  第 %d 轮: 子进程 40 秒内没开始写(n=%d)" % [i, n])
			continue
		started += 1
		OS.delay_msec(rng.randi_range(0, 400))
		OS.kill(pid)
		OS.delay_msec(300)   # 等句柄放掉
		var st := _check()
		tally[st] += 1
		writes_seen.append(n)
		print("  第 %d 轮: 子进程已写完 %d 份后被杀 ⇒ 盘上 %s" % [i, n, st])
	_rm(Child.MARK)
	_rm(Child.PATH)
	_rm(Child.PATH + ".tmp")
	_ok("★分母: %d 轮里真的在「不停写」时杀掉了 ≥ %d 轮" % [TRIALS, TRIALS - 1], started >= TRIALS - 1,
		"杀到 %d 轮 · 每轮杀前已写完 %s 份" % [started, str(writes_seen)])
	_ok("★★被杀之后盘上没有一次是空的 / 半截的", int(tally["corrupt"]) == 0, str(tally))
	if OS.get_name() != "Windows":
		_ok("非 Windows(rename 原子替换): 文件一次都不缺", int(tally["missing"]) == 0, str(tally))
	_part_self_heal()
	_part_boot_heal()
	print("分母: %d 条断言" % _n)
	print("ALL PASS" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
