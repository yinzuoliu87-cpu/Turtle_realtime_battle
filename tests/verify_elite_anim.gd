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
## ★★2026-09-03: 动作表的判据从【源码正则】改成【读真常量】。
##   由来: `ACTION_ELITE` 整表从上帝文件搬到 `scripts/gamedata/action_elite.gd`
##   (主文件超 arch_budget, 按 CLAUDE.md §5 落位表挪走), 正则当场全部落空 ——
##   本测试自己的分母断言「节拍校对一个都没跑到 — 空检查不是通过」把它抓住了。
##   CLAUDE.md §2 早写过这个坑:「审计器读战斗源码找数值, 函数外迁到新文件后
##   它找不到 = 误报」。⇒ 读常量跟着引擎实际读到的那份走, 表放哪个文件都不影响。
const RBS := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")


## 按名字取动作表。★`Script.get(名字)` 读的是属性, const 不在其中 ⇒ 走 constant_map。
##
## ★★三张表**住在三个不同的文件**里 —— 这也是"读常量比读源码可靠"的直接证据:
##     ACTION_MELEE  → RealtimeBattle3DScene.gd
##     ACTION_ELITE  → scripts/gamedata/action_elite.gd(2026-09-03 搬走)
##     ACTION_RANGED → scripts/gamedata/minion_codex.gd
##   原来的 `_fps_in_table` 对**主文件源码**跑正则 `"<act>": ["...", fps]`,
##   **完全不检查表名** ⇒ 它在整份源码里瞎找, ACTION_RANGED 明明不在主文件里
##   却"解析到 1 个"。那是宽一格的假判据(memory [[fb-judge-must-fit-the-shape]]),
##   换成读常量之后才暴露出来。
const MinionCodexRef := preload("res://scripts/gamedata/minion_codex.gd")
const ActionEliteRef := preload("res://scripts/gamedata/action_elite.gd")

static func _consts() -> Dictionary:
	var out: Dictionary = (RBS as Script).get_script_constant_map().duplicate()
	## 后并入的不覆盖主文件已有的同名键(主文件的 ACTION_ELITE 就是 ActionElite.TABLE 本身)
	for src2 in [(MinionCodexRef as Script), (ActionEliteRef as Script)]:
		for k in src2.get_script_constant_map():
			if not out.has(k):
				out[k] = src2.get_script_constant_map()[k]
	return out

# 触发点函数名 → 期望在函数体里出现的 _elite_anim 动作名
const HOOKS := {
	"_elite_whirl":       ["whirl"],
	"_elite_try_consume": ["consume"],
	"_tick_elite_whip":   ["whip"],
	"_sk_elite_hammer":   ["hammer", "hammer_big"],
}

var _fails: Array[String] = []


func _ready() -> void:
	## ★2026-08-21 扫描面跟着内容走: `ACTION_RANGED` 与 `ART_FACES_RIGHT_KEY` 已从主战斗文件
	##   挪到 gamedata/minion_codex.gd(架构预算不许往上帝文件加表)。判据是"在源码文本里找表",
	##   不跟着挪就会报「解析不到 fps」—— CLAUDE.md §2 记过这个坑(函数外迁后审计器误报)。
	var src := ""
	for _sf in [SCENE_PATH,
		"res://scripts/systems/skills/elite_system.gd",
		"res://scripts/scenes/battle/battle_vfx.gd",
		"res://scripts/scenes/battle/battle_render.gd",
		"res://scripts/gamedata/minion_codex.gd"]:
		src += FileAccess.get_file_as_string(str(_sf)) + "\n"
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
## 精英五段的节拍(2026-07-22 复查补上 —— 做精英动画时压根没量过, 四段对不上)
##   数字取自代码: _elite_whirl 的 tween 0.42 / _sk_elite_hammer 撞击帧 delay 0.43 /
##   hammer_big 0.35跳起+1.0空中蓄力+0.12下砸 / _tick_elite_whip 0.3链射+0.18拉体 /
##   _elite_try_consume 的 _pending_shots delay 1.5
const ELITE_BEATS := {
	"whirl": 0.42, "hammer": 0.43, "hammer_big": 1.47, "whip": 0.48, "consume": 1.50,
}

## 远程小将(2026-08-21)。技能 = 火箭蓄力 1.5 秒(`_sk_minion_rocket` 的蓄力段)。
## ★动画时长必须 == 代码节拍, 否则动画先播完、角色站着发呆(精英/近战都栽过)。
const RANGED_BEATS := {
	"skill": 1.5,
}

const MELEE_BEATS := {
	"leap": 0.64,    # 0.00-0.64 蓄力(tween_interval 0.3) + 起跳(tween_method 0.34)
	"throw": 0.64,   # 0.64-1.28 滞空(_pending_shots delay 0.68 → 1.28)
	"dive": 0.30,    # 1.28-1.58 俯冲(_minion_bodysurf_ride 的 while d < 0.3)
	"surf": 0.833,   # 1.58-2.41 踩滑(slide_dur = 0.833)
	"land": 0.30,    # 2.41 侧跳落地
}

func _check_melee_timing(src: String) -> void:
	_check_timing_group(src, "melee", "ACTION_MELEE", MELEE_BEATS)
	_check_timing_group(src, "ranged", "ACTION_RANGED", RANGED_BEATS)
	_check_timing_group(src, "elite", "ACTION_ELITE", ELITE_BEATS)


func _check_timing_group(src: String, dir_name: String, table: String, beats: Dictionary) -> void:
	var n := 0
	for act in beats.keys():
		var fps := _fps_in_table(src, table, str(act))
		if fps <= 0.0:
			_fail("%s 里解析不到 %s 的 fps" % [table, str(act)])
			continue
		var p := "res://assets/sprites/pets/animations/%s/%s.png" % [dir_name, str(act)]
		if not ResourceLoader.exists(p):
			_fail("缺图 %s" % p)
			continue
		var tex: Texture2D = load(p)
		var frames: int = maxi(1, tex.get_width() / tex.get_height())
		var dur: float = float(frames) / fps
		var beat: float = float(beats[act])
		n += 1
		if absf(dur - beat) > 0.03:
			_fail("%s/%s 动画 %.3fs ≠ 节拍 %.3fs (差 %+.3fs) —— %s"
				% [dir_name, str(act), dur, beat, dur - beat,
				   "动画先播完, 剩下时间角色会站着" if dur < beat else "动画会被下一段打断"])
	print("  [节拍] %s: 校对 %d 个动作" % [dir_name, n])
	if n == 0:
		_fail("节拍校对一个都没跑到 —— 空检查不是通过")


## 从指定动作表里抠某动作的 fps
func _fps_in_table(_src: String, table: String, act: String) -> float:
	## ★读真常量, 不解析源码(见文件头 RBS 那段注释)。
	var d = _consts().get(table, null)
	if not (d is Dictionary):
		return -1.0
	var e = (d as Dictionary).get(act, null)
	if not (e is Array) or (e as Array).size() < 2:
		return -1.0
	return float((e as Array)[1])


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
## 【朝向】改成金样本, 不再自动判。
##
## ★★2026-08-21 用户对着逐帧接触印相把三处朝向错误一个个指出来之后, 我得承认:
##   **自动判朝向的判据今晚错了三次** ——
##     ① `_reach_dir`(最外缘) 被精英背后的**披风**骗, 把朝右的图一路判绿;
##     ② 换成"面罩重心"后, 被中间帧那对**紫色拳套**骗, hammer_big 全判成朝左;
##     ③ 我照着②的数值把**本来正确**的 idle/attack/hammer 镜像坏了(已还原)。
##   ⇒ 不再让机器猜"它朝哪边"。**朝向的权威是人眼**;
##     门禁的职责改成【把人确认过的那一版冻住】—— 与 tools/text_golden.py 同一个思路。
##   谁重新生成/镜像了素材, 这里就会红, 逼一次人工复核, 而不是被一个坏判据静默放过。
const FACING_GOLDEN_PATH := "res://tests/golden/minion_facing.txt"


func _check_facing() -> void:
	var cur: Array = []
	for d in ["melee", "elite", "ranged", "wraith"]:
		var dir := DirAccess.open("res://assets/sprites/pets/animations/%s" % d)
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".png"):
				continue
			cur.append("%s/%s %s" % [d, f.get_basename(),
				_sil_fingerprint("res://assets/sprites/pets/animations/%s/%s" % [d, f])])
	for n in ["minion", "minion-elite", "minion-back", "wraith"]:
		var ip := "res://assets/sprites/pets/%s.png" % n
		if ResourceLoader.exists(ip):
			cur.append("idle/%s %s" % [n, _sil_fingerprint(ip)])
	cur.sort()
	## ★分母断言: 扫不到图就等于空检查
	print("  [朝向] 扫到 %d 张图(动作+立绘)" % cur.size())
	if cur.size() < 15:
		_fail("只扫到 %d 张图, 预期 ≥15 —— 目录没读到就等于漏检" % cur.size())
	var want := ""
	if FileAccess.file_exists(FACING_GOLDEN_PATH):
		want = FileAccess.get_file_as_string(FACING_GOLDEN_PATH).strip_edges()
	var got := "\n".join(PackedStringArray(cur))
	if want == "":
		var fh := FileAccess.open(FACING_GOLDEN_PATH, FileAccess.WRITE)
		if fh != null:
			fh.store_string(got)
			fh.close()
		print("  [朝向] 首次建立金样本(%d 张) —— 内容是【人眼已确认】的那一版" % cur.size())
		return
	if got == want:
		print("  [朝向] 与金样本一字不差(%d 张) —— 没人动过素材" % cur.size())
		return
	var wl := want.split("\n")
	var changed: Array = []
	for line in cur:
		if not wl.has(line):
			changed.append(str(line).split(" ")[0])
	_fail("素材变了(%s) —— 朝向的权威是人眼: 逐帧看过确认无误后, 删掉 %s 让它重建"
		% [", ".join(PackedStringArray(changed)).substr(0, 120), FACING_GOLDEN_PATH])


## 轮廓指纹: 逐帧取 alpha 轮廓的左右重心差(量化成整数), 拼成一串。
## ★只用来发现"素材被改了", **不用来判朝向** —— 判朝向那件事已经证明机器做不可靠。
func _sil_fingerprint(path: String) -> String:
	var tex: Texture2D = load(path)
	if tex == null:
		return "?"
	var img := tex.get_image()
	if img == null:
		return "?"
	var h := img.get_height()
	var frames: int = maxi(1, img.get_width() / h)
	var parts: Array = []
	for f in range(frames):
		var l := 0
		var r := 0
		for x in range(h):
			for y in range(h):
				if img.get_pixel(f * h + x, y).a > 0.16:
					if x < h / 2:
						l += 1
					else:
						r += 1
		parts.append(str(l - r))
	return ",".join(PackedStringArray(parts))

## 背后有披风/尾焰的图 —— 最外缘量到的是那个附件, 不是朝向。改用面罩位置判。
const FACE_JUDGE_SHEETS := ["elite/attack", "elite/hammer"]


## 面罩(高饱和高亮像素)重心 − 整体重心, 逐帧平均。负 = 脸偏左 = 朝左。
func _face_dir(path: String) -> float:
	var tex: Texture2D = load(path)
	if tex == null:
		return 0.0
	var img := tex.get_image()
	if img == null:
		return 0.0
	var h := img.get_height()
	var frames: int = maxi(1, img.get_width() / h)
	var acc := 0.0
	var used := 0
	for f in range(frames):
		var fx := 0.0
		var fn := 0
		var bx := 0.0
		var bn := 0
		for x in range(h):
			for y in range(h):
				var col := img.get_pixel(f * h + x, y)
				if col.a < 0.16:
					continue
				bx += float(x)
				bn += 1
				if col.s > 0.30 and col.v > 0.42:
					fx += float(x)
					fn += 1
		if fn >= 6 and bn >= 10:
			acc += (fx / float(fn)) - (bx / float(bn))
			used += 1
	return (acc / float(used)) if used > 0 else 0.0


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
		## ★2026-08-21 新增远程小将。它此前**一张动作图都没有**, 也不在这张表里 ——
		##   所以它的朝向/归一/时长【从来没有人守过】。
		"__minion_back__": {"dir": "ranged", "idle": "pets/minion-back.png",
			"ref": "attack", "acts": ["attack", "run", "skill"]},
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
func _sheet_paths(_src: String) -> Array[String]:
	## ★读真常量: 把 ACTION_ELITE / ACTION_ATTACK 两张表里的 elite 动作图路径掏出来。
	##   原来是对主文件源码跑正则 `pets/animations/elite/*.png`, 表一搬家就全落空。
	var out: Array[String] = []
	var cs := _consts()
	for tbl in ["ACTION_ELITE", "ACTION_ATTACK"]:
		var d = cs.get(tbl, null)
		if not (d is Dictionary):
			continue
		for k in (d as Dictionary):
			var e = (d as Dictionary)[k]
			if not (e is Array) or (e as Array).is_empty():
				continue
			var pth := str((e as Array)[0])
			if pth.contains("pets/animations/elite/") and not out.has(pth):
				out.append(pth)
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
