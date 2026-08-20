extends Node
## 探针: {C:} 占位符在**真引擎**里到底展开成什么。
##
## ★为什么必须有这个: tools/text_golden.py 是 python **重写**的渲染器,
##   游戏里跑的是 GDScript 的 SkillText。两边若不一致, python 说"一字不差",
##   玩家却在图鉴上看到字面的 {C:CrystalSystem.STACK_MAX} —— 这正是我要防的分歧。
##   所以判据必须走**真出口** render_bbcode / render_plain, 不许自己调 render_consts。


func _ready() -> void:
	await get_tree().process_frame
	var f := FileAccess.open("res://data/pets.json", FileAccess.READ)
	var pets = JSON.parse_string(f.get_as_text())
	f.close()
	var arr: Array = pets["pets"] if pets is Dictionary and pets.has("pets") else pets
	var ctx := {"atk": 100.0, "def": 50.0, "mr": 30.0, "maxHp": 1000.0, "spd": 100.0}
	var n_seg := 0
	var n_ctok := 0
	var leaked: Array = []
	var samples: Array = []
	## ★分母修正: 技能不在 "skills" 而在 skillPool/defaultSkills, 上一版只扫到 59/576 段。
	##   改成【递归走遍整棵 JSON】, 谁也漏不掉 —— 分母错了后面全是假结论。
	var stack: Array = [[arr, {}]]
	while not stack.is_empty():
		var it = stack.pop_back()
		var node = it[0]
		var owner: Dictionary = it[1]
		if node is Array:
			for e in node:
				stack.append([e, owner])
		elif node is Dictionary:
			for k in node.keys():
				var v = node[k]
				if v is String:
					n_seg += 1
					if not (v as String).contains("{C:"):
						continue
					n_ctok += 1
					var out_bb := SkillText.render_bbcode(v, ctx, node, 17)
					var out_pl := SkillText.render_plain(v, ctx, node)
					if out_bb.contains("{C:") or out_pl.contains("{C:"):
						leaked.append(str(node.get("name", k)) + "." + str(k))
					samples.append(str(node.get("name", "?")) + "." + str(k) + "  →  " + out_pl.replace("
", " / ").substr(0, 130))
				else:
					stack.append([v, node])
	print("=== {C:} 真引擎展开探针 ===")
	print("[分母] 扫了 %d 段文案, 其中含 {C:} 的 %d 段" % [n_seg, n_ctok])
	for s in samples:
		print("   ", s)
	print("[结果] 展开后仍残留 {C: 的段数 = %d" % leaked.size())
	for s in leaked:
		print("   [LEAK] ", s)
	print("PROBE DONE")
	get_tree().quit(0)
