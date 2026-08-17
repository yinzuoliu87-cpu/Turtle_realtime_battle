extends Node
## _probe_codex_clip.gd — 图鉴技能卡【被截断张数】全 28 只实测(2026-08-17, 只量不判)
##
## 由来: 今晚给描述做了两轮改动 —— ①长句在分号处断行(会**加行**) ②清套话(会**减字**)。
## 两个方向相反, 只有实测才知道净效果。记录在案的基线是【卡 112 张 / 被截 24 张】。
## 门禁 `verify_codex_layout` ⑨ 找够 3 张就早退(省时间), 拿不到总数, 所以单写这个探针。
##
## 跑法: <godot> --headless --path . res://tests/_probe_codex_clip.tscn --quit-after 30000

const SCN := preload("res://scenes/Codex.tscn")

var _inst


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	_inst = SCN.instantiate()
	add_child(_inst)
	await _settle(12)
	_inst._switch_tab("pets")
	await _settle(8)
	var cards := 0
	var clipped := 0
	var hints := 0
	var worst: Array = []
	for i in range(_inst._items.size()):
		_inst._select(i)
		await _settle(6)
		for c in _inst.detail.get_children():
			if c is RichTextLabel:
				var rt := c as RichTextLabel
				if rt.size.y > 40.0 and rt.size.y < 400.0:
					cards += 1
					var over: float = rt.get_content_height() - rt.size.y
					if over > 0.5:
						clipped += 1
						worst.append("第%d只 超%.0fpx" % [i, over])
			elif c is Label and str((c as Label).text).begins_with("点开看全部"):
				hints += 1
	print("=== 图鉴技能卡截断实测(全 %d 只) ===" % _inst._items.size())
	print("  卡片正文 %d 张 · 被截断 %d 张 · 提示条 %d 条" % [cards, clipped, hints])
	print("  基线(记录在案): 卡 112 张 / 被截 24 张")
	print("  最严重的几张: %s" % str(worst.slice(0, 6)))
	print("PROBE DONE")
	get_tree().quit(0)
