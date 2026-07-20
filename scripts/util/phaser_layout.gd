class_name PhaserLayout
extends RefCounted

## Phaser → Godot 坐标/尺寸单一换算源 (杜绝逐元素手算漂移).
##
## ⛔ 2026-07-19 核实: 【本文件已死】—— PhaserLayout 全项目零引用(含 .tscn), 两个 static func 也无人调。
## 各场景(MainMenu/Record/TeamSelect)都是自己手算坐标。下面这条"铁律"从未真正执行过, 别照它去用本文件。
##
## 移植铁律: Godot 里每个视觉数值都必须能引用到 Phaser 源码某一行.
##   引用不出来 = 自创 = 错. 不靠截图判断"对上", 靠数值与 Phaser 字面相等.
##
## Phaser 模型: add.image(x,y,key).setDisplaySize(w,h) 默认 origin (0.5,0.5) — (x,y) 是中心.
##            add.text(x,y,..).setOrigin(0.5) 同理; rectangle(x,y,w,h) 默认中心.
## Godot 模型: Control.position / Node2D 左上角 (Control) 或锚点 (Node2D 用 position 即中心可不转).
##
## 用法: 拿 Phaser 的 (cx, cy, w, h, originX, originY) 一律走这里, 不要在场景里再 ±w/2.

## Phaser 中心+displaySize → Godot Control 左上角 position.
## origin 默认 (0.5,0.5)=中心. originX=0→左对齐, originY=0→上对齐.
static func rect_pos(cx: float, cy: float, w: float, h: float, origin_x: float = 0.5, origin_y: float = 0.5) -> Vector2:
	return Vector2(cx - w * origin_x, cy - h * origin_y)

## 便捷: 直接给 Phaser 中心点 + 尺寸, 配 Control.set_size 用.
static func place(ctrl: Control, cx: float, cy: float, w: float, h: float, origin_x: float = 0.5, origin_y: float = 0.5) -> void:
	ctrl.size = Vector2(w, h)
	ctrl.position = rect_pos(cx, cy, w, h, origin_x, origin_y)

## Phaser setDisplaySize 整图拉伸 = Godot TextureRect EXPAND_IGNORE_SIZE + STRETCH_SCALE.
## (不是 9 宫格 NinePatchRect — 那会角不拉伸, 形状不对.)
static func stretch_image(tex: Texture2D, cx: float, cy: float, w: float, h: float, origin_x: float = 0.5, origin_y: float = 0.5) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = Vector2(w, h)
	tr.position = rect_pos(cx, cy, w, h, origin_x, origin_y)
	return tr

## Phaser text() 描边 → Godot Label outline. strokeThickness Phaser 是"半径", Godot outline_size 近似 ×2.
static func apply_stroke(lbl: Label, stroke_color: String, thickness: int) -> void:
	lbl.add_theme_constant_override("outline_size", thickness * 2)
	lbl.add_theme_color_override("font_outline_color", Color(stroke_color))
