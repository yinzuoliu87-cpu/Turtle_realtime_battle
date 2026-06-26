# ══════════════════════════════════════════════════════════
# detail_panel_frame.gd — 信息面板金属斜面边框 + 四角铆钉 overlay (_draw)
# 1:1 PoC DetailPanel.ts:98-128
#   box-shadow inset 0 0 0 2px #ffe9a8 / 4px #c79a36 / 6px rgba(0,0,0,.55)
#     → 从面板内缘往内叠 3 个 2px 实心环 (亮金 / 暗金 / 黑槽)
#   ::after inset:8px, 四角 radial 芯#ffe9a8 r1.6 + 环#7d6320 r3 (在角 5px 处)
# 用 draw_style_box(StyleBoxFlat draw_center=false) 画环; draw_circle 画铆钉。
# preload 不用 class_name; 挂在 PanelContainer 内当 full-rect overlay, mouse IGNORE。
# ══════════════════════════════════════════════════════════
extends Control

# 主面板圆角 (1:1 PoC border-radius:14px)
const PANEL_RADIUS := 14
# 3 圈斜面: inset(px) → color (PoC box-shadow inset 顺序: 2/4/6)
#   Godot StyleBoxFlat 的 border 画在矩形【内侧】→ inset=2 的矩形其 2px border 占屏 2-4px, 正好对位。
const BEVEL_RINGS := [
	[2, Color("#ffe9a8")],              # inset 0 0 0 2px #ffe9a8  亮金
	[4, Color("#c79a36")],              # inset 0 0 0 4px #c79a36  暗金
	[6, Color(0, 0, 0, 0.55)],          # inset 0 0 0 6px rgba(0,0,0,.55) 黑槽
]
# 铆钉: ::after inset:8 + 角内 5px 处 → 距面板边缘 13px (1:1 PoC L121/124)
const RIVET_INSET := 13.0
const RIVET_RING_R := 3.0               # 环 #7d6320 r3 (PoC L124)
const RIVET_CORE_R := 1.6               # 芯 #ffe9a8 r1.6 (PoC L124)
const RIVET_RING_COL := Color("#7d6320")
const RIVET_CORE_COL := Color("#ffe9a8")


func _draw() -> void:
	var sz := size
	# ── 3 圈金属斜面环 (从内缘往内 2/4/6px) ──
	for ring in BEVEL_RINGS:
		var inset: int = ring[0]
		var col: Color = ring[1]
		var sb := StyleBoxFlat.new()
		sb.draw_center = false               # 只画边框, 不填充中心
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(2)           # 每环 2px 实心
		sb.border_color = col
		var r := maxi(0, PANEL_RADIUS - inset)
		sb.set_corner_radius_all(r)
		var rect := Rect2(Vector2(inset, inset), sz - Vector2(inset * 2, inset * 2))
		draw_style_box(sb, rect)
	# ── 四角铆钉 (距边缘 13px 处, 各画环+芯) ──
	var corners := [
		Vector2(RIVET_INSET, RIVET_INSET),                       # 左上
		Vector2(sz.x - RIVET_INSET, RIVET_INSET),                # 右上
		Vector2(RIVET_INSET, sz.y - RIVET_INSET),                # 左下
		Vector2(sz.x - RIVET_INSET, sz.y - RIVET_INSET),         # 右下
	]
	for c in corners:
		draw_circle(c, RIVET_RING_R, RIVET_RING_COL)
		draw_circle(c, RIVET_CORE_R, RIVET_CORE_COL)
