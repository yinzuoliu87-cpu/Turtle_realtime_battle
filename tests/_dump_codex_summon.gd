extends Node
## DEV 工具(不是门禁): 把图鉴「角色」栏召唤物 / 战场单位每页每列的文字按玩家看到的样子(常量代入、去 BBCode)打成纯文本, 逐句自审用。
## 跑法: <godot> --headless --path . res://tests/_dump_codex_summon.tscn  ⇒ .out/codex_summon_text.txt

func _ready() -> void:
	await get_tree().process_frame
	var out: PackedStringArray = []
	var re_bb := RegEx.create_from_string("\\[[^\\]]*\\]")
	for id in SummonCodex.all_ids():
		var nc: int = maxi(1, SummonCodex.cols(str(id)).size())
		for ci in range(nc):
			var si: Dictionary = SummonCodex.info(str(id), ci)
			var cols: Array = si.get("cols", [])
			out.append("══════ %s%s" % [si["name"], ("  [%s %s]" % [si.get("col_title", ""), cols[ci]]) if not cols.is_empty() else ""])
			if ci == 0:
				var src: Dictionary = si.get("source", {})
				out.append("签牌: %s | 来源: %s" % [" / ".join(PackedStringArray(si.get("tags", []))), str(src.get("text", ""))])
			var st: PackedStringArray = []
			for r in si.get("stats", []):
				st.append("%s %s" % [str(r["label"]), str(r["disp"])])
			out.append("属性: " + "  ".join(st))
			var ctx := {"atk": float(_disp(si, "atk")), "maxHp": float(_disp(si, "hp")), "lv": 1}
			var rows: Array = []
			for pv in si.get("passives", []):
				rows.append(["被动", pv])
			if not (si.get("basic", {}) as Dictionary).is_empty():
				rows.append(["攻击", si["basic"]])
			if not (si.get("skill", {}) as Dictionary).is_empty():
				rows.append(["技能", si["skill"]])
			for r in rows:
				var d: Dictionary = r[1]
				var txt: String = SkillText.render_bbcode_formula(str(d["desc"]), ctx, {})
				txt = re_bb.sub(txt, "", true).replace("[lb]", "[")
				out.append("  %s · %s：%s" % [r[0], d["name"], txt])
	var f := FileAccess.open("res://.out/codex_summon_text.txt", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	print("dumped ", out.size())
	get_tree().quit()


func _disp(si: Dictionary, key: String) -> String:
	for r in si.get("stats", []):
		if str(r["key"]) == key:
			return str(r["disp"])
	return "0"
