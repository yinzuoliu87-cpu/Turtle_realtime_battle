extends Node
## 探针(2026-10-31 周日彩排 P13): 第一次进对阵图「正在查询分组」要等 20~90 秒。
## 走真场景 BracketMap.tscn + 真入口 fetch_finals_async, 网络换成注入的假传输(可调延迟, 不碰网络),
##   每 0.25 秒打一行: 进场后多少毫秒 / finals_tried / _feed_kind / 屏上那句 / 页签字 / 请求计数。
## 场景(env PROBE_CASE):
##   A  冷进: 缓存是空的, 回包 not_seated 延迟 LAT 毫秒(finals_week_view 回 buckets:[] 延迟 WLAT)
##   B  主菜单那条请求在飞的时候进来(先 finals_clear + fetch_finals_async, 再进对阵图)
##   C  分组之后: 回包是 4 人组(size > 0)
## 跑法: TURTLE_SUPABASE=" " PROBE_CASE=A LAT=700 WLAT=300 <godot> --headless --audio-driver Dummy --path . res://tests/_probe_bracket_wait.tscn

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

var _reqs := {}
var _case := "A"
var _lat := 700
var _wlat := 300


func _env_int(k: String, d: int) -> int:
	var s := OS.get_environment(k).strip_edges()
	return int(s) if s != "" else d


func _seated_body(now: int) -> String:
	var ent: Array = []
	for s in range(4):
		ent.append({"seed": s, "name": "龟%d" % s, "account_id": "uid-me" if s == 1 else "uid-%d" % s})
	return JSON.stringify({"ok": true, "bucket": 3, "n": 4, "round": 1, "closed": false,
		"round_at": now - 30, "next_at": now + 450, "now": now, "entrants": ent, "done": {}})


func _reply_for(url: String, now: int) -> Dictionary:
	if url.find("finals_week_view") >= 0:
		return {"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "week": 1, "now": now, "buckets": [], "cup": null})}
	if url.find("finals_view") >= 0:
		if _case == "C":
			return {"ok": true, "code": 200, "body": _seated_body(now)}
		return {"ok": true, "code": 200, "body": JSON.stringify({"ok": false, "reason": "not_seated", "entered": 24})}
	return {"ok": true, "code": 200, "body": "{}"}


func _transport(_m, url, _h, _b, cb) -> void:
	var u := str(url)
	var key := u.get_slice("?", 0).get_file()
	_reqs[key] = int(_reqs.get(key, 0)) + 1
	var d := _lat
	if u.find("finals_week_view") >= 0:
		d = _wlat
	elif u.find("finals_view") < 0:
		d = 200
	var now := P2C.now_utc()
	var rep := _reply_for(u, now)
	get_tree().create_timer(float(d) / 1000.0).timeout.connect(func() -> void: cb.call(rep))


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_case = OS.get_environment("PROBE_CASE").strip_edges()
	if _case == "":
		_case = "A"
	_lat = _env_int("LAT", 700)
	_wlat = _env_int("WLAT", 300)
	GameState.test_mode = true
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	GameState.account_id = "uid-me"
	SB._token = "gate-token"
	SB._transport_for_test = _transport
	var wk: int = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	P2C.now_override_ts = wk + 6 * 86400 + (17 * 3600 + 31 * 60 if _case != "C" else 18 * 3600 + 2 * 60)
	print("=== 探针 P13 case=%s  finals_view 延迟 %d ms · finals_week_view 延迟 %d ms · phase=%s ===" % [
		_case, _lat, _wlat, P2C.phase_at_utc(P2C.now_utc())])
	SB.finals_clear()
	SB.finals_week_clear()
	if _case == "B":
		## 主菜单 `_finals_title_tick` 那两行: 先清, 再发(请求在飞)
		SB.fetch_finals_async(P2C.week_anchor_utc(P2C.now_utc()), -1)
		SB.fetch_finals_week_async(P2C.week_anchor_utc(P2C.now_utc()))
		await get_tree().create_timer(0.1).timeout
		print("  进场前: finals_inflight=%s tried=%s" % [str(SB._finals_inflight), str(SB.finals_tried())])
	var t0 := Time.get_ticks_msec()
	var bm = (load("res://scenes/BracketMap.tscn") as PackedScene).instantiate()
	add_child(bm)
	var last_line := ""
	var tried_at := -1
	var screen_ok_at := -1
	while Time.get_ticks_msec() - t0 < 65000:
		await get_tree().create_timer(0.25).timeout
		var ms := Time.get_ticks_msec() - t0
		var txt: String = str(bm._empty_lb.text) if bm._empty_box != null and bm._empty_box.visible else "(图)"
		var tab: String = str((bm._tabs.get_child(0) as Button).text)
		if tried_at < 0 and SB.finals_tried():
			tried_at = ms
		## 「屏幕跟上了」= 回包到了(不再是 wait 那一档)且屏上那句就是此刻该说的那句(不抄屏幕字面量)
		if screen_ok_at < 0 and bm._feed_kind() != bm.EK_WAIT and txt == str(bm._empty_text()):
			screen_ok_at = ms
		var line := "tried=%s inflight=%s feed_kind=%s 屏=「%s」 页签=「%s」 cached=%s" % [
			str(SB.finals_tried()), str(SB._finals_inflight), bm._feed_kind(), txt, tab, str(SB.finals_cached())]
		if line != last_line:
			print("  t=%5d ms  %s  reqs=%s" % [ms, line, str(_reqs)])
			last_line = line
		if screen_ok_at >= 0 and ms > screen_ok_at + 1000:
			break
	print("RESULT case=%s lat=%d wlat=%d  回包到(tried)=%d ms  屏幕跟上(屏上那句 = 此刻的判断)=%d ms  请求=%s" % [
		_case, _lat, _wlat, tried_at, screen_ok_at, str(_reqs)])
	SB._transport_for_test = Callable()
	SB._token = ""
	P2C.now_override_ts = 0
	get_tree().quit(0)
