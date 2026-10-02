extends Control
## rich_tooltip.gd — 能渲染 BBCode 的自定义 tooltip 宿主 (2026-07-22)
##
## Godot 的系统 tooltip 是纯文本, 直接把 [color=..] 原样显示给玩家。
## 背包里的装备介绍要按玩家当前星级高亮(SkillText.highlight_star 产出 BBCode),
## 所以给格子挂上这个脚本, 覆写 _make_custom_tooltip。
##
## 用法: box.set_script(preload("res://scripts/scenes/rich_tooltip.gd"))
##       box.tooltip_text = <含 BBCode 的文本>
##
## ★★2026-10-02 `extends Panel` → `extends Control`。
##   由来: 这份脚本一直【只有背包在用】, 而另外两个落点挂不上去 ——
##   `set_script` 要求脚本的原生基类是节点类型的**祖先**, 而 `Panel` 与
##   `PanelContainer` 是**兄弟**(两个都直接继承 Control), 不是父子。
##   选龟页那个被动 chip 正是 `PanelContainer` ⇒ 挂不上 ⇒ 它的 tooltip 一直在把
##   `[color=#ff4444]攻击力[/color]` 这种标记【原样印给玩家】(2026-10-02 实拍留证:
##   docs/plans/20261002-文案落点BBCode普查.md)。
##   ⇒ 基类放宽到 Control, 这份宿主就能挂在任何控件上, 不用再抄第二份。
##   ⚠ 脚本里不碰 Panel 独有的 API(只覆写 _make_custom_tooltip), 所以放宽是安全的;
##     原来挂着它的 `Panel` 仍然是 Control 的子类, 一个字都不用改。

func _make_custom_tooltip(for_text: String) -> Object:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0a0e18")
	sb.border_color = Color(1, 216.0 / 255.0, 107.0 / 255.0, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true          # 不开则高度为 0, tooltip 空白
	rt.scroll_active = false
	rt.custom_minimum_size = Vector2(300, 0)
	rt.add_theme_font_size_override("normal_font_size", 12)
	rt.add_theme_color_override("default_color", Color("#dbe6f2"))
	rt.text = for_text
	pc.add_child(rt)
	return pc
