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
	print("分母: %d 条断言" % _n)
	print("ALL PASS" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
