extends Node
## verify_axe_orphan.gd — 096 小木斧「斧头独立存在」(第十批 E2 · 用户 2026-10-04 拍板 V6)
##
## ★由来(方案书 docs/plans/20260915c-087至096第十批十件.md E2 / V6):
##   斧头的每帧推进(攒龟能 / 蓄力 / 造物主动 / 余烬之光到期)原来**只**由携带者的 tick 驱动,
##   主循环跳过死亡单位 ⇒ 携带者一死斧头整条停摆: 蓄力中阵亡 8 秒后仍在蓄力、禁普攻、禁移动、
##   70% 减伤; 余烬之光的 0.25 减伤与 0.25 吸血永久残留。
##   用户原话「斧头独立存在」⇒ 携带者阵亡后斧头照常工作直到战斗结束; 它挂的临时状态
##   换路 / 整场结束时由斧头系统自己收干净。
##
## ★判据全部走真入口: 推 sim 用 `_sim_step`(主循环本体), 换路用 `_dl_clear_units`, 整场结束用 `_dl_finish`。
##   量的是产品自己的字段(damage_reduction / lifesteal / no_move / no_basic / pos / dmg_dealt / energy),
##   不数我插的标记。
## ★不依赖墙钟 / 帧数: 同步调 `_sim_step(SIM_DT)` N 次 = 确切 N×SIM_DT 游戏秒, 与机器快慢无关。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const AF := preload("res://scripts/gamedata/axe_final_stats.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _c() -> Vector2:
	return _s.ARENA.position + _s.ARENA.size * 0.5


func _steps(sec: float) -> void:
	var k: int = int(ceil(sec / _s.SIM_DT))
	for _i in range(k):
		_s._sim_step(_s.SIM_DT, false, false)


## 一个携带者(真带着 096, 走真召唤)+ 一只钉血的友军(保证携带者死后战斗不结束)+ 一个钉血的对手。
func _rig(off_y: float, final_key: String, pv: int) -> Dictionary:
	var carrier: Dictionary = _s._spawn._make_unit("basic", "left", _c() + Vector2(-250, off_y))
	_s._units.append(carrier)
	carrier["equips"] = [{"id": "p2eq_096", "star": 1}]
	carrier["eq_state"] = {}
	carrier["maxHp"] = 1.0e8
	carrier["hp"] = 1.0e8
	var ax = _s._equip_sys._axe.summon(carrier)
	if not (ax is Dictionary):
		return {}
	ax["maxHp"] = 1.0e8
	ax["hp"] = 1.0e8
	ax["_axe_pv"] = pv
	if final_key != "":
		ax["_axe_final"] = final_key
	return {"carrier": carrier, "ax": ax}


func _arena(foe_off: Vector2) -> Dictionary:
	_s._units.clear()
	_s._over = false
	var ally: Dictionary = _s._spawn._make_unit("basic", "left", _c() + Vector2(-600, 300))
	_s._units.append(ally)
	ally["maxHp"] = 1.0e8
	ally["hp"] = 1.0e8
	ally["no_move"] = true
	ally["no_basic"] = true
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", _c() + foe_off)
	_s._units.append(foe)
	foe["maxHp"] = 1.0e8
	foe["hp"] = 1.0e8
	foe["no_move"] = true
	return {"ally": ally, "foe": foe}


func _kill_carrier(carrier: Dictionary, foe: Dictionary) -> void:
	carrier["hp"] = 0.0
	_s._kill(carrier, foe)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 096 小木斧: 携带者阵亡后斧头独立存在(E2 / V6) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s.set_process(false)          # sim 只由本门禁的 _sim_step 推, 不让 _process 按墙钟另推
	_s._edit_mode = false
	if str(_s._dl_state) == "place":
		_s._dl_state = ""

	_t_charge_orphan()
	_t_ember_orphan()
	_t_lane_change()
	_t_battle_end()

	if _n < 30:
		print("  [FAIL] ★分母: 断言只有 %d 条(<30) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 096 斧头独立存在(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  ① 蓄力中携带者阵亡: 斧头照样砸下去、解除定身、接着走路打人
# ══════════════════════════════════════════════════════════════
func _t_charge_orphan() -> void:
	print("--- ① 蓄力中携带者阵亡 ---")
	var ar: Dictionary = _arena(Vector2(150, 0))
	var foe: Dictionary = ar["foe"]
	var r: Dictionary = _rig(0.0, "", 6)
	_ok("★分母: 真召唤出了斧头(AxeSystem.summon)", not r.is_empty())
	if r.is_empty():
		return
	var carrier: Dictionary = r["carrier"]
	var ax: Dictionary = r["ax"]
	var pas = _s._equip_sys._axe._pas
	var dr0: float = float(ax.get("damage_reduction", 0.0))
	ax["energy"] = AE.ACTIVE_ENERGY
	_steps(_s.SIM_DT)
	_ok("★分母: 携带者活着时满龟能走真主循环进了蓄力(被动 6)", pas.is_charging(ax),
		"charging=%s dr=%.2f" % [str(pas.is_charging(ax)), float(ax.get("damage_reduction", 0.0))])
	_ok("★分母: 蓄力挂上了禁移动 / 禁普攻 / 70%% 减伤",
		bool(ax.get("no_move", false)) and bool(ax.get("no_basic", false))
		and is_equal_approx(float(ax.get("damage_reduction", 0.0)), AE.CHARGE_DR))
	_kill_carrier(carrier, foe)
	_ok("★分母: 携带者真的死了、斧头还活着、战斗没结束",
		not bool(carrier.get("alive", true)) and bool(ax.get("alive", false)) and not bool(_s._over),
		"carrier=%s ax=%s over=%s" % [str(carrier.get("alive")), str(ax.get("alive")), str(_s._over)])
	var t0: float = float(_s._t)
	var pos0: Vector2 = ax["pos"]
	_steps(AE.CHARGE_TIME + 0.5)
	_ok("★分母: 游戏钟真的走了 %.1f 秒(钟冻住 = 根本没等)" % (AE.CHARGE_TIME + 0.5),
		float(_s._t) - t0 > AE.CHARGE_TIME, "走了 %.2f 秒" % (float(_s._t) - t0))
	_ok("★★① 携带者死后蓄力照样走完(修前 8 秒后仍在蓄)", not pas.is_charging(ax),
		"charging=%s" % str(pas.is_charging(ax)))
	_ok("★★① 禁移动 / 禁普攻解除", not bool(ax.get("no_move", true)) and not bool(ax.get("no_basic", true)),
		"no_move=%s no_basic=%s" % [str(ax.get("no_move")), str(ax.get("no_basic"))])
	_ok("★★① 70%% 减伤还原成蓄力前(%.2f)" % dr0,
		absf(float(ax.get("damage_reduction", -1.0)) - dr0) < 1e-6,
		"dr=%.3f" % float(ax.get("damage_reduction", -1.0)))
	var e_mid: float = float(ax.get("energy", 0.0))
	var pos_mid: Vector2 = ax["pos"]
	var fhp_mid: float = float(foe.get("hp", 0.0))
	## 走到对手跟前要 ~3 秒、首刀可能被闪避 ⇒ 最多等 12 游戏秒, 一见掉血就停(上限防死循环, 尺子是游戏秒)。
	var t_mid: float = float(_s._t)
	while float(_s._t) - t_mid < 12.0 and float(foe.get("hp", 0.0)) >= fhp_mid:
		_steps(0.25)
	_ok("★★① 携带者死后斧头还在攒龟能(修前一动不动)", float(ax.get("energy", 0.0)) > e_mid,
		"%.2f → %.2f" % [e_mid, float(ax.get("energy", 0.0))])
	var moved: float = (ax["pos"] as Vector2).distance_to(pos_mid)
	_ok("★★① 携带者死后斧头还在走(砸完后又走了 %.0f 码)" % moved, moved > 30.0,
		"pos0=%s 砸完=%s 现在=%s" % [str(pos0), str(pos_mid), str(ax["pos"])])
	## ★量对手掉的血(场上能打它的只有斧头: 友军钉了 no_basic、携带者已死)。
	## ★从「砸完之后」量起: 只算普攻, 不把那一下猛砸算进来。
	var lost: float = fhp_mid - float(foe.get("hp", 0.0))
	_ok("★★① 携带者死后斧头还在打人(对手掉血 %.0f)" % lost, lost > 0.0,
		"砸完后 %.2f 游戏秒 / 斧头到对手距离 %.0f 码" % [float(_s._t) - t_mid, (ax["pos"] as Vector2).distance_to(foe["pos"])])
	_ok("★分母: 整段斧头一直活着(死斧头不动是另一回事)", bool(ax.get("alive", false)))


# ══════════════════════════════════════════════════════════════
#  ② 余烬之光在线时携带者阵亡: 4 秒后照样到期, 减伤 / 吸血还原
# ══════════════════════════════════════════════════════════════
func _t_ember_orphan() -> void:
	print("--- ② 余烬之光在线时携带者阵亡 ---")
	var ar: Dictionary = _arena(Vector2(400, 0))
	var foe: Dictionary = ar["foe"]
	var r: Dictionary = _rig(0.0, "ember", 6)
	if r.is_empty():
		_ok("★分母: 真召唤出了斧头", false)
		return
	var carrier: Dictionary = r["carrier"]
	var ax: Dictionary = r["ax"]
	var fin = _s._equip_sys._axe._fin
	var dr0: float = float(ax.get("damage_reduction", 0.0))
	var ls0: float = float(ax.get("lifesteal", 0.0))
	ax["energy"] = AE.ACTIVE_ENERGY
	_steps(_s.SIM_DT)
	_ok("★分母: 携带者活着时走真主循环放出了余烬之光(1 层)", fin.ember_light_stacks(ax) == 1,
		"层数 %d" % fin.ember_light_stacks(ax))
	_ok("★分母: 在线时减伤 %.2f / 吸血 %.2f" % [AF.EMBER_LIGHT_DR, AF.EMBER_LIGHT_LIFESTEAL],
		is_equal_approx(float(ax.get("damage_reduction", 0.0)), maxf(dr0, AF.EMBER_LIGHT_DR))
		and is_equal_approx(float(ax.get("lifesteal", 0.0)), maxf(ls0, AF.EMBER_LIGHT_LIFESTEAL)),
		"dr=%.2f ls=%.2f" % [float(ax.get("damage_reduction", 0.0)), float(ax.get("lifesteal", 0.0))])
	_kill_carrier(carrier, foe)
	_ok("★分母: 携带者死了、斧头活着、战斗没结束",
		not bool(carrier.get("alive", true)) and bool(ax.get("alive", false)) and not bool(_s._over))
	_steps(AF.EMBER_LIGHT_TIME + 0.5)
	_ok("★★② 携带者死后余烬之光照样到期(修前永久在线)", fin.ember_light_stacks(ax) == 0,
		"层数 %d" % fin.ember_light_stacks(ax))
	_ok("★★② 减伤还原成施放前(%.2f)" % dr0, absf(float(ax.get("damage_reduction", -1.0)) - dr0) < 1e-6,
		"dr=%.3f" % float(ax.get("damage_reduction", -1.0)))
	_ok("★★② 吸血还原成施放前(%.2f)" % ls0, absf(float(ax.get("lifesteal", -1.0)) - ls0) < 1e-6,
		"ls=%.3f" % float(ax.get("lifesteal", -1.0)))


## 摆三把斧头, 各自挂上一种临时状态: 蓄力 + 余烬之光 / 全息插地 / 炽天使甩镖(含在途镖)。
## ★一把的携带者已阵亡(孤儿), 证明收尾不分有主无主。
func _rig_busy() -> Array:
	var ar: Dictionary = _arena(Vector2(300, 0))
	var foe: Dictionary = ar["foe"]
	var r1: Dictionary = _rig(-200.0, "ember", 6)
	var r2: Dictionary = _rig(0.0, "holo", 6)
	var r3: Dictionary = _rig(200.0, "seraph", 6)
	if r1.is_empty() or r2.is_empty() or r3.is_empty():
		return []
	var pas = _s._equip_sys._axe._pas
	for r in [r1, r2, r3]:
		(r["ax"] as Dictionary)["energy"] = AE.ACTIVE_ENERGY
	_steps(_s.SIM_DT)
	_steps(0.5)                         # 炽天使甩出几把镖, 让在途表非空
	pas.begin_charge(r1["ax"])          # 余烬那把再叠一个蓄力(两种状态同时在身上)
	_kill_carrier(r1["carrier"], foe)   # 余烬那把变成孤儿
	_steps(_s.SIM_DT)
	return [r1["ax"], r2["ax"], r3["ax"]]


func _check_clean(tag: String, axes: Array) -> void:
	var fin = _s._equip_sys._axe._fin
	var pas = _s._equip_sys._axe._pas
	var names := ["余烬+蓄力(孤儿)", "全息插地", "炽天使"]
	for i in range(axes.size()):
		var ax: Dictionary = axes[i]
		var dr: float = float(ax.get("damage_reduction", -1.0))
		var ls: float = float(ax.get("lifesteal", -1.0))
		_ok("★★%s %s: 减伤 / 吸血回到 0" % [tag, names[i]], absf(dr) < 1e-6 and absf(ls) < 1e-6,
			"dr=%.3f ls=%.3f" % [dr, ls])
		_ok("★★%s %s: 禁移动 / 禁普攻 / 蓄力 / 插地 / 甩镖全收掉" % [tag, names[i]],
			not bool(ax.get("no_move", false)) and not bool(ax.get("no_basic", false))
			and not pas.is_charging(ax) and not fin.active_busy(ax) and fin.ember_light_stacks(ax) == 0,
			"no_move=%s no_basic=%s charging=%s busy=%s ember=%d" % [str(ax.get("no_move")), str(ax.get("no_basic")),
				str(pas.is_charging(ax)), str(fin.active_busy(ax)), fin.ember_light_stacks(ax)])
	_ok("★★%s 在途回旋镖清空" % tag, fin._booms.is_empty(), "剩 %d 把" % fin._booms.size())


func _busy_denominators(axes: Array) -> void:
	var fin = _s._equip_sys._axe._fin
	var pas = _s._equip_sys._axe._pas
	_ok("★分母: 三把斧头都摆好了", axes.size() == 3)
	if axes.size() != 3:
		return
	_ok("★分母: 余烬那把同时在蓄力 + 余烬之光在线 + 携带者已阵亡",
		pas.is_charging(axes[0]) and fin.ember_light_stacks(axes[0]) >= 1
		and not bool((axes[0] as Dictionary)["summon_owner"].get("alive", true)),
		"charging=%s ember=%d" % [str(pas.is_charging(axes[0])), fin.ember_light_stacks(axes[0])])
	_ok("★分母: 全息那把正插在地里(定身 + 30%% 减伤)",
		(axes[1] as Dictionary).has("_holo_until") and bool((axes[1] as Dictionary).get("no_move", false))
		and float((axes[1] as Dictionary).get("damage_reduction", 0.0)) > 0.0)
	_ok("★分母: 炽天使正在甩、且有在途镖", (axes[2] as Dictionary).has("_seraph_until") and not fin._booms.is_empty(),
		"在途 %d 把" % fin._booms.size())


# ══════════════════════════════════════════════════════════════
#  ③ 换路(真入口 _dl_clear_units): 斧头挂的临时状态全部收掉
# ══════════════════════════════════════════════════════════════
func _t_lane_change() -> void:
	print("--- ③ 换路 ---")
	var axes: Array = _rig_busy()
	_busy_denominators(axes)
	if axes.size() != 3:
		return
	_s._dl_sys._dl_clear_units()
	_ok("★分母: 真入口清了场(_units 空了)", _s._units.is_empty(), "剩 %d" % _s._units.size())
	_check_clean("③换路", axes)


# ══════════════════════════════════════════════════════════════
#  ④ 整场结束(真入口 _dl_finish): 同样收掉
# ══════════════════════════════════════════════════════════════
func _t_battle_end() -> void:
	print("--- ④ 整场结束 ---")
	var axes: Array = _rig_busy()
	_busy_denominators(axes)
	if axes.size() != 3:
		return
	_s._dl_sys._dl_finish(true)
	_ok("★分母: 真入口判了整场结束(_over)", bool(_s._over))
	_check_clean("④整场结束", axes)
