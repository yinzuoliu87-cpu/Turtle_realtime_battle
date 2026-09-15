extends Node
## verify_axe_finals.gd — 四个最终造物 (2026-09-01·方案书六期)
##
## ★需求原文(用户 2026-08-31)逐字，每条断言都能指回引用 —— 见 AxeFinalStats 头注。
##
## ★★这份门禁里最容易写假的六条：
##   ① 「无限叠加」：只验"叠了 3 层"看不出有没有上限。要叠到 200 层再量一次。
##   ② 「处决线」：只验"低于线被处决"会漏掉边界。**恰好在线上要处决、线上一点点不处决**，
##      两侧各量一次 —— 边界写错一格是这类功能最常见的 bug。
##   ③ 「独立的4秒，不打扰当前buff」：只验"再放一次还在"会被"刷新"蒙混。
##      要**先让第一层过期**，看第二层还在不在。
##   ④ 「魔法伤害」：伤害类型是接线不是颜色。给靶子堆魔抗，量它**真的被削**。
##   ⑤ 「600码内」：只验范围内吃到，不验范围外**没吃到** ⇒ 全场加血也算过。
##   ⑦ 「免疫控制」: 断言**引擎真的会读的那个字段**(`cc_immune_until` 时间戳),
##      不是我自己顺手插的 `cc_immune` 布尔 —— 后者全引擎零读者, 断言它必绿而免控是假的。
##      (2026-09-01 删掉了那个假字段; memory: 门禁要量需求不是量我的钩子)
##   ⑥ 「不再获得减伤」(炽天使)：这是需求**明确取消**的东西，要验它确实是 0，
##      不能当成"漏掉了没写"。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AF := preload("res://scripts/gamedata/axe_final_stats.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const AV := preload("res://scripts/scenes/battle/axe_final_vfx.gd")
const ASV := preload("res://scripts/scenes/battle/axe_seraph_vfx.gd")
## 推回旋镖用的模拟步长(= 60 帧/秒一步)。★门禁推战斗步, 不等任何 tween(CLAUDE.md §3.5)。
const DT := 1.0 / 60.0

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _mk_axe(final_key: String, atk: float = 100.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var ax: Dictionary = _s._spawn._make_unit("basic", "left", c)
	_s._units.append(ax)
	ax["_eq_axe"] = true
	ax["_axe_pv"] = 4
	ax["_axe_final"] = final_key
	ax["id"] = "__axe_probe__"
	ax["crit"] = 0.0
	ax["atk"] = atk
	ax["maxHp"] = 10000.0
	ax["hp"] = 5000.0
	ax["maxEnergy"] = 1000.0
	ax["energy"] = 0.0
	ax["atk_range"] = 200.0
	return ax


func _mk_foe(off: Vector2, hp: float = 100000.0, mr: float = 0.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", "right", c + off)
	_s._units.append(u)
	u["id"] = "__foe_probe__"
	u["maxHp"] = hp
	u["hp"] = hp
	u["def"] = 0.0
	u["mr"] = mr
	u["flat_dr"] = 0.0
	u["damage_reduction"] = 0.0
	u["shield"] = 0.0
	return u


func _mk_ally(off: Vector2) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var a: Dictionary = _s._spawn._make_unit("basic", "left", c + off)
	_s._units.append(a)
	a["id"] = "__ally_probe__"
	a["maxHp"] = 5000.0
	a["hp"] = 1000.0
	a["maxEnergy"] = 1000.0
	a["energy"] = 0.0
	a["shield"] = 0.0
	return a


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 四个最终造物 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	_t_table()
	_t_undead()
	_t_seraph()
	_t_holo()
	_t_ember()
	_t_vfx_curves()
	_t_real_path()

	if _n < 58:
		print("  [FAIL] ★分母: 断言只有 %d 条(<58) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 四个最终造物(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  ① 分母: 数值表与 FINALS 一一对应
# ══════════════════════════════════════════════════════════════
func _t_table() -> void:
	print("--- ① 分母: 数值表 ---")
	var miss: Array = []
	for f in AE.FINALS:
		if not AF.STATS.has(str((f as Dictionary)["key"])):
			miss.append(str((f as Dictionary)["key"]))
	_ok("★四个造物**每一个**都在数值表里(少一个 = 那个造物没数值, 选了等于白选)",
		miss.is_empty() and AE.FINALS.size() == 4, str(miss))
	_ok("★分母: 亡灵 %.0f血/%.0f攻/%.0f甲/%.0f抗 · 环 %.0f码 · 重生 %.1f秒带 %.0f%%"
		% [AF.stat("undead", "hp"), AF.stat("undead", "atk"), AF.stat("undead", "def"),
		   AF.stat("undead", "mr"), AF.UNDEAD_RING_R, AF.UNDEAD_REVIVE_DELAY,
		   AF.UNDEAD_REVIVE_HP_PCT * 100.0],
		is_equal_approx(AF.stat("undead", "hp"), 1200.0)
		and is_equal_approx(AF.UNDEAD_RING_R, 300.0)
		and is_equal_approx(AF.UNDEAD_REVIVE_DELAY, 2.5)
		and is_equal_approx(AF.UNDEAD_REVIVE_HP_PCT, 0.40))
	_ok("★分母: 炽天使 %.0f射程 · %d层灼烧 · %d把回旋镖 · 半宽%.0f"
		% [AF.stat("seraph", "range"), AF.SERAPH_BURN_ON_HIT, AF.SERAPH_BOOMERANGS,
		   AF.SERAPH_BOOM_R],
		is_equal_approx(AF.stat("seraph", "range"), 300.0) and AF.SERAPH_BURN_ON_HIT == 8
		and AF.SERAPH_BOOMERANGS == 10 and is_equal_approx(AF.SERAPH_BOOM_R, 300.0))
	_ok("★★炽天使「**不再获得减伤**」是需求明确取消的 ⇒ 常量必须是 0(不是漏写)",
		is_equal_approx(AF.SERAPH_CHARGE_DR, 0.0))
	_ok("★分母: 全息 %.0f盾/%.0f龟能 · 阵%.0f码 每%.1f秒 回%.0f血 给%.0f龟能 +%.0f%%攻速 · 减伤%.0f%%"
		% [AF.HOLO_ONHIT_SHIELD, AF.HOLO_ONHIT_ENERGY, AF.HOLO_AURA_R, AF.HOLO_AURA_TICK,
		   AF.HOLO_AURA_HEAL, AF.HOLO_AURA_ENERGY, AF.HOLO_AURA_ASPD * 100.0, AF.HOLO_PLANT_DR * 100.0],
		is_equal_approx(AF.HOLO_ONHIT_SHIELD, 60.0) and is_equal_approx(AF.HOLO_AURA_R, 600.0)
		and is_equal_approx(AF.HOLO_AURA_TICK, 0.5) and is_equal_approx(AF.HOLO_AURA_HEAL, 100.0)
		and is_equal_approx(AF.HOLO_AURA_ASPD, 0.30) and is_equal_approx(AF.HOLO_PLANT_DR, 0.30))
	_ok("★分母: 余烬 %.0f攻/+%.0f%%攻速/+%.0f%%移速 · 每层%.1f%%处决线 · 处决+%.0f龟能 · 光%.0f秒"
		% [AF.stat("ember", "atk"), AF.stat("ember", "aspd_pct") * 100.0,
		   AF.stat("ember", "move_pct") * 100.0, AF.EMBER_SEED_EXEC_PCT * 100.0,
		   AF.EMBER_EXEC_ENERGY, AF.EMBER_LIGHT_TIME],
		is_equal_approx(AF.stat("ember", "atk"), 80.0)
		and is_equal_approx(AF.stat("ember", "aspd_pct"), 0.80)
		and is_equal_approx(AF.EMBER_SEED_EXEC_PCT, 0.005)
		and is_equal_approx(AF.EMBER_EXEC_ENERGY, 150.0))


# ══════════════════════════════════════════════════════════════
#  ② 亡灵之斧
# ══════════════════════════════════════════════════════════════
func _t_undead() -> void:
	print("--- ② 亡灵之斧 ---")
	var fin = _s._equip_sys._axe._fin
	var ax: Dictionary = _mk_axe("undead")
	## 属性折进去了没有
	var raw_hp: float = float(ax["maxHp"])
	var probe: Dictionary = _mk_axe("")
	probe["maxHp"] = 10000.0
	fin.apply_stats(probe, "undead")
	_ok("★登场折进 +%.0f 最大生命(%.0f → %.0f)" % [AF.stat("undead", "hp"), 10000.0, probe["maxHp"]],
		is_equal_approx(float(probe["maxHp"]), 10000.0 + AF.stat("undead", "hp")))

	## 环内/环外
	var inside: Dictionary = _mk_foe(Vector2(100, 0), 200000.0)
	var outside: Dictionary = _mk_foe(Vector2(AF.UNDEAD_RING_R + 200.0, 0), 200000.0)
	var hp_in0: float = float(inside["hp"])
	var hp_out0: float = float(outside["hp"])
	ax["hp"] = 5000.0
	var n: int = fin.undead_ring_tick(ax)
	_ok("★分母: 环内数到 %d 个敌人" % n, n == 1, "环 %.0f 码" % AF.UNDEAD_RING_R)
	_ok("★★环内那个真的掉血了(%.0f → %.0f)" % [hp_in0, float(inside["hp"])],
		float(inside["hp"]) < hp_in0)
	_ok("★★★环外那个【一点没掉】(只验环内吃到 = 全场掉血也算过)",
		is_equal_approx(float(outside["hp"]), hp_out0),
		"%.0f → %.0f" % [hp_out0, float(outside["hp"])])
	_ok("★★吸血 = %.1f%% 最大生命 × 环内人数(5000 → %.0f)"
		% [AF.UNDEAD_LEECH_PCT * 100.0, float(ax["hp"])],
		float(ax["hp"]) > 5000.0)

	## ★★魔法伤害要吃魔抗 —— 伤害类型是接线不是颜色
	var soft: Dictionary = _mk_foe(Vector2(60, 0), 100000.0, 0.0)
	var hard: Dictionary = _mk_foe(Vector2(-60, 0), 100000.0, 200.0)
	var s0: float = float(soft["hp"])
	var h0: float = float(hard["hp"])
	fin.undead_ring_tick(ax)
	var d_soft: float = s0 - float(soft["hp"])
	var d_hard: float = h0 - float(hard["hp"])
	_ok("★★★环是【魔法伤害】: 200 魔抗那个掉得更少(%.0f vs %.0f)" % [d_hard, d_soft],
		d_hard < d_soft - 0.5 and d_soft > 1.0, "分母: 无抗的掉了 %.0f(必须 >1)" % d_soft)

	## 重生
	var ux: Dictionary = _mk_axe("undead")
	ux["maxHp"] = 10000.0
	ux["alive"] = false
	ux["hp"] = 0.0
	_ok("★死后安排了重生", fin.undead_on_death(ux))
	_ok("★分母: 还没到 %.1f 秒时不站起来" % AF.UNDEAD_REVIVE_DELAY, not fin.undead_tick_revive(ux))
	ux["_axe_revive_at"] = _s._t - 0.01
	_ok("★★到点站起来了", fin.undead_tick_revive(ux) and ux.get("alive", false))
	_ok("★★带 %.0f%% 最大生命回来(实测 %.0f / %.0f)"
		% [AF.UNDEAD_REVIVE_HP_PCT * 100.0, float(ux["hp"]), float(ux["maxHp"])],
		is_equal_approx(float(ux["hp"]), 10000.0 * AF.UNDEAD_REVIVE_HP_PCT))
	ux["alive"] = false
	_ok("★★一场只重生一次(第二次不再安排)", not fin.undead_on_death(ux))
	## ★不做死亡动画(用户两次点名) —— 焊在这里, 六期不许破坏
	var rb_src: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var i_d: int = rb_src.find("const ACTION_DEATH := {")
	var body_d: String = rb_src.substr(i_d, rb_src.find("}", i_d) - i_d) if i_d >= 0 else ""
	_ok("★★★重生**不靠死亡动画**: ACTION_DEATH 里仍然没有 axe(用户两次点名不要)",
		body_d != "" and not body_d.contains("axe"), "分母: 表解析到 %d 字" % body_d.length())


# ══════════════════════════════════════════════════════════════
#  ③ 炽天使
# ══════════════════════════════════════════════════════════════
func _t_seraph() -> void:
	print("--- ③ 炽天使 ---")
	var fin = _s._equip_sys._axe._fin
	var ax: Dictionary = _mk_axe("seraph")
	var probe: Dictionary = _mk_axe("")
	probe["atk_range"] = 120.0
	probe["melee"] = true
	fin.apply_stats(probe, "seraph")
	_ok("★★射程**设成** %.0f 而不是加 %.0f(近战 120 加 300 会变成 420)"
		% [AF.stat("seraph", "range"), AF.stat("seraph", "range")],
		is_equal_approx(float(probe["atk_range"]), AF.stat("seraph", "range"))
		and not bool(probe.get("melee", true)))

	var foe: Dictionary = _mk_foe(Vector2(120, 0))
	fin.seraph_on_hit(ax, foe)
	var burn: int = int((foe.get("dot_stacks", {}) as Dictionary).get("burn", 0))
	_ok("★★普攻附带 %d 层灼烧(实测 %d)" % [AF.SERAPH_BURN_ON_HIT, burn],
		burn >= AF.SERAPH_BURN_ON_HIT)

	## ── 回旋镖(2026-09-15 重做: 飞出去 → 折返 → 飞回斧头, 经过时结算) ──
	## 用户:「7/9的回旋镖同样是在敷衍我啊，回旋镖是什么？以及特效和实际伤害范围完全不一样啊，也没有命中特效」
	## ★旧断言直接调 `seraph_boomerang_settle`(出手当帧全部结算) —— 那个函数已经没了。
	##   新断言一律【推模拟步】(直接调 tick_boomerangs, 真链另在 ⑦ 节走 EquipSystem.tick_global), 不等 tween,
	##   量产品自己的账: 敌人真实血量 / 灼烧层 / 在途记录的中心 / 世界里真的镖身与火花节点。
	## ★每个用例在【干净的单位表】里跑: 场景刷出来的队伍与前面各节的探针会改变「身前最远那个」,
	##   飞出距离就量不准(memory: 拿随机单位测精确数值 ⇒ CI 偶发红)。结束时原样放回。
	var bak: Array = _s._units.duplicate()
	fin._booms.clear()
	_t_boom_pass(fin)
	_t_boom_filters(fin)
	_t_boom_return(fin)
	_t_boom_leave(fin)
	_s._units.clear()
	_s._units.append_array(bak)
	fin._booms.clear()


## 一个敌人正前方 700 码: 出手当帧不掉血 / 镖到了才掉 / 飞出去再回来 / 每把只吃一次 / 节点外径与位置 / 飞回收节点。
func _t_boom_pass(fin) -> void:
	_s._units.clear()
	var ax: Dictionary = _mk_axe("seraph")
	var org: Vector2 = ax["pos"]
	var foe: Dictionary = _mk_foe(Vector2(700, 0))
	var h0: float = float(foe["hp"])
	var rec: Dictionary = fin.seraph_boomerang_launch(ax, Vector2.RIGHT)
	_ok("★分母: 出手登记了一把在途回旋镖(在途 %d 把)" % fin._booms.size(),
		not rec.is_empty() and fin._booms.size() == 1)
	_ok("★★★出手当帧敌人【一点没掉】(原来出手当帧就全部结算 = 伤害与演出脱节)",
		absf(float(foe["hp"]) - h0) < 0.5, "%.0f → %.0f" % [h0, float(foe["hp"])])
	_ok("★飞出距离取最小值 %.0f 码(身前最远的敌人才 700 码)" % AF.SERAPH_BOOM_MIN_OUT,
		is_equal_approx(float(rec.get("out", -1.0)), AF.SERAPH_BOOM_MIN_OUT), "out=%.1f" % float(rec.get("out", -1.0)))
	var node = rec.get("node", null)
	_ok("★分母: 镖身节点真的建进了世界(Sprite3D)",
		node is Sprite3D and is_instance_valid(node) and (node as Node).is_inside_tree())
	if node is Sprite3D:
		var sp := node as Sprite3D
		var fw: float = (float(sp.texture.get_width()) / float(maxi(1, sp.hframes))) if sp.texture != null else 0.0
		var diam: float = sp.pixel_size * fw / float(_s.WS)
		_ok("★★★镖身外径 = 2 × 判定半宽 = %.0f 码(pixel_size × 帧宽 ÷ WS 实测 %.1f 码)" % [2.0 * AF.SERAPH_BOOM_R, diam],
			fw > 0.0 and absf(diam - 2.0 * AF.SERAPH_BOOM_R) < 0.5, "帧宽 %.0f 像素 × %d 帧" % [fw, sp.hframes])
		_ok("★镖身贴地(板面法线朝上 · 不是公告板)",
			sp.billboard == BaseMaterial3D.BILLBOARD_DISABLED and absf(sp.basis.z.normalized().dot(Vector3.UP)) > 0.99)
		_ok("★镖身 NEAREST(像素贴图不许被线性插值糊掉)", sp.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	var art: Array = _boom_art_radius()
	_ok("★★画出来的外径也对得上: %d 帧里不透明像素离帧心最远 = 半格的 %.0f%%~%.0f%%(要 90%%~100%%)"
		% [int(art[2]), float(art[0]) * 100.0, float(art[1]) * 100.0],
		int(art[2]) == ASV.BOOM_FRAMES and float(art[0]) >= 0.90 and float(art[1]) <= 1.0)
	## 推模拟步: 记每一步的中心离出手点多远、哪一步掉的血、节点有没有跟着中心走
	var dists: Array = []
	var hit_d := -1.0
	var hp_after_hit := -1.0
	var node_ok := true
	var node_checked := 0
	var steps := 0
	while steps < 600 and not fin._booms.is_empty():
		var hp_prev: float = float(foe["hp"])
		fin.tick_boomerangs(DT)
		steps += 1
		var p: Vector2 = rec["pos"]
		dists.append(p.distance_to(org))
		if hit_d < 0.0 and float(foe["hp"]) < hp_prev:
			hit_d = p.distance_to(org)
			hp_after_hit = float(foe["hp"])
		if not bool(rec["done"]) and is_instance_valid(node):
			node_checked += 1
			if (node as Node3D).position.distance_to(_s._world_pos(p, ASV.BOOM_Y)) > 0.001:
				node_ok = false
	var step_px: float = AF.SERAPH_BOOM_SPEED * DT
	var want_hit: float = 700.0 - AF.SERAPH_BOOM_R
	_ok("★★★镖飞到了才掉血: 掉血那一步镖中心离出手点 %.1f 码(敌人 700 − 半宽 %.0f = %.0f, 容差一步 %.1f)"
		% [hit_d, AF.SERAPH_BOOM_R, want_hit, step_px],
		hit_d >= want_hit - 0.01 and hit_d <= want_hit + step_px + 0.01)
	var imax := 0
	for i in range(dists.size()):
		if float(dists[i]) > float(dists[imax]):
			imax = i
	var up_ok := true
	for i in range(1, imax + 1):
		if float(dists[i]) < float(dists[i - 1]) - 0.001:
			up_ok = false
	var down_ok := true
	for i in range(imax + 1, dists.size()):
		if float(dists[i]) > float(dists[i - 1]) + 0.001:
			down_ok = false
	var dmax: float = float(dists[imax]) if not dists.is_empty() else -1.0
	var out: float = float(rec.get("out", -1.0))
	_ok("★★★飞出去再回来: 中心先一路远离(%d 步) → 最远 %.1f 码(飞出距离 %.0f, 差不到一步) → 一路回来(%d 步)"
		% [imax, dmax, out, dists.size() - 1 - imax],
		up_ok and down_ok and imax >= 10 and dists.size() - 1 - imax >= 10
		and dmax <= out + 0.01 and dmax >= out - step_px - 0.01)
	var end_gap: float = (rec["pos"] as Vector2).distance_to(ax["pos"])
	_ok("★★回到了斧头身上(终点离斧头 %.3f 码)且在途表清空" % end_gap,
		end_gap < 0.01 and bool(rec["done"]) and fin._booms.is_empty())
	_ok("★分母: 一去一回 %d 步 = %.2f 秒(%.0f 码 × 2 ÷ %.0f 码/秒 = %.2f 秒)"
		% [steps, steps * DT, out, AF.SERAPH_BOOM_SPEED, 2.0 * out / AF.SERAPH_BOOM_SPEED],
		absf(steps * DT - 2.0 * out / AF.SERAPH_BOOM_SPEED) < 2.0 * DT)
	_ok("★★镖身节点每一步都搬到了当前中心(量了 %d 步)" % node_checked, node_ok and node_checked >= 40)
	_ok("★★飞回后镖身节点收掉了(queue_free)",
		node is Object and (not is_instance_valid(node) or (node as Node).is_queued_for_deletion()))
	_ok("★★★每把每个敌人只吃一次: 去程命中后回程再经过它, 血量不再动(%.0f → 命中后 %.0f → 飞完 %.0f)"
		% [h0, hp_after_hit, float(foe["hp"])],
		hp_after_hit > 0.0 and hp_after_hit < h0 - 0.5 and absf(float(foe["hp"]) - hp_after_hit) < 0.5)
	var burn: int = int((foe.get("dot_stacks", {}) as Dictionary).get("burn", 0))
	_ok("★★命中加 %d 层灼烧, 且只加一份(实测 %d)" % [AF.SERAPH_BOOM_BURN, burn], burn == AF.SERAPH_BOOM_BURN)


## 1300 码外 / 横向超出半宽 / 身后(但在镖的圆里) / 魔抗 / 命中火花。
func _t_boom_filters(fin) -> void:
	_s._units.clear()
	var ax: Dictionary = _mk_axe("seraph")
	var org: Vector2 = ax["pos"]
	var far: Dictionary = _mk_foe(Vector2(1300, 0))
	var side: Dictionary = _mk_foe(Vector2(500, AF.SERAPH_BOOM_R + 60.0))
	var behind: Dictionary = _mk_foe(Vector2(-200, 0))
	var mr_foe: Dictionary = _mk_foe(Vector2(600, 40), 100000.0, 200.0)
	mr_foe["base_mr"] = 200.0
	var raw_foe: Dictionary = _mk_foe(Vector2(600, -40), 100000.0, 0.0)
	raw_foe["base_mr"] = 0.0
	var f0: float = float(far["hp"])
	var s0: float = float(side["hp"])
	var b0: float = float(behind["hp"])
	var m0: float = float(mr_foe["hp"])
	var r0: float = float(raw_foe["hp"])
	## ★出手前世界里已有的火花(上一个用例的最后一个火花 queue_free 了, 但同步代码里要到帧末才真正离树)
	##   先记下来排除 —— 第一版没排除, 数出「命中 3 · 火花 4」, 多的那个就是上一把留下的。
	var old_sparks: Dictionary = {}
	for ch0 in _s._world.get_children():
		if ch0 is Sprite3D and (ch0 as Sprite3D).texture != null \
				and (ch0 as Sprite3D).texture.resource_path == ASV.TEX_HIT:
			old_sparks[(ch0 as Object).get_instance_id()] = true
	var rec: Dictionary = fin.seraph_boomerang_launch(ax, Vector2.RIGHT)
	_ok("★★飞出距离 = 身前判定带里最远那个的纵深(实测 %.0f, 应 1300)" % float(rec.get("out", -1.0)),
		is_equal_approx(float(rec.get("out", -1.0)), 1300.0))
	var sparks: Dictionary = {}                  # 火花节点实例 id(整数) → 节点(不含出手前就在的)
	var hits := 0
	var reach := 0.0
	var steps := 0
	while steps < 900 and not fin._booms.is_empty():
		hits += int(fin.tick_boomerangs(DT))
		steps += 1
		reach = maxf(reach, (rec["pos"] as Vector2).distance_to(org))
		for ch in _s._world.get_children():
			if ch is Sprite3D and (ch as Sprite3D).texture != null \
					and (ch as Sprite3D).texture.resource_path == ASV.TEX_HIT \
					and not old_sparks.has((ch as Object).get_instance_id()):
				sparks[(ch as Object).get_instance_id()] = ch
	_ok("★★★1300 码外的敌人也打到了(镖真的飞过去: 中心最远 %.0f 码)" % reach,
		float(far["hp"]) < f0 and reach >= 1300.0 - AF.SERAPH_BOOM_SPEED * DT - 0.01,
		"%.0f → %.0f" % [f0, float(far["hp"])])
	_ok("★★★横向超出半宽的那个【一点没掉】(离中线 %.0f 码 > 半宽 %.0f)" % [AF.SERAPH_BOOM_R + 60.0, AF.SERAPH_BOOM_R],
		absf(float(side["hp"]) - s0) < 0.5, "%.0f → %.0f" % [s0, float(side["hp"])])
	_ok("★★★身后那个【一点没掉】—— 它离出手点只有 %.0f 码, 在镖的圆里(< 半宽 %.0f), 不判身前就会被打"
		% [(behind["pos"] as Vector2).distance_to(org), AF.SERAPH_BOOM_R],
		absf(float(behind["hp"]) - b0) < 0.5, "%.0f → %.0f" % [b0, float(behind["hp"])])
	## ★★★「1ATK**魔法**伤害」必须吃魔抗(memory: 伤害类型是接线不是颜色)。
	##   亡灵环踩过这坑并修了, 回旋镖漏过一次 —— 当时没有任何一条断言问"削了多少"。
	var d_mr: float = m0 - float(mr_foe["hp"])
	var d_raw: float = r0 - float(raw_foe["hp"])
	_ok("★★★回旋镖是【魔法伤害】: 200 魔抗那个掉得更少(%.0f vs %.0f)" % [d_mr, d_raw],
		d_raw > 0.0 and d_mr < d_raw, "分母: 零魔抗那个掉了 %.0f(为 0 就是压根没打到)" % d_raw)
	var fb: int = int((far.get("dot_stacks", {}) as Dictionary).get("burn", 0))
	_ok("★远处命中也加 %d 层灼烧(实测 %d)" % [AF.SERAPH_BOOM_BURN, fb], fb == AF.SERAPH_BOOM_BURN)
	_ok("★分母: 这一把命中 %d 人次(远 / 魔抗 / 零魔抗 = 3)" % hits,
		hits == 3 and (rec["hits"] as Array).size() == 3)
	_ok("★★★每次命中真的建出了火花节点(命中 %d 人次 · 世界里新出现的火花 %d 个)" % [hits, sparks.size()],
		hits >= 1 and sparks.size() == hits)
	var sp_done := true
	for k in sparks:
		var nd = sparks[k]
		if is_instance_valid(nd) and not (nd as Node).is_queued_for_deletion():
			sp_done = false
	_ok("★火花是一次性的: 飞完时 %d 个全部收掉" % sparks.size(), sp_done and sparks.size() >= 1)
	## ★分母: 换成别的造物, 同一个出手什么都不该登记
	var other: Dictionary = _mk_axe("holo")
	var nb: int = fin._booms.size()
	_ok("★★分母: 换成全息斧, seraph_boomerang_launch 什么都不登记",
		(fin.seraph_boomerang_launch(other, Vector2.RIGHT) as Dictionary).is_empty() and fin._booms.size() == nb)


## 回程终点: 斧头活着 = 它【当前】的位置(它在走); 斧头死了不作废, 飞回出手点。
func _t_boom_return(fin) -> void:
	for dead in [false, true]:
		_s._units.clear()
		var ax: Dictionary = _mk_axe("seraph")
		var org: Vector2 = ax["pos"]
		_mk_foe(Vector2(400, 0))
		var rec: Dictionary = fin.seraph_boomerang_launch(ax, Vector2.RIGHT)
		var steps := 0
		while steps < 600 and not bool(rec.get("back", false)):
			fin.tick_boomerangs(DT)
			steps += 1
		var turned: bool = bool(rec.get("back", false))
		var moved: Vector2 = org + Vector2(0, 250)
		ax["pos"] = moved
		if dead:
			ax["alive"] = false
		while steps < 1200 and not fin._booms.is_empty():
			fin.tick_boomerangs(DT)
			steps += 1
		var want: Vector2 = org if dead else moved
		var gap: float = (rec["pos"] as Vector2).distance_to(want)
		if dead:
			_ok("★★斧头死了不作废, 回程飞回【出手点】(终点离出手点 %.3f 码; 斧头尸体在 250 码外)" % gap,
				turned and gap < 0.01 and fin._booms.is_empty())
		else:
			_ok("★★回程飞回斧头【当前】位置(折返后斧头挪了 250 码; 终点离它 %.3f 码)" % gap,
				turned and gap < 0.01 and fin._booms.is_empty())


## 源单位离场(换路 / 战斗结束) ⇒ 在途作废、节点收掉、不再打人。
func _t_boom_leave(fin) -> void:
	_s._units.clear()
	var ax: Dictionary = _mk_axe("seraph")
	var foe: Dictionary = _mk_foe(Vector2(900, 0))
	var rec: Dictionary = fin.seraph_boomerang_launch(ax, Vector2.RIGHT)
	var node = rec.get("node", null)
	for _i in range(5):
		fin.tick_boomerangs(DT)
	var h0: float = float(foe["hp"])
	_ok("★分母: 离场前镖还在途、节点还在、敌人还没挨打(它在 900 码, 镖中心要到 600 码才碰得到)",
		fin._booms.size() == 1 and node is Sprite3D and is_instance_valid(node)
		and not (node as Node).is_queued_for_deletion() and absf(h0 - 100000.0) < 0.5)
	_s._arr_erase_unit(_s._units, ax)
	for _i in range(120):
		fin.tick_boomerangs(DT)
	_ok("★★★斧头离场 ⇒ 在途表清空", fin._booms.is_empty(), "在途 %d 把" % fin._booms.size())
	_ok("★★★斧头离场 ⇒ 镖身节点收掉",
		not is_instance_valid(node) or (node as Node).is_queued_for_deletion())
	_ok("★★斧头离场后镖不再打人(900 码的敌人 %.0f → %.0f; 不作废的话 120 步 = 2 秒早就飞到了)"
		% [h0, float(foe["hp"])], absf(float(foe["hp"]) - h0) < 0.5)


## 回旋镖素材每一帧【不透明像素离帧心最远】占半格的比例 —— 量的是**画出来的**外径, 不是节点配置。
## 返回 [8 帧里最小的比例, 最大的比例, 量到的帧数]。
func _boom_art_radius() -> Array:
	## ★读 png 原始字节再解码, 不用 `Image.load_from_file` —— 后者对 res:// 里已导入的图会报
	##   「Loaded resource as image file」警告(第一版就是这样, 日志里多一段回溯)。
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ASV.TEX_BOOM)
	var img := Image.new()
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK or img.is_empty():
		return [0.0, 0.0, 0]
	var nf: int = ASV.BOOM_FRAMES
	var cw: int = img.get_width() / nf
	var ch: int = img.get_height()
	var mn := 9.0
	var mx := 0.0
	var cnt := 0
	for f in range(nf):
		var best := 0.0
		for y in range(ch):
			for x in range(cw):
				if img.get_pixel(f * cw + x, y).a > 0.5:
					best = maxf(best, Vector2(float(x) + 0.5 - cw * 0.5, float(y) + 0.5 - ch * 0.5).length())
		mn = minf(mn, best / (cw * 0.5))
		mx = maxf(mx, best / (cw * 0.5))
		cnt += 1
	return [mn, mx, cnt]


# ══════════════════════════════════════════════════════════════
#  ④ 全息斧
# ══════════════════════════════════════════════════════════════
func _t_holo() -> void:
	print("--- ④ 全息斧 ---")
	var fin = _s._equip_sys._axe._fin
	var ax: Dictionary = _mk_axe("holo")
	var probe: Dictionary = _mk_axe("")
	fin.apply_stats(probe, "holo")
	_ok("★登场折进 +%.0f 最大生命 · %.0f%% 龟能充能速率登记在表里"
		% [AF.stat("holo", "hp"), AF.stat("holo", "energy_rate_pct") * 100.0],
		is_equal_approx(AF.stat("holo", "energy_rate_pct"), 0.50))

	## 普攻: 给【血量最低的】友军
	var low: Dictionary = _mk_ally(Vector2(80, 0))
	low["hp"] = 100.0
	var high: Dictionary = _mk_ally(Vector2(-80, 0))
	high["hp"] = 4900.0
	## ★量"冷却有没有被推进"要在调用【前】记基线
	var cd_before: float = _min_cd(low)
	var got = fin.holo_on_hit(ax)
	var cd_after: float = _min_cd(low)
	_ok("★★挑中的是【血量最低】那个(不是最近的/第一个)", is_same(got, low),
		"低血 %.0f/%.0f vs 高血 %.0f/%.0f" % [low["hp"], low["maxHp"], high["hp"], high["maxHp"]])
	_ok("★给了 %.0f 护盾 + %.0f 龟能(实测 盾%.0f 能%.0f)"
		% [AF.HOLO_ONHIT_SHIELD, AF.HOLO_ONHIT_ENERGY, float(low.get("shield", 0.0)),
		   float(low.get("energy", 0.0))],
		float(low.get("shield", 0.0)) >= AF.HOLO_ONHIT_SHIELD)
	## ★★★龟能必须进**引擎真的会读**的那条路。
	##   原来写的是 `low["energy"] += 5` —— 实时版**没有龟的 `energy` 字段**
	##   (龟能 = 技能冷却充能, 入口是 `EquipSystem._eq_grant_energy` → 龟能银行)。
	##   `_make_unit` 确实建了这个键, 所以断言 `energy == 5` **恒绿而功能是死的** ——
	##   这正是"量我自己插的标记"那一类假判据。2026-09-01 改成量冷却真的被推进。
	_ok("★★★友军的 %.0f 龟能进了【冷却充能】而不是那个没人读的 energy 字段"
		% AF.HOLO_ONHIT_ENERGY,
		cd_after < cd_before - 0.001 or float(low.get("energy_bank", 0.0)) > 0.0,
		"分母: 最快就绪的技冷却 %.3f → %.3f · 银行 %.2f"
		% [cd_before, cd_after, float(low.get("energy_bank", 0.0))])

	## 法阵: 范围内吃到、范围外没吃到
	var near: Dictionary = _mk_ally(Vector2(200, 0))
	near["hp"] = 1000.0
	var far: Dictionary = _mk_ally(Vector2(AF.HOLO_AURA_R + 300.0, 0))
	far["hp"] = 1000.0
	far["energy"] = 0.0
	var n: int = fin.holo_aura_tick(ax)
	_ok("★分母: 法阵这一跳照顾到 %d 个友军" % n, n >= 1)
	_ok("★★范围内那个回了 %.0f 血(1000 → %.0f)" % [AF.HOLO_AURA_HEAL, float(near["hp"])],
		float(near["hp"]) > 1000.0)
	_ok("★★★范围外(%.0f 码)那个【一点没回、也没拿到龟能】—— 只验范围内吃到 = 全场加血也算过"
		% AF.HOLO_AURA_R,
		is_equal_approx(float(far["hp"]), 1000.0) and is_equal_approx(float(far.get("energy", 0.0)), 0.0),
		"血 %.0f 能 %.0f" % [float(far["hp"]), float(far.get("energy", 0.0))])
	_ok("★★范围内那个拿到 +%.0f%% 攻速" % (AF.HOLO_AURA_ASPD * 100.0),
		is_equal_approx(float(near.get("haste_mult", 1.0)), 1.0 + AF.HOLO_AURA_ASPD)
		and float(near.get("haste_until", 0.0)) > _s._t)


# ══════════════════════════════════════════════════════════════
#  ⑤ 余烬
# ══════════════════════════════════════════════════════════════
func _t_ember() -> void:
	print("--- ⑤ 余烬 ---")
	var fin = _s._equip_sys._axe._fin
	var ax: Dictionary = _mk_axe("ember")

	## ★★「无限叠加」—— 只验叠 3 层看不出有没有上限
	_ok("★处决线 = 层数 × %.1f%%: 10 层 = %.0f%%"
		% [AF.EMBER_SEED_EXEC_PCT * 100.0, AF.ember_exec_pct(10) * 100.0],
		is_equal_approx(AF.ember_exec_pct(10), 0.05))
	_ok("★★★真的**无上限**: 200 层 = %.0f%%(封顶的实现在这里会露馅)"
		% (AF.ember_exec_pct(200) * 100.0),
		is_equal_approx(AF.ember_exec_pct(200), AF.EMBER_SEED_EXEC_PCT * 200.0))

	## ★★处决线的两侧边界
	var mh := 10000.0
	var line: float = mh * AF.ember_exec_pct(10)
	_ok("★★恰好在线上(%.0f)【要】处决 —— 边界含等号" % line,
		AF.ember_should_execute(line, mh, 10))
	_ok("★★★线上一点点(%.0f)【不】处决 —— 边界写错一格就在这里露馅" % (line + 1.0),
		not AF.ember_should_execute(line + 1.0, mh, 10))
	_ok("★分母: 0 层时任何血量都不处决(没打过就不该被斩)",
		not AF.ember_should_execute(1.0, mh, 0))

	## 命中挂种子
	var foe: Dictionary = _mk_foe(Vector2(90, 0), 10000.0)
	var r1: Dictionary = fin.ember_on_hit(ax, foe)
	_ok("★命中挂 1 层种子(实测 %d)" % int(r1["stacks"]), int(r1["stacks"]) == 1)
	_ok("★分母: 满血时不处决", not bool(r1["executed"]))
	## 堆够层数 + 压低血量 → 处决
	foe["_ember_seeds"] = 39
	foe["hp"] = 10000.0 * 0.19          # 40 层 = 20% 线, 19% 在线下
	ax["energy"] = 0.0
	var r2: Dictionary = fin.ember_on_hit(ax, foe)
	_ok("★★40 层(线 %.0f%%)时 19%% 血被处决" % (AF.ember_exec_pct(40) * 100.0),
		bool(r2["executed"]), "层数 %d" % int(r2["stacks"]))
	_ok("★★处决之后召唤物 +%.0f 龟能(实测 %.0f)" % [AF.EMBER_EXEC_ENERGY, float(ax["energy"])],
		is_equal_approx(float(ax["energy"]), AF.EMBER_EXEC_ENERGY))

	## ★★★余烬之光: 独立叠加, 不是刷新
	var bx: Dictionary = _mk_axe("ember")
	_ok("★分母: 起手 0 层光", fin.ember_light_stacks(bx) == 0)
	fin.ember_light_cast(bx)
	_ok("★放一次 = 1 层, 且 buff 真的挂上了(减伤 %.0f%% / 免控)"
		% (AF.EMBER_LIGHT_DR * 100.0),
		fin.ember_light_stacks(bx) == 1
		and is_equal_approx(float(bx.get("damage_reduction", 0.0)), AF.EMBER_LIGHT_DR)
		and float(bx.get("cc_immune_until", 0.0)) > float(_s._t))
	fin.ember_light_cast(bx)
	_ok("★★再放一次 = 2 层(是**叠加**不是刷新)", fin.ember_light_stacks(bx) == 2)
	## ★★★关键: 让第一层过期, 第二层必须还在 —— "刷新"的实现在这里会掉到 0
	var arr: Array = bx["_ember_lights"]
	arr[0] = _s._t - 0.01               # 第一层已过期
	bx["_ember_lights"] = arr
	fin.ember_light_tick(bx)
	_ok("★★★第一层过期后第二层**还在**(刷新式实现在这里会变 0)",
		fin.ember_light_stacks(bx) == 1 and float(bx.get("cc_immune_until", 0.0)) > float(_s._t),
		"实测 %d 层" % fin.ember_light_stacks(bx))
	## ★多层【只延长在线时间, 不叠强度】—— 这条最容易做反
	_ok("★★两层时减伤仍是 %.0f%% 而不是翻倍(需求说的是「独立的4秒」, 不是效果叠乘)"
		% (AF.EMBER_LIGHT_DR * 100.0),
		is_equal_approx(float(bx.get("damage_reduction", 0.0)), AF.EMBER_LIGHT_DR))
	## 全部过期 → buff 干净落地
	arr = bx["_ember_lights"]
	for i in range(arr.size()):
		arr[i] = _s._t - 1.0
	bx["_ember_lights"] = arr
	fin.ember_light_tick(bx)
	_ok("★★全部过期后减伤/免控【还原】(不许留一个永久无敌的怪物)",
		fin.ember_light_stacks(bx) == 0
		and is_equal_approx(float(bx.get("damage_reduction", 0.0)), 0.0)
		and float(bx.get("cc_immune_until", 0.0)) <= float(_s._t))


# ══════════════════════════════════════════════════════════════
#  ⑥ 特效的【曲线形状】—— 这是本仓库对"特效也能被门禁守住"的答案
# ══════════════════════════════════════════════════════════════
## ★演出本身没法断言"好不好看", 但**运动曲线的性质可以被量**:
##   单调性 / 端点 / 值域 / 前后段快慢。照 arcane_eq_vfx 的先例(rise_frac 那一段)。
## ★这些函数是 static 纯函数 —— 不建节点、不等 tween, 门禁直接调。
func _t_vfx_curves() -> void:
	print("--- ⑥ 特效曲线 ---")
	## hold_fade: 前 70% 满亮, 后 30% 才淡 —— 防"淡出病"(一出生就淡 ⇒ 实拍读成土棕/灰)
	_ok("★★hold_fade 前 70%% 是**满亮**(0→1.0 / 0.7→1.0), 不是一出生就淡",
		is_equal_approx(AV.hold_fade(0.0), 1.0) and is_equal_approx(AV.hold_fade(0.7), 1.0))
	_ok("★hold_fade 末端归零(1.0 → 0)", is_equal_approx(AV.hold_fade(1.0), 0.0))
	var mono := true
	var prev := 2.0
	for i in range(41):
		var v: float = AV.hold_fade(float(i) / 40.0)
		if v > prev + 0.0001:
			mono = false
		prev = v
	_ok("★hold_fade 全程单调不增(41 个采样点)", mono)
	## ★★分母: 线性淡出在这里会红 —— 证明这条判据卡得住"淡出病"那个形状
	_ok("★★分母: 线性淡出(1-t)在 0.7 处只有 0.30, 与本曲线的 1.0 分得开",
		absf(AV.hold_fade(0.7) - (1.0 - 0.7)) > 0.5)

	## ring_breath: 常驻环要"活着"而不是闪一下
	var in_range := true
	for i in range(60):
		var b: float = AV.ring_breath(float(i) * 0.05)
		if b > 1.0001 or b < 0.94 - 0.0001:
			in_range = false
	_ok("★环呼吸恒在 [0.94, 1.0] 内(60 个采样点), 不会缩成一点也不会撑爆",
		in_range and is_equal_approx(AV.ring_breath(0.0), 1.0))

	## boomerang: 10 把在 4 秒里均匀铺开
	var ts: Array = []
	for i in range(AF.SERAPH_BOOMERANGS):
		ts.append(AV.boomerang_launch_t(i, AF.SERAPH_BOOMERANGS, AF.SERAPH_CAST_TIME))
	var inc := true
	for i in range(1, ts.size()):
		if float(ts[i]) <= float(ts[i - 1]):
			inc = false
	_ok("★★%d 把回旋镖的出手时刻**严格递增**且第一把在 0(实测 %s…)"
		% [AF.SERAPH_BOOMERANGS, str(ts.slice(0, 3))],
		inc and is_equal_approx(float(ts[0]), 0.0))
	_ok("★★最后一把也在 %.1f 秒之内出手(实测 %.2f) —— 出手时刻超出总时长 = 有几把永远不出"
		% [AF.SERAPH_CAST_TIME, float(ts[-1])], float(ts[-1]) < AF.SERAPH_CAST_TIME)
	_ok("★去程匀速: frac(半程)=0.5 而不是加速/减速(2026-09-15 起在途路径按 SERAPH_BOOM_SPEED 恒速走)",
		is_equal_approx(AV.boomerang_frac(0.5, 1.0), 0.5))
	## 镖身切帧: 按飞行时间循环, 20 帧/秒 × 8 帧 = 0.4 秒一圈
	_ok("★镖身切帧按飞行时间循环(0 秒第 0 帧 · 0.05 秒第 1 帧 · 0.4 秒转满一圈回第 0 帧)",
		ASV.boom_frame(0.0) == 0 and ASV.boom_frame(0.051) == 1 and ASV.boom_frame(0.401) == 0
		and ASV.boom_frame(0.351) == ASV.BOOM_FRAMES - 1)

	## aura_pulse: 跳的那一刻最亮, 让"每 0.5 秒一跳"看得出节拍
	_ok("★法阵脉冲: 跳的那一刻最亮(1.0), 拍尾落到底(0.35)",
		is_equal_approx(AV.aura_pulse(0.0), 1.0) and is_equal_approx(AV.aura_pulse(1.0), 0.35))
	var pm := true
	var pv := 2.0
	for i in range(21):
		var a2: float = AV.aura_pulse(float(i) / 20.0)
		if a2 > pv + 0.0001:
			pm = false
		pv = a2
	_ok("★法阵脉冲单调衰减(21 个采样点)", pm)

	## revive_gather: 前慢后快(三次方) —— 线性的话读不出"聚拢"
	_ok("★重生聚拢 端点对(0→0 / 1→1)",
		is_equal_approx(AV.revive_gather(0.0), 0.0) and is_equal_approx(AV.revive_gather(1.0), 1.0))
	_ok("★★★重生是**前慢后快**: 走到一半时间只聚拢了 %.0f%%(线性会是 50%%)"
		% (AV.revive_gather(0.5) * 100.0), AV.revive_gather(0.5) < 0.30,
		"线性实现在这里会红")

	## seed_glow: 无上限的层数 → 有上限的视觉
	_ok("★种子火星浓度随层数涨(1 层 %.2f < 15 层 %.2f)"
		% [AV.seed_glow(1), AV.seed_glow(15)], AV.seed_glow(1) < AV.seed_glow(15))
	_ok("★★视觉浓度**封顶**(200 层与 30 层一样浓, 否则叠满是一团纯白)",
		is_equal_approx(AV.seed_glow(200), 1.0) and is_equal_approx(AV.seed_glow(30), 1.0))

	## ★★演出接在结算之后(§3.5): 源码守卫 —— 数值不许埋进 tween 链
	var src: String = FileAccess.get_file_as_string("res://scripts/systems/equip/axe_final_forms.gd")
	_ok("★★结算文件里【不出现】tween —— 数值全是同步的, 演出只在 axe_final_vfx 里",
		not src.contains("_reg_tween") and not src.contains("create_tween"),
		"分母: 源码 %d 字" % src.length())
	_ok("★分母: 结算文件确实调了演出(vfx.xxx), 否则上面那条是空检查",
		src.contains("vfx."))


# ══════════════════════════════════════════════════════════════
#  ⑦ ★★走【真入口】—— 造物的主动到底放不放得出来
# ══════════════════════════════════════════════════════════════
## 由来(2026-09-01): 零调用者扫描抓到 —— `undead_on_death` / `seraph_boomerang_settle` /
## `holo_aura_tick` / `ember_light_cast` **产品代码里一个调用者都没有**。
## 也就是说四个造物的主动**一个都放不出来**, 而上面 64 条门禁全绿 ——
## 因为它们直接调那些函数, 从没证明"游戏里真的会走到"。
## (memory [[fb-verify-must-run-the-real-path]]: 断言函数存在 ≠ 还有没有人调)
##
## ⇒ 这一节**只从 `AxeSystem.tick` 进去**, 不碰 `_fin.*`。
func _t_real_path() -> void:
	print("--- ⑦ 走真入口 ---")
	var axs = _s._equip_sys._axe
	## 造一个"携带者 + 斧头"的最小场: tick 的入口参数是**携带者**, 不是斧头
	for cs in [["seraph", "_seraph_until"], ["holo", "_holo_until"]]:
		var fk: String = str(cs[0])
		var flag: String = str(cs[1])
		var ax: Dictionary = _mk_axe(fk)
		ax["maxEnergy"] = AE.ACTIVE_ENERGY
		ax["energy"] = AE.ACTIVE_ENERGY          # 龟能满 ⇒ 主动该放了
		ax["hp"] = 3000.0
		var owner: Dictionary = _mk_axe("")
		owner["_axe_ref"] = ax
		_mk_foe(Vector2(200, 0))
		axs.tick(owner, 0.016)                   # ★真入口
		_ok("★★%s: 从 AxeSystem.tick 进去, 主动**真的起来了**(标记 %s)" % [fk, flag],
			ax.has(flag), "龟能 %.0f" % float(ax.get("energy", -1)))
	## 余烬: 主动 = 立刻起一个 4 秒 buff(不是蓄力)
	var ex: Dictionary = _mk_axe("ember")
	ex["maxEnergy"] = AE.ACTIVE_ENERGY
	ex["energy"] = AE.ACTIVE_ENERGY
	ex["hp"] = 3000.0
	var eo: Dictionary = _mk_axe("")
	eo["_axe_ref"] = ex
	axs.tick(eo, 0.016)
	_ok("★★余烬: 从真入口进去后余烬之光**真的挂上了**(层数 %d · 免控 %s)"
		% [_s._equip_sys._axe._fin.ember_light_stacks(ex), str(float(ex.get("cc_immune_until", 0.0)) > float(_s._t))],
		_s._equip_sys._axe._fin.ember_light_stacks(ex) >= 1
		and float(ex.get("cc_immune_until", 0.0)) > float(_s._t))
	## ★分母: 没有造物时仍然走**被动6的猛砸**(不能因为加了造物就把原路径弄丢)
	var nx: Dictionary = _mk_axe("")
	nx["_axe_pv"] = 4
	nx["maxEnergy"] = AE.ACTIVE_ENERGY
	nx["energy"] = AE.ACTIVE_ENERGY
	nx["hp"] = 3000.0
	var no: Dictionary = _mk_axe("")
	no["_axe_ref"] = nx
	axs.tick(no, 0.016)
	_ok("★★★分母: 没有造物时仍走被动6的梯形蓄力(原路径没被造物挤掉)",
		_s._equip_sys._axe._pas.is_charging(nx), "在蓄力=%s" % str(_s._equip_sys._axe._pas.is_charging(nx)))
	## ★炽天使真的会**一把一把甩** —— 推时间(战斗时钟 + 装备全局步), 数它甩了几把、目标什么时候掉血。
	## ★2026-09-15 回旋镖改成「经过时结算」后, 原来那种"把下一把的时刻拨到过去、只调 AxeSystem.tick"的推法
	##   量不到伤害了(伤害在 EquipSystem.tick_global 那条链上)。现在按真实节奏推: 每 0.05 秒
	##   `_t` 前进 → AxeSystem.tick(到点就甩) → EquipSystem.tick_global(在途镖飞、经过就结算)。
	## ★干净单位表(同 ③ 节): 前面各节留下的探针会改变"最近的敌人" = 甩的方向。结束时原样放回。
	var bak: Array = _s._units.duplicate()
	_s._units.clear()
	var fin = axs._fin
	fin._booms.clear()
	var sx: Dictionary = _mk_axe("seraph")
	sx["maxEnergy"] = AE.ACTIVE_ENERGY
	sx["energy"] = AE.ACTIVE_ENERGY
	sx["hp"] = 3000.0
	var so: Dictionary = _mk_axe("")
	so["_axe_ref"] = sx
	var tgt: Dictionary = _mk_foe(Vector2(260, 0), 1.0e9)
	axs.tick(so, 0.016)                          # 龟能满 ⇒ 放主动(登记 4 秒 10 把)
	var hp0: float = float(tgt["hp"])
	var thrown := 0
	var hp_at_first_throw := -1.0
	var stp := 0.05
	for _i in range(int(8.0 / stp)):
		_s._t = float(_s._t) + stp
		var before: int = int(sx.get("_seraph_left", 0))
		axs.tick(so, stp)                        # ★真入口: 到点就甩
		if int(sx.get("_seraph_left", 0)) < before:
			thrown += 1
			if thrown == 1:
				hp_at_first_throw = float(tgt["hp"])
		_s._equip_sys.tick_global(stp)           # ★真链: EquipSystem.tick_global → AxeSystem.tick_global → 在途镖
	_ok("★★炽天使从真入口一共甩了 %d 把(需求是 %d 把, 4 秒内甩完自己收工)"
		% [thrown, AF.SERAPH_BOOMERANGS], thrown == AF.SERAPH_BOOMERANGS and not sx.has("_seraph_until"))
	## ★下一条不用 is_equal_approx: 它按相对误差比, 1e9 血时容差约 1 万 —— 变异 M1(出手当帧结算)掉 100 血照样绿
	_ok("★★★真入口甩出第一把的那一刻目标【没掉血】(镖还没飞到; 原来出手当帧就结算)",
		hp_at_first_throw >= 0.0 and absf(hp_at_first_throw - hp0) < 0.5,
		"%.0f → %.0f" % [hp0, hp_at_first_throw])
	_ok("★★推战斗步之后这 %d 把真的打到人了(目标掉血 %.0f)" % [thrown, hp0 - float(tgt["hp"])],
		float(tgt["hp"]) < hp0)
	_ok("★8 秒后在途表清空(每把都飞回来了, 在途 %d 把)" % fin._booms.size(), fin._booms.is_empty())
	_s._units.clear()
	_s._units.append_array(bak)
	## ★全息斧: 插地期间有 30% 减伤, **到期必须还原**
	var hx: Dictionary = _mk_axe("holo")
	hx["maxEnergy"] = AE.ACTIVE_ENERGY
	hx["energy"] = AE.ACTIVE_ENERGY
	hx["hp"] = 3000.0
	var ho: Dictionary = _mk_axe("")
	ho["_axe_ref"] = hx
	axs.tick(ho, 0.016)
	_ok("★全息插地期间拿到 %.0f%% 减伤" % (AF.HOLO_PLANT_DR * 100.0),
		is_equal_approx(float(hx.get("damage_reduction", 0.0)), AF.HOLO_PLANT_DR))
	hx["_holo_until"] = _s._t - 0.01            # 拨到过期
	axs.tick(ho, 0.016)
	_ok("★★★插地到期后减伤**还原**(不还原就是个永久 30%% 减伤的怪物)",
		is_equal_approx(float(hx.get("damage_reduction", 0.0)), 0.0),
		"实测 %.2f" % float(hx.get("damage_reduction", 0.0)))
	## ★零调用者守卫: 四个曾经"写了没人读"的函数, 现在必须在产品里可达
	var src: String = FileAccess.get_file_as_string("res://scripts/systems/equip/axe_final_forms.gd")
	var sys_src: String = FileAccess.get_file_as_string("res://scripts/systems/equip/axe_system.gd")
	var eq_src: String = FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	_ok("★★造物主动的分派器被 AxeSystem 真的调了(begin_active / tick_active / active_busy)",
		sys_src.contains("_fin.begin_active(") and sys_src.contains("_fin.tick_active(")
		and sys_src.contains("_fin.active_busy("))
	_ok("★★亡灵重生挂在 on-death 上(之前 undead_on_death 零调用者 = 死了根本不会重生)",
		eq_src.contains("undead_on_death("))
	_ok("★★在途回旋镖挂在装备全局步上(EquipSystem.tick_global → AxeSystem.tick_global → tick_boomerangs)",
		eq_src.contains("_axe.tick_global(") and sys_src.contains("_fin.tick_boomerangs("))
	var dead: Array = []
	for fn in ["seraph_boomerang_launch", "holo_aura_tick", "ember_light_cast"]:
		if src.count(fn) < 2:                     # 定义 1 次 + 至少被调 1 次
			dead.append(fn)
	_ok("★★这三个曾经零调用者的函数现在**在文件内被分派器调到**(分母: 每个至少出现 2 次)",
		dead.is_empty(), str(dead))


## 这只龟【最快就绪】的那个技能还剩多少冷却 —— `_eq_grant_energy` 就是从它开始扣的,
## 所以"给了龟能"在引擎里的可观测后果就是这个数变小。
func _min_cd(u: Dictionary) -> float:
	var cds = u.get("cds", null)
	if not (cds is Dictionary) or (cds as Dictionary).is_empty():
		return -1.0
	var m: float = 1e9
	for k in cds:
		m = minf(m, float(cds[k]))
	return m