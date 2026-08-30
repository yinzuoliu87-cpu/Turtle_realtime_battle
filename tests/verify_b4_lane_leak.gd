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
	_t_new_lane_summons_alive()
	_t_ui_residue()

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


## ③ 换路残留: UI 层的飘字必须被清, 而 HUD 必须留着(用户 2026-08-13 第 9 条)。
##
## ★为什么 UI 层要单独守: 兜底扫 `_sweep_world_vfx()` 只遍历 `_world`, 而飘字挂的是
##   `_ui_layer`(battle_vfx.gd) ⇒ 换路后伤害/治疗数字照样留在屏幕上。探针实测拿到过
##   两个匿名 Label 活过换路。
## ★两个方向都要守: 我第一版用"建场快照"判常驻, 结果 HUD 是快照之后才建的 ⇒
##   整个 HUD(PK条/暗角/按钮)被当成非常驻一起扫掉, `_ui_layer` 从 13 个变 0 个。
##   所以下面第二条("HUD 还在")和第一条同样重要。
func _t_ui_residue() -> void:
	print("── ③ 换路残留: UI 层 ──")
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var a: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-150, 0))
	var b: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(150, 0))
	_s._units.clear()
	_s._units.append_array([a, b])
	_s._damage._apply_damage_from(a, b, 120.0, Color("#ff4444"), 0.0, false, false)
	_s._damage._apply_damage_from(b, a, 90.0, Color("#7ecbff"), 0.0, false, false)
	var floats0: int = get_tree().get_nodes_in_group(BattleHud.UI_TRANSIENT_GROUP).size()
	_ok("③ ★分母: 打两下真的产生了飘字(0 的话下面是空检查)", floats0 >= 2,
		"飘字 %d 个" % floats0)
	var hud_before: int = int(_s._ui_layer.get_child_count())
	_s._dl_sys._dl_clear_units()
	var alive_floats := 0
	for n in get_tree().get_nodes_in_group(BattleHud.UI_TRANSIENT_GROUP):
		if n is Node and is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
			alive_floats += 1
	_ok("③ ★★换路清场后飘字一个不剩(它们挂在 _ui_layer, 以前从没被扫过)",
		alive_floats == 0, "还活着 %d 个" % alive_floats)
	var pk_alive := false
	for ch in _s._ui_layer.get_children():
		if str(ch.name) == "PkBar" and not ch.is_queued_for_deletion():
			pk_alive = true
	_ok("③ ★★HUD 不许被误伤(PkBar 还在) —— 第一版用快照判常驻就把整个 HUD 扫没了",
		pk_alive, "清场前 UI 层 %d 个子节点" % hud_before)


# ─────────────────────────────────────────────────────────────
# ④ ★★换路之后, 新一路【该长出来的召唤物要真的活着】
#
#   ★由来(2026-08-30): 用户实测「5 费直升机有 bug, 无法召唤」「上路/下路/决胜都不行」。
#     根因: `_dl_build_lane_field()` 里清了两次 —— `_b4_all()` 那一轮在登场钩【之前】(对的),
#     但 08-20 补的 `for _sysref` 名单又把同样五个系统列进去, 而它在登场钩【之后】
#     ⇒ 直升机刚生成就被 `vfx.heli_free()` 拔掉整个节点。
#
#   ★本文件上面 ① 那条为什么全绿: 它只问"换路后旧的清光没有"—— 而这个 bug
#     让结果【更干净】, 恰好满足它的期望。判据只卡住了需求的一半。
#     缺的这一半就是本条: **新一路的携带者必须重新拥有它的召唤物。**
#     (同族: memory [[fb-judge-must-fit-the-shape]]、[[fb-gate-subject-never-constructed]])
# ─────────────────────────────────────────────────────────────
func _t_new_lane_summons_alive() -> void:
	print("── ④ 换路后新一路的召唤物 ──")
	_s._units.clear()
	var saved: Dictionary = GameState.dual_lineup.duplicate(true)
	var saved_lane = GameState.current_lane
	var saved_active = GameState.get("dual_active")
	## ★必须打开双路标记 —— 否则 `_inject_equipment` 走 `use_demo` 分支,
	##   会拿 DEMO_EQUIP 把我们配的 080 整个覆盖掉(分母断言第一次就是被它抓出来的)。
	GameState.set("dual_active", true)
	## ★阵容必须【结构合法】—— `get_dual_lineup()` 要求 top+bottom 都在、恰好 3 个统领
	##   且 slot 覆盖 0/1/2, 否则它**整个重置成默认阵容**, 我们配的 080 当场被扔掉
	##   (第一版就是栽在这里: 分母断言报"携带者 0 个", 而不是静默放过)。
	## ★`_resolve_leader_slots` 会拿 season_leaders[slot] 覆盖 id ⇒ 也得一起摆好再还原。
	var saved_leaders: Array = (GameState.season_leaders as Array).duplicate(true)
	GameState.season_leaders = ["basic", "basic", "basic"]
	GameState.dual_lineup = {
		"top": [
			{"kind": "leader", "id": "basic", "slot": 0,
				"equips": [{"id": "p2eq_080", "star": 3}, {"id": "p2eq_077", "star": 3}]},
			{"kind": "leader", "id": "basic", "slot": 1},
			{"kind": "minion", "role": "front"}],
		"bottom": [
			{"kind": "leader", "id": "basic", "slot": 2},
			{"kind": "minion", "role": "front"},
			{"kind": "minion", "role": "back"}],
	}
	GameState.current_lane = "top"
	_s._dl_sys._dl_build_lane_field()
	var live: Dictionary = _b4_live()
	var carrier_n: int = 0
	for u in _s._units:
		if u is Dictionary and str(_s._eff_side(u)) == "left":
			for e in u.get("equips", []):
				if e is Dictionary and str(e.get("id", "")) == "p2eq_080":
					carrier_n += 1
	_ok("④ ★分母: 新一路真的建出了一个带 080 的携带者(没有他, 下面那条恒真)",
		carrier_n >= 1, "携带者 %d 个 / 场上 %d 单位" % [carrier_n, _s._units.size()])
	_ok("④ ★★换路之后直升机【活着】—— 生成完不许再被清一次",
		int(live.get("heli", -1)) >= 1, "heli=%d  全表 %s" % [int(live.get("heli", -1)), str(live)])
	_ok("④ 同管线的小手枪也活着(它是真单位, 只会丢驱动登记表 ⇒ 另一副面孔)",
		int(live.get("pistol", -1)) >= 1, "pistol=%d" % int(live.get("pistol", -1)))
	## ★收尾还原(CLAUDE.md §7 铁律④: 测试不许污染真存档)
	GameState.dual_lineup = saved
	GameState.current_lane = saved_lane
	GameState.set("dual_active", saved_active)
	GameState.season_leaders = saved_leaders
	_s._units.clear()
