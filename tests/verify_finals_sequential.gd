extends Node
## verify_finals_sequential.gd — 周日决赛日开播: 冠军杯赛一场接一场 / 小组赛同轮同时(方案书 docs/plans/20261101-决赛日开播一场接一场.md)
##
## 用户 2026-10-31「有任何商业游戏会同时播两个半决赛吗」→ 纠正「桶内就是这样子同时跑，但是决赛里面就一定是一场场跑」。
## 服务端 20261101 迁移起每组多下发 seq(每场 [开播, 揭晓]); 客户端判定在纯函数 `premiere_schedule.gd`(按每场自己的档期, 与是哪种排法无关),
## `live_spectate` / 对阵图只接线。①~⑤ 喂的是「一场接一场」的档期(= 冠军杯赛), ⑧ 喂的是「同一轮同时」(= 小组赛)。
##
## 段落:
##   ① 纯函数: 一场的三态(即将开播 → 开播中 → 已揭晓)逐秒边界; 顺序(按开播先后、与场号无关); 当前轮的档期不认(第二道锁);
##      看过的那一场提前揭晓; 形状不对 / 版本不认识 ⇒ 老规则
##   ② 解析: finals_view / finals_week_view 回包里的 seq 原样带进组字典; 没有 seq / seq = null / 多出不认识的键都不出错
##   ③ live_spectate 接线: premiere_hidden(即将开播 + 开播中都藏)/ premiere_upcoming / 开播会话起点 = 这一场自己的开播时刻
##   ④ 对阵图(我在组里, 4 人组第 1 轮两场): 五个时刻 —— 第 1 场开播中 / 场间 / 第 2 场开播中 / 本轮播完 / 下一轮备战;
##      每个时刻: 格子状态、✓ 数、「开播」小签数、能点的格子(只有开播中那一场)、顶上那一行、备战那一行
##   ⑤ ★下一轮备战在整轮播完之后: [翻面, round_at) 逐秒 —— 购物窗不开、备战那一行不出现; 揭晓前我的下一轮对手一律「待定」
##      (剧透那条例外在一场接一场时不生效), 揭晓后写出名字; round_at 起购物窗开
##   ⑥ 老字段退回: 同一组去掉 seq ⇒ 与老规则逐条相同(两场同一刻开播、我的下一轮对手照常写出、顶上那一行老写法)
##   ⑦ 结算段(备战结束 → 翻面, 服务端翻面提前到「备战结束 + 60 秒且结果齐」): 顶上那一行「结算中 · 即将开播」, 第 1 轮也有
##   ⑧ 小组赛同一轮同时开播: 两场同一刻开播中、短的那场先揭晓; 顶上那一行「本轮 2 场开播中 · 下一轮备战 X后开始」→「本轮 1 场开播中 …」;
##      对阵图两格都标「开播」、两格都能点; 我的下一轮对手在长的那场揭晓前一律「待定」; 下一轮备战 = 最长那场 + 25 秒
## 每条新判据都做过反向验证(改坏 → 红 → 逐字节还原), 见方案书「实施回填」。

const SB := preload("res://scripts/net/supabase.gd")
const LS := preload("res://scripts/systems/replay/live_spectate.gd")
const PS := preload("res://scripts/systems/replay/premiere_schedule.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BMS := preload("res://scripts/scenes/BracketMapScene.gd")
const BRACKET := "res://scenes/BracketMap.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
## 与服务端 finals_premiere_intro_sec / finals_premiere_gap_sec 同值(这里只用来造回包; 客户端产品代码不存这两个数)
const INTRO := 30
const GAP := 25

var _fail := 0
var _n := 0
var _gs
var _now := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	_gs.test_mode = true
	_gs.finals_pending_reveal = {}
	LS.watched = {}
	LS.known_len = {}
	_now = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 6 * 86400 + 18 * 3600 + 600
	_t_pure()
	_t_parse()
	_t_ls()
	await _t_map()
	await _t_no_spoiler()
	await _t_legacy()
	await _t_together()
	_cleanup()
	_finish()


func _cleanup() -> void:
	LS.pending = {}
	LS.watched = {}
	LS.known_len = {}
	SB._finals_view = {}
	SB._finals_tried = false
	SB.finals_week_clear()
	_gs.finals_pending_reveal = {}
	_gs.account_id = ""


## 服务端 finals_premiere_plan 的排法(这里只为造回包): 第 1 场 = 翻面, 每场 ceil(步数/60) + INTRO, 场间 GAP。
func _wire(flip: int, steps: Array, rnd: int = 1, first_m: int = 0) -> Dictionary:
	var p := {}
	var t := flip
	for i in range(steps.size()):
		var ln := int(ceil(float(steps[i]) / 60.0)) + INTRO
		p["%d-%d" % [rnd, first_m + i]] = [t, t + ln]
		t += ln + GAP
	return {"v": 1, "until": t, "settle_at": t + P2C.FINALS_SHOP_SEC, "p": p}


## 小组赛的排法(服务端 finals_premiere_plan 非杯那一支): 同一轮都 = 翻面, 档期结束 = 翻面 + 最长那场 + GAP。
func _wire_together(flip: int, steps: Array, rnd: int = 1) -> Dictionary:
	var p := {}
	var mx := 0
	for i in range(steps.size()):
		var ln := int(ceil(float(steps[i]) / 60.0)) + INTRO
		p["%d-%d" % [rnd, i]] = [flip, flip + ln]
		mx = maxi(mx, ln)
	var t := flip + mx + GAP
	return {"v": 1, "until": t, "settle_at": t + P2C.FINALS_SHOP_SEC, "p": p}


## 一个 4 人组(我是 0 号)、第 1 轮已翻面(第 1 场 0 号赢、第 2 场 2 号赢)。`seq` 为 null ⇒ 老服务端那一份。
func _body(flip: int, seq, closed: bool = false, rnd: int = 2) -> String:
	var nm := ["我自己", "乙", "丙", "丁"]
	var ents: Array = []
	for i in range(4):
		ents.append({"seed": i, "name": nm[i], "account_id": ME if i == 0 else "acct-x%d" % i})
	var round_at: int = int((seq as Dictionary)["until"]) if seq is Dictionary else flip
	## 新服务端: 倒计时 = 最早翻面(备战结束 + 60); 老服务端: round_at + 480
	var d := {"ok": true, "bucket": 0, "n": 4, "round": rnd, "closed": closed, "round_at": round_at,
		"revealed_at": flip, "next_at": round_at + (P2C.FINALS_SHOP_SEC + 60 if seq != null else 480), "now": _now, "entrants": ents,
		"done": {"1-0": 0, "1-1": 1}}
	if seq != null:
		d["seq"] = seq
	return JSON.stringify(d)


func _bk(flip: int, seq) -> Dictionary:
	return SB.parse_finals(true, 200, _body(flip, seq), ME, _now)


# ① ─────────────────────────────────────────────────────────────
func _t_pure() -> void:
	print("── ① 纯函数 ──")
	var F := 1_800_000_000
	var w := _wire(F, [6000, 7230])            # 第 1 场 [F, F+130]; 第 2 场 [F+155, F+306]; until F+331
	var b := {"bucket": 0, "size": 4, "round": 2, "closed": false, "round_at": int(w["until"]), "done": {"1-0": 0, "1-1": 1}, "seq": w}
	_ok("① 分母: is_seq / 两场都有档期", PS.is_seq(b) and PS.slot(b, 1, 0) == [F, F + 130] and PS.slot(b, 1, 1) == [F + 155, F + 306],
		str(PS.slot(b, 1, 0)) + str(PS.slot(b, 1, 1)))
	## 逐秒走一遍 [F − 5, until + 5]: 每一秒两场的状态都要等于按档期手算的那一个
	var bad: Array = []
	var seen := {}
	for t in range(F - 5, int(w["until"]) + 6):
		for m in range(2):
			var sl: Array = PS.slot(b, 1, m)
			var want := PS.S_UPCOMING if t < int(sl[0]) else (PS.S_LIVE if t < int(sl[1]) else PS.S_REVEALED)
			var got := PS.state(b, 1, m, t)
			seen[got] = true
			if got != want and bad.size() < 4:
				bad.append("t=F%+d m=%d want %d got %d" % [t - F, m, want, got])
			if PS.hidden(b, 1, m, t) != (got == PS.S_UPCOMING or got == PS.S_LIVE) and bad.size() < 4:
				bad.append("hidden t=F%+d m=%d" % [t - F, m])
	_ok("① ★三态逐秒边界: 开播前 = 即将开播 / [开播, 揭晓) = 开播中 / 之后 = 已揭晓(两场各自按档期)", bad.is_empty(), str(bad))
	_ok("① 分母: 三态都真的出现过", seen.has(PS.S_UPCOMING) and seen.has(PS.S_LIVE) and seen.has(PS.S_REVEALED))
	## 一次只有一场在开播(这就是「一场接一场」)
	var both := 0
	var live_t := 0
	for t in range(F, int(w["until"])):
		var k := 0
		for m in range(2):
			if PS.state(b, 1, m, t) == PS.S_LIVE:
				k += 1
		if k > 1:
			both += 1
		if k == 1:
			live_t += 1
	_ok("① ★同一时刻至多一场开播中(分母: 有 %d 秒在播)" % live_t, both == 0 and live_t == 130 + 151, "重叠 %d 秒" % both)
	_ok("① 第 2 场在第 1 场揭晓之后 ≥ 20 秒才开播(场间留给结束仪式)", int(PS.slot(b, 1, 1)[0]) - int(PS.slot(b, 1, 0)[1]) >= 20)
	_ok("① 看过的那一场: 开播中也算已揭晓; 即将开播的看过也不算(还没开始)",
		PS.state(b, 1, 0, F + 5, true) == PS.S_REVEALED and PS.state(b, 1, 1, F + 5, false) == PS.S_UPCOMING)
	_ok("① done 里没有这一场 ⇒ S_NONE(当前轮本来就没结果)", PS.state(b, 2, 0, F + 5) == PS.S_NONE)
	## 顺序按开播先后(与场号无关): 把第 2 场排到前面
	var w2 := {"v": 1, "until": F + 400, "p": {"1-0": [F + 200, F + 330], "1-1": [F, F + 150]}}
	var b2 := b.duplicate(true)
	b2["seq"] = w2
	var lu := PS.lineup(b2, 1)
	_ok("① lineup 按开播先后排(场号 1 在前)", lu.size() == 2 and int(lu[0][0]) == 1 and int(lu[1][0]) == 0, str(lu))
	## 第二道锁: 没收盘时当前轮(及以后)的档期不认
	var b3 := b.duplicate(true)
	(b3["seq"]["p"] as Dictionary)["2-0"] = [F, F + 100]
	(b3["done"] as Dictionary)["2-0"] = 0
	_ok("① ★第二道锁: 没收盘时当前轮的档期不认(哪天服务端多发了也不提前开播)", PS.slot(b3, 2, 0).is_empty() and PS.state(b3, 2, 0, F + 5) == PS.S_NONE)
	var b4 := b3.duplicate(true)
	b4["closed"] = true
	_ok("① 对照: 收盘了就认", PS.slot(b4, 2, 0) == [F, F + 100])
	## 形状不对 ⇒ 老规则
	var bad_shapes := [null, "x", {}, {"v": 0, "p": {}}, {"v": 1}, {"v": 1, "p": []}]
	var legacy_ok := true
	for s in bad_shapes:
		var bx := b.duplicate(true)
		bx["seq"] = s
		if PS.is_seq(bx) or PS.state(bx, 1, 0, F + 5) != PS.S_NONE:
			legacy_ok = false
	_ok("① 形状不对 / 版本不认识 / 没有 ⇒ 老规则(is_seq = false、S_NONE)× %d 种" % bad_shapes.size(), legacy_ok)
	var bx2 := b.duplicate(true)
	(bx2["seq"]["p"] as Dictionary)["1-0"] = [F + 10, F]
	_ok("① 揭晓早于开播的坏档期 ⇒ 不认", PS.slot(bx2, 1, 0).is_empty())
	## 顶上那一行
	var fmt := Callable(BMS, "countdown_text")
	_ok("① 顶上那一行 · 第 1 场开播中", PS.round_line(b, F + 10, fmt) == "第 1 场开播中 · 第 2 场 2 分 25 秒后开播",
		PS.round_line(b, F + 10, fmt))
	_ok("① 顶上那一行 · 场间", PS.round_line(b, F + 140, fmt) == "第 2 场 15 秒后开播", PS.round_line(b, F + 140, fmt))
	_ok("① 顶上那一行 · 本轮最后一场开播中 ⇒ 带下一轮备战倒计时", PS.round_line(b, F + 200, fmt) == "第 2 场开播中 · 下一轮备战 2 分 11 秒后开始",
		PS.round_line(b, F + 200, fmt))
	_ok("① 顶上那一行 · 本轮播完", PS.round_line(b, F + 320, fmt) == "下一轮备战 11 秒后开始", PS.round_line(b, F + 320, fmt))
	_ok("① 顶上那一行 · 备战开始后不归这里管(\"\")", PS.round_line(b, F + 331, fmt) == "")
	_ok("① 顶上那一行 · 看完了第 1 场 ⇒ 当场间说", PS.round_line(b, F + 10, fmt, {0: true}) == "第 2 场 2 分 25 秒后开播",
		PS.round_line(b, F + 10, fmt, {0: true}))
	var bc := {"bucket": 0, "size": 2, "round": 1, "closed": true, "round_at": F - 600, "done": {"1-0": 0}, "seq": _wire(F, [6000])}
	(bc["seq"] as Dictionary)["settle_at"] = 0
	_ok("① 收盘那一轮只有决赛 ⇒「决赛开播中」, 不写下一轮备战", PS.round_line(bc, F + 10, fmt) == "决赛开播中", PS.round_line(bc, F + 10, fmt))
	_ok("① 决赛播完 ⇒ \"\"", PS.round_line(bc, F + 200, fmt) == "")
	_ok("① before_shop: [翻面, round_at) 真 / round_at 起假 / 收盘假 / 老规则假",
		PS.before_shop(b, F) and PS.before_shop(b, F + 330) and not PS.before_shop(b, F + 331)
		and not PS.before_shop(bc, F) and not PS.before_shop({"round_at": F + 100}, F))
	## ⑦ 结算段: 备战结束(settle_at)起 → 翻面前; 备战中 / 收盘 / 老规则都不说
	var sa := int(w["until"]) + P2C.FINALS_SHOP_SEC
	_ok("⑦ 备战中(round_at + 5)不归这里管; 备战结束起「结算中 · 即将开播」",
		PS.round_line(b, int(w["until"]) + 5, fmt) == "" and not PS.settling(b, sa - 1)
		and PS.settling(b, sa) and PS.round_line(b, sa + 30, fmt) == PS.TXT_SETTLE, PS.round_line(b, sa + 30, fmt))
	var b1 := {"bucket": 0, "size": 4, "round": 1, "closed": false, "round_at": F, "done": {},
		"seq": {"v": 1, "until": 0, "settle_at": F + P2C.FINALS_SHOP_SEC, "p": {}}}
	_ok("⑦ 第 1 轮(还没翻过面、p 为空)也说: 备战中 \"\" / 备战结束后「结算中 · 即将开播」",
		PS.is_seq(b1) and PS.round_line(b1, F + 10, fmt) == "" and PS.round_line(b1, F + P2C.FINALS_SHOP_SEC + 1, fmt) == PS.TXT_SETTLE)
	_ok("⑦ 收盘 / 老规则(没有 settle_at)不说", not PS.settling(bc, F + 99999) and not PS.settling({"round_at": F}, F + 99999)
		and PS.round_line(bc, F + 99999, fmt) == "")


# ② ─────────────────────────────────────────────────────────────
func _t_parse() -> void:
	print("── ② 解析 ──")
	var flip := _now - 10
	var w := _wire(flip, [6000, 7230])
	var one := _bk(flip, w)
	_ok("② finals_view: seq 原样带进组字典", one.get("seq", null) is Dictionary and PS.slot(one, 1, 1) == [flip + 155, flip + 306],
		str(one.get("seq", null)))
	var wk: Dictionary = SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": 1, "now": _now, "buckets": [
		{"bucket": 0, "n": 4, "round": 2, "closed": false, "round_at": int(w["until"]), "revealed_at": flip,
			"done": {"1-0": 0, "1-1": 1}, "entrants": [], "seq": w},
		{"bucket": 1, "n": 4, "round": 2, "closed": false, "round_at": flip, "revealed_at": flip,
			"done": {"1-0": 0, "1-1": 1}, "entrants": [], "seq": null}],
		"cup": {"bucket": P2C.FINALS_CUP_BUCKET, "n": 2, "round": 1, "closed": true, "round_at": flip - 900,
			"revealed_at": flip, "done": {"1-0": 0}, "entrants": [], "seq": _wire(flip, [3000])}}), "", _now)
	var bs: Array = wk.get("buckets", [])
	_ok("② 分母: 周视图两组 + 杯", bs.size() == 2 and wk.has("cup"))
	if bs.size() == 2:
		_ok("② 周视图: 组 0 带 seq、组 1 seq = null ⇒ 老规则", PS.is_seq(bs[0]) and not PS.is_seq(bs[1]))
	_ok("② 周视图: 杯也带 seq", PS.is_seq(wk.get("cup", {})) and PS.slot(wk.get("cup", {}), 1, 0) == [flip, flip + 80])
	var old := SB.parse_finals(true, 200, _body(flip, null), ME, _now)
	_ok("② 老服务端(没有 seq 键)⇒ seq = null、老规则", old.get("seq", 1) == null and not PS.is_seq(old) and int(old.get("size", 0)) == 4)
	## 老客户端看到新回包: 只读具名键(这里用当前版本的解析证明「多一个键」不影响其余字段)
	var extra := JSON.parse_string(_body(flip, w)) as Dictionary
	extra["future_key"] = {"x": [1, 2]}
	var ex := SB.parse_finals(true, 200, JSON.stringify(extra), ME, _now)
	_ok("② 多出不认识的键 ⇒ 其余字段与没有时逐个相同",
		ex.get("done") == one.get("done") and ex.get("round_at") == one.get("round_at") and ex.get("left") == one.get("left")
		and ex.get("names") == one.get("names") and ex.get("me") == one.get("me"))


# ③ ─────────────────────────────────────────────────────────────
func _t_ls() -> void:
	print("── ③ live_spectate 接线 ──")
	LS.watched = {}
	var F := _now - 10
	var b := _bk(F, _wire(F, [6000, 7230]))
	_ok("③ premiere_hidden: 开播中 + 即将开播都藏", LS.premiere_hidden(b, 1, 0, F + 10) and LS.premiere_hidden(b, 1, 1, F + 10))
	_ok("③ premiere_upcoming: 只有第 2 场", not LS.premiere_upcoming(b, 1, 0, F + 10) and LS.premiere_upcoming(b, 1, 1, F + 10))
	_ok("③ 第 1 场揭晓后、第 2 场还藏着(场间)", not LS.premiere_hidden(b, 1, 0, F + 140) and LS.premiere_hidden(b, 1, 1, F + 140))
	var s1 := LS.premiere_session(b, 1, 1, F + 160)
	_ok("③ ★开播会话起点 = 这一场自己的开播时刻(F+155), 不是整轮翻面时刻", int(s1.get("flip_ts", 0)) == F + 155,
		"flip_ts - F = %d" % (int(s1.get("flip_ts", 0)) - F))
	_ok("③ 第 1 场的会话起点 = 翻面时刻", int(LS.premiere_session(b, 1, 0, F + 10).get("flip_ts", 0)) == F)
	LS.watched[LS.premiere_key(b, 1, 0)] = true
	_ok("③ 这台设备看完第 1 场 ⇒ 开播中也揭晓; 第 2 场仍是即将开播",
		not LS.premiere_hidden(b, 1, 0, F + 10) and LS.premiere_upcoming(b, 1, 1, F + 10))
	_ok("③ 顶上那一行(带 watched)= 场间写法", LS.premiere_round_line(b, F + 10, Callable(BMS, "countdown_text")) == "第 2 场 2 分 25 秒后开播",
		LS.premiere_round_line(b, F + 10, Callable(BMS, "countdown_text")))
	LS.watched = {}
	var old := _bk(F, null)
	_ok("③ 对照(老规则): 两场同一刻都在窗口里、没有「即将开播」、会话起点 = 翻面时刻",
		LS.premiere_hidden(old, 1, 0, F + 10) and LS.premiere_hidden(old, 1, 1, F + 10)
		and not LS.premiere_upcoming(old, 1, 1, F + 10) and int(LS.premiere_session(old, 1, 1, F + 10).get("flip_ts", 0)) == F)


# ④ ─────────────────────────────────────────────────────────────
func _open_map(bucket: Dictionary, now: int) -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	var m: Node = (load(BRACKET) as PackedScene).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	await _frames(3)
	m.set_data(bucket, {}, now)
	m.set_week({"buckets": []})
	await _frames(4)
	return m


## 把对阵图钉到 t 时刻, 走一遍产品自己的轮询(读缓存 → 重画 → 备战那一行 → 顶上那一行)。
func _at(m: Node, bucket: Dictionary, t: int) -> void:
	SB._finals_view = bucket
	SB._finals_tried = true
	m._now_override = t
	m._fetch_left = 999.0
	m._on_poll()
	await _frames(2)


func _ticks(m: Node) -> int:
	var k := 0
	for c in m._canvas.find_children("*", "Label", true, false):
		if str((c as Label).text).begins_with("✓"):
			k += 1
	return k


func _btns(m: Node) -> Array:
	var out: Array = []
	for c in m._canvas.find_children(BMS.N_NODE_BTN, "Button", true, false):
		out.append((c as Button).get_meta("rm", Vector2i(-9, -9)))
	return out


func _tags(m: Node) -> int:
	return m._canvas.find_children("PremiereTag", "", true, false).size()


func _t_map() -> void:
	print("── ④ 对阵图(4 人组, 我是 0 号; 第 1 轮两场一场接一场) ──")
	_gs.account_id = ME
	_gs.finals_pending_reveal = {}
	LS.watched = {}
	var F := _now - 10
	var w := _wire(F, [6000, 7230])
	var bk := _bk(F, w)
	var m: Node = await _open_map(bk, F + 10)
	_ok("④ 分母: 我那一组(4 人, 我是 0 号, 第 2 轮, seq)", int(m.cur().get("me", -1)) == 0 and int(m.cur().get("round", 0)) == 2
		and PS.is_seq(m.cur()))
	var fmt := Callable(BMS, "countdown_text")
	## [时刻, 第 1 场状态, 第 2 场状态, ✓ 数, 「开播」小签数, 顶上那一行]
	## ★对阵图那一行句首补轮名(20261031c 块 B · S 清单第 2 条:「半决赛第 1 场开播中 · 第 2 场 X 后开播」); `round_line` 本身不带(①那几条照旧)。
	var rows := [
		[F + 10, BMS.ST_PREMIERE, BMS.ST_UPCOMING, 0, 1, "半决赛第 1 场开播中 · 第 2 场 2 分 25 秒后开播"],
		[F + 140, BMS.ST_DONE, BMS.ST_UPCOMING, 1, 0, "半决赛第 2 场 15 秒后开播"],
		[F + 200, BMS.ST_DONE, BMS.ST_PREMIERE, 1, 1, "半决赛第 2 场开播中 · 下一轮备战 2 分 11 秒后开始"],
		[F + 320, BMS.ST_DONE, BMS.ST_DONE, 2, 0, "下一轮备战 11 秒后开始"],
	]
	for row in rows:
		var t: int = row[0]
		await _at(m, bk, t)
		var tag := "F%+d" % (t - F)
		_ok("④ %s 格子状态 = %s / %s" % [tag, row[1], row[2]],
			str(m.match_state(1, 0)) == row[1] and str(m.match_state(1, 1)) == row[2],
			"%s / %s" % [m.match_state(1, 0), m.match_state(1, 1)])
		_ok("④ %s ✓ %d 个、「开播」小签 %d 枚" % [tag, row[3], row[4]], _ticks(m) == row[3] and _tags(m) == row[4],
			"✓ %d · 开播 %d" % [_ticks(m), _tags(m)])
		var b := _btns(m)
		var live_btns := 0
		for rm in b:
			if str(m.match_state((rm as Vector2i).x, (rm as Vector2i).y)) == BMS.ST_PREMIERE:
				live_btns += 1
		_ok("④ %s ★即将开播的那一场不能点; 能点的开播格子只有正在播的那一场" % tag,
			not b.has(Vector2i(1, 1)) if str(row[2]) == BMS.ST_UPCOMING else true, str(b))
		_ok("④ %s 开播中可点的场数 = %d(主按钮只指向它)" % [tag, 1 if (row[1] == BMS.ST_PREMIERE or row[2] == BMS.ST_PREMIERE) else 0],
			live_btns == (1 if (row[1] == BMS.ST_PREMIERE or row[2] == BMS.ST_PREMIERE) else 0) and m.premiere_count() == live_btns,
			"%d / premiere_count %d" % [live_btns, m.premiere_count()])
		_ok("④ %s 顶上那一行「%s」" % [tag, row[5]], m._tip.visible and m._tip.text == row[5], m._tip.text)
		_ok("④ %s 备战那一行不出现(下一轮备战还没开始)" % tag, not m._shop_row.visible, m._shop_row.text)
	var cta: Node = m.find_child("PrimaryCta", true, false)
	if cta != null and (cta as Button).visible:
		await _at(m, bk, F + 200)
		_ok("④ 主按钮(在时)指向正在播的第 2 场", (cta as Button).get_meta("rm", Vector2i(-1, -1)) == Vector2i(1, 1))
	## 下一轮备战开始
	var ra := int(w["until"])
	await _at(m, bk, ra + 5)
	_ok("④ round_at 起: 备战那一行「备战购物 · 还剩 …」", m._shop_row.visible and str(m._shop_row.text).begins_with("备战购物"),
		m._shop_row.text)
	_ok("④ round_at 起: 顶上那一行回到倒计时写法(决赛 X 后开播, 倒计时到最早翻面 = 备战结束 + 60)",
		m._tip.text == BMS.round_tip(2, 4, ra + P2C.FINALS_SHOP_SEC + 60 - (ra + 5)), m._tip.text)
	await _at(m, bk, ra + P2C.FINALS_SHOP_SEC + 5)
	_ok("⑦ 备战结束后(还没翻面): 顶上那一行「结算中 · 即将开播」", m._tip.visible and m._tip.text == PS.TXT_SETTLE, m._tip.text)
	m.queue_free()
	await _frames(2)


# ⑤ ─────────────────────────────────────────────────────────────
func _t_no_spoiler() -> void:
	print("── ⑤ 下一轮备战在整轮播完之后 · 不剧透 ──")
	_gs.account_id = ME
	LS.watched = {}
	var F := _now - 10
	var w := _wire(F, [6000, 7230])
	var bk := _bk(F, w)
	var m: Node = await _open_map(bk, F)
	var ra := int(w["until"])
	var s1e := int(PS.slot(bk, 1, 1)[1])
	var bad: Array = []
	var n := 0
	for t in range(F, ra + 3):
		m._now_override = t
		n += 1
		var foe := str(m.competitor(2, 0, 1).get("name", ""))
		var want_foe := "待定" if t < s1e else "丙"
		if foe != want_foe and bad.size() < 4:
			bad.append("t=F%+d 对手=%s 期望 %s" % [t - F, foe, want_foe])
		var shop: bool = P2C.finals_shop_open(int(m.cur().get("round_at", 0)), t)
		if shop != (t >= ra) and bad.size() < 4:
			bad.append("t=F%+d 购物窗=%s" % [t - F, shop])
		if PS.before_shop(m.cur(), t) != (t < ra) and bad.size() < 4:
			bad.append("t=F%+d before_shop" % [t - F])
	_ok("⑤ ★逐秒 %d 秒: 第 2 场揭晓前我的下一轮对手一律「待定」、之后写出; 购物窗 round_at 才开" % n, bad.is_empty() and n > 300, str(bad))
	_ok("⑤ round_at ≥ 本轮最后一场揭晓 + 20 秒(结束仪式放得完)", ra - s1e >= 20, "%d" % (ra - s1e))
	m._now_override = F + 10
	_ok("⑤ 开播段: 问不了下一轮对手、也开不了打", not m.should_fetch_opponent(2, 0) and m.my_opponent_seed(2, 0) < 0)
	m._now_override = ra + P2C.FINALS_SHOP_SEC + 5
	_ok("⑤ 对照: 备战结束后问得出对手(丙)", m.my_opponent_seed(2, 0) == 2)
	m.queue_free()
	await _frames(2)


# ⑥ ─────────────────────────────────────────────────────────────
func _t_legacy() -> void:
	print("── ⑥ 老字段退回(服务端没上 20261101 / 开关关) ──")
	_gs.account_id = ME
	LS.watched = {}
	var F := _now - 10
	var bk := _bk(F, null)
	var m: Node = await _open_map(bk, F + 10)
	await _at(m, bk, F + 10)
	_ok("⑥ 分母: 没有 seq", not PS.is_seq(m.cur()))
	_ok("⑥ 两场同一刻开播(老规则)", str(m.match_state(1, 0)) == BMS.ST_PREMIERE and str(m.match_state(1, 1)) == BMS.ST_PREMIERE
		and _tags(m) == 2, "%s / %s · 开播 %d" % [m.match_state(1, 0), m.match_state(1, 1), _tags(m)])
	_ok("⑥ 没有「即将开播」这一态", not m.premiere_upcoming(1, 1))
	_ok("⑥ 老规则那条例外照旧: 我的下一轮对手照常写出(要备战)", str(m.competitor(2, 0, 1).get("name", "")) == "丙",
		str(m.competitor(2, 0, 1).get("name", "")))
	_ok("⑥ 顶上那一行老写法(决赛 X 后开播)", m._tip.text == BMS.round_tip(2, 4, F + 480 - (F + 10)), m._tip.text)
	_ok("⑥ 备战那一行老写法(购物窗开着: 备战购物 · 还剩 …)", m._shop_row.visible and str(m._shop_row.text).begins_with("备战购物"),
		m._shop_row.text)
	_ok("⑥ 开播会话起点 = 整轮翻面时刻", int(LS.premiere_session(m.cur(), 1, 1, F + 10).get("flip_ts", 0)) == F)
	m.queue_free()
	await _frames(2)


# ⑧ ─────────────────────────────────────────────────────────────
func _t_together() -> void:
	print("── ⑧ 小组赛同一轮同时开播 ──")
	_gs.account_id = ME
	LS.watched = {}
	var F := _now - 10
	var w := _wire_together(F, [6000, 7230])      # 两场 [F, F+130] / [F, F+151]; 下一轮备战 F+176
	var bk := _bk(F, w)
	var fmt := Callable(BMS, "countdown_text")
	_ok("⑧ 分母: 两场都从翻面开播、together", PS.slot(bk, 1, 0) == [F, F + 130] and PS.slot(bk, 1, 1) == [F, F + 151]
		and PS.together(PS.lineup(bk, 1)) and int(w["until"]) == F + 176)
	var both := 0
	var bad: Array = []
	for t in range(F, F + 177):
		var l0 := PS.state(bk, 1, 0, t) == PS.S_LIVE
		var l1 := PS.state(bk, 1, 1, t) == PS.S_LIVE
		if l0 and l1:
			both += 1
		if l0 != (t < F + 130) or l1 != (t < F + 151):
			if bad.size() < 3:
				bad.append("t=F%+d" % (t - F))
	_ok("⑧ ★同一时刻两场都在开播(%d 秒), 短的那场先揭晓" % both, bad.is_empty() and both == 130, str(bad))
	_ok("⑧ 顶上那一行 · 两场都在播", PS.round_line(bk, F + 10, fmt) == "本轮 2 场开播中 · 下一轮备战 2 分 46 秒后开始",
		PS.round_line(bk, F + 10, fmt))
	_ok("⑧ 顶上那一行 · 短的那场揭晓后", PS.round_line(bk, F + 140, fmt) == "本轮 1 场开播中 · 下一轮备战 36 秒后开始",
		PS.round_line(bk, F + 140, fmt))
	_ok("⑧ 顶上那一行 · 都揭晓了、下一轮备战没开始", PS.round_line(bk, F + 160, fmt) == "下一轮备战 16 秒后开始",
		PS.round_line(bk, F + 160, fmt))
	_ok("⑧ 顶上那一行 · 这台设备看完了第 1 场 ⇒ 只数还在播的", PS.round_line(bk, F + 10, fmt, {0: true}) == "本轮 1 场开播中 · 下一轮备战 2 分 46 秒后开始",
		PS.round_line(bk, F + 10, fmt, {0: true}))
	_ok("⑧ 对照: 一场接一场(杯)不是 together", not PS.together(PS.lineup(_bk(F, _wire(F, [6000, 7230])), 1)))
	var m: Node = await _open_map(bk, F + 10)
	await _at(m, bk, F + 10)
	var b := _btns(m)
	_ok("⑧ 对阵图 F+10: 两格都是开播、「开播」小签 2 枚、✓ 0 个、两格都能点、premiere_count 2",
		str(m.match_state(1, 0)) == BMS.ST_PREMIERE and str(m.match_state(1, 1)) == BMS.ST_PREMIERE and _tags(m) == 2
		and _ticks(m) == 0 and b.has(Vector2i(1, 0)) and b.has(Vector2i(1, 1)) and m.premiere_count() == 2,
		"%s / %s · 开播 %d · ✓ %d · %s" % [m.match_state(1, 0), m.match_state(1, 1), _tags(m), _ticks(m), str(b)])
	## ★对阵图那一行把「本轮」换成轮名(20261031c 块 B, 主会话转 S 10-31): 「半决赛 2 场开播中 · …」; `round_line` 本身(上面几条)照旧写「本轮」。
	_ok("⑧ 对阵图 F+10: 顶上那一行「半决赛 2 场开播中 · …」、备战那一行不出现", m._tip.text == "半决赛 2 场开播中 · 下一轮备战 2 分 46 秒后开始"
		and not m._shop_row.visible, m._tip.text)
	await _at(m, bk, F + 140)
	_ok("⑧ 对阵图 F+140: 第 1 场揭晓(✓ 1)、第 2 场仍开播、「开播」1 枚、顶上「半决赛 1 场开播中 · …」",
		str(m.match_state(1, 0)) == BMS.ST_DONE and str(m.match_state(1, 1)) == BMS.ST_PREMIERE and _tags(m) == 1 and _ticks(m) == 1
		and m._tip.text == "半决赛 1 场开播中 · 下一轮备战 36 秒后开始", "%s · %s" % [m.match_state(1, 1), m._tip.text])
	## 不剧透: 我的下一轮对手(第 2 场的胜者)在第 2 场揭晓前一律「待定」
	var bad2: Array = []
	for t in range(F, F + 177):
		m._now_override = t
		var foe := str(m.competitor(2, 0, 1).get("name", ""))
		if foe != ("待定" if t < F + 151 else "丙") and bad2.size() < 3:
			bad2.append("t=F%+d %s" % [t - F, foe])
		if P2C.finals_shop_open(int(m.cur().get("round_at", 0)), t) != (t >= F + 176) and bad2.size() < 3:
			bad2.append("t=F%+d 购物窗" % (t - F))
	_ok("⑧ ★逐秒: 长的那场揭晓前对手「待定」、之后写出; 下一轮备战 = 最长那场 + 25 秒才开", bad2.is_empty(), str(bad2))
	m.queue_free()
	await _frames(2)


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 开播一场接一场" if _fail == 0 and _n > 50 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
