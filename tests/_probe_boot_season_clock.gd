extends Node
## _probe_boot_season_clock.gd — 探针(不进门禁): 开机那一次 ensure_season() 用的是哪个钟 (2026-10-22 内测服彩排)
##
## 由来: 内测服整周彩排, 21 个模拟号在假周六一开游戏赛季就被清空(season_id 2→3, 锚点退回真实本周 10-19)。
##   推测是开机 ensure_season() 在内测服时钟偏移到达之前就用本机钟判了「跨周」—— 推测不算根因, 这里打数。
##
## 用法(每次一个干净的 APPDATA, 事先放好 savegame.json / server_clock.cfg):
##   APPDATA=<dir> XDG_DATA_HOME=<dir> [TURTLE_SERVER=beta ONLINE=1] bash godot-quiet.sh res://tests/_probe_boot_season_clock.tscn
##   · 无头且没设 SIM_DRIVER ⇒ GameState.test_mode = true ⇒ 不写存档、不登录、不推云(只读探针)。
##   · PROBE_WAIT_BETA=1   等内测服 service_status 回包把假时间偏移带回来(要 ONLINE=1 + TURTLE_SERVER=beta)
##   · PROBE_SRV_SHIFT=<秒> 模拟「服务器回包的 Date 头 = 本机钟 − 秒数」(走真传输缝 SupabaseNet._http),
##                          之后再调一次 ensure_season()(= 打完一场结算那一次 / 取回云存档那一次)
## 输出全是 [probe] 开头的行。

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SB := preload("res://scripts/net/supabase.gd")
const SE := preload("res://scripts/net/server_env.gd")
const _MON := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const _WD := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


func _day(ts: int) -> String:
	return Time.get_datetime_string_from_unix_time(ts, true).substr(0, 16)


func _gs_line(gs) -> String:
	return "season_id=%d week_anchor_ts=%d(%s) battles=%d wins=%d hearts=%d ranked_used=%d leaders=%s" % [
		int(gs.season_id), int(gs.week_anchor_ts), _day(int(gs.week_anchor_ts)), int(gs.season_total_battles),
		int(gs.season_wins), int(gs.hearts), int(gs.ranked_used), str(gs.season_leaders)]


func _clock_line() -> String:
	var real := int(Time.get_unix_time_from_system())
	var now := int(P2.now_utc())
	return "real=%d(%s) server_offset=%d known=%s beta_clock_offset=%d now_utc=%d(%s) week(now_utc)=%d(%s) asked=%d" % [
		real, _day(real), int(P2.server_offset_sec), str(P2.server_offset_known), P2.beta_clock_offset(),
		now, _day(now), P2.week_anchor_utc(now), _day(P2.week_anchor_utc(now)), SB.ask_count()]


func _http_date(ts: int) -> String:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	return "%s, %02d %s %04d %02d:%02d:%02d GMT" % [_WD[int(d["weekday"])], int(d["day"]),
		_MON[int(d["month"]) - 1], int(d["year"]), int(d["hour"]), int(d["minute"]), int(d["second"])]


func _ready() -> void:
	var t_scene := Time.get_ticks_msec()
	var gs = get_node_or_null("/root/GameState")
	print("[probe] is_beta=%s base=%s test_mode=%s" % [SE.is_beta(), SB.base_url(), str(gs.test_mode)])
	## 盘上那份(test_mode ⇒ 开机的 ensure_season 写不了盘, 所以盘上还是开机之前的样子)
	var f := FileAccess.open("user://savegame.json", FileAccess.READ)
	var disk = JSON.parse_string(f.get_as_text()) if f != null else null
	if disk is Dictionary:
		print("[probe] 盘上存档(开机前): season_id=%d week_anchor_ts=%d(%s) battles=%d wins=%d hearts=%d" % [
			int(disk.get("season_id", -1)), int(disk.get("week_anchor_ts", -1)), _day(int(disk.get("week_anchor_ts", 0))),
			int(disk.get("season_total_battles", -1)), int(disk.get("season_wins", -1)), int(disk.get("hearts", -1))])
	else:
		print("[probe] 盘上存档: 没有")
	print("[probe] A 开机后(GameState._ready 已跑完 ensure_season, t=%dms): %s" % [t_scene, _gs_line(gs)])
	print("[probe] A 时钟: %s" % _clock_line())

	if OS.get_environment("PROBE_WAIT_BETA") == "1":
		var t0 := Time.get_ticks_msec()
		var frames := 0
		while Time.get_ticks_msec() - t0 < 20000 and P2.beta_clock_offset() == 0:
			await get_tree().process_frame
			frames += 1
		print("[probe] B 内测服偏移到达: t=%dms(开机后) 等了 %d 帧 · %s" % [Time.get_ticks_msec(), frames, _clock_line()])
		print("[probe] B 此刻再算: week(now_utc)=%d(%s) vs 内存锚点 %d / 盘上锚点 %s" % [
			P2.week_anchor_utc(int(P2.now_utc())), _day(P2.week_anchor_utc(int(P2.now_utc()))), int(gs.week_anchor_ts),
			str(int(disk.get("week_anchor_ts", -1))) if disk is Dictionary else "-"])
		gs.ensure_season()
		print("[probe] B 偏移到了之后再 ensure_season(): %s" % _gs_line(gs))

	var shift_s := OS.get_environment("PROBE_SRV_SHIFT")
	if shift_s != "":
		var shift := int(shift_s)
		var dev := int(Time.get_unix_time_from_system())
		var net = SB.new()
		add_child(net)
		net._transport = func(_m, _u, _h, _b, cb):
			cb.call({"ok": true, "code": 200, "body": "[]",
				"headers": PackedStringArray(["Content-Type: application/json", "Date: " + _http_date(dev - shift)])})
		var got := [false]
		net._http("GET", "https://example.invalid/rest/v1/service_status?select=*&limit=1", "", func(_r): got[0] = true)
		var w := 0
		while not got[0] and w < 600:
			await get_tree().process_frame
			w += 1
		print("[probe] C 服务器回包到了(Date = 本机 − %d 秒, 回调=%s): %s" % [shift, str(got[0]), _clock_line()])
		gs.ensure_season()
		print("[probe] C 再 ensure_season()(= 打完一场的结算 / 取回云存档): %s" % _gs_line(gs))
	print("[probe] END")
	get_tree().quit(0)
