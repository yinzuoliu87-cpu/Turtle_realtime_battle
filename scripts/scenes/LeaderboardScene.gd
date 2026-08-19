extends Control

## LeaderboardScene — V2 排行榜 (阶段5 MVP, 设计§五/§十三). 按本赛季击杀龟蛋数降序.
## MVP: 本地 ghost 池各阵容的 season_eggs_killed + 自己, 排序展示. 真后端复算防作弊=上线版.
##
## ═══ 2026-08-19 实拍复看(1560×720 真渲染截图)修掉的四件事 ═══
## ① 整屏还是「深色圆角矩形 + 2px 细边」—— 背包/图鉴/选龟早就换成金属九宫格了, 只剩这屏没跟上。
## ② **榜上找不到自己**: `Backend.leaderboard()` 把自己混进去按蛋数降序切前 30 条,
##    而本屏只画得下 13 行 —— 蛋数并列 0 的时候自己排在哪儿全看排序稳定性, 实拍那张
##    13 行里**一个「◀ 你」都没有**。排行榜看不到自己 = 这屏白开。⇒ 自己那行【钉住】。
## ③ 最后一行**压在金属边带上**: 原来 `y > 540` 才 break, 末行标签 532+28=560 = 面板高度,
##    正好压满下边框(金属框实测边带 13px, 比原来的 2px 细边更吃亏)。⇒ 行数按内容区算出来。
## ④ 返回键 120×44 = **24pt**, 低于 44pt 触控下限(视口 720 ↔ 390pt ⇒ 44pt = 81px);
##    而且是 Godot 默认皮。⇒ UISkin.button + 81 高。

const W := 1280.0
const PANEL_W := 760.0
## 内边距要 > panel-frame 贴图**实测边带 13px**(不是九宫格配置的 20 —— 那是"从哪切开",
## 不是"画了多宽的边"; verify_ui_consistency 的 `_band_of` 就是这么量的)。
const PAD := 22.0
const ROW_H := 40.0
const ROW_TOP := 68.0
## 底部给"提示行"留一行的位置 —— 空数据态/自己 0 蛋时要说人话, 不能只剩一屏 0。
const FOOT_H := 30.0
const ROWS := 11
## ★面板高度是【按内容反算】的, 不是拍脑袋: 表头到首行 68 + 11 行×40 + 提示行 30 + 下内边距。
##   第一版随手写 584, 于是 floor(可用高/行高) 之后余下一条 24px 的空带子夹在末行和提示行之间。
const PANEL_H := ROW_TOP + float(ROWS) * ROW_H + FOOT_H + PAD
const PANEL_X := (W - PANEL_W) / 2.0
const PANEL_Y := 86.0
const Backend = preload("res://scripts/net/backend.gd")

func _ready() -> void:
	_bg()

	var title := Label.new(); title.text = "🏆 排行榜 · 本赛季击杀龟蛋数"
	title.add_theme_font_size_override("font_size", 30); title.add_theme_color_override("font_color", Color("#ffd93d"))
	title.position = Vector2(W / 2.0 - 300, 22); title.size = Vector2(600, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(title)

	var back := Button.new(); back.text = "← 返回"; back.add_theme_font_size_override("font_size", 20)
	## ★44pt 触控下限 = 81px(视口恒 720 高 ↔ iPhone 横屏 390pt ⇒ 1pt = 1.846px)。
	##   原来写 120×44 是把「44pt」当成了 44 像素 —— 实际只有 24pt。
	var _m: Vector4 = SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	back.position = Vector2(maxf(20.0, _m.x), maxf(18.0, _m.y))
	back.custom_minimum_size = Vector2(150.0, 81.0)
	back.size = Vector2(150.0, 81.0)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	UISkin.button(back, Color("#9fb6c9"))   # 金属签牌皮(原来是 Godot 默认圆角纯色)
	add_child(back)

	var pool := Backend.load_pool()
	## ★limit 必须给【全量】(原来是 30) —— `Backend.leaderboard()` 是**排完序再切**的,
	##   开局大家蛋数并列 0 时自己经常落在第 30 名开外, **在本屏拿到 rows 之前就已经被切没了**,
	##   于是下面的"钉住自己"根本无从谈起(第一版实拍复看: 榜上仍旧一个「◀ 你」都没有)。
	##   拿全量在这里自己切, 名次 = 全量下标 + 1, 才是真名次。
	var rows := Backend.leaderboard(pool, "我 (玩家)", int(GameState.season_eggs_killed), 1 << 30)

	# 表面板 —— 金属九宫格(和背包/图鉴/战绩同一张 panel-frame)。冷蓝调走 modulate,
	# ★ modulate 别超 1.3: 过了会把框芯冲亮、金属细节糊平(实拍确认过)。
	var panel := Panel.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.12, 0.18, 0.9); psb.border_color = Color("#2e4a5e")
	psb.set_border_width_all(2); psb.set_corner_radius_all(12)
	var ptex := UISkin.nine("panel-frame.png", 20, psb)
	if ptex is StyleBoxTexture:
		(ptex as StyleBoxTexture).modulate_color = Color(0.74, 0.94, 1.14, 1.0)
	panel.add_theme_stylebox_override("panel", ptex)
	panel.position = Vector2(PANEL_X, PANEL_Y); panel.size = Vector2(PANEL_W, PANEL_H)
	add_child(panel)

	# 表头 + 一条分隔线(原来表头和第一行只隔 38px 且没有任何分界, 整块读起来是一堵字墙)
	_row_labels(panel, PAD, "#58d3ff", "排名", "玩家", "击杀蛋数", true)
	var sep := ColorRect.new()
	sep.color = Color(0.35, 0.55, 0.70, 0.55)
	sep.position = Vector2(PAD, ROW_TOP - 12.0); sep.size = Vector2(PANEL_W - PAD * 2.0, 2)
	panel.add_child(sep)

	# ★能画几行是【算出来】的, 不是写死的阈值 —— 写死那次末行正好压在金属边带上。
	var body_h: float = PANEL_H - PAD - FOOT_H - ROW_TOP
	var cap: int = maxi(1, int(floor(body_h / ROW_H)))
	print("[LB] rows=%d cap=%d body_h=%.0f" % [rows.size(), cap, body_h])   # 分母: 0 行 = 空检查
	var self_idx := _self_index(rows)
	var shown := _pick_rows(rows, cap, self_idx)

	var y := ROW_TOP
	for item in shown:
		var idx: int = int(item)
		if idx < 0:                     # -1 = 省略号占位(自己被钉到末行时, 中间断开的地方)
			var gap := Label.new(); gap.text = "⋯"
			gap.add_theme_font_size_override("font_size", 18)
			gap.add_theme_color_override("font_color", Color("#4a5a6b"))
			gap.position = Vector2(PAD, y); gap.size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 6.0)
			gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			panel.add_child(gap)
			y += ROW_H
			continue
		var r: Dictionary = rows[idx]
		var is_self: bool = bool(r.get("is_self", false))
		if is_self:
			# 自己那行套金属小签牌(原来是一块半透明黄色 ColorRect, 且高 36 会探出面板 4px)
			var hl := Panel.new()
			var hsb := StyleBoxFlat.new()
			hsb.bg_color = Color(1.0, 0.85, 0.24, 0.14); hsb.set_corner_radius_all(6)
			var htex := UISkin.nine("chip-frame.png", 7, hsb)
			if htex is StyleBoxTexture:
				(htex as StyleBoxTexture).modulate_color = Color(1.18, 1.02, 0.52, 1.0)
			hl.add_theme_stylebox_override("panel", htex)
			hl.position = Vector2(PAD - 6.0, y - 5.0)
			hl.size = Vector2(PANEL_W - (PAD - 6.0) * 2.0, ROW_H - 4.0)
			panel.add_child(hl)
		elif idx % 2 == 1:
			var zebra := ColorRect.new()   # 斑马纹: 纯色块, 不带边 ⇒ 不是"网页盒"
			zebra.color = Color(1, 1, 1, 0.035)
			zebra.position = Vector2(PAD - 6.0, y - 5.0)
			zebra.size = Vector2(PANEL_W - (PAD - 6.0) * 2.0, ROW_H - 4.0)
			panel.add_child(zebra)
		_row_labels(panel, y, "#ffd93d" if is_self else "#dfe9f2",
			"#%d" % (idx + 1), str(r.get("name", "?")) + ("  ◀ 你" if is_self else ""),
			str(int(r.get("eggs", 0))), false)
		y += ROW_H

	# 底部提示行 —— 三种态各说各的话(原来只有"池子只有我一个"那一种才出提示)。
	var hint := Label.new()
	if rows.size() <= 1:
		hint.text = "（打几局上传阵容后, 这里会出现更多对手排名）"
	elif self_idx >= 0 and int((rows[self_idx] as Dictionary).get("eggs", 0)) <= 0:
		hint.text = "（打碎对面的龟蛋就能上分 —— 你本赛季还是 0 颗）"
	else:
		hint.text = "（每场结算后上传, 榜单按本赛季击杀龟蛋数排）"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("#6b7b8c"))
	hint.position = Vector2(PAD, PANEL_H - PAD - FOOT_H + 4.0)
	hint.size = Vector2(PANEL_W - PAD * 2.0, FOOT_H - 6.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hint)
	# ★UI 双端适配(用户2026-08-01「有些画面都没有居中」): 把内容装进 1280×720 设计框并居中于真实视口。
	#   本屏原先直接按设计坐标画在视口(0,0) → 21:9 上内容整体坐在左边 200px(审计器实测)。
	#   ★必须放在 _ready 最后 —— UIFrame 收编的是【已经建出来的】子节点。
	#   (异步晚建的节点由 UIFrame._process 的孤儿收编兜住。)
	UIFrame.attach(self)


## 背景 = 主菜单那张平铺底(深绿 #1a3a2a + menu-bg-tile + 暗渐变遮罩)。
##
## ★这不是"给新内容挑素材", 是**补上一处漏做的统一**: 主菜单/图鉴/战绩/设置四屏早就是这张底了,
##   只有本屏还是一块纯 #0a1622 —— 实拍看就是"一片空的深色屏"。
##   (素材铁律说的是"新内容一律新素材"; 这里连新内容都不是, 就是同一层壳没铺全。)
func _bg() -> void:
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)
	add_child(base)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		tile.texture = PreloadCache.menu_bg_tile_tex()   # 复用缓存 512² 纹理(resize 只做一次)
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vp := get_viewport_rect().size
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
		var drift := tile.create_tween().set_loops()
		drift.tween_property(tile, "position", Vector2(0, 0), 25.0).from(Vector2(-512, -512)).set_trans(Tween.TRANS_LINEAR)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0.031, 0.047, 0.078, 0.20),
		Color(0.031, 0.047, 0.078, 0.32),
		Color(0.031, 0.047, 0.078, 0.46),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	gt.width = 8; gt.height = 128
	var ov := TextureRect.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt
	ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)


## 自己在 rows 里的下标(没有 = -1)。
func _self_index(rows: Array) -> int:
	for i in range(rows.size()):
		if bool((rows[i] as Dictionary).get("is_self", false)):
			return i
	return -1


## 挑出要画的行下标; `-1` 表示"这里插一个省略号"。
##
## ★为什么要这一步: 榜单能取 30 条, 面板只画得下 12 行左右。原来是"画到装不下就 break",
##   于是**自己排在第 13 名开外时整屏看不到自己** —— 而蛋数并列 0 的开局,
##   自己排第几完全看排序稳定性(实拍那张就一个「◀ 你」都没有)。
##   ⇒ 自己不在可见段里就把**末行让给自己**, 中间用 ⋯ 断开(通用榜单做法)。
func _pick_rows(rows: Array, cap: int, self_idx: int) -> Array:
	var out: Array = []
	var n: int = mini(rows.size(), cap)
	if self_idx < 0 or self_idx < cap:
		for i in range(n):
			out.append(i)
		return out
	for i in range(maxi(0, cap - 2)):
		out.append(i)
	out.append(-1)
	out.append(self_idx)
	return out


func _row_labels(parent: Control, y: float, color: String, c1: String, c2: String, c3: String, header: bool) -> void:
	var fs := 15 if header else 18
	var xs := [PAD + 6.0, PAD + 110.0, PAD + 500.0]
	var txts := [c1, c2, c3]
	var ws := [100.0, 380.0, 210.0]
	for i in range(3):
		var l := Label.new(); l.text = txts[i]
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", Color(color))
		l.position = Vector2(float(xs[i]), y); l.size = Vector2(float(ws[i]), ROW_H - 12.0)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if i == 1:
			## ghost 名来自玩家自定义 profile, 长度不受控 —— 截断加省略号, 别让它糊到蛋数列上。
			l.clip_text = true
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if i == 2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		parent.add_child(l)
