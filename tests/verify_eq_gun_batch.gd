extends Node
## verify_eq_gun_batch.gd — 枪线 4 件(077/078/079/080)逐件焊死 + 演出物理模型门禁
##
## 规格: docs/plans/20260805-装备逐件重做.md §0.5【用户逐件亲手写的定稿】
## 实装: scripts/systems/equip/eq_gun_batch.gd  ·  演出: scripts/scenes/battle/gun_eq_vfx.gd
##
## ★本文件的规矩(契约 §8, 逐条对应 CLAUDE.md / memory):
##   · 全部用【干净合成单位】—— 随机 spawn 的敌带盾/flat_dr/未播种 RNG 会让精确数值
##     在 CI 上偶发红(memory [[fb-ci-vs-local-divergence]])。开测前先 `_units.clear()`,
##     否则默认对局的 9 只真单位会抢走 `_nearest_enemy`。
##   · 合成单位坐标放 ARENA 【内】—— 放外面会被钳到同一点(500 帧红 1500 帧绿那次)。
##   · 需求字面值【直接写在断言里】, 绝不引用被测常量 —— 引用常量就是拿代码跟自己比, 永远绿。
##     (唯一例外是"两个常量必须相等"这类**同一性**断言, 那本来就要读两边。)
##   · 至少各有一条【经中央伤害管线 _apply_damage_from / _apply_damage 的端到端】断言 ——
##     memory [[fb-verify-must-run-the-real-path]]:「断言函数存在」守不住「还有没有人调它」。
##   · **不依赖任何演出 tween / 弹道飞完**(CLAUDE.md §3.5): 排队子弹靠同步喂
##     `_ballistics._step_pending_shots(dt)`, 演出寿命靠同步喂 `vfx.tick(delta)`。
##   · 每条断言打印实测值与期望值; 每组带一条【分母】断言(N=0 是空检查不是通过)。
##   · 美术断言查**真的显示进 `_world`** 且**量真实节点**, 不是把公式在测试里抄一遍。
##
## 跑法: <godot> --headless --path . res://tests/verify_eq_gun_batch.tscn --quit-after 3000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null
var _gun = null

const SEED := 20260806


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


## 干净合成单位。★携带者一律 `fortune` 不用 `basic`:
##   小龟·不屈会给小龟造成的一切伤害 +20%, 拿 basic 当携带者验精确数值会量到 1.2 倍。
func _mk(id: String, side: String, off: Vector2, hp: float = 100000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["dodge_bonus"] = 0.0
	u["damage_reduction"] = 0.0
	u["damage_amp"] = 0.0
	u["crit"] = 0.0
	u["crit_dmg"] = 1.5
	u["heal_amp"] = 0.0
	u["shield_amp"] = 0.0
	u["reflect"] = 0.0
	u["lifesteal"] = 0.0
	u["ls_bonus"] = 0.0
	u["armor_pen"] = 0.0
	u["magic_pen"] = 0.0
	u["armor_pen_pct"] = 0.0
	u["magic_pen_pct"] = 0.0
	u["corrode_stacks"] = 0
	u["corrode_tier"] = 0
	u["aspd_perm"] = 1.0
	u["_fire_ctrl"] = 0.0
	u["dots"] = []
	u["buffs"] = []
	u["dot_stacks"] = {}
	u["equips"] = []
	u["eq_state"] = {}
	_s._units.append(u)
	return u


func _reset() -> void:
	_s._units.clear()
	_s._pending_shots.clear()
	_s._sd_stacks = 0
	_s._synergy._by_side = {"left": {}, "right": {}}
	_gun.clear_all()


func _equip(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	return u


## 走【真入口】把装备属性 + 批④ 登场钩全跑一遍(EquipStatsApply._eq_apply_all_stats
## 末尾就是 `_b4_on_spawn_all`, 它查 B4_OWNER 再调 sys.on_spawn)。
func _spawn_all() -> void:
	_s._equip_sys._stats._eq_apply_all_stats()


## ★必须在 `_spawn_all()` 【之后】调 —— 那一步会把装备 STATS(攻击/破甲/攻速)加到携带者身上
## 并 `_recalc_stats`, 在它之前设的 atk/aspd 会被冲掉。
## 把攻击力钉成给定值、把破甲/暴击清零, 才量得出"15 + 0.3ATK"这种字面公式:
##   · 破甲不清零 ⇒ 敌人 def=0 时会变成【负护甲 = 增伤】(DamageMath 有意设计), 数值全部偏高;
##   · 暴击不清零 ⇒ 精确数值变成掷骰, CI 必然偶发红。
func _pin(u: Dictionary, atk: float) -> void:
	u["atk"] = atk
	u["base_atk"] = atk
	u["armor_pen"] = 0.0
	u["magic_pen"] = 0.0
	u["armor_pen_pct"] = 0.0
	u["magic_pen_pct"] = 0.0
	u["crit"] = 0.0
	u["damage_amp"] = 0.0
	u["_fire_ctrl"] = 0.0


func _tier(side: String, t: int) -> void:
	_s._synergy._by_side[side] = {"枪": t}


## 同步把排队的子弹全部打出去(★不等 tween、不等帧)
func _pump(times: int = 40) -> void:
	for _i in range(times):
		if _s._pending_shots.is_empty():
			return
		_s._ballistics._step_pending_shots(0.2)


func _find_summon(kind: String) -> Variant:
	for u in _s._units:
		if u is Dictionary and str(u.get("summon_kind", "")) == kind:
			return u
	return null


func _strip(path: String) -> String:
	var raw: String = FileAccess.get_file_as_string(path)
	var out := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		out += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	return out


func _fn_body(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var e: int = code.find("\nfunc ", i + 1)
	return code.substr(i, (e - i) if e > i else -1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 枪线 4 件(077 铜管手铳 / 078 电鳗双管铳 / 079 珊瑚急救塔 / 080 打捞旋翼机) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0
	_gun = _s._equip_sys._gun_sys

	_t_dispatch()
	_t_from_equip()
	_t077_summon()
	_t077_cap()
	_t077_pen_gold()
	_t078_alternate()
	_t078_left()
	_t078_right()
	_t078_gold()
	_t079_pos()
	_t079_summon()
	_t079_aspd_live()
	_t079_bullet()
	_t079_lowest_ally()
	_t080_spawn()
	_t080_strafe_energy()
	_t080_lane()
	_t080_bomb()
	_t080_crash()
	_t_vfx_models()
	_t_vfx_nodes()
	_t_clear()

	_gun.clear_all()
	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 枪线 4 件" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ═════════════════════════════════════════════════════════════
# ⓪ 分发纪律与接线 —— 四件都落在【已有的】十个钩子上, 没有新增分发口
# ═════════════════════════════════════════════════════════════
func _t_dispatch() -> void:
	print("── ⓪ 分发纪律与接线 ──")
	var code: String = _strip("res://scripts/systems/equip/equip_system.gd")
	_ok("⓪ ★分母: equip_system.gd 剥注释后非空", code.length() > 5000, "len=%d" % code.length())
	var miss: Array = []
	for iid in ["p2eq_077", "p2eq_078", "p2eq_079", "p2eq_080"]:
		if str(EquipSystem.B4_OWNER.get(iid, "")) != "gun":
			miss.append(iid)
	_ok("⓪ B4_OWNER 把 077~080 四件全路由到 gun", miss.is_empty(), "缺 %s" % str(miss))
	var gbody: String = _fn_body(code, "func tick_global")
	_ok("⓪ ★分母: tick_global 函数体非空", gbody.length() > 100, "len=%d" % gbody.length())
	_ok("⓪ tick_global 里真的调了批④ 的全局 tick(_b4s.tick(delta))", gbody.contains("_b4s.tick(delta)"))
	# ★★这条守的是"全局推进不能挂在【某只龟身上有装备】的闸里面": 077 的小手枪 / 079 的炮台 /
	#   080 的直升机在携带者阵亡后都要继续动, 挂在那个闸里就会整个停摆(而且不报错)。
	var rb: String = _strip("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("⓪ ★★主循环【无条件】每帧调一次 tick_global(不看有没有带装备的活单位)",
		rb.contains("_equip_sys.tick_global(dt)"))
	var body: String = _fn_body(code, "func _eq_tick")
	_ok("⓪ ★分母: _eq_tick 函数体非空", body.length() > 200, "len=%d" % body.length())
	_ok("⓪ _eq_tick 里真的调了批④ 的逐单位 tick(_b4u.tick_unit(u, delta))",
		body.contains("_b4u.tick_unit(u, delta)"))
	var sac: String = _strip("res://scripts/systems/equip/equip_stats_apply.gd")
	_ok("⓪ 登场钩 _b4_on_spawn_all 真的调 sys.on_spawn", sac.contains("sys.on_spawn("))
	var dl: String = _strip("res://scripts/scenes/battle/dual_lane_flow.gd")
	_ok("⓪ 换路撤场真的调 _b4ref.clear_all()", dl.contains("_b4ref.clear_all()"))
	_ok("⓪ ★★接线: battle._equip_sys._gun_sys 真的是 EqGunBatch",
		_gun != null and _gun is EqGunBatch, str(_gun))
	_ok("⓪ ★★接线: 它自己也真的 new 了演出层 GunEqVfx",
		_gun.vfx != null and _gun.vfx is GunEqVfx, str(_gun.vfx))
	var iv_bad: Array = []
	for iid2 in ["p2eq_077", "p2eq_078", "p2eq_079", "p2eq_080"]:
		if EquipSystem.EQ_IV_BATCH1.has(iid2):
			iv_bad.append(iid2)
	_ok("⓪ 四件都【不】排 EQ_PERIOD(全部自管计时, 契约 §2)", iv_bad.is_empty(), "还在表里: %s" % str(iv_bad))
	# STATS 三星属性在位(主会话填的; 这里只当分母, 不重抄数值)
	var st_n := 0
	for iid3 in ["p2eq_077", "p2eq_078", "p2eq_079", "p2eq_080"]:
		if (_s.EquipStats.STATS.get(iid3, []) as Array).size() == 3:
			st_n += 1
	_ok("⓪ ★分母: 四件的 STATS 都有三星三档", st_n == 4, "有 %d/4" % st_n)


# ═════════════════════════════════════════════════════════════
# ★焊死口径②: 本文件打出的每一段伤害都 from_equip = true
# ═════════════════════════════════════════════════════════════
func _t_from_equip() -> void:
	print("── ★ 焊死口径②: from_equip=true(不回钩 on-hit / 不触反伤 → 不自激) ──")
	var src: String = _strip("res://scripts/systems/equip/eq_gun_batch.gd")
	var total := 0
	var bad := 0
	for ln in src.split("\n"):
		if not ln.contains("_apply_damage_from("):
			continue
		total += 1
		if not ln.contains(", false, true)"):
			bad += 1
	_ok("★ ★分母: eq_gun_batch.gd 里一共 %d 处 _apply_damage_from" % total, total >= 8, "total=%d" % total)
	_ok("★ 每一处 _apply_damage_from 都带 from_equip=true", bad == 0, "漏了 %d 处" % bad)
	# 端到端行为证据: 反伤只在 `not from_equip` 时触发(battle_damage.gd:237)。
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	var foe: Dictionary = _mk("fortune", "right", Vector2(-100.0, 0.0), 100000.0)
	foe["reflect"] = 1.0                       # 受击 100% 反伤 —— 只要回钩就一定看得见
	_equip(u, "p2eq_078", 1)
	_spawn_all()
	_pin(u, 100.0)
	var h0: float = float(u["hp"])
	_gun._eel_right(u, 0)
	var refl_eq: float = h0 - float(u["hp"])
	_s._damage._apply_damage_from(u, foe, 100, Color.WHITE)   # 分母: 同一条路 from_equip 默认 false
	var refl_plain: float = h0 - float(u["hp"]) - refl_eq
	_ok("★ ★分母: 关掉 from_equip 时反伤确实会打回来", refl_plain > 0.0, "反伤=%.1f" % refl_plain)
	_ok("★ 078 右管打出去【没有】触发反伤(⇒ from_equip 生效)", _near(refl_eq, 0.0, 0.001),
		"携带者掉血=%.3f (应为 0)" % refl_eq)


# ═════════════════════════════════════════════════════════════
# ① 077 铜管手铳
# ═════════════════════════════════════════════════════════════
func _t077_summon() -> void:
	print("── ① 077: 小手枪 30/60/100 血 · 10/20/30 攻 · 700 码 · 攻速 2/秒 · 50% 暴击 ──")
	var got_hp: Array = []
	var got_atk: Array = []
	var n := 0
	for si in range(3):
		_reset()
		var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
		_equip(u, "p2eq_077", si + 1)
		_spawn_all()
		var p = _find_summon("pistol")
		if not (p is Dictionary):
			continue
		n += 1
		got_hp.append(float(p["maxHp"]))
		got_atk.append(float(p["atk"]))
		if si == 2:
			_ok("① 3★ 射程 700 码", _near(float(p["atk_range"]), 700.0), "range=%.0f" % float(p["atk_range"]))
			_ok("① 3★ 攻速 2 次/秒(攻击间隔 0.5 秒)", _near(float(p["atk_interval"]), 0.5),
				"iv=%.3f" % float(p["atk_interval"]))
			_ok("① 3★ 暴击率 50%", _near(float(p["crit"]), 0.5), "crit=%.2f" % float(p["crit"]))
			_ok("① 小手枪是【单位】(能被选中/吃 AOE/被嘲讽 —— 规格没写不可选中)",
				_s._arr_has_unit(_s._units, p))
	_ok("① ★分母: 三个星级各生成了一把小手枪", n == 3, "n=%d" % n)
	_ok("① 血量 30/60/100(★不乘 HP_MULT: 装备/召唤物血是最终值)",
		got_hp == [30.0, 60.0, 100.0], str(got_hp))
	_ok("① 攻击力 10/20/30", got_atk == [10.0, 20.0, 30.0], str(got_atk))


func _t077_cap() -> void:
	print("── ① 077: 受到的所有伤害(含真伤/DoT)降为 2 点; 携带者阵亡后 5 点 ──")
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u, "p2eq_077", 2)
	_spawn_all()
	var atkr: Dictionary = _mk("fortune", "right", Vector2(100.0, 0.0))
	var plain: Dictionary = _mk("fortune", "right", Vector2(200.0, 60.0), 100000.0)
	var p = _find_summon("pistol")
	_ok("① ★分母: 小手枪在场且满血 60(2★)", p is Dictionary and _near(float(p["hp"]), 60.0),
		"hp=%s" % (str(p["hp"]) if p is Dictionary else "无"))
	# ★分母: 不带封顶的干净单位挨同样一发, 掉的是 500
	var b0: float = float(plain["hp"])
	_s._damage._apply_damage_from(atkr, plain, 500, Color.WHITE)
	_ok("① ★分母: 不带封顶的合成单位挨 500 普攻 → 掉 500",
		_near(float(plain["hp"]), b0 - 500.0, 0.6), "掉了 %.1f" % (b0 - float(plain["hp"])))
	var h0: float = float(p["hp"])
	_s._damage._apply_damage_from(atkr, p, 500, Color.WHITE)
	_ok("① 普攻/技能路(_apply_damage_from) 500 伤害 → 只掉 2",
		_near(h0 - float(p["hp"]), 2.0, 0.01), "掉了 %.2f" % (h0 - float(p["hp"])))
	h0 = float(p["hp"])
	_s._damage._apply_damage(p, 500, Color.WHITE, atkr, "tru")
	_ok("① ★DoT/真伤路(_apply_damage · bucket=tru) 500 真伤 → 也只掉 2 (§3.3 两条路径)",
		_near(h0 - float(p["hp"]), 2.0, 0.01), "掉了 %.2f" % (h0 - float(p["hp"])))
	h0 = float(p["hp"])
	_s._damage._apply_damage(p, 500, Color.WHITE, atkr, "mag")
	_ok("① 灼烧/中毒这类每跳(bucket=mag) 500 → 也只掉 2",
		_near(h0 - float(p["hp"]), 2.0, 0.01), "掉了 %.2f" % (h0 - float(p["hp"])))
	# 携带者阵亡 → 5 点。走真入口 _eq_on_death(它查 B4_OWNER 再调 on_death)
	u["alive"] = false
	_s._equip_sys._eq_on_death(u, null)
	h0 = float(p["hp"])
	_s._damage._apply_damage_from(atkr, p, 500, Color.WHITE)
	_ok("① 携带者阵亡后 → 每段伤害降为 5 点", _near(h0 - float(p["hp"]), 5.0, 0.01),
		"掉了 %.2f" % (h0 - float(p["hp"])))
	h0 = float(p["hp"])
	_s._damage._apply_damage(p, 500, Color.WHITE, atkr, "tru")
	_ok("① 携带者阵亡后真伤也是 5 点", _near(h0 - float(p["hp"]), 5.0, 0.01),
		"掉了 %.2f" % (h0 - float(p["hp"])))


func _t077_pen_gold() -> void:
	print("── ① 077: 每次攻击 +1 破甲(每路重置) + 金弹(每把枪各自计数) + 端到端伤害 ──")
	_reset()
	_tier("left", 3)                     # 枪羁绊 3 档: 每 2 发一发金弹, 金弹 +100% 真伤
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u, "p2eq_077", 3)
	_spawn_all()
	var foe: Dictionary = _mk("fortune", "right", Vector2(-100.0, 0.0), 100000.0)
	var p = _find_summon("pistol")
	p["crit"] = 0.0                      # 关暴击才量得准(暴击是 RNG)
	p["pos"] = foe["pos"] + Vector2(-200.0, 0.0)
	_ok("① ★分母: 小手枪初始破甲为 0", _near(float(p["armor_pen"]), 0.0), "pen=%.1f" % float(p["armor_pen"]))
	_s._pending_shots.clear()
	var e = null
	for x in _gun._pistols:
		if is_same(x["u"], p):
			e = x
	_ok("① ★分母: 登记表里找得到这把小手枪", e != null)
	for _k in range(4):
		_gun._pistol_attack(e)
	_ok("① 攻击 4 次 → 破甲 +4(每次攻击各 +1)", _near(float(p["armor_pen"]), 4.0),
		"pen=%.1f" % float(p["armor_pen"]))
	_ok("① 金弹: 4 发正常弹 + 3 档每 2 发一发金弹 ⇒ 排了 6 发",
		_s._pending_shots.size() == 6, "排了 %d 发" % _s._pending_shots.size())
	# 端到端: 3★ 攻 30, 敌 def=0 ⇒ 正常弹 30; 金弹 30 + 100% 真伤 = 60。合计 4×30 + 2×60 = 240
	# ★量伤害前把刚攒的 4 点破甲归零 —— 敌人 def=0 时破甲会把护甲压成【负数 = 增伤】
	#   (DamageMath.resist_multiplier 对负值是有意设计的增伤), 不归零量到的是 264 而不是 240,
	#   那验的就不是"1ATK 物理"而是"1ATK + 破甲增伤"两件事混在一起。
	p["armor_pen"] = 0.0
	var f0: float = float(foe["hp"])
	_pump()
	var dealt: float = f0 - float(foe["hp"])
	_ok("① ★端到端(过中央伤害管线): 4 正常 ×30 + 2 金弹 ×(30+30真伤) = 240",
		_near(dealt, 240.0, 0.5), "实打 %.1f" % dealt)
	# 每路重置: 换路会调 clear_all + 重新登场
	_gun.clear_all()
	_reset()
	var u2: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u2, "p2eq_077", 3)
	_spawn_all()
	var p2 = _find_summon("pistol")
	_ok("① 破甲【每路重置】: 换路重建后新小手枪破甲回 0",
		p2 is Dictionary and _near(float(p2["armor_pen"]), 0.0),
		"pen=%s" % (str(p2["armor_pen"]) if p2 is Dictionary else "无"))


# ═════════════════════════════════════════════════════════════
# ② 078 电鳗双管铳
# ═════════════════════════════════════════════════════════════
func _t078_alternate() -> void:
	print("── ② 078: 左右管共享计数, 每 2 秒交替射一发 ──")
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u, "p2eq_078", 1)
	_spawn_all()
	_pin(u, 100.0)
	_mk("fortune", "right", Vector2(-100.0, 0.0))
	_ok("② ★分母: 登场钩写了常驻字段 _g078_si(tick_unit 的守卫)", u.has("_g078_si"))
	for _k in range(19):
		_gun.tick_unit(u, 0.1)          # 1.9 秒
	_ok("② 1.9 秒时还没开火", int(u.get("_g078_n", -1)) == 0, "n=%d" % int(u.get("_g078_n", -1)))
	_gun.tick_unit(u, 0.1)              # 2.0 秒
	_ok("② 2.0 秒开出第 1 发", int(u.get("_g078_n", -1)) == 1, "n=%d" % int(u.get("_g078_n", -1)))
	for _k2 in range(20):
		_gun.tick_unit(u, 0.1)          # 再 2 秒
	_ok("② 4.0 秒开出第 2 发(两管加起来每 2 秒一发 ⇒ 每管各 4 秒一次)",
		int(u.get("_g078_n", -1)) == 2, "n=%d" % int(u.get("_g078_n", -1)))
	# ★跨路不重置的陷阱: 计时器是自管累加器, 不读 battle._t
	var body: String = _strip("res://scripts/systems/equip/eq_gun_batch.gd")
	_ok("② ★口径③: tick_unit 用自管累加器, 没有拿 battle._t 直接和常数比",
		not _fn_body(body, "func tick_unit").contains("battle._t"))


func _t078_left() -> void:
	print("── ② 078 左管: 400 码 60 度锥形霰弹 15+0.3 / 25+0.6 / 40+1 倍攻击力物理 ──")
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-400.0, 0.0))
	_equip(u, "p2eq_078", 1)
	_spawn_all()
	_pin(u, 100.0)
	var inn: Dictionary = _mk("fortune", "right", Vector2(-200.0, 0.0))          # 正前 200 码, 锥内
	var side_out: Dictionary = _mk("fortune", "right", Vector2(-400.0, 200.0))   # 正上方 200 码 ⇒ 90 度, 锥外
	var far_out: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))       # 正前 600 码 ⇒ 超 400 码
	var h1: float = float(inn["hp"])
	var h2: float = float(side_out["hp"])
	var h3: float = float(far_out["hp"])
	_gun._eel_left(u, 0, Vector2.RIGHT)
	_ok("② 1★ 锥内: 15 + 0.3×100 = 45", _near(h1 - float(inn["hp"]), 45.0, 0.5),
		"实打 %.1f" % (h1 - float(inn["hp"])))
	_ok("② 60 度锥外(正侧方 90 度)不吃伤", _near(h2 - float(side_out["hp"]), 0.0, 0.01),
		"实打 %.1f" % (h2 - float(side_out["hp"])))
	_ok("② 400 码外(600 码)不吃伤", _near(h3 - float(far_out["hp"]), 0.0, 0.01),
		"实打 %.1f" % (h3 - float(far_out["hp"])))
	var h1b: float = float(inn["hp"])
	_gun._eel_left(u, 2, Vector2.RIGHT)
	_ok("② 3★ 锥内: 40 + 1.0×100 = 140", _near(h1b - float(inn["hp"]), 140.0, 0.5),
		"实打 %.1f" % (h1b - float(inn["hp"])))


func _t078_right() -> void:
	print("── ② 078 右管: 首目标 0.5ATK 物理 + 50/100/180 魔法, 连锁每跳降 20/15/10% ──")
	for si in [0, 2]:
		_reset()
		var u: Dictionary = _mk("fortune", "left", Vector2(-500.0, 0.0))
		_equip(u, "p2eq_078", si + 1)
		_spawn_all()
		_pin(u, 100.0)
		var a: Dictionary = _mk("fortune", "right", Vector2(-300.0, 0.0))
		var b: Dictionary = _mk("fortune", "right", Vector2(-100.0, 0.0))
		var c: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
		var h: Array = [float(a["hp"]), float(b["hp"]), float(c["hp"])]
		_gun._eel_right(u, si)
		var d0: float = h[0] - float(a["hp"])
		var d1: float = h[1] - float(b["hp"])
		var d2: float = h[2] - float(c["hp"])
		if si == 0:
			_ok("② 1★ 首目标 = 0.5×100 物理 + 50 魔法 = 100", _near(d0, 100.0, 0.6), "实打 %.1f" % d0)
			_ok("② 1★ 第 2 跳 = 50 × 0.8 = 40", _near(d1, 40.0, 0.6), "实打 %.1f" % d1)
			_ok("② 1★ 第 3 跳 = 40 × 0.8 = 32", _near(d2, 32.0, 0.6), "实打 %.1f" % d2)
		else:
			_ok("② 3★ 首目标 = 50 物理 + 180 魔法 = 230", _near(d0, 230.0, 0.6), "实打 %.1f" % d0)
			_ok("② 3★ 第 2 跳 = 180 × 0.9 = 162", _near(d1, 162.0, 0.6), "实打 %.1f" % d1)
			_ok("② 3★ 第 3 跳 = 162 × 0.9 = 145.8 → 146", _near(d2, 146.0, 0.6), "实打 %.1f" % d2)
		_ok("② ★分母(si=%d): 三个敌人都吃到了(连锁真的跳满全场)" % si, d0 > 0.0 and d1 > 0.0 and d2 > 0.0)


func _t078_gold() -> void:
	print("── ② 078 金弹: 从轮到的那一管打出 + 首目标与每一跳都吃真伤 ──")
	# (a) 真伤: 首目标与每一跳都 ×(1+60%)
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-500.0, 0.0))
	_equip(u, "p2eq_078", 1)
	_spawn_all()
	_pin(u, 100.0)
	var a: Dictionary = _mk("fortune", "right", Vector2(-300.0, 0.0))
	var b: Dictionary = _mk("fortune", "right", Vector2(-100.0, 0.0))
	var c: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	var h: Array = [float(a["hp"]), float(b["hp"]), float(c["hp"])]
	_gun._eel_right(u, 0)
	var plain: Array = [h[0] - float(a["hp"]), h[1] - float(b["hp"]), h[2] - float(c["hp"])]
	h = [float(a["hp"]), float(b["hp"]), float(c["hp"])]
	u["_golden_pct"] = 0.60
	_gun._eel_right(u, 0)
	u["_golden_pct"] = 0.0
	var gold: Array = [h[0] - float(a["hp"]), h[1] - float(b["hp"]), h[2] - float(c["hp"])]
	_ok("② ★分母: 非金弹那一发三段都打出来了", plain[0] > 0.0 and plain[1] > 0.0 and plain[2] > 0.0, str(plain))
	_ok("② 金弹: 首目标 ×1.6(60% 真伤)", _near(float(gold[0]) / maxf(0.01, float(plain[0])), 1.6, 0.02),
		"%.1f → %.1f" % [plain[0], gold[0]])
	_ok("② 金弹: 第 2 跳也 ×1.6", _near(float(gold[1]) / maxf(0.01, float(plain[1])), 1.6, 0.02),
		"%.1f → %.1f" % [plain[1], gold[1]])
	_ok("② 金弹: 第 3 跳也 ×1.6(★用户拍板: 每一跳都吃)",
		_near(float(gold[2]) / maxf(0.01, float(plain[2])), 1.6, 0.02), "%.1f → %.1f" % [plain[2], gold[2]])
	# (b) 金弹从【轮到的那一管】打出: 第 3 个敌人放在锥外 ⇒ 只有右管够得到它
	_reset()
	_tier("left", 3)                                # 3 档: 射满 2 发出一发金弹
	var u2: Dictionary = _mk("fortune", "left", Vector2(-500.0, 0.0))
	_equip(u2, "p2eq_078", 1)
	_spawn_all()
	_pin(u2, 100.0)
	_mk("fortune", "right", Vector2(-300.0, 0.0))
	_mk("fortune", "right", Vector2(-100.0, 0.0))
	var back: Dictionary = _mk("fortune", "right", Vector2(-500.0, 300.0))   # 正侧方 ⇒ 左管锥打不到
	u2["_g078_n"] = 1                               # 下一发轮到【右管】
	u2["_gun_shot_ct"] = {"p2eq_078": 1}            # 再射 1 发就满 2 ⇒ 这一发之后跟一发金弹
	_s._pending_shots.clear()
	var bh: float = float(back["hp"])
	_gun._eel_fire(u2, 0)
	_ok("② ★分母: 这一发触发了金弹(排了 2 发)", _s._pending_shots.size() == 2,
		"排了 %d 发" % _s._pending_shots.size())
	_pump()
	var hits_r: float = bh - float(back["hp"])
	_ok("② 轮到右管时金弹也是【右管】(锥外的第 3 人被电了 2 次)", hits_r > 0.0 and hits_r > 40.0,
		"锥外敌掉血 %.1f" % hits_r)
	# 对照: 轮到左管时金弹也是左管 ⇒ 锥外的人一次都打不到
	u2["_g078_n"] = 0                               # 下一发轮到【左管】
	u2["_gun_shot_ct"] = {"p2eq_078": 1}
	_s._pending_shots.clear()
	bh = float(back["hp"])
	_gun._eel_fire(u2, 0)
	_pump()
	_ok("② 轮到左管时金弹也是【左管】(锥外的第 3 人一次都没被打到)",
		_near(bh - float(back["hp"]), 0.0, 0.01), "锥外敌掉血 %.1f" % (bh - float(back["hp"])))


# ═════════════════════════════════════════════════════════════
# ③ 079 珊瑚急救塔
# ═════════════════════════════════════════════════════════════
func _t079_pos() -> void:
	print("── ③ 079: 生成在携带者【后方 150 码】—— 双边 / 边界 / 障碍 ──")
	var arena: Rect2 = _s.ARENA
	var c: Vector2 = arena.position + arena.size * 0.5
	var pl: Vector2 = EqGunBatch.tower_pos(c, "left", arena, [], 28.0)
	var pr: Vector2 = EqGunBatch.tower_pos(c, "right", arena, [], 28.0)
	_ok("③ left 阵营朝右打 ⇒ 后方是 −X, 150 码", _near(pl.x, c.x - 150.0) and _near(pl.y, c.y),
		"%s (中心 %s)" % [str(pl), str(c)])
	_ok("③ right 阵营朝左打 ⇒ 后方是 +X, 150 码", _near(pr.x, c.x + 150.0) and _near(pr.y, c.y),
		str(pr))
	_ok("③ ★分母: 两边的落点确实不同(不是写死一侧)", not _near(pl.x, pr.x), "%.0f vs %.0f" % [pl.x, pr.x])
	# 边界: 携带者贴左边界时, 后方 150 会越界 → 必须被钳回场内
	var edge: Vector2 = Vector2(arena.position.x + 20.0, c.y)
	var pe: Vector2 = EqGunBatch.tower_pos(edge, "left", arena, [], 28.0)
	_ok("③ 落点越界 → 钳回 ARENA 内", pe.x >= arena.position.x and pe.x <= arena.end.x
		and pe.y >= arena.position.y and pe.y <= arena.end.y, str(pe))
	_ok("③ ★分母: 不钳的话确实会越界", edge.x - 150.0 < arena.position.x,
		"裸落点 x=%.0f 边界 x=%.0f" % [edge.x - 150.0, arena.position.x])
	# 障碍: 把一块礁石正好放在落点上 → 必须被推到椭圆外
	var raw: Vector2 = Vector2(c.x - 150.0, c.y)
	var ob: Array = [{"c": raw, "rx": 60.0, "ry": 36.0}]
	var po: Vector2 = EqGunBatch.tower_pos(c, "left", arena, ob, 28.0)
	var d: Vector2 = po - raw
	var ell: float = Vector2(d.x / (60.0 + 28.0), d.y / (36.0 + 28.0)).length()
	_ok("③ 落点落进障碍(含 OBSTACLE_MARGIN)→ 沿径向推到椭圆边上", ell >= 0.999,
		"椭圆参数 t=%.3f (≥1 才算在外)" % ell)
	_ok("③ ★分母: 不推的话裸落点确实在障碍里", true, "裸落点就是礁石中心")


func _t079_summon() -> void:
	print("── ③ 079: 炮台 700/1200/2500 血 · 15/20/30 攻 · 50/70/100 双抗 ──")
	var hp: Array = []
	var atk: Array = []
	var res: Array = []
	var n := 0
	for si in range(3):
		_reset()
		var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
		_equip(u, "p2eq_079", si + 1)
		_spawn_all()
		var t = _find_summon("medtower")
		if not (t is Dictionary):
			continue
		n += 1
		hp.append(float(t["maxHp"]))
		atk.append(float(t["atk"]))
		res.append(Vector2(float(t["def"]), float(t["mr"])))
		if si == 0:
			_ok("③ 炮台不移动(它是建筑)", bool(t.get("no_move", false)))
	_ok("③ ★分母: 三个星级各生成了一座炮台", n == 3, "n=%d" % n)
	_ok("③ 血量 700/1200/2500", hp == [700.0, 1200.0, 2500.0], str(hp))
	_ok("③ 攻击力 15/20/30", atk == [15.0, 20.0, 30.0], str(atk))
	_ok("③ 双抗 50/70/100(护甲与魔抗同值)",
		res == [Vector2(50.0, 50.0), Vector2(70.0, 70.0), Vector2(100.0, 100.0)], str(res))


func _t079_aspd_live() -> void:
	print("── ③ 079: 攻速【实时】等于携带者(不是生成时快照) ──")
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u, "p2eq_079", 1)
	_spawn_all()
	u["atk_interval"] = 1.0
	u["aspd_perm"] = 1.0          # ★装备 STATS 的 +8% 攻速已在 _spawn_all 里加进 aspd_perm, 这里钉成 1.0 当基线
	var t = _find_summon("medtower")
	_ok("③ ★分母: 炮台在场", t is Dictionary)
	var a0: float = _gun.carrier_aps(u)
	_gun.tick(0.0)
	var iv0: float = float(t["atk_interval"])
	u["aspd_perm"] = 3.0                      # 携带者攻速 ×3(枪羁绊就是往这个通道加)
	var a1: float = _gun.carrier_aps(u)
	_gun.tick(0.0)
	var iv1: float = float(t["atk_interval"])
	_ok("③ 携带者攻速 ×3 → carrier_aps 也 ×3", _near(a1 / maxf(0.001, a0), 3.0, 0.001),
		"%.3f → %.3f 次/秒" % [a0, a1])
	_ok("③ ★生成后再改攻速, 炮台的射击间隔跟着变(⇒ 是实时不是快照)",
		_near(iv0 / maxf(0.001, iv1), 3.0, 0.01), "间隔 %.3f → %.3f 秒" % [iv0, iv1])
	# 真正的射速: 喂 1 秒, 应当射出 3 发(aps=3)
	_s._pending_shots.clear()
	_gun.tick(1.0)
	_ok("③ 喂 1 秒 → 排出 3 发(= 携带者的 3 次/秒)", _s._pending_shots.size() == 3,
		"排了 %d 发" % _s._pending_shots.size())


func _t079_bullet() -> void:
	print("── ③ 079 炮弹: 1ATK 物理 + 目标最大生命 1/1.5/2% 魔法 + 给最低血友军回 10/15/20 ──")
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u, "p2eq_079", 2)                    # 2★: 攻 20 · 1.5% · 回 15
	_spawn_all()
	var t = _find_summon("medtower")
	var foe: Dictionary = _mk("fortune", "right", Vector2(-100.0, 0.0), 1000.0)
	var ally: Dictionary = _mk("fortune", "left", Vector2(-350.0, 60.0), 1000.0)
	ally["hp"] = 100.0                          # 全场最低血 ⇒ 该它吃回血
	t["pos"] = foe["pos"] + Vector2(-200.0, 0.0)
	_ok("③ ★分母: 炮台/敌人/友军都在场", t is Dictionary and foe.get("alive", false))
	var f0: float = float(foe["hp"])
	var a0: float = float(ally["hp"])
	_gun._tower_bullet(t, 1)
	var dealt: float = f0 - float(foe["hp"])
	var healed: float = float(ally["hp"]) - a0
	_ok("③ 2★ 单发伤害 = 1×20 物理 + 1000×1.5% 魔法 = 35", _near(dealt, 35.0, 0.6), "实打 %.1f" % dealt)
	_ok("③ 2★ 给最低血友军回 15", _near(healed, 15.0, 0.01), "回了 %.1f" % healed)
	# ★★本件专属: 金弹时回血【翻倍】(全表唯一例外)
	var a1: float = float(ally["hp"])
	t["_golden_pct"] = 0.80
	_gun._tower_bullet(t, 1)
	t["_golden_pct"] = 0.0
	var healed_g: float = float(ally["hp"]) - a1
	_ok("③ ★★金弹时回血翻倍: 15 → 30(全表唯一例外)", _near(healed_g, 30.0, 0.01),
		"回了 %.1f" % healed_g)
	# 3★: 30 攻 + 2% + 回 20
	_reset()
	var u3: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u3, "p2eq_079", 3)
	_spawn_all()
	var t3 = _find_summon("medtower")
	var foe3: Dictionary = _mk("fortune", "right", Vector2(-100.0, 0.0), 1000.0)
	var ally3: Dictionary = _mk("fortune", "left", Vector2(-350.0, 60.0), 1000.0)
	ally3["hp"] = 100.0
	t3["pos"] = foe3["pos"] + Vector2(-200.0, 0.0)
	var f3: float = float(foe3["hp"])
	var y3: float = float(ally3["hp"])
	_gun._tower_bullet(t3, 2)
	_ok("③ 3★ 单发伤害 = 1×30 物理 + 1000×2% 魔法 = 50", _near(f3 - float(foe3["hp"]), 50.0, 0.6),
		"实打 %.1f" % (f3 - float(foe3["hp"])))
	_ok("③ 3★ 回血 20", _near(float(ally3["hp"]) - y3, 20.0, 0.01),
		"回了 %.1f" % (float(ally3["hp"]) - y3))


func _t079_lowest_ally() -> void:
	print("── ③ 079: 「最低血友军」★排除龟蛋与训龟大师(契约 §4 全表通用口径) ──")
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u, "p2eq_079", 1)
	_spawn_all()
	var t = _find_summon("medtower")
	var egg: Dictionary = _mk("fortune", "left", Vector2(-320.0, 40.0), 1000.0)
	egg["hp"] = 10.0
	egg["_isEgg"] = true
	var master: Dictionary = _mk("fortune", "left", Vector2(-320.0, 80.0), 1000.0)
	master["hp"] = 20.0
	master["is_trainer"] = true
	var normal: Dictionary = _mk("fortune", "left", Vector2(-320.0, 120.0), 1000.0)
	normal["hp"] = 500.0
	_ok("③ ★分母: 龟蛋(1%)与大师(2%)的血量百分比确实比普通友军(50%)低",
		float(egg["hp"]) / 1000.0 < 0.5 and float(master["hp"]) / 1000.0 < 0.5)
	var low = _gun.lowest_ally(t)
	_ok("③ 最低血友军跳过龟蛋与训龟大师, 选到普通友军",
		low is Dictionary and is_same(low, normal),
		"选到 %s" % (str(low.get("name", "?")) if low is Dictionary else "null"))


# ═════════════════════════════════════════════════════════════
# ④ 080 打捞旋翼机
# ═════════════════════════════════════════════════════════════
func _t080_spawn() -> void:
	print("── ④ 080: 无法选中 + 完全免疫的直升机(结构性: 它根本不是单位) ──")
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u, "p2eq_080", 1)
	var before: int = _s._units.size()
	_spawn_all()
	_ok("④ ★分母: 直升机登记表里确实多了一架", _gun._helis.size() == 1, "n=%d" % _gun._helis.size())
	_ok("④ ★不可选中/完全免疫是【结构性】的: 它没进 battle._units",
		_s._units.size() == before, "units %d → %d" % [before, _s._units.size()])
	var found := false
	for x in _s._units:
		if x is Dictionary and str(x.get("summon_kind", "")).contains("heli"):
			found = true
	_ok("④ 场上找不到任何叫 heli 的单位(索敌/AOE 都够不到它)", not found)


func _t080_strafe_energy() -> void:
	print("── ④ 080: 每 1.2 秒扫射 3/4/10 发 · 每发 0.35ATK · 每命中 +4 龟能(上限 100) ──")
	var shots: Array = []
	for si in range(3):
		_reset()
		var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
		_equip(u, "p2eq_080", si + 1)
		_spawn_all()
		_pin(u, 200.0)
		_mk("fortune", "right", Vector2(-100.0, 0.0))
		_s._pending_shots.clear()
		_gun.tick(1.19)
		var mid: int = _s._pending_shots.size()
		_gun.tick(0.02)
		shots.append(_s._pending_shots.size())
		if si == 0:
			_ok("④ 1.19 秒还没到 1.2 秒的节拍 ⇒ 一发都没排", mid == 0, "mid=%d" % mid)
	_ok("④ 一轮扫射 3/4/10 发(无羁绊时不带金弹)", shots == [3, 4, 10], str(shots))
	# 每发 0.35 ATK: ATK 200 ⇒ 70/发; 一轮 3 发 = 210
	_reset()
	var u2: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u2, "p2eq_080", 1)
	_spawn_all()
	_pin(u2, 200.0)
	var foe: Dictionary = _mk("fortune", "right", Vector2(-100.0, 0.0), 100000.0)
	var h0: float = float(foe["hp"])
	_s._pending_shots.clear()
	_gun.tick(1.2)
	_pump()
	_ok("④ ★端到端: 1★ 一轮 3 发 × 0.35×200 = 210", _near(h0 - float(foe["hp"]), 210.0, 1.0),
		"实打 %.1f" % (h0 - float(foe["hp"])))
	var h: Dictionary = _gun._helis[0]
	_ok("④ 3 发全命中 ⇒ 龟能 +12", _near(float(h["energy"]), 12.0, 0.01), "energy=%.1f" % float(h["energy"]))
	# ★上限 100: 先把状态钉成 bomb 让"满了就起飞"那条不触发, 才量得到【封顶】本身
	h["state"] = "bomb"
	h["energy"] = 99.0
	_gun._heli_bullet(h, 0.35)
	_ok("④ 龟能上限 100(99 + 4 只到 100, 不是 103)", _near(float(h["energy"]), 100.0, 0.01),
		"energy=%.1f" % float(h["energy"]))
	# 满龟能 ⇒ 从巡航态起飞轰炸, 并把龟能清零(下一轮重新攒)
	h["state"] = "patrol"
	h["energy"] = 96.0
	_gun._heli_bullet(h, 0.35)
	# ★★2026-08-07 状态机多了一步 `approach`(进场)。由来: 用户实拍「你用瞬移了？」——
	#   `_heli_begin_bomb` 原来一行 `h["pos"] = lane_a` **把直升机直接挪到航线起点**,
	#   航线长 800 码 ⇒ 这一跳非常显眼。现在改成先飞过去。见 tests/verify_heli_approach.gd。
	#   ⇒ 这条断言从「立刻是 bomb」改成「**进入轰炸流程**」, 并把进场喂完再验后面那些。
	#   ⚠ 不是"为了让门禁绿而放宽" —— 下面紧跟着**仍然断言它最终会到 bomb**,
	#     且进场本身有 verify_heli_approach 的 13 条(含三次变异反向验证)守着。
	_ok("④ 龟能满 ⇒ 进入【地毯轰炸】流程(先进场)",
		str(h.get("state", "")) == "approach", "state=%s" % str(h.get("state", "")))
	var _appr := 0
	while str(h.get("state", "")) == "approach" and _appr < 400:
		_gun._heli_approach(h, 0.02)
		_appr += 1
	_ok("④ 进场结束后进入【地毯轰炸】", str(h.get("state", "")) == "bomb",
		"state=%s (进场 %d 帧)" % [str(h.get("state", "")), _appr])
	_ok("④ 起飞轰炸时龟能清零(下一轮重新攒)", _near(float(h["energy"]), 0.0, 0.01),
		"energy=%.1f" % float(h["energy"]))


func _t080_lane() -> void:
	print("── ④ 080 地毯轰炸: 800×120 航线【覆盖敌人最多】且完全确定性 ──")
	# 构造: 3 人沿水平线排开(间距 300, 都落在 800 长的带内) + 2 人在 400 码外的上方
	var base: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var pts: Array = [base + Vector2(-300.0, 0.0), base, base + Vector2(300.0, 0.0),
		base + Vector2(-300.0, 400.0), base + Vector2(300.0, 400.0)]
	var lane: Array = EqGunBatch.best_lane(pts)
	_ok("④ ★分母: 候选点 5 个", pts.size() == 5)
	_ok("④ 选出的航线覆盖 3 人(那 3 个共线的)", int(lane[2]) == 3, "覆盖 %d 人" % int(lane[2]))
	var cov: int = EqGunBatch.lane_cover(Vector2(lane[0]), Vector2(lane[1]), pts)
	_ok("④ 返回的 (带心, 方向) 自洽: 用 lane_cover 复数一遍还是 3", cov == 3, "cov=%d" % cov)
	var lane2: Array = EqGunBatch.best_lane(pts)
	_ok("④ ★确定性: 同样的输入两次跑出完全一样的航线(不掷骰)",
		Vector2(lane[0]).is_equal_approx(Vector2(lane2[0])) and Vector2(lane[1]).is_equal_approx(Vector2(lane2[1]))
		and int(lane[2]) == int(lane2[2]))
	# 单调性: 往选中的航线上再加一个人, 覆盖数必须 +1
	var pts2: Array = pts.duplicate()
	pts2.append(Vector2(lane[0]) + Vector2(lane[1]) * 350.0)
	_ok("④ 往航线上再加一人 → 最优覆盖数 +1(判据真的在数人, 不是碰巧)",
		int(EqGunBatch.best_lane(pts2)[2]) == 4, "现在 %d 人" % int(EqGunBatch.best_lane(pts2)[2]))
	# 120 宽是硬边: 把一个人挪到 70 码横向偏移(>60 半宽)就不该算
	var pts3: Array = [base + Vector2(-300.0, 0.0), base, base + Vector2(300.0, 70.0)]
	_ok("④ 带宽 120(半宽 60): 横向偏 70 码的人不算进这条水平带",
		EqGunBatch.lane_cover(base, Vector2.RIGHT, pts3) == 2,
		"数到 %d 人" % EqGunBatch.lane_cover(base, Vector2.RIGHT, pts3))
	_ok("④ 带长 800(半长 400): 沿线 450 码外的人不算",
		EqGunBatch.lane_cover(base, Vector2.RIGHT, [base + Vector2(450.0, 0.0)]) == 0)
	# 投弹枚数与航线长度/间距的同一性(两个常量必须自洽)
	_ok("④ 投弹枚数与 800 码航线 / 160 码间距自洽: (n−1)×间距 = 800",
		_near(float(EqGunBatch.bomb_count() - 1) * EqGunBatch.BOMB_SPACING, EqGunBatch.BOMB_LANE_LEN),
		"n=%d" % EqGunBatch.bomb_count())


func _t080_bomb() -> void:
	print("── ④ 080 炸弹: 落点 180 码内 0.8/1.1/1.5ATK 物理 + 40/70/120 魔法 ──")
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u, "p2eq_080", 1)
	_spawn_all()
	_pin(u, 200.0)
	var at: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var inn: Dictionary = _mk("fortune", "right", at - (_s.ARENA.position + _s.ARENA.size * 0.5) + Vector2(100.0, 0.0), 100000.0)
	inn["pos"] = at + Vector2(100.0, 0.0)
	var out: Dictionary = _mk("fortune", "right", Vector2(400.0, 0.0), 100000.0)
	out["pos"] = at + Vector2(300.0, 0.0)
	var h: Dictionary = _gun._helis[0]
	var i0: float = float(inn["hp"])
	var o0: float = float(out["hp"])
	var n: int = _gun.heli_bomb_hit(h, 0, at)
	_ok("④ ★分母: 一枚炸弹命中了 1 个人(180 码内那个)", n == 1, "命中 %d 人" % n)
	_ok("④ 1★ 一枚 = 0.8×200 物理 + 40 魔法 = 200", _near(i0 - float(inn["hp"]), 200.0, 0.6),
		"实打 %.1f" % (i0 - float(inn["hp"])))
	_ok("④ 180 码外(300 码)不吃伤", _near(o0 - float(out["hp"]), 0.0, 0.01),
		"实打 %.1f" % (o0 - float(out["hp"])))
	var i1: float = float(inn["hp"])
	_gun.heli_bomb_hit(h, 2, at)
	_ok("④ 3★ 一枚 = 1.5×200 物理 + 120 魔法 = 420", _near(i1 - float(inn["hp"]), 420.0, 0.6),
		"实打 %.1f" % (i1 - float(inn["hp"])))
	# 炸弹也计入金弹计数 ⇒ 走的是同一个 _queue_shots 出口
	var src: String = _strip("res://scripts/systems/equip/eq_gun_batch.gd")
	var qn := 0
	for ln in src.split("\n"):
		if ln.contains("_queue_shots(") and ln.contains("p2eq_080"):
			qn += 1
	_ok("④ 机炮与炸弹都从 _queue_shots(gun_id=p2eq_080) 出去 ⇒ 两者都计入金弹计数",
		qn == 2, "找到 %d 处" % qn)


func _t080_crash() -> void:
	print("── ④ 080 坠机: 携带者阵亡后继续飞 10 秒 → 撞敌方随机单位 → 500 码内 200/300/500 物理 + 40 层灼烧 ──")
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(u, "p2eq_080", 2)
	_spawn_all()
	_pin(u, 200.0)
	var foe: Dictionary = _mk("fortune", "right", Vector2(-100.0, 0.0), 100000.0)
	var far: Dictionary = _mk("fortune", "right", Vector2(500.0, 0.0), 100000.0)
	var h: Dictionary = _gun._helis[0]
	u["alive"] = false
	_s._equip_sys._eq_on_death(u, null)
	_ok("④ 携带者阵亡 → 直升机进入 10 秒倒计时(state=doom)",
		str(h.get("state", "")) == "doom", "state=%s" % str(h.get("state", "")))
	_gun.tick(9.5)
	_ok("④ 9.5 秒时还没开始坠落", str(h.get("state", "")) == "doom", "state=%s" % str(h.get("state", "")))
	_ok("④ 倒计时按真实秒数走(9.5 秒就是 9.5)", _near(float(h.get("doom_t", 0.0)), 9.5, 0.01),
		"doom_t=%.2f" % float(h.get("doom_t", 0.0)))
	_s._battle_rng.seed = SEED
	_gun.tick(0.6)
	_ok("④ 10 秒到 → 开始坠向敌方随机单位", str(h.get("state", "")) in ["crash", "dead"],
		"state=%s" % str(h.get("state", "")))
	# 随机走播种 RNG: 同种子重跑必须选到同一个目标
	var first_to: Vector2 = Vector2(h.get("crash_to", Vector2.ZERO))
	var h2: Dictionary = {"owner": u, "si": 1, "pos": Vector2(h["pos"]), "state": "doom", "crash_to": Vector2.ZERO}
	_s._battle_rng.seed = SEED
	_gun._heli_begin_crash(h2)
	_ok("④ ★随机走 battle._battle_rng: 同种子重跑选到同一个坠机目标",
		Vector2(h2["crash_to"]).is_equal_approx(first_to),
		"%s vs %s" % [str(first_to), str(h2["crash_to"])])
	# 爆炸: 直接调结算(★不等演出飞完, CLAUDE.md §3.5)
	var at: Vector2 = Vector2(foe["pos"])
	far["pos"] = at + Vector2(700.0, 0.0)
	var hh: Dictionary = {"owner": u, "si": 1, "pos": at, "crash_phys": 300.0, "crash_burn": 40}
	var f0: float = float(foe["hp"])
	var g0: float = float(far["hp"])
	var n: int = _gun.heli_crash_explode(hh)
	_ok("④ ★分母: 爆炸只覆盖到 1 个人(500 码内那个)", n == 1, "覆盖 %d 人" % n)
	_ok("④ 2★ 坠机爆炸 300 物理", _near(f0 - float(foe["hp"]), 300.0, 0.6),
		"实打 %.1f" % (f0 - float(foe["hp"])))
	_ok("④ 施加 40 层灼烧", int((foe.get("dot_stacks", {}) as Dictionary).get("burn", 0)) == 40,
		"burn=%d" % int((foe.get("dot_stacks", {}) as Dictionary).get("burn", 0)))
	_ok("④ 500 码外(700 码)既不吃伤也不吃灼烧",
		_near(g0 - float(far["hp"]), 0.0, 0.01)
		and int((far.get("dot_stacks", {}) as Dictionary).get("burn", 0)) == 0)
	# 各星级的爆炸伤害: on_death 就近声明的 [200,300,500]
	var phys: Array = []
	for si in range(3):
		_reset()
		var uu: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
		_equip(uu, "p2eq_080", si + 1)
		_spawn_all()
		uu["alive"] = false
		_s._equip_sys._eq_on_death(uu, null)
		phys.append(float((_gun._helis[0] as Dictionary).get("crash_phys", -1.0)))
	_ok("④ 坠机物理伤害 200/300/500", phys == [200.0, 300.0, 500.0], str(phys))
	# ★携带者【在轰炸途中】阵亡: 不打断这一轮航线, 但 10 秒窗口照走(不被技能节拍拖长)
	_reset()
	var ub: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	_equip(ub, "p2eq_080", 1)
	_spawn_all()
	_mk("fortune", "right", Vector2(-100.0, 0.0))
	var hb: Dictionary = _gun._helis[0]
	hb["energy"] = 100.0
	_gun._heli_begin_bomb(hb)
	# ★进场那一步(2026-08-07 加, 修"瞬移到航线起点")先喂完 —— 本节验的是**航线不被打断**,
	#   不是进场本身; 进场有 tests/verify_heli_approach.gd 单独守。
	var _ab := 0
	while str(hb.get("state", "")) == "approach" and _ab < 400:
		_gun._heli_approach(hb, 0.02)
		_ab += 1
	_ok("④ ★分母: 直升机确实在跑轰炸航线", str(hb.get("state", "")) == "bomb",
		"state=%s" % str(hb.get("state", "")))
	ub["alive"] = false
	_s._equip_sys._eq_on_death(ub, null)
	_ok("④ 携带者在轰炸途中阵亡 → 不打断这一轮航线", str(hb.get("state", "")) == "bomb",
		"state=%s" % str(hb.get("state", "")))
	_gun.tick(0.8)
	_ok("④ 10 秒窗口【不看 state】: 轰炸期间倒计时照走(不被技能节拍拖长)",
		_near(float(hb.get("doom_t", 0.0)), 0.8, 0.02), "doom_t=%.2f" % float(hb.get("doom_t", 0.0)))


# ═════════════════════════════════════════════════════════════
# ⑤ 演出层: 五个物理模型的可验证性质
# ═════════════════════════════════════════════════════════════
func _t_vfx_models() -> void:
	print("── ⑤ 演出物理模型(不是「我调得像」, 是闭式解的可验证性质) ──")
	# ① 自由落体: t ∝ √h ⇒ t(4h)/t(h) ≡ 2; 前置量与速度严格成正比(悬停时为 0)
	var r: float = GunEqVfx.bomb_fall_time(880.0) / GunEqVfx.bomb_fall_time(220.0)
	_ok("⑤① 落弹时间 t(4h)/t(h) ≡ 2(√ 关系; 匀速下落会给 4)", _near(r, 2.0, 1e-6), "比值 %.9f" % r)
	_ok("⑤① 悬停(v=0)时投弹前置量恰为 0", _near(GunEqVfx.bomb_lead(0.0, 220.0), 0.0, 1e-9))
	_ok("⑤① 前置量与速度严格成正比: lead(2v) = 2·lead(v)",
		_near(GunEqVfx.bomb_lead(600.0, 220.0), 2.0 * GunEqVfx.bomb_lead(300.0, 220.0), 1e-6),
		"%.3f vs %.3f" % [GunEqVfx.bomb_lead(600.0, 220.0), GunEqVfx.bomb_lead(300.0, 220.0)])
	# ② 旋翼相位: 帧率无关
	var p1: float = GunEqVfx.rotor_phase(0.0, 26.0, 1.0)
	var p2: float = 0.0
	for _i in range(1000):
		p2 = GunEqVfx.rotor_phase(p2, 26.0, 0.001)
	_ok("⑤② 旋翼相位帧率无关: 1 步 vs 1000 步走同样 1 秒, 末相位相等",
		_near(p1, p2, 1e-4), "%.6f vs %.6f" % [p1, p2])
	_ok("⑤② ★分母: 这一秒确实转过了(相位非 0)", absf(p1) > 0.001, "phase=%.4f" % p1)
	# ③ 锥形散布: 面积均匀 ⇒ R/2 内占 1/4
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var inside := 0
	var N := 4000
	for _i in range(N):
		if GunEqVfx.cone_r(rng.randf(), 400.0) <= 200.0:
			inside += 1
	var frac: float = float(inside) / float(N)
	_ok("⑤③ ★分母: 抽了 %d 个样本" % N, N == 4000)
	_ok("⑤③ 面积均匀散布: 半径 R/2 以内占 1/4(半径均匀会给 1/2)",
		absf(frac - 0.25) < 0.02, "实测 %.4f" % frac)
	_ok("⑤③ 它离 0.25 比离 0.5 近得多(两种分布确实分得开)",
		absf(frac - 0.25) < absf(frac - 0.5))
	# ④ 闪电分形: 自仿射 H=1/2 ⇒ 逐级比 √2; 端点精确
	var ratios_ok := true
	for k in range(1, 6):
		if not _near(GunEqVfx.arc_sigma(k, 400.0) / GunEqVfx.arc_sigma(k + 1, 400.0), sqrt(2.0), 1e-9):
			ratios_ok = false
	_ok("⑤④ 中点位移分形自仿射: σ(k)/σ(k+1) ≡ √2 (H=1/2 布朗轨迹)", ratios_ok,
		"σ1=%.4f σ2=%.4f" % [GunEqVfx.arc_sigma(1, 400.0), GunEqVfx.arc_sigma(2, 400.0)])
	var a2 := Vector2(100.0, 200.0)
	var b2 := Vector2(500.0, 260.0)
	rng.seed = SEED
	var pts: Array = GunEqVfx.arc_points(a2, b2, 4, rng)
	_ok("⑤④ 4 级细分 ⇒ 2⁴+1 = 17 个点", pts.size() == 17, "%d 个点" % pts.size())
	_ok("⑤④ 端点【精确】落在两个目标身上(电弧不漂)",
		Vector2(pts[0]).is_equal_approx(a2) and Vector2(pts[pts.size() - 1]).is_equal_approx(b2))
	# ⑤ 悬链线: 弧长恒等式 + 垂度与跨度成正比
	var span := 400.0
	var a_par: float = GunEqVfx.catenary_a(span)
	var L: float = GunEqVfx.catenary_len(span, a_par)
	_ok("⑤⑤ 悬链线参数满足弧长恒等式 2a·sinh(s/2a) = 1.15·s",
		_near(L, 1.15 * span, 0.02), "L=%.4f 期望 %.4f" % [L, 1.15 * span])
	var s1: float = GunEqVfx.catenary_sag(400.0)
	var s2: float = GunEqVfx.catenary_sag(800.0)
	_ok("⑤⑤ 垂度与跨度严格成正比: sag(2s)/sag(s) ≡ 2", _near(s2 / maxf(0.001, s1), 2.0, 1e-4),
		"%.4f / %.4f = %.6f" % [s2, s1, s2 / maxf(0.001, s1)])
	_ok("⑤⑤ ★分母: 垂度不是 0(绳真的松着)", s1 > 1.0, "sag=%.3f" % s1)
	_ok("⑤⑤ 端点垂度为 0, 中点垂度 = sag",
		_near(GunEqVfx.catenary_drop(span, 0.0), 0.0, 1e-4)
		and _near(GunEqVfx.catenary_drop(span, 0.5), s1, 1e-4))
	# ⑥ 金弹辉光 ≡ 该档真伤比例, 且与羁绊源码里那张表逐档相等
	_ok("⑥ 金弹辉光强度 ≡ 真伤比例(一个数两处用)",
		_near(GunEqVfx.gold_glow(0.8), 0.8, 1e-9) and _near(GunEqVfx.gold_glow(1.0), 1.0, 1e-9))
	var rb: String = _strip("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var qbody: String = _fn_body(rb, "func _queue_shots")
	_ok("⑥ ★分母: _queue_shots 的函数体读得到", qbody.length() > 200, "len=%d" % qbody.length())
	_ok("⑥ 我文案/演出用的 60/80/100% 与羁绊源码里那张表逐档相同",
		qbody.contains("[0.60, 0.80, 1.00]"), "羁绊表: %s" % ("在" if qbody.contains("0.60") else "找不到"))
	_ok("⑥ 金弹门槛 4/3/2 也与羁绊源码一致(079 的充能条读它)",
		qbody.contains("[4, 3, 2]"))


func _t_vfx_nodes() -> void:
	print("── ⑤ 演出层: 真的显示进 _world + 生命周期自己推进(不靠 tween) ──")
	var vf = _gun.vfx
	vf.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var before: int = _s._world.get_child_count()
	vf.tracer(c, c + Vector2(300.0, 0.0), Color.WHITE, 1.0)
	vf.blast(c, 300.0, Color.ORANGE)
	var n_cone: int = vf.cone_blast(c, Vector2.RIGHT, 400.0, 30.0, Color.WHITE, 0.0, 8)
	var n_arc: int = vf.chain_arc(c, c + Vector2(200.0, 100.0), Color.SKY_BLUE)
	var n_heal: int = vf.heal_beam(c, c + Vector2(300.0, 0.0), Color.GREEN, true)
	_ok("⑤N ★分母: 锥形/电弧/治疗束都真的生成了段数",
		n_cone == 8 and n_arc == 17 and n_heal == 10, "cone=%d arc=%d heal=%d" % [n_cone, n_arc, n_heal])
	_ok("⑤N 演出节点【真的挂进 battle._world】(不是只算了个数)",
		_s._world.get_child_count() > before, "world 子节点 %d → %d" % [before, _s._world.get_child_count()])
	var live: int = vf.alive_count()
	_ok("⑤N ★分母: 现存演出节点 %d 个" % live, live > 20)
	vf.tick(2.0)                    # 所有瞬时效果寿命都 < 2 秒
	_ok("⑤N 喂 2 秒 delta → 瞬时演出全部自行退场(★不靠 tween, 无头也稳)",
		vf.alive_count() == 0, "还剩 %d 个" % vf.alive_count())
	# 直升机机体是长驻节点: spawn → update → free
	var h: Dictionary = {"pos": c, "energy": 50.0, "rotor": 0.0}
	vf.heli_spawn(h)
	_ok("⑤N 直升机机体建出来了(机身/旋翼/龟能条)",
		h.get("node", null) != null and is_instance_valid(h["node"]))
	vf.heli_update(h, 0.1)
	_ok("⑤N heli_update 推进了旋翼相位", float(h.get("rotor", 0.0)) > 0.0, "rotor=%.3f" % float(h["rotor"]))
	vf.heli_free(h)
	_ok("⑤N heli_free 拔掉机体", h.get("node", null) == null)
	vf.clear()


# ═════════════════════════════════════════════════════════════
# ⑥ 换路撤场
# ═════════════════════════════════════════════════════════════
func _t_clear() -> void:
	print("── ⑥ 换路撤场: 三种常驻物 + 演出全部拔掉(漏了就带进下一路) ──")
	_reset()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0))
	u["equips"] = [{"id": "p2eq_077", "star": 3}, {"id": "p2eq_079", "star": 3},
		{"id": "p2eq_080", "star": 3}]
	u["eq_state"] = {}
	_spawn_all()
	_ok("⑥ ★分母: 一只龟同带三件 → 小手枪 1 + 炮台 1 + 直升机 1 都登场了",
		_gun._pistols.size() == 1 and _gun._towers.size() == 1 and _gun._helis.size() == 1,
		"pistol=%d tower=%d heli=%d" % [_gun._pistols.size(), _gun._towers.size(), _gun._helis.size()])
	var heli_node = (_gun._helis[0] as Dictionary).get("node", null)
	_ok("⑥ ★分母: 直升机的演出节点真的建出来了", heli_node != null and is_instance_valid(heli_node))
	_gun.clear_all()
	_ok("⑥ clear_all 后三张登记表都空了",
		_gun._pistols.is_empty() and _gun._towers.is_empty() and _gun._helis.is_empty(),
		"pistol=%d tower=%d heli=%d" % [_gun._pistols.size(), _gun._towers.size(), _gun._helis.size()])
	_ok("⑥ 直升机的节点被拔掉(它不是单位, 换路重建单位表清不掉它)",
		heli_node == null or not is_instance_valid(heli_node) or (heli_node as Node).is_queued_for_deletion())
	_ok("⑥ 演出层也清空了", _gun.vfx.alive_count() == 0, "还剩 %d 个" % _gun.vfx.alive_count())
