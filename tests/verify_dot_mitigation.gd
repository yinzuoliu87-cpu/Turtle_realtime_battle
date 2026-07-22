extends Node

# DOT 减伤/穿甲/归属 守卫 (2026-07-22)
#
# 用户:「所有DOT都是对应的伤害类型吧，该过护甲的都过了吗，伤害类型都统计了吗」
#     「DOT不用管削弱后的伤害，现在DOT就因为这个bug本来过于强势了，DOT要享受穿甲增伤等」
#
# ★修之前的事实(实测行数): _apply_damage 30 行 / _apply_damage_from 205 行,
#   差的 175 行全是减伤与触发链 → 钻石18%/岩层-30%/嘲讽/铁壁盾/靶向器/暴露蛋
#   对 DOT 【全部无效】; aura 储能盾不吸 DOT; 亡灵免死能被 DOT 打穿;
#   DOT 击杀不算击杀数(on-kill 装备全不触发); 诅咒走 _raw_lose 完全不进统计。
#
# 本测试守三件事:
#   ① 两条伤害路径【共用同一份受害者减伤】(_mitigate_incoming), 不允许各写各的
#   ② _apply_damage 里那些曾经缺失的钩子都在(aura盾/免死/带 killer 的 _kill)
#   ③ DOT 抗性计算吃施加者的护穿与增伤

const SCENE_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"

var _fails: Array[String] = []


func _ready() -> void:
	var src := FileAccess.get_file_as_string(SCENE_PATH)
	if src == "":
		_fail("读不到 %s" % SCENE_PATH)
		_done()
		return
	_check_shared_mitigation(src)
	_check_apply_damage_hooks(src)
	_check_dot_pen(src)
	_check_curse_path(src)
	_check_resist_math()
	_done()


## ① 两条路径必须都调 _mitigate_incoming —— 否则又会各改各的, 回到 DOT 不吃减伤的老路
func _check_shared_mitigation(src: String) -> void:
	if src.find("func _mitigate_incoming(") < 0:
		_fail("缺少公共减伤函数 _mitigate_incoming")
		return
	var n := 0
	for fn in ["_apply_damage", "_apply_damage_from"]:
		if _code_only(_func_body(src, fn)).find("_mitigate_incoming(") >= 0:
			n += 1
		else:
			_fail("%s 没调 _mitigate_incoming —— 两条路径的减伤又分家了" % fn)
	# 公共函数里必须真的含那几项减伤, 否则"调了"也是空壳
	var mb := _code_only(_func_body(src, "_mitigate_incoming"))
	for key in ["eq_marked_until", "_egg_final", "diamond", "stone_rockbody", "stone_dr_until", "flat_dr"]:
		if mb.find(key) < 0:
			_fail("_mitigate_incoming 里缺 %s —— 该项减伤对两条路径都会失效" % key)
	print("  [共用减伤] 两条路径均调用, 公共函数含 6 项减伤 (调用方 N=%d)" % n)


## ② _apply_damage 曾经缺失的钩子
func _check_apply_damage_hooks(src: String) -> void:
	var b := _code_only(_func_body(src, "_apply_damage"))
	if b == "":
		_fail("找不到 _apply_damage")
		return
	# ★断言要查【具体的读取形式】而不是"标识符出现过" —— 后者太弱:
	#   反向验证时把 aura 盾的判断条件改成 false, 因为下面几行仍写着 u["_auraShieldVal"],
	#   只查标识符的版本照样绿(2026-07-22 实测到这个假通过)。
	var need := {
		"u.get(\"_auraShieldVal\"": "aura 储能盾不吸 DOT(金龟/龟壳储能盾期间被灼烧照样掉血)",
		"deathfloor_until": "亡灵免死锁血被 DOT 打穿(免死光环亮着人被烧死)",
		"_assembling": "组装期免疫被 DOT 打穿",
	}
	for k in need.keys():
		if b.find(str(k)) < 0:
			_fail("_apply_damage 缺 %s → %s" % [str(k), str(need[k])])
	# _kill 必须带 killer, 否则 DOT 击杀不算击杀数、on-kill 装备不触发
	if b.find("_kill(u, ") < 0:
		_fail("_apply_damage 的 _kill 没带 killer —— DOT 击杀不算击杀数, 暴君之牙等 on-kill 装备不触发")
	print("  [落伤钩子] aura盾/免死/组装免疫/带killer 四项已检")


## ③ DOT 抗性要吃施加者的护穿与增伤(用户 2026-07-22 拍板)
func _check_dot_pen(src: String) -> void:
	var b := _code_only(_func_body(src, "_dot_after_resist"))
	if b == "":
		_fail("找不到 _dot_after_resist")
		return
	for k in ["armor_pen", "magic_pen", "damage_amp"]:
		if b.find(k) < 0:
			_fail("_dot_after_resist 没吃 %s —— 用户要求 DOT 享受穿甲增伤" % k)
	# 三个结算点都要把施加者传进去, 否则上面写了也白写
	var tick := _code_only(_func_body(src, "_tick_dot_stacks"))
	var n := tick.count("_dot_after_resist(u, float(dmg)")
	var withsrc := tick.count("dot_src\", {}).get(")
	print("  [DOT穿甲] _dot_after_resist 调用 %d 处, 带 dot_src 的引用 %d 处" % [n, withsrc])
	if n < 3:
		_fail("_tick_dot_stacks 里 _dot_after_resist 调用点只有 %d 处, 预期 ≥3(burn/poison/bleed)" % n)
	for kind in ["burn", "poison", "bleed"]:
		if tick.find("_dot_after_resist(u, float(dmg), true, u.get(\"dot_src\", {}).get(\"%s\"" % kind) < 0 \
		   and tick.find("_dot_after_resist(u, float(dmg), false, u.get(\"dot_src\", {}).get(\"%s\"" % kind) < 0:
			_fail("%s 的抗性计算没把施加者传进去 —— 它的穿甲/增伤不会生效" % kind)


## ④ 诅咒必须走正规伤害路径, 不能再用 _raw_lose
func _check_curse_path(src: String) -> void:
	var b := _code_only(_func_body(src, "_tick_effects"))
	if b == "":
		# 诅咒结算所在函数名可能变, 退而求其次: 全局检查
		b = _code_only(src)
	if b.find("_raw_lose(u, dot[\"dps\"]") >= 0:
		_fail("诅咒仍走 _raw_lose —— 不进统计/不跳飘字/不过任何减伤/能打穿组装免疫")
	# _add_dot 必须存施加者, 否则诅咒伤害永远无主
	var ad := _code_only(_func_body(src, "_add_dot"))
	if ad.find("\"src\"") < 0:
		_fail("_add_dot 没存施加者 —— 诅咒伤害永远无主(不进统计、不吃穿甲)")
	print("  [诅咒] 已离开 _raw_lose 且带施加者")


## ⑤ 抗性曲线本身的数学(纯逻辑, 与实现对照)
func _check_resist_math() -> void:
	var cases := [
		[30.0, 0.0, 0.0, "无穿甲"],
		[30.0, 15.0, 0.0, "15 点固定穿甲"],
		[30.0, 0.0, 0.30, "30% 百分比穿甲"],
	]
	var base := _mult(30.0)
	for c in cases:
		var eff: float = float(c[0]) * (1.0 - float(c[2])) - float(c[1])
		var m := _mult(eff)
		if float(c[1]) > 0.0 or float(c[2]) > 0.0:
			if m <= base:
				_fail("穿甲没让伤害变高: %s (倍率 %.3f ≤ 基准 %.3f)" % [str(c[3]), m, base])
	print("  [抗性曲线] 3 组穿甲取值校验, 基准倍率 %.3f" % base)


func _mult(r: float) -> float:
	return (1.0 - r / (r + 40.0)) if r >= 0.0 else (1.0 + absf(r) / (absf(r) + 40.0))


## 剥注释 —— 断言"函数体里有没有某调用"必须先过这层, 否则注释里提到那个名字就会假通过
## (2026-07-22 在 verify_cyber_hijack 上连踩两次)。不能简单按第一个 # 截断: 满文件的
## Color("#ff9a5a") 会被误伤 → 要判引号状态。
func _strip_comment(line: String) -> String:
	var in_q := false
	var q := ""
	for i in line.length():
		var ch := line[i]
		if in_q:
			if ch == q and (i == 0 or line[i - 1] != "\\"):
				in_q = false
		elif ch == "\"" or ch == "'":
			in_q = true
			q = ch
		elif ch == "#":
			return line.substr(0, i)
	return line


func _code_only(block: String) -> String:
	var out := ""
	for l in block.split("\n"):
		out += _strip_comment(str(l)) + "\n"
	return out


func _func_body(src: String, fname: String) -> String:
	var head := "\nfunc %s(" % fname
	var i := src.find(head)
	if i < 0:
		return ""
	var start := i + 1
	var j := src.find("\nfunc ", start)
	if j < 0:
		j = src.length()
	return src.substr(start, j - start)


func _fail(msg: String) -> void:
	_fails.append(msg)


func _done() -> void:
	if _fails.is_empty():
		print("ALL PASS — DOT 减伤/穿甲/归属 正确")
	else:
		for f in _fails:
			printerr("FAIL: %s" % f)
		printerr("FAIL — DOT %d 项不通过" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)
