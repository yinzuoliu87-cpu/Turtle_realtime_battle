extends Node
## verify_chest_ledger.gd — 宝箱龟「本场宝箱账」(2026-10-22 · 修 B/C/D/E/F/G)
##
## ══════════════════════════════════════════════════════════════════════
##  由来(审计已用探针实测, 这里一条一条焊住)
## ══════════════════════════════════════════════════════════════════════
##   B 敌方跨路丢进度: 每一路单位字典重建, 敌方 chest_opened 回到快照件数、本路开出的战利品丢掉;
##     seed 11 实测敌方第一路开出锁链, 终极路又开一次第 1 箱(血筛子), 锁链没了。
##   C 局内财宝条: 当前值读本路 dmg_dealt、已开数读 u.chest_opened(我方从来不设), 且本路 0 伤害整条不显示。
##   D 清点财宝: 敌方只看本路 dmg_dealt、不读快照基数 ⇒ 同样财宝值敌方回得少(实测 12000 时 11% vs 5%)。
##   E 调试场写真存档: 宝箱只排除评审台; 调试场里开箱当场 GameState.save(), 还把真存档的战利品装上。
##   F 持续伤害不计财宝值(只有 _apply_damage_from 累加 dmg_dealt) —— 用户 2026-10-22 拍板「算」。
##   G 宝箱龟阵亡后不再 tick, 风暴余下几跳进了 dmg_dealt 却没进财宝值。
##
## ★修法: ChestSystem 里左右两侧各一本账(不挂单位字典), 伤害落地那一刻在两条伤害路里进账,
##   开箱 / 清点财宝 / 面板三处读同一个取数口 `treasure_progress`; 只有计分对局的左方写存档。
##
## ★判据一律量产品自己的账, 且与被测的账【不同源】: 敌人承伤 `_st_taken`、伤害统计 `_st_dealt`、
##   GameState 存档字段、面板 `_resource_bars` 的行、单位身上真的装着的战利品 —— 不数我自己插的标记。
##   每条断言配分母(那件事真的发生过), 否则"没变"可能只是"什么都没做"。
##
## ★⑦ 用真对局: 服务器裁判跑一局(真入口 RefereeRunner, 双方宝箱龟), 再拿它的录像走「中途退出补打」
##   那条本机复算路真打到 `_settle_season`(= 本机计分对局), 两边对账。
##
## 跑法: <godot> --headless --path . res://tests/verify_chest_ledger.tscn --quit-after 8000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Chest := preload("res://scripts/systems/skills/chest_system.gd")
const Backend := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const MID := "5c3e9a71-2b4d-4e6f-8a1b-3c5d7e9f1a2b"
const SEED := 2000023
## 对局里双方宝箱龟的起点(审计那局同一个数): 离第 1 箱 3000 只差 200, 第一路就会开箱
const BASE_REAL := 2800.0

var _n := 0
var _fail := 0
var _gs
var _s
var _cs
var _c0 := Vector2.ZERO
var _rec: Dictionary = {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


# ───────────────────────────── 造单位 / 读数 ─────────────────────────────

## 宝箱龟走真登场路(`_apply_spawn_passive_one`: 回装战利品 + 贪婪), 不手搓 chest_treasures。
func _chest(side: String, at: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("chest", side, at)
	u["no_basic"] = true
	u["no_move"] = true
	_s._units.append(u)
	_s._spawn._apply_spawn_passive_one(u)
	return u


func _dummy(side: String, at: Vector2) -> Dictionary:
	var e: Dictionary = _s._spawn._make_unit("basic", side, at)
	e["maxHp"] = 1.0e7
	e["hp"] = 1.0e7
	e["no_basic"] = true
	e["no_move"] = true
	e["dodge_bonus"] = 0.0
	_s._units.append(e)
	return e


func _val(u: Dictionary) -> float:
	return float(_cs.treasure_progress(u)["value"])


func _opened(u: Dictionary) -> int:
	return int(_cs.treasure_progress(u)["opened"])


func _taken(e: Dictionary) -> float:
	return float(e.get("_st_taken", 0))


func _loot(u: Dictionary) -> Array:
	var k: Array = (u.get("chest_treasures", {}) as Dictionary).keys()
	k.sort()
	return k


## 真伤一段(无视护甲, 量多少就是多少; 暴击掷骰会让它更大, 判据只量差值不量名义值)。
func _hit(src: Dictionary, e: Dictionary, amt: int) -> float:
	var t0 := _taken(e)
	_s._damage._apply_damage_from(src, e, amt, Color.RED, 0.0, true)
	return _taken(e) - t0


## dev = 开发工具场(调试场)与否; scored = 有赛季阵容(计分对局)与否。账从头记, 按新形态重取起点。
func _mode(dev: bool, scored: bool) -> void:
	RB.DEBUG_EDIT = dev
	_gs.tutorial_active = false
	_gs.season_leaders = ["chest", "basic", "stone"] if scored else []
	_s._units.clear()
	_s._pending_shots.clear()
	_cs.reset_ledger()


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.01


# ───────────────────────────────── 主流程 ─────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	print("=== 宝箱龟本场宝箱账(B/C/D/E/F/G) ===")
	_gs = get_node_or_null("/root/GameState")
	_ok("分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	_gs.test_mode = true                 # 任何 save() 空转(本条量的是内存里的存档字段)
	var backup: Dictionary = ReplayRecorder.capture_all()

	RB.DEBUG_EDIT = true                 # 建场走调试场(不进赛季流程); 之后按用例切形态
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)                # 手动驱动: 每一步由用例自己调, 与帧率无关
	_s.set_physics_process(false)
	_s._debug._edit_clear()
	_s._edit_mode = false
	_s._over = false
	_cs = _s._chest_sys
	_c0 = _s.ARENA.position + _s.ARENA.size * 0.5

	_t_f_dot()
	_t_g_after_death()
	_t_d_inventory()
	_t_c_panel()
	_t_e_no_write()
	_t_b_cross_lane()

	_s._units.clear()
	_s._pending_shots.clear()
	_s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	RB.DEBUG_EDIT = false
	for n in backup:
		var v = backup[n]
		_gs.set(str(n), v.duplicate(true) if (v is Array or v is Dictionary) else v)

	await _t_real_match()

	for n in backup:
		var v = backup[n]
		_gs.set(str(n), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	_finish()


# ── ⑤ F: 持续伤害(_apply_damage 那条路)也计财宝值 ─────────────────────────────
func _t_f_dot() -> void:
	print("--- ⑤ F 持续伤害计入财宝值 ---")
	_mode(false, true)
	_gs.chest_treasure_value = 1000.0
	_gs.chest_treasures_won = []
	var c := _chest("left", _c0 + Vector2(-150, 0))
	var e := _dummy("right", _c0 + Vector2(150, 0))
	e["maxHp"] = 20000.0                            # 灼烧每跳带最大生命比例, 千万血的靶子会跳出几十万的数
	e["hp"] = 20000.0
	var v0 := _val(c)
	var g0 := float(_gs.chest_treasure_value)
	var dd0 := float(c.get("dmg_dealt", 0.0))
	var t0 := _taken(e)
	## 真的持续伤害入口: 宝箱龟给敌人叠灼烧(dot_src = 宝箱龟), 跳一次(_tick_dot_stacks → _apply_damage)
	_s._damage._apply_dot_stacks(e, "burn", 40, c)
	_s._tick_dot_stacks(e)
	var dt := _taken(e) - t0
	_ok("⑤ 分母: 灼烧真的跳了一次(敌人承伤 %.0f)" % dt, dt > 0.0)
	_ok("★★⑤ F 持续伤害计入财宝值(增量 %.0f == 这一跳承伤 %.0f)" % [_val(c) - v0, dt], _approx(_val(c) - v0, dt))
	_ok("★⑤ F 计分对局的我方: 存档财宝值同步 +%.0f" % dt, _approx(float(_gs.chest_treasure_value) - g0, dt),
		"存档 %.0f → %.0f" % [g0, float(_gs.chest_treasure_value)])
	_ok("⑤ dmg_dealt 的含义没动(持续伤害仍不进 dmg_dealt, 它别的消费者照旧)",
		_approx(float(c.get("dmg_dealt", 0.0)), dd0))
	## 反面: 打自己不算
	var v1 := _val(c)
	var hp1 := float(c["hp"])
	_s._damage._apply_damage(c, 50, Color.RED, c, "dot", true)
	_ok("⑤ 反面分母: 自伤真的扣了血", float(c["hp"]) < hp1)
	_ok("★⑤ 反面: 宝箱龟打自己不计财宝值", _approx(_val(c), v1))


# ── ⑥ G: 阵亡后风暴余下几跳照样计入 ─────────────────────────────────────────
func _t_g_after_death() -> void:
	print("--- ⑥ G 阵亡后风暴余跳计入 ---")
	_mode(false, true)
	_gs.chest_treasure_value = 0.0
	_gs.chest_treasures_won = []
	var c := _chest("left", _c0 + Vector2(-150, 0))
	var e := _dummy("right", _c0 + Vector2(100, 0))
	_cs._sk_chest_storm(c, e)                       # 真技能: 5 跳挂进 _pending_shots
	_s._ballistics._step_pending_shots(0.01)        # 第 1 跳(delay 0)
	_s._kill(c)                                     # 风暴放出后宝箱龟阵亡
	_ok("⑥ 分母: 宝箱龟确实阵亡", not bool(c.get("alive", true)))
	var v0 := _val(c)
	var g0 := float(_gs.chest_treasure_value)
	var t0 := _taken(e)
	for _k in range(Chest.STORM_TICKS):
		_s._ballistics._step_pending_shots(Chest.STORM_TICK_SEC)
	var dt := _taken(e) - t0
	_ok("⑥ 分母: 阵亡之后风暴还在跳(敌人又承伤 %.0f)" % dt, dt > 0.0)
	_ok("★★⑥ G 阵亡后的那几跳照样计入财宝值(+%.0f / 承伤 %.0f)" % [_val(c) - v0, dt], _approx(_val(c) - v0, dt))
	_ok("★⑥ G 计分对局的我方: 存档财宝值也同步(原来只在存活时逐帧补记, 死了就漏)",
		_approx(float(_gs.chest_treasure_value) - g0, dt), "存档 %.0f → %.0f" % [g0, float(_gs.chest_treasure_value)])
	## 同一个形状的另一张脸: 活着打出的【制胜一击】—— 打完战斗当场结束, 后面再没有一次逐帧补记。
	##   改前实测(只有我方带宝箱龟、种子 99、终极路): 宝箱龟最后一下 240 点打完 `_over = true`,
	##   存档记 4881, 改后 5121, 终局指纹两边相同(战斗本身一点没变, 只是这一下原来没记上)。
	##   这里不调 `_chest_treasure_tick`: 进账不该等 tick。
	var c2 := _chest("left", _c0 + Vector2(-150, 60))
	var g1 := float(_gs.chest_treasure_value)
	var d2 := _hit(c2, e, 240)
	_ok("⑥ 分母: 这一击真的打出去了(%.0f)" % d2, d2 > 0.0)
	_ok("★⑥ 活着的一击也不等 tick: 落地那一刻存档就 +%.0f(制胜一击打完战斗就结束, 改前这一下会漏)" % d2,
		_approx(float(_gs.chest_treasure_value) - g1, d2), "存档 %.0f → %.0f" % [g1, float(_gs.chest_treasure_value)])


# ── ③ D: 同样累计财宝值, 敌我清点财宝回血相同 ─────────────────────────────────
func _t_d_inventory() -> void:
	print("--- ③ D 清点财宝敌我一致 ---")
	_mode(false, false)
	_gs.chest_treasure_value = 12000.0
	_gs.chest_treasures_won = []
	_gs.dual_ghost = {"chest_treasure_value": 12000.0, "chest_treasures_won": []}
	var lc := _chest("left", _c0 + Vector2(-150, -80))
	var rc := _chest("right", _c0 + Vector2(150, -80))
	_ok("③ 分母: 敌我累计财宝值都是 12000(我方读存档 / 敌方读快照)", _approx(_val(lc), 12000.0) and _approx(_val(rc), 12000.0),
		"%.0f / %.0f" % [_val(lc), _val(rc)])
	var heals: Array = []
	for u in [lc, rc]:
		u["maxHp"] = 2000.0
		u["hp"] = 100.0
		u["atk"] = 100.0
		u["shield"] = 0.0
		var h0 := float(u["hp"])
		_cs._sk_chest_inventory(u)
		heals.append(float(u["hp"]) - h0)
	var want: float = 2000.0 * Chest.COUNT_HEAL_PCT * (1.0 + Chest.COUNT_HEAL_BONUS * floorf(12000.0 / Chest.COUNT_PER_TREASURE))
	_ok("★★③ D 同样财宝值敌我回血相同(我方 %.1f / 敌方 %.1f)" % [heals[0], heals[1]], _approx(heals[0], heals[1]))
	_ok("★③ D 回血 = 最大生命 × 5%% × (1 + 10%% × 12) = %.0f(加成真的吃到了快照基数)" % want, _approx(heals[1], want),
		"敌方实回 %.1f" % heals[1])


# ── ② C: 面板财宝条 = 累计值 / 下一阈值 + 已开数, 0 伤害也显示 ─────────────────────
func _bar(u: Dictionary) -> Dictionary:
	for r in _s._info_sys._resource_bars(u):
		if str((r as Dictionary).get("name", "")) == "财宝":
			return r
	return {}


func _t_c_panel() -> void:
	print("--- ② C 面板财宝条 ---")
	_mode(false, false)
	_gs.chest_treasure_value = 4500.0
	_gs.chest_treasures_won = ["dagger"]
	_gs.dual_ghost = {"chest_treasure_value": 7000.0, "chest_treasures_won": ["rum", "chain"]}
	var lc := _chest("left", _c0 + Vector2(-150, 0))
	var rc := _chest("right", _c0 + Vector2(150, 0))
	var bl := _bar(lc)
	var br := _bar(rc)
	_ok("② 分母: 本场 0 伤害 —— 敌我都没出过手", float(lc.get("dmg_dealt", 0.0)) == 0.0 and float(rc.get("dmg_dealt", 0.0)) == 0.0)
	_ok("★★② C 本场 0 伤害也显示财宝条(原来 dmg_dealt == 0 整条不建)", not bl.is_empty() and not br.is_empty())
	_ok("★★② C 我方: 当前 = 存档累计 4500, 分母 = 第 2 箱阈值 %.0f" % float(RB._CHEST_THRESH[1]),
		_approx(float(bl.get("cur", -1)), 4500.0) and _approx(float(bl.get("cap", -1)), float(RB._CHEST_THRESH[1])),
		"%s / %s" % [str(bl.get("cur")), str(bl.get("cap"))])
	_ok("★② C 我方已开数印出来了(已开 1/5)", str(bl.get("hint", "")).find("已开 1/5") >= 0, str(bl.get("hint", "")))
	_ok("★★② C 敌方: 当前 = 快照累计 7000, 分母 = 第 3 箱阈值 %.0f" % float(RB._CHEST_THRESH[2]),
		_approx(float(br.get("cur", -1)), 7000.0) and _approx(float(br.get("cap", -1)), float(RB._CHEST_THRESH[2])),
		"%s / %s" % [str(br.get("cur")), str(br.get("cap"))])
	_ok("★② C 敌方已开数印出来了(已开 2/5)", str(br.get("hint", "")).find("已开 2/5") >= 0, str(br.get("hint", "")))
	## 数会跟着走: 记一段持续伤害后, 条上的当前值 + 面板重建签名都要变(签名不变 = 面板不刷新)
	var e := _dummy("right", _c0 + Vector2(150, 120))
	var sig0: String = _s._info_sys._status_sig_own(lc)
	var t0 := _taken(e)
	_s._damage._apply_damage(e, 300, Color.RED, lc, "dot")
	var dt := _taken(e) - t0
	_ok("② 分母: 这一段真的打出去了(%.0f)" % dt, dt > 0.0)
	_ok("★② C 条上的当前值跟着涨(4500 + %.0f)" % dt, _approx(float(_bar(lc).get("cur", -1)), 4500.0 + dt))
	_ok("② C 面板重建签名跟着变(否则停在开面板那一刻)", _s._info_sys._status_sig_own(lc) != sig0)
	## 逐帧直播播放端不画: 那里一步 sim 都不跑(账是空的), 流里也不带财宝值 ⇒ 画出来就是把开局起点当实时数
	var m0 := str(_s._replay.mode)
	_s._replay.mode = "stream"
	var bs := _bar(lc)
	_s._replay.mode = m0
	_ok("② C 逐帧直播播放端不画财宝条(与改之前同: 那里本来就拿不到实时财宝值)", bs.is_empty())
	## 登场回装: 存档那件 / 快照那两件真的装在身上
	_ok("② 登场回装: 我方身上 = [dagger], 敌方 = [chain, rum]", _loot(lc) == ["dagger"] and _loot(rc) == ["chain", "rum"],
		"%s / %s" % [str(_loot(lc)), str(_loot(rc))])


# ── ④ E: 调试场 / 非计分对局不写存档 ─────────────────────────────────────────
func _t_e_no_write() -> void:
	print("--- ④ E 只有计分对局写存档 ---")
	## E1 调试场(开发工具场): 起点不读存档、开箱不写存档。★season_leaders 照样给 —— 证明是「开发工具场」这一条在挡。
	_mode(true, true)
	_ok("④ 分母: 调试场 = 开发工具场, 且不是计分对局", _s._world_builder._is_dev_tool_battle() and not _s._world_builder._is_scored_match())
	_gs.chest_treasure_value = 2900.0
	_gs.chest_treasures_won = ["dagger"]
	var c := _chest("left", _c0 + Vector2(-150, 0))
	var e := _dummy("right", _c0 + Vector2(150, 0))
	_ok("★④ E1 调试场登场不装真存档里的战利品", not (c.get("chest_treasures", {}) as Dictionary).has("dagger"), str(_loot(c)))
	_ok("④ E1 调试场的账起点为空(0 / 0 件)", _approx(_val(c), 0.0) and _opened(c) == 0)
	_hit(c, e, 3200)
	_cs._chest_treasure_tick(c)
	_ok("④ E1 分母: 调试场里真的开出了第 1 箱", _opened(c) == 1 and _loot(c).size() == 1, str(_loot(c)))
	_ok("★★④ E1 存档财宝值没动(2900)", _approx(float(_gs.chest_treasure_value), 2900.0), str(_gs.chest_treasure_value))
	_ok("★★④ E1 存档战利品没动([dagger])", _gs.chest_treasures_won == ["dagger"], str(_gs.chest_treasures_won))

	## E2 非开发工具、但不计分(没有赛季阵容: 演示 / 回放播放一类): 起点读存档, 但不写
	_mode(false, false)
	_gs.chest_treasure_value = 2900.0
	_gs.chest_treasures_won = []
	c = _chest("left", _c0 + Vector2(-150, 0))
	e = _dummy("right", _c0 + Vector2(150, 0))
	_ok("④ 分母: 不计分(_is_scored_match = false)", not _s._world_builder._is_scored_match())
	_ok("④ E2 分母: 起点读的是存档(2900)", _approx(_val(c), 2900.0))
	_hit(c, e, 200)
	_cs._chest_treasure_tick(c)
	_ok("④ E2 分母: 开出了第 1 箱", _opened(c) == 1)
	_ok("★★④ E2 不计分对局: 存档财宝值 / 战利品都没动",
		_approx(float(_gs.chest_treasure_value), 2900.0) and (_gs.chest_treasures_won as Array).is_empty(),
		"%s %s" % [str(_gs.chest_treasure_value), str(_gs.chest_treasures_won)])

	## E3 对照: 计分对局才写 —— 证明上面两条"没动"不是因为写的那条路本来就不通
	_mode(false, true)
	_gs.chest_treasure_value = 2900.0
	_gs.chest_treasures_won = []
	c = _chest("left", _c0 + Vector2(-150, 0))
	e = _dummy("right", _c0 + Vector2(150, 0))
	_ok("④ 分母: 计分对局(_is_scored_match = true)", _s._world_builder._is_scored_match())
	var dt := _hit(c, e, 200)
	_cs._chest_treasure_tick(c)
	_ok("★④ E3 对照: 计分对局存档财宝值 +本场伤害(2900 + %.0f)" % dt, _approx(float(_gs.chest_treasure_value), 2900.0 + dt),
		str(_gs.chest_treasure_value))
	_ok("★④ E3 对照: 计分对局存档记上新开的那件", _gs.chest_treasures_won == _loot(c) and _loot(c).size() == 1,
		"%s / 身上 %s" % [str(_gs.chest_treasures_won), str(_loot(c))])
	## E4 入口: 设置页进调试场就是置 DEBUG_EDIT(上面 E1 量的就是这个形态) —— 不靠 test_mode
	var ss := FileAccess.get_file_as_string("res://scripts/scenes/SettingsScene.gd")
	_ok("④ E4 设置页的调试场入口置 DEBUG_EDIT(= E1 那个形态)", ss.find("_RB_DEBUG.DEBUG_EDIT = true") >= 0)


# ── ① B: 敌方跨路不丢进度(单位字典整个重建) ─────────────────────────────────────
func _t_b_cross_lane() -> void:
	print("--- ① B 敌方跨路 ---")
	_mode(false, true)
	_gs.dual_ghost = {"chest_treasure_value": 2900.0, "chest_treasures_won": []}
	var r1 := _chest("right", _c0 + Vector2(150, 0))
	var e := _dummy("left", _c0 + Vector2(-150, 0))
	_ok("① 分母: 敌方起点读对手快照(2900 / 0 件)", _approx(_val(r1), 2900.0) and _opened(r1) == 0)
	var d1 := _hit(r1, e, 200)
	_cs._chest_treasure_tick(r1)
	var lane1: Array = _loot(r1)
	_ok("① 分母: 第一路开出 1 件", _opened(r1) == 1 and lane1.size() == 1, str(lane1))
	## 换路: 与 dual_lane_flow 一样, 单位字典整个重建(_make_unit + 登场被动)
	_s._units.clear()
	var r2 := _chest("right", _c0 + Vector2(150, 0))
	e = _dummy("left", _c0 + Vector2(-150, 0))
	_ok("★★★① B 第二路开局身上带着第一路开出的那件", lane1.size() == 1 and _loot(r2) == lane1,
		"第二路登场 %s / 第一路开出 %s" % [str(_loot(r2)), str(lane1)])
	_ok("★★① B 已开数延续(1), 财宝值延续(2900 + %.0f)" % d1, _opened(r2) == 1 and _approx(_val(r2), 2900.0 + d1),
		"已开 %d 值 %.0f" % [_opened(r2), _val(r2)])
	_hit(r2, e, 100)
	_cs._chest_treasure_tick(r2)
	_ok("★★① B 不重开第 1 箱(没到第 2 箱阈值 6000 就不开)", _opened(r2) == 1 and _loot(r2) == lane1,
		"值 %.0f 已开 %d 身上 %s" % [_val(r2), _opened(r2), str(_loot(r2))])
	_hit(r2, e, 3000)
	_cs._chest_treasure_tick(r2)
	_ok("① B 到第 2 箱阈值才开第 2 箱, 与第一件不重复", _opened(r2) == 2 and _loot(r2).size() == 2,
		"值 %.0f 身上 %s" % [_val(r2), str(_loot(r2))])
	var fr: Dictionary = _cs.ledger_final("right")
	_ok("① 账: ledger_final(右) = 快照 0 件 + 本场两件, 顺序 = 开出顺序", (fr["chest_treasures_won"] as Array).size() == 2
		and str((fr["chest_treasures_won"] as Array)[0]) == str(lane1[0]), str(fr))


# ── ⑦ 真对局: 裁判跑一局 + 同一局本机复算到结算 ─────────────────────────────────

## 阵容快照(真生产函数 build_ghost_snapshot)。装备留空: 本局不出额外真伤(金弹 / 腐蚀 / 墨迹), 伤害统计才与财宝账同口径可比。
func _snap(leaders: Array, top: Array, bottom: Array, val: float, gid: String) -> Dictionary:
	_gs.reset_dual_lane()
	_gs.season_leaders = leaders.duplicate()
	_gs.left_team.assign(leaders)
	var pe := {}
	for p in leaders:
		pe[p] = []
	_gs.persistent_equipped = pe
	var dl := {"top": [], "bottom": []}
	for p in top:
		(dl["top"] as Array).append({"kind": "leader", "slot": leaders.find(p), "id": p})
	(dl["top"] as Array).append({"kind": "minion", "role": "front", "equips": []})
	for p in bottom:
		(dl["bottom"] as Array).append({"kind": "leader", "slot": leaders.find(p), "id": p})
	(dl["bottom"] as Array).append({"kind": "minion", "role": "back", "equips": []})
	_gs.dual_lineup = dl
	_gs.season_level = 6
	_gs.chest_treasure_value = val
	_gs.chest_treasures_won = []
	return Backend.build_ghost_snapshot(gid, {"name": gid, "avatar": leaders[0], "id": gid})


func _job(a: Dictionary, b: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify({"v": 1, "job_id": 1, "match_id": MID, "mode": "gauntlet",
		"key": {"week": 1}, "seed": SEED, "client_version": ReplayRecorder.client_version(), "a": a, "b": b}))


## 每一步末尾采一次(sim_stepped 在步尾发): 认出每个宝箱龟实例(is_same), 记它登场那一刻身上的战利品、
## 最后一次还活着时的 dmg_dealt(= 修之前的口径: 只在存活时逐帧补记), 以及这一刻的取数口。
func _sample(battle) -> void:
	var lane := str(_gs.current_lane)
	var insts: Array = _rec["inst"]
	for u in battle._units:
		if str(u.get("id", "")) != "chest" or bool(u.get("is_summon", false)):
			continue
		var hit = null
		for r in insts:
			if is_same(r["u"], u):
				hit = r
				break
		if hit == null:
			hit = {"u": u, "side": str(u["side"]), "lane": lane, "loot0": _loot(u), "dd_alive": 0.0}
			insts.append(hit)
		if bool(u.get("alive", false)):
			hit["dd_alive"] = float(u.get("dmg_dealt", 0.0))
	_rec["fl"] = battle._chest_sys.ledger_final("left")
	_rec["fr"] = battle._chest_sys.ledger_final("right")
	_rec["gs"] = [float(_gs.chest_treasure_value), (_gs.chest_treasures_won as Array).duplicate()]
	_rec["steps"] = int(_rec.get("steps", 0)) + 1


func _sum(side: String, key: String) -> float:
	var t := 0.0
	for r in _rec["inst"]:
		if str(r["side"]) != side:
			continue
		if key == "dd_alive":
			t += float(r["dd_alive"])
		else:
			t += float((r["u"] as Dictionary).get(key, 0.0))
	return t


func _t_real_match() -> void:
	print("--- ⑦ 真对局(裁判 + 本机复算) ---")
	_gs.tutorial_active = false
	RB.DEBUG_EDIT = false
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600   # 一个周六中午(用完还原)
	var a := _snap(["chest", "basic", "stone"], ["chest"], ["basic", "stone"], BASE_REAL, "g_ledger_a")
	## B: 宝箱龟与忍者同在上路(上路赢面大、宝箱龟活到终极路), 下路只放熔岩(下路输 ⇒ 1:1 进终极)
	var b := _snap(["chest", "ninja", "lava"], ["chest", "ninja"], ["lava"], BASE_REAL, "g_ledger_b")

	# ── 裁判 ──
	_rec = {"inst": []}
	var on_battle := func(bt) -> void:
		bt.sim_stepped.connect(_sample.bind(bt))
	var res: Dictionary = await RefereeRunner.run(self, _job(a, b), on_battle)
	_ok("⑦ 分母 · 裁判算完(ok)", bool(res.get("ok", false)), str(res.get("error", "")))
	if not bool(res.get("ok", false)):
		P2C.now_override_ts = 0
		return
	var lanes: Dictionary = res.get("lane_results", {})
	print("  [量] 裁判: winner=%s lanes=%s steps=%d digest=%s" % [str(res["winner"]), str(lanes), int(res.get("steps", 0)), str(res["digest"])])
	var rights: Array = []
	var lefts_ref: Array = []
	for r in _rec["inst"]:
		print("  [量]   %s lane=%s 登场身上=%s 收场身上=%s alive=%s dmg_dealt=%.0f _st_dealt=%.0f" % [r["side"], r["lane"], str(r["loot0"]),
			str(_loot(r["u"])), str((r["u"] as Dictionary).get("alive")), float((r["u"] as Dictionary).get("dmg_dealt", 0.0)),
			float((r["u"] as Dictionary).get("_st_dealt", 0.0))])
		if str(r["side"]) == "right":
			rights.append(r)
		else:
			lefts_ref.append(r)
	var fl_ref: Dictionary = _rec.get("fl", {})
	var fr_ref: Dictionary = _rec.get("fr", {})
	print("  [量]   ledger_final 左=%s 右=%s" % [str(fl_ref), str(fr_ref)])

	## B(真对局): 敌方宝箱龟在后一路登场时, 身上 = 它前几路开出的全部
	_ok("⑦ 分母 · 敌方宝箱龟跨了两路(上路 + 终极路), 且第一路就开出了战利品",
		rights.size() >= 2 and _loot(rights[0]["u"]).size() >= 1, "%d 个实例" % rights.size())
	if rights.size() >= 2:
		var before: Array = _loot(rights[rights.size() - 2]["u"])
		var last: Dictionary = rights[rights.size() - 1]
		_ok("★★★⑦ B 真对局: 敌方后一路登场时身上 = 前一路收场时的全部战利品(%s)" % str(before),
			last["loot0"] == before, "后一路登场 %s" % str(last["loot0"]))
	var frw: Array = fr_ref.get("chest_treasures_won", [])
	var uniq := {}
	for t in frw:
		uniq[str(t)] = true
	_ok("★⑦ B 真对局: 敌方整局开出的战利品没有重复(原来终极路会重开第 1 箱)", uniq.size() == frw.size() and frw.size() >= 1, str(frw))

	## 取数口(给主会话写裁判结果单): 形状与存档字段同名同型
	_ok("⑦ 取数口 ledger_final 形状: {chest_treasure_value: float, chest_treasures_won: Array[String]}",
		fl_ref.get("chest_treasure_value") is float and fl_ref.get("chest_treasures_won") is Array)
	_ok("★★⑦ 裁判: 左方累计 = 起点 %.0f + 宝箱龟整局全部伤害(伤害统计 _st_dealt 之和 %.0f, 另一本账)" % [BASE_REAL, _sum("left", "_st_dealt")],
		_approx(float(fl_ref.get("chest_treasure_value", -1.0)), BASE_REAL + _sum("left", "_st_dealt")) and _sum("left", "_st_dealt") > 0.0,
		"取数口 %.0f" % float(fl_ref.get("chest_treasure_value", -1.0)))

	# ── 同一局本机复算到结算(计分对局, `_settle_season` 真跑) ──
	var rec: Dictionary = ReplayRecorder.decode(Marshalls.base64_to_raw(str(res.get("replay_b64", ""))))
	_ok("⑦ 分母 · 裁判的录像解得开", not rec.is_empty())
	if rec.is_empty():
		P2C.now_override_ts = 0
		return
	var loc: Dictionary = await _local_settle(rec)
	print("  [量] 本机: finished=%s settled=%s digest=%s 起点=%.0f 结算后存档=%s" % [str(loc["finished"]), str(loc["settled"]), str(loc["digest"]),
		float(loc["base"]), str(loc["gs_after"])])
	_ok("⑦ 分母 · 本机这一局真打到了结算(resume 模式, _settle_season 跑了)", bool(loc["finished"]) and bool(loc["settled"]))
	_ok("⑦ 分母 · 本机与裁判是同一局(终局指纹相同), 起点同为 %.0f" % BASE_REAL,
		str(loc["digest"]) == str(res["digest"]) and _approx(float(loc["base"]), BASE_REAL), "%s / %s" % [str(loc["digest"]), str(res["digest"])])
	var gs_after: Array = loc["gs_after"]
	var st_sum := _sum("left", "_st_dealt")
	var dd_alive := _sum("left", "dd_alive")
	var dd_all := _sum("left", "dmg_dealt")
	print("  [量] 本机左方宝箱龟: 修前口径(存活时 dmg_dealt 之和) %.0f · 全部 dmg_dealt %.0f(阵亡后风暴余跳 %.0f) · 伤害统计 %.0f(持续伤害 %.0f)"
		% [dd_alive, dd_all, dd_all - dd_alive, st_sum, st_sum - dd_all])
	_ok("★★★⑦ 本机计分对局: 存档财宝值增量 == 宝箱龟整局全部伤害(伤害统计, %.0f)" % st_sum,
		_approx(float(gs_after[0]) - BASE_REAL, st_sum) and st_sum > 0.0, "增量 %.0f" % (float(gs_after[0]) - BASE_REAL))
	_ok("★★⑦ 本机计分对局 == 裁判取数口(财宝值与已开列表逐项相同 —— 服务器回写存档就该写这两个数)",
		_approx(float(gs_after[0]), float(fl_ref.get("chest_treasure_value", -1.0))) and gs_after[1] == fl_ref.get("chest_treasures_won", []),
		"本机 %s / 裁判 %s" % [str(gs_after), str(fl_ref)])
	_ok("⑦ 分母 · 本机这一局我方真的开过箱(已开列表非空)", (gs_after[1] as Array).size() >= 1)
	_ok("★⑦ 修前口径只会更少, 差额全是 F/G(持续伤害 + 阵亡后余跳)", dd_alive <= float(gs_after[0]) - BASE_REAL + 0.01)
	P2C.now_override_ts = 0


## 拿录像走「中途退出补打」那条复算路(同 verify_referee_coins): GameState 摆成录像开局那一刻(A 方), 周六口径,
## 战斗场 resume 模式真打到 `_settle_season`。返回结算之后(还原之前)存档里的宝箱两字段。
func _local_settle(rec: Dictionary) -> Dictionary:
	var backup: Dictionary = ReplayRecorder.capture_all()
	ReplayRecorder.apply_state(rec.get("state", {}))
	_gs.week_anchor_ts = P2C.week_anchor_utc(int(P2C.now_utc()))
	_gs.week_phase = P2C.PHASE_GAUNTLET
	_gs.promoted = true
	_gs.gauntlet_wins = 0
	_gs.gauntlet_losses = 0
	_gs.ensure_season()
	var base := float(_gs.chest_treasure_value)
	AbandonedMatch.pending_resume = {"rec": rec.duplicate(true), "loss": false, "text": ""}
	_rec = {"inst": []}
	var s = (load(BATTLE) as PackedScene).instantiate()
	s.sim_stepped.connect(_sample.bind(s))
	add_child(s)
	var sub = s.get("_sub")
	if is_instance_valid(sub) and sub is SubViewport:
		(sub as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	var f := 0
	while f < 20000 and not bool(s._replay.finished):
		await get_tree().process_frame
		f += 1
	await get_tree().process_frame
	var out := {"finished": bool(s._replay.finished), "settled": str(s._replay.mode) == "resume" and bool(s.get("_had_season")),
		"digest": str((s._replay.rec.get("end", {}) as Dictionary).get("h", "")), "base": base,
		"gs_after": [float(_gs.chest_treasure_value), (_gs.chest_treasures_won as Array).duplicate()]}
	s.queue_free()
	for _i in range(3):
		await get_tree().process_frame
	AbandonedMatch.pending_resume = {}
	for n in backup:
		var v = backup[n]
		_gs.set(str(n), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	return out


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 宝箱龟本场宝箱账" if _fail == 0 and _n >= 40 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
