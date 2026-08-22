extends Node
## 探针: 在【引擎里】渲染文案, 确认 {C:...} 真的被替换掉了。
## ★由来: Python 审计器(text_golden)自己解析 .gd 取常量, 而**游戏**走
##   `ProjectSettings.get_global_class_list()` —— 两条路可能不一致。
##   审计器绿 ≠ 玩家看到的是数字(memory: 产物才是判据)。
func _ready() -> void:
	await get_tree().process_frame
	var d = get_node("/root/DataRegistry")
	var bad := 0
	var seg := 0
	for pid in d.pet_by_id.keys():
		var p: Dictionary = d.pet_by_id[pid]
		var blobs: Array = []
		var pv = p.get("passive", null)
		if pv is Dictionary:
			blobs.append([str(pid) + "/" + str(pv.get("name", "")) + ".desc", str(pv.get("desc", "")), pv])
			blobs.append([str(pid) + "/" + str(pv.get("name", "")) + ".detail", str(pv.get("detail", "")), pv])
		for sk in p.get("skillPool", []):
			blobs.append([str(pid) + "/" + str(sk.get("name", "")) + ".brief", str(sk.get("brief", "")), sk])
			blobs.append([str(pid) + "/" + str(sk.get("name", "")) + ".detail", str(sk.get("detail", "")), sk])
		## ★用**真实渲染入口**(render_html)带上单位上下文, 不是只展开 {C:} ——
		##   裸 `{rageMax}` 这类要靠 build_vars 的变量表, Python 快照工具解析不了它们,
		##   只有引擎里跑一遍才知道玩家看到的是数字还是花括号。
		var fake: Dictionary = {"atk": 100, "def": 50, "mr": 40, "maxHp": 3000, "crit": 0.25, "lv": 1,
			"passive": (pv if pv is Dictionary else {})}
		for b in blobs:
			var ctxs: Dictionary = b[2]
			var t: String = SkillText.render_html(str(b[1]), fake, ctxs)
			seg += 1
			if t.contains("{"):
				bad += 1
				print("  ★没渲染出来: %s → %s" % [str(b[0]), t.substr(maxi(0, t.find("{")), 70)])
	print("★引擎内渲染: 查了 %d 段, 残留花括号(未渲染)的有 %d 段" % [seg, bad])
	get_tree().quit(0 if bad == 0 else 1)
