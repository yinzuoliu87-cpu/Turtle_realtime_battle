extends Node
## verify_boot_season_clock.gd — 开机那一次赛季判定用的钟可能是旧的: 往回滚要等时钟核对过 (2026-10-22)
##
## ══════════════════════════════════════════════════════════════════════
##  由来: 内测服整周彩排(台账 docs/plans/ref/内测服整周彩排台账.md「六」)
## ══════════════════════════════════════════════════════════════════════
## 假时间拨到 10-31 周六起 21 个模拟号打闯关赛, **一开游戏赛季就被清空**(season_id 2→3、16 场 11 胜归零、
##   锚点退回真实本周 10-19)。探针 tests/_probe_boot_season_clock.gd 打出来的数:
##   · `GameState._ready` 里那一次 `ensure_season()` 跑完时 asked=0(服务状态都还没问)、内测服偏移 0
##     ⇒ 用本机钟(真周 10-19)判存档(假周 10-26)⇒ `!=` ⇒ 滚轮清档;
##   · 337ms 后偏移才到(807687 秒), 那时再 ensure_season 又判一次换周 ⇒ season_id 再 +1(两次清档)。
##   · 正式服同一条路径: 手机钟在两次联网之间被往回拨 4 天(落盘的 Date 头偏移是旧的)⇒ 2→3→4。
##
## ══════════════════════════════════════════════════════════════════════
##  判据(全部走真入口 `GameState.ensure_season()` + 真传输缝 `SupabaseNet._http`)
## ══════════════════════════════════════════════════════════════════════
##   A 内测服: 存档在假周(下周)、本机钟在真周、偏移晚到
##       ⇒ 偏移到之前 ensure_season 不滚; 偏移从真入口到了之后**不用等打完一场**就补判:
##          还是不滚, 而且晋级(`promoted`)算出来了、周六闯关赛开得了
##   B 正式服: 手机钟被往回拨(落盘偏移旧)⇒ Date 头到之前不滚; 到了之后同一周 ⇒ 也不滚
##   C 正式服: 核对过之后钟**仍然**早于存档(锚点是坏钟写的)⇒ 照原样滚 —— 「往回滚」没被整个删掉
##   D 正式服: 往前滚(周一换轮)一个字没变 —— 没核对也照旧当场滚
##   E 接线: 钩子真挂在 GameState 上; 门禁(test_mode)默认不动它
##   ★每条「不滚」都配一条分母: 那一刻本机钟所在的周确实早于存档那一周(否则判据空转)。
## ★全程 test_mode = true, 并量存档文件修改时刻(ensure_season 内部会 save())。
##
## 跑法: bash godot-quiet.sh res://tests/verify_boot_season_clock.tscn --quit-after 600

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SB := preload("res://scripts/net/supabase.gd")
const SE := preload("res://scripts/net/server_env.gd")
const DAY := 86400
const WEEK := 604800
const _MON := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const _WD := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const STATUS_URL := "https://example.invalid/rest/v1/service_status?select=*&limit=1"

var _n := 0
var _fail := 0
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])


func _dev() -> int:
	return int(Time.get_unix_time_from_system())


func _day(ts: int) -> String:
	return Time.get_datetime_string_from_unix_time(ts, true).substr(0, 10)


func _http_date(ts: int) -> String:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	return "%s, %02d %s %04d %02d:%02d:%02d GMT" % [_WD[int(d["weekday"])], int(d["day"]),
		_MON[int(d["month"]) - 1], int(d["year"]), int(d["hour"]), int(d["minute"]), int(d["second"])]


## 走真传输缝问一次服务状态: 回包带 `Date: <srv_ts>`, 正文带 `clock_offset_sec`(<0 ⇒ 正文里不带这一列)。
## 回调与 `SupabaseNet.fetch_status()` 同一句(那个函数在后端停用时直接返回, 门禁进不去)。
func _status_round_trip(srv_ts: int, clock_off: int) -> void:
	var row := {"id": 1, "maintenance": false, "notice": "", "min_client_version": "0.0.0"}
	if clock_off >= 0:
		row["clock_offset_sec"] = clock_off
	var body := JSON.stringify([row])
	var net = SB.new()
	add_child(net)
	net._transport = func(_m, _u, _h, _b, cb):
		cb.call({"ok": true, "code": 200, "body": body,
			"headers": PackedStringArray(["Content-Type: application/json", "Date: " + _http_date(srv_ts)])})
	var got := [false]
	net._http("GET", STATUS_URL, "", func(res):
		SB.apply_status_response(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", "")))
		got[0] = true)
	var w := 0
	while not got[0] and w < 120:
		await get_tree().process_frame
		w += 1
	_ok("  (回包到了, 走的是真传输缝)", got[0])
	net.queue_free()


## 等 deferred 的钩子跑完(它在 HTTP 回调里 call_deferred)。
func _await_hook(runs0: int) -> bool:
	var w := 0
	while int(_gs.clock_hook_runs) == runs0 and w < 120:
		await get_tree().process_frame
		w += 1
	return int(_gs.clock_hook_runs) > runs0


## 摆一份「打到一半」的存档局面(非默认值, 滚轮就会被看出来)。
func _stage(sid: int, anchor: int) -> void:
	_gs.season_id = sid
	_gs.season_start_ts = anchor
	_gs.week_anchor_ts = anchor
	_gs.season_total_battles = 16
	_gs.season_wins = 11
	_gs.hearts = 1
	_gs.ranked_used = 16
	_gs.promoted = false
	_gs.backfill_paid = 0
	_gs.gauntlet_wins = 0
	_gs.gauntlet_losses = 0
	_gs.season_leaders = ["pirate", "hiding", "diamond"]


func _intact(sid: int, anchor: int) -> bool:
	return int(_gs.season_id) == sid and int(_gs.week_anchor_ts) == anchor \
		and int(_gs.season_total_battles) == 16 and int(_gs.season_wins) == 11 and int(_gs.hearts) == 1 \
		and (_gs.season_leaders as Array).size() == 3


func _desc() -> String:
	return "season_id=%d 锚点=%s 场=%d 胜=%d 命=%d 阵容=%s" % [int(_gs.season_id), _day(int(_gs.week_anchor_ts)),
		int(_gs.season_total_battles), int(_gs.season_wins), int(_gs.hearts), str(_gs.season_leaders)]


func _ready() -> void:
	await get_tree().process_frame
	print("== verify_boot_season_clock ==")
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload GameState")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	_ok("★分母: test_mode 已置位(ensure_season 内部会 save())", bool(_gs.test_mode))
	var save_p: String = str(_gs.SAVE_PATH)
	var had: bool = FileAccess.file_exists(save_p)
	var mtime0: int = FileAccess.get_modified_time(save_p) if had else -1

	var k_ovr: int = P2.now_override_ts
	var k_beta: int = P2.beta_clock_offset_sec
	var k_hook: bool = bool(_gs.clock_hook_in_test)
	P2.now_override_ts = 0
	P2.travel_reset()

	_t_wiring(k_hook)
	_gs.clock_hook_in_test = true
	await _t_beta_late_offset()
	await _t_prod_clock_set_back()
	await _t_prod_confirmed_still_behind()
	_t_forward_roll_unchanged()

	## 还原
	_gs.clock_hook_in_test = k_hook
	SE.beta_override = -1
	P2.beta_clock_offset_sec = k_beta
	P2.beta_clock_heard = false
	P2.server_clock_reset()
	P2.now_override_ts = k_ovr
	var mtime1: int = FileAccess.get_modified_time(save_p) if FileAccess.file_exists(save_p) else -1
	_ok("★收尾: 存档文件没被写过", FileAccess.file_exists(save_p) == had and mtime1 == mtime0,
		"跑之前 mtime=%d, 跑之后 mtime=%d" % [mtime0, mtime1])
	print("verify_boot_season_clock: %d/%d" % [_n - _fail, _n])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)


# ── E 接线 ──────────────────────────────────────────────
func _t_wiring(k_hook: bool) -> void:
	print("── E 钩子接线 ──")
	var cb: Callable = P2.clock_listener
	_ok("E ★钩子挂在 GameState._on_clock_confirmed 上(GameState._ready 注册)",
		cb.is_valid() and cb.get_object() == _gs and str(cb.get_method()) == "_on_clock_confirmed",
		"%s / %s" % [str(cb.get_object()), str(cb.get_method()) if cb.is_valid() else "<无效>"])
	_ok("E 门禁里默认不动(clock_hook_in_test 默认 false)", not k_hook)
	## 门禁默认态下真叫一次: 不许走进 ensure_season
	var runs0: int = int(_gs.clock_hook_runs)
	_gs._on_clock_confirmed()
	_ok("E test_mode 且没开 clock_hook_in_test ⇒ 钩子不进 ensure_season", int(_gs.clock_hook_runs) == runs0,
		"%d → %d" % [runs0, int(_gs.clock_hook_runs)])
	## now_override_ts 钉住 = 算核对过(钉钟的门禁行为与原来逐字节相同)
	P2.server_clock_reset()
	P2.now_override_ts = _dev()
	_ok("E 钉了 now_override_ts ⇒ 算核对过", P2.clock_confirmed())
	P2.now_override_ts = 0
	_ok("E 分母: 不钉、没回包 ⇒ 没核对过", not P2.clock_confirmed())


# ── A 内测服: 存档在假周、本机钟在真周、偏移晚到 ──────────────
func _t_beta_late_offset() -> void:
	print("── A 内测服: 存档在假周、本机钟在真周、偏移晚到 ──")
	SE.beta_override = 1
	P2.server_clock_reset()               # 开机: 没有落盘偏移、本进程什么都没听到
	P2.beta_clock_offset_sec = 0          # 内测服假时间偏移不落盘 ⇒ 开机那一刻恒 0
	var real: int = _dev()
	var fake_wk: int = P2.week_anchor_utc(real) + WEEK          # 假时间在下一周
	var fake_now: int = fake_wk + 5 * DAY + 8 * 3600            # 下周六 08:00 UTC
	var off: int = fake_now - real
	_stage(2, fake_wk)
	_ok("A ★分母: 偏移到之前, 本机钟所在的周早于存档那一周",
		P2.week_anchor_utc(int(P2.now_utc())) < fake_wk and P2.beta_clock_offset() == 0,
		"本机周 %s < 存档周 %s" % [_day(P2.week_anchor_utc(int(P2.now_utc()))), _day(fake_wk)])
	_ok("A 分母: 这一刻时钟没核对过", not P2.clock_confirmed())
	_gs.ensure_season()                   # == GameState._ready 里那一次
	_ok("A ★★偏移到之前 ensure_season 不滚轮(赛季号/锚点/场次/胜场/命/阵容都没动)", _intact(2, fake_wk), _desc())

	var runs0: int = int(_gs.clock_hook_runs)
	await _status_round_trip(real, off)   # 偏移晚到: Date 头 = 真实时刻, 状态行带假时间偏移
	_ok("A 分母: 偏移从真入口到了", P2.beta_clock_offset() == off and P2.clock_confirmed(),
		"beta_clock_offset=%d 应为 %d" % [P2.beta_clock_offset(), off])
	_ok("A 分母: 到了之后假时间落在存档那一周、而且是周六",
		P2.week_anchor_utc(int(P2.now_utc())) == fake_wk and P2.phase_at_utc(int(P2.now_utc())) == P2.PHASE_GAUNTLET,
		"%s %s" % [_day(int(P2.now_utc())), P2.phase_at_utc(int(P2.now_utc()))])
	_ok("A ★偏移一到钩子自己补判了一次(不等打完一场)", await _await_hook(runs0),
		"clock_hook_runs %d → %d" % [runs0, int(_gs.clock_hook_runs)])
	_ok("A ★★补判之后仍然不滚轮", _intact(2, fake_wk), _desc())
	_ok("A ★★补判把晋级算出来了(11 胜 1 命, 收盘已过)⇒ 周六闯关赛开得了",
		bool(_gs.promoted) and bool(_gs.gauntlet_can_play()),
		"promoted=%s can_play=%s" % [str(_gs.promoted), str(_gs.gauntlet_can_play())])
	SE.beta_override = -1
	P2.beta_clock_offset_sec = 0


# ── B 正式服: 手机钟被往回拨(落盘偏移旧)、Date 头晚到 ─────────────
func _t_prod_clock_set_back() -> void:
	print("── B 正式服: 手机钟被往回拨, Date 头晚到 ──")
	SE.beta_override = 0
	P2.server_clock_reset()
	var real: int = _dev()
	var truth_wk: int = P2.week_anchor_utc(real) + WEEK          # 真实时间其实在下一周(手机慢了)
	var truth: int = truth_wk + 2 * DAY + 12 * 3600
	_stage(7, truth_wk)
	_ok("B ★分母: Date 头到之前, 本机钟所在的周早于存档那一周",
		P2.week_anchor_utc(int(P2.now_utc())) < truth_wk, "本机周 %s < 存档周 %s" % [
			_day(P2.week_anchor_utc(int(P2.now_utc()))), _day(truth_wk)])
	_gs.ensure_season()
	_ok("B ★★Date 头到之前不滚轮", _intact(7, truth_wk), _desc())
	var runs0: int = int(_gs.clock_hook_runs)
	await _status_round_trip(truth, -1)
	_ok("B 分母: 偏移测出来了, 现在落在存档那一周", P2.clock_confirmed()
		and P2.week_anchor_utc(int(P2.now_utc())) == truth_wk, "server_offset=%d" % P2.server_offset_sec)
	_ok("B 钩子补判了一次", await _await_hook(runs0))
	_ok("B ★★补判之后也不滚轮(老代码: 开机清一次、Date 头到了再清一次)", _intact(7, truth_wk), _desc())
	SE.beta_override = -1


# ── C 正式服: 核对过之后仍然早于存档 ⇒ 照原样滚 ───────────────
func _t_prod_confirmed_still_behind() -> void:
	print("── C 正式服: 核对过之后仍然早于存档 ⇒ 照原样滚 ──")
	SE.beta_override = 0
	P2.server_clock_reset()
	var real: int = _dev()
	var bad_wk: int = P2.week_anchor_utc(real) + WEEK          # 锚点是一只快了一周的钟写的
	_stage(9, bad_wk)
	_gs.ensure_season()
	_ok("C 分母: 核对之前先不滚(同 A/B)", _intact(9, bad_wk), _desc())
	var runs0: int = int(_gs.clock_hook_runs)
	await _status_round_trip(real, -1)    # 服务器说: 就是本机这一刻 ⇒ 存档锚点确实在未来
	_ok("C 分母: 核对过了、偏移 0、仍然早于存档", P2.clock_confirmed() and P2.server_offset_sec == 0
		and P2.week_anchor_utc(int(P2.now_utc())) < bad_wk)
	_ok("C 钩子补判了一次", await _await_hook(runs0))
	_ok("C ★★核对过仍然更早 ⇒ 照原样滚到本周(往回滚没被整个删掉)",
		int(_gs.season_id) == 10 and int(_gs.week_anchor_ts) == P2.week_anchor_utc(real)
		and int(_gs.season_total_battles) == 0 and int(_gs.hearts) == int(P2.HEARTS_MAX), _desc())
	SE.beta_override = -1


# ── D 正式服: 往前滚一个字没变 ──────────────────────────────
func _t_forward_roll_unchanged() -> void:
	print("── D 往前滚(周一换轮)照旧当场滚 ──")
	SE.beta_override = 0
	P2.server_clock_reset()
	var real: int = _dev()
	var last_wk: int = P2.week_anchor_utc(real) - WEEK
	_stage(11, last_wk)
	_ok("D 分母: 时钟没核对过", not P2.clock_confirmed())
	_gs.ensure_season()
	_ok("D ★★存档在上周 ⇒ 没核对也当场滚(周一开游戏的玩家行为不变)",
		int(_gs.season_id) == 12 and int(_gs.week_anchor_ts) == P2.week_anchor_utc(real)
		and int(_gs.season_total_battles) == 0 and int(_gs.ranked_used) == 0, _desc())
	SE.beta_override = -1
