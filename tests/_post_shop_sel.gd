extends Node
## 截图用: 商店【选中一格】—— 否则右侧详情面板永远是空态, 而"描述那里有一堆乱七八糟的东西"
## 说的正是详情面板里的内容。SHOT_SEL_IDX=N 选第 N 格(默认 0)。


static func run(scene: Node) -> void:
	var idx := 0
	if OS.get_environment("SHOT_SEL_IDX").is_valid_int():
		idx = int(OS.get_environment("SHOT_SEL_IDX"))
	## SHOT_FORCE_ID=p2eq_084: 把第 idx 格换成指定装备 —— 货架是随机 roll 的,
	## 想复现"最长的那件描述"只能强制指定, 否则截十次也未必碰上。
	var fid := OS.get_environment("SHOT_FORCE_ID")
	if fid != "":
		for e in DataRegistry.phase2_equipment:
			if str((e as Dictionary).get("id", "")) == fid:
				var off: Array = scene.get("_offer")
				if idx >= 0 and idx < off.size():
					off[idx] = e
				break
	scene.set("_sel", idx)
	if scene.has_method("_rebuild"):
		scene.call("_rebuild")
