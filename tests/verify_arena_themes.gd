extends Node
## verify_arena_themes.gd — 四版完整地图: **每版九层齐全**, 一个常量切换
##
## ★用户 2026-10-03:「3到4版**完整的地图**包括各种东西背景等等明白吗」
##
## ★★这条判据存在的理由: 「完整」是个会被我自己悄悄缩水的词。
##   少做一层(比如前景框边)画面照样能跑、门禁照样绿, 而我会以为做完了。
##   ⇒ 把九层逐个点名, 缺一个当场红。
##
## ★九层 = `ArenaTheme.REQUIRED_KEYS`:
##   ①地面材质 ②海岸线 ③海 ④周边装饰环 ⑤前景框边 ⑥挡路障碍 ⑦中景地标 ⑧远景背景 ⑨灯光(带灯具) ⑩氛围粒子
##
## ⚠ 本条判据只管**配置齐不齐**与**切换生不生效**。
##   「画出来好不好看」不是它能判的 —— 那由实拍 + `tools/battle_scene_check.py` 五条 + 用户的眼睛。
##   ★不许把"配置齐了"说成"做完了"(memory `fb-verify-artifact-not-steps`)。

const AT := preload("res://scripts/gamedata/arena_theme.gd")

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 四版完整地图 ===")

	# ── ① 分母: 四版都在 ──────────────────────────────────────────
	var all: Array = AT.ALL
	_ok("①★分母: 主题表里有 3~4 版(用户要的是「3到4版」)",
		all.size() >= 3 and all.size() <= 4, "%d 版: %s" % [all.size(), str(all)])
	_ok("①★分母: 每一版在 THEMES 里都有配置",
		all.all(func(k): return (AT.THEMES as Dictionary).has(k)),
		str((AT.THEMES as Dictionary).keys()))

	# ── ② 每版九层齐全 ────────────────────────────────────────────
	var req: Array = AT.REQUIRED_KEYS
	_ok("②★分母: 必填层清单非空(空的话下面那条恒真)", req.size() >= 9, "%d 层" % req.size())
	var missing: Array = []
	for k in all:
		var c: Dictionary = AT.cfg_of(str(k))
		for key in req:
			if not c.has(key):
				missing.append("%s 缺 %s" % [str(k), str(key)])
			elif c[key] is Array and (c[key] as Array).is_empty():
				missing.append("%s 的 %s 是空数组" % [str(k), str(key)])
			elif c[key] is String and str(c[key]) == "":
				missing.append("%s 的 %s 是空串" % [str(k), str(key)])
	_ok("②★★每一版都【九层齐全】(少一层就不算「完整的地图」)",
		missing.is_empty(), str(missing))

	# ── ③ 四版必须真的不一样 ──────────────────────────────────────
	##   不然"四版"只是同一张图改了个名字。按**最能看出区别的三层**比:
	##   地面色 / 海色 / 远景做法。
	var seen_ground: Array = []
	var seen_water: Array = []
	var seen_bg: Array = []
	for k in all:
		var c: Dictionary = AT.cfg_of(str(k))
		seen_ground.append(str(c.get("ground_col", "")))
		seen_water.append(str(c.get("water_col", "")))
		seen_bg.append(str(c.get("bg_kind", "")))
	_ok("③★★四版的【地面色】两两不同(相同 = 不是四张图)",
		_uniq(seen_ground) == all.size(), str(seen_ground))
	_ok("③★★四版的【海色】两两不同", _uniq(seen_water) == all.size(), str(seen_water))
	_ok("③★★四版的【远景做法】两两不同", _uniq(seen_bg) == all.size(), str(seen_bg))

	# ── ④ 海必须比陆暗(参考实测: 咩咩的水是暗的, 靠材质区分可走区不靠亮度) ──
	##   ★这条是**从参考量出来的硬约束**, 不是审美偏好:
	##     我们改前水是全场最亮(实拍海/陆 = 3.2× 的常量, 渲染后 0.37×), 方向一错整张图就"假"。
	var bad_lum: Array = []
	for k in all:
		var c: Dictionary = AT.cfg_of(str(k))
		var g: Color = c.get("ground_col", Color.BLACK)
		var w: Color = c.get("water_col", Color.WHITE)
		if _lum(w) >= _lum(g):
			bad_lum.append("%s 海 %.3f ≥ 陆 %.3f" % [str(k), _lum(w), _lum(g)])
	_ok("④★★每一版的海都比陆暗(靠材质区分可走区, 不靠亮度)",
		bad_lum.is_empty(), str(bad_lum))

	# ── ⑤ 切换真的生效 ────────────────────────────────────────────
	var keep: String = AT.active
	var ok_switch := true
	var seen: Array = []
	for k in all:
		AT.active = str(k)
		var c: Dictionary = AT.cfg()
		seen.append(str(c.get("label", "")))
		if str(c.get("ground_col", "")) != str(AT.cfg_of(str(k)).get("ground_col", "")):
			ok_switch = false
	AT.active = keep
	_ok("⑤★★改一个常量就换一整版(cfg() 跟着 active 走)", ok_switch, str(seen))
	_ok("⑤★分母: 切回来了(测试不许留下污染)", AT.active == keep, AT.active)

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 四版完整地图" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _uniq(a: Array) -> int:
	var s := {}
	for x in a:
		s[x] = true
	return s.size()


func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
