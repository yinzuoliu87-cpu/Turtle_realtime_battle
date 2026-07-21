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
	var want_body := _const_int(src, "ELITE_ACT_BODY_H")
	var want_feet := _const_int(src, "ELITE_ACT_FEET_ROW")
	var want_idle := _const_int(src, "ELITE_IDLE_BODY_H")
	if want_body <= 0 or want_feet <= 0 or want_idle <= 0:
		_fail("解析不到归一常量 (BODY_H=%d FEET_ROW=%d IDLE_BODY_H=%d)" % [want_body, want_feet, want_idle])
		return
	# ★用【各图首帧高度的中位数】比, 不逐张比等值 ——
	#   环形斩第 0 帧刀刃已经甩出来了(实测 56 vs 本体 47), 那不是本体尺寸;
	#   逐张等值会被这种单张异常带偏。中位数对它免疫, 又能抓住"整体重做导致尺寸变了"。
	var heights: Array[int] = []
	var n := 0
	for act in ["attack", "whirl", "hammer", "hammer_big", "whip", "consume", "run"]:
		var p := "res://assets/sprites/pets/animations/elite/%s.png" % act
		if not ResourceLoader.exists(p):
			continue                      # 缺图由 _check_sheets_exist 报
		var bb := _frame0_bbox(p)
		if bb.is_empty():
			_fail("%s 第0帧整帧透明?" % act)
			continue
		n += 1
		heights.append(int(bb["h"]))
		# 脚底行必须每张都一致 —— 它决定角色贴不贴地, 差一点就悬空/陷地, 没有"异常帧"的借口
		if int(bb["bottom"]) != want_feet:
			_fail("%s 第0帧脚底行 %d ≠ ELITE_ACT_FEET_ROW %d —— 动作播出来会悬空/陷地" % [act, int(bb["bottom"]), want_feet])
	if n > 0:
		heights.sort()
		var med: int = heights[n / 2]
		if absi(med - want_body) > 2:
			_fail("动作图本体高中位数 %d ≠ ELITE_ACT_BODY_H %d (容差2) —— 角色一播动作就会大小不对。各图首帧: %s"
				% [med, want_body, str(heights)])
	# idle 基准图
	var ib := _frame0_bbox("res://assets/sprites/pets/minion-elite.png")
	if not ib.is_empty() and int(ib["h"]) != want_idle:
		_fail("idle 本体高 %d ≠ ELITE_IDLE_BODY_H %d" % [int(ib["h"]), want_idle])
	print("  [归一] 校对 %d 张动作图 + idle 基准" % n)   # ★打印分母: N=0 是空检查不是通过


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
