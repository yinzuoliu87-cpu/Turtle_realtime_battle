class_name UISkin
extends RefCounted
## 【共享皮肤层】—— 把「九宫格金属框」这套做法从战斗信息面板推到别的屏(2026-08-17)。
##
## ═══ 由来 ═══
## 通宵那一轮把战斗信息面板从"网页味"改成金属框(v0.19.199~216), 靠的是 5 张九宫格贴图。
## 收尾时把判据推到全部 7 个屏幕实测(`tests/_probe_webbox.gd`), 结果:
##
##   屏      stylebox  网页盒  圆角盒  九宫格
##   背包      54       44     54      0
##   图鉴     104       45     40      0
##   选龟     114       43    105      0
##   战斗面板   —        0      0      5     ← 全游戏唯一一个
##
## ⇒ 我把战斗面板做成金属框, **反而让它成了全游戏唯一一个** —— 这是我制造的新不一致。
##   (运行时那 132 个网页盒是循环放大出来的; **源点只有 25 处**, 所以改得动。)
##
## ═══ 为什么单独一个文件, 而不是把 info_panel 的 `_nine_box` 复制过来 ═══
## memory `fb-hand-rolled-copies-drift`:「手抄的副本必然落后 —— 抄一次永远落后一次」。
## 今晚已经在 `data_integrity.py` 里亲眼见过: 三条文案判据各自手抄了一份字段清单,
## 我扩了一条没扩另两条, 于是**同一个文件里出现三种覆盖面**。
## ⇒ 这里做成唯一出处; `info_panel.gd::_nine_box` 也改成委托给它。
##
## ═══ 铁律 ═══
## ① 贴图缺失必须**优雅退回**给调用方传的 `fallback` —— 不许崩、不许画成空白。
##    (`ResourceLoader.exists()` 对没有 `.import` 的 PNG 返回 **false** 且不报错, 这是个静默坑。)
## ② 状态色走 `modulate_color` 而不是各做一张图 —— 一张中性贴图 modulate 出所有状态,
##    否则"按状态配色"这套信息会被贴图吃掉(状态签那次的教训)。
## ③ 九宫格的**边距之和必须小于目标尺寸**, 否则中段是负的、框直接画不出来
##    (今晚栽过两次: 头像框 64→56、资源条 24→14)。调用方自己保证, 这里只提供工具。

const TEX_DIR := "res://assets/sprites/battlehud/"

## 【九宫格的最小可用尺寸】小于它就**不该**套框, 保持纯色块。
##
## ★由来(2026-08-18 实测退回): 背包卡片上 18 个迷你装备格只有 26px,
##   套上原生 57x57 的槽框后 —— 四角铆钉吃掉大半格子、图标没地方放,
##   更要命的是**费用色从「整块实心」退化成「一圈细边」, 而那块实心色本身就是信息**。
##   实拍对比后退回。
## ⇒ 这条教训不该只活在我脑子里, 焊成常量: 调用方用 `nine_if_big()` 自动降级。
##   40px 的来历: 槽框边距 12x2=24 + 中间至少留 16px 给内容。
const MIN_FRAME_PX := 40.0


## 尺寸够大才套九宫格, 否则原样退回 `fallback`(纯色块)。
static func nine_if_big(w: float, h: float, tex_name: String, margin: int, fallback: StyleBox) -> StyleBox:
	if w < MIN_FRAME_PX or h < MIN_FRAME_PX:
		return fallback
	return nine(tex_name, margin, fallback)



## 九宫格 StyleBox。贴图不在就原样返回 `fallback`(调用方给的 StyleBoxFlat)。
## ★★`tile`(2026-09-19): 中段**平铺**而不是拉伸。
##   九宫格默认是 STRETCH —— 控件比素材大不多时无害,
##   但匹配屏把 **64×64 的 `portrait-frame` 用在 200×200 控件上** ⇒
##   中段 32px 被拉到 168px = **5.25 倍**, 边上那排蓝宝石铆钉被拉扁成细线,
##   实拍出来只剩四个孤立的金角块 —— 我当时差点把它当成「占位符/调试辅助线」。
##   用 TILE_FIT 不用 TILE: TILE 会在末端留半个图案(左右不对称),
##   TILE_FIT 把平铺数取整后微调尺寸(168/5=33.6 ⇒ **1.05 倍**), 铆钉形状基本不变。
##   ★素材不动、尺寸不动, 只改“中段怎么填”。
static func nine(tex_name: String, margin: int, fallback: StyleBox, tile: bool = false) -> StyleBox:
	# 名字里带 "/" 就当成 assets/sprites/ 下的相对路径(战斗 HUD 那套冷色框不适合所有屏,
	# 木桌世界的几屏要用自己的暖色框 —— 见 teamselect/card-frame.png 的由来)。
	var p := ("res://assets/sprites/" + tex_name) if "/" in tex_name else (TEX_DIR + tex_name)
	if not ResourceLoader.exists(p):
		return fallback
	var st := StyleBoxTexture.new()
	st.texture = load(p)
	st.set_texture_margin_all(margin)
	if tile:
		st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		st.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return st


## 槽框(88px 那套的通用版)。`tint` 给状态色, `dim` 用于"空槽"。
##
## ★空槽压暗是**有来历的**: 战斗面板里那段"空槽画灰框"写了但从没生效过
##   (`_nine_box` 只在贴图缺失时才用兜底 StyleBoxFlat ⇒ 那两行 `if filled` 永远是死代码),
##   实拍空槽和满槽一模一样。修法就是这里的 `dim`。
static func slot(fallback: StyleBox, tint: Color = Color.WHITE, dim: bool = false) -> StyleBox:
	var sb := nine("slot-frame.png", 12, fallback)
	if sb is StyleBoxTexture:
		var t := tint
		if dim:
			t = Color(t.r * 0.55, t.g * 0.60, t.b * 0.70, 1.0)
		(sb as StyleBoxTexture).modulate_color = t
	return sb


## 给按钮套上金属签牌皮(三态)。
##
## ★由来: 用户 2026-08-18 问「所有可以点击和交互的地方都考虑了吗」——
##   实测答案是**没有**: 全项目 157 个可交互元素里, **12 个按钮还是 Godot 默认皮**
##   (主菜单 8 · 背包 2 · 图鉴 2), 圆角纯色, 是"没游戏味"最直接的来源。
##   (战斗面板的「✕」「详细」两个按钮当初也是这样, 而且**逃过了网页盒判据** ——
##    那条判据先查 `has_theme_stylebox_override`, 而默认主题不是 override。)
## ★三态靠 modulate 区分, 一张中性签牌管三态; `tint` 给按钮的语义色。
static func button(b: Button, tint: Color = Color.WHITE, margin: int = 7) -> void:
	## ★★按尺寸挑框(2026-08-19): 原来一律用 `chip-frame`(源图 **48x24**)。
	##   小签牌上没问题, 但返回键这类 120x81 的大按钮把它拉了 2.5~3.4 倍 ——
	##   **金属细节全被拉平, 看起来就是一块灰板**(实拍图鉴/排行榜/背包的返回键, 三个一模一样)。
	##   而 `menu/btn-frame.png` 源图 **893x212**, 本来就是给这个尺寸的按钮画的。
	##   判据用**按钮的真实尺寸**, 不是名字: 短边 ≥56 且面积 ≥5000 就换大框。
	##   ⚠ 要读 `b.size`, 而 `custom_minimum_size` 常常才是调用方设的值 —— 两个取大。
	var w: float = maxf(b.size.x, b.custom_minimum_size.x)
	var h: float = maxf(b.size.y, b.custom_minimum_size.y)
	var big: bool = minf(w, h) >= 56.0 and w * h >= 5000.0
	var tex := ("res://assets/sprites/menu/frame-rect.png" if big else TEX_DIR + "chip-frame.png")
	if not ResourceLoader.exists(tex):
		tex = TEX_DIR + "chip-frame.png"
	if not ResourceLoader.exists(tex):
		return                      # 贴图不在就保持调用方原样, 不动它
	var t: Texture2D = load(tex)
	## ★挑 `frame-rect` 而不是 `btn-frame`, 是**量出来的**, 不是挑好看的:
	##   btn-frame 666→893 宽里端花占 **101px**, 而返回键只有 120 宽 —— 左右各 101 根本放不下,
	##   九宫格会把两端花纹叠在一起(实拍是一坨糊的金色方块, 比原来那块灰板还糟)。
	##   frame-rect 666x161 的边带是 **27x28**: 27+27=54 < 120、28+28=56 < 81, 装得下。
	##   ⇒ **贴图有它的最小可用尺寸**; 判据是"边带×2 装不装得进按钮", 不是"哪张更华丽"。
	if big:
		margin = 27
	for st in [["normal", 1.0], ["hover", 1.22], ["pressed", 0.74],
			["focus", 1.0], ["disabled", 0.55]]:
		var sb := StyleBoxTexture.new()
		sb.texture = t
		sb.set_texture_margin_all(margin)
		var k := float(st[1])
		sb.modulate_color = Color(tint.r * k, tint.g * k, tint.b * k, 1.0)
		sb.content_margin_left = 10; sb.content_margin_right = 10
		sb.content_margin_top = 4; sb.content_margin_bottom = 4
		b.add_theme_stylebox_override(str(st[0]), sb)


## ══════════════════════════════════════════════════════════════════════
##  像素按钮皮(周末页 / 战绩页)—— 2026-10-07
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-10-07 看周日对阵图:「按钮框能不能换一种呢，这不适合我们啊」「参考别的游戏，别看仓库的」。
## 木牌(`frame-rect`)是主菜单擂台那一套暖色; 对阵图 / 赛况板 / 战绩页是深海军蓝 + 青色细边,
## 木牌压在上面就是两套世界。参考见 `docs/plans/ref/20261007-按钮参考/`(README 写了每张取什么):
##   主操作 = 1/2/8(indieklem 像素按钮四态 · 元气骑士实心按钮): 实心色块 + 顶 1px 亮线 + 底 3px 深色厚度
##            + 1px 深描边切角; 悬停 = 提亮; 按下 = 厚度变 1px、整体下移; 焦点 = 外圈亮描边。
##   页签   = 5/6(Children of Morta): 深底细边; 选中 = 青边 + 青色底杠。
## ★素材 `ui/pixel-btn.png` 是一张表(一格 40x36 = 逻辑 20x18 × 2 倍最近邻):
##   一个逻辑像素 = 屏上 2px, 与弹窗金属框 / 对阵图格子的像素格同一个尺度。
##   行: 红 / 金 / 石板 / 禁用 / 页签; 列: 常态 / 悬停 / 按下 / 焦点圈(页签行: 未选 / 未选悬停 / 选中 / 选中悬停)。
## ★为什么不像 `button()` 那样一张中性图 modulate 出状态: modulate 会把**深描边和底厚度一起染色**,
##   像素按钮的明暗关系就靠这三档色(亮线 / 本体 / 厚度)立住 ⇒ 每档单独画。
## ★九宫格边带: 左右 6 / 上 8 / 下 12(px), 最小可用尺寸 12x20 —— 这三屏最小的页签 132x81 远大于它。
## ⚠ 只给这几屏用; 全局 `button()` 不动(主菜单 / 商店 / 背包是擂台木牌那一套)。
const PIXEL_BTN := "res://assets/sprites/ui/pixel-btn.png"
const PX_CELL := Vector2(40.0, 36.0)
const PX_RED := "red"        # 观赛 / 直播(与「直播」「开播」小签同一种红)
const PX_GOLD := "gold"      # 观看 / 回放 / 开始对战
const PX_SLATE := "slate"    # 关闭 / 上一组 / 下一组 / 我的位置
const _PX_ROW := {"red": 0, "gold": 1, "slate": 2}
const _PX_ROW_DISABLED := 3
const _PX_ROW_TAB := 4
## 字色 / 描边色。金底亮, 白字压不住 ⇒ 深棕字、不描边(描边色不分状态, 浅金描边落到禁用的灰底上就是一圈黄晕);
## 红底白字深红描边; 石板白字近黑描边。描边色 a=0 ⇒ 不描边。
const _PX_FONT := {
	"red": [Color("#fff4ee"), Color("#4a0f0b")],
	"gold": [Color("#2e1a00"), Color(0, 0, 0, 0)],
	"slate": [Color("#e8f0f6"), Color("#0a0d16")],
}


## 表里的一格 → StyleBoxTexture。贴图不在就返回 null(调用方保持原样)。
static func _px_cell(row: int, col: int, pressed: bool = false) -> StyleBoxTexture:
	if not ResourceLoader.exists(PIXEL_BTN):
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = load(PIXEL_BTN)
	sb.region_rect = Rect2(col * PX_CELL.x, row * PX_CELL.y, PX_CELL.x, PX_CELL.y)
	sb.texture_margin_left = 6; sb.texture_margin_right = 6
	sb.texture_margin_top = 8; sb.texture_margin_bottom = 12
	sb.content_margin_left = 12; sb.content_margin_right = 12
	## 字落在本体的视觉中心(底下 6px 是厚度); 按下时厚度剩 2px、整体下移 2px, 字跟着下移 2px。
	sb.content_margin_top = 8 if pressed else 6
	sb.content_margin_bottom = 10 if pressed else 12
	return sb


## 像素按钮(实心色块)。`accent` = PX_RED / PX_GOLD / PX_SLATE。
static func pixel_button(b: Button, accent: String = PX_SLATE, outline: int = 4) -> void:
	var row: int = int(_PX_ROW.get(accent, 2))
	var styles := {
		"normal": _px_cell(row, 0), "hover": _px_cell(row, 1), "pressed": _px_cell(row, 2, true),
		"focus": _px_cell(row, 3), "disabled": _px_cell(_PX_ROW_DISABLED, 0),
	}
	if styles["normal"] == null:
		return
	for k in styles:
		b.add_theme_stylebox_override(str(k), styles[k])
	var fc: Array = _PX_FONT.get(accent, _PX_FONT["slate"])
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(s, fc[0])
	b.add_theme_color_override("font_disabled_color", Color("#8a909a"))
	b.add_theme_color_override("font_outline_color", fc[1])
	b.add_theme_constant_override("outline_size", outline if (fc[1] as Color).a > 0.0 else 0)


## 像素页签(深底细边)。`on` = 选中: 青边 + 青色底杠 + 亮字; 未选: 暗边暗字。切换选中时再调一次。
static func pixel_tab(b: Button, on: bool) -> void:
	var c0 := 2 if on else 0
	var styles := {
		"normal": _px_cell(_PX_ROW_TAB, c0), "hover": _px_cell(_PX_ROW_TAB, c0 + 1),
		"pressed": _px_cell(_PX_ROW_TAB, 2), "focus": StyleBoxEmpty.new(),
		"disabled": _px_cell(_PX_ROW_TAB, 0),
	}
	if styles["normal"] == null:
		return
	for k in styles:
		b.add_theme_stylebox_override(str(k), styles[k])
	var fc := Color("#e8fff8") if on else Color("#8fa0b6")
	for s in ["font_color", "font_focus_color", "font_hover_pressed_color", "font_pressed_color"]:
		b.add_theme_color_override(s, fc)
	b.add_theme_color_override("font_hover_color", Color("#ffffff") if on else Color("#c4d2e2"))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))


## 把一个"状态边框色"折算成适合 modulate 的色调。
##
## 调用方原来传的是 `border_color`(黄=选中 / 紫=道具 / 深灰=空)。直接拿它 modulate 会过饱和,
## 把框自己的明暗关系压没 ⇒ 往白里提一档, 只保留色相倾向。
static func tint_of(border: Color) -> Color:
	var v: float = maxf(border.r, maxf(border.g, border.b))
	if v < 0.30:
		return Color.WHITE          # 深灰边 = 无状态, 不染色
	var k := 0.55                   # 0=纯白(不染) 1=原色(过饱和)
	return Color(lerpf(1.0, border.r, k), lerpf(1.0, border.g, k), lerpf(1.0, border.b, k), 1.0)
