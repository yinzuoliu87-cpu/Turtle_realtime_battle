extends Node
## verify_text_render.gd — 玩家文案里的占位符, 在【引擎里】必须真的渲染成数字。
##
## ══════════════════════════════════════════════════════════════════
##  为什么 Python 审计器全绿还需要这一条
## ══════════════════════════════════════════════════════════════════
## `{C:类名.常量}` 有**两条独立的解析路径**:
##   · Python 审计器(text_golden / number_coverage): 自己正则解析 .gd 取常量;
##   · **游戏**: `ProjectSettings.get_global_class_list()` → load(脚本) → 读常量。
## 两条随时可能不一致 ⇒ 审计器绿 ≠ 玩家看到的是数字。
##
## ★2026-08-22 实测两个只有这条能抓到的坑:
##   ① **新增 `class_name` 文件后, 在跑一次 `--import` 之前它不在全局类表里** ——
##      不但它自己的 {C:} 全废, **连引用它的那个类**(主场景引用了 BasicConsts)
##      的 {C:RealtimeBattle3DScene.X} 也一起解析不了。悄无声息。
##   ② `{N:expr}` 走的是 `eval_expr`(只认 build_vars 的变量, **不认代码常量**),
##      算不出来时**原样吐回表达式、花括号已被吃掉** ⇒ 玩家看到 "VOLLEY_ATK_COEF*ATK"。
##      所以"没有花括号"这一条判据**不够**, 下面还查"大写常量名样式的裸标识符"。
##
## ★覆盖两条消费管线: 龟(pets.json·280 段) + **装备**(phase2-equipment.json·97 段)。
##   装备走的是商店 `_equip_full_desc` → `render_consts`, 龟那条绿不代表它也绿。
##
## 反向验证: 往任意一段塞 `{C:NoSuchClass.X}` 或 `{N:SOME_CONST*ATK}`, 本用例立刻红。


## `\*` 在 GDScript 字符串里是**非法转义** ⇒ Parse Error; 用字符类 [*] 绕开。
## 匹配"连续 4+ 个大写/下划线"的裸标识符 = 没算出来的表达式残骸。
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
			## ★★`passive.brief` 必须也扫: 2026-08-22 反向验证时它救了我一次 ——
			##   我往 brief 里塞了个不存在的类, 而本用例当时只扫 desc/detail ⇒ 照样 ALL PASS。
			##   "判据没错但被测字段不在扫描范围里" 是最难发现的一类空检查。
			blobs.append([str(pid) + "/" + str(pv.get("name", "")) + ".brief", str(pv.get("brief", "")), pv])
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
	print("  分母: 引擎内渲染了 %d 段文案(龟+装备两条管线)" % seg)
	## ★分母断言: 段数太少 = 数据没加载上, 下面那条 "0 残留" 就是空检查。
	var ok_seg: bool = seg >= 300
	print(("  [ OK ] " if ok_seg else "  [FAIL] ") + "分母·扫到 %d 段 ≥ 300" % seg)
	print(("  [ OK ] " if bad == 0 else "  [FAIL] ") + "占位符全部渲染成数字: 残留 %d 段(必须 0)" % bad)
	if bad == 0 and ok_seg:
		print("ALL PASS — 文案占位符引擎内渲染")
	else:
		print("★FAIL")
	get_tree().quit(0 if (bad == 0 and ok_seg) else 1)
