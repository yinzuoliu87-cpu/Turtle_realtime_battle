extends Node
## verify_skill_energy.gd — 守卫: 龟能只有【一个事实源】

const SkillEnergy := preload("res://scripts/systems/skill_energy.gd")  # 该脚本无 class_name, 必须 preload
##
## 由来: 龟能的数值散在两个地方, 三处 UI 各读各的 → 骗玩家。
##   · 战斗   `RealtimeBattle3DScene._skill_cost` = pets.json `energyCost` 优先, `SkillEnergy` 兜底
##   · 图鉴   `CodexScene._skill_energy`          = 同口径 (早先已修)
##   · 选龟   `TeamSelectScene`                   = ★2026-07-10 之前【只读 SkillEnergy】→
##        彩虹·棱镜护盾 `shield`: pets=50 / SkillEnergy=70 → 界面显 70, 实战花 50
##        彩虹·反射 `rainbowReflect`: 表里根本没有 → `is_active()` 为 false → 界面【完全不显龟能】
##
## 本测试把「单一事实源」变成机器检查:
##   1. `SkillEnergy.SKILL_COST` 的键集合 == 全部 28 龟 skillPool[1..3] 的 type 集合
##      (多了 → 死数据 / 普攻 type 混进来会让选龟界面给普攻卡贴"龟能"标签;
##       少了 → is_active() 为 false, 那个技能在选龟界面不显龟能)
##   2. 凡 pets.json 写了 `energyCost` 的, 必须与 SkillEnergy 表里的值一致 (否则运行时/界面对不上)
##   3. 普攻 (skillPool[0]) 的 type 一律【不许】出现在表里

var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame

	var f := FileAccess.open("res://data/pets.json", FileAccess.READ)
	var doc = JSON.parse_string(f.get_as_text())
	f.close()
	var pets: Array = doc["pets"] if (doc is Dictionary and doc.has("pets")) else doc

	var active: Dictionary = {}   # type -> energyCost (可能 null)
	var basics: Dictionary = {}
	for p in pets:
		var pool = p.get("skillPool", [])
		if not (pool is Array):
			continue
		for i in (pool as Array).size():
			var sk: Dictionary = pool[i]
			var t := str(sk.get("type", ""))
			if t == "":
				continue
			if i == 0:
				basics[t] = true
			else:
				active[t] = sk.get("energyCost", null)

	var tbl: Dictionary = SkillEnergy.SKILL_COST

	# ── 自检探针: 表和集合都不是空的, 且已知项在位 ─────────────────────────
	_ok("自检·阳性(lineInkBomb 是主动技)", active.has("lineInkBomb"))
	_ok("自检·阴性(编造的 type 不在主动技集)", not active.has("__不存在的技能__"))
	_ok("自检·SkillEnergy 表非空", tbl.size() > 10, "size=%d" % tbl.size())

	# ── 1. 键集合必须完全相等 ────────────────────────────────────────────
	var extra: Array = []
	for k in tbl.keys():
		if not active.has(k):
			extra.append("%s%s" % [k, "(是普攻type)" if basics.has(k) else ""])
	var lack: Array = []
	for k in active.keys():
		if not tbl.has(k):
			lack.append(k)
	_ok("SkillEnergy 表 = skillPool[1..3] 的 type 集合", extra.is_empty() and lack.is_empty(),
		"多出 %s / 缺少 %s" % [str(extra.slice(0, 5)), str(lack.slice(0, 5))])

	# ── 2. pets.json 写了 energyCost 的必须与表一致 ───────────────────────
	var conflict: Array = []
	for k in active.keys():
		var ec = active[k]
		if ec != null and tbl.has(k) and absf(float(ec) - float(tbl[k])) > 0.01:
			conflict.append("%s: pets=%s SkillEnergy=%s" % [k, ec, tbl[k]])
	_ok("pets.json energyCost 与 SkillEnergy 无冲突", conflict.is_empty(), str(conflict))

	# ── 3. 普攻 type 不许进表 ─────────────────────────────────────────────
	var basic_in_tbl: Array = []
	for k in basics.keys():
		if tbl.has(k):
			basic_in_tbl.append(k)
	_ok("普攻 type 不在龟能表里", basic_in_tbl.is_empty(), str(basic_in_tbl))

	print("")
	if _fail == 0:
		print("ALL PASS — 龟能单一事实源: 表与技能池一一对应, 无冲突, 普攻不占位")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)
