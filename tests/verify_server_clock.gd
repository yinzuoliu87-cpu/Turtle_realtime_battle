extends Node
## verify_server_clock.gd — 周赛程跟服务器时间走, 不信手机时钟 (2026-10-05)
##
## 方案书 docs/plans/20260916-大轮赛制v2周赛制.md §8 E1 / Q2 选 b。
## `phase2_config.now_utc()` = 本机时钟 + 服务器偏移(偏移由 `SupabaseNet._http` 从回包 `Date` 头测得, 落盘)。
##
## 「本机钟往前/往后拨 3 天」无法真去拨系统钟 ⇒ 等价造法: 让服务器回包的 `Date` 说「真实时刻 = 本机 ∓ 3 天」
##   (相对于服务器, 本机钟就是拨了 ±3 天)。量的是**真入口**: 回包走 `SupabaseNet._http` 的传输缝, 不直接调 note。
##   ① 本机快 3 天 ⇒ now_utc() == 真实时刻, 周锚点 / 赛程阶段 / GameState.is_season_expired 都按真实时刻
##   ② 本机慢 3 天 ⇒ 同上
##      分母: ①② 至少一条里「本机钟的周锚点」≠「真实时刻的周锚点」(否则测的是同一周, 判据空转)
##   ③ 没网(传输失败) ⇒ 偏移不动; 重开游戏(清内存从盘读) ⇒ 还是上次的偏移
##   ④ 开发包时间穿越优先(穿越中 now_utc 走穿越, 不叠服务器偏移); now_override_ts 更优先
##   ⑤ 钟准的手机(±2 秒内) ⇒ 偏移 0; 从没连上过 ⇒ now_utc 就是本机钟
##   ⑥ Date 头解析
##
## 跑法: TURTLE_BACKEND=" " TURTLE_SUPABASE=" " <godot> --headless --path . res://tests/verify_server_clock.tscn --quit-after 600

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SB := preload("res://scripts/net/supabase.gd")

var _n := 0
var _fail := 0
const DAY := 86400
const _MON := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const _WD := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])


func _dev() -> int:
	return int(Time.get_unix_time_from_system())


func _http_date(ts: int) -> String:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	return "%s, %02d %s %04d %02d:%02d:%02d GMT" % [_WD[int(d["weekday"])], int(d["day"]),
		_MON[int(d["month"]) - 1], int(d["year"]), int(d["hour"]), int(d["minute"]), int(d["second"])]


## 走真传输缝发一次请求, 回包带 `Date: <srv_ts>`(srv_ts<=0 ⇒ 模拟没网)。
func _round_trip(srv_ts: int) -> void:
	var net = SB.new()
	add_child(net)
	net._transport = func(_m, _u, _h, _b, cb):
		if srv_ts <= 0:
			cb.call({"ok": false, "code": 0, "body": ""})
		else:
			cb.call({"ok": true, "code": 200, "body": "[]",
				"headers": PackedStringArray(["Content-Type: application/json", "Date: " + _http_date(srv_ts)])})
	var got := [false]
	net._http("GET", "https://example.invalid/rest/v1/service_status?select=*&limit=1", "",
		func(_res): got[0] = true)
	_ok("  (传输回调到了)", got[0])
	net.queue_free()


func _ready() -> void:
	print("== verify_server_clock ==")
	P2.now_override_ts = 0
	P2.travel_reset()
	P2.server_clock_reset()

	## ⑥ 解析
	_ok("⑥ Date 头解析", P2.parse_http_date("Mon, 05 Oct 2026 08:19:12 GMT") == 1791188352,
		str(P2.parse_http_date("Mon, 05 Oct 2026 08:19:12 GMT")))
	_ok("⑥ 坏 Date 头 ⇒ -1", P2.parse_http_date("garbage") == -1)
	_ok("⑥ 往返", P2.parse_http_date(_http_date(1791188352)) == 1791188352)

	## ⑤ 从没连上过 ⇒ 本机钟
	_ok("⑤ 从没连上过 ⇒ now_utc == 本机钟", absi(P2.now_utc() - _dev()) <= 1, "%d vs %d" % [P2.now_utc(), _dev()])
	_ok("⑤ 从没连上过 ⇒ known=false", not P2.server_offset_known)

	var differs := 0
	## ★±4 天(原 ±3): ±3 在周四恰好落在同一周(周一/周日)⇒ 「至少一条跨周」那条分母周四必红; ±4 在一周任何一天都至少跨一次。
	for shift in [4 * DAY, -4 * DAY]:
		P2.server_clock_reset()
		var tag := "本机快4天" if shift > 0 else "本机慢4天"
		_round_trip(_dev() - shift)
		var now: int = P2.now_utc()
		var truth_now: int = _dev() - shift
		_ok("①② %s ⇒ now_utc == 真实时刻" % tag, absi(now - truth_now) <= 1, "now=%d truth=%d" % [now, truth_now])
		_ok("①② %s ⇒ 周锚点按真实" % tag, P2.week_anchor_utc(now) == P2.week_anchor_utc(truth_now))
		_ok("①② %s ⇒ 赛程阶段按真实" % tag, P2.phase_at_utc(now) == P2.phase_at_utc(truth_now),
			"%s (本机钟会说 %s)" % [P2.phase_at_utc(now), P2.phase_at_utc(_dev())])
		if P2.week_anchor_utc(_dev()) != P2.week_anchor_utc(truth_now):
			differs += 1
			## GameState 真入口: 锚点钉在「真实这周」⇒ 不过期; 不纠正的话本机钟会判成换周
			var gs = get_node_or_null("/root/GameState")
			_ok("①② %s GameState 在场(分母)" % tag, gs != null)
			if gs != null:
				var saved: int = int(gs.week_anchor_ts)
				gs.week_anchor_ts = P2.week_anchor_utc(truth_now)
				_ok("①② %s ⇒ GameState 不误判换周" % tag, not gs.is_season_expired())
				gs.week_anchor_ts = saved
		## ③ 没网: 偏移不动
		var off0: int = P2.server_offset_sec
		_round_trip(0)
		_ok("③ %s 没网 ⇒ 偏移不动" % tag, P2.server_offset_sec == off0 and off0 == -shift, str(P2.server_offset_sec))
		## ③ 重开游戏: 从盘读回
		P2.server_clock_forget_memory()
		_ok("③ %s 重开 ⇒ 从盘读回上次偏移" % tag, absi(P2.now_utc() - (_dev() - shift)) <= 1 and P2.server_offset_known,
			str(P2.server_offset_sec))
	_ok("①② 分母: 至少一条跨了周(本机钟与真实不在同一周)", differs >= 1, "differs=%d" % differs)

	## ④ 时间穿越优先 / now_override_ts 更优先 (此时偏移 = +3 天)
	var dev: int = _dev()
	var target: int = P2.week_day_at(dev, 6, 15, 0)
	var traveled: bool = P2.travel_to(target)
	_ok("④ 穿越生效(分母)", traveled and P2.travel_active())
	_ok("④ 穿越中 now_utc 走穿越、不叠服务器偏移", absi(P2.now_utc() - target) <= 1,
		"now=%d target=%d off=%d" % [P2.now_utc(), target, P2.server_offset_sec])
	P2.now_override_ts = 1791188352
	_ok("④ now_override_ts 最优先", P2.now_utc() == 1791188352)
	P2.now_override_ts = 0
	P2.travel_reset()

	## ⑤ 钟准的手机 ⇒ 偏移 0
	_round_trip(_dev() + 1)
	_ok("⑤ ±2 秒内当 0", P2.server_offset_sec == 0 and P2.server_offset_known, str(P2.server_offset_sec))

	P2.server_clock_reset()
	print("verify_server_clock: %d/%d" % [_n - _fail, _n])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
