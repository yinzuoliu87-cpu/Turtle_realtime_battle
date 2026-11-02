extends Node
func _ready() -> void:
	await get_tree().process_frame
	var n_bad := 0
	var n_all := 0
	for p in DataRegistry.all_pets:
		var pa: Dictionary = p.get("passive", {})
		var texts: Array = []
		for k in ["brief", "desc", "detail"]:
			if str(pa.get(k, "")) != "":
				texts.append([str(p.get("id", "")) + ".passive." + k, str(pa.get(k, ""))])
		for s in p.get("skillPool", []):
			for k2 in ["brief", "desc", "detail"]:
				if str(s.get(k2, "")) != "":
					texts.append(["%s/%s.%s" % [p.get("id", ""), s.get("name", ""), k2], str(s.get(k2, ""))])
		for row in texts:
			n_all += 1
			var out := SkillText.render_plain(str(row[1]), p, {})
			if out.find("{") >= 0 or out.find("}") >= 0:
				n_bad += 1
				var i := out.find("{")
				print("  [花括号没渲染掉] %s → 「%s」" % [row[0], out.substr(maxi(0, i - 12), 40)])
	print("渲染了 %d 段, 花括号残留 %d 段" % [n_all, n_bad])
	print("PROBE DONE")
	get_tree().quit(0)
