extends Node
## verify_axe_owner_progress.gd — 096 小木斧: 每一方的斧头按【自己主人】的砍伐进度建 (2026-10-10)
##
## ★根因(查回放分叉时读代码确认):
##   ① `AxeSystem.summon` 不分敌我一律读**本机** GameState 的 axe_exp_total / axe_stage / axe_final
##      ⇒ 对手(快照/机器人)带 096 时, 它的斧头用的是**我**的进度。
##   ② `AxeSystem.on_death` 认「任何一把斧头」的击杀/3 秒助攻 ⇒ 对手的斧头砍死我的龟, 涨的是**我的**经验。
## ★判据都量**召唤物本身**(真入口 summon 建出来的血/攻/被动档/造物), 不量我插的标记;
##   本机与对手两份进度故意拉开(高/低、再反过来), 两边各自对上自己那份才算过。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const RR := preload("res://scripts/systems/replay/replay_recorder.gd")
const Backend := preload("res://scripts/net/backend.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _owner(side: String, off: Vector2) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", side, c + off)
	_s._units.append(u)
	u["equips"] = [{"id": "p2eq_096", "star": 1}]
	return u


func _set_local(gs, total: int, stage: int, fin: String) -> void:
	gs.axe_exp_bar = 0
	gs.axe_exp_total = total
	gs.axe_stage = stage
	gs.axe_final = fin


## 召唤一把斧头, 返回 {hp, atk, pv, fin}(召唤失败返回空)。
func _summon(side: String, off: Vector2) -> Dictionary:
	var ow := _owner(side, off)
	var ax = _s._equip_sys._axe.summon(ow)
	if not (ax is Dictionary):
		return {}
	return {"ax": ax, "hp": float(ax["maxHp"]), "atk": float(ax["atk"]), "pv": int(ax.get("_axe_pv", -1)),
		"fin": str(ax.get("_axe_final", ""))}


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.51


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	var bak := {"bar": int(gs.axe_exp_bar), "tot": int(gs.axe_exp_total), "st": int(gs.axe_stage),
		"fin": str(gs.axe_final), "dg": (gs.dual_ghost as Dictionary).duplicate(true)}
	print("=== 096 小木斧 · 斧头按主人自己的砍伐进度 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._units.clear()

	# ── ① 本机高 / 对手低 ──
	_set_local(gs, 600, 4, "")
	gs.dual_ghost = {"season_total_battles": 3.0, "axe_exp_total": 30.0, "axe_stage": 0.0, "axe_final": ""}
	var L1 := _summon("left", Vector2(-200, 0))
	var R1 := _summon("right", Vector2(200, 0))
	_ok("★分母: 两边都召唤出了斧头", not L1.is_empty() and not R1.is_empty())
	if not L1.is_empty() and not R1.is_empty():
		_ok("本机斧头 = 本机进度(600 经验/钻石斧): 血 %.0f 攻 %.1f 被动 %d" % [L1["hp"], L1["atk"], L1["pv"]],
			_near(L1["hp"], AE.minion_hp(600, 4)) and _near(L1["atk"], AE.minion_atk(600, 4)) and L1["pv"] == 4,
			"期望 血 %.0f 攻 %.1f" % [AE.minion_hp(600, 4), AE.minion_atk(600, 4)])
		_ok("★★对手斧头 = 对手快照进度(30 经验/木斧), 不是本机的 600/钻石: 血 %.0f 攻 %.1f 被动 %d" % [R1["hp"], R1["atk"], R1["pv"]],
			_near(R1["hp"], AE.minion_hp(30, 0)) and _near(R1["atk"], AE.minion_atk(30, 0)) and R1["pv"] == 0,
			"期望 血 %.0f 攻 %.1f" % [AE.minion_hp(30, 0), AE.minion_atk(30, 0)])
		_ok("★分母: 两份进度造出来的斧头确实不一样(否则上面两条分不出谁读了谁)",
			not _near(L1["hp"], R1["hp"]), "%.0f vs %.0f" % [L1["hp"], R1["hp"]])

	# ── ② 反过来: 本机低 / 对手高(带造物) ──
	_s._units.clear()
	_set_local(gs, 30, 0, "")
	gs.dual_ghost = {"season_total_battles": 14.0, "axe_exp_total": 520.0, "axe_stage": 4.0, "axe_final": "holo"}
	var L2 := _summon("left", Vector2(-200, 0))
	var R2 := _summon("right", Vector2(200, 0))
	if not L2.is_empty() and not R2.is_empty():
		_ok("本机斧头 = 本机进度(30/木斧/无造物)",
			_near(L2["hp"], AE.minion_hp(30, 0)) and L2["pv"] == 0 and L2["fin"] == "",
			"血 %.0f 被动 %d 造物「%s」" % [L2["hp"], L2["pv"], L2["fin"]])
		_ok("★★对手斧头 = 对手快照(钻石斧 + 全息造物), 本机没有造物也照样是全息",
			R2["pv"] == 4 and R2["fin"] == "holo",
			"被动 %d 造物「%s」" % [R2["pv"], R2["fin"]])
	else:
		_ok("★分母: ② 两边都召唤出了斧头", false)

	# ── ③ 本机带造物、对手没有: 造物不许漏到对面 ──
	_s._units.clear()
	_set_local(gs, 600, 4, "ember")
	gs.dual_ghost = {"season_total_battles": 6.0, "axe_exp_total": 200.0, "axe_stage": 2.0, "axe_final": ""}
	var L3 := _summon("left", Vector2(-200, 0))
	var R3 := _summon("right", Vector2(200, 0))
	if not L3.is_empty() and not R3.is_empty():
		_ok("本机斧头带本机造物(余烬)", L3["fin"] == "ember", "「%s」" % L3["fin"])
		_ok("★★对手斧头: 铁斧(200 经验)、没有造物 —— 本机的余烬不漏过去",
			R3["fin"] == "" and R3["pv"] == 2 and _near(R3["hp"], AE.minion_hp(200, 2)),
			"造物「%s」被动 %d 血 %.0f(期望 %.0f)" % [R3["fin"], R3["pv"], R3["hp"], AE.minion_hp(200, 2)])
	else:
		_ok("★分母: ③ 两边都召唤出了斧头", false)

	# ── ④ 老快照(没有这三个键) → 按场次回落 ──
	##   7 场 × 每场 15 = 105 经验; 第 6 场攒到 90 ≥ 80 进化成石斧(进度条清零)⇒ 档位 1。
	##   ★期望值在这里**手算写死**, 不只调回落函数自己(否则函数写错, 期望也跟着错)。
	_ok("回落函数: 7 场 ⇒ 105 经验 / 石斧 / 无造物(手算)",
		AE.progress_for_battles(7) == {"total": 105, "stage": 1, "final": ""}, str(AE.progress_for_battles(7)))
	_ok("回落函数: 0 场 ⇒ 木斧零经验", AE.progress_for_battles(0) == {"total": 0, "stage": 0, "final": ""},
		str(AE.progress_for_battles(0)))
	_s._units.clear()
	_set_local(gs, 600, 4, "")
	gs.dual_ghost = {"season_total_battles": 7.0}
	var R4 := _summon("right", Vector2(200, 0))
	if not R4.is_empty():
		_ok("★★老快照(缺三键)的对手斧头 = 7 场下界(105/石斧), 不是本机的 600/钻石",
			R4["pv"] == 1 and _near(R4["hp"], AE.minion_hp(105, 1)),
			"被动 %d 血 %.0f(期望 %.0f)" % [R4["pv"], R4["hp"], AE.minion_hp(105, 1)])
	else:
		_ok("★分母: ④ 召唤出了斧头", false)
	## 没有对手快照(调试/冷启动兜底 bot) ⇒ 视为 0 场 ⇒ 木斧, 仍不读本机
	_s._units.clear()
	gs.dual_ghost = {}
	var R5 := _summon("right", Vector2(200, 0))
	if not R5.is_empty():
		_ok("★没有对手快照 ⇒ 对手斧头是零经验木斧(不回落到本机进度)",
			R5["pv"] == 0 and _near(R5["hp"], AE.minion_hp(0, 0)), "被动 %d 血 %.0f" % [R5["pv"], R5["hp"]])
	## 脏快照: 不崩、夹回合法区间、造物名不认就当没选
	var pd: Dictionary = AE.progress_of_snapshot({"axe_exp_total": -5.0, "axe_stage": 99.0, "axe_final": "nope"})
	_ok("脏快照: 经验夹到 ≥0 / 档位夹到钻石 / 不认识的造物当没选",
		pd == {"total": 0, "stage": AE.STAGES.size() - 1, "final": ""}, str(pd))
	var pn: Dictionary = AE.progress_of_snapshot({"axe_exp_total": null, "axe_stage": 1.0, "axe_final": "", "season_total_battles": 0.0})
	_ok("脏快照: 经验是 null ⇒ 整条按场次回落(不 int(null) 崩)", pn == AE.progress_for_battles(0), str(pn))

	# ── ⑤ 经验只记给本机自己的斧头 ──
	_s._units.clear()
	_set_local(gs, 0, 0, "")
	gs.dual_ghost = {"season_total_battles": 3.0, "axe_exp_total": 30.0, "axe_stage": 0.0, "axe_final": ""}
	var LK := _summon("left", Vector2(-200, 0))
	var RK := _summon("right", Vector2(200, 0))
	if not LK.is_empty() and not RK.is_empty():
		var axsys = _s._equip_sys._axe
		_ok("★分母: 本机斧头标成本机 / 对手斧头不是", bool(LK["ax"].get("_axe_local", false)) and not bool(RK["ax"].get("_axe_local", true)))
		## 对手斧头亲手砍死我方单位
		var e0: int = int(gs.axe_exp_total)
		axsys.on_death({"alive": false, "side": "left"}, RK["ax"])
		_ok("★★对手斧头击杀 ⇒ 本机经验不动(%d → %d)" % [e0, int(gs.axe_exp_total)], int(gs.axe_exp_total) == e0)
		## 对手斧头碰过我方单位, 别人补刀
		var mine := {"alive": true, "side": "left", "shield": 0.0}
		axsys.on_hit(RK["ax"], mine, false)
		_ok("对手斧头碰过不留「本机斧头碰过」的时间戳", not mine.has("_axe_touch_t"), str(mine.get("_axe_touch_t", "无")))
		mine["alive"] = false
		axsys.on_death(mine, {"alive": true, "side": "right"})
		_ok("★★对手斧头助攻 ⇒ 本机经验不动(%d → %d)" % [e0, int(gs.axe_exp_total)], int(gs.axe_exp_total) == e0)
		## 分母: 本机斧头的击杀 / 助攻照样加
		axsys.on_death({"alive": false, "side": "right"}, LK["ax"])
		_ok("★★分母: 本机斧头击杀 ⇒ +%d(%d → %d)" % [AE.EXP_ON_KILL, e0, int(gs.axe_exp_total)],
			int(gs.axe_exp_total) == e0 + AE.EXP_ON_KILL)
		var foe := {"alive": true, "side": "right", "shield": 0.0}
		axsys.on_hit(LK["ax"], foe, false)
		foe["alive"] = false
		axsys.on_death(foe, {"alive": true, "side": "left"})
		_ok("★★分母: 本机斧头助攻 ⇒ 再 +%d(实测 %d)" % [AE.EXP_ON_KILL, int(gs.axe_exp_total)],
			int(gs.axe_exp_total) == e0 + 2 * AE.EXP_ON_KILL)
	else:
		_ok("★分母: ⑤ 两边都召唤出了斧头", false)

	# ── ⑥ 快照生产侧: 真人上传 / 机器人都带三键; 回放能复现 ──
	_set_local(gs, 345, 3, "seraph")
	var hs: Dictionary = Backend.build_ghost_snapshot("probe_axe_owner", {"name": "x", "avatar": "basic", "id": "probe_axe_owner"})
	_ok("★真人上传的快照带本机砍伐进度(345/金斧/炽天使)",
		int(hs.get("axe_exp_total", -1)) == 345 and int(hs.get("axe_stage", -1)) == 3 and str(hs.get("axe_final", "?")) == "seraph",
		"%s/%s/%s" % [str(hs.get("axe_exp_total", "缺")), str(hs.get("axe_stage", "缺")), str(hs.get("axe_final", "缺"))])
	var rt: Dictionary = AE.progress_of_snapshot(JSON.parse_string(JSON.stringify(hs)))
	_ok("★上传→JSON 往返→对手读出来还是同一份进度", rt == {"total": 345, "stage": 3, "final": "seraph"}, str(rt))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var bot: Dictionary = Backend.make_bot(9, rng)
	var bp: Dictionary = AE.progress_for_battles(9)
	_ok("★机器人快照带三键 = 同场次下界(%s)" % str(bp),
		bot.has("axe_exp_total") and bot.has("axe_stage") and bot.has("axe_final")
			and AE.progress_of_snapshot(bot) == bp,
		"%s/%s/%s" % [str(bot.get("axe_exp_total", "缺")), str(bot.get("axe_stage", "缺")), str(bot.get("axe_final", "缺"))])
	_ok("★回放: 对手进度的来源 dual_ghost 在录像 STATE_KEYS 里", RR.STATE_KEYS.has("dual_ghost"))

	## ★收尾还原(不污染真存档)
	gs.axe_exp_bar = int(bak["bar"])
	gs.axe_exp_total = int(bak["tot"])
	gs.axe_stage = int(bak["st"])
	gs.axe_final = str(bak["fin"])
	gs.dual_ghost = bak["dg"]

	if _n < 24:
		print("  [FAIL] ★分母: 断言只有 %d 条(<24)" % _n)
		_fail += 1
	print("ALL PASS — 096 斧头按主人进度 (%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
