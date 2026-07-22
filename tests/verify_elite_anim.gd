extends Node

# 精英小将动作动画接线守卫 (2026-07-21)
#
# 焊住三件事, 任何一件断了都会让动画"看着像没做"却不报错:
#   ① ACTION_ELITE / ACTION_ATTACK 里登记的 png 真的存在 (缺图时 _resolve_action 返回空字典,
#      _elite_anim 静默 return —— 不报错, 只是永远不播)
#   ② 五个技能触发点真的调了 _elite_anim, 且动作名对得上
#   ③ 这五个动作名在 _play_action 的不打断白名单里 (否则刚换上就被普攻/受击换掉)
#
# ★键必须是 "__minion_elite__" 不是 "__minion__": 三种小将(前排/后排/精英)共用同一个 id,
#   用 id 查表会让普通小将也套上精英的帧。见 _anim_key()。

const SCENE_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"

# 触发点函数名 → 期望在函数体里出现的 _elite_anim 动作名
const HOOKS := {
	"_elite_whirl":       ["whirl"],
	"_elite_try_consume": ["consume"],
	"_tick_elite_whip":   ["whip"],
	"_sk_elite_hammer":   ["hammer", "hammer_big"],
}

var _fails: Array[String] = []


func _ready() -> void:
	var src := FileAccess.get_file_as_string(SCENE_PATH)
	if src == "":
		_fail("读不到 %s" % SCENE_PATH)
		_done()
		return
	_check_sheets_exist(src)
	_check_hooks(src)
	_check_no_interrupt(src)
	_check_body_norm(src)
	_done()


## ④归一常量 ↔ 图的实际内容 必须对上
##   _set_anim_sheet 的通用归一假设"角色本体填满整帧", 但 PixelLab 的 96×96 输出里
##   本体只占 47px、脚底在第 71 行 —— 所以代码里用 ELITE_ACT_BODY_H / ELITE_ACT_FEET_ROW
##   手工补偿。★谁重新生成一次动作图, 这两个数就可能变, 而变了【不会报错】,
##   只会让角色一播动作就变大/变小/悬空(2026-07-21 用户一眼看出"大小明显不对")。
func _check_body_norm(src: String) -> void:
	# ★2026-07-22 泛化: 归一数据从三个常量改成 ANIM_NORM 表(每套图数值不同, 不能沿用别人的)。
	#   表: 动画键 → [动作图本体高, 动作图脚底行, idle 图本体高]
	var groups := {
		"__minion_elite__": {"dir": "elite", "idle": "pets/minion-elite.png",
			"ref": "attack", "acts": ["attack", "whirl", "hammer", "hammer_big", "whip", "consume", "run"]},
		"__minion_front__": {"dir": "melee", "idle": "pets/minion.png",
			"ref": "attack", "acts": ["attack", "leap", "throw", "dive", "surf", "land"]},
	}
	var checked := 0
	for key in groups.keys():
		var want := _norm_row(src, str(key))
		if want.is_empty():
			_fail("ANIM_NORM 里没有 %s 的归一数据 —— 该单位一播动作就会大小不对" % str(key))
			continue
		var g: Dictionary = groups[key]
		var heights: Array[int] = []
		var n := 0
		for act in g["acts"]:
			var p2 := "res://assets/sprites/pets/animations/%s/%s.png" % [str(g["dir"]), str(act)]
			if not ResourceLoader.exists(p2):
				continue
			var bb := _frame0_bbox(p2)
			if bb.is_empty():
				_fail("%s/%s 第0帧整帧透明?" % [str(g["dir"]), str(act)])
				continue
			n += 1
			heights.append(int(bb["h"]))
			# ★只对【中性站姿】那张做严格断言。其余动作的 bbox 天然会变, 拿它们比是判据设计错误:
			#   melee/throw 有绳索垂到脚下(脚底行 76)、melee/surf 脚下踩着一块板(71)、
			#   melee/leap 是蹲姿(本体只有 42)、elite/whirl 第0帧刀刃已甩出(56 vs 本体 47)。
			#   归一系数本来就是按中性站姿算的, 测试就该盯那一张。
			if str(act) == str(g["ref"]):
				if int(bb["bottom"]) != int(want[1]):
					_fail("%s/%s(中性站姿) 脚底行 %d ≠ 表里的 %d —— 角色会悬空/陷地"
						% [str(g["dir"]), str(act), int(bb["bottom"]), int(want[1])])
				if absi(int(bb["h"]) - int(want[0])) > 2:
					_fail("%s/%s(中性站姿) 本体高 %d ≠ 表里的 %d (容差2) —— 一播动作就大小不对"
						% [str(g["dir"]), str(act), int(bb["h"]), int(want[0])])
		if n == 0:
			_fail("%s 一张动作图都没找到 —— 这组检查是空的" % str(key))
			continue
		heights.sort()
		var med: int = heights[n / 2]
		# idle 基准
		var ib := _frame0_bbox("res://assets/sprites/" + str(g["idle"]))
		if not ib.is_empty() and absi(int(ib["h"]) - int(want[2])) > 2:
			_fail("%s 的 idle 本体高 %d ≠ 表里的 %d" % [str(key), int(ib["h"]), int(want[2])])
		checked += 1
		print("  [归一] %s: %d 张动作图, 本体中位数 %d, 脚底 %d, idle %d"
			% [str(key), n, med, int(want[1]), int(want[2])])
	if checked == 0:
		_fail("一组都没校到 —— 这是空检查不是通过")


## 从 ANIM_NORM 里抠某个键的三元组
func _norm_row(src: String, key: String) -> Array:
	var re := RegEx.new()
	# 匹配形如   "__minion_front__": [45.0, 65.0, 60.0],
	re.compile("\"" + key + "\"\\s*:\\s*\\[\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)")
	var m := re.search(src)
	if m == null:
		return []
	return [float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3))]


## 取图第 0 帧的不透明内容包围盒 {h, bottom}. 方帧横排 → 第0帧是左上角 h×h。
func _frame0_bbox(path: String) -> Dictionary:
	var tex: Texture2D = load(path)
	if tex == null:
		return {}
	var img := tex.get_image()
	if img == null:
		return {}
	var fh := img.get_height()
	var fw: int = mini(fh, img.get_width())
	var top := -1
	var bot := -1
	for y in range(fh):
		for x in range(fw):
			if img.get_pixel(x, y).a > 0.01:
				if top < 0:
					top = y
				bot = y
				break
	if top < 0:
		return {}
	return {"h": bot - top + 1, "bottom": bot + 1}   # bottom 用 1-based 行数, 同 PIL bbox 口径


## 从源码里抠 `const NAME := 123.0` 的数值
func _const_int(src: String, name: String) -> int:
	var re := RegEx.new()
	re.compile("const\\s+" + name + "\\s*:=\\s*([0-9]+)")
	var m := re.search(src)
	return int(m.get_string(1)) if m != null else -1


## ① 表里登记的图都在磁盘上
func _check_sheets_exist(src: String) -> void:
	var paths := _sheet_paths(src)
	print("  [图存在] 检出登记路径 N=%d" % paths.size())
	if paths.size() < 6:
		_fail("只解析到 %d 条精英动作路径, 预期 ≥6 (5个ACTION_ELITE + 1个ACTION_ATTACK) —— 正则失效或表被改" % paths.size())
		return
	for p in paths:
		var full := "res://assets/sprites/" + p
		if not ResourceLoader.exists(full):
			_fail("登记了但文件不存在: %s" % full)


## 从两张表里抠出 pets/animations/elite/*.png
func _sheet_paths(src: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("pets/animations/elite/[A-Za-z0-9_]+\\.png")
	for m in re.search_all(src):
		var s := m.get_string()
		if not out.has(s):
			out.append(s)
	return out


## ② 每个触发点函数体里真的调了 _elite_anim("<动作>")
func _check_hooks(src: String) -> void:
	for fname in HOOKS.keys():
		var body := _func_body(src, str(fname))
		if body == "":
			_fail("找不到函数 %s —— 被改名或删了" % str(fname))
			continue
		# 按"含 _elite_anim( 的行"判定, 不要求字面量参数 ——
		#   铁锤那处是三元 _elite_anim(u, "hammer_big" if big else "hammer"), 死匹配会误报。
		var call_lines := ""
		for line in body.split("\n"):
			if str(line).find("_elite_anim(") >= 0:
				call_lines += str(line) + "\n"
		if call_lines == "":
			_fail("%s 里一次 _elite_anim() 都没调 —— 动作永不播" % str(fname))
			continue
		for act in HOOKS[fname]:
			if call_lines.find("\"%s\"" % str(act)) < 0:
				_fail("%s 的 _elite_anim 调用里没出现动作名 \"%s\"" % [str(fname), str(act)])
	print("  [触发点] 检查 %d 个函数" % HOOKS.size())


## ③ ACTION_ELITE 的动作在 _play_action 的不打断判断里
func _check_no_interrupt(src: String) -> void:
	var body := _func_body(src, "_play_action")
	if body == "":
		_fail("找不到 _play_action")
		return
	if body.find("ACTION_ELITE.has(") < 0:
		_fail("_play_action 的不打断判断里没有 ACTION_ELITE.has(...) —— 精英动作会被普攻/受击秒换掉")
	print("  [不打断] _play_action 白名单已检")


## 取一个顶层函数的函数体 (从 func 行到下一个顶层 func 之前).
##   ★不能用 substr(idx, 固定长度) —— 长度不够会把定义本身吞掉, 让"删掉调用也照样过"的假通过溜过去
##   (2026-07-20 verify_info_panel 踩过)。
func _func_body(src: String, fname: String) -> String:
	var head := "\nfunc %s(" % fname
	var i := src.find(head)
	if i < 0:
		return ""
	var start := i + 1
	var j := src.find("\nfunc ", start)
	if j < 0:
		j = src.length()
	var body := src.substr(start, j - start)
	# 自检: 函数体里不该再出现下一个顶层 func 定义
	if body.find("\nfunc ") >= 0:
		_fail("_func_body(%s) 切歪了 —— 体内还有顶层 func" % fname)
	return body


func _fail(msg: String) -> void:
	_fails.append(msg)


func _done() -> void:
	if _fails.is_empty():
		print("ALL PASS — 精英小将动作动画接线完整")
	else:
		for f in _fails:
			printerr("FAIL: %s" % f)
		printerr("FAIL — 精英小将动作动画 %d 项不通过" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)
