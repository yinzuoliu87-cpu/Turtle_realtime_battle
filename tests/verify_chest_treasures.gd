extends Node
## verify_chest_treasures.gd — 宝箱龟 15 件战利品【逐件过一遍】(2026-08-14)
##
## ★★★由来: 变异探针实测 `chest_system._sk_chest_storm`(146 行)**打瘸了全套一条不红**
##   —— 宝箱龟是**裸奔**的。而 15 件战利品里有 **7 件是「置 flag + 别处钩子读」**的间接实装:
##   朗姆酒/锁链/石头/火石/毒箭/雷刃/星辉/凤凰雕像。
##   **这类最容易变成死件** —— flag 写了但没人读, 正是今晚反复踩的那个形状
##   (香火"写进去了没人读"、凤凰"接了 A 钩子而消费者在 B 钩子")。
##
## ★所以本条的核心不是"数值对不对", 是【每一件的效果真的落到了产品状态上】。
##   判据一律量产品自己的账: 属性字段 / 血量 / DoT 层数 / 减伤标记 / eq_state。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Chest := preload("res://scripts/systems/skills/chest_system.gd")

## 池子里全部 15 件 —— 从产品常量取, 不手抄(手抄的副本必然落后)
var _pool_all: Array = []

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _mk(s, at: Vector2) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit("chest", "left", at)
	u["atk"] = 100.0
	u["maxHp"] = 1000.0
	u["hp"] = 500.0
	u["no_basic"] = true
	u["no_move"] = true
	u["chest_treasures"] = {}
	return u


func _ready() -> void:
	await get_tree().process_frame
	print("=== 宝箱龟 15 件战利品 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var cs = s._chest_sys

	for g in ["basic", "adv", "legend"]:
		for tid in s._CHEST_TREASURE_POOL.get(g, []):
			_pool_all.append(str(tid))
	_ok("★分母: 战利品池共 %d 件(基础6+进阶6+传说3)" % _pool_all.size(),
		_pool_all.size() == 15, "实得 %d" % _pool_all.size())
	## ★2026-08-25 文案根除: 图鉴文案现在写 `{C:ChestSystem.TREASURE_TOTAL}` 件。
	##   那个常量不能是第二份手抄 —— 这条断言把它焊在【真实池子件数】上,
	##   池子增删一件而常量没跟, 这里当场红。
	_ok("★TREASURE_TOTAL(%d) == 真实池子件数(%d) —— 文案引用的就是它"
		% [Chest.TREASURE_TOTAL, _pool_all.size()],
		Chest.TREASURE_TOTAL == _pool_all.size())

	# ── ① 每一件都【真的改变了产品状态】────────────────────────────────────
	##   ★宽判据在这里是合适的: 我要抓的是"死件"(什么都没发生), 不是数值对不对。
	##     数值单独在 ② 逐条精确验。
	var dead: Array = []
	for tid in _pool_all:
		var u: Dictionary = _mk(s, c + Vector2(-200, 0))
		s._units.clear()
		s._units.append(u)
		s._edit_mode = false
		s._over = false
		var before: String = str([u.get("atk"), u.get("def"), u.get("mr"), u.get("crit"),
			u.get("crit_dmg"), u.get("lifesteal"), u.get("maxHp"),
			u.get("chest_rum_t"), u.get("chest_aoe_mult"), u.get("chest_rock_bonus"),
			u.get("_chest_revive"), u.get("chest_starlight")])
		cs._chest_apply_treasure(u, tid)
		var after: String = str([u.get("atk"), u.get("def"), u.get("mr"), u.get("crit"),
			u.get("crit_dmg"), u.get("lifesteal"), u.get("maxHp"),
			u.get("chest_rum_t"), u.get("chest_aoe_mult"), u.get("chest_rock_bonus"),
			u.get("_chest_revive"), u.get("chest_starlight")])
		var owned: bool = (u.get("chest_treasures", {}) as Dictionary).has(tid)
		## flint / poison / thunder 是纯 on-hit 钩子, 应用时本来就不改属性 ⇒ 只验登记。
		var hookonly: bool = tid in ["flint", "poison", "thunder"]
		var ok: bool = owned and (hookonly or after != before)
		if not ok:
			dead.append(tid)
		_ok("%-16s %s" % [tid, "已登记 + 钩子件(不改属性)" if hookonly else "已登记 + 改变了产品状态"],
			ok, "登记=%s 状态变了=%s" % [str(owned), str(after != before)])
	_ok("★★【什么都没发生】的死件: %d 件" % dead.size(), dead.is_empty(), "死件: %s" % str(dead))

	# ── ② 本轮调整的五个数值(用户 2026-08-14)──────────────────────────────
	_ok("★朗姆酒 每秒回 0.5%%", absf(Chest.RUM_HEAL_PCT - 0.005) < 1e-9,
		"实得 %.4f" % Chest.RUM_HEAL_PCT)
	_ok("★宝石甲 +500 最大生命", absf(Chest.GEM_HP - 500.0) < 1e-6, "实得 %.0f" % Chest.GEM_HP)
	_ok("★火石 0.05×ATK 层灼烧", absf(Chest.FLINT_BURN_COEF - 0.05) < 1e-9,
		"实得 %.3f" % Chest.FLINT_BURN_COEF)
	var src_dmg := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_damage.gd")
	_ok("★★星辉【只有普攻与技能】转真实(装备段不再白嫖穿甲)",
		src_dmg.find('src.get("chest_starlight", false) and not from_equip') >= 0)
	_ok("★★雷刃【只有普攻与技能】命中才叠层",
		src_dmg.find('_cht.has("thunder") and not from_equip') >= 0)

	# ── ③ 宝石甲的 +500 真的加到了血上(不是只改常量)──────────────────────
	var ug: Dictionary = _mk(s, c + Vector2(-260, 0))
	var hp0: float = float(ug["maxHp"])
	cs._chest_apply_treasure(ug, "gem_armor")
	_ok("★★宝石甲实测: 最大生命 %.0f → %.0f(+%.0f)" % [hp0, float(ug["maxHp"]), float(ug["maxHp"]) - hp0],
		absf(float(ug["maxHp"]) - hp0 - Chest.GEM_HP) < 0.01)

	# ── ④ 火石的钩子【真的有人读】(不是写了 flag 没人用)────────────────────
	##   ★这正是"7 件间接实装最容易变死件"要守的那条。
	var uf: Dictionary = _mk(s, c + Vector2(-200, 0))
	cs._chest_apply_treasure(uf, "flint")
	var ef: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	ef["maxHp"] = 1.0e7
	ef["hp"] = 1.0e7
	ef["no_basic"] = true
	ef["no_move"] = true
	s._units.clear()
	s._units.append_array([uf, ef])
	var burn0: int = int((ef.get("dot_stacks", {}) as Dictionary).get("burn", 0))
	s._damage._apply_damage_from(uf, ef, 100, Color.RED)
	var burn1: int = int((ef.get("dot_stacks", {}) as Dictionary).get("burn", 0))
	## ★★判据必须是【精确层数】不能只是"着火了" —— 反向验证时把系数改成 0,
	##   `maxi(1, roundi(atk*0))` 仍会上 **1 层**, "着火了"照样成立 ⇒ 抓不到。
	##   这是今晚第 N 次同一形状: 判据选在错的层。
	var want_burn: int = maxi(1, roundi(float(uf["atk"]) * Chest.FLINT_BURN_COEF))
	_ok("★★★火石: 命中后目标着火【正好 %d 层】(= 0.05×ATK, 钩子有人读)" % want_burn,
		burn1 - burn0 == want_burn,
		"灼烧 %d → %d(增 %d, 应 %d)" % [burn0, burn1, burn1 - burn0, want_burn])
	## 反面: 装备触发的段(from_equip)不该叠雷刃 —— 顺带验 ⑤ 的收窄真的生效
	var ut: Dictionary = _mk(s, c + Vector2(-200, 0))
	cs._chest_apply_treasure(ut, "thunder")
	s._units.clear()
	s._units.append_array([ut, ef])
	var st0: int = int(battle_stacks(s, ef))
	s._damage._apply_damage_from(ut, ef, 100, Color.RED, 0.0, false, true)   # from_equip = true
	_ok("★★反面: 装备触发的段【不叠】雷刃层", int(battle_stacks(s, ef)) == st0,
		"层数 %d → %d" % [st0, int(battle_stacks(s, ef))])
	s._damage._apply_damage_from(ut, ef, 100, Color.RED)                      # 普攻/技能
	_ok("★★普攻/技能命中【会叠】雷刃层", int(battle_stacks(s, ef)) > st0,
		"层数 %d → %d" % [st0, int(battle_stacks(s, ef))])

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 宝箱龟战利品")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()


func battle_stacks(s, u: Dictionary) -> int:
	var st = u.get("stacks", {})
	if st is Dictionary:
		return int((st as Dictionary).get("chest_thunder", 0))
	return 0
