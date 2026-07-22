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
	_check_facing()
	_check_melee_timing(src)
	_done()


## ⑥ 近战小将各动作的【动画时长】必须等于技能里的【代码节拍】(2026-07-22 用户「时间对不上吗」)
##
## ★对不上的后果不是"手感差"而是【动画先播完 → _advance_anim 立刻回 idle】,
##   剩下那段时间角色是站姿。实测: surf 12fps×4帧=0.33s 而踩滑节拍 0.833s
##   → 踩着敌人滑行的【后 0.50 秒角色站着】。leap/throw 也各早完 0.07s。
## 节拍取自 _sk_minion_bodysurf / _minion_bodysurf_ride 里的真实数字, 见方案书 §3.5 时间轴。
const MELEE_BEATS := {
	"leap": 0.64,    # 0.00-0.64 蓄力(tween_interval 0.3) + 起跳(tween_method 0.34)
	"throw": 0.64,   # 0.64-1.28 滞空(_pending_shots delay 0.68 → 1.28)
	"dive": 0.30,    # 1.28-1.58 俯冲(_minion_bodysurf_ride 的 while d < 0.3)
	"surf": 0.833,   # 1.58-2.41 踩滑(slide_dur = 0.833)
	"land": 0.30,    # 2.41 侧跳落地
}

func _check_melee_timing(src: String) -> void:
	var n := 0
	for act in MELEE_BEATS.keys():
		var fps := _melee_fps(src, str(act))
		if fps <= 0.0:
			_fail("ACTION_MELEE 里解析不到 %s 的 fps" % str(act))
			continue
		var p := "res://assets/sprites/pets/animations/melee/%s.png" % str(act)
		if not ResourceLoader.exists(p):
			_fail("缺图 %s" % p)
			continue
		var tex: Texture2D = load(p)
		var frames: int = maxi(1, tex.get_width() / tex.get_height())
		var dur: float = float(frames) / fps
		var beat: float = float(MELEE_BEATS[act])
		n += 1
		if absf(dur - beat) > 0.03:
			_fail("%s 动画 %.3fs ≠ 节拍 %.3fs (差 %+.3fs) —— %s"
				% [str(act), dur, beat, dur - beat,
				   "动画先播完, 剩下时间角色会站着" if dur < beat else "动画会被下一段打断"])
	print("  [节拍] 校对 %d 个动作的 动画时长 ↔ 代码节拍" % n)
	if n == 0:
		_fail("节拍校对一个都没跑到 —— 空检查不是通过")


## 从 ACTION_MELEE 里抠某动作的 fps
func _melee_fps(src: String, act: String) -> float:
	var re := RegEx.new()
	re.compile("\"" + act + "\"\\s*:\\s*\\[\\s*\"[^\"]+\"\\s*,\\s*([0-9.]+)")
	var m := re.search(src.substr(maxi(0, src.find("const ACTION_MELEE"))))
	return float(m.get_string(1)) if m != null else 0.0


## ⑤ 动作图的朝向必须与 idle 一致 (2026-07-22 用户「方向是否正确」抓到)
##
## ★这个 bug 完全无声: PixelLab 生成的近战小将 attack 是【朝右刺】的, 而项目全局约定是
##   「原图朝左」(ART_FACES_RIGHT 只有 hiding/headless/mech 三个例外), 于是引擎认为它朝左 →
##   敌人在右时 flip_h=true 把它翻过去 → 变成【背对敌人朝左刺】。
##   探针实测: face_right=true art_right=false flip_h=true —— 逻辑没错, 是素材反了。
##   已把 7 张近战图逐帧水平镜像修正(不能整条镜像, 那会连帧顺序一起倒过来)。
##
## 判据: 拿【武器伸出最远的那一帧】比, 看极值落在身体中线的哪一侧。
##   不用"各帧 bbox 中心的平均"—— 那个会被来回摆动的动作抵消掉
##   (实测它把明明朝右刺的 melee/attack 判成"居中")。
func _check_facing() -> void:
	# [目录, 用来判方向的动作]  —— 挑动势指向明确的那张
	var cases := [["melee", "attack"]]
	var n := 0
	for c in cases:
		var p := "res://assets/sprites/pets/animations/%s/%s.png" % [str(c[0]), str(c[1])]
		if not ResourceLoader.exists(p):
			continue
		var d := _reach_dir(p)
		n += 1
		print("  [朝向] %s/%s 伸展方向 %+.1f (负=朝左, 与全局约定一致)" % [str(c[0]), str(c[1]), d])
		if d > 0.0:
			_fail("%s/%s 是【朝右】的, 但项目约定原图朝左(ART_FACES_RIGHT 里没有小将) —— 引擎会再翻一次, 变成背对敌人出招。修法: 逐帧水平镜像" % [str(c[0]), str(c[1])])
	if n == 0:
		_fail("朝向检查一张图都没跑到 —— 空检查不是通过")


## 武器伸得最远那一帧, 极值在中线哪一侧 (正=朝右)
func _reach_dir(path: String) -> float:
	var tex: Texture2D = load(path)
	if tex == null:
		return 0.0
	var img := tex.get_image()
	if img == null:
		return 0.0
	var h := img.get_height()
	var frames: int = maxi(1, img.get_width() / h)
	var best := 0.0
	for f in range(frames):
		var lo := h
		var hi := -1
		for x in range(h):
			for y in range(h):
				if img.get_pixel(f * h + x, y).a > 0.01:
					lo = mini(lo, x)
					hi = maxi(hi, x)
					break
		if hi < 0:
			continue
		var mid := float(h) * 0.5
		# 该帧向左/向右各伸出多远, 取更大的那侧作为本帧的"伸展方向"
		var reach_r := float(hi) - mid
		var reach_l := mid - float(lo)
		var d: float = reach_r if reach_r > reach_l else -reach_l
		if absf(d) > absf(best):
			best = d
	return best


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
