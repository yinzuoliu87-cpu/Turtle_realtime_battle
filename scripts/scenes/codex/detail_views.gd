class_name CodexDetail
extends RefCounted
const SkillTextRef := preload("res://scripts/util/skill_text.gd")   # 三档数值按★1高亮(与商店/背包同一份)
const _EquipPoolRef := preload("res://scripts/gamedata/equip_pool.gd")   # NO_STAR: 不升星的件不给选档
const _EquipStatsRef := preload("res://scripts/gamedata/equip_stats.gd")   # 属性一排按选中档取值
## 图鉴·右栏详情视图(龟/装备/羁绊(类型)/状态/规则/小将 13渲染函数)
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

func _show_minion(kind: String) -> void:
	host._clear_detail()
	var mi: Dictionary = host.MINION_INFO.get(kind, {})
	if mi.is_empty():
		return
	## ★2026-10-08 两栏, 与龟页同一套: 左栏立绘 + 名字/签牌 + 属性方块条, 右栏说明 + 技能 + 被动。
	host._add_image(95, 100, "res://assets/sprites/pets/%s" % mi["img"], 160, 160, true)
	## ★★2026-09-27 抬头与龟页同一套: 名字 + 一排签牌, 不再是「深海小将   近战」这种
	##   "字段名 + 值"的两段式(用户: 图鉴「全是 ai 味和网页味, 文字语言也是」)。
	_left_header(str(mi["name"]), [{"kind": "tag", "text": "深海小将", "color": "#9fb6c9"},
		{"kind": "tag", "text": str(mi["role"]), "color": "#58d3ff"}])
	# 属性 7 行 (Lv1 值) —— 与龟页共用 _stat_rows, 不在这里另摆一套表格
	var rows = [
		{"key": "hp", "label": "生命", "disp": str(mi["hp"]), "color": "#06d6a0"},
		{"key": "atk", "label": "攻击", "disp": str(mi["atk"]), "color": "#ff9f43"},
		{"key": "def", "label": "护甲", "disp": str(mi["def"]), "color": "#ffd93d"},
		{"key": "mr", "label": "魔抗", "disp": str(mi["mr"]), "color": "#4dabf7"},
		## 顺序与龟页同一套(…魔抗 / 移速 / 每秒攻击 / 射程)。
		{"key": "move", "label": "移速", "disp": str(mi["spd"]), "color": "#8fd4ff"},
		## ★与龟页同一个单位(「每秒攻击」= 1 / 攻击间隔), 原来这里单独写「间隔 0.85 秒」(2026-10-07 H)。
		{"key": "aspd", "label": "每秒攻击", "disp": "%.2f" % (1.0 / maxf(0.01, float(mi["interval"]))), "color": "#ff9ecb"},
		{"key": "range", "label": "射程", "disp": str(mi["range"]), "color": "#d6e4f0"},
	]
	_col_divider(_stat_rows(rows))
	## 两句说明改口语: 原文「非统领单位 · 不可选入阵容 · 由系统补位生成」「…×1.05 复利成长,
	## 双抗为定值」—— "非统领单位""复利成长""定值"都是开发者/说明书用词, 不是游戏里的话。
	## (两栏后挪到右栏顶: 左栏抬头只有 180 宽, 放不下这两句)
	host._add_text(RCOL_X + 4.0, 26, "不可编入阵容 · 开战时自动登场", 13, "#7a8a96", 0.0, 0.5)
	host._add_text(RCOL_X + 4.0, 48, "每级生命与攻击 ×1.05，护甲与魔抗不变", 13, "#7a8a96", 0.0, 0.5)
	# 技能 + 被动
	var y = 72.0
	## ★2026-10-07 H: 技能抬头与龟页同一套 —— [技能图标] 名字 + 「主动 · 龟能 N」(龟页卡片 chip 同一句式);
	##   原来是「技能 · 人体浪板  (120 龟能)」, 而 MinionCodex 里新加的 skill_icon 图鉴一直没画。
	var _sx: float = RCOL_X
	var _sic: String = str(mi.get("skill_icon", ""))
	if _sic.ends_with(".png") and ResourceLoader.exists("res://assets/sprites/%s" % _sic):
		host._add_image(RCOL_X + 16.0, y + 12.0, "res://assets/sprites/%s" % _sic, 32, 32)
		_sx = RCOL_X + 40.0
	var _snl: Variant = host._add_text(_sx, y + 12.0, str(mi["skill_name"]), 17, "#ffd93d", 0.0, 0.5, true)
	var _scx: float = _sx + 90.0
	if _snl is Control:
		_scx = _sx + (_snl as Control).get_combined_minimum_size().x + 14.0
	host._add_text(_scx, y + 12.0, "主动 · 龟能 %d" % int(mi["skill_cost"]), 13, "#06d6a0", 0.0, 0.5)
	y += 34.0
	y = _minion_body(str(mi["skill_desc"]), y) + 18.0
	for pv in mi.get("passives", []):
		host._add_text(RCOL_X, y, "被动 · %s" % str(pv["name"]), 17, "#58d3ff", 0.0, 0.0, true)
		y += 28.0
		y = _minion_body(str(pv["desc"]), y) + 16.0

## 一段正文(自动换行), 返回下一段该起的 y.
func _minion_body(txt: String, y: float) -> float:
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(RCOL_X, y)
	rt.custom_minimum_size = Vector2(_rw(), 0)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.text = txt
	host.detail.add_child(rt)
	# ★2026-08-15 改成【问它自己占多高】, 不再按字数估行。
	#   原来是 `ceilf(txt.length() / 62.0) * 19` —— 62 这个"每行几个全角字"是照 13px 字号拍的,
	#   字号一改(13→16)整套间距就全错; 而且 BBCode 标记也被算进了 length()。
	#   同一个位置 2026-08-01 已经栽过一次(写成 host.ceilf ⇒ SCRIPT ERROR ⇒ return 永不执行 ⇒
	#   每段正文拿到同一个 y、全叠在一起, 用户报「精英小将的描述都挤在一块」)。
	#   get_combined_minimum_size() 是 RichTextLabel(fit_content) 自己算的真实高度, 与字号自洽
	#   —— 同一份写法在 _show_p2eq 已经用了(那边的效果段/羁绊块就是这么顺排的)。
	return y + maxf(20.0, rt.get_combined_minimum_size().y)


# ══════════════════════════════════════════════════════════════════
# 属性牌 / 稀有度牌 / 词条签 (2026-09-27 去"后台仪表盘"味)
# ══════════════════════════════════════════════════════════════════
## 一块牌子 = 金属签牌九宫格 + 语义色 modulate。
##
## ★为什么直接调 `UISkin.nine` 而不是 `nine_if_big`: 牌高只有 34~48,
##   低于 `UISkin.MIN_FRAME_PX`(40) 的那几个会被 `nine_if_big` 退回**纯色块** ——
##   而纯色块 + 四边描边 + 半透底正是门禁认的"网页盒"。`chip-frame` 源图 48x24、
##   边带实测只有 4px, 34 高完全装得下(普攻条 36 高就是这么挂的, 见 _render_skill_cards)。
## ★兜底 StyleBoxFlat 的底色 alpha 给 **1.0**: 贴图万一缺失时也不能变成"半透底+四边框",
##   那会让图鉴凭空多出 N 个网页盒(verify_ui_consistency 的主指标)。
func _plaque(x: float, y: float, w: float, h: float, col: String, bg: String = "") -> Panel:
	var p := Panel.new()
	p.position = Vector2(x, y)
	p.custom_minimum_size = Vector2(w, h)
	p.size = p.custom_minimum_size
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(bg) if bg != "" else Color(0.071, 0.125, 0.165, 1.0)
	fb.bg_color.a = 1.0
	fb.border_color = Color(col)
	fb.set_border_width_all(2)
	var sb := UISkin.nine("chip-frame.png", 7, fb)
	if sb is StyleBoxTexture:
		(sb as StyleBoxTexture).modulate_color = UISkin.tint_of(Color(col))
	p.add_theme_stylebox_override("panel", sb)
	host.detail.add_child(p)
	return p

## 牌子上那行字 —— **不走 `host._add_text` 的居中锚**。
##
## ★★为什么(2026-09-27 实测, 门禁当场逮到「近战斗士+4」):
##   `_add_text` 的锚是拿 `字数 × 字号 × 0.62` 估出来的宽度算的, 而 0.62 是**英文的字宽比**。
##   中文是**全角**(≈1.0×字号): 「近战斗士」16px 真宽 64, 估出来只有 39.7 ⇒
##   "居中"实际把字往右推了 (64-39.7)/2 = 12px, 正好推出签牌的金属边带。
##   ⇒ 牌里的字一律**给死矩形 + 让 Label 自己居中**, 宽度由牌决定、不由我估。
##   (`_add_text` 本身不能改: 它是主场景的共享入口, 全图鉴几十处在用。)
func _chip_text(x: float, y: float, w: float, h: float, txt: String, size: int, col: String) -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(col))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(x, y)
	l.custom_minimum_size = Vector2(w, h)
	host.detail.add_child(l)
	l.size = Vector2(w, h)

## 稀有度牌: 一块方牌, 牌上只有那个字母。**不写"稀有度"这个词** ——
## 牌子本身就是"品阶"的表示法(与左栏列表行的稀有度字母同色同字)。
const BADGE_PX := 48.0
func _rarity_badge(cx: float, cy: float, letter: String, col: String) -> void:
	_plaque(cx - BADGE_PX / 2.0, cy - BADGE_PX / 2.0, BADGE_PX, BADGE_PX, col)
	## 字框比牌小一圈(牌 48 / 字框 38) —— chip-frame 的边带实测 4px, 留到 5 才有余量。
	## ★字号 22 不是 24: 最长的品阶是三个字母(SSS), 22px 下约 36 宽, 装得进 38 的字框;
	##   24px 下约 39 ⇒ Label 的最小宽度会**顶开字框**, 反而漫到边带上(门禁量 over>2 就红)。
	_chip_text(cx - 19.0, cy - 15.0, 38.0, 30.0, letter, 22, col)

## 词条签: 一块扁牌 + 一行字, 返回它占了多宽(调用方据此往右接下一块)。
const TAG_H := 36.0
func _tag_chip(x: float, cy: float, txt: String, col: String) -> float:
	## 宽度按【全角字宽】估(16px 字 ⇒ 每字 16) —— 签牌是九宫格, 宽一点不变形; 宁可宽也别切字。
	var w: float = maxf(58.0, float(txt.length()) * 16.0 + 26.0)
	_plaque(x, cy - TAG_H / 2.0, w, TAG_H, col)
	_chip_text(x + 7.0, cy - 12.0, w - 14.0, 24.0, txt, 16, col)
	return w

## 属性牌的排布。2 列 × 3 行, 右缘正好落在 DETAIL_W - 20。
## 同类装备网格: 图标边长与行高。
## ★图标 32: 装备 PNG 尺寸不统一(51 张 64 / 27 张 32 / 十几张大图),
##   跟左栏列表(36×36)同一党: 等比内缩到固定框。项目默认 texture_filter 已是 NEAREST
##   (`project.godot` 第 54 行 `default_texture_filter=0`), 所以不会被插值糊掉。
## ★行高 36 = 32 + 4 的行间缝; 原来是 26(那时行里只有一个 emoji 字符)。
const MEMBER_ICON := 32.0
const MEMBER_ROW := 36.0
## ═══ 两栏骨架(2026-10-08 用户「右侧布局需要重新设计」) ═══
## 左栏 0~LCOL_W: 立绘 + 名字/签牌 + 属性方块条; 右栏 RCOL_X~(DETAIL_W-20): 被动 / 普攻 / 开局三选一(竖排)。
## 方案书 docs/plans/20261008-图鉴龟页右侧重排.md。
const LCOL_W := 370.0
const RCOL_X := 386.0

## 右栏宽(右缘与原来整宽版式同一条线 DETAIL_W - 20)。
func _rw() -> float:
	return float(host.DETAIL_W) - 20.0 - RCOL_X

## 属性方块: 每格代表多少。用户 2026-10-08 原话「100生命值一格，10攻击力一格」, 看过实拍后改「攻击力按6，双抗按2」;
##   移速 10、每秒攻击 0.1 经 AskUserQuestion 拍板; 射程(只有小将页有)是我定的 100。
## ★只画满格(用户选「只画满格」): 945 生命 = 9 格, 零头看旁边的数字。
const STAT_BLOCK_UNIT := {"hp": 100.0, "atk": 6.0, "def": 2.0, "mr": 2.0, "move": 10.0, "aspd": 0.1, "range": 100.0}
const STAT_ROW_Y0 := 196.0
const STAT_ROW_H := 46.0
const BLOCK_X0 := 22.0
const BLOCK_W := 16.0
const BLOCK_H := 14.0
const BLOCK_GAP := 4.0
## 每 5 格多空一点, 一眼数得出「几个 5」(战斗血条 1000 大刻度 / 100 小刻度是同一个思路)。
const BLOCK_GROUP_GAP := 4.0

## 一格属性该画几格: floor(屏上数值 / 单位)。拿【屏上那个数】算, 不拿原始浮点 ——
##   每秒攻击屏上写 0.70, 原始值 0.7000001 或 0.6999999 都必须画 7 格。+1e-6 吃掉 0.7/0.1 = 6.9999 的浮点尾巴。
static func stat_block_count(key: String, disp: String) -> int:
	var unit: float = float(STAT_BLOCK_UNIT.get(key, 0.0))
	if unit <= 0.0 or not disp.is_valid_float():
		return 0
	return maxi(0, int(floorf(float(disp) / unit + 1e-6)))

## 一行属性: 上层 [图标] 数值 小字名(左对齐挨着), 下层一排方块。
##
## ★★2026-09-27 用户否过一版「名词在左、数字在右、后面拖一串小方块(945/40 = 23 个)」——
##   「全是 ai 味和网页味」: 那是后台仪表盘的长相。这次方块是用户自己要的(单位也是他给的),
##   但长相不退回去: 不做名左数右、不画空槽底轨、方块是带亮边/暗边的像素砖, 不是扁平进度条。
## ★名词 13px 暗灰排在数字**右边**: 与原属性牌同一个读法(先看数, 再看是什么)。
func _stat_row(y: float, st: Dictionary) -> void:
	var key: String = str(st["key"])
	var col: Color = Color(str(st["color"]))
	var _iconp: String = "res://assets/sprites/stats/%s-icon.png" % key
	var vx: float = BLOCK_X0
	if ResourceLoader.exists(_iconp):   # 缺图只显文字, 不崩
		## ★`host` 没有类型标注 ⇒ 动态派发返回 Variant, 不能用 `:=` 推断(2026-10-01 Parse Error 那次)。
		var _ir: Variant = host._add_image(BLOCK_X0 + 11.0, y + 10.0, _iconp, 22, 22)
		if _ir is TextureRect:
			(_ir as TextureRect).modulate = SkillText.stat_icon_color_of(_iconp)   # 纯白模板→按属性固定色
		vx = BLOCK_X0 + 30.0
	var disp: String = str(st["disp"])
	var num: Label = host._add_text(vx, y + 10.0, disp, 20, str(st["color"]), 0.0, 0.5, true)
	num.set_meta("stat_num", key)
	var nw: float = num.get_combined_minimum_size().x
	host._add_text(vx + nw + 8.0, y + 11.0, str(st["label"]), 13, "#8c9cab", 0.0, 0.5)
	_stat_blocks(y + 24.0, key, stat_block_count(key, disp), col)

## 一排方块。超出左栏可用宽度时等比收窄(满级生命 15 格正常放得下, 这是给临时等级加成留的退路)。
func _stat_blocks(y: float, key: String, n: int, col: Color) -> void:
	if n <= 0:
		return
	var avail: float = LCOL_W - 10.0 - BLOCK_X0
	var need: float = float(n) * (BLOCK_W + BLOCK_GAP) - BLOCK_GAP + float((n - 1) / 5) * BLOCK_GROUP_GAP
	var k: float = minf(1.0, avail / need)
	var bw: float = BLOCK_W * k
	var x: float = BLOCK_X0
	var hi: Color = col.lightened(0.35)
	var lo: Color = col.darkened(0.45)
	for i in range(n):
		if i > 0:
			x += (BLOCK_W + BLOCK_GAP) * k
			if i % 5 == 0:
				x += BLOCK_GROUP_GAP * k
		var body := ColorRect.new()
		body.color = col
		body.position = Vector2(x, y)
		body.size = Vector2(bw, BLOCK_H)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.set_meta("stat_block", key)   # 门禁 verify_codex_stat_blocks 按它数格
		host.detail.add_child(body)
		## 像素砖: 顶 2px 亮边 + 底 3px 暗边(画在砖内, 不另占地方)
		for band in [[0.0, 2.0, hi], [BLOCK_H - 3.0, 3.0, lo]]:
			var r := ColorRect.new()
			r.color = band[2]
			r.position = Vector2(x, y + float(band[0]))
			r.size = Vector2(bw, float(band[1]))
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			host.detail.add_child(r)

## 左栏整列属性(龟 6 行 / 小将 7 行)。返回最后一行的底边。
func _stat_rows(rows: Array) -> float:
	var y: float = STAT_ROW_Y0
	for st in rows:
		_stat_row(y, st)
		y += STAT_ROW_H
	return y - STAT_ROW_H + 24.0 + BLOCK_H

## 左栏抬头: 立绘 + 名字 + 一排签牌(放不下就换行)。立绘/名字的位置龟页与小将页同一套。
func _left_header(name_txt: String, chips: Array) -> void:
	var mid_x := 190.0
	host._add_text(mid_x, 34, name_txt, 32, "#ffd93d", 0.0, 0.5, true)
	var cx: float = mid_x
	var cy: float = 88.0
	for c in chips:
		var w: float = 0.0
		if str(c["kind"]) == "badge":
			w = BADGE_PX
		else:
			w = maxf(58.0, float(str(c["text"]).length()) * 16.0 + 26.0)   # 与 _tag_chip 同一个估宽
		if cx > mid_x and cx + w > LCOL_W - 6.0:
			cx = mid_x
			cy += 48.0
		if str(c["kind"]) == "badge":
			_rarity_badge(cx + BADGE_PX / 2.0, cy, str(c["text"]), str(c["color"]))
		else:
			_tag_chip(cx, cy, str(c["text"]), str(c["color"]))
		cx += w + 8.0

## ★★2026-10-08 右栏去框(用户:「这些框框真的丑，哪个游戏这么排的」)。参考 `docs/plans/ref/20261006-云顶装备弹窗/` 1、2:
##   Riot 检视面板设计稿 / 云顶实机 —— 技能是「图标 + 名字」一行, 区块之间只用一条细线, **没有一层套一层的框**;
##   战斗信息面板(info_panel.gd, 10-06 用户拍板)也是这一套。⇒ 被动 / 普通攻击 / 技能 每项一行、无底框, 项与项之间一条细线。
## 一行的底板: 不画任何东西(StyleBoxEmpty), 只占位 —— 点击区/门禁按节点认它, 但画面上它不存在。
func _flat_row(x: float, y: float, w: float, h: float, nm: String = "") -> Panel:
	var p := Panel.new()
	if nm != "":
		p.name = nm
	p.position = Vector2(x, y)
	p.custom_minimum_size = Vector2(w, h)
	p.size = p.custom_minimum_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	host.detail.add_child(p)
	return p

## 右栏里项与项之间那条细线(与两栏竖分隔线同色同透明度)。
func _row_rule(y: float) -> Panel:
	return host._add_rect(RCOL_X + _rw() / 2.0, y, _rw(), 1, "#ffd93d", 0.3)

## 两栏之间一条竖分隔线。
func _col_divider(bottom: float) -> void:
	host._add_rect(LCOL_W + 8.0, (16.0 + bottom) / 2.0, 1, bottom - 16.0, "#ffd93d", 0.3)


func _show_pet(pet: Dictionary) -> void:
	host._clear_detail()
	var rarity: String = pet.get("rarity", "C")
	var rarity_color: String = host.RARITY_COLOR.get(rarity, "#ffffff")
	var ctx = host._ctx_for(pet)

	# 1) 立绘 160 —— 左栏左上(2026-10-08 两栏) · 全身 idle 动画 sprite, 非头像
	host._add_pet_portrait(95, 100, pet, 160.0)

	# 2) 名字 y30 32px 金 bold。
	## ★★2026-09-27 抬头改「名字 + 一排牌子」(用户: 图鉴「全是 ai 味和网页味」)。
	##   原来是三行 `label: value` 的属性表写法:
	##       Lv 1.  小龟
	##       稀有度   C
	##       定位     近战斗士
	##   —— 「稀有度」「定位」两个词只是在给旁边那个值当字段名, 玩家一个都不需要读,
	##   而「C」在游戏里从来不是一个"字段的值", 它是**一块牌子**。
	##   现在: 名字独占一行, 下面一排 [稀有度牌][Lv 签][定位签] —— 牌/签的形状自己说明是什么。
	## ★等级牌显示【战斗真正用的等级】(2026-10-07 J): 原来读 `pet_levels`(战斗不读它; 写它的调试面板已删)。
	var lv: int = int(ctx.get("lv", 1))
	# ★tag 区已删(用户2026-07-23 点5): 守护/元素/物理/法术等 10 种标签全是凑羁绊的, 龟间羁绊已废 → 全去。
	#   腾出的位置给【定位】(用户2026-07-28: 定位是移速/攻速的权威事实源, 玩家该看得到)。
	var _role: String = str(host.TurtleStats.ROLE.get(str(pet.get("id", "")), ""))
	var _chips: Array = [{"kind": "badge", "text": rarity, "color": rarity_color},
		{"kind": "tag", "text": "Lv %d" % lv, "color": "#ffd93d"}]
	if _role != "":
		_chips.append({"kind": "tag", "text": _role, "color": "#9ad0ff"})
	_left_header(str(pet.get("name", "?")), _chips)

	# 3) 属性: 左栏 6 行「数值 + 方块」(2026-10-08; 原来是右上 2×3 属性牌)。
	# ★四项主属性直接取 `ctx`(= host._ctx_for, 与战斗生成的单位同口径: 只吃等级缩放, 不乘稀有度)。
	#   2026-10-07 之前这里另乘了一份 rarity_mult ⇒ 非 C 龟虚高 3~15%(战斗从不乘它)。
	# ★移速/攻速(点5): 从 host.TurtleStats.STATS 单一事实源读, 与战斗同口径 ——
	#   移速【不缩放】(定值); 攻速=1/攻击间隔 且【+2%/级】(atk_interval /= 1+0.02*(lv-1), 见战斗 _make_unit); 都不乘 rarity_mult。
	var _tid = str(pet.get("id", ""))
	var _ts: Array = host.TurtleStats.STATS.get(_tid, [])
	var _mspd: int = int(round(float(_ts[1]))) if _ts.size() > 1 else 0
	var _aspd: float = (1.0 / float(_ts[2])) * (1.0 + 0.02 * float(lv - 1)) if _ts.size() > 2 and float(_ts[2]) > 0.0 else 0.0
	## ★射程(2026-10-08 用户「射程要么都显示啊，怎么只有小将有？」): 印【出生时实际生效】的值 ——
	##   与 battle_spawn._make_unit 同一条规则: 近战抬到 ≥ MELEE_ATK_RANGE_MIN, 远程照表(门禁 verify_codex_battle_parity 对真单位)。
	var _rng: int = 0
	if _ts.size() > 3:
		_rng = int(round(maxf(float(_ts[3]), RealtimeBattle3DScene.MELEE_ATK_RANGE_MIN) if bool(_ts[0]) else float(_ts[3])))
	## `label` 是牌子底下那行**小字说明**(13px 暗灰), 不再是"字段名: 值"里的字段名。
	## ★★★2026-09-28 两件事一起收:
	##  ① **`unit` 这个字段没人读** —— 当时的 `_stat_plaque`(2026-10-08 已换成 `_stat_row`)只读 `key/disp/label/color`
	##    (2026-09-27 那版重写把它丢了、字段留在这里)。于是「次/秒」这三个字
	##    **一直没上过屏**, 而它看着像在屏上 ⇒ 正是 memory `fb-write-without-reader`
	##    那一类。直接删掉, 不再留一个只能骗人的字段。
	##  ② 战斗信息面板那边已经改成「攻速 每秒 N 下」(`info_panel.gd`),
	##    而这里只写一个光秃的 0.77 + 「攻击速度」—— **连是速率还是间隔都读不出来**
	##    (2026-08-10 就因为这两者分岔出过事)。改成「每秒攻击」, 与面板同一种说法。
	## ⚠ 宽度是算过的, 不是拍的: 牌 186 宽, 图标吃到 48, 大字 "0.77" 约 48,
	##   小字从 48+4×14+12=116 起, 4 个全角 13px 约 52 ⇒ 收在 168 < 186。
	##   (再长一个字就超 186 ⇒ `verify_ui_consistency` 的「文字压边带」会红, Codex 基线是 0。)
	## ★「移速」字面量被 verify_codex_stats 用源码 grep 守着, 别改字。
	##   攻速那一条已改成按 `"key": "aspd"` 找(量结构, 不量文案)。
	var stats = [
		{"key": "hp", "label": "生命", "disp": str(int(ctx["maxHp"])), "color": "#06d6a0"},
		{"key": "atk", "label": "攻击", "disp": str(int(ctx["atk"])), "color": "#ff9f43"},
		{"key": "def", "label": "护甲", "disp": str(int(ctx["def"])), "color": "#ffd93d"},
		{"key": "mr", "label": "魔抗", "disp": str(int(ctx["mr"])), "color": "#4dabf7"},
		{"key": "move", "label": "移速", "disp": str(_mspd), "color": "#8fd4ff"},
		{"key": "aspd", "label": "每秒攻击", "disp": "%.2f" % _aspd, "color": "#ff9ecb"},
		{"key": "range", "label": "射程", "disp": str(_rng), "color": "#d6e4f0"},
	]
	var stats_bottom: float = _stat_rows(stats)
	_col_divider(stats_bottom)

	# 9) 被动条(右栏顶) 高 PASSIVE_BAR_H · 两行: 标题行 + 简述一行
	var passive: Dictionary = pet.get("passive", {})
	var rw: float = _rw()
	var cards_y := 16.0   # 无被动的龟(目前 0 只)从右栏顶起
	if not passive.is_empty():
		var passive_y = 16.0
		## ★2026-10-08 无框(见 _flat_row 上方): 展开态靠右端「收起」二字区分, 不再靠框色。
		_flat_row(RCOL_X, passive_y, rw, PASSIVE_BAR_H, "PassiveBar")
		var mid_y: float = passive_y + 19.0   # 标题行中线(与普攻条同一套几何)
		var text_x = RCOL_X + 16.0
		var pi_path: String = DataRegistry.passive_icons.get(passive.get("type", ""), "")
		if pi_path != "":
			if pi_path.ends_with(".png"):
				## 被动条九宫格边带 13 ⇒ 图标放 28, 不漫到边带上。
				host._add_image(RCOL_X + 30.0, mid_y, "res://assets/sprites/%s" % pi_path, 28, 28)
				text_x = RCOL_X + ROW_TEXT_X
			else:
				host._add_text(RCOL_X + ROW_ICON_CX, mid_y, pi_path, 28, "#ffffff", 0.5, 0.5)
				text_x = RCOL_X + ROW_TEXT_X
		host._add_text(text_x, mid_y, "被动 · %s" % passive.get("name", ""), 17, "#58d3ff", 0.0, 0.5, true)
		## ★★被动的简述【就画在条上】(2026-08-15, 用户点名的"同一屏两种交互"):
		##   与技能卡同构 —— **条上给简述, 点开看全文**。
		## ★2026-10-08 两栏后右栏只剩 494 宽, 简述从「标题右边横着放」改成标题下面一整行。
		var p_brief: String = str(passive.get("brief", passive.get("desc", "")))
		if p_brief.strip_edges() != "":
			var brt := RichTextLabel.new()
			brt.bbcode_enabled = true
			brt.fit_content = false     # 定高一行 + clip: 撑高就把技能卡挤下去了
			brt.scroll_active = false
			brt.clip_contents = true
			brt.position = Vector2(RCOL_X + CARD_PAD + 2.0, passive_y + 35.0)   # 标题 Label 下沿约 +34
			brt.custom_minimum_size = Vector2(rw - CARD_PAD * 2.0 - 4.0, 22.0)
			brt.size = brt.custom_minimum_size
			brt.add_theme_font_size_override("normal_font_size", 14)
			brt.add_theme_color_override("default_color", Color("#aab8c6"))
			brt.text = SkillText.render_bbcode(_trim_tail(p_brief), ctx, passive, 14)
			host.detail.add_child(brt)
		# hint: 展开→"收起"金 / 否则"看全部"蓝(与技能卡的"点开看全部"同一句式)
		## ★同上去掉 ▾/▸ 两个折叠箭头。
		var p_hint: String = "收起" if host._codex_passive_view else "查看全部"
		var p_hint_col: String = "#ffd93d" if host._codex_passive_view else "#7fb5d8"
		host._add_text(host.DETAIL_W - 30 - CARD_PAD * 2.0, mid_y, p_hint, 14, p_hint_col, 1.0, 0.5)
		# drill-down: 点被动条 → 内联展开/收起完整 passive desc (1:1 PoC showPetDetail view='passive' toggle, 非弹窗)
		var p_hit = Control.new()
		p_hit.position = Vector2(RCOL_X, passive_y)
		p_hit.size = Vector2(rw, PASSIVE_BAR_H)
		p_hit.mouse_filter = Control.MOUSE_FILTER_STOP
		p_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var pet_ref2: Dictionary = pet
		p_hit.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				host._codex_skill_detail = {}
				host._codex_passive_view = not host._codex_passive_view
				_show_pet(pet_ref2))
		host.detail.add_child(p_hit)
		_row_rule(passive_y + PASSIVE_BAR_H + 3.0)
		cards_y = passive_y + PASSIVE_BAR_H + 8.0
	## 双形态龟(双头/熔岩)的形态切换钮: 原来写死 y=262 压在被动条上; 后来给它在这里留了一条 42px 带,
	##   而钮却按【卡片起点】定位(start_y 已经越过普攻条) ⇒ 实拍压在普攻条上、带子空着。
	## ★2026-10-07 改挂到「开局三选一」那一行的右端(见 _render_skill_cards), 这里不再另留带 ——
	##   省下的高度还给三选一卡片(熔岩龟形态页原来每张卡只剩 1 行正文)。

	# 10) 技能卡 — 4 卡 1 行, 铺满板宽, 每卡高度按自己的正文收(见 _render_skill_cards)
	_render_skill_cards(pet, ctx, cards_y)


# ─── 技能卡 (1:1 PoC renderSkillListSection) ───
## 被动条高。2026-10-08 两栏后改两行: 标题行 + 简述一行(右栏只有 494 宽, 简述横排在标题右边放不下)。
## ★60 = 与普攻条同高同几何(chip-frame 边带 4px)。原 panel-frame(边带 13)要 80 才装得下两行。
const PASSIVE_BAR_H := 60.0
## 卡片内容离卡边的留白。
##
## ★原来是散在八处的字面量 8 —— 而卡框换成九宫格金属框之后, 边带**实测 13px 厚**,
##   于是「3选1候选」「点开看全部 ▸」这些贴边摆的文字全压在边带上(判据 13 量到 5~15px)。
##   **换框不是换花纹, 是内容区真的变小了。** 提到 14(> 13) 并收进一个常量,
##   免得下次换框又要满文件找 `cx + 8`。
const CARD_PAD := 14.0
## ★2026-10-08 技能卡改竖排(每张占右栏整宽): 图标槽 44 在左, 名字 + 「主动 · 龟能 N」同一行在图标右边,
##   简述接在名字下面、与名字左对齐。正文左缘 = 卡左 + CARD_PAD + CARD_TEXT_DX。
## ★2026-10-08 去框后: 图标中心与被动/普通攻击两行的图标同一条竖线(RCOL_X + 30), 名字左缘同一条竖线(RCOL_X + 60)。
const ROW_ICON_CX := 30.0
const ROW_TEXT_X := 60.0
const CARD_TEXT_DX := ROW_TEXT_X - CARD_PAD
## 卡片正文的起始 y(卡内相对) —— 边带 14 + 名字行 26。
const CARD_BODY_TOP := 40.0
## 卡片最矮不低于这个: 能把 44 的图标槽完整装下(14 + 44 + 14 + 4)。
const CARD_MIN_H := 76.0
## 正文与卡底边带之间的缝。
const CARD_BODY_GAP := 4.0
## 卡片【最高】也至少给到这么多: 正文起点 40 + 3 行(13px 纯文字行≈20) + 间隙 4 + 底边带 14。
## ★被切时「查看全部」画在**名字行右端**, 不在卡底另占一条提示带 —— 竖排三张卡, 每张省 18px。
const CARD_MAX_FLOOR := 118.0
## 竖排卡片之间的缝。
const CARD_GAP := 8.0
## 双形态龟「开局三选一」那一行的行高(同时挂 34 高的形态切换钮)。
const FORM_ROW_H := 38.0

## 每张卡收完高度后, 它那条提示带该画在哪个 y(卡内绝对 y)。
## 键是 RichTextLabel 实例 —— _mark_card_clipped 拿它取自己那张卡的真实底边。
## (不是单位字典, 可以安全做键; 见 CLAUDE.md §3.2 说的是战斗单位字典)
var _card_hint_y: Dictionary = {}

## 抽掉普攻后, 候选卡在原 skillPool 里的索引(角色/龟能判定要用原始索引, 不能用移位后的)。
var _orig_idx: Array = []

## 技能卡的简述被切断时, 在卡片底部那条留白里画一行"点开看全部 ▸"。
##
## ★必须等一帧才问 `get_content_height()` —— 刚 add_child 时还没排版, 拿到 0 ⇒ 永远判"没被切",
##   提示永远不出现(这就是个不会红的假检查)。同 ShopScene._add_scroll_hint 那条。
## ★这里等【两帧】: 第一帧让 _fit_skill_cards 把每张卡收到自己的正文高度(它只等一帧),
##   第二帧才轮到这里判"收完之后还超不超"。少等一帧就会拿收缩前的 size.y 判断 ⇒ 全判成"被切"。
func _mark_card_clipped(rt: RichTextLabel, cx: float, y: float, card_w: float) -> void:
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if not is_instance_valid(rt) or not is_instance_valid(host) or host.detail == null:
		return
	if rt.get_content_height() <= rt.size.y + 0.5:
		return
	y = float(_card_hint_y.get(rt, y))   # 收缩后各卡底边不同; 没登记就用调用侧给的兜底值
	var l := Label.new()
	## ★★2026-09-27 去掉 `▸` —— 它是网页折叠控件的展开箭头, 游戏里不用它指路。
	##   ⚠ 技能卡提示「查看全部」(2026-10-07 去口语化, 原「点开看全部」)与被动/普攻条同字; verify_codex_layout ⑨ 逐只龟数
	##   "被截的卡数 == 画出提示的卡数", 靠右对齐(HORIZONTAL_ALIGNMENT_RIGHT)把它与条上的提示分开。
	l.text = "查看全部"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("#7fb5d8"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(cx + CARD_PAD, y)
	l.size = Vector2(card_w - CARD_PAD * 2.0, 16)
	host.detail.add_child(l)


func _render_skill_cards(pet: Dictionary, ctx: Dictionary, cards_y: float) -> void:
	_card_hint_y.clear()
	_orig_idx = []
	# 内联技能详情页 (1:1 PoC showPetDetail view={skillIdx} → renderSkillDetailSection): 顶部"← 返回列表" + 完整 host.detail
	if not host._codex_skill_detail.is_empty():
		_render_skill_detail_inline(pet, ctx, host._codex_skill_detail, cards_y)
		return
	# 内联被动详情 (1:1 PoC showPetDetail view='passive' → renderPassiveDetailSection): 下方区显完整 desc
	if host._codex_passive_view and not (pet.get("passive", {}) as Dictionary).is_empty():
		_render_passive_detail_inline(pet, ctx, cards_y)
		return
	# E1 双形态 (PoC CodexScene.ts:401-405): 近战(meleeSkills 双头) / 火山(volcanoSkills 熔岩)
	var melee = pet.get("meleeSkills", [])
	var volcano = pet.get("volcanoSkills", [])
	var is_melee_form: bool = melee is Array and not (melee as Array).is_empty()
	var form_skills: Array = (melee if is_melee_form else (volcano if volcano is Array else [])) as Array
	var has_form: bool = not form_skills.is_empty()
	var skill_pool = form_skills if (host._codex_form_view and has_form) else pet.get("skillPool", [])
	if not (skill_pool is Array):
		return
	var default_idxs = pet.get("defaultSkills", [0, 1, 2])
	var start_x: float = RCOL_X
	var start_y: float = cards_y
	var form_btn_y: float = -1.0   # 形态切换钮的中心 y(挂在「开局三选一」那一行); <0 = 还没排到

	## ═══ 把【普攻】从三选一里拆出来 ═══
	## 用户 2026-08-18:「右下角这些被动普攻技能这样子放你不觉得怪吗」——
	## 原来是**一排四张等宽卡**: 攻击(基础·普攻) + 打击/龟派气波/过肩摔(3选1候选)。
	## 四张长得一模一样 ⇒ 视觉上直接读成"四选一", 可普攻是**固定自带、不参与选择**的。
	## 现在分三层, 每层是一种东西:
	##     被动条(固定) → 普攻条(固定) → 三选一卡片 ×3(要选)
	## 附带好处: 卡片从 4 张变 3 张, **每张宽 33%**, 正文被切、要点"看全部"的情况同时缓解。
	var pid_s: String = str(pet.get("id", ""))
	var basic_i: int = -1
	for bi in range(skill_pool.size()):
		if str(host._skill_role(pid_s, skill_pool[bi], bi)) == "basic":
			basic_i = bi
			break
	var cand_pool: Array = []
	## ★角色判定 `_skill_role(pid, sk, i)` 是**按索引**算的(索引 0 = 普攻)。
	##   抽掉普攻之后剩下的技能索引整体前移 ⇒ 第一张候选卡会被判成"基础 · 普攻"
	##   (实拍确认: 「打击」卡上挂着「基础 · 普攻」)。所以要把**原始索引**带着走。
	var cand_orig: Array = []
	for ci in range(skill_pool.size()):
		if ci != basic_i:
			cand_pool.append(skill_pool[ci])
			cand_orig.append(ci)
	if basic_i >= 0:
		var bsk: Dictionary = skill_pool[basic_i]
		start_y += _basic_attack_bar(pet, ctx, bsk, start_y) + 6.0
		# 三选一那一排上面给一句抬头 —— 不然玩家不知道这三张是"要选一个"
		## 双形态龟: 这一行同时挂「换成 X 形态」钮(钮高 34) ⇒ 行高 38; 其余龟仍是 15。
		var head_h: float = FORM_ROW_H if has_form else 15.0
		## ★2026-10-08 「开局三选一」→「技能」。用户:「开局三选一是啥呢」「我问你哪个参考游戏会这么说？」—— 没有哪个游戏这么说,
		##   是我 08-18 自己加的, 讲的是我们的选择机制(同 10-01 被否的「3选1候选」)。对齐战斗信息面板「被动 / 普通攻击 / 技能」(10-06 用户拍板)。
		host._add_text(start_x + 2.0, start_y + (head_h / 2.0 if has_form else 6.0), "技能", 12, "#06d6a0", 0.0, 0.5, true)
		if has_form:
			form_btn_y = start_y + head_h / 2.0
		start_y += head_h
		skill_pool = cand_pool
		_orig_idx = cand_orig
		default_idxs = [0, 1, 2]

	if has_form and form_btn_y < 0.0:   # 没有普攻条的双形态龟(目前 0 只): 自己占一行, 不压卡片
		form_btn_y = start_y + FORM_ROW_H / 2.0
		start_y += FORM_ROW_H
	var n: int = mini(skill_pool.size(), 5)
	## ★2026-10-08 两栏: 卡片【竖排】, 每张占右栏整宽(494)。
	##   原来三张横排各 ~280 宽, 而右栏只剩 494 —— 横排每张只剩 160, 一行放不下 10 个字。
	var card_w: float = _rw()
	## 每张卡最高 = 详情框剩下的高度均分给 n 张; 下限 CARD_MAX_FLOOR(至少 3 行正文), 超出由外层滚动接住。
	var card_max_h: float = maxf(CARD_MAX_FLOOR,
		(host.DETAIL_MAX_H - start_y - 14.0 - float(maxi(0, n - 1)) * CARD_GAP) / float(maxi(1, n)))
	var card_h: float = card_max_h
	var parts: Array = []   # 每张卡的 {panel, rt, hit, nodes, y0}, 建完统一按各自正文收高并重新竖排
	for i in n:
		var sk: Dictionary = skill_pool[i]
		if sk.is_empty():
			continue
		var cx: float = start_x
		## 先按最高卡高排开(互不重叠), 下一帧 _fit_skill_cards 收高后整体上移。
		var cy0: float = start_y + float(i) * (card_max_h + CARD_GAP)
		var nodes: Array = []
		## (2026-07-10 去掉等级解锁后「锁住」恒为假的那条死分支, 随竖排重写一并删掉 —— 它连同锁图标都上不了屏)
		## ★2026-10-08 无框(见 _flat_row 上方): 原来每张卡一个金属框(默认绿/普通蓝边), 改成一行 + 行间细线。
		var card_panel: Panel = _flat_row(cx, cy0, card_w, card_h)
		if i > 0:
			nodes.append(_row_rule(cy0 - CARD_GAP / 2.0))
		# 图标 (skills/<icon>.png), "+" 强化角标
		var icon: String = sk.get("icon", "")
		var enhances: bool = sk.get("enhancesPassive", false)
		var icon_src: String = ""
		if icon != "" and icon.ends_with(".png"):
			icon_src = icon
		elif enhances and not pet.get("passive", {}).is_empty():
			var pic: String = DataRegistry.passive_icons.get(pet.get("passive", {}).get("type", ""), "")
			if pic.ends_with(".png"):
				icon_src = pic
		var text_x: float = cx + CARD_PAD + CARD_TEXT_DX
		if icon_src != "":
			# PoC skillIconHtml: 图标带金框 socket; 原裸图无框 (用户报"很多地方技能都没有框")
			var sock = Panel.new()
			var sock_sb = StyleBoxFlat.new()
			sock_sb.bg_color = Color(0.04, 0.06, 0.09, 0.7)
			sock_sb.border_color = Color(1.0, 0.851, 0.4, 0.5)   # PoC border rgba(255,217,102,.5)
			sock_sb.set_border_width_all(2)
			sock_sb.set_corner_radius_all(8)
			# 装备槽换成和背包/战斗面板同一张槽框(44px 够 MIN_FRAME_PX)。
			var sock_nine := UISkin.nine_if_big(44.0, 44.0, "slot-frame.png", 12, sock_sb)
			if sock_nine is StyleBoxTexture:
				(sock_nine as StyleBoxTexture).modulate_color = Color(1.0, 0.94, 0.72, 1.0)
				sock_sb = sock_nine
			sock.add_theme_stylebox_override("panel", sock_sb)
			sock.position = Vector2(cx + ROW_ICON_CX - 22.0, cy0 + CARD_PAD)
			sock.custom_minimum_size = Vector2(44, 44); sock.size = Vector2(44, 44)
			host.detail.add_child(sock)
			nodes.append(sock)
			## 图标 32: 它住在 44x44 的槽框里, 槽框金属边带 6px ⇒ 内沿只有 32(38 的图会漫出 3px)。
			nodes.append(host._add_image(cx + ROW_ICON_CX, cy0 + CARD_PAD + 22, "res://assets/sprites/%s" % icon_src, 32, 32))
			if enhances or sk.get("iconPlus", false):
				nodes.append(host._add_text(cx + ROW_ICON_CX + 10.0, cy0 + CARD_PAD - 2, "+", 15, "#06d6a0", 0.5, 0.5, true))
		else:
			text_x = cx + CARD_PAD
		# 名字 16px —— 与类型 chip 同一行
		var name_y: float = cy0 + CARD_PAD + 12.0
		var nlbl: Label = host._add_text(text_x, name_y, sk.get("name", "?"), 16, "#ffd93d", 0.0, 0.5, true)
		nodes.append(nlbl)
		# 类型 chip (基础/主动·龟能/被动) —— 龟能口径(无"冷却/CD"): 普攻=不花龟能 / 主动=显龟能花费(与战斗同源) / 被动
		var chip_text = ""
		var chip_color = "#58d3ff"
		match host._skill_role(str(pet.get("id", "")), sk, (int(_orig_idx[i]) if i < _orig_idx.size() else i)):
			"passive": chip_text = "被动"; chip_color = "#c77dff"
			## 用户 2026-10-06「真的要说普攻这个吗，真的是商业游戏吗」「是被动，普通攻击，和技能啊」⇒ 全称, 与战斗信息面板同一个词。
			"basic": chip_text = "普通攻击"; chip_color = "#58d3ff"
			## ★★2026-10-01: 原来写「3选1候选 · 龟能N」。用户:「3选1候选，这又是什么 ai 味描述」——
			##   LoL 的技能头上只写**名字 + 消耗**。⇒ 与兄弟分支对齐成「角色 · 代价」;
			##   「龟能 100」中间留空格(codex_text_lint「汉字贴着数字」)。
			_: chip_text = "主动 · 龟能 %d" % host._skill_energy(sk); chip_color = "#06d6a0"
		nodes.append(host._add_text(text_x + nlbl.get_combined_minimum_size().x + 12.0, name_y + 1.0, chip_text, 13, chip_color, 0.0, 0.5))
		# 简述 — 富文本 BBCode, 多行 clamp
		var brief = SkillText.render_bbcode(_trim_tail(str(sk.get("brief", ""))), ctx, sk, 13)
		var rt = RichTextLabel.new()
		rt.bbcode_enabled = true
		## ★fit_content 必须是 false: 它会把控件撑到内容高度, 于是
		##   `get_content_height() <= size.y` **恒成立** —— 我加的"被切了就提示"永远不触发,
		##   而文字照样被卡片边缘切掉。这就是个不会红的假检查(等一帧也救不了)。
		rt.fit_content = false
		rt.scroll_active = false
		rt.position = Vector2(text_x, cy0 + CARD_BODY_TOP)
		## 正文高度 = 卡高 − 头部(CARD_BODY_TOP) − 间隙(CARD_BODY_GAP) − 底边带(CARD_PAD); 「查看全部」在名字行, 不占正文。
		var rt_w: float = cx + card_w - CARD_PAD - text_x
		var rt_h: float = card_h - CARD_BODY_TOP - CARD_BODY_GAP - CARD_PAD
		rt.custom_minimum_size = Vector2(rt_w, rt_h)
		rt.size = Vector2(rt_w, rt_h)
		rt.clip_contents = true
		rt.add_theme_font_size_override("normal_font_size", 13)
		rt.add_theme_color_override("default_color", Color("#aaaaaa"))
		rt.text = brief
		rt.set_meta("codex_card_body", true)   # 门禁据此认「技能卡正文」(竖排后宽度已分不开卡片与被动条)
		host.detail.add_child(rt)
		_mark_card_clipped(rt, cx, cy0 + CARD_PAD + 4.0, card_w)
		# drill-down: 点技能卡 → 内联换页显示完整 host.detail (1:1 PoC showPetDetail view={skillIdx}→renderSkillDetailSection)
		var hit = Control.new()
		hit.position = Vector2(cx, cy0)
		hit.size = Vector2(card_w, card_h)
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var sk_ref: Dictionary = sk
		hit.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				host._codex_skill_detail = sk_ref
				_show_pet(pet))
		host.detail.add_child(hit)
		parts.append({"panel": card_panel, "rt": rt, "hit": hit, "nodes": nodes, "y0": cy0})
	_fit_skill_cards(parts, start_y, card_max_h)
	## E1 形态切换钮 —— 整块在 `_form_switch_button()`(2026-09-28 拆出去的)。
	if has_form:
		_form_switch_button(pet, form_btn_y, is_melee_form)


## 普攻条(固定自带、不参与三选一): 图标 + 名字 + 一行简述 + 「看全部」, 点整条进技能详情。返回条高。
## ★2026-10-07 从 `_render_skill_cards` 整块搬出来(行为一字未改): 本轮给它加了「看全部」与点击区,
##   函数涨到 269 行越过 `tools/arch_budget.py` 的 250 行上限 —— 按职责拆, 不靠删注释凑绿。
func _basic_attack_bar(pet: Dictionary, ctx: Dictionary, bsk: Dictionary, start_y: float) -> float:
	## ★2026-10-08 两栏: 条占右栏整宽(494), 改两行 —— 标题行(图标 + 「普攻 · X」 + 右端「查看全部」) + 简述一行。
	##   原来是 36 高一行(名字右边接简述), 右栏变窄后简述只剩二十来个字的位置。
	var bar_h := 60.0
	var rw: float = _rw()
	var bmid: float = start_y + 19.0   # 标题行中线
	## 条高 58 ≥ UISkin.MIN_FRAME_PX, 但仍挂边带只有 4px 的 chip-frame(与签牌同一张), 不吃正文的地方。
	var bp := Panel.new()
	bp.name = "BasicBar"   # 门禁按名字找这一条(原来按「宽 > 800、高 36」认, 两栏后不成立)
	bp.position = Vector2(RCOL_X, start_y)
	bp.custom_minimum_size = Vector2(rw, bar_h)
	bp.size = bp.custom_minimum_size
	## ★2026-10-08 无框(见 _flat_row 上方): 只占位给点击区与门禁认。
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bp.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	host.detail.add_child(bp)
	var btx := RCOL_X + 14.0
	var bic: String = str(bsk.get("icon", ""))
	if bic.ends_with(".png"):
		host._add_image(RCOL_X + 30.0, bmid, "res://assets/sprites/%s" % bic, 28, 28)
		btx = RCOL_X + ROW_TEXT_X
	## 「普通攻击」全称(用户 2026-10-06, 战斗信息面板 info_panel.gd 同一个词); 2026-10-08 图鉴这里漏改, 用户实拍追问。
	host._add_text(btx, bmid, "普通攻击 · %s" % str(bsk.get("name", "?")), 17, "#58d3ff", 0.0, 0.5, true)
	## ★★2026-10-02: 普攻简述用 `RichTextLabel` + `render_bbcode`(与被动条/三选一卡同一种上色)。
	## ★定高一行 + clip; `fit_content` 必须是 false —— 开了它会被撑高把三选一卡片挤下去。
	var bbrief := SkillText.render_bbcode(_trim_tail(str(bsk.get("brief", ""))), ctx, bsk, 14)
	var brt2 := RichTextLabel.new()
	brt2.bbcode_enabled = true
	brt2.fit_content = false
	brt2.scroll_active = false
	brt2.clip_contents = true
	## 名字 17px 的 Label 下沿在 start_y + 33(中线 19 + 估高的一半); 简述从 35 起, 不相交(门禁 F 量过 0.95px 的重叠)。
	brt2.position = Vector2(RCOL_X + CARD_PAD + 2.0, start_y + 35.0)
	brt2.custom_minimum_size = Vector2(rw - CARD_PAD * 2.0 - 4.0, 22.0)
	brt2.size = brt2.custom_minimum_size
	brt2.add_theme_font_size_override("normal_font_size", 14)
	brt2.add_theme_color_override("default_color", Color("#aab8c6"))
	brt2.text = bbrief
	host.detail.add_child(brt2)
	## ★★2026-10-07 B: 简述被切时**必须有办法看到被切掉的部分**(例: 忍者龟「若本次斩击暴击，则改为施加 3 层流血」)。
	##   照被动条那一套: 条上给简述 + 右端「查看全部」, 点整条进技能详情(与三选一卡片同一个落地页)。
	host._add_text(host.DETAIL_W - 30 - CARD_PAD * 2.0, bmid, "查看全部", 14, "#7fb5d8", 1.0, 0.5)
	var b_hit := Control.new()
	b_hit.position = Vector2(RCOL_X, start_y)
	b_hit.size = Vector2(rw, bar_h)
	b_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	b_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var bsk_ref: Dictionary = bsk
	b_hit.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			host._codex_passive_view = false
			host._codex_skill_detail = bsk_ref
			_show_pet(pet))
	host.detail.add_child(b_hit)
	_row_rule(start_y + bar_h + 3.0)
	return bar_h


## 去掉正文末尾的空行(连同包着它的收尾标签一起看)。
## ★2026-10-07 G: 很多简述以 `…。\n</span>` 收尾 —— 那个换行在卡片里是**一整行空白**,
##   它被切掉时卡片照样画「点开看全部」, 而点开之后什么新东西都没有(26 张卡, 实测)。
##   收尾标签要保留(否则颜色区间不闭合), 只删标签前面的空白。
func _trim_tail(s: String) -> String:
	var t: String = s.strip_edges(false, true)
	var closers: String = ""
	var again: bool = true
	while again:
		again = false
		for tag in ["</span>", "</b>", "[/color]", "[/b]"]:
			if t.ends_with(tag):
				closers = tag + closers
				t = t.substr(0, t.length() - tag.length()).strip_edges(false, true)
				again = true
				break
	return t + closers


## E1 双形态龟的「换形态」钮 (1:1 PoC CodexScene.ts:417-431)。
## ★仅双形态龟(双头/熔岩)身上画; 切普通↔形态技能。
##
## ★★2026-09-28 从 `_render_skill_cards` 里**整块搬出来**的, 行为一字未改。
##   缘由: 那个函数原本 244 行(离上限只剩 6 行), 本轮给它加了两段
##   「为什么去掉 emoji」的注释 ⇒ 256 行, 越过 `tools/arch_budget.py` 的 250 行上限。
##   ★**不靠删注释凑绿灯** —— 那是把解释删掉换绿灯。按职责拆:
##     这一块自成一事(一颗钮的版式 + 文案 + 点击), 与技能卡排版没有共享状态,
##     入参只有 `pet / start_y / is_melee_form` 三个。
##   ★留在 `scripts/scenes/codex/` —— 它不在 `_sim_step` 调用链上, 图鉴的东西就放图鉴这里。
func _form_switch_button(pet: Dictionary, center_y: float, is_melee_form: bool) -> void:
	## ★钮的尺寸/位置都改了(2026-08-15):
	##   · 220×30 = 7.3:1 的又扁又宽片(用户刚为商店的扁按钮发过火) → 196×34。
	##   · 原来写死 btn_y=262, 而被动条占 213~263 ⇒ 【钮压在被动条上】, 双形态那两只
	##     (双头龟/熔岩龟)一直是这么画的。现在钉在卡片上沿那条空带里(_show_pet 为它留了 42px)。
	var btn_w = 196.0
	var btn_h = 34.0
	var btn_x = host.DETAIL_W - 20.0 - btn_w / 2.0
	var btn_y = center_y   # ★2026-10-07: 由调用方给中心 y(「开局三选一」那一行), 不再拿卡片起点倒推
	var label: String
	if is_melee_form:
		## ★★2026-09-28 去掉四个 emoji(🏹/⚔/🐢/🌋)。它们是**纯装饰** ——
		##   「换成 远程形态」自己把话说完了; 而四个字形全来自 NotoEmoji,
		##   钉在一颗 14px 的像素签牌上就是两套画法。
		## ⚠ 不拿现成的 `icon-turtle`/`icon-equip` 顶替: 这里说的是「近战/远程/火山形态」,
		##   不是「龟」也不是「装备」 —— 语义不符的图不往上放(素材铁律)。已登进缺口表。
		label = "切换至远程形态" if host._codex_form_view else "切换至近战形态"
	else:
		label = "切换至普通形态" if host._codex_form_view else "切换至火山形态"
	var bg_hex = "#3a1810" if host._codex_form_view else "#2a1430"
	var border_hex = "#58d3ff" if host._codex_form_view else "#ff7043"
	var txt_hex = "#9fd8ff" if host._codex_form_view else "#ffae80"
	## ★★2026-09-27 这颗钮原来走 `host._add_rect(..., stroke=2.0)`, 而它内部是
	##   `UISkin.nine_if_big(196, 34, "panel-frame.png", …)` —— **34 < MIN_FRAME_PX(40)**
	##   ⇒ 静默退回 StyleBoxFlat(四边框 2px + 底 a=0.92)= 门禁定义的**网页盒**。
	##   而它只在双形态龟(双头/熔岩)那两只身上画, `verify_ui_consistency` 只量列表
	##   第一条 ⇒ **这个网页盒从来没被数到过**(棘轮基线 Codex web≤0 一直绿着)。
	##   改挂边带只有 4px 的 chip-frame(与牌子/普攻条同一张), 34 高装得下。
	_plaque(btn_x - btn_w / 2.0, btn_y - btn_h / 2.0, btn_w, btn_h, border_hex, bg_hex)
	host._add_text(btn_x, btn_y, label, 14, txt_hex, 0.5, 0.5, true)
	var hitb = Control.new()
	hitb.position = Vector2(btn_x - btn_w / 2.0, btn_y - btn_h / 2.0)
	hitb.size = Vector2(btn_w, btn_h)
	hitb.mouse_filter = Control.MOUSE_FILTER_STOP
	hitb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var pet_ref: Dictionary = pet
	hitb.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			host._codex_form_view = not host._codex_form_view
			_show_pet(pet_ref))
	host.detail.add_child(hitb)



## ★每张卡收到【自己那段正文】的高度(2026-08-15, 用户点名"短的留大片空白、长的被切")。
##
## 改前实测(小龟 4 张卡, 卡内余白): 普攻卡 138px 全空, 另外两张反而【溢出 22 / 42px 被切掉】——
## 一排等高卡片, 高度是照最长的那条定的, 于是最短的那张空掉一半、最长的那张还是不够。
##
## ★必须等一帧才量: RichTextLabel 刚 add_child 时没排版, get_content_height() 返回 0
##   ⇒ 每张卡都会被收成最矮的 CARD_MIN_H(而且不报错)。这跟 _mark_card_clipped 是同一个坑。
## ★只等【一帧】: _mark_card_clipped 等两帧, 靠这个差值保证"先收高、再判还超不超"的顺序。
func _fit_skill_cards(parts: Array, top: float, max_h: float) -> void:
	await host.get_tree().process_frame
	if not is_instance_valid(host) or host.detail == null:
		return
	## ★2026-10-08 竖排: 每张卡收完高度后, 下一张紧接着它的底边排(各卡高度不同)。
	##   卡里的图标/名字/chip 是 detail 的直接子节点(门禁按 detail 的子节点数富文本), 不能装进容器整体挪 ——
	##   所以每张卡记下自己建过的节点和起始 y, 这里按差值整体平移。
	var y: float = top
	for p in parts:
		var panel: Panel = p["panel"]
		var rt: RichTextLabel = p["rt"]
		var hit: Control = p["hit"]
		if not (is_instance_valid(panel) and is_instance_valid(rt) and is_instance_valid(hit)):
			continue
		var dy: float = y - float(p["y0"])
		for nd in p["nodes"]:
			if is_instance_valid(nd) and nd is Control:   # 先判有效再 is(对已释放对象 is 会报错, freed_is_order 审计)
				(nd as Control).position.y += dy
		rt.position.y += dy
		## 卡高 = 正文起点 + 正文 + 间隙 + **底部边带**(金属九宫格 13px 厚, 内容区真的变小了)。
		var want: float = clampf(CARD_BODY_TOP + rt.get_content_height() + CARD_BODY_GAP
			+ CARD_PAD, CARD_MIN_H, max_h)
		## ★高度对齐整行, 但**只在真的装不下时才这么做**:
		##   没顶到上限就按内容实际高度给足(不切、也就不需要提示);
		##   顶到上限了才向下取整到整行(避免半截字悬在卡底), 这时提示才该出现。
		var body_h: float = want - CARD_BODY_TOP - CARD_BODY_GAP - CARD_PAD
		var clamped: bool = want >= max_h - 0.5
		if clamped:
			## ★2026-10-07 G: 按【这段正文自己的行边界】取整, 不按"标称行高"取整
			##   (带行内图标的行比纯文字行高, 实测 20 vs 24)。get_line_offset(i) = 第 i 行的上沿。
			var cut: float = 0.0
			for li in range(1, rt.get_line_count()):
				var off: float = rt.get_line_offset(li)
				if off <= body_h + 0.5:
					cut = off
				else:
					break
			if cut > 0.0:
				body_h = cut
				## ★卡高跟着截断收回来(2026-10-08 实拍): 第三行带行内图标(行高 24 > 20)放不下时只剩两行,
				##   卡却仍按三行的高度画 ⇒ 两行字下面空一截。竖排下这截空白会把下面的卡整体往下推。
				want = maxf(CARD_MIN_H, CARD_BODY_TOP + body_h + CARD_BODY_GAP + CARD_PAD)
		else:
			body_h = maxf(body_h, rt.get_content_height())
		panel.position.y = y
		panel.custom_minimum_size.y = want
		panel.size.y = want
		hit.position.y = y
		hit.size.y = want
		rt.custom_minimum_size.y = body_h
		rt.size.y = body_h
		## 「查看全部」画在这张卡**名字行**的右端(竖排后不在卡底另占提示带)。
		_card_hint_y[rt] = y + CARD_PAD + 4.0
		y += want + CARD_GAP


## 内联技能详情 (1:1 PoC renderSkillDetailSection CodexScene.ts:532-568): 顶"← 返回列表"(蓝) + 标题行(图标+★+名32px+CD) + 完整 host.detail #fff 13px
func _render_skill_detail_inline(pet: Dictionary, ctx: Dictionary, sk: Dictionary, top: float) -> void:
	# 返回钮 100×34, fill #1a2740@0.9 边 #58d3ff 1px@0.6; 文字 14px #58d3ff (PoC L539-549)
	## ★2026-10-08 两栏: 内联详情只占右栏, 左栏立绘与属性保持可见。
	host._add_rect(RCOL_X + 50.0, top + 17.0, 100, 34, "#1a2740", 0.9, "#58d3ff", 1, 0.6)
	host._add_text(RCOL_X + 50.0, top + 17.0, "← 返回", 14, "#58d3ff", 0.5, 0.5)
	var bhit = Control.new()
	bhit.position = Vector2(RCOL_X, top)
	bhit.size = Vector2(100, 34)
	bhit.mouse_filter = Control.MOUSE_FILTER_STOP
	bhit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bhit.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			host._codex_skill_detail = {}
			_show_pet(pet))   # host._codex_form_view 保留 → 返回到形态/普通列表 (PoC isForm?'form-list':'skill-list')
	host.detail.add_child(bhit)
	# 标题行 (PoC L552-558 addDomHTML(160,283) origin(0,0)): 图标40 inline + ★(默认绿) + 名32px#ffd93d + CD chip 20px#06d6a0
	# 默认技能判定: 形态视图不算默认 (PoC isDefault = !isForm && defaultSkills.includes(idx))
	var is_default = false
	if not host._codex_form_view:
		var sp = pet.get("skillPool", [])
		if sp is Array:
			var dfs = pet.get("defaultSkills", [0, 1, 2])
			is_default = (sp as Array).find(sk) in dfs
	# 图标解析同技能卡 (1:1 PoC skillIconHtml): 有png用; 否则 enhancesPassive→取被动图标
	var icon: String = str(sk.get("icon", ""))
	var icon_src: String = ""
	if icon.ends_with(".png"):
		icon_src = icon
	elif sk.get("enhancesPassive", false) and not (pet.get("passive", {}) as Dictionary).is_empty():
		var pic: String = DataRegistry.passive_icons.get(pet.get("passive", {}).get("type", ""), "")
		if pic.ends_with(".png"):
			icon_src = pic
	var sp_role: Array = pet.get("skillPool", []) if pet.get("skillPool") is Array else []
	var role_d: String = host._skill_role(str(pet.get("id", "")), sk, sp_role.find(sk))
	var bb = ""
	if icon_src != "":
		bb += "[img=40x40]res://assets/sprites/%s[/img] " % icon_src
	if is_default:
		bb += "[color=#06d6a0][font_size=28]★[/font_size][/color] "
	bb += "[color=#ffd93d][font_size=32]%s[/font_size][/color]" % str(sk.get("name", "?"))
	if role_d == "active":   # 龟能口径: 主动技显龟能花费 (无"CD"); 攒满龟能自动施放
		## ★2026-10-01: 「龟能100」→「龟能 100」。codex_text_lint 有一条「汉字贴着数字」,
		##   它只扫 data/*.json 的玩家文案, 扫不到这里拼出来的屏幕串 —— 所以这处一直漏着。
		bb += "　[color=#06d6a0][font_size=20]龟能 %d[/font_size][/color]" % host._skill_energy(sk)
	var title = RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 内联图标像素锐利
	title.position = Vector2(RCOL_X + 116.0, top + 3.0)
	title.custom_minimum_size = Vector2(_rw() - 116.0, 48)
	title.add_theme_font_size_override("normal_font_size", 32)
	title.add_theme_color_override("default_color", Color("#ffffff"))
	title.text = bb
	host.detail.add_child(title)
	## 完整正文。★字号 13 → 17: 这是"点开技能看全部"的落地页, 全项目最小的字放在这里最没道理
	##   (同一屏的装备效果正文是 19)。★fit_content 撑高 + 外层详情自己会滚(2026-08-03),
	##   不再自己开 scroll_active —— 框里套框的滚动条玩家根本发现不了。
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.position = Vector2(RCOL_X, top + 58.0)
	rt.custom_minimum_size = Vector2(_rw(), 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	var _sk_src: String = str(sk.get("detail", sk.get("brief", "")))
	rt.text = SkillText.render_bbcode(_sk_src, ctx, sk, 17)
	## ★2026-10-01 专名解释行(用户「要，加在详细说明底部」)。只加在**详细**这一层:
	##   商店那个 246px 的说明框实测加上之后要滚的从 3 件涨到 7 件 —— 那是销售文案, 不是资料页。
	var _g := SkillText.glossary_bb(_sk_src, 17)
	if _g != "":
		rt.text += "

" + _g
	host.detail.add_child(rt)


## 内联被动详情 (1:1 PoC renderPassiveDetailSection CodexScene.ts:572-582): 完整 desc 占下方区
func _render_passive_detail_inline(pet: Dictionary, ctx: Dictionary, top: float) -> void:
	var passive: Dictionary = pet.get("passive", {})
	if passive.is_empty():
		return
	var full_desc: String = str(passive.get("desc", passive.get("brief", "")))
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.position = Vector2(RCOL_X, top)
	rt.custom_minimum_size = Vector2(_rw(), 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.text = SkillText.render_bbcode(full_desc, ctx, passive, 17)
	var _g2 := SkillText.glossary_bb(full_desc, 17)   # 专名解释行(同上)
	if _g2 != "":
		rt.text += "

" + _g2
	host.detail.add_child(rt)


# ─── 其余 tab 详情 (沿用同详情容器, 数据 1:1) ───
# 装备详情: 消耗品(all_equipment, 有 category=consumable+desc) 与 p2eq(phase2_equipment, 有 cost) 两种数据形态。
# ─── 其余 tab 详情 (沿用同详情容器, 数据 1:1) ───
# 装备详情: 消耗品(all_equipment, 有 category=consumable+desc) 与 p2eq(phase2_equipment, 有 cost) 两种数据形态。
func _show_equip(eq: Dictionary) -> void:
	if eq.get("category", "") == "consumable":
		_show_consumable(eq)
	else:
		_show_p2eq(eq)


# ── p2eq 装备详情 (data/phase2-equipment.json 字段) ──
#   头图: PNG 图标(img·2026-07-18装备图标)→无 img 才 emoji 徽章兜底。名 + 费用 + 类型(p2eq-types) + 类型(p2eq-types) + 属性(EquipStats.STATS) + 效果(effectDesc1/3)。
# ── p2eq 装备详情 (data/phase2-equipment.json 字段) ──
#   头图: PNG 图标(img·2026-07-18装备图标)→无 img 才 emoji 徽章兜底。名 + 费用 + 类型(p2eq-types) + 类型(p2eq-types) + 属性(EquipStats.STATS) + 效果(effectDesc1/3)。
func _show_p2eq(eq: Dictionary) -> void:
	host._clear_detail()
	var cost: int = int(eq.get("cost", 0))
	var ccol: String = host.COST_COLOR.get(cost, "#4cc9f0")
	var rcol: String = ccol
	var emoji: String = str(eq.get("emoji", "📦"))
	# 头图区: PNG 图标(新版 img·2026-07-18装备图标)→无则 emoji 徽章框兜底 (中心锚 @(60,70))
	var img: String = str(eq.get("img", ""))
	var ipath: String = "res://assets/sprites/%s" % img if img.ends_with(".png") else ""
	host._add_rect(60, 70, 90, 90, "#12202a", 0.55, rcol, 2.0, 0.9)
	if ipath != "" and ResourceLoader.exists(ipath):
		host._add_image(60, 70, ipath, 78, 78, true)
	else:
		host._add_text(60, 70, emoji, 44, rcol, 0.5, 0.5, true)
	# 名 30px 黄 + 副标(费用 · 类型)
	host._add_text(130, 34, eq.get("name", "?"), 30, "#ffd93d", 0.0, 0.5, true)
	## ★2026-08-15 副标原来【一行说完费用+类型】; 2026-10-10 类型挪到页底「羁绊」那一块
	##   (那里同时写每档给什么), 副标只留费用 —— 同一个类型标签一屏只出现一次(verify_codex_layout ⑥)。
	## ★费用 0 = 盾羁绊赠送的圣光护盾, 它不上商店所以没有费用; 写"费用 0"读起来像"免费"。
	##   左栏分组标题早就写的是"羁绊赠送"(list_builder.gd:178), 详情跟着对齐。
	var sub: String = ("羁绊赠送" if cost <= 0 else "费用 %d" % cost)
	var sub_bb: String = sub
	var subrt := RichTextLabel.new()
	subrt.bbcode_enabled = true
	subrt.fit_content = true
	subrt.scroll_active = false
	subrt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 行内图标像素锐利(同 735 行)
	## y 跟原来的 `_add_text(..., oy=0.5)` 逐像素对齐: 中心 74 − 行高(17×1.3)/2。
	subrt.position = Vector2(130.0, 74.0 - 17.0 * 1.3 / 2.0)
	subrt.custom_minimum_size = Vector2(host.DETAIL_W - 150.0, 22.0)
	subrt.add_theme_font_size_override("normal_font_size", 17)
	subrt.add_theme_color_override("default_color", Color(ccol))
	subrt.text = sub_bb
	host.detail.add_child(subrt)

	## ── 以下各块【按实测高度顺排】(2026-08-15) ────────────────────────────
	## 原来是一串写死的绝对 y(134/154/200/224…): 上面任何一块长了就压住下一块、短了就留洞。
	## 现在每块画完问它自己占了多高, 下一块接着画。
	##
	## ★★2026-10-10 整页按云顶装备卡/技能卡重排(用户「左轮手枪玩家看到的是什么东西」「这有任何其他游戏是这样的吗」)。
	##   参考 docs/plans/ref/20261006-云顶装备弹窗/ 5(装备卡: 名字 → 一排属性图标+数 → 一段效果)、
	##   6/7(技能卡: 正文只写当前那一档的数, 底下一张分档表「名字 [ a / b / c ]」, 当前档亮、另两档暗)。
	##   改前三个毛病: ① 简述 + 全文说两遍且数对不上(简述「150/310/1200 点」, 全文「150/310/1200+3/5/9×攻击力」)
	##   ② 三档挤成「150/310/1200+3/5/9×攻击力」靠三色 + 页底图例读 ③ 羁绊只写「装满 3/6/9 件」不说是哪个羁绊、每档给什么。
	##   ⇒ 右上 ★1/★2/★3 选档(默认 ★1) → 属性一排(图标 + 当前档的数) → 效果一段(只有当前档的数) → 分档表 → 羁绊(名字 + 逐档效果)。
	##   简述(effectBrief)只在商店/背包这类小框里用, 图鉴不再显示。
	const HEAD_SIZE := 17     # 小标题(原来 14 —— 比它自己的正文 19 还小一大截)
	const BLOCK_GAP := 20.0
	var _eid: String = str(eq.get("id", ""))
	var _no_star: bool = _EquipPoolRef.NO_STAR.has(_eid)
	if _eid != _eq_star_for:   # 换了一件装备 ⇒ 回到 ★1
		_eq_star_for = _eid
		_eq_star = 1
	var _full_plain: String = SkillText.equip_full(eq)
	var d3: String = SkillText.render_consts(str(eq.get("effectDesc3", "")))
	var _st_rows: Array = host.EquipStats.stat_lines_all_stars(_eid)
	## 有没有分档: 效果正文里有「a/b/c」, 或某条属性三档不同。不升星的件(096)永远只有一档 ⇒ 不给选档。
	var _tiered: bool = not _no_star and (not tier_matches(_full_plain + "\n" + d3).is_empty() or _stats_tiered(_st_rows))
	var star: int = _eq_star if _tiered else 0
	if _tiered:
		_star_selector(eq)
	var y := 130.0

	# 属性 —— 取自 host.EquipStats.STATS(战斗实装的同一张表), 不打印 data 里手写的 baseStats1。
	host._add_text(20, y, "属性", HEAD_SIZE, "#58d3ff", 0.0, 0.0, true)
	y += 26.0
	var srt := RichTextLabel.new()
	srt.bbcode_enabled = true; srt.fit_content = true; srt.scroll_active = false
	srt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	srt.position = Vector2(20, y)
	srt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	srt.add_theme_font_size_override("normal_font_size", 19)
	srt.add_theme_color_override("default_color", Color("#e8f2ff"))
	srt.text = stat_row_bb(_eid, maxi(1, star), 19)
	srt.set_meta("codex_eq_stats", true)
	host.detail.add_child(srt)
	y += maxf(24.0, srt.get_combined_minimum_size().y) + BLOCK_GAP

	# 效果 —— 一段, 只写当前选中那一档的数(★2 时「150/310/1200+3/5/9×攻击力」读作「310+5×攻击力」)。
	host._add_text(20, y, "效果", HEAD_SIZE, "#58d3ff", 0.0, 0.0, true)
	y += 26.0
	var bb: String = star_text_bb(_full_plain, star, 19)
	## ★{C:} 要先展开(render_consts)—— 原来裸取 effectDesc3 会把 {C:类.常量} 原样显示给玩家。
	if d3.strip_edges() != "":
		bb += "\n\n" + star_text_bb(d3, star, 19)
	## ★专名解释行要盖住【这一屏显示的全部文字】(096 的【最终造物】只出现在 desc3 里)。
	var _gloss := SkillText.glossary_bb(_full_plain + "\n" + d3, 17)
	if _gloss != "":
		bb += "\n\n" + _gloss
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, y)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	## ★字号 19(2026-08-14): 图鉴是"专门来看资料"的地方, 正文不能是全项目最小的一处。
	rt.add_theme_font_size_override("normal_font_size", 19)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.add_theme_constant_override("line_separation", 6)
	rt.text = bb
	rt.set_meta("codex_eq_effect", true)
	host.detail.add_child(rt)
	y += maxf(24.0, rt.get_combined_minimum_size().y) + BLOCK_GAP

	# 分档表 —— 每个分档的量一行, 三档并排, 当前档亮、另两档暗(云顶技能卡底部那张表)。
	if _tiered:
		var lines: PackedStringArray = tier_breakdown_lines(_full_plain + "\n" + d3, _st_rows, star)
		if not lines.is_empty():
			_row_rule_full(y - BLOCK_GAP / 2.0)
			var brt := RichTextLabel.new()
			brt.bbcode_enabled = true; brt.fit_content = true; brt.scroll_active = false
			brt.position = Vector2(20, y)
			brt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
			brt.add_theme_font_size_override("normal_font_size", 18)
			brt.add_theme_color_override("default_color", Color("#aab8c6"))
			brt.add_theme_constant_override("line_separation", 4)
			brt.text = "\n".join(lines)
			brt.set_meta("codex_eq_tiers", lines.size())
			host.detail.add_child(brt)
			y += maxf(24.0, brt.get_combined_minimum_size().y) + BLOCK_GAP

	## ── 羁绊: 写出是哪个羁绊(图标 + 名字) + 每档给什么(与羁绊页同一份 Phase2Types.TIER_DESCS) ──
	## ★类型标签(图标 + 名字)全屏只出现在这里一次 —— 头顶副标只写费用(2026-08-15 用户「有没有说两遍的信息」)。
	var _tps: Array = host.Phase2Types.types_of(_eid)
	if not _tps.is_empty():
		host._add_text(20, y, "羁绊", HEAD_SIZE, "#58d3ff", 0.0, 0.0, true)
		y += 28.0
		for tp1 in _tps:
			var tname: String = str(tp1)
			var tiers: Array = (host.Phase2Types.TYPES.get(tname, {}) as Dictionary).get("tiers", [])
			if tiers.is_empty():
				continue
			y = _synergy_block(tname, tiers, y) + 12.0


## 羁绊一块: 「[图标] 名字」一行 + 逐档「N 件  效果」。返回块底 y。
func _synergy_block(tname: String, tiers: Array, y: float) -> float:
	var tcol: String = host._type_color(tname)
	var tic: String = host._type_icon(tname)
	var head := RichTextLabel.new()
	head.bbcode_enabled = true; head.fit_content = true; head.scroll_active = false
	head.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.position = Vector2(20, y)
	head.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	head.add_theme_font_size_override("normal_font_size", 18)
	head.add_theme_color_override("default_color", Color(tcol))
	## 图标 16: 源图 32×32 硬边像素画, 只有 32 与 16 保得住像素网格。
	head.text = ("[img=16x16]%s[/img] " % tic if tic != "" else "") + "[b]%s[/b]" % tname
	head.set_meta("codex_eq_synergy", tname)
	host.detail.add_child(head)
	y += maxf(24.0, head.get_combined_minimum_size().y) + 4.0
	var descs: Array = host.Phase2Types.TIER_DESCS.get(tname, [])
	var parts: PackedStringArray = []
	for i in range(tiers.size()):
		var txt: String = SkillText.render_consts(str(descs[i])) if i < descs.size() else ""
		parts.append("[color=%s][b]%d 件[/b][/color]  %s" % [tcol, int(tiers[i]), txt])
	var body := RichTextLabel.new()
	body.bbcode_enabled = true; body.fit_content = true; body.scroll_active = false
	body.position = Vector2(20, y)
	body.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	body.add_theme_font_size_override("normal_font_size", 16)
	body.add_theme_color_override("default_color", Color("#c8d4e0"))
	body.add_theme_constant_override("line_separation", 5)
	body.text = "\n".join(parts)
	host.detail.add_child(body)
	return y + maxf(24.0, body.get_combined_minimum_size().y)


## 整幅宽的细线(分档表上方), 与两栏竖分隔线同色同透明度。
func _row_rule_full(y: float) -> void:
	host._add_rect(host.DETAIL_W / 2.0, y, host.DETAIL_W - 40.0, 1, "#ffd93d", 0.3)


# ─── 装备页的星级选择 ───
## 图鉴里看的是哪一档(1~3)。换一件装备回到 ★1。
var _eq_star: int = 1
var _eq_star_for: String = ""
const STAR_CHIP_W := 56.0
const STAR_CHIP_H := 36.0
const STAR_HIT_H := 48.0

## 右上角三块签牌 ★1 / ★2 / ★3(与龟页签牌同一张 chip-frame), 当前档金色, 另两档暗。点一下换档重画。
func _star_selector(eq: Dictionary) -> void:
	var x0: float = float(host.DETAIL_W) - 20.0 - 3.0 * STAR_CHIP_W - 2.0 * 8.0
	var cy := 52.0
	for s in [1, 2, 3]:
		var x: float = x0 + float(s - 1) * (STAR_CHIP_W + 8.0)
		var on: bool = s == _eq_star
		var col: String = "#ffd93d" if on else "#5f7186"
		var p: Panel = _plaque(x, cy - STAR_CHIP_H / 2.0, STAR_CHIP_W, STAR_CHIP_H, col)
		p.name = "EqStar%d" % s
		_chip_text(x + 6.0, cy - 12.0, STAR_CHIP_W - 12.0, 24.0, "★%d" % s, 18, col)
		var hit := Control.new()
		hit.name = "EqStarHit%d" % s
		## 点击区比签牌大一圈: 手机上手指的最小热区 44(verify_ui_consistency「热区不足」同一个数), 签牌只画 36 高。
		hit.position = Vector2(x - 4.0, cy - STAR_HIT_H / 2.0)
		hit.size = Vector2(STAR_CHIP_W + 8.0, STAR_HIT_H)
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var eq_ref: Dictionary = eq
		var s_ref: int = s
		hit.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_set_eq_star(eq_ref, s_ref))
		host.detail.add_child(hit)


## 换档并重画(点签牌 / 门禁 / 截图探针共用这一个入口)。
func _set_eq_star(eq: Dictionary, s: int) -> void:
	_eq_star_for = str(eq.get("id", ""))
	_eq_star = clampi(s, 1, 3)
	_show_p2eq(eq)


# ─── 分档文字的拆分(纯函数, 门禁直接调) ───
## 恰好三档的「a/b/c」: 前后都不许再贴着数字或斜杠 —— 「80/110/130/160」这种四段的(斧头进化阈值)不是星级分档。
const TIER_PAT := "(?<![\\d./])(\\d+(?:\\.\\d+)?)/(\\d+(?:\\.\\d+)?)/(\\d+(?:\\.\\d+)?)(?![\\d/]|\\.\\d)"
const TIER_HI := "#ffd93d"      # 当前档(与签牌选中色同一个)。★只上色不加粗: 粗体走另一套像素字, 数字会小一号(实拍)
const TIER_DIM := "#7d8ea0"     # 另两档(与 SkillText.highlight_star 的压暗色同一个, 对比度 4.9:1)
static var _tier_re: RegEx = null

static func tier_matches(t: String) -> Array:
	if _tier_re == null:
		_tier_re = RegEx.create_from_string(TIER_PAT)
	return _tier_re.search_all(t)


## 纯文本里每个「a/b/c」换成第 star 档的那一个数; star=0 原样返回。
## mark=true 时数字两边夹私用区字符, 上色后再换成 BBCode(上色管线认的是纯文本, 不能先塞 BBCode 进去)。
static func collapse_tiers(t: String, star: int, mark: bool = false) -> String:
	if star < 1 or star > 3:
		return t
	var out := ""
	var pos := 0
	for m in tier_matches(t):
		out += t.substr(pos, m.get_start() - pos)
		var v: String = m.get_string(star)
		out += ("\uE000%s\uE001" % v) if mark else v
		pos = m.get_end()
	return out + t.substr(pos)


## 效果正文(纯文本) → 只剩当前档的数、数字加亮, 关键词上色与内联属性图标照 SkillText 同一条管线。
static func star_text_bb(plain: String, star: int, font_px: int) -> String:
	var bb: String = SkillText.plain_to_bb(collapse_tiers(plain, star, true), font_px)
	return bb.replace("\uE000", "[color=%s]" % TIER_HI).replace("\uE001", "[/color]")


## 一组三档 → 「a / b / c」, 第 star 档亮、另两档暗。
static func tier_triplet_bb(vals: Array, star: int) -> String:
	var ps: PackedStringArray = []
	for i in range(vals.size()):
		var v: String = str(vals[i])
		ps.append(("[color=%s]%s[/color]" % [TIER_HI, v]) if i == star - 1 else ("[color=%s]%s[/color]" % [TIER_DIM, v]))
	return (" [color=%s]/[/color] " % TIER_DIM).join(ps)


## 属性里有没有哪一条三档不同。
static func _stats_tiered(rows: Array) -> bool:
	for kv in rows:
		if str(kv[1]).contains("/"):
			return true
	return false


## 属性一排: [图标] +数 名字 —— 第 star 档的值(云顶装备卡那一排「图标 + 数」, 名字小一号暗灰跟在数后面, 与龟页读法相同)。
const STAT_ICON_KEY := {"攻击力": "atk", "最大生命值": "hp", "护甲": "def", "魔抗": "mr", "暴击率": "crit",
	"暴击伤害": "crit-dmg", "护甲穿透": "armorpen", "魔法穿透": "magicpen", "生命偷取": "lifesteal",
	"闪避": "dodge", "反伤": "reflect", "治疗增幅": "healamp", "护盾增幅": "shieldamp",
	"治疗与护盾增幅": "shieldheal", "初始龟能": "maxenergy", "龟能充能速率": "echarge", "射程": "range",
	"攻击速度": "aspd", "移动速度": "move", "攻击射程": "range"}

static func stat_row_bb(eid: String, star: int, font_px: int) -> String:
	var kvs: Array = _EquipStatsRef.stat_lines(eid, star)
	if kvs.is_empty():
		return "[color=#8c9cab]无属性加成[/color]"
	var ipx: int = maxi(12, roundi(float(font_px) * 1.15))
	var ps: PackedStringArray = []
	for kv in kvs:
		var key: String = str(STAT_ICON_KEY.get(str(kv[0]), ""))
		var ip: String = "res://assets/sprites/stats/%s-icon.png" % key
		var seg := ""
		if key != "" and ResourceLoader.exists(ip):
			seg += "[img width=%d color=#%s]%s[/img] " % [ipx, SkillText.stat_icon_color_of(ip).to_html(false), ip]
		seg += "%s [font_size=%d][color=#8c9cab]%s[/color][/font_size]" % [str(kv[1]), maxi(14, font_px - 4), str(kv[0])]
		ps.append(seg)
	return "      ".join(ps)


## 分档表的行: 先属性(三档不同的那几条), 再效果正文里每一句带分档的话。
## ★效果那一行【不另起名字】—— 名字从原句里截(按 ，。；、：换行 切句), 分档数换成「a / b / c」。
##   起名字要猜「这个数是什么」, 猜错就是在骗人; 原句本身就是这个数的说明。
static func tier_breakdown_lines(plain: String, stat_rows: Array, star: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for kv in stat_rows:
		var v: String = str(kv[1])
		if not v.contains("/"):
			continue
		out.append("[color=#c8d4e0]%s[/color]  %s" % [str(kv[0]), tier_triplet_bb(Array(v.split("/")), star)])
	var seen := {}
	for clause in _tier_clauses(plain):
		if seen.has(clause):
			continue
		seen[clause] = true
		var line := ""
		var pos := 0
		## ★一句里有两组以上分档时每组加方括号(2026-10-10 实拍:「150 / 310 / 1200+3 / 5 / 9×攻击力」读成「1200+3」)。
		##   照云顶技能卡「[450% / 450% / 1000%]」的写法; 字面方括号在 BBCode 里要写 [lb]/[rb]。
		var ms: Array = tier_matches(clause)
		var wrap: bool = ms.size() >= 2
		for m in ms:
			## 原句的空格原样留着(「造成 150/310/1200 + …」与「4/6/15%自身…」两种写法都有), 不另加。
			line += "[color=#c8d4e0]%s[/color]" % clause.substr(pos, m.get_start() - pos)
			var trip := tier_triplet_bb([m.get_string(1), m.get_string(2), m.get_string(3)], star)
			line += ("[color=%s][lb][/color]%s[color=%s][rb][/color]" % [TIER_DIM, trip, TIER_DIM]) if wrap else trip
			pos = m.get_end()
		line += "[color=#c8d4e0]%s[/color]" % clause.substr(pos)
		out.append(line.strip_edges())
	return out


## 正文切句, 只留带分档的那几句; 去掉句首连接词、补齐落单的括号。
const CLAUSE_SEP := "，。；、：\n,;"
static func _tier_clauses(plain: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur := ""
	for ch in plain + "\n":
		if CLAUSE_SEP.contains(ch):
			var c := cur.strip_edges()
			cur = ""
			if c == "" or tier_matches(c).is_empty():
				continue
			for lead in ["并且", "并", "且", "外加", "此外", "随后"]:
				if c.begins_with(lead):
					c = c.substr(str(lead).length()).strip_edges()
					break
			if c.count("（") > c.count("）"):
				c = c.replace("（", "")
			elif c.count("）") > c.count("（"):
				c = c.replace("）", "")
			out.append(c)
		else:
			cur += ch
	return out


# ── 消耗品详情 (all_equipment category=consumable; 有 PNG icon + desc + target) ──
# ── 消耗品详情 (all_equipment category=consumable; 有 PNG icon + desc + target) ──
func _show_consumable(eq: Dictionary) -> void:
	host._clear_detail()
	var icon: String = str(eq.get("icon", ""))
	if icon.ends_with(".png"):
		host._add_image(90, 90, "res://assets/sprites/%s" % icon, 120, 120, true)
	host._add_text(180, 34, eq.get("name", "?"), 30, "#ffd93d", 0.0, 0.5, true)
	# 副标一行说完【消耗品 + 作用目标】(原来是两个 Label 硬摆在 x=180 和 x=240, 名字一长就撞)
	var tgt: String = str(eq.get("target", ""))
	var tgt_label: String = str({"ally": "作用于友方", "enemy": "作用于敌方"}.get(tgt, ""))
	host._add_text(180, 72, "消耗品" + ("   ·   " + tgt_label if tgt_label != "" else ""),
		16, "#06d6a0", 0.0, 0.5, true)
	host._add_text(20, 150, "效果", 17, "#58d3ff", 0.0, 0.0, true)
	var desc = SkillText.render_bbcode(str(eq.get("desc", "")), {"atk": 0, "def": 0, "mr": 0, "maxHp": 0}, {}, 17)
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	## ★正文挪到整幅宽(20)、不再缩在图右边那 720px 里 —— 图只有 120 高, 正文从它下面走。
	rt.position = Vector2(20, 176)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.text = desc
	host.detail.add_child(rt)


# ─── 类型羁绊详情 (2026-08-03 批1 取代学派详情) — 名 + 档阈值 + 成员装备 + 逐档效果文案 ───
#   数据: 类型定义 host.Phase2Types.TYPES(阈值) / 逐档文案 Phase2Types.TIER_DESCS / 成员装备 p2eq-types.json。
#   ★逐档文案【不再在图鉴里手抄一份】: 旧版 CodexScene.SCHOOL_EFFECTS 与 phase2_schools.gd 是两份
#   互相矛盾的口径(一份写"每2.5秒"、一份写"每回合开始")且都自称权威。现在只有 TIER_DESCS 一份。
#   排版骨架 1:1 沿用旧 _show_school, 只换数据源。
func _show_type(item: Dictionary) -> void:
	host._clear_detail()
	var tname: String = str(item.get("_type", ""))
	var def: Dictionary = host.Phase2Types.TYPES.get(tname, {})
	# 类型的色/图标只走 host 那一对取值函数 —— 三处各自 `TYPE_STYLE.get(...)` 加各自的兜底,
	# 正是「香火在羁绊页是 🔗、在装备页是 🗡️」那种两处默认值不一样的来源。
	var color: String = host._type_color(tname)
	var icon: String = host._type_icon(tname)
	var tiers: Array = def.get("tiers", [])
	var members: Array = _type_members(tname)   # [{id,name,emoji}], 该类型全部装备

	# 头图区: 类型色框 + 类型图标徽章
	host._add_rect(60, 70, 90, 90, "#12202a", 0.55, color, 2.0, 0.9)
	## ★★ 2026-09-28 从 44px 的 emoji 字换成 tags/ 的 32×32 像素图, **按 2x = 64 画**。
	##   44 是 1.375 倍 —— 非整数倍会把像素网格打烂; 这个框是 90×90, 64 装得下(四边各留 13)。
	## ★图标为空(表里没这个类型)就只留空框 —— 看得见的缺口好过兜底成别的类型的图。
	if icon != "":
		var _badge = host._add_image(60, 70, icon, 64, 64, true)   # host 无类型标注 ⇒ 返回 Variant, 不能用 :=
		if _badge != null:
			_badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 名 32px 类型色 + 副标 + 档阈值 / 成员件数
	host._add_text(130, 36, tname, 32, color, 0.0, 0.5, true)
	## ★副标不写 display_name —— 那返回「剑系」「弓箭·神射手」这类游戏里不存在的花名(用户 2026-08-14)。
	##   而且大标题已经写了类型名, 副标再写一遍就是同一屏说两遍。这里只说它【是什么】。
	host._add_text(130, 72, "装备羁绊", 15, "#888888", 0.0, 0.5)
	var thresh := ""
	for i in range(tiers.size()):
		thresh += ("" if i == 0 else " / ") + str(int(tiers[i]))
	# ★顶档 == 该类型【最终】件数是有意设计(方案书 D5)。批 3 加完 35 件之前顶档够不到,
	#   这里如实显示"现有 N 件", 玩家自己看得出还差几件, 不写"不可达"这种开发者口吻的字。
	host._add_text(130, 100, "激活 %s 件   ·   现有装备 %d 件" % [thresh, members.size()], 16, color, 0.0, 0.5, true)

	# 逐档效果文案 (事实源 Phase2Types.TIER_DESCS, 与背包羁绊面板同一份)
	host._add_text(20, 150, "羁绊效果", 17, "#58d3ff", 0.0, 0.0, true)
	var descs: Array = host.Phase2Types.TIER_DESCS.get(tname, [])
	var bb := ""
	for i in range(descs.size()):
		## ★2026-08-21 接上 {C:} 消费链: TIER_DESCS 原来是**直接拿原文显示**的,
		##   写 `{C:类名.常量}` 会原样漏给玩家(这正是 verify_code_const_token ⑦ 在守的那类事故)。
		##   过一遍 render_consts 之后, 羁绊文案就能直接引用代码常量、不再手抄。
		var txt: String = SkillText.render_consts(str(descs[i]))
		if txt.strip_edges() == "":
			continue
		var th: int = int(tiers[i]) if i < tiers.size() else 0
		bb += ("" if bb == "" else "\n\n") + "[color=%s][b]%d 件[/b][/color]  %s" % [color, th, txt]
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	## ★2026-08-15 改回撑高 + 让【外层详情】滚。原来是"固定 260px 框 + 框内自己滚":
	##   · 短的类型(剑 3 档)内容只有 ~150px ⇒ 框里空 110px, 而下面的成员清单又写死在 y=446,
	##     两处死空白叠一块;
	##   · 长的类型(弓箭/奇械 4 档)内容 300+px ⇒ 藏进一个【框中框】的滚动条里 ——
	##     详情面板本身已经是 ScrollContainer, 套两层滚动玩家根本发现不了里面还有内容。
	rt.fit_content = true
	rt.scroll_active = false
	rt.position = Vector2(20, 176)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.add_theme_constant_override("line_separation", 5)
	rt.text = bb.strip_edges()
	host.detail.add_child(rt)

	# 成员装备清单 (从 p2eq-types.json 反查). 3 列流式网格, 接着上面的效果文案往下排(不再写死 y=446)。
	var list_y: float = 176.0 + maxf(24.0, rt.get_combined_minimum_size().y) + 26.0
	## ★★2026-09-27 去掉括号计数。
	host._add_text(20, list_y, "同类装备", 17, "#58d3ff", 0.0, 0.0, true)
	var cols := 3
	var col_w: float = (host.DETAIL_W - 40.0) / float(cols)
	for i in range(members.size()):
		var m: Dictionary = members[i]
		var col: int = i % cols
		var row: int = int(i / cols)
		var mx: float = 24.0 + col * col_w
		## ★行高 26 → `MEMBER_ROW`(36): 图标要 1x = 32 画, 26 的行距会让上下两行的图重叠 6px。
		var my: float = list_y + 30.0 + row * MEMBER_ROW
		## ★★2026-09-28 行前缀从 emoji 换成**装备自己的 PNG 图标**。
		##   这一处是整屏最密的 emoji: 羽维页一张表就能列出十几件, 每件一个
		##   🗡/⚙/🍖…—— 而左栏列表早就画的是真图标。**同一件装备在两个地方两种长相。**
		## ★图从 `m["img"]` 来(96 件**全部**有 PNG 且图都在盘上, 已逐件查过),
		##   所以这条路不会退化成空白; 真的缺图才走后面那支只写名字。
		## ★尺寸的实情(量过, 不是拍的): 96 件装备的 PNG **尺寸不统一** ——
		##   51 张 64×64 / 27 张 32×32 / 剩下十几张是几百到 1024 的大图。
		##   所以装备图标本来就**做不到统一整数倍** ⇒ 跟着全项目既有的写法走:
		##   等比内缩到一个固定框(左栏列表 36×36 / 背包大格 44×36 / 详情头图 78×78)。
		##   这里取 32 —— 与左栏列表那一类尺寸相当, 且行高装得下。
		##   (本轮那批**新 UI 图标**是另一回事: 它们全是 32×32, 一律按整数倍画。)
		## ★画法走 `keep_aspect=true`: 源图里有非正方(489×510 等), 拉满会变形。
		var _mimg: String = str(m.get("img", ""))
		var _mpath: String = ("res://assets/sprites/" + _mimg) if _mimg.ends_with(".png") else ""
		if _mpath != "" and ResourceLoader.exists(_mpath):
			host._add_image(mx + MEMBER_ICON / 2.0, my + MEMBER_ICON / 2.0, _mpath, MEMBER_ICON, MEMBER_ICON, true)
			host._add_text(mx + MEMBER_ICON + 6.0, my + MEMBER_ICON / 2.0, str(m.get("name", "?")), 15, "#cdd6e0", 0.0, 0.5)
		else:
			host._add_text(mx, my + MEMBER_ICON / 2.0, str(m.get("name", "?")), 15, "#cdd6e0", 0.0, 0.5)


## 某类型的成员装备 [{id,name,emoji}], 反查 p2eq-types.json(经 host.Phase2Types.type_of)。
## 按 p2eq id 升序(= phase2_equipment 声明序), 与设计表一致。
func _type_members(tname: String) -> Array:
	var out: Array = []
	for eq in DataRegistry.phase2_equipment:
		if not (eq is Dictionary):
			continue
		var eid: String = str(eq.get("id", ""))
		## ★用 types_of 不是 type_of(2026-08-15)。type_of 只返回【第一个】类型,
		##   而 p2eq_093 香火石登记的是两个(遗物 + 香火, 用户 2026-08-13 拍板)
		##   ⇒ 香火那一页实拍是「该类型装备 (0)」, 一件都列不出来, 看着像功能没做完。
		if host.Phase2Types.types_of(eid).has(tname):
			out.append({"id": eid, "name": str(eq.get("name", eid)), "img": str(eq.get("img", ""))})
	return out



func _show_status(st: Dictionary) -> void:
	host._clear_detail()
	var icon_key: String = st.get("iconKey", "")
	host._add_image(70, 70, "res://assets/sprites/status/%s-icon.png" % icon_key.replace("status-", ""), 100, 100, true)
	var cat_label = {"dot": "持续伤害", "cc": "控制", "buff": "增益", "debuff": "减益"}
	host._add_text(140, 38, st.get("name", "?"), 32, "#ffd93d", 0.0, 0.5, true)
	host._add_text(140, 78, cat_label.get(st.get("category", ""), st.get("category", "")), 15, "#58d3ff", 0.0, 0.5, true)
	host._add_text(20, 150, "效果", 17, "#58d3ff", 0.0, 0.0, true)
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, 176)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	## ★2026-10-07: 状态说明里的数字走 `{C:类.常量}`(与龟/装备文案同一套), 不在 json 里手抄。
	##   原来这里是裸取 desc —— 写 {C:} 会原样漏给玩家, 所以要先过一遍 render_consts。
	rt.text = SkillText.render_consts(str(st.get("desc", "")))
	host.detail.add_child(rt)
	var formula: String = st.get("formula", "")
	if formula != "":
		## ★"生效公式"接着说明往下排。原来写死 y=240/264 —— 说明只要长过 64px 就会被公式压住,
		##   而 13 个状态里最长的那条正文改成 17px 之后就正好跨过这条线。
		var fy: float = 176.0 + maxf(24.0, rt.get_combined_minimum_size().y) + 26.0
		host._add_text(20, fy, "生效公式", 17, "#58d3ff", 0.0, 0.0, true)
		host._add_text(20, fy + 28.0, formula, 17, "#ffd93d", 0.0, 0.0, true)
