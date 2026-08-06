extends Node
## verify_b4_lane_leak.gd — 批④ 的【跨路泄漏】专项门禁
##
## ══════════════════════════════════════════════════════════════════════
##  为什么单独立一份
## ══════════════════════════════════════════════════════════════════════
## `verify_b4_wiring` 验的是「换路时**会调** `clear_all()`」——那是**源码扫描**。
## 它守不住「`clear_all()` 到底清干净没有」：一个只写了 `pass` 的 `clear_all`
## 同样能让那条断言全绿，而游戏里上一路的召唤物与光环会**整个带进下一路**、
## **不报错、不崩**，只是下路莫名其妙。这正是 memory [[fb-write-without-reader-and-fake-gates]]
## 那一类（「写进去了没人读」的镜像：「调了但没干活」）。
##
## 批④ 里会活过一路的东西特别多:
##   077 小手枪 · 079 医疗炮台 · 080 直升机 · 086 六门浮游炮（召唤物/逻辑体）
##   088 潮汐碑 · 094 祖龟碑（地面区域 + 全队光环）· 089 符纸（贴在敌人身上）
##
## ══════════════════════════════════════════════════════════════════════
##  本文件的规矩
## ══════════════════════════════════════════════════════════════════════
## · 量的是**真实对象**：`battle._world` 的子节点数、`battle._units` 的单位数、
##   友军身上 `damage_amp` 的实际数值 —— 不是「函数被调了几次」。
## · 每组带**分母**：先证明"清之前确实有东西"，否则"清完是 0"是空检查。
## · 走**真入口** `battle._dl_sys._dl_build_lane_field()`（换路的那条唯一管线），
##   不去手调各系统的 `clear_all()` —— 手调只能证明函数本身好使，
##   证明不了换路时真的有人调它（memory [[fb-verify-must-run-the-real-path]]）。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 批④ 跨路泄漏专项 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0

	_t_summons_cleared()
	_t_aura_cleared()
	_t_clear_all_not_empty()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 批④ 跨路无泄漏" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _mk(pos_off: Vector2, eqs: Array, side: String = "left") -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("fortune", side, c + pos_off)
	u["maxHp"] = 100000.0
	u["hp"] = 100000.0
	u["shield"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["damage_amp"] = 0.0
	u["damage_reduction"] = 0.0
	u["crit"] = 0.0
	u["buffs"] = []
	u["equips"] = eqs
	u["eq_state"] = {}
	for e in eqs:
		u["eq_state"][str(e["id"])] = {}
	if not eqs.is_empty():
		u["_b4_eq"] = true
	_s._units.append(u)
	return u


## 场上属于批④ 各系统的"活对象"总数(召唤物 + 逻辑体 + 区域)。
## ★不数 `battle._world` 的子节点总数 —— 那里面还有地形/装饰/别件的演出, 噪音太大,
##   "清完 == 0" 根本不可能成立。数各系统自己的表才是这份门禁要守的东西。
func _b4_live() -> Dictionary:
	var es = _s._equip_sys
	var d := {}
	d["pistol"] = (es._gun_sys._pistols as Array).size() if es._gun_sys.get("_pistols") != null else -1
	d["tower"] = (es._gun_sys._towers as Array).size() if es._gun_sys.get("_towers") != null else -1
	d["heli"] = (es._gun_sys._helis as Array).size() if es._gun_sys.get("_helis") != null else -1
	d["stele94"] = es._relic_sys.stele_count() if es._relic_sys.has_method("stele_count") else -1
	return d


func _sum(d: Dictionary) -> int:
	var t := 0
	for k in d:
		if int(d[k]) > 0:
			t += int(d[k])
	return t


# ─────────────────────────────────────────────────────────────
# ① 召唤物 / 逻辑体 / 碑: 换路之后一个都不许剩
# ─────────────────────────────────────────────────────────────
func _t_summons_cleared() -> void:
	print("── ① 召唤物与碑 ──")
	_s._units.clear()
	# 一只龟同时带 077 + 079 + 080(枪线三件召唤类), 另一只带 094(阵亡立碑)
	var a: Dictionary = _mk(Vector2(-260.0, -80.0), [
		{"id": "p2eq_077", "star": 3}, {"id": "p2eq_079", "star": 3}, {"id": "p2eq_080", "star": 3}])
	var b: Dictionary = _mk(Vector2(-260.0, 40.0), [{"id": "p2eq_094", "star": 3}])
	_mk(Vector2(260.0, 0.0), [], "right")
	# 走真的登场钩(每路开战管线跑的就是它)
	_s._equip_sys._stats._eq_apply_all_stats()
	# 094 要阵亡才立碑 —— 走真的伤害路径
	_s._damage._apply_damage_from(_s._units[2], b, 999999, Color("#ffffff"))
	var before: Dictionary = _b4_live()
	_ok("① ★分母: 换路【之前】场上确实有批④的活对象", _sum(before) > 0, str(before))
	_ok("① ★分母: 094 的碑确实立起来了", int(before.get("stele94", 0)) >= 1,
		"stele=%d" % int(before.get("stele94", -1)))

	# ★走真入口换路 —— 不去手调各系统的 clear_all
	_s._dl_sys._dl_build_lane_field()
	var after: Dictionary = _b4_live()
	_ok("① ★★换路之后批④的活对象全部清零(召唤物/直升机/炮台/碑一个不剩)",
		_sum(after) == 0, "清前 %s → 清后 %s" % [str(before), str(after)])
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# ② 光环: 094 的全队增伤/减伤不许跟着进下一路
#    ★量的是友军身上的【实际数值】, 不是"函数被调了"
# ─────────────────────────────────────────────────────────────
func _t_aura_cleared() -> void:
	print("── ② 光环残留 ──")
	_s._units.clear()
	var car: Dictionary = _mk(Vector2(-240.0, -40.0), [{"id": "p2eq_094", "star": 3}])
	var mate: Dictionary = _mk(Vector2(-200.0, -40.0), [])
	_mk(Vector2(240.0, -40.0), [], "right")
	_s._equip_sys._stats._eq_apply_all_stats()
	_s._damage._apply_damage_from(_s._units[2], car, 999999, Color("#ffffff"))
	_s._equip_sys.tick_global(0.1)
	var amp0: float = float(mate.get("damage_amp", 0.0))
	_ok("② ★分母: 立碑后队友确实吃到了增伤", amp0 > 0.0, "amp=%.4f" % amp0)

	_s._dl_sys._dl_build_lane_field()
	# ★换路会整体重建单位字典 ⇒ 旧的 mate 已经不在场上。要验的是【新一路的单位】没有残留光环,
	#   而不是去看那个已经作废的旧字典(它留着多少都无所谓)。
	var leaked: Array = []
	for u in _s._units:
		if u is Dictionary and float(u.get("damage_amp", 0.0)) > 0.0001:
			leaked.append("%s amp=%.4f" % [str(u.get("name", "?")), float(u["damage_amp"])])
	_ok("② ★★换路后【新一路的单位】身上没有残留的碑光环", leaked.is_empty(), str(leaked))
	_ok("② ★分母: 新一路确实建出了单位(空场会让上面那条恒真)",
		_s._units.size() > 0, "units=%d" % _s._units.size())
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# ③ 反向: 六个 clear_all 里不许有空壳
#    ★这条守的是"以后有人把某一路的 clear_all 改回 pass" —— 那时上面两条会红,
#      但红在很远的地方、很难定位; 这条直接指出是哪一路。
# ─────────────────────────────────────────────────────────────
func _t_clear_all_not_empty() -> void:
	print("── ③ 六个 clear_all 都不是空壳 ──")
	var files := {
		"gun": "res://scripts/systems/equip/eq_gun_batch.gd",
		"blade": "res://scripts/systems/equip/eq_blade_batch.gd",
		"gadget": "res://scripts/systems/equip/eq_gadget_batch.gd",
		"arcane": "res://scripts/systems/equip/eq_arcane_batch.gd",
		"relic": "res://scripts/systems/equip/eq_relic_batch.gd",
		"incense": "res://scripts/systems/equip/incense_stone_system.gd",
	}
	var empty: Array = []
	var checked := 0
	for k in files:
		var raw: String = FileAccess.get_file_as_string(str(files[k]))
		var code := ""
		for ln in raw.split("\n"):
			var hi: int = ln.find("#")
			code += (ln if hi < 0 else ln.substr(0, hi)) + "\n"   # ★剥注释再扫
		var i: int = code.find("func clear_all()")
		if i < 0:
			empty.append("%s 没有 clear_all" % k)
			continue
		var e: int = code.find("\nfunc ", i + 1)
		var body: String = code.substr(i, (e - i) if e > i else -1)
		checked += 1
		# 只有 `func clear_all() -> void:` + `pass` 两行 = 空壳
		var meat := body.replace("func clear_all() -> void:", "").replace("pass", "").strip_edges()
		if meat == "":
			empty.append("%s 的 clear_all 是空壳" % k)
	_ok("③ 六个 clear_all 都真的干了活(不是只写 pass)", empty.is_empty(), str(empty))
	_ok("③ ★分母: 真的取到了 6 个函数体", checked == 6, "checked=%d" % checked)
