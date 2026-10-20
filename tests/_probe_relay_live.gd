extends Node
## 大陆中转第一阶段 · 真网络实测(下划线开头: 不是门禁, 不进 run-tests)。只发只读请求, 不登录、不写库。
##   TURTLE_RELAY=https://stream.turtlearena.xyz:8443 RELAY_CHUNK=<match_id> bash godot-quiet.sh res://tests/_probe_relay_live.tscn --quit-after 20000
##   ★不要设 TURTLE_SUPABASE(那样只剩一条入口); GameState.test_mode=true 挡住 20 秒一拍的自动登录。
## 量: ① 真竞速(两条入口各自耗时与胜者)② 经产品出口 `_http` 分别走直连 / 中转各 GET service_status 5 次
##     ③ 走中转的直播入口(stream_watch.base_url)用 StreamSource.Http 拉一块, 打印字节数与 sha256。

const SB := preload("res://scripts/net/supabase.gd")
const NR := preload("res://scripts/net/net_route.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")


func _fetch(path: String) -> Array:
	var box := {"done": false, "res": {}}
	var n = SB._spawn()
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	n._http("GET", SB.base_url() + path, "", func(res: Dictionary) -> void:
		box["res"] = res
		box["done"] = true)
	while not bool(box["done"]) and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
	var ms := Time.get_ticks_msec() - t0
	if is_instance_valid(n):
		n.queue_free()
	return [int((box["res"] as Dictionary).get("code", 0)), ms]


func _ready() -> void:
	GameState.test_mode = true
	await get_tree().process_frame
	print("入口表 ", NR.routes())
	var t := SB.new()
	NR.kick(t._headers())
	t.free()
	var t0 := Time.get_ticks_msec()
	while NR.races == 0 and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	print("竞速 胜者=", NR.last_winner, " 明细=", NR.last_race)
	for b in NR.routes():
		NR._force_for_test(b)
		var line := []
		for i in 5:
			var r: Array = await _fetch("/rest/v1/service_status?select=*&limit=1")
			line.append("%d/%dms" % [r[0], r[1]])
		print("出口_http GET service_status 经 ", b, " : ", line)
	NR._force_for_test(NR.routes()[NR.routes().size() - 1])
	var mid := OS.get_environment("RELAY_CHUNK")
	if mid != "":
		var base := SW.base_url()
		var src := StreamSource.Http.new(base, mid, {"finished": true, "giveup_sec": 5.0})
		var t1 := Time.get_ticks_msec()
		while src.state == "fetching" and Time.get_ticks_msec() - t1 < 15000:
			await get_tree().process_frame
		var c: PackedByteArray = src.chunk(0)
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(c)
		print("直播 经 ", base, " 状态=", src.state, " 块数=", src.fetched(), " 字节=", c.size(), " 请求=", src.requests,
			" 耗时=", Time.get_ticks_msec() - t1, "ms sha256=", ctx.finish().hex_encode())
	print("RELAY LIVE PROBE DONE")
	get_tree().quit(0)
