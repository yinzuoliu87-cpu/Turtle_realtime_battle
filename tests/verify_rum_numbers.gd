extends Node
## verify_rum_numbers.gd — 朗姆酒：一份回血只许弹一个数字 + 数值口径 (2026-08-29)
##
## ══════════════════════════════════════════════════════════════════════
##  由来
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-29 实拍:「朗姆酒我为什么会看到**两种绿色数字**？」
##
## 量出来确实是两种（扫截图聚类）：
##   · 青绿 `#06d6a0`（hue 0.46）= `_damage._heal()` 喂进**标准治疗累加器**后弹的
##   · 黄绿 `#7fe39a`（hue 0.38）= 朗姆酒**自己又另存一份** `_rum_heal_acc`，每 0.55 秒再弹一个
##
## **病根**：写那段的人以为 `_heal(..., silent=true)` 的 `silent` 会关掉数字 ——
## **它只关音效**，累加器照样喂。两条通道间隔还差不多（0.55 vs 0.6）⇒ 双份绿字。
##
## ══════════════════════════════════════════════════════════════════════
##  这条门禁守什么
## ══════════════════════════════════════════════════════════════════════
## ★判据落在**真的画到屏上的飘字节点**（`battle._ui_layer` 下的 Label），
##   按**颜色**分类计数 —— 不是"我插的标记被设过"
##   (memory [[fb-gate-must-measure-requirement-not-my-hook]])。
## ★分母：得先证明**真的弹出过治疗数字**，否则"只有一种绿"可能只是一个都没弹
##   (memory [[fb-gate-subject-never-constructed]])。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_rum_numbers.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const PirateSystem := preload("res://scripts/systems/skills/pirate_system.gd")

## 全局统一的治疗数字色（`battle_damage._heal_flush`）。所有回血都该用它。
const HEAL_GREEN := Color("#06d6a0")

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 收集 UI 层里所有"+数字"飘字的颜色（去重成色号 → 出现次数）。
func _collect_float_colors() -> Dictionary:
	var out: Dictionary = {}
	if _s._ui_layer == null:
		return out
	for ch in _s._ui_layer.get_children():
		if not (ch is Label):
			continue
		var t := str((ch as Label).text)
		if not t.begins_with("+"):
			continue
		## 只看纯数字的（"+150 盾" 这类带字的不算治疗数字）
		if not t.substr(1).is_valid_int():
			continue
		var col: Color = (ch as Label).get_theme_color("font_color")
		var key := col.to_html(false)
		out[key] = int(out.get(key, 0)) + 1
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 朗姆酒·一份回血一个数字 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	# ── ① 数值口径（用户 2026-08-29 拍板：护甲 0.7A / 魔抗 0.2A）──
	_ok("★① 魔抗系数 = 0.20 × ATK",
		absf(PirateSystem.RUM_MR_COEF - 0.20) < 0.0001,
		"RUM_MR_COEF=%.3f" % PirateSystem.RUM_MR_COEF)
	_ok("★① 护甲系数 = 0.70 × ATK（0.2 双抗 + 0.5 额外）",
		absf(PirateSystem.RUM_DEF_COEF - 0.70) < 0.0001,
		"RUM_DEF_COEF=%.3f (= MR %.2f + EXTRA %.2f)"
			% [PirateSystem.RUM_DEF_COEF, PirateSystem.RUM_MR_COEF, PirateSystem.RUM_DEF_EXTRA])
	## ★护甲系数是**推导**出来的（`RUM_MR_COEF + RUM_DEF_EXTRA`），不是另写一份 0.7 ——
	##   写死第二份就会漂（memory [[fb-refactor-creates-the-drift-it-removes]]）。
	_ok("★① 护甲系数是推导的不是手写的第二份",
		absf(PirateSystem.RUM_DEF_COEF - (PirateSystem.RUM_MR_COEF + PirateSystem.RUM_DEF_EXTRA)) < 1e-9)
	_ok("★① 每秒回 4% 最大生命 × 6 秒",
		absf(PirateSystem.RUM_HOT_PCT - 0.04) < 0.0001 and absf(PirateSystem.RUM_SEC - 6.0) < 0.0001,
		"%.0f%%/秒 × %.0f 秒" % [PirateSystem.RUM_HOT_PCT * 100.0, PirateSystem.RUM_SEC])

	# ── ② ★★真放一次朗姆酒，数屏上弹出的治疗数字有几种颜色 ──
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var pir: Dictionary = _s._spawn._make_unit("pirate", "left", c + Vector2(-120, 0))
	pir["no_basic"] = true
	pir["no_move"] = true
	pir["maxHp"] = 4000.0
	pir["hp"] = 1000.0            # ★留出回血余量 —— 满血时 _heal 实回 0, 一个数字都不弹
	pir["atk"] = 100.0
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	foe["maxHp"] = 1.0e8
	foe["hp"] = 1.0e8
	foe["no_basic"] = true
	foe["no_move"] = true
	_s._units.clear()
	_s._units.append(pir)
	_s._units.append(foe)
	_s._edit_mode = false
	_s._over = false

	var hp0: float = float(pir["hp"])
	_s._pirate_sys._sk_pirate_rum(pir)
	_ok("★分母: 朗姆酒真的生效了(rum_until 在未来)",
		float(pir.get("rum_until", 0.0)) > _s._t,
		"rum_until-_t = %.2f 秒" % (float(pir.get("rum_until", 0.0)) - _s._t))

	## ★墙钟等整个 HoT 跑完（CLAUDE.md §3.5：帧数在无头下每帧只推 1ms）。
	##   期间**每帧**扫一次 UI 层，把见过的飘字颜色都记下来 ——
	##   飘字 1.5 秒就淡出销毁，只在结束时看一眼会全错过。
	var seen: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 7000:
		for k in _collect_float_colors().keys():
			seen[str(k)] = int(seen.get(str(k), 0)) + 1
		await get_tree().process_frame

	var healed: float = float(pir["hp"]) - hp0
	_ok("★★分母: 真的回血了 %.0f 点(没回血就一个数字都不会弹 = 空检查)" % healed, healed > 10.0)
	_ok("★★分母: 真的弹出过治疗数字(见到 %d 种颜色)" % seen.size(), seen.size() >= 1,
		str(seen.keys()))

	# ★★核心判据：治疗数字**只许有一种颜色**，且必须是全局统一的那个
	_ok("★★② 治疗数字只有一种颜色(用户看到两种 = 同一份回血被显示两遍)",
		seen.size() == 1,
		"看到 %d 种: %s" % [seen.size(), str(seen.keys())])
	_ok("★★② 那一种就是全局统一的治疗绿 #%s" % HEAL_GREEN.to_html(false),
		seen.has(HEAL_GREEN.to_html(false)),
		"看到 %s" % str(seen.keys()))

	# ── ③ 朗姆酒不许再自己造一份治疗数字（源码守卫）──
	## ★运行时那条已经很强了；这条是**防再犯**：谁又在朗姆酒那段里加飘字就当场红。
	var src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("★分母: 主文件源码读到了(空串会让下面变假 PASS)", src.length() > 1000)
	## ★判据卡的是【带 `_float_text` 的那一行里出现这个色号】—— 而不是"文件里出现过"。
	##   头注里为了讲清病根写了色号, 用后者会把**说明文字**判成 bug
	##   (第一版就是这么红的; memory [[fb-judge-must-fit-the-shape]]: 宽一格造假 bug)。
	var bad := 0
	var n_lines := 0
	for ln in src.split(String.chr(10)):
		n_lines += 1
		if ln.contains("_float_text") and ln.contains("7fe39a"):
			bad += 1
	_ok("★分母: 逐行扫了 %d 行(N=0 是空检查)" % n_lines, n_lines > 100)
	_ok("★③ 朗姆酒不许再自造治疗飘字(带 _float_text 的行里不许出现 7fe39a)",
		bad == 0, "命中 %d 行" % bad)

	_done()


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 12:
		print("  [FAIL] ★分母: 断言只有 %d 条(<12) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 朗姆酒数字与数值" if _fail == 0 else "FAIL x%d — 朗姆酒数字与数值" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
