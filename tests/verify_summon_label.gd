extends Node
## verify_summon_label.gd — **结算战报里不许出现英文内部名**(台账 ⑸ `wraith`)
## 判据名: **NO_RAW_ID**(`spirit_synergy_system.gd` 的注释按这个名字指过来)
##
## ═══ 守的是哪条真机 bug ═══
## 台账 ⑸: 玩家在结算战报的「我方 / 敌方」表里看到一行写着英文 `wraith`。
## 机制: `battle_spawn._spawn_summon()` 里
##   `"name": str(behavior.get("label", kind))`
## ⇒ 调用点**不传 `label`** 就直接把内部 kind 当名字写进单位字典,
## 而结算战报那一行画的是 `battle._st_name(u)`(`battle_hud._stats_column`),
## 它读的正是 `u["name"]` ⇒ 少传一个字段, 屏幕上就多一个英文词。
##
## ═══ 三段, 少一段都会放过一种错法 ═══
##   ① **机制分母**: 真调一次不带 label 的 `_spawn_summon`, 证明它确实会把英文写上屏
##      —— 没有这一条, 下面两段可能在测一个不会出事的机制(恒真式)。
##   ② **全仓覆盖**: 扫 `scripts/` 下**每一个** `_spawn_summon(` 调用点,
##      逐个要求带 `label`, 且 label 里不许有 ASCII 字母。
##      ★只补 `wraith` 那一件是不够的 —— 下一个新召唤物照样会漏。分母 = 扫到几个调用点。
##   ③ **端到端**: 走亡灵羁绊的**真入口** `on_death()` 生一只亡魂,
##      读产品自己的战报取名函数 `_st_name()`。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_summon_label.tscn --quit-after 500

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")

## 扫哪里 / 扫什么。★不写死文件名单 —— 名单天生会漏(本仓 8 个测试就是漏登记才从没跑过)。
const SCAN_ROOT := "res://scripts"
const CALL := "_spawn_summon("

## 调用点总数的**下限**。2026-09-30 实测 16 个。
## ★写成下限而不是等号: 新加召唤物不该让这条红(它该让"这个新调用点带没带 label"那条红)。
const MIN_CALL_SITES := 16

## 允许的**非字面量** label 表达式 —— 每一条都在 ② 段末尾有一条单独的运行期断言
## 把它的真实取值验一遍。名单之外的非字面量当场红(否则动态 label 就是一条无人看管的缝)。
const DYNAMIC_LABELS := ["str(AE.stage(si)[\"name\"])"]

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 有没有 ASCII 字母 —— 「英文内部名」的判据。
## ★不判"是不是中文": 数字/百分号/间隔号在名字里是合法的(「小手枪」没有, 但将来可能有),
##   而**玩家屏幕上不该出现拉丁字母**这件事是明确的。
func _has_latin(s: String) -> bool:
	for i in range(s.length()):
		var c: int = s.unicode_at(i)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			return true
	return false


func _ready() -> void:
	await get_tree().process_frame
	print("=== 召唤物名字: 屏幕上不许出现英文内部名 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(20):
		await get_tree().process_frame

	_seg1_mechanism()
	_seg2_coverage()
	_seg3_wraith()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 召唤物名字无英文内部名" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _mk(side: String) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("green", side, c)
	u["maxHp"] = 1000.0
	u["hp"] = 1000.0
	u["base_atk"] = 100.0
	u["atk"] = 100.0
	return u


# ══════════════════════════════════════════════════════════════════════
# ① 机制分母: 不传 label 就真的会把英文写上屏
# ══════════════════════════════════════════════════════════════════════
func _seg1_mechanism() -> void:
	print("── ① 机制分母: `_spawn_summon` 少传 label = 英文上屏 ──")
	var own := _mk("left")
	_ok("① ★分母: 战斗场起来了(拿不到 _spawn 的话下面全是空检查)",
		_s._spawn != null and _s.has_method("_st_name"))
	## ★这里走的是**产品自己的函数**, 不是我造的标记: `_spawn_summon` 建单位,
	##   `_st_name` 就是 `battle_hud._stats_column` 画那一行名字时调的那个。
	var bare = _s._spawn._spawn_summon(own, "wraith", 100.0, 10.0, {})
	_ok("① ★★不传 label ⇒ 战报取名函数吐出**内部 kind 本身**(台账 ⑸ 屏幕上那个词)",
		bare is Dictionary and _s._st_name(bare) == "wraith",
		"_st_name=%s" % (_s._st_name(bare) if bare is Dictionary else "<null>"))
	_ok("① ★★而且它确实含 ASCII 字母(这就是本门禁的判据形状)",
		bare is Dictionary and _has_latin(_s._st_name(bare)),
		_s._st_name(bare) if bare is Dictionary else "")
	var named = _s._spawn._spawn_summon(own, "wraith", 100.0, 10.0, {"label": "亡魂"})
	_ok("① ★传了 label ⇒ 战报那一行就是它", named is Dictionary and _s._st_name(named) == "亡魂",
		"_st_name=%s" % (_s._st_name(named) if named is Dictionary else "<null>"))
	## 把这两只造出来的临时单位撤掉, 别污染后面的段
	for x in [bare, named]:
		if x is Dictionary:
			for i in range(_s._units.size() - 1, -1, -1):
				if is_same(_s._units[i], x):
					_s._units.remove_at(i)


# ══════════════════════════════════════════════════════════════════════
# ② 全仓覆盖: 每一个 `_spawn_summon(` 调用点都带中文 label
# ══════════════════════════════════════════════════════════════════════
func _files(root: String) -> Array:
	var out: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var d: String = str(st.pop_back())
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		while true:
			var f := da.get_next()
			if f == "":
				break
			if f.begins_with("."):
				continue
			var p: String = d.path_join(f)
			if da.current_is_dir():
				st.append(p)
			elif f.ends_with(".gd"):
				out.append(p)
		da.list_dir_end()
	out.sort()
	return out


## 从 `_spawn_summon(` 那个左括号起做括号配平, 切出整条调用(可能跨多行)。
func _call_text(src: String, open_paren: int) -> String:
	var depth := 0
	var instr := ""
	var k: int = open_paren
	while k < src.length():
		var c: String = src[k]
		if instr != "":
			if c == "\\":
				k += 2
				continue
			if c == instr:
				instr = ""
		elif c == "\"" or c == "'":
			instr = c
		elif c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
			if depth == 0 and c == ")":
				return src.substr(open_paren, k - open_paren + 1)
		k += 1
	return src.substr(open_paren)


## `"label": <这里>` 的那段表达式原文(到同层的 `,` 或 `}` 为止)。取不到返回 ""。
func _label_expr(call: String) -> String:
	var i: int = call.find("\"label\"")
	if i < 0:
		return ""
	var j: int = call.find(":", i)
	if j < 0:
		return ""
	j += 1
	var depth := 0
	var instr := ""
	var out := ""
	var k: int = j
	while k < call.length():
		var c: String = call[k]
		if instr != "":
			out += c
			if c == "\\":
				out += call[k + 1] if k + 1 < call.length() else ""
				k += 2
				continue
			if c == instr:
				instr = ""
			k += 1
			continue
		if c == "\"" or c == "'":
			instr = c
			out += c
		elif c == "(" or c == "[" or c == "{":
			depth += 1
			out += c
		elif c == ")" or c == "]" or c == "}":
			if depth == 0:
				break
			depth -= 1
			out += c
		elif c == "," and depth == 0:
			break
		else:
			out += c
		k += 1
	return out.strip_edges()


## NO_RAW_ID —— 本门禁的主判据。
func _seg2_coverage() -> void:
	print("── ② 全仓覆盖: 每个 `_spawn_summon(` 调用点都带中文 label ──")
	var files: Array = _files(SCAN_ROOT)
	_ok("② ★分母: 扫到 %d 个 .gd(0 个 = 目录读不到, 下面全是空检查)" % files.size(),
		files.size() >= 60, "%d 个" % files.size())
	var sites: Array = []           # [{file, line, kind, expr}]
	for f in files:
		var src: String = FileAccess.get_file_as_string(str(f))
		if src == "":
			continue
		var i := 0
		while true:
			i = src.find(CALL, i)
			if i < 0:
				break
			var ls: int = src.rfind("\n", i) + 1
			var le: int = src.find("\n", i)
			var line: String = src.substr(ls, (le - ls) if le > ls else -1)
			var stripped: String = line.strip_edges()
			## 排掉函数定义本身与注释行 —— 它们不是调用点
			if stripped.begins_with("func ") or stripped.begins_with("#"):
				i += CALL.length()
				continue
			var op: int = i + CALL.length() - 1
			var call: String = _call_text(src, op)
			var kind := ""
			var q1: int = call.find("\"", call.find(",") + 1)
			if q1 > 0:
				var q2: int = call.find("\"", q1 + 1)
				if q2 > q1:
					kind = call.substr(q1 + 1, q2 - q1 - 1)
			sites.append({"file": str(f), "line": src.count("\n", 0, i) + 1,
				"kind": kind, "expr": _label_expr(call)})
			i = op + call.length()
	print("    [分母] 扫到 %d 个 `_spawn_summon(` 调用点" % sites.size())
	for s in sites:
		print("      %s:%d  kind=%s  label=%s" % [str((s as Dictionary)["file"]),
			int((s as Dictionary)["line"]), str((s as Dictionary)["kind"]),
			str((s as Dictionary)["expr"]) if str((s as Dictionary)["expr"]) != "" else "<缺>"])
	_ok("② ★★分母: 调用点数 ≥ %d(扫不到就是判据坏了, 不是代码干净)" % MIN_CALL_SITES,
		sites.size() >= MIN_CALL_SITES, "%d 个" % sites.size())

	var missing: Array = []
	var latin: Array = []
	var dyn: Array = []
	for s in sites:
		var sd: Dictionary = s
		var e: String = str(sd["expr"])
		var where := "%s:%d(%s)" % [str(sd["file"]).get_file(), int(sd["line"]), str(sd["kind"])]
		if e == "":
			missing.append(where)
			continue
		if e.begins_with("\"") and e.ends_with("\"") and e.length() >= 2:
			var lit: String = e.substr(1, e.length() - 2)
			if _has_latin(lit):
				latin.append("%s=%s" % [where, lit])
		else:
			dyn.append(e)
			if not DYNAMIC_LABELS.has(e):
				latin.append("%s=%s(非字面量且不在白名单)" % [where, e])
	_ok("② ★★★**每一个**调用点都传了 `label` —— 台账 ⑸ 就是漏了一个",
		missing.is_empty(), "漏传的: %s" % str(missing))
	_ok("② ★★★没有任何 label 含 ASCII 字母(屏幕上不许出现英文内部名)",
		latin.is_empty(), str(latin))
	## ★动态 label 也得有人管: 白名单里那条的**运行期取值**逐档验一遍。
	_ok("② ★分母: 非字面量 label 恰好 %d 处(白名单 %d 条)" % [dyn.size(), DYNAMIC_LABELS.size()],
		dyn.size() == DYNAMIC_LABELS.size(), str(dyn))
	var stage_bad: Array = []
	for i in range(AE.STAGES.size()):
		var nm := str(AE.stage(i).get("name", ""))
		if nm == "" or _has_latin(nm):
			stage_bad.append("%d=%s" % [i, nm])
	_ok("② ★分母: 斧头进化共 %d 档(动态 label 的全部取值)" % AE.STAGES.size(),
		AE.STAGES.size() >= 5, "%d 档" % AE.STAGES.size())
	_ok("② ★★动态 label `AE.stage(si)[\"name\"]` 的 %d 档取值全无英文" % AE.STAGES.size(),
		stage_bad.is_empty(), str(stage_bad))


# ══════════════════════════════════════════════════════════════════════
# ③ 端到端: 亡灵羁绊的真入口 → 战报那一行写的是「亡魂」
# ══════════════════════════════════════════════════════════════════════
func _seg3_wraith() -> void:
	print("── ③ 端到端: 亡灵真入口 on_death → 战报取名 ──")
	var sp: Array = []
	for e in DataRegistry.phase2_equipment:
		if Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == "灵物":
			sp.append(str((e as Dictionary).get("id", "")))
		if sp.size() >= 2:
			break
	_ok("③ ★分母: 拿到 %d 件灵物(不够 2 件就激活不了亡灵, 下面是空检查)" % sp.size(),
		sp.size() >= 2, "%d 件" % sp.size())
	var eqs: Array = []
	for i in sp:
		eqs.append({"id": str(i), "star": 1})
	var carrier := _mk("left")
	carrier["equips"] = eqs
	var dead := _mk("left")
	_s._units.clear()
	_s._units.append_array([carrier, dead])
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	dead["alive"] = false
	var n0: int = _s._units.size()
	_s._spirit_syn.on_death(dead)
	_ok("③ ★分母: 真入口 `on_death` 确实生出了一只亡魂(没生出来就没什么可验的)",
		_s._units.size() == n0 + 1, "%d → %d" % [n0, _s._units.size()])
	if _s._units.size() <= n0:
		return
	var wr = _s._units[_s._units.size() - 1]
	_ok("③ ★分母: 它真的是亡魂(`_is_wraith`), 不是别的召唤物",
		wr is Dictionary and bool((wr as Dictionary).get("_is_wraith", false)))
	_ok("③ ★★★结算战报那一行写的是「亡魂」, 不是 `wraith`",
		wr is Dictionary and _s._st_name(wr) == "亡魂",
		"_st_name=%s" % (_s._st_name(wr) if wr is Dictionary else "<null>"))
	_ok("③ ★★战报那一行一个 ASCII 字母都没有",
		wr is Dictionary and not _has_latin(_s._st_name(wr)),
		_s._st_name(wr) if wr is Dictionary else "")
	## ★`_st_name` 的兜底是 `u["id"]`, 而召唤体的 id 是 `_summon_<kind>` —— **也是英文**。
	##   所以"名字对了"这件事不能靠兜底, 得靠 `name` 字段本身。单列一条说明这件事。
	_ok("③ ★召唤体的 `id` 是英文(`_summon_wraith`) ⇒ 名字只能靠 `name` 字段, 兜底救不了",
		wr is Dictionary and _has_latin(str((wr as Dictionary).get("id", ""))),
		str((wr as Dictionary).get("id", "")) if wr is Dictionary else "")
