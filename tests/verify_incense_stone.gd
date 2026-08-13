extends Node
## verify_incense_stone.gd — 093 香火石【全链路】门禁
##
## 规格 = `docs/plans/20260805-装备逐件重做.md` §0.5「★093 香火石」(用户 2026-08-06 亲手设计)。
## 效果本体 `scripts/systems/equip/incense_stone_system.gd`, 演出 `scripts/scenes/battle/incense_vfx.gd`。
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁存在的唯一理由: 充能条会静默清零
## ══════════════════════════════════════════════════════════════════════
## 093 是全表唯一【跨对局养成】的装备 —— 充能条(0~4000)跟着装备实例走、要落进存档。
## 而装备 dict 在本项目里被**重建**的地方有 **10 处**:
##   GameState 8 处(买入 / 战中三合一 / try_merge_all 的扁平化·重建·合成件 / 持久流升星 ×3 / 糖果罐)
##   + 主场景 `_inject_equipment` 2 处(双路小将 / 玩家统领)
## 每一处都写死 `{"id":…, "star":…}`, **额外字段直接丢**。
## ⇒ 漏一处 = 玩家攒了一整个赛季的香火在某次升星/进战斗时归零, **不报错、不崩、没人会发现**。
##
## ★所以这里逐段走【真入口】: 买 → 装 → 升星 → 存档 → 读档 → 进战斗 → 攒 → 卖。
##   不去调那 10 个重建点的内部实现 —— memory [[fb-verify-must-run-the-real-path]]:
##   「断言函数存在」守不住「还有没有人调它」。
##
## ★不许恒真: 期望值一律**写死字面量**, 不读 `IncenseStoneSystem.PER_MARK` 这类被测常量。
##   每组带分母(N=0 是空检查不是通过)。

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
	print("=== 093 香火石 全链路 ===")

	_t_storage()
	_t_merge_chain()
	_t_save_load()

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0
	_t_inject()
	_t_marks()
	_t_buffs()
	_t_empower()
	_s.queue_free()
	await get_tree().process_frame

	_t_season_reset()

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 093 香火石全链路" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 存储收口: mk_eq / eq_chg —— 只有香火石带 chg 字段
# ─────────────────────────────────────────────────────────────
func _t_storage() -> void:
	print("── ① 存储收口 ──")
	var a: Dictionary = _gs.mk_eq("p2eq_093", 1, 20)
	_ok("① 香火石带 chg 字段", a.has("chg") and int(a["chg"]) == 20, str(a))
	var b: Dictionary = _gs.mk_eq("p2eq_001", 1, 20)
	_ok("① ★分母: 非香火石【不】写 chg 字段(不给另外 94 件的存档凭空加键)",
		not b.has("chg"), str(b))
	var c: Dictionary = _gs.mk_eq("p2eq_093", 1)
	_ok("① 香火石 chg=0 时也不写字段(存档不留 0 值噪音)", not c.has("chg"), str(c))
	_ok("① eq_chg 读得回 20", int(_gs.eq_chg(a)) == 20, "实测 %d" % int(_gs.eq_chg(a)))
	_ok("① ★分母: eq_chg 对非香火石恒为 0(哪怕它身上真有 chg 字段)",
		int(_gs.eq_chg({"id": "p2eq_001", "star": 1, "chg": 999})) == 0, "")


# ─────────────────────────────────────────────────────────────
# ② 升星: 三件的充能相加(用户「如果升星就合并 20 和其他的」)
#    ★走三条【真的升星入口】: try_merge_bench / try_merge_all / auto_merge_all
# ─────────────────────────────────────────────────────────────
func _t_merge_chain() -> void:
	print("── ② 升星合并充能 ──")

	# (a) 备战席三合一
	_gs.bench_inventory = [
		_gs.mk_eq("p2eq_093", 1, 20), _gs.mk_eq("p2eq_093", 1, 30), _gs.mk_eq("p2eq_093", 1, 50),
	]
	_gs.equipped_p2 = {}
	var merges: int = _gs.try_merge_bench()
	var got: int = -1
	for it in _gs.bench_inventory:
		if it is Dictionary and str(it.get("id", "")) == "p2eq_093":
			got = int(_gs.eq_chg(it))
	_ok("② (a) try_merge_bench 三合一: 充能 20+30+50 = 100", got == 100,
		"merges=%d 实测 chg=%d" % [merges, got])
	_ok("② (a) ★分母: 真的合成了 1 次且席上只剩 1 件", merges == 1 and _gs.bench_inventory.size() == 1,
		"merges=%d size=%d" % [merges, _gs.bench_inventory.size()])

	# (b) 跨域三合一(席 + 龟身)
	_gs.bench_inventory = [_gs.mk_eq("p2eq_093", 1, 7), _gs.mk_eq("p2eq_093", 1, 11)]
	_gs.equipped_p2 = {"basic": [_gs.mk_eq("p2eq_093", 1, 13)]}
	var res: Array = _gs.try_merge_all("left")
	var got2: int = -1
	for it2 in _gs.bench_inventory:
		if it2 is Dictionary and str(it2.get("id", "")) == "p2eq_093":
			got2 = int(_gs.eq_chg(it2))
	for pet in _gs.equipped_p2:
		for it3 in _gs.equipped_p2[pet]:
			if it3 is Dictionary and str(it3.get("id", "")) == "p2eq_093":
				got2 = int(_gs.eq_chg(it3))
	_ok("② (b) try_merge_all 跨域三合一: 充能 7+11+13 = 31", got2 == 31,
		"合成 %d 次 实测 chg=%d" % [res.size(), got2])
	_ok("② (b) ★分母: 真的发生了合成", res.size() >= 1, "res=%d" % res.size())

	# (c) 持久流升星(大地图)
	_gs.bench_inventory = []
	_gs.equipped_p2 = {}
	_gs.persistent_bench = [_gs.mk_eq("p2eq_093", 1, 100), _gs.mk_eq("p2eq_093", 1, 200)]
	_gs.persistent_equipped = {"basic": [_gs.mk_eq("p2eq_093", 1, 300)]}
	_gs.auto_merge_all()
	var got3: int = -1
	var star3: int = -1
	for src in [_gs.persistent_bench, _gs.persistent_equipped.get("basic", [])]:
		for it4 in src:
			if it4 is Dictionary and str(it4.get("id", "")) == "p2eq_093":
				got3 = int(_gs.eq_chg(it4)); star3 = int(it4.get("star", 1))
	_ok("② (c) auto_merge_all 持久流升星: 充能 100+200+300 = 600", got3 == 600,
		"实测 chg=%d star=%d" % [got3, star3])
	_ok("② (c) ★分母: 真的升到了 2 星(证明上面那条不是【根本没合】时的巧合)",
		star3 == 2, "star=%d" % star3)


# ─────────────────────────────────────────────────────────────
# ③ 存档 → 读档: 充能与刻痕都要活下来
# ─────────────────────────────────────────────────────────────
func _t_save_load() -> void:
	print("── ③ 存档往返 ──")
	_gs.persistent_bench = []
	_gs.persistent_equipped = {"basic": [_gs.mk_eq("p2eq_093", 2, 1234)]}
	_gs.incense_marks = 77
	# ★★这里【不调 GameState.save()】: 它里面第一行就是 `if test_mode: return` ——
	#   那是防止测试污染玩家真存档的正确设计, 测试要尊重它(verify_shop_persist 同款做法)。
	#   于是拆成两头各验一次, 合起来等价于"存得进去 + 读得回来":
	#     (a) 值经 JSON 往返不变形(存档就是 JSON.stringify / parse_string)
	#     (b) 源码级: `save()` 的 dict 里真的有这两个键, `_load()` 真的读它们
	var payload := {"persistent_equipped": _gs.persistent_equipped, "incense_marks": _gs.incense_marks}
	var back_any = JSON.parse_string(JSON.stringify(payload))
	var back: int = -1
	var back_marks: int = -1
	if back_any is Dictionary:
		back_marks = int((back_any as Dictionary).get("incense_marks", -1))
		var pe2 = (back_any as Dictionary).get("persistent_equipped", {})
		if pe2 is Dictionary:
			for it in (pe2 as Dictionary).get("basic", []):
				if it is Dictionary and str(it.get("id", "")) == "p2eq_093":
					back = int(it.get("chg", -1))
	_ok("③ (a) JSON 往返后充能还在(1234)", back == 1234, "实测 %d" % back)
	_ok("③ (a) JSON 往返后刻痕还在(77)", back_marks == 77, "实测 %d" % back_marks)

	# (b) 源码级: 存/读两头都要在。少一头就是"存了没人读"或"读了没人存",
	#     两种都不报错、只是玩家的进度悄悄归零。
	var raw: String = FileAccess.get_file_as_string("res://autoload/GameState.gd")
	var code := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		code += (ln if hi < 0 else ln.substr(0, hi)) + "\n"   # ★剥注释, 否则会命中说明文字
	var save_body: String = _fn_body(code, "func save()")
	var load_body: String = _fn_body(code, "func _load()")
	_ok("③ (b) ★★save() 的存档 dict 里有 incense_marks",
		save_body.contains("\"incense_marks\""), "save 体 %d 字符" % save_body.length())
	_ok("③ (b) ★★_load() 真的把它读回来",
		load_body.contains("incense_marks = int(data.get(\"incense_marks\""),
		"load 体 %d 字符" % load_body.length())
	_ok("③ (b) ★分母: 扫描方式有效(已知在存档里的 season_wins 两头都能扫到)",
		save_body.contains("\"season_wins\"") and load_body.contains("season_wins = int(data.get("), "")
	_ok("③ (b) ★分母: 两个函数体都非空(空串会让上面三条恒真)",
		save_body.length() > 500 and load_body.length() > 500,
		"save=%d load=%d" % [save_body.length(), load_body.length()])


## 取某个函数的函数体(到下一个顶格 func 为止)。
func _fn_body(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var e: int = code.find("\nfunc ", i + 1)
	return code.substr(i, (e - i) if e > i else -1)


# ─────────────────────────────────────────────────────────────
# ④ 进战斗: _inject_equipment 要把充能带进 u["equips"] 并进 eq_state
#    ★这是第 9/10 个重建点, 也是最容易漏的一处(它不在 GameState 里)
# ─────────────────────────────────────────────────────────────
func _t_inject() -> void:
	print("── ④ 进战斗不丢充能 ──")
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-260.0, -160.0))
	u["eq_state"] = {}
	_s._units.append(u)
	_gs.persistent_equipped = {"basic": [_gs.mk_eq("p2eq_093", 1, 3999)]}
	_s._inject_equipment()
	var carried: int = -1
	for e in u.get("equips", []):
		if e is Dictionary and str(e.get("id", "")) == "p2eq_093":
			carried = int(e.get("chg", -1))
	_ok("④ ★★_inject_equipment 把充能带进战斗(3999)", carried == 3999, "实测 %d" % carried)

	## ★★2026-08-13 充能改挂【羁绊/赛季池】(用户:「羁绊里有多少刻痕和充能都是重新激活
	##   状态…就接着激活啊」)。on_spawn 从此读 `GameState.incense_charge`, 不再读装备实例的
	##   `chg` —— 否则"卖掉再买"会把充能清零而刻痕还在, 同一条香火线两半各走各的。
	##   ⚠ 攒充能的**来源没变**: 仍是【火石携带者自己打出的伤害】(不是全队)。
	GameState.incense_charge = 3999
	_s._equip_sys._incense.on_spawn(u, "p2eq_093", 0)
	var stt: Dictionary = u["eq_state"].get("p2eq_093", {})
	_ok("④ on_spawn 从羁绊池读进 eq_state(3999)", int(stt.get("chg", -1)) == 3999,
		"实测 %d" % int(stt.get("chg", -1)))
	GameState.incense_charge = 0   # ★池子是全局的, 用完立刻清 —— 不清会污染后面的用例
	_ok("④ ★分母: 战斗里的 equips 是【副本】不是存档那个对象(改一个不该动另一个)",
		not is_same(u["equips"][0], _gs.persistent_equipped["basic"][0]), "")

	# ★★2026-08-06 补: `_inject_equipment` 里有【两条】分支各建一次装备 dict ——
	#   上面测的是 `persistent_equipped`(玩家统领)那条, 这里补 `_dl_equips`(双路小将)那条。
	#   ⚠ 这个缺口是【反向验证抓出来的】: 我打断小将分支时门禁纹丝不动 —— 因为它根本没被测到。
	#   小将一样能带装备(dual_lineup 里配的), 漏了就是"香火石装在小将身上进战斗即清零"。
	_s._units.clear()
	var m: Dictionary = _s._spawn._make_unit("__minion__", "left", c + Vector2(-200.0, -160.0))
	m["eq_state"] = {}
	m["_dl_equips"] = [{"id": "p2eq_093", "star": 1, "chg": 2718}]
	_s._units.append(m)
	_s._inject_equipment()
	var mc: int = -1
	for e2 in m.get("equips", []):
		if e2 is Dictionary and str(e2.get("id", "")) == "p2eq_093":
			mc = int(e2.get("chg", -1))
	_ok("④ ★★小将那条分支(_dl_equips)也把充能带进战斗(2718)", mc == 2718, "实测 %d" % mc)
	_ok("④ ★分母: 小将真的拿到了这件装备(不是【没装备所以没丢】)",
		mc != -1, "equips=%s" % str(m.get("equips", [])))


# ─────────────────────────────────────────────────────────────
# ⑤ 刻痕: 每 4000 伤害一道, 上限 300, 且写进 GameState
# ─────────────────────────────────────────────────────────────
func _t_marks() -> void:
	print("── ⑤ 刻痕 ──")
	_s._units.clear()
	_gs.incense_marks = 0
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _mk_carrier(c + Vector2(-260.0, -80.0), 1)
	_s._equip_sys._incense.on_spawn(u, "p2eq_093", 0)

	# 3999 伤害 → 还差 1 点, 不该刻
	u["_st_dealt"] = 3999
	_s._equip_sys._incense.tick_unit(u, 0.016)
	_ok("⑤ 造成 3999 伤害: 一道痕都没刻(阈值是 4000)",
		int(_gs.incense_marks) == 0, "marks=%d" % int(_gs.incense_marks))
	# 再 1 点 → 刚好 4000, 刻 1 道
	u["_st_dealt"] = 4000
	_s._equip_sys._incense.tick_unit(u, 0.016)
	_ok("⑤ 造成 4000 伤害: 刻 1 道", int(_gs.incense_marks) == 1, "marks=%d" % int(_gs.incense_marks))
	# 一口气 12000 → 再刻 3 道(证明是 while 不是 if, 一帧打出多道也不漏)
	u["_st_dealt"] = 16000
	_s._equip_sys._incense.tick_unit(u, 0.016)
	_ok("⑤ 一帧内又造成 12000: 再刻 3 道(是 while 不是 if)",
		int(_gs.incense_marks) == 4, "marks=%d" % int(_gs.incense_marks))

	# 上限 300: 灌一个天文数字
	u["_st_dealt"] = 16000 + 4000 * 500
	_s._equip_sys._incense.tick_unit(u, 0.016)
	_ok("⑤ ★上限 300 封住(灌了 500 道的量)", int(_gs.incense_marks) == 300,
		"marks=%d" % int(_gs.incense_marks))
	var stt: Dictionary = u["eq_state"].get("p2eq_093", {})
	_ok("⑤ 满 300 后充能条冻结在满格(不再空转)", int(stt.get("chg", -1)) == 4000,
		"chg=%d" % int(stt.get("chg", -1)))

	# 充能写回了存档
	_gs.persistent_equipped = {"basic": [_gs.mk_eq("p2eq_093", 1, 0)]}
	_gs.incense_marks = 0
	var v: Dictionary = _mk_carrier(c + Vector2(-260.0, 0.0), 1)
	v["id"] = "basic"
	_s._equip_sys._incense.on_spawn(v, "p2eq_093", 0)
	v["_st_dealt"] = 4500
	_s._equip_sys._incense.tick_unit(v, 0.016)
	var saved: int = -1
	for it in _gs.persistent_equipped.get("basic", []):
		if it is Dictionary and str(it.get("id", "")) == "p2eq_093":
			saved = int(_gs.eq_chg(it))
	_ok("⑤ ★★刻成一道痕时把余下的充能写回存档(4500-4000=500)", saved == 500,
		"存档里 chg=%d" % saved)
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# ⑥ 刻痕加成: 携带者 0.3%/痕, 其余友军 0.1%/痕, 龟蛋与大师不吃
#    ★期望值写死字面量, 不读被测常量
# ─────────────────────────────────────────────────────────────
func _t_buffs() -> void:
	print("── ⑥ 刻痕加成 ──")
	_s._units.clear()
	_gs.incense_marks = 0
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var carrier: Dictionary = _mk_carrier(c + Vector2(-260.0, 80.0), 1)
	var mate: Dictionary = _mk_plain(c + Vector2(-200.0, 80.0), "left")
	var egg: Dictionary = _mk_plain(c + Vector2(-320.0, 80.0), "left")
	egg["_isEgg"] = true
	var master: Dictionary = _mk_plain(c + Vector2(-340.0, 80.0), "left")
	master["is_trainer"] = true
	var foe: Dictionary = _mk_plain(c + Vector2(200.0, 80.0), "right")

	_s._equip_sys._incense.on_spawn(carrier, "p2eq_093", 0)
	carrier["_st_dealt"] = 4000 * 100        # 攒到 100 道
	_s._equip_sys._incense.tick_unit(carrier, 0.016)
	_ok("⑥ ★分母: 真的攒到了 100 道", int(_gs.incense_marks) == 100,
		"marks=%d" % int(_gs.incense_marks))

	# 100 道: 携带者 0.3%×100 = 30%; 其余友军 0.1%×100 = 10%
	_ok("⑥ 携带者增伤 = 30%(装备 0.2% + 羁绊 0.1%, 每道痕)",
		is_equal_approx(snappedf(float(carrier.get("damage_amp", 0.0)), 0.0001), 0.30),
		"实测 %.4f" % float(carrier.get("damage_amp", 0.0)))
	_ok("⑥ 携带者减伤 = 15%(0.1% + 0.05%)",
		is_equal_approx(snappedf(float(carrier.get("damage_reduction", 0.0)), 0.0001), 0.15),
		"实测 %.4f" % float(carrier.get("damage_reduction", 0.0)))
	_ok("⑥ 同队友军增伤 = 10%(只吃羁绊那一份)",
		is_equal_approx(snappedf(float(mate.get("damage_amp", 0.0)), 0.0001), 0.10),
		"实测 %.4f" % float(mate.get("damage_amp", 0.0)))
	_ok("⑥ ★龟蛋不吃(全表通用口径)", is_zero_approx(float(egg.get("damage_amp", 0.0))),
		"实测 %.4f" % float(egg.get("damage_amp", 0.0)))
	_ok("⑥ ★训龟大师不吃(全表通用口径)", is_zero_approx(float(master.get("damage_amp", 0.0))),
		"实测 %.4f" % float(master.get("damage_amp", 0.0)))
	_ok("⑥ ★分母: 敌方不吃(不是给全场加)", is_zero_approx(float(foe.get("damage_amp", 0.0))),
		"实测 %.4f" % float(foe.get("damage_amp", 0.0)))

	# 撤场要撤干净 —— 用【差量】记账, 不是凭空减
	mate["damage_amp"] = float(mate.get("damage_amp", 0.0)) + 0.25   # 别人给的贡献
	_s._equip_sys._incense.clear_all()
	_ok("⑥ ★★撤场只撤自己那一份(别人给的 25% 原封不动)",
		is_equal_approx(snappedf(float(mate.get("damage_amp", 0.0)), 0.0001), 0.25),
		"实测 %.4f" % float(mate.get("damage_amp", 0.0)))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# ⑦ 主动: 每 12 秒强化下 4 次普攻(+100% 攻速 / 10% 吸血 / 附带伤害)
# ─────────────────────────────────────────────────────────────
func _t_empower() -> void:
	print("── ⑦ 主动强化普攻 ──")
	_s._units.clear()
	_gs.incense_marks = 0
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	for si in range(3):
		var u: Dictionary = _mk_carrier(c + Vector2(-260.0, 160.0 + 20.0 * si), si + 1)
		u["atk"] = 100.0
		u["base_atk"] = 100.0
		u["crit"] = 0.0
		var tgt: Dictionary = _mk_plain(c + Vector2(200.0, 160.0 + 20.0 * si), "right")
		tgt["maxHp"] = 5000.0
		tgt["hp"] = 5000.0
		_s._equip_sys._incense.on_spawn(u, "p2eq_093", si)

		# 不到 12 秒不该就绪
		_s._equip_sys._incense.tick_unit(u, 11.0)
		var stt: Dictionary = u["eq_state"]["p2eq_093"]
		_ok("⑦ si=%d 11 秒时还没就绪" % si, int(stt.get("emp", 0)) == 0,
			"emp=%d" % int(stt.get("emp", 0)))
		var aspd0: float = float(u.get("aspd_perm", 1.0))
		_s._equip_sys._incense.tick_unit(u, 1.2)
		_ok("⑦ si=%d 满 12 秒: 强化下 4 次普攻" % si, int(stt.get("emp", 0)) == 4,
			"emp=%d" % int(stt.get("emp", 0)))
		_ok("⑦ si=%d 强化期间 +100% 攻速" % si,
			is_equal_approx(float(u.get("aspd_perm", 1.0)), aspd0 + 1.0),
			"aspd %.2f→%.2f" % [aspd0, float(u.get("aspd_perm", 1.0))])

		# 一发强化普攻: 附带 30/50/80 + 目标最大生命 1/1.5/2%
		var want: float = [30.0, 50.0, 80.0][si] + 5000.0 * [0.01, 0.015, 0.02][si]
		var hp0: float = float(tgt["hp"])
		_s._equip_sys._incense.on_basic(u, tgt, "p2eq_093", si)
		var dealt: float = hp0 - float(tgt["hp"])
		_ok("⑦ si=%d 附带伤害 ≈ %d(30/50/80 + 目标最大生命 1/1.5/2%%)" % [si, int(want)],
			absf(dealt - want) <= maxf(2.0, want * 0.02), "实测 %.0f 期望 %.0f" % [dealt, want])
		_ok("⑦ si=%d ★分母: 触发证据 _incense_emp_n = 1" % si,
			int(u.get("_incense_emp_n", 0)) == 1, "n=%d" % int(u.get("_incense_emp_n", 0)))

		# 打满 4 次 → 攻速撤回
		for _k in range(3):
			_s._equip_sys._incense.on_basic(u, tgt, "p2eq_093", si)
		_ok("⑦ si=%d 4 次用完: 攻速撤回原值(不残留永久攻速)" % si,
			is_equal_approx(float(u.get("aspd_perm", 1.0)), aspd0),
			"aspd=%.2f 期望 %.2f" % [float(u.get("aspd_perm", 1.0)), aspd0])
		_ok("⑦ si=%d 第 5 次普攻不再有附带伤害(计数用完了)" % si,
			int(u.get("_incense_emp_n", 0)) == 4, "n=%d" % int(u.get("_incense_emp_n", 0)))
		_s._equip_sys._incense.on_basic(u, tgt, "p2eq_093", si)
		_ok("⑦ si=%d ★分母: 第 5 次确实没加(仍是 4)" % si,
			int(u.get("_incense_emp_n", 0)) == 4, "n=%d" % int(u.get("_incense_emp_n", 0)))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# ⑧ 赛季重置: 刻痕清零(用户「一大轮重置」= 赛季)
# ─────────────────────────────────────────────────────────────
func _t_season_reset() -> void:
	print("── ⑧ 赛季重置 ──")
	_gs.incense_marks = 188
	_ok("⑧ ★分母: 重置前刻痕是 188", int(_gs.incense_marks) == 188)
	_gs.start_new_season()
	_ok("⑧ start_new_season 后刻痕清零", int(_gs.incense_marks) == 0,
		"实测 %d" % int(_gs.incense_marks))


# ── 合成单位 ─────────────────────────────────────────────────
func _mk_plain(pos: Vector2, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("fortune", side, pos)
	u["maxHp"] = 100000.0
	u["hp"] = 100000.0
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
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	_s._units.append(u)
	return u


func _mk_carrier(pos: Vector2, star: int) -> Dictionary:
	var u: Dictionary = _mk_plain(pos, "left")
	u["equips"] = [{"id": "p2eq_093", "star": star, "chg": 0}]
	u["eq_state"] = {"p2eq_093": {}}
	return u
