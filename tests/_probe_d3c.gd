extends Node
## _probe_d3c.gd —— D-3c 真 Supabase 跨进程探针（不是门禁；要真网络，手动跑）
##
## 验的是当初坏掉的那个场景本身：**重开 App 之后还能不能用**。
## 门禁（verify_session_refresh ⑤）喂的是真实形状的回包，这里打的是真服务器。
##
## 跑法（两个**独立进程**，中间就是「重开 App」）：
##   PROBE_PHASE=1 <godot> --headless --path . res://tests/_probe_d3c.tscn   ⇒ 注册, 把身份写到临时文件
##   PROBE_PHASE=2 <godot> --headless --path . res://tests/_probe_d3c.tscn   ⇒ 新进程只带着身份, 续登录 + 上传
## ★上传用 `season_week = 1`（不可能存在的周）隔离 —— `ghosts` 没有 delete 策略, 写进去就删不掉。

const SB := preload("res://scripts/net/supabase.gd")
const HANDOFF := "user://_probe_d3c_handoff.json"


func _p(s: String) -> void:
	print("[D3C] " + s)


func _wait_until(cond: Callable, sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(sec * 1000.0) and not cond.call():
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	var phase := OS.get_environment("PROBE_PHASE")
	_p("阶段 %s  后端启用=%s" % [phase, str(SB.enabled())])
	if not SB.enabled():
		get_tree().quit(1)
		return
	if phase == "1":
		await _phase1()
	else:
		await _phase2()


func _phase1() -> void:
	GameState.account_id = ""
	GameState.auth_refresh = ""
	SB._reset_auth_for_test()
	SB.ensure_signed_in_async()
	await _wait_until(func(): return str(GameState.account_id) != "", 8.0)
	_p("① 注册: account=%s  refresh长度=%d  token长度=%d" % [
		str(GameState.account_id).substr(0, 8), str(GameState.auth_refresh).length(),
		SB.access_token().length()])
	var f := FileAccess.open(HANDOFF, FileAccess.WRITE)
	f.store_string(JSON.stringify({"account_id": GameState.account_id,
		"auth_refresh": GameState.auth_refresh}))
	f.close()
	_p("① 身份写进临时文件, 本进程退出(= 关掉 App)")
	get_tree().quit(0 if str(GameState.auth_refresh) != "" else 1)


func _phase2() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(HANDOFF))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HANDOFF))
	if not (d is Dictionary):
		_p("没有交接文件, 先跑阶段 1")
		get_tree().quit(1)
		return
	## = 重开 App: 新进程, 内存里没有 token, 存档里带着身份与续期令牌
	GameState.account_id = str(d["account_id"])
	GameState.account_email = ""
	GameState.auth_refresh = str(d["auth_refresh"])
	_p("② 新进程: 内存 token 长度=%d(应为 0)  账号=%s" % [SB.access_token().length(),
		str(GameState.account_id).substr(0, 8)])
	var old_rt := str(GameState.auth_refresh)
	SB.ensure_signed_in_async()
	await _wait_until(func(): return SB.access_token() != "", 8.0)
	_p("② 续登录后: token长度=%d  还是同一个号=%s  refresh轮换了=%s" % [
		SB.access_token().length(), str(str(GameState.account_id) == str(d["account_id"])),
		str(str(GameState.auth_refresh) != old_rt)])

	## 需要登录的真请求: 上传一行(隔离周)
	SB._reset_upload_for_test()
	var row := SB.ghost_row_from_snapshot({"ghost_id": "g_probe_d3c", "season_total_battles": 2},
		str(GameState.account_id), 1, 2, "probe-d3c")
	SB.upload_ghost_async(row)
	await _wait_until(func(): return SB.upload_try_count() > 0, 8.0)
	_p("② 重开后上传: try=%d ok=%d(旧代码这里是 401)" % [SB.upload_try_count(), SB.upload_ok_count()])
	var passed := SB.access_token() != "" and SB.upload_ok_count() == 1 \
		and str(GameState.account_id) == str(d["account_id"])
	_p("══ 重开 App 之后还能用: %s" % ("通过" if passed else "★没通过"))
	get_tree().quit(0 if passed else 1)
