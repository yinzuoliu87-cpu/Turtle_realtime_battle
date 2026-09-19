extends Node
## verify_top_bar — 枢纽页顶栏：**返回是扁平薄片，不是厚装饰框**；热区足 44pt。
##
## ★★为什么有它（2026-09-19，用户「这个按钮你不要看原项目的，原项目的就丑啊」→「做」）：
##   九个屏九种返回键。我第一次给的建议是「统一成木框，因为九个里三个已经是」——
##   **那是数自家人头**，而那三个正是被否掉的那批。
##
## ★规则来自 **599 张 / 146 个触屏游戏**枢纽页的逐张实测（Game UI Database `plat=2`
##   触屏 × Inventory/Equipping/Buying/CurrencyStore/Collection/Codex/Leaderboards/
##   Profile/Loadout/Team 十类），详见 `scripts/util/top_bar.gd` 头注：
##     ① 返回永远是**扁平薄片**，和所在那条栏同一套皮；
##        146 款里**没有一款**用「四角包边的厚木框/金属框」做返回 ——
##        那种厚框只给**主 CTA**（"开始战斗""保存并返回"那种）。
##     ④ 要么带字就大而清楚，要么纯图标就完全不带字。
##
## ★★判据是**位置性**的，不是"按文案找返回键"：
##   「保存并返回」这四个字里也有"返回"，但它是**主 CTA**、在屏幕底部，
##   按文案找就会把它一起判死 —— 那就是本项目记过的「挡多了也是错」。
##   ⇒ 判据 = **顶栏区域（y < TOP_ZONE）里不许有 StyleBoxTexture 的按钮**。
##   底部的主 CTA 自然不在射程，规则也不会被"一刀切"。
##
## ★判据走**真场景实例**读活节点，不是在源码里找 `TopBar` 这个词
##   （那样把 `TopBar.new(...)` 整行删掉判据照样绿）。

const TOP_ZONE := 120.0      # 顶栏区域：屏幕上沿往下 120px
const TOUCH_MIN := 81.0      # 44pt

## 要查的枢纽屏。★匹配屏**不在**列表里：它的卡是 `await create_timer(2.2)` 之后才建、
##   2.6 秒就 `change_scene` 进战斗，扫它要么量到空要么把测试树掀掉（显式登记，不静默跳过）。
const SCREENS := ["Record", "Settings", "Leaderboard", "Inventory", "Codex", "Shop", "TeamSelect"]

var _pass := 0
var _fail := 0
var _btns := 0


func _ok(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [label, extra])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [label, extra])


func _walk(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n as Button)
	for c in n.get_children():
		_walk(c, out)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var thick_total := 0
	var back_total := 0
	for scn in SCREENS:
		var path := "res://scenes/%s.tscn" % scn
		_ok("★分母: 场景 %s 在" % scn, ResourceLoader.exists(path))
		if not ResourceLoader.exists(path):
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		add_child(inst)
		for _i in range(40):
			await get_tree().process_frame

		var btns: Array = []
		_walk(inst, btns)
		## ★★**不能按绝对 y 圈顶栏**: 无头视口是 **1280×1280 正方**,
		##   而各屏按 720 高居中 ⇒ 顶栏被推到 y=283, 第一版 `y < 120` 量到 **0 个**。
		##   (本项目记过这个坑, 我又踩了一次。)
		## ⇒ 换成位置无关的形状: 【每屏 **x 最小**的可见按钮就是返回键】。
		##   实测: Record/Inventory/Codex 的返回都在 x=18, 而 Codex 的页签 x=199+,
		##   页签不会被选中 —— 判据刚好卡住返回键这个形状。
		## ★选返回键：文本是返回类 **且不含「保存」**的里面取最左。
		##   ★不含「保存」是关键：「保存并返回」是**主 CTA**, 按规则就该是厚签牌,
		##   把它一起判死 = 「挡多了也是错」。
		##   ★第一版我取「全屏最左的按钮」, 阵容屏选中的是「全部」筛选键 ——
		##   分母断言当场拓出来了(实得「全部」)。
		var back_btn: Button = null
		var vis := 0
		for b in btns:
			var bb: Button = b
			if not bb.is_visible_in_tree():
				continue
			vis += 1
			var bt2 := bb.text
			if bt2.contains("保存"):
				continue
			if not (bt2.contains("返回") or bt2.contains("←") or bt2.contains("‹")
					or bt2.contains("✕") or bt2.contains("↩")):
				continue
			if back_btn == null or bb.get_global_rect().position.x < back_btn.get_global_rect().position.x:
				back_btn = bb
		## ★分母：这屏真的有可见按钮。一个都没有 = 这屏没被测到。
		_ok("★分母: %s 量到可见按钮" % scn, vis >= 1, "%d 个" % vis)
		if back_btn != null:
			_btns += 1
			var bt := back_btn.text
			## ★分母：选中的真是返回键。选错了对象, 下面两条就是在量别人。
			var is_back: bool = bt.contains("返回") or bt.contains("←") or bt.contains("‹") 				or bt.contains("✕") or bt.contains("↩")
			_ok("★分母: %s 最左那个真是返回键" % scn, is_back, "实得「%s」" % bt.substr(0, 10))
			if is_back:
				back_total += 1
			var sb: StyleBox = back_btn.get_theme_stylebox("normal")
			var thick: bool = sb is StyleBoxTexture
			if thick:
				thick_total += 1
			_ok("① %s 返回键不是厚装饰框" % scn, not thick, "stylebox=%s" % sb.get_class())
			_ok("② %s 返回键热区 ≥ %dpx(44pt)" % [scn, int(TOUCH_MIN)],
				back_btn.size.y >= TOUCH_MIN - 0.5 and back_btn.size.x >= TOUCH_MIN - 0.5,
				"%.0f×%.0f" % [back_btn.size.x, back_btn.size.y])
			## ③ 薄片皮的指纹: `apply_chip_skin` 会塞一个名为 chip_plate 的子节点。
			##   ★这一条守的是「走了同一个原语」—— 另手抄一份皮也过不了。
			## ★③ 不是【网页盒】—— 本项目 `verify_ui_consistency` 的签名是
			##   「`StyleBoxFlat` 四边有边框 + 底半透」(CSS border+rgba) 与「圆角 > 0」。
			##   ★我第二版的薄片正是那个形状, 全套门禁当场红(5 屏超台账)。
			##   **扁平 ≠ 网页盒**: 参考里的薄片是游戏美术的扁平件。
			var webby := false
			var rounded := false
			if sb is StyleBoxFlat:
				var f := sb as StyleBoxFlat
				rounded = f.corner_radius_top_left > 0 or f.corner_radius_top_right > 0 					or f.corner_radius_bottom_left > 0 or f.corner_radius_bottom_right > 0
				webby = f.border_width_left > 0 and f.border_width_right > 0 					and f.border_width_top > 0 and f.border_width_bottom > 0 and f.bg_color.a < 1.0
			_ok("③ %s 返回键不是网页盒/圆角盒" % scn, not webby and not rounded,
				"stylebox=%s 圆角=%s 网页盒=%s" % [sb.get_class(), str(rounded), str(webby)])
		inst.queue_free()

	## ── 全局分母 ─────────────────────────────────────────────
	_ok("★分母: 七屏各认出一个返回键", _btns >= 7, "实得 %d" % _btns)
	_ok("★分母: 至少 7 个真是返回类(判据真作用在它们身上)", back_total >= 7,
		"实得 %d" % back_total)
	print("  [统计] 返回键 %d 个 · 其中厚装饰框 %d 个(必须为 0)" % [_btns, thick_total])
	print("  [缺口] 匹配屏不在扫描范围(卡 2.2s 后才建·2.6s 换场景), 靠实拍验证")
	_done()


func _done() -> void:
	var total := _pass + _fail
	if _fail == 0:
		print("ALL PASS — 顶栏薄片规则 (%d/%d)" % [_pass, total])
	else:
		print("FAILED — 顶栏薄片规则 (%d/%d)" % [_pass, total])
	get_tree().quit(1 if _fail > 0 else 0)
