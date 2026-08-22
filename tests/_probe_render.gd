extends Node
## 探针: 在【引擎里】渲染文案, 确认 {C:...} 真的被替换掉了。
## ★由来: Python 审计器(text_golden)自己解析 .gd 取常量, 而**游戏**走
##   `ProjectSettings.get_global_class_list()` —— 两条路可能不一致。
##   审计器绿 ≠ 玩家看到的是数字(memory: 产物才是判据)。
## `\*` 在 GDScript 字符串里是**非法转义** ⇒ Parse Error(与 skill_text 里 `\{` 那条同族)。
## 用字符类 [*] 绕开。匹配"连续 4+ 个大写/下划线"的裸标识符 = 没算出来的表达式残骸。
var _leak := RegEx.create_from_string("[A-Z][A-Z0-9_]{3,}[*]?[A-Za-z]*")


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
			## ★★"没有花括号"**不够**(2026-08-22 实测漏网): `{N:expr}` 走 `eval_expr`,
			##   算不出来时**原样吐回表达式字符串**、花括号已经被吃掉 ⇒ 玩家看到
			##   "VOLLEY_ATK_COEF*ATK" 这种鬼东西, 而本探针一路绿灯。
			##   (我就是这么把一个常量名写进 {N:} 里的 —— {N:} 只认 build_vars 的变量,
			##    不认代码常量, 那是 {C:} 的活。)
			##   ⇒ 再加一条: 渲染完不许残留【大写常量名样式的裸标识符】。
			if t.contains("{"):
				bad += 1
				print("  ★没渲染出来: %s → %s" % [str(b[0]), t.substr(maxi(0, t.find("{")), 70)])
			elif _leak.search(t) != null:
				bad += 1
				print("  ★表达式没算出来(原样吐回): %s → %s" % [str(b[0]), str(_leak.search(t).get_string())])
	## ★★装备文案是【另一条消费管线】(商店 `_equip_full_desc` 走 `render_consts`),
	##   龟的那条绿不代表它也绿 —— 2026-08-22 转 FPGA 板时才发现探针根本没扫装备。
	for eid in d.phase2_equipment_by_id.keys():
		var e: Dictionary = d.phase2_equipment_by_id[eid]
		for k in ["effectDesc1", "effectDesc2", "effectDesc3", "desc"]:
			var raw: String = str(e.get(k, ""))
			if raw == "":
				continue
			seg += 1
			var t2: String = SkillText.render_consts(raw)
			if t2.contains("{C:"):
				bad += 1
				print("  ★装备没渲染出来: %s.%s → %s" % [str(eid), k, t2.substr(maxi(0, t2.find("{C:")), 60)])
	print("★引擎内渲染: 查了 %d 段, 残留花括号(未渲染)的有 %d 段" % [seg, bad])
	get_tree().quit(0 if bad == 0 else 1)
