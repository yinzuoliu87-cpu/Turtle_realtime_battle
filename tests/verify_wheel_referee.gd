extends Node
## verify_wheel_referee —— 赌神命运之轮一大轮内累积, 服务器局里生效(2026-11-06)。
##
## 设计(用户 11-06):「这个技能的设计就是在一大轮之内, 就是逐渐成长的一个技能」。
## 查出来的: 抽到的花色存在本机存档; 裁判开局写死 {}, 结果单不带 ⇒ 积分赛上裁判机后每局从 0 开始。
## 判据(真裁判入口 + 真回包解析):
##   A 快照: 抽过才带 wheel_stacks(没抽过与机器人同形); 只认四种花色, 异常值夹住
##   B ★开局带进去: 左方累积 ♠3 ⇒ 赌神最大生命比没有累积时正好多 3 × WHEEL_SPADE_HP
##   C ★右方同一条规则
##   D ★局内抽到的带回来: 结果单 wheel_new / wheel_new_b 两边都有, 次数 > 0(分母: 真抽到了)
##   E ★结算累积: 真回包 ⇒ 存档 +1 累积(不是覆盖); 回包不带这个键 ⇒ 不变
##   F ★整条链: 这一局带回来的 ⇒ 下一局快照带上 ⇒ 下一局裁判开局就吃到
##   G 换轮清零

const Backend := preload("res://scripts/net/backend.gd")
const BP := preload("res://scripts/referee/bot_pool.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const GS_SYS := preload("res://scripts/systems/skills/gambler_system.gd")
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"

var _fails := 0
var _n := 0
var _gs
var _b = null
var _hp := {}
var _idx := -1


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if d == "" else "  " + d))
	if not c:
		_fails += 1


func _on_battle(b) -> void:
	_b = b


func _process(_d: float) -> void:
	if _b == null or not is_instance_valid(_b):
		return
	for u in _b._units:
		var k := "%s/%s" % [str(u.get("side", "")), str(u.get("id", ""))]
		if not _hp.has(k):
			_hp[k] = float(u.get("maxHp", 0.0))


func _snap(gid: String, wheel: Dictionary) -> Dictionary:
	_gs.start_new_season()
	_gs.season_leaders = ["gambler", "stone", "bamboo"]
	_gs.left_team.assign(["gambler", "stone", "bamboo"])
	_gs.persistent_equipped = {}
	_gs.loadouts = {"gambler": _idx}
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "gambler"}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone"}, {"kind": "leader", "slot": 2, "id": "bamboo"},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.season_level = 6
	_gs.gambler_wheel_stacks = wheel.duplicate()
	return Backend.build_ghost_snapshot(gid, {"name": gid, "avatar": "gambler", "id": gid})


func _run(a: Dictionary, b: Dictionary, sd: int) -> Dictionary:
	_b = null
	_hp = {}
	var job = JSON.parse_string(JSON.stringify({"v": 1, "job_id": 1, "match_id": MID, "mode": "gauntlet", "key": {"week": 1},
		"seed": sd, "client_version": ReplayRecorder.client_version(), "a": a, "b": b}))
	var res: Dictionary = await RefereeRunner.run(self, job, _on_battle)
	_b = null
	return {"res": res, "hp": _hp.duplicate()}


func _sum(d) -> int:
	var n := 0
	if d is Dictionary:
		for k in d:
			n += int(d[k])
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_gs.test_mode = true
	_gs.tutorial_active = false
	var keep: int = P2.now_override_ts
	P2.now_override_ts = P2.week_anchor_utc(int(Time.get_unix_time_from_system())) + 2 * 86400 + 12 * 3600
	var pets = JSON.parse_string(FileAccess.get_file_as_string("res://data/pets.json"))
	for p in (pets if pets is Array else pets.get("pets", [])):
		if str(p.get("id", "")) == "gambler":
			var pool: Array = p.get("skillPool", [])
			for i in range(pool.size()):
				if str(pool[i].get("type", "")) == "gamblerFateWheel":
					_idx = i
	_ok("分母: 找到命运之轮的技能下标", _idx >= 0, str(_idx))

	## ── A 快照 ──
	var a0 := _snap("g_w_a", {})
	var a3 := _snap("g_w_a", {"spade": 3})
	_ok("A 抽过才带 wheel_stacks", int((a3.get("wheel_stacks", {}) as Dictionary).get("spade", 0)) == 3 and not a0.has("wheel_stacks"))
	_ok("A 异常值: 不认识的花色丢掉、大数夹到 99、负数 / 不是数不要",
		Backend.ghost_wheel_stacks({"wheel_stacks": {"gift": 5, "spade": 999, "heart": -2, "club": "9"}}) == {"spade": 99})

	## ── B / C 开局带进去 ──
	var b0: Dictionary = _snap("g_w_b", {})
	b0["gl_ts"] = int(P2.now_utc()) - 300
	var b3: Dictionary = b0.duplicate(true)
	b3["wheel_stacks"] = {"spade": 3}
	var r0: Dictionary = await _run(a0, b0, 77)
	_ok("分母: 基线一局跑通", bool((r0["res"] as Dictionary).get("ok", false)), str((r0["res"] as Dictionary).get("error", "")))
	var r1: Dictionary = await _run(a3, b3, 77)
	var want := 3.0 * GS_SYS.WHEEL_SPADE_HP
	var dl: float = float((r1["hp"] as Dictionary).get("left/gambler", 0.0)) - float((r0["hp"] as Dictionary).get("left/gambler", 0.0))
	var dr: float = float((r1["hp"] as Dictionary).get("right/gambler", 0.0)) - float((r0["hp"] as Dictionary).get("right/gambler", 0.0))
	_ok("B ★左方累积 ♠3 ⇒ 最大生命多 %.0f" % want, absf(dl - want) < 1.0, "实测多 %.0f" % dl)
	_ok("C ★右方同一条规则", absf(dr - want) < 1.0, "实测多 %.0f" % dr)

	## ── D 局内抽到的带回来(两边都抽到才算, 换种子找) ──
	var res: Dictionary = {}
	for sd in [77, 78, 79, 80, 81, 82]:
		res = ((await _run(a0, b0, sd)) as Dictionary)["res"]
		if _sum(res.get("wheel_new")) > 0 and _sum(res.get("wheel_new_b")) > 0:
			break
	print("  结果单 wheel_new=%s wheel_new_b=%s" % [str(res.get("wheel_new")), str(res.get("wheel_new_b"))])
	_ok("D ★结果单带回两边各自抽到的花色", _sum(res.get("wheel_new")) > 0 and _sum(res.get("wheel_new_b")) > 0)

	## ── E 结算累积(走真回包解析) ──
	var wk := P2.week_anchor_utc(int(P2.now_utc()))
	_gs.start_new_season()
	_gs.week_anchor_ts = wk
	_gs.gambler_wheel_stacks = {"spade": 1}
	var led := {"battles": 1, "wins": 1, "hearts": P2.HEARTS_MAX, "sweeps": 0, "eggs": 1, "used": 1, "reward": 20, "sweep": false}
	var body := {"ok": true, "status": "done", "match_id": MID, "kind": "ranked", "won": true, "coins": 0, "ranked": led, "wheel_new": {"spade": 2, "club": 1}}
	var st: Dictionary = RN.parse_status(true, 200, JSON.stringify(body))
	_ok("E ★真回包解析把 wheel_new 带过来了", int((st.get("wheel_new", {}) as Dictionary).get("spade", 0)) == 2, str(st.get("wheel_new", "没有")))
	_gs.referee_pending = RW.ranked_bill(1, MID, wk, {})
	RW.settle_ranked(_gs, 1, st)
	_ok("E ★累积不是覆盖: ♠1 + 2 = 3, ♣1", int(_gs.gambler_wheel_stacks.get("spade", 0)) == 3 and int(_gs.gambler_wheel_stacks.get("club", 0)) == 1, str(_gs.gambler_wheel_stacks))
	var before: Dictionary = (_gs.gambler_wheel_stacks as Dictionary).duplicate()
	led["battles"] = 2
	led["used"] = 2
	body.erase("wheel_new")
	_gs.referee_pending = RW.ranked_bill(2, MID, wk, {})
	RW.settle_ranked(_gs, 2, RN.parse_status(true, 200, JSON.stringify(body)))
	_ok("E 回包不带这个键(服务端没上)⇒ 不变", _gs.gambler_wheel_stacks == before, str(_gs.gambler_wheel_stacks))
	_gs.referee_pending = RW.pending_for(3, MID, wk, {})
	RW.settle(_gs, 3, RN.parse_status(true, 200, JSON.stringify({"ok": true, "status": "done", "match_id": MID, "won": true, "coins": 0, "gw": 1, "gl": 0, "wheel_new": {"heart": 1}})))
	_ok("E 闯关回包同样累积", int(_gs.gambler_wheel_stacks.get("heart", 0)) == 1, str(_gs.gambler_wheel_stacks))
	_ok("E ★决赛回包解析也带过来了", int((RN.parse_finals_coins(true, 200, JSON.stringify({"ok": true, "status": "done", "coins": 3, "wheel_new": {"club": 2}})).get("wheel_new", {}) as Dictionary).get("club", 0)) == 2)

	## ── F 整条链: 这一局带回来的进下一局快照 ──
	var carried: Dictionary = (_gs.gambler_wheel_stacks as Dictionary).duplicate()
	var a_next := _snap("g_w_a", carried)
	_ok("F ★带回来的累积进了下一局快照", a_next.get("wheel_stacks", {}) == Backend.ghost_wheel_stacks({"wheel_stacks": carried}), str(a_next.get("wheel_stacks", "没有")))

	## ── G 换轮清零 ──
	_gs.start_new_season()
	_ok("G 换轮清零(一大轮内成长)", (_gs.gambler_wheel_stacks as Dictionary).is_empty())

	P2.now_override_ts = keep
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
