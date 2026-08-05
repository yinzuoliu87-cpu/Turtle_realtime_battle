extends Node
## verify_hp_lines.gd — 【多条血线阈值】基建（2026-08-05）
##
## 069 珊瑚糖糕要三道线(80/55/30%)、064 溺者的浮囊要一道(35%)。
## 既有的 `_eq_check_hp_threshold` 是**写死一条 50% 线**的, 再往里塞 hpXX_fired 标记就是灾难。
##
## 守六条:
##   ⓪ 分母: _hpl 真的在
##   ① 跌破才触发, 没跌破不触发
##   ② ★同一条线只触发一次(不会每帧重复)
##   ③ ★★一次掉血跌穿多条线 ⇒ 按【从高到低】顺序【全部】触发
##      —— 069 明确要求"掉血够快会一口气吃完三块"
##   ④ 回血再掉下去, 已触发的线【不】再触发(是"首次"不是"每次")
##   ⑤ ★clear_all() 后重新可触发 —— 这就是用户定的「每路一次」口径
##   ⑥ ★两处接线都在: battle_damage.gd 调 check、dual_lane_flow.gd 调 clear_all

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond: print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _dummy() -> Dictionary:
	var o := Vector2(_s.ARENA.position.x + 200.0, _s.ARENA.position.y + 200.0)
	var u: Dictionary = _s._spawn._make_unit("basic", "left", o)
	u["alive"] = true; u["hp"] = 1000.0; u["maxHp"] = 1000.0
	_s._units.append(u)
	return u


func _ready() -> void:
	await get_tree().process_frame
	print("=== 多条血线阈值基建 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	if _s == null:
		print("  [FAIL] ⓪ 战场没起来"); print("FAIL x1"); get_tree().quit(1); return
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s._units.clear()
	var hl = _s._hpl
	_ok("⓪ ★分母: _hpl 在", hl != null)
	if hl == null: print("FAIL x1"); get_tree().quit(1); return

	# ── ①② 跌破才触发, 且只触发一次 ──
	var log1: Array = []
	var u1 := _dummy()
	hl.add(u1, "a", 0.5, func(_u, k): log1.append(k))
	u1["hp"] = 600.0; hl.check(u1)
	_ok("① ★没跌破(60%% > 50%%)不触发(实测 %d 次)" % log1.size(), log1.is_empty())
	u1["hp"] = 400.0; hl.check(u1)
	_ok("①b ★跌破(40%% < 50%%)触发一次(实测 %d 次)" % log1.size(), log1.size() == 1)
	hl.check(u1); hl.check(u1); hl.check(u1)
	_ok("② ★再查三次不重复触发(实测累计 %d 次)" % log1.size(), log1.size() == 1,
		"每帧都会调 check, 重复触发 = 一块糕吃无数次")

	# ── ③ 一次跌穿三条线 → 按高到低全部触发 ──
	var log2: Array = []
	var u2 := _dummy()
	hl.add(u2, "L80", 0.80, func(_u, k): log2.append(k))
	hl.add(u2, "L55", 0.55, func(_u, k): log2.append(k))
	hl.add(u2, "L30", 0.30, func(_u, k): log2.append(k))
	u2["hp"] = 200.0                                  # 一次从 100% 掉到 20%, 跌穿全部三条
	hl.check(u2)
	_ok("③ ★★一次跌穿三条线 ⇒ 全部触发(实测 %d 条: %s)" % [log2.size(), str(log2)],
		log2.size() == 3, "069 要求「掉血够快会一口气吃完三块」")
	_ok("③b ★★触发顺序是【从高到低】(实测 %s)" % str(log2),
		log2 == ["L80", "L55", "L30"], "顺序不确定 ⇒ 门禁没法验、玩家看到的吃糕顺序也会乱")

	# ── ④ 回血再掉, 不重复 ──
	var log3: Array = []
	var u3 := _dummy()
	hl.add(u3, "x", 0.5, func(_u, k): log3.append(k))
	u3["hp"] = 400.0; hl.check(u3)
	u3["hp"] = 900.0; hl.check(u3)
	u3["hp"] = 100.0; hl.check(u3)
	_ok("④ ★回血再掉下去不重复触发(实测 %d 次) —— 是「首次」不是「每次」" % log3.size(),
		log3.size() == 1)

	# ── ⑤ clear_all 后可再触发(每路一次) ──
	var log4: Array = []
	var u4 := _dummy()
	hl.add(u4, "y", 0.5, func(_u, k): log4.append(k))
	u4["hp"] = 400.0; hl.check(u4)
	var before: int = log4.size()
	hl.clear_all()
	hl.add(u4, "y", 0.5, func(_u, k): log4.append(k))
	hl.check(u4)
	_ok("⑤ ★clear_all() 后重新注册可再触发(前 %d → 后 %d) = 「每路一次」" % [before, log4.size()],
		before == 1 and log4.size() == 2)

	# ── ⑥ ★接线要【走真实伤害路径】验, 不能扫源码字符串 ──
	# 我第一版写的是 `sd.contains("_hpl.check(")`, 结果反向验证时把调用改成
	# `pass  # battle._hpl.check(u)` —— **字符串还在注释里**, 断言照样绿。
	# 这就是「断言函数存在守不住还有没有人调」。改成真的打一拳看回调响不响。
	var log5: Array = []
	var u5 := _dummy()
	u5["def"] = 0.0; u5["mr"] = 0.0; u5["shield"] = 0.0; u5["flat_dr"] = 0.0
	_s._hpl.add(u5, "wire", 0.5, func(_u, k): log5.append(k))
	_s._damage._apply_damage(u5, 700, Color(1, 1, 1))     # 1000 → 300 血, 跌破 50%
	_ok("⑥ ★★接线: 走真实 _apply_damage(DoT/真伤路) 打掉 70%% 血, 血线回调真的响了(实测 %d 次)" % log5.size(),
		log5.size() == 1,
		"没响 = battle_damage.gd 里那句 _hpl.check(u) 没在跑(注释掉/删了也照样'存在'于源码)")
	# ⑥c ★★另一条伤害路径也要能触发(§3.3 —— 我第一版只接了一条, 自己踩了这个坑)
	var log6: Array = []
	var u6 := _dummy()
	u6["def"] = 0.0; u6["mr"] = 0.0; u6["shield"] = 0.0; u6["flat_dr"] = 0.0
	u6["dodge"] = 0.0
	var atk6 := _dummy()
	atk6["side"] = "right"
	_s._hpl.add(u6, "wire2", 0.5, func(_u, k): log6.append(k))
	_s._damage._apply_damage_from(atk6, u6, 700, Color(1, 1, 1), 0.0, false, true, false, true)
	_ok("⑥c ★★另一条路径(_apply_damage_from 普攻/技能路)也触发(实测 %d 次)" % log6.size(),
		log6.size() == 1,
		"§3.3: 两条伤害路径各自扣血, 只接一条 = 只有某类伤害才触发")
	var sl: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd")
	_ok("⑥b ★换路清场接线在(dual_lane_flow 调 _hpl.clear_all)",
		sl.contains("_hpl.clear_all("),
		"没接 = 换路后一辈子不再触发")

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 多条血线阈值" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
