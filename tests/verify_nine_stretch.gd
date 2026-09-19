extends Node
## verify_nine_stretch — 九宫格框：**中段带周期性装饰的**不许被大倍率拉伸。
##
## ★★为什么有它（2026-09-19，实拍巡检当场看见的）：
##   匹配屏把 **64×64 的 `portrait-frame` 套在 200×200 的控件上** ——
##   九宫格默认 `AXIS_STRETCH_MODE_STRETCH` ⇒ 中段 32px 被拉到 168px = **5.25 倍**，
##   边上那排蓝宝石铆钉被拉扁成细线，实拍只剩四个孤立的金角块。
##   我当时差点把它当成「占位符 / 调试辅助线」去查，其实是**把好素材拉坏了**。
##
## ★★**第一版判据是错的，这里记下来**：我先写成「倍率 > 3 就红」，
##   结果它把 `chip-frame`(21 倍) 和 `panel-frame`(4.68 倍) 也报成问题 ——
##   而那两张**中段就是一条平色带**，拉 21 倍也只是把平色带拉长，一点事没有。
##   按那个阈值去"修"，等于**照假尺子把好素材改坏**（本项目记过这个病）。
##   ⇒ 换形状不是放松：真正该问的是**中段沿拉伸轴有没有周期性装饰**。
##
## ★尺子先拿已知答案的样本标定过（下面 ① 就是那把标定尺，且它自己会红）：
##     portrait-frame CV=0.210 ← 有铆钉
##     chip-frame 0.018 / panel-frame 0.018 / slot-frame 0.023 ← 平色带
##   差一个数量级，阈值 0.10 落在两群正中间，离两边都远。
##
## ★★**显式登记一个缺口，不静默截断**：匹配屏那两张卡是
##   `await create_timer(2.2)` 之后才建的，而 `2.6` 秒就 `change_scene` 进战斗 ——
##   门禁去扫它要么量到空（我第一版就是，150 帧无头 ≈ 几十毫秒真实时间，
##   **用帧数等一个走真实时间的计时器**，正是 CLAUDE.md §3.5.1 记过的坑），
##   要么撞上换场景把整棵测试树掀掉。⇒ 本门禁**不扫匹配屏**；
##   那一处的修复证据是 A/B 实拍（改前边上只剩 3~4 个拉长的斑块，
##   改后是连续的铆钉带），记在 CHANGELOG。
##   本门禁守的是：尺子没漂 + 原语真的能平铺 + 静态屏上没有新的"高 CV 高倍率"框。

const CV_THRESH := 0.10     # 中段变异系数：超过 = 有周期性装饰
const RATIO_MAX := 2.0      # 中段拉伸倍率上限（只对"有装饰"的框生效）
const SCREENS := ["Leaderboard", "Record"]

## 标定样本：[素材, 九宫格边距, CV 下限, CV 上限]。
## ★这四行是**尺子自己的体检**：换了素材/改了边距让某张跨到另一群，这里当场红，
##   而不是等到某天实拍看出来。
const CALIB := [
	["portrait-frame.png", 16, 0.12, 1.00],
	["chip-frame.png", 7, 0.00, 0.06],
	["panel-frame.png", 20, 0.00, 0.06],
	["slot-frame.png", 12, 0.00, 0.06],
]

var _pass := 0
var _fail := 0
var _boxes := 0


func _ok(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [label, extra])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [label, extra])


## 上边中段那条带，沿 x 方向逐列亮度的变异系数（标准差 / 均值）。
## 返回 -1.0 表示量不了（贴图取不到 / 中段宽度 <= 0）—— 调用方要把它当**红**不是当过。
func _mid_cv(tex: Texture2D, m: int) -> float:
	if tex == null:
		return -1.0
	var img: Image = tex.get_image()
	if img == null:
		return -1.0
	var w := img.get_width()
	if w - m * 2 <= 0 or m <= 0:
		return -1.0
	var cols: Array = []
	for x in range(m, w - m):
		var s := 0.0
		for y in range(0, m):
			var c := img.get_pixel(x, y)
			s += (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * c.a
		cols.append(s / float(m))
	var mu := 0.0
	for v in cols:
		mu += float(v)
	mu /= float(cols.size())
	if mu <= 0.0:
		return -1.0
	var var_ := 0.0
	for v in cols:
		var_ += pow(float(v) - mu, 2.0)
	return sqrt(var_ / float(cols.size())) / mu


func _walk(n: Node, out: Array) -> void:
	if n is Control:
		var c := n as Control
		for sname in ["panel", "normal"]:
			if c.has_theme_stylebox_override(sname):
				var sb := c.get_theme_stylebox(sname)
				if sb is StyleBoxTexture:
					out.append([c, sb as StyleBoxTexture, sname])
	for ch in n.get_children():
		_walk(ch, out)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	## ── ① 尺子体检：四张已知答案的框，CV 必须各自留在自己那一群 ──
	for row in CALIB:
		var p := "res://assets/sprites/battlehud/%s" % str(row[0])
		var tex: Texture2D = load(p) if ResourceLoader.exists(p) else null
		_ok("① ★分母: 标定素材在 %s" % str(row[0]), tex != null)
		if tex == null:
			continue
		var cv := _mid_cv(tex, int(row[1]))
		_ok("① 标定 %s 中段 CV 落在 [%.2f, %.2f]" % [str(row[0]), float(row[2]), float(row[3])],
			cv >= float(row[2]) and cv <= float(row[3]), "实得 %.3f" % cv)

	## ── ② 原语真的能平铺，且 `tile` 这个参数真的有用（不是恒真）──
	var US = load("res://scripts/util/ui_skin.gd")
	_ok("② ★分母: ui_skin.gd 载得进来", US != null)
	if US != null:
		var fb := StyleBoxFlat.new()
		var a = US.nine("portrait-frame.png", 16, fb, true)
		var b = US.nine("portrait-frame.png", 16, fb, false)
		_ok("② tile=true ⇒ 中段平铺(TILE_FIT)",
			a is StyleBoxTexture
			and int((a as StyleBoxTexture).axis_stretch_horizontal) == int(StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT)
			and int((a as StyleBoxTexture).axis_stretch_vertical) == int(StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT))
		_ok("② ★tile=false ⇒ 仍是拉伸(证明这个参数真的在起作用, 不是恒真式)",
			b is StyleBoxTexture
			and int((b as StyleBoxTexture).axis_stretch_horizontal) == int(StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH))

	## ── ③ 静态屏普查：有装饰的中段不许被拉过头 ──────────────
	for scn in SCREENS:
		var path := "res://scenes/%s.tscn" % scn
		_ok("③ ★分母: 场景 %s 在" % scn, ResourceLoader.exists(path))
		if not ResourceLoader.exists(path):
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		add_child(inst)
		for _i in range(30):
			await get_tree().process_frame
		var found: Array = []
		_walk(inst, found)
		for item in found:
			var c: Control = item[0]
			var sb: StyleBoxTexture = item[1]
			if sb.texture == null:
				continue
			var tw := float(sb.texture.get_width())
			var th := float(sb.texture.get_height())
			var ml := sb.get_texture_margin(SIDE_LEFT) + sb.get_texture_margin(SIDE_RIGHT)
			var mt := sb.get_texture_margin(SIDE_TOP) + sb.get_texture_margin(SIDE_BOTTOM)
			var sz := c.size
			if tw - ml <= 0.0 or th - mt <= 0.0 or sz.x <= 0.0 or sz.y <= 0.0:
				continue
			_boxes += 1
			var r: float = maxf((sz.x - ml) / (tw - ml), (sz.y - mt) / (th - mt))
			var cv := _mid_cv(sb.texture, int(sb.get_texture_margin(SIDE_TOP)))
			var tiled: bool = int(sb.axis_stretch_horizontal) != int(StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH)
			var bad: bool = cv > CV_THRESH and r > RATIO_MAX and not tiled
			_ok("③ %s·%s 倍率 %.2f · 中段CV %.3f%s" % [scn, c.name, r, cv,
				"(中段是平色带 ⇒ 拉多少都无害)" if cv <= CV_THRESH else "(★中段有装饰)"],
				not bad, "贴图 %.0fx%.0f 控件 %.0fx%.0f" % [tw, th, sz.x, sz.y])
		inst.queue_free()

	## ★★分母：真量到了框。一个都没量到 = 空检查不是通过。
	_ok("③ ★分母: 静态屏上量到 >= 3 个九宫格框", _boxes >= 3, "实得 %d" % _boxes)

	print("  [缺口] 匹配屏不在扫描范围(卡在 2.2s 后才建 · 2.6s 就换场景); ")
	print("         那一处靠 A/B 实拍验证, 见 CHANGELOG v0.19.410。")
	_done()


func _done() -> void:
	var total := _pass + _fail
	if _fail == 0:
		print("ALL PASS — 九宫格中段拉伸 (%d/%d)" % [_pass, total])
	else:
		print("FAILED — 九宫格中段拉伸 (%d/%d)" % [_pass, total])
	get_tree().quit(1 if _fail > 0 else 0)
