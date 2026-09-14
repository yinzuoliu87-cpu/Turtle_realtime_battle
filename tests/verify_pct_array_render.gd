extends Node
## verify_pct_array_render.gd — 带 % 的【数组】占位符必须逐项 ×100(第九批 D1)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来 (2026-09-15, 077~086 调查)
## ══════════════════════════════════════════════════════════════════
## 084 手半剑的文案在游戏里显示成「获得 0.03/0.06/0.1% 增伤」, 实际是 3/6/10%。
## 根因: `SkillText.const_of` 只对【标量】乘 100, 数组分支原样输出。
## 而文案快照审计 `tools/text_golden.py` 用的是 Python 抄的一份渲染逻辑 ——
## 它遇到数组 `float("0.03/0.06/0.1")` 报错, 被 except 接住后**原样留下占位符**,
## 快照里存的是没展开的 `{C:EqBladeBatch.HH_MELEE_AMP%}`, 于是这条审计从来没看见。
## ⇒ 这条门禁在 Godot 里走**游戏自己的渲染入口**, 不信任何抄本。
##
## ★判据:
##   ① 三个已知数组型 % 占位符渲染出的数(期望值写死成文案原意, 不读被测常量)
##   ② 扫两个 json 里【全部】`{C:类.常量%}`: 常量是数组的, 渲染结果必须逐项等于 ×100
##      (分母: % 占位符总数 / 其中数组个数)
##   ③ 084 手半剑全文里写的是「3/6/10% 增伤」「3/6/10% 减伤」(走图鉴全文入口)
## ★★② 第一版用正则扫「小数/小数/…%」这个形状 —— **判据形状错了**:
##   091 远古龟甲片「0.1/0.15/0.2% 最大生命值」本来就是真的很小的百分比, 当场误报。
##   ⇒ 不猜形状, 逐个查占位符(memory fb-judge-must-fit-the-shape)。
const SkillText := preload("res://scripts/util/skill_text.gd")

## 2026-09-15 全仓扫过: 418 个带 % 的占位符里数组只有这 3 个, 全部存小数比例
const WANT := {
	"EqBladeBatch.HH_MELEE_AMP%": "3/6/10",
	"EqBladeBatch.HH_RANGED_DR%": "3/6/10",
	"ChestSystem.CHEST_HEAL_PCT%": "8/8/11/11/15",
}

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s" % t)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


## 期望: 数组逐项 ×100, 整数不带 .0 —— 这是文案「N%」的原意, 独立写一遍, 不调被测函数
func _want_pct(arr: Array) -> String:
	var parts: PackedStringArray = []
	for x in arr:
		var f: float = float(x) * 100.0
		parts.append(str(int(roundf(f))) if is_equal_approx(f, roundf(f)) else str(f))
	return "/".join(parts)


func _consts_of(cls: String) -> Dictionary:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == cls:
			var path := str(c.get("path", ""))
			if path != "" and ResourceLoader.exists(path):
				var scr := load(path) as Script
				if scr != null:
					return scr.get_script_constant_map()
	return {}


func _ready() -> void:
	await get_tree().process_frame
	print("=== 带 % 的数组占位符: 逐项 ×100 (第九批 D1) ===")

	# ── 自检: 期望函数本身对已知样本给出已知答案 ──
	_ok("自检·期望函数: [0.03, 0.06, 0.10] → 3/6/10 · [0.125] → 12.5",
		_want_pct([0.03, 0.06, 0.10]) == "3/6/10" and _want_pct([0.125]) == "12.5",
		"期望函数错了 ⇒ ② 的比对没有意义")

	# ── ① 三个已知数组型 % 占位符 ──
	for ref in WANT.keys():
		var got: String = SkillText.const_of(ref)
		_ok("① {C:%s} 渲染成 %s(实测 %s)" % [ref, WANT[ref], got], got == WANT[ref],
			"数组没逐项 ×100 ⇒ 玩家看到的是小数")

	# ── ② 两个 json 里全部 % 占位符 ──
	var re := RegEx.new()
	re.compile("\\{C:([A-Za-z_][A-Za-z0-9_]*)\\.([A-Za-z_][A-Za-z0-9_]*)%\\}")
	var seen: Dictionary = {}
	for jp in ["res://data/phase2-equipment.json", "res://data/pets.json"]:
		var fa := FileAccess.open(jp, FileAccess.READ)
		if fa == null:
			continue
		for m in re.search_all(fa.get_as_text()):
			seen[m.get_string(1) + "." + m.get_string(2)] = true
		fa.close()
	var arrays := 0
	var bad: Array = []
	for key in seen.keys():
		var dot: int = str(key).rfind(".")
		var v = _consts_of(str(key).substr(0, dot)).get(str(key).substr(dot + 1), null)
		if not (v is Array):
			continue
		arrays += 1
		var got2: String = SkillText.const_of(str(key) + "%")
		var want2: String = _want_pct(v as Array)
		if got2 != want2:
			bad.append("%s: 实测 %s / 应为 %s" % [key, got2, want2])
	_ok("★分母: 两个 json 里带 %% 的常量占位符 %d 个, 其中数组 %d 个" % [seen.size(), arrays],
		seen.size() >= 400 and arrays >= 3, "扫到的太少 ⇒ ② 扫了个寂寞")
	_ok("② 全部数组型 %% 占位符都逐项 ×100(不一致 %d 个 %s)" % [bad.size(), str(bad.slice(0, 4))],
		bad.is_empty(), "")

	# ── ③ 084 全文(图鉴详情入口) ──
	var hh_full := ""
	for e in DataRegistry.phase2_equipment:
		if e is Dictionary and str((e as Dictionary).get("id", "")) == "p2eq_084":
			hh_full = SkillText.equip_full(e)
	_ok("③ 084 手半剑全文里写的是「3/6/10% 增伤」与「3/6/10% 减伤」",
		hh_full.contains("3/6/10% 增伤") and hh_full.contains("3/6/10% 减伤"),
		"没找到 ⇒ 084 的文案不在场或还是小数: %s" % hh_full.substr(0, 120))

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
