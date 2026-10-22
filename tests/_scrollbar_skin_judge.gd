extends RefCounted
## 滚动条皮的判据 —— 商店说明卡正文(verify_shop_interactions)与背包羁绊弹框正文(verify_synergy_popup)共用。
## ★一份判据两处调: 两个门禁各抄一份, 改一处另一处就落后(memory fb-hand-rolled-copies-drift)。
##
## 由来(2026-10-22): 这两处正文超高时右边那根是 Godot 默认的灰色圆角细条, 与木框 / 黄铜边的像素画不搭。
## ★量的是需求本身, 不是「UISkin.scrollbar 被调过」(memory fb-gate-must-measure-requirement-not-my-hook):
##   ① 直角 —— 默认皮圆角 10, 像素画里没有圆角
##   ② 滑块是暖色黄铜 / 木色(色相 18°~52°、饱和度 ≥ 0.35)—— 默认皮是灰(饱和度 0)
##   ③ 槽是深色(明度 ≤ 0.2)
##   ④ 粗细 6 ~ max_w —— 是细条, 且不宽过调用方给正文让出的那条宽(宽过了字就压在滚动条下)
## ★四种样式(槽 / 滑块常态 / 悬停 / 按下)都量: 只换常态, 手指一按就闪回灰的。
## ★换成贴图皮(StyleBoxTexture)也算合格 —— 颜色由贴图定, 这里不量; 默认皮不是贴图, 照样拦得住。


## 返回 "" = 合格; 否则一句原因。
static func problem(sc: ScrollContainer, max_w: float) -> String:
	if sc == null:
		return "没有滚动框"
	var bar: VScrollBar = sc.get_v_scroll_bar()
	if bar == null:
		return "没有竖滚动条"
	var w: float = bar.get_combined_minimum_size().x
	if w < 6.0 or w > max_w + 0.5:
		return "竖滚动条宽 %.0f, 不在 6 ~ %.0f" % [w, max_w]
	for st in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		var sb: StyleBox = bar.get_theme_stylebox(st)
		if sb is StyleBoxTexture:
			continue
		if not (sb is StyleBoxFlat):
			return "%s 是 %s" % [st, sb.get_class() if sb != null else "null"]
		var f := sb as StyleBoxFlat
		var r: int = maxi(maxi(f.corner_radius_top_left, f.corner_radius_top_right),
			maxi(f.corner_radius_bottom_left, f.corner_radius_bottom_right))
		if r > 0:
			return "%s 圆角 %d" % [st, r]
		var c: Color = f.bg_color
		if st == "scroll":
			if c.v > 0.2:
				return "槽底色 #%s 不够暗(明度 %.2f)" % [c.to_html(false), c.v]
		else:
			var hue: float = c.h * 360.0
			if c.s < 0.35 or hue < 18.0 or hue > 52.0 or c.a < 0.9:
				return "%s 底色 #%s 不是黄铜 / 木色(色相 %.0f° · 饱和 %.2f · 不透明 %.2f)" % [st, c.to_html(false), hue, c.s, c.a]
	return ""
