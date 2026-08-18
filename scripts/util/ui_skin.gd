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


## 九宫格 StyleBox。贴图不在就原样返回 `fallback`(调用方给的 StyleBoxFlat)。
static func nine(tex_name: String, margin: int, fallback: StyleBox) -> StyleBox:
	var p := TEX_DIR + tex_name
	if not ResourceLoader.exists(p):
		return fallback
	var st := StyleBoxTexture.new()
	st.texture = load(p)
	st.set_texture_margin_all(margin)
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
