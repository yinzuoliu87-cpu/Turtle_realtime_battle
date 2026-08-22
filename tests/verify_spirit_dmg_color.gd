extends Node
## verify_spirit_dmg_color.gd — 触手拍击的伤害【必须是物理】, 两条路都是
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 用户 2026-08-22「触手打的时候跳的伤害数字是紫色的没有符合规则,
##          有的时候物理伤害被跳成了蓝色数字, 这是很严重的 bug」
## ══════════════════════════════════════════════════════════════════
## 复现出来的根因(不是推理):
##   飘字颜色**只看全局 `battle._last_dmg_type`**(物红/魔蓝/真白) ——
##   `_apply_damage` / `_apply_damage_from` 的 `col` 参数在函数体里根本没被用。
##   而 `_slap_resolve` 的【没有携带者】分支不走 `_resolve_dmg` ⇒ 不设那个字段
##   ⇒ **继承上一次别的伤害的类型**。
## ★那条分支的原注释写着「理论上不该发生」—— **是错的**:
##   触手是**无敌的**, 会活过携带者的死亡, 携带者一死就必然走到它。
##
## 判据: 先把全局类型**污染**成 magic, 再打一下, 打完必须是 physical。
##   ★污染是必须的 —— 不污染的话默认值本来就是 physical, 这条会永远绿(空判据)。

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	for u in scn._units.duplicate():
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp):
			sp.queue_free()
	scn._units.clear()
	var cx: float = scn.ARENA.position.x + scn.ARENA.size.x * 0.5
	var cy: float = scn.ARENA.position.y + scn.ARENA.size.y * 0.5
	var carrier: Dictionary = scn._spawn._make_unit("basic", "left", Vector2(cx - 320.0, cy))
	carrier["no_move"] = true
	carrier["no_basic"] = true
	carrier["move_spd"] = 0.0
	carrier["active_skills"] = []
	carrier["deathfloor_until"] = 999999.0
	carrier["equips"] = [{"id": "p2eq_032", "star": 1}, {"id": "p2eq_025", "star": 1}]
	scn._units.append(carrier)
	var root: Vector2 = scn._tentacle_vfx.default_root("left", 0)
	var d: Dictionary = scn._spawn._make_unit("basic", "right", Vector2(root.x + 200.0, root.y))
	d["no_move"] = true
	d["no_basic"] = true
	d["move_spd"] = 0.0
	d["active_skills"] = []
	d["base_def"] = 0.0
	d["base_mr"] = 0.0
	scn._recalc_stats(d)
	d["maxHp"] = 100000.0
	d["hp"] = 100000.0
	d["deathfloor_until"] = 999999.0
	scn._units.append(d)
	scn._synergy.clear()
	scn._synergy.apply_all()
	await get_tree().process_frame
	print("=== 触手拍击的伤害类型(飘字颜色的唯一来源) ===")
	var ss = scn._spirit_syn
	_ok("★分母: 灵物档位配上了(0 的话什么都不会发生)", ss._side_tier("left") > 0,
		"档位 %d" % ss._side_tier("left"))

	## ── ① 有携带者 ──
	scn._last_dmg_type = "magic"                      # ★污染: 假装上一次是法术
	var hp0: float = float(d["hp"])
	var n1: int = ss._slap_resolve("left", root, Vector2.RIGHT, 400.0, 1.0)
	_ok("★分母: 有携带者时真的打中了", n1 > 0 and float(d["hp"]) < hp0, "命中 %d" % n1)
	_ok("★★①有携带者: 打完伤害类型是【物理】(飘字红)",
		scn._last_dmg_type == "physical", "实测 %s" % scn._last_dmg_type)

	## ── ② 携带者已死 —— 触手无敌, 会活过它 ──
	## ★★2026-08-22 改: 这里原来【全队只有携带者一个人】, 它一死场上就没有任何
	##   活着的友军。上一版为此手搓了一个 ghost 字典当伤害来源, 结果那个精简字典
	##   缺 `dmg_dealt`(+= 缺键=运行时错误, 函数当场中止)、被**反伤**当受害者打回来时
	##   又缺 `shield`/`id`(smoke 一场刷 11 条红)。手搓精简单位这条路仓库里栽过两次。
	##   ⇒ 现在不造合成单位, 没有携带者就退回【本方任一存活单位】当来源。
	##   ⇒ 场景也要改成真实的那个: **携带者死了、队伍还在** —— 用户报的 bug 就发生在
	##     那种局面, 而不是"整队团灭后触手还在打"(那时胜负早已判定)。
	var mate: Dictionary = scn._spawn._make_unit("basic", "left", root + Vector2(-60.0, 40.0))
	mate["no_move"] = true
	mate["no_basic"] = true
	scn._units.append(mate)
	carrier["alive"] = false
	_ok("★分母: 携带者死后 _any_carrier 真的返回空(否则下面这条测不到)",
		ss._any_carrier("left") == null)
	scn._last_dmg_type = "magic"
	var hp1: float = float(d["hp"])
	var n2: int = ss._slap_resolve("left", root, Vector2.RIGHT, 400.0, 1.0)
	_ok("★分母: 携带者死后触手照样打中(它是无敌的)", n2 > 0 and float(d["hp"]) < hp1,
		"命中 %d" % n2)
	_ok("★★★②携带者已死: 打完伤害类型仍是【物理】(这就是用户报的那个 bug)",
		scn._last_dmg_type == "physical", "实测 %s" % scn._last_dmg_type)

	## ── ③ 整队团灭 —— 明确记下新行为, 别让它变成"没人知道会怎样" ──
	## 没有任何存活友军时【不再出伤】。理由: 那一刻胜负已定; 而为了继续出伤去手搓
	## 一个假来源, 换来的是上面那两类缺键崩溃。这是有意的取舍, 不是漏改。
	mate["alive"] = false
	var hp2: float = float(d["hp"])
	var n3: int = ss._slap_resolve("left", root, Vector2.RIGHT, 400.0, 1.0)
	_ok("★③本方全灭: 拍击不再出伤(有意取舍·见上)",
		n3 == 0 and absf(float(d["hp"]) - hp2) < 0.01, "命中 %d" % n3)

	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 触手伤害恒为物理" if _fail == 0 else "FAIL")
	scn.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)
