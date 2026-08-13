extends Node
## verify_phoenix_flame_onhit.gd — 凤凰喷火: 每跳只给【最近的一个】走 on-hit（用户 2026-08-13）
##
## 用户原话:「火焰每0.5跳的时候给最近的onhit, 比如触发竹叶装备」。
## ★由来: 喷火走的是**范围结算**, 一次都不碰 on-hit 钩子 ⇒ 竹弓/金弹/腐蚀这类
##   "命中时触发"的装备在凤凰身上完全不生效。
## ★判据两条, 缺一条都守不住:
##   ① 扇形里三个敌人**都吃到了伤害**(分母 —— 否则下一条可能只是"没人被打到")
##   ② 但**只有最近的那个**触发 on-hit(不是每人一次 —— 那会让装备特效翻几倍)

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	print("=== 凤凰喷火 on-hit ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("phoenix", "left", c + Vector2(-100, 0))
	u["atk"] = 100.0
	u["phx_aim"] = 0.0                       # 锥朝 +x
	# 三个敌人排在锥内, 由近到远
	var es: Array = []
	for i in range(3):
		var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(60.0 + 90.0 * float(i), 0))
		e["maxHp"] = 1.0e7
		e["hp"] = 1.0e7
		es.append(e)
	s._units.clear()
	s._units.append(u)
	s._units.append_array(es)

	var hp0: Array = []
	for e in es:
		hp0.append(float(e["hp"]))
	u["_phx_onhit_n"] = 0
	s._phoenix_sys._phoenix_flame_cone(u, es[0])

	var hurt := 0
	for i in range(es.size()):
		if float(es[i]["hp"]) < hp0[i] - 0.01:
			hurt += 1
	_ok("★分母: 扇形里三个敌人都吃到了喷火伤害", hurt == 3, "实得 %d 个" % hurt)
	_ok("★★这一跳只触发了【一次】on-hit(不是每人一次)",
		int(u.get("_phx_onhit_n", -1)) == 1, "实得 %d 次" % int(u.get("_phx_onhit_n", -1)))
	# 最近的那个: 把最近的挪到最远, 再跳一次 —— 触发对象应当跟着换
	es[0]["pos"] = c + Vector2(600.0, 0)
	u["_phx_onhit_n"] = 0
	s._phoenix_sys._phoenix_flame_cone(u, es[1])
	_ok("★挪走最近的之后仍然只触发一次(选的是当下最近的那个)",
		int(u.get("_phx_onhit_n", -1)) == 1, "实得 %d 次" % int(u.get("_phx_onhit_n", -1)))
	# 反面: 锥里一个人都没有 ⇒ 一次都不触发
	for e2 in es:
		(e2 as Dictionary)["pos"] = c + Vector2(-800.0, 0)   # 全挪到背后
	u["_phx_onhit_n"] = 0
	s._phoenix_sys._phoenix_flame_cone(u, es[0])
	_ok("★反面: 锥里没人 ⇒ 一次都不触发(不是恒触发)",
		int(u.get("_phx_onhit_n", -1)) == 0, "实得 %d 次" % int(u.get("_phx_onhit_n", -1)))
	## ★★走的必须是【普攻】那条 on-hit(用户:「我的意思就是触发普攻的 onhit」)——
	##   凤凰的喷火就是它的普攻, 只有 basic=true 才会推进"每第 N 次普攻"那类计数器,
	##   竹叶这类只认普攻的装备才吃得到。第一版写的 false, 它们照样不触发。
	var src_px: String = FileAccess.get_file_as_string("res://scripts/systems/skills/phoenix_system.gd")
	_ok("★★喷火的 on-hit 按【普攻】算(basic=true)",
		src_px.find("_eq_on_hit(u, nearest, roundi(mag), true)") >= 0)

	# ══ 涅槃: 2.5 秒演出, 到点才结算(用户 2026-08-13) ═══════════════════════
	#   原来是**一帧完成**: 血条瞬间跳满、灼烧同帧施加 ⇒ 玩家眼里"死了又突然站着"。
	#   ★判据必须落在【时间轴】上: 只断言"最后复活了"守不住 —— 一帧复活也满足。
	var pu: Dictionary = s._spawn._make_unit("phoenix", "left", c + Vector2(-300, 0))
	pu["maxHp"] = 1000.0
	pu["hp"] = 1000.0
	pu["atk"] = 100.0
	var pe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(-200, 0))
	pe["maxHp"] = 1.0e7
	pe["hp"] = 1.0e7
	s._units.clear()
	s._units.append_array([pu, pe])
	## ★关掉编辑模式: 2026-08-13 起「摆位/编辑模式不推进战斗」那道闸也门着 _pending_shots,
	##   不关的话涅槃的 2.5 秒定时永远不到点(今天已在 arcane/gun 两个门禁踩过同一条)。
	s._edit_mode = false
	s._over = false
	var burn0: int = int((pe.get("dot_stacks", {}) as Dictionary).get("burn", 0))
	s._kill(pu, pe)
	_ok("涅槃 ★分母: 触发了复活(没有真死)", pu.get("alive", false), "alive=%s" % str(pu.get("alive", false)))
	_ok("涅槃 ★★演出期【不可选中】(否则尸体会被 AOE 二次打死)",
		s._is_untargetable(pu), "untargetable=%s" % str(s._is_untargetable(pu)))
	_ok("涅槃 ★★演出期血条【还没跳】(留 1 血)", float(pu["hp"]) <= 2.0, "hp=%.0f" % float(pu["hp"]))
	_ok("涅槃 ★★演出期敌人【还没吃灼烧】(结算等展翼那一刻)",
		int((pe.get("dot_stacks", {}) as Dictionary).get("burn", 0)) == burn0,
		"burn=%d" % int((pe.get("dot_stacks", {}) as Dictionary).get("burn", 0)))
	for _f in range(int(2.6 * 60.0)):
		s._sim_step(1.0 / 60.0, false, false)
	_ok("涅槃 ★★到点(2.5 秒)才跳血条 = 25%% 最大生命",
		absf(float(pu["hp"]) - 250.0) < 1.0, "hp=%.0f (应 250)" % float(pu["hp"]))
	_ok("涅槃 ★★到点才给全体敌人灼烧",
		int((pe.get("dot_stacks", {}) as Dictionary).get("burn", 0)) > burn0,
		"burn %d → %d" % [burn0, int((pe.get("dot_stacks", {}) as Dictionary).get("burn", 0))])
	_ok("涅槃 ★演出结束后恢复可选中", not s._is_untargetable(pu))

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 凤凰喷火 on-hit" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
