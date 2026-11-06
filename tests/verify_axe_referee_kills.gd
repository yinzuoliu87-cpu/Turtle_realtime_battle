extends Node
## verify_axe_referee_kills —— 服务器局的小木斧击杀经验(2026-11-06)。
##
## 查出来的: 用户 10-22 定「买 22 / 打完一局 10 / 击杀 6」; 积分赛上裁判机之后, 击杀经验只在裁判机的工作副本上涨, 跑完 GameState 还原、
##   结果单不带 ⇒ 没了。正式服 527 个相邻两局的经验增量里 0 个带 +6; 探针重跑真任务 1122: 340 → 352, 结果单 33 个键里没有斧头。
## 判据:
##   A 计数: 左方斧头亲手击杀 / 3 秒内助攻 ⇒ kills.left +1, 本机经验 +EXP_ON_KILL; 右方同样两种 ⇒ kills.right +1, ★本机经验不动;
##     过了助攻窗 / 不是斧头 ⇒ 都不算(分母)
##   B ★真裁判局: 结果单带 axe_kills / axe_kills_b, 且 = 这一局 kills(不是恒 0: 跑一局两边都带斧头的, 分母 > 0)
##   C 结算: 积分赛 / 闯关回包带 axe_kills ⇒ 经验 +n×EXP_ON_KILL 且落流水; 不带这个键(服务端没上)⇒ 一点不变; 回包异常的大数 ⇒ 夹住
##   D 不改对局: 同一局不算 kills 的结果(赢家 / 步数 / 指纹)与计数无关 —— 由 verify_rules_fingerprint 守, 这里只查结果单键齐全。

const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const BP := preload("res://scripts/referee/bot_pool.gd")
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
const Backend := preload("res://scripts/net/backend.gd")

var _fails := 0
var _n := 0
var _gs


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if d == "" else "  " + d))
	if not c:
		_fails += 1


## 最小战场: on_death 只读 battle._t 与 /root/GameState。
class FakeBattle extends Node:
	var _t := 100.0


func _t_count() -> void:
	var b := FakeBattle.new()
	b.name = "FakeBattle"
	add_child(b)
	var ax := AxeSystem.new(b)
	var left := {"_eq_axe": true, "_axe_local": true}
	var right := {"_eq_axe": true, "_axe_local": false}
	var other := {"_eq_axe": false}
	_gs.axe_exp_total = 0
	_gs.axe_stage = 0
	_gs.axe_exp_bar = 0
	var e0 := int(_gs.axe_exp_total)
	ax.on_death({}, left)
	_ok("A 左方亲手击杀: left +1、本机经验 +%d" % AE.EXP_ON_KILL, ax.kills == {"left": 1, "right": 0} and int(_gs.axe_exp_total) == e0 + AE.EXP_ON_KILL, str(ax.kills))
	ax.on_death({"_axe_touch_t": 98.0}, other)
	_ok("A 左方 3 秒内助攻: left +1", ax.kills == {"left": 2, "right": 0}, str(ax.kills))
	var e1 := int(_gs.axe_exp_total)
	ax.on_death({}, right)
	_ok("A ★右方亲手击杀: right +1、本机经验不动", ax.kills == {"left": 2, "right": 1} and int(_gs.axe_exp_total) == e1, str(ax.kills))
	ax.on_death({"_axe_touch_r": 98.0}, other)
	_ok("A 右方 3 秒内助攻: right +1", ax.kills == {"left": 2, "right": 2}, str(ax.kills))
	ax.on_death({"_axe_touch_t": 90.0, "_axe_touch_r": 90.0}, other)
	_ok("A 过了助攻窗 / 不是斧头 ⇒ 都不算", ax.kills == {"left": 2, "right": 2}, str(ax.kills))
	b.queue_free()


func _snap() -> Dictionary:
	_gs.start_new_season()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(["basic", "stone", "bamboo"])
	var axe := {"id": "p2eq_096", "star": 1}
	_gs.persistent_equipped = {"basic": [axe.duplicate()], "stone": [axe.duplicate()], "bamboo": [axe.duplicate()]}
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic"}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone"}, {"kind": "leader", "slot": 2, "id": "bamboo"},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.season_level = 6
	_gs.axe_exp_total = 300
	_gs.axe_stage = 3
	return Backend.build_ghost_snapshot("g_axe_a", {"name": "甲方", "avatar": "basic", "id": "g_axe_a"})


func _t_referee() -> void:
	var a := _snap()
	var b: Dictionary = BP.one(16, 0, 0, 0)
	b["gl_ts"] = int(P2.now_utc()) - 300
	var res: Dictionary = {}
	var total := 0
	for sd in [11, 22, 33, 44]:
		var job = JSON.parse_string(JSON.stringify({"v": 1, "job_id": 1, "match_id": MID, "mode": "gauntlet", "key": {"week": 1},
			"seed": sd, "client_version": ReplayRecorder.client_version(), "a": a, "b": b}))
		res = await RefereeRunner.run(self, job)
		print("  种子 %d: ok=%s err=%s axe_kills=%s axe_kills_b=%s steps=%s" % [sd, str(res.get("ok")), str(res.get("error", "")), str(res.get("axe_kills")), str(res.get("axe_kills_b")), str(res.get("steps"))])
		if not bool(res.get("ok", false)) or not res.has("axe_kills") or not res.has("axe_kills_b"):
			_ok("B 结果单带 axe_kills / axe_kills_b", false, str(res.keys()))
			return
		total += int(res["axe_kills"])
		if total > 0:
			break
	_ok("B ★真裁判局: 结果单带击杀数, 三只都带斧头的一方跑出来 > 0(分母, 不是恒 0)", total > 0, "累计 %d" % total)


func _t_settle() -> void:
	var wk := P2.week_anchor_utc(int(P2.now_utc()))
	_gs.start_new_season()
	_gs.week_anchor_ts = wk
	_gs.persistent_bench = []
	_gs.persistent_equipped = {"candy": [{"id": "p2eq_096", "star": 1}]}
	_gs.econ_log = []
	_gs.econ_up = 0
	var led := {"battles": 1, "wins": 1, "hearts": P2.HEARTS_MAX, "sweeps": 0, "eggs": 1, "used": 1, "reward": 20}
	_gs.referee_pending = RW.ranked_bill(1, MID, wk, {})
	var t0 := int(_gs.axe_exp_total)
	RW.settle_ranked(_gs, 1, {"won": 1, "coins": 0, "ranked": led, "axe_kills": 2})
	_ok("C ★积分赛回包带 2 次击杀 ⇒ 经验 = 打完一局 %d + 击杀 %d" % [AE.EXP_ON_MATCH, 2 * AE.EXP_ON_KILL],
		int(_gs.axe_exp_total) == t0 + AE.EXP_ON_MATCH + 2 * AE.EXP_ON_KILL, "%d → %d" % [t0, int(_gs.axe_exp_total)])
	var ops: Array = (_gs.econ_log as Array).filter(func(r): return str(r.get("op", "")) == "axe_exp")
	_ok("C 落了流水(一条 axe_exp n=%d)" % (2 * AE.EXP_ON_KILL), ops.size() == 1 and int(ops[0].get("n", 0)) == 2 * AE.EXP_ON_KILL, str(ops))
	var t1 := int(_gs.axe_exp_total)
	led["battles"] = 2
	led["used"] = 2
	_gs.referee_pending = RW.ranked_bill(2, MID, wk, {})
	RW.settle_ranked(_gs, 2, {"won": 1, "coins": 0, "ranked": led})
	_ok("C ★回包不带这个键(服务端没上)⇒ 只有打完一局那一笔", int(_gs.axe_exp_total) == t1 + AE.EXP_ON_MATCH, "%d → %d" % [t1, int(_gs.axe_exp_total)])
	var t2 := int(_gs.axe_exp_total)
	_gs.referee_pending = RW.pending_for(3, MID, wk, {})
	RW.settle(_gs, 3, {"won": 1, "coins": 0, "gw": 1, "gl": 0, "axe_kills": 1})
	_ok("C ★闯关回包同样发", int(_gs.axe_exp_total) == t2 + AE.EXP_ON_MATCH + AE.EXP_ON_KILL, "%d → %d" % [t2, int(_gs.axe_exp_total)])
	var t3 := int(_gs.axe_exp_total)
	RW.apply_axe_kills(_gs, {"axe_kills": 99999})
	_ok("C 回包异常的大数被夹住", int(_gs.axe_exp_total) <= t3 + 200 * AE.EXP_ON_KILL, str(_gs.axe_exp_total))
	var t4 := int(_gs.axe_exp_total)
	RW.apply_axe_kills(_gs, {"axe_kills": -5})
	_ok("C 负数不发", int(_gs.axe_exp_total) == t4)


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
	_t_count()
	await _t_referee()
	_t_settle()
	P2.now_override_ts = keep
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
