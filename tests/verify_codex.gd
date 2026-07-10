extends Node
## verify_codex.gd — 自证: 图鉴显示 == 战斗实现 ("描述≠实现" 是用户高发投诉点)
## 跑法: godot --headless --path . res://tests/verify_codex.tscn --quit-after 300
##
## 覆盖:
##  1. ★龟能事实源同一: 图鉴 _skill_energy(sk) 必须等于战斗 _skill_cost() 的口径
##     (= pets.json energyCost 优先, 缺则 SkillEnergy 表兜底) —— 全 28 龟 × 全候选技逐个对
##  2. ★3选1 真的能选 3 个: _available_skill_indices() 返回全部索引 (原 idx3 需 Lv4 → 实际是 2选1)
##  3. 图鉴不再显示"🔒 Lv.4 解锁" 这类回合制残留
##  4. 每龟 skillPool = idx0 普攻 + idx1..3 三候选 (无"图鉴可见但选不到"的 idx>=4)
##  5. 每个候选技的 type 都在战斗的 _IMPL_SKILLS / PASSIVE_SKILL_TYPES 里 (图鉴里有=游戏里放得出)

const SkillEnergy := preload("res://scripts/systems/skill_energy.gd")
const Codex := preload("res://scripts/scenes/CodexScene.gd")
const TeamSel := preload("res://scripts/scenes/TeamSelectScene.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  ✓ ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  ✗ ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var pets: Array = DataRegistry.all_pets
	_ok("DataRegistry 加载了 28 龟", pets.size() == 28, "got=%d" % pets.size())

	print("=== 1. ★龟能: 图鉴 == 战斗 (pets.json energyCost 优先) ===")
	var codex := Codex.new()
	var drift: Array = []
	var zero: Array = []
	for p in pets:
		var sp: Array = p.get("skillPool", [])
		for i in range(sp.size()):
			var sk: Dictionary = sp[i]
			if i == 0 or sk.get("passiveSkill", false):
				continue
			var ty := str(sk.get("type", ""))
			if ty == "" or ty == "physical" or ty == "magic":
				continue
			var shown: int = codex._skill_energy(sk)
			var battle: int = int(round(float(sk["energyCost"]))) if sk.has("energyCost") else int(round(SkillEnergy.cost_of(ty)))
			if shown != battle:
				drift.append("%s/%s 图鉴=%d 战斗=%d" % [p["id"], ty, shown, battle])
			if shown <= 0:
				zero.append("%s/%s" % [p["id"], ty])
	codex.free()
	_ok("图鉴龟能与战斗完全一致", drift.is_empty(), "; ".join(drift))
	_ok("没有主动技显示成「龟能 0」", zero.is_empty(), "; ".join(zero))

	print("=== 2. ★3选1 真的能选 3 个 (原 idx3 被 Lv.4 锁死 = 实际 2选1) ===")
	var ts := TeamSel.new()
	var bad: Array = []
	for p in pets:
		var sp: Array = p.get("skillPool", [])
		var avail: Array = ts._available_skill_indices(p)
		if avail.size() != sp.size():
			bad.append("%s: avail=%d/%d" % [p["id"], avail.size(), sp.size()])
		elif not (3 in avail) and sp.size() > 3:
			bad.append("%s: idx3 不可选" % p["id"])
	ts.free()
	_ok("全 28 龟的 3 个候选都可选 (含 idx3)", bad.is_empty(), "; ".join(bad))
	# 不依赖玩家存档: 直接问一个不存在的 id → 走默认值分支
	# 〔踩坑: 原来断言 get_pet_level("basic")==1, 但真机存档里调试面板设过等级 → 假红〕
	GameState.test_mode = true
	_ok("get_pet_level 默认值为 1 (证明原 Lv.4 锁在实机上恒生效: 龟等级只有调试面板能改)",
		GameState.get_pet_level("__no_such_pet__") == 1)

	print("=== 3. 图鉴不再有等级解锁残留 ===")
	var csrc := _src("res://scripts/scenes/CodexScene.gd")
	_ok("图鉴无「🔒 Lv.4 解锁」文案", csrc.find("Lv.4 解锁") < 0)
	_ok("图鉴 is_locked 已恒 false", csrc.find("var is_locked: bool = false") >= 0)
	_ok("图鉴 chip 改成「3选1候选」", csrc.find("3选1候选 · 龟能") >= 0)
	var tsrc := _src("res://scripts/scenes/TeamSelectScene.gd")
	_ok("选龟界面 _available_skill_indices 不再读 get_pet_level", tsrc.find("var lv: int = GameState.get_pet_level") < 0)

	print("=== 4. skillPool 结构 = 普攻 + 3 候选 ===")
	var shape: Array = []
	for p in pets:
		var n: int = (p.get("skillPool", []) as Array).size()
		if n != 4:
			shape.append("%s len=%d" % [p["id"], n])
	_ok("全 28 龟 skillPool 长度 = 4", shape.is_empty(), "; ".join(shape))

	print("=== 5. 图鉴里有 = 游戏里放得出 ===")
	var impl := _parse_dict_keys("res://scripts/scenes/RealtimeBattle3DScene.gd", "_IMPL_SKILLS")
	var pas := _parse_dict_keys("res://scripts/scenes/RealtimeBattle3DScene.gd", "PASSIVE_SKILL_TYPES")
	_ok("_IMPL_SKILLS 解析到 (>50 条)", impl.size() > 50, "got=%d" % impl.size())
	var ghosts: Array = []
	for p in pets:
		var sp: Array = p.get("skillPool", [])
		for i in range(sp.size()):
			var sk: Dictionary = sp[i]
			var ty := str(sk.get("type", ""))
			if i == 0 or ty == "physical" or ty == "magic" or sk.get("passiveSkill", false):
				continue
			if not (ty in impl) and not (ty in pas):
				ghosts.append("%s/%s" % [p["id"], ty])
	_ok("没有「图鉴展示但战斗放不出」的技", ghosts.is_empty(), "; ".join(ghosts))

	print("")
	if _fail == 0:
		print("ALL PASS — 图鉴 == 实现 (龟能同源 / 3选1可选3个 / 无等级解锁残留)")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return ""
	var s := f.get_as_text()
	f.close()
	return s


## 括号配对解析 `const NAME := { ... }` 里的 "key": true
## 〔踩坑: 用 src.find("}") 会被注释里的 `{N/M/T:...}` 提前截断 → 曾误报"79个技放不出来"〕
func _parse_dict_keys(path: String, name: String) -> Array:
	var s := _src(path)
	var i := s.find("const %s := {" % name)
	if i < 0: return []
	var j := s.find("{", i)
	var depth := 0
	var k := j
	while k < s.length():
		var c := s[k]
		if c == "{": depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0: break
		k += 1
	var body := s.substr(j, k - j + 1)
	var out: Array = []
	var re := RegEx.new()
	re.compile("\"([A-Za-z_]+)\"\\s*:\\s*true")
	# 去注释行, 防 `{N/M/T:...}` 之类干扰
	var clean := ""
	for line in body.split("\n"):
		var h := line.find("#")
		clean += (line if h < 0 else line.substr(0, h)) + "\n"
	for m in re.search_all(clean):
		out.append(m.get_string(1))
	return out
