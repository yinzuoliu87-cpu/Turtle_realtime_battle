extends Node
## verify_codex_battle_parity.gd — 图鉴上的数 == 战斗里真生成出来的单位的数(2026-10-07 内测前图鉴体检 A/H/J)
##
## ★由来: 图鉴 `_ctx_for` / 属性牌乘了 `DataRegistry.rarity_mult`(B×1.03 … SSS×1.15),
##   而战斗 `battle_spawn._make_unit` **从来不乘稀有度** ⇒ 非 C 龟的血/攻/双抗和所有
##   {N:…ATK} 技能数字在图鉴上虚高 3~15%。等级也读错了表(`pet_levels` 只有调试面板写,
##   战斗读的是赛季等级/调试强制等级)。小将页的射程写的是 70/90, 而近战单位在
##   `_make_unit` 里被抬到 ≥ 100。
##
## ★判据一律拿【真生成的战斗单位】当尺子(`s._spawn._make_unit`), 不拿我另算的公式:
##   两边各算一份就是 memory「手抄的副本必然落后」—— 这次的 bug 正是这么来的。
##   ① 稀有度 C/B/A/S/SS/SSS 各一只: 图鉴属性牌上印的 生命/攻击/护甲/魔抗 == roundi(单位真值)
##   ② 三只按攻击力缩放的技能数字(B 手里剑 / A 精准射击 / S 水晶刺): 图鉴卡片上印的数
##      == roundi(系数 × 单位真攻击力)
##   ③ 等级: 赛季等级 4 / 调试强制等级 2 两种情况, 图鉴等级牌 == 战斗 `_unit_level("left")`,
##      且 4 项属性仍逐项相等(等级缩放同口径)
##   ④ 小将: 图鉴表(MinionCodex)的 血/攻/双抗/攻击间隔/射程 == 真生成的三种小将
##
## 跑法: bash godot-quiet.sh res://tests/verify_codex_battle_parity.tscn --quit-after 600

const SCN := preload("res://scenes/Codex.tscn")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _codex = null
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _pet(id: String) -> Dictionary:
	for it in _codex._items:
		if it is Dictionary and str((it as Dictionary).get("id", "")) == id and not (it as Dictionary).has("_minion"):
			return it
	return {}


func _select_pet(id: String) -> void:
	for i in range(_codex._items.size()):
		var it = _codex._items[i]
		if it is Dictionary and str((it as Dictionary).get("id", "")) == id and not (it as Dictionary).has("_minion"):
			_codex._codex_skill_detail = {}
			_codex._codex_passive_view = false
			_codex._codex_form_view = false
			_codex._select(i)
			await _settle(4)
			return


## 详情里所有 Label 的字(属性牌的大数字就是 Label)。
func _labels() -> PackedStringArray:
	var out: PackedStringArray = []
	for c in _codex.detail.get_children():
		if c is Label:
			out.append(str((c as Label).text))
	return out


## 详情里所有富文本(技能卡/普攻条/被动条)拼起来。
func _rich_text() -> String:
	var s := ""
	for c in _codex.detail.get_children():
		if c is RichTextLabel:
			s += (c as RichTextLabel).get_parsed_text() + "\n"
	return s


## 文本里有没有这个独立的整数(前后不是数字/小数点)。
func _has_int(txt: String, v: int) -> bool:
	var re := RegEx.create_from_string("(?<![0-9.])%d(?![0-9.])" % v)
	return re.search(txt) != null


func _spawn(id: String) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	return _s._spawn._make_unit(id, "left", c)


## 一只龟: 图鉴属性牌 vs 真生成单位。返回该单位(给技能数字那一条用)。
func _check_stats(id: String, tag: String) -> Dictionary:
	var pet := _pet(id)
	var u: Dictionary = _spawn(id)
	await _select_pet(id)
	var ctx: Dictionary = _codex._ctx_for(pet)
	var labels := _labels()
	var pairs := [["生命", "maxHp", "maxHp"], ["攻击", "atk", "atk"], ["护甲", "def", "def"], ["魔抗", "mr", "mr"]]
	for p in pairs:
		var want: int = roundi(float(u[p[1]]))
		var got: int = int(ctx[p[2]])
		_ok("%s %s(%s) %s: 图鉴 %d == 战斗 %d" % [tag, id, str(pet.get("rarity", "?")), p[0], got, want],
			got == want and labels.has(str(want)),
			"" if labels.has(str(want)) else "属性牌上没印出 %d" % want)
	## ★射程(2026-10-08 龟页新增): 图鉴印的必须是真生成单位的 atk_range(近战被抬到 ≥100, 远程照表)。
	##   按射程那一行的数字 Label 认(stat_num 元数据) —— 只查「屏上有个 100」会被移速 100 冒充。
	var want_rng: int = roundi(float(u.get("atk_range", -1.0)))
	var got_rng: String = "<没有射程行>"
	for ch in _codex.detail.get_children():
		if ch is Label and ch.has_meta("stat_num") and str(ch.get_meta("stat_num")) == "range":
			got_rng = str((ch as Label).text)
	_ok("%s %s 射程: 图鉴 %s == 战斗 atk_range %d" % [tag, id, got_rng, want_rng], want_rng > 0 and got_rng == str(want_rng))
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	## ★SHIP: 调试构建下 `_review_demo()` 默认真 ⇒ `_unit_level` 恒回 1, 赛季等级那条路走不到。
	##   设上 SHIP 才是玩家实际走的那条路(进程内环境变量, 退出前还原)。
	var had_ship := OS.has_environment("SHIP")
	OS.set_environment("SHIP", "1")
	var lv0_season: int = int(gs.season_level)
	var lv0_debug: int = int(gs.debug_level)
	gs.season_level = 1
	gs.debug_level = 0

	print("=== 图鉴数值 == 战斗真生成单位 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await _settle(2)
	_codex = SCN.instantiate()
	add_child(_codex)
	await _settle(10)
	_codex._switch_tab("pets")
	await _settle(4)
	_ok("★分母: 图鉴龟列表装起来了(%d 条)" % _codex._items.size(), _codex._items.size() >= 28)

	# ① 六个稀有度各一只(Lv1)
	print("-- ① 属性牌(Lv1, 六个稀有度) --")
	var units := {}
	for id in ["basic", "ninja", "hunter", "crystal", "headless", "shell"]:
		units[id] = await _check_stats(id, "①")

	# ② 按攻击力缩放的技能数字(Lv1 ⇒ 攻击力是整数, 必须逐字相等)
	print("-- ② 技能数字(系数 × 战斗单位真攻击力) --")
	var cases := [
		["ninja", "手里剑", NinjaSystem.SHURIKEN_COEF],
		["hunter", "精准射击", HunterSystem.SHOT_ATK_COEF],
		["crystal", "水晶刺(普攻条)", CrystalSystem.BASIC_ATK_COEF],
	]
	for cs in cases:
		var u: Dictionary = units[cs[0]]
		var want: int = roundi(float(cs[2]) * float(u["atk"]))
		var infl: int = roundi(float(cs[2]) * float(u["atk"]) * float(DataRegistry.rarity_mult.get(str(u.get("rarity", "C")), 1.0)))
		await _select_pet(cs[0])
		var txt := _rich_text()
		_ok("② %s·%s: 图鉴印 %d (= %.2f × 战斗攻击 %.0f)" % [cs[0], cs[1], want, float(cs[2]), float(u["atk"])],
			_has_int(txt, want), "" if _has_int(txt, want) else "图鉴里找不到 %d" % want)
		## 反面: 乘了稀有度的旧值不许出现(它与正确值不同时才有意义)
		if infl != want:
			_ok("② %s·%s: 旧的稀有度虚高值 %d 不再出现" % [cs[0], cs[1], infl], not _has_int(txt, infl))

	# ③ 等级: 赛季等级 / 调试强制等级
	print("-- ③ 等级(图鉴等级牌 == 战斗 _unit_level) --")
	for mode in [["赛季等级 4", 4, 0], ["调试强制等级 2", 1, 2]]:
		gs.season_level = int(mode[1])
		gs.debug_level = int(mode[2])
		var blv: int = int(_s._unit_level("left"))
		var clv: int = int(_codex._battle_level("hunter"))
		_ok("③ %s: 图鉴 Lv %d == 战斗 Lv %d" % [mode[0], clv, blv], clv == blv and blv > 1)
		await _select_pet("hunter")
		_ok("③ %s: 等级牌印着「Lv %d」" % [mode[0], blv], _labels().has("Lv %d" % blv), str(_labels().slice(0, 6)))
		for id in ["hunter", "headless"]:
			await _check_stats(id, "③[%s]" % mode[0])
	gs.season_level = 1
	gs.debug_level = 0

	# ④ 小将
	print("-- ④ 小将(MinionCodex 表 == 真生成的小将) --")
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	for mk in [["front", {"minion": true, "role": "front", "level": 1}],
			["back", {"minion": true, "role": "back", "level": 1}],
			["elite", {"minion": true, "role": "front", "elite": true, "level": 1}]]:
		var mi: Dictionary = MinionCodex.MINION_INFO[mk[0]]
		var mu: Dictionary = _s._spawn._make_unit("__minion__", "left", c, mk[1])
		var rows := [["生命", float(mi["hp"]), float(mu["maxHp"])], ["攻击", float(mi["atk"]), float(mu["atk"])],
			["护甲", float(mi["def"]), float(mu["def"])], ["魔抗", float(mi["mr"]), float(mu["mr"])],
			["射程", float(mi["range"]), float(mu["atk_range"])]]
		for r in rows:
			_ok("④ %s %s: 图鉴 %.0f == 战斗 %.0f" % [mk[0], r[0], r[1], r[2]], absf(float(r[1]) - float(r[2])) < 0.51)
		_ok("④ %s 攻击间隔: 图鉴 %.2f ≈ 战斗 %.3f" % [mk[0], float(mi["interval"]), float(mu["atk_interval"])],
			absf(float(mi["interval"]) - float(mu["atk_interval"])) < 0.006)

	gs.season_level = lv0_season
	gs.debug_level = lv0_debug
	if not had_ship:
		OS.unset_environment("SHIP")
	print("ALL PASS — 图鉴数值与战斗真生成单位逐项一致 (%d 项)" % _n if _fail == 0 else "FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)
