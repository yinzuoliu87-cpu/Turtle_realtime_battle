extends Node
## verify_sim_exit_clean.gd — 补格子的陪练号「配上就下线」走的是正常退出: 不留闪退标记, 下次开机不报 unclean_exit。
## 2026-11-01 U3(方案书 docs/plans/20261031b-闯关赛开局铺号与早兜底.md §10)。
##
## 起真的子进程(独立 user://): 子进程开机 ⇒ ErrorReporter 写运行标记 user://running.flag; 子进程挂真的 sim_driver、
##   调 `_finish("exit_on_pair")`(与 SIM_EXIT_ON_PAIR 配上就下线同一条路: SIM_QUIT_WHEN_DONE=1 ⇒ 3 秒后 get_tree().quit())。
##   ① 正常退出: 子进程自己退了、退出码 0、开机时标记在、退出后标记没了 ⇒ 下次开机 `_check_unclean_exit` 不排 unclean_exit
##   ② 对照(尺子): 同一个子进程不退、被硬杀(= 调度器原来停号的方式)⇒ 标记留着 ⇒ 下次开机会排 unclean_exit
##      (再起一个子进程开机, 读它排进队列的那一条 —— 用的就是 ErrorReporter 真的判定)
## 反向验证: 子进程不调 _finish 而是硬杀 ⇒ ① 红(标记留着)。

const MARK := "sim_exit_child.txt"
const FLAG := "running.flag"

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print("  [%s] %s %s" % ["PASS" if cond else "FAIL", name, detail])
	if not cond:
		_fail += 1


## 起一个子进程(独立 user://), 返回 [pid, 它的 user:// 目录]。
func _spawn(root: String, hang: bool) -> Array:
	var appname := str(ProjectSettings.get_setting("application/config/name"))
	var ud := root.path_join("Godot/app_userdata").path_join(appname) if OS.get_name() == "Windows" \
		else root.path_join("godot/app_userdata").path_join(appname)
	var keep := {}
	for k in ["APPDATA", "XDG_DATA_HOME", "TURTLE_SUPABASE", "SIM_QUIT_WHEN_DONE", "CHILD_HANG"]:
		keep[k] = [OS.has_environment(k), OS.get_environment(k)]
	OS.set_environment("APPDATA", root)
	OS.set_environment("XDG_DATA_HOME", root)
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("SIM_QUIT_WHEN_DONE", "1")
	OS.set_environment("CHILD_HANG", "1" if hang else "")
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--audio-driver", "Dummy", "--path",
		ProjectSettings.globalize_path("res://"), "res://tests/_sim_exit_child.tscn", "--quit-after", "100000"])
	for k in keep:
		if bool(keep[k][0]):
			OS.set_environment(k, str(keep[k][1]))
		else:
			OS.unset_environment(k)
	return [pid, ud]


func _wait_mark(ud: String, ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if FileAccess.file_exists(ud.path_join(MARK)):
			return true
		OS.delay_msec(50)
	return false


func _ready() -> void:
	print("=== 补格子的陪练号配上就下线 = 正常退出(不留闪退标记) ===")
	var base := ProjectSettings.globalize_path("user://").path_join("sim_exit_%d" % Time.get_ticks_usec())
	## ① 正常退出
	var r1 := base.path_join("normal")
	DirAccess.make_dir_recursive_absolute(r1)
	var s1 := _spawn(r1, false)
	var pid1: int = s1[0]
	var ud1: String = s1[1]
	var t0 := Time.get_ticks_msec()
	while pid1 > 0 and OS.is_process_running(pid1) and Time.get_ticks_msec() - t0 < 90000:
		OS.delay_msec(100)
	var exited := pid1 > 0 and not OS.is_process_running(pid1)
	var code := OS.get_process_exit_code(pid1) if exited else -999
	var mark1 := FileAccess.get_file_as_string(ud1.path_join(MARK)) if FileAccess.file_exists(ud1.path_join(MARK)) else ""
	_ok("① 分母: 子进程起来了、开机时写了运行标记(%s)、自己退了(用时 %.1f 秒)" % [mark1, (Time.get_ticks_msec() - t0) / 1000.0],
		exited and mark1 == "flag=1", "pid=%d dir=%s" % [pid1, ud1])
	_ok("★① 走 sim_driver `_finish(\"exit_on_pair\")` 正常退出: 退出码 0、运行标记没了(下次开机不报 unclean_exit)",
		exited and code == 0 and not FileAccess.file_exists(ud1.path_join(FLAG)), "code=%d flag=%s" % [code, FileAccess.file_exists(ud1.path_join(FLAG))])
	## 驱动自己记的那一行(收工原因)
	var ev := FileAccess.get_file_as_string(ud1.path_join("sim_events.jsonl")) if FileAccess.file_exists(ud1.path_join("sim_events.jsonl")) else ""
	_ok("① 驱动事件里记了收工原因 exit_on_pair", ev.find("\"why\":\"exit_on_pair\"") >= 0, ev.right(200))
	## ② 对照: 硬杀 ⇒ 标记留着 ⇒ 下次开机排 unclean_exit
	var r2 := base.path_join("killed")
	DirAccess.make_dir_recursive_absolute(r2)
	var s2 := _spawn(r2, true)
	var pid2: int = s2[0]
	var ud2: String = s2[1]
	var up := _wait_mark(ud2, 60000)
	if pid2 > 0:
		OS.kill(pid2)
	OS.delay_msec(500)
	_ok("② 尺子: 同一个子进程被硬杀 ⇒ 运行标记留着(下次开机会报 unclean_exit)", up and FileAccess.file_exists(ud2.path_join(FLAG)),
		"up=%s flag=%s" % [up, FileAccess.file_exists(ud2.path_join(FLAG))])
	## 清理
	for d in [ud1, ud2]:
		for sub in ["logs", ""]:
			for fn in DirAccess.get_files_at(d.path_join(sub)):
				DirAccess.remove_absolute(d.path_join(sub).path_join(fn))
	print("ALL PASS (%d)" % _n if _fail == 0 and _n >= 4 else "FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
