extends Node
## _probe_row_width.gd — 只读剖面: 状态行候选文案的**真实字宽**(框只有 LEFT_W-8 = 374px)。
## 起因: `_probe_status_row_days` 量出周六那一行 **485px / 框 374** —— 顶穿 111px,
## 而它一周只渲染一天, `verify_ui_consistency` 扫的是"今天"那一屏 ⇒ 一直没人红。

const MENU := preload("res://scripts/scenes/MainMenuScene.gd")

const HEAD := "第 1 大轮 · Lv 1   "
const CANDS := [
	"",
	"闯关赛 2-1 · 再赢 2 场晋级 / 再输 2 场出局",
	"闯关赛 2-1 · 再赢 2 / 再输 2 出局",
	"闯关赛 2-1 · 再赢 2 / 再输 2",
	"闯关赛 2-1 · 2 胜晋级 / 2 负出局",
	"闯关赛 2-1 · 差 2 胜晋级 / 2 负出局",
	"闯关赛 2-1 · 赢 2 晋级 输 2 出局",
	"闯关赛 2-1 · 再 2 胜晋级 / 再 2 负淘汰",
	"闯关赛 2-1 · 2 胜进决赛 / 2 负出局",
	"闯关赛 2-1 · 还有 2 胜 / 2 负",
	"闯关赛 2-1 · 再赢 2 晋级, 再输 2 出局",
]


func _ready() -> void:
	await get_tree().process_frame
	var m = MENU.new()
	var f = m._bold_font()
	print("=== 字宽(18号粗体, 框 374) ===")
	for c in CANDS:
		var full: String = HEAD + c
		var w: float = f.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		print("  %6.1f %s 「%s」" % [w, ("超" if w > 374.0 else "  "), full])
	m.free()
	print("PROBE DONE")
	get_tree().quit(0)
