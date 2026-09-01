extends Node
## verify_hiding_pool.gd — 守卫: 缩头召唤池 = 全部 A/B/C 稀有度的龟, 且每只能当随从不崩
##
## 用户〖2026-07-11〗:「缩头乌龟只能召唤A及以下的」「确保涵盖所有A，B，C的」
##   → _hiding_pool() 运行时从稀有度动态生成; 本测试断言它【恰好】= 全部 A/B/C 龟(不多不少),
##     且逐只 _make_unit 当随从不崩(捕过去只测了固定 12 只名单)。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const HidingSystem := preload("res://scripts/systems/skills/hiding_system.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	# 从 pets.json 算出应有的 A/B/C 集合
	var f := FileAccess.open("res://data/pets.json", FileAccess.READ)
	var doc = JSON.parse_string(f.get_as_text())
	f.close()
	var pets: Array = doc["pets"] if (doc is Dictionary and doc.has("pets")) else doc
	var want: Dictionary = {}
	for p in pets:
		var r := str(p.get("rarity", ""))
		if r == "A" or r == "B" or r == "C":
			want[str(p.get("id", ""))] = true

	var pool: Array = scene._hiding_sys._hiding_pool()
	var got: Dictionary = {}
	for x in pool:
		got[str(x)] = true

	# ── 自检探针 ──
	_ok("自检·阳性(basic 是 C 级, 应在池里)", want.has("basic"))
	_ok("自检·阴性(shell 是 SSS 级, 不该在池里)", not want.has("shell"))
	_ok("自检·阴性(headless 是 SS 级, 不该在池里)", not want.has("headless"))

	# ── 1. 池 == 全部 A/B/C ──
	var extra: Array = []
	for x in got.keys():
		if not want.has(x):
			extra.append(x)
	var lack: Array = []
	for x in want.keys():
		if not got.has(x):
			lack.append(x)
	_ok("缩头池 = 全部 A/B/C 稀有度的龟", extra.is_empty() and lack.is_empty(),
		"多出 %s / 缺少 %s (池 %d 只)" % [str(extra), str(lack), pool.size()])

	# ── 2. 每只都能当随从 spawn 不崩 ──
	var crashed: Array = []
	for pid in want.keys():
		var m: Dictionary = scene._spawn._make_unit(str(pid), "right", Vector2(900, 400))
		if m.is_empty() or not m.has("hp"):
			crashed.append(str(pid))
	_ok("每只 A/B/C 龟都能 _make_unit 当随从", crashed.is_empty(), str(crashed))

	# ── 3. ★★★缩头大招的另一半:「立即给随从 +50% 技能龟能」真的加速了随从 ──
	## ★由来(2026-09-01): 原来写的是 `m["energy"] += cost * 0.5`, 而**随从的 `energy`
	##   全引擎零读者** —— 随从跟真龟一样走技能冷却 `skill_cd`。
	##   探针实测: 随从 bamboo/bambooHeal 冷却剩 8.050 秒, 放完缩头**仍是 8.050**,
	##   这个 100 龟能大招有一半是空的。与同日抓到的斧头 `ax["energy"]` 同一个形状。
	## ★★判据落在**冷却真的被推进**(产品自己的账), 不是"我插了个标记"。
	var owner_u: Dictionary = scene._spawn._make_unit("hiding", "left",
		scene.ARENA.position + scene.ARENA.size * 0.5)
	scene._units.append(owner_u)
	scene._spawn._spawn_hiding_minion(owner_u)
	await get_tree().process_frame
	var mi = scene._hiding_sys._hiding_minion_of(owner_u)
	_ok("★分母: 缩头随从真的召出来了(没召出来 = 下面是空检查)", mi != null,
		"id=%s" % str(mi.get("id", "?") if mi != null else "null"))
	if mi != null:
		for _w in range(20):
			await get_tree().process_frame
		var cds: Dictionary = mi.get("skill_cd", {})
		_ok("★分母: 随从带着自己的技能冷却表(%d 项)" % cds.size(), not cds.is_empty(),
			"active_skills=%s" % str(mi.get("active_skills", [])))
		var cd0 := 1e9
		for k in cds:
			cd0 = minf(cd0, float(cds[k]))
		_ok("★分母: 放技前冷却是【非零】的(为 0 就推不动, 这条会恒绿)", cd0 > 0.05,
			"实测 %.3f 秒" % cd0)
		## ★★★【不许跨帧】—— 第一版我在前后各 await 了一帧, 而冷却**自己也在走**,
		##   于是 `cd1 < cd0` 恒真: 反向验证时把那行改回没人读的 energy, 门禁照样全绿。
		##   量的是"时间过去了"而不是"技能给了龟能"。同步调用同步量, 中间一帧都不许过。
		scene._hiding_sys._sk_hiding_shrink(owner_u)
		var cd1 := 1e9
		for k in cds:
			cd1 = minf(cd1, float(cds[k]))
		## ★判据还要卡住【推进了多少】: 1 点龟能 = 0.075 秒(全局换算),
		##   给的是该技花费的 50% ⇒ 推进量 = cost × 0.5 × 0.075。只判">0"会被自然冷却蒙混。
		var acts: Array = mi.get("active_skills", [])
		var cost: float = scene.SkillEnergy.cost_of(str(acts[0])) if not acts.is_empty() else 95.0
		var want_drop: float = cost * HidingSystem.SHRINK_MINION_ENERGY * 0.075
		_ok("★★★缩头把随从冷却推进了 %.3f 秒(应 %.3f = %.0f龟能×50%%×0.075)"
			% [cd0 - cd1, want_drop, cost],
			absf((cd0 - cd1) - want_drop) <= 0.05,
			"一点没动/对不上 = 那 +50% 龟能又进了没人读的字段")

	print("")
	if _fail == 0:
		print("ALL PASS — 缩头池 = 全 A/B/C(", want.size(), "只), 无 S/SS/SSS, 逐只可当随从")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)
