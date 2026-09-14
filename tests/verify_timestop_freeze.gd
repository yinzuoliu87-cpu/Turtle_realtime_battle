extends Node
## verify_timestop_freeze.gd — 059 沙漏【时停期间到底冻没冻】
##
## ══════════════════════════════════════════════════════════════════
##  ★由来：用户 2026-09-14「这个装备我看有很多有问题的地方，**很多特效没有冻结**」
## ══════════════════════════════════════════════════════════════════
## 他是对的，而且能量出来。
##
## **尺子来自参考**（JoJo「ザ・ワールド」15 秒 149 帧，逐帧研究见
## `docs/studies/20260914e-059时停参考逐帧.md`）：定格段的帧间运动量实测 **0.00 ~ 0.81**，
## 而动态段 **1.25 ~ 90.47** —— 定格就是**真的一帧都不动**，不是"大致静止"。
##
## 产品侧的等价物：时停期间 `battle._world` 下**没有任何 Node3D 的 transform / 帧号 / 颜色会变**
## （场上只有携带者能动，而本门禁把携带者配成不出手）。
##
## **探针实测（修之前）**：时停期间 `_world` 里 **56 个节点照常在动**，
## 位移量和时停前一模一样（背景鱼群 Δpos 1.4112 → 1.4188、气泡 1.1063 → 1.1122）。
## 根因不是"漏了某一处"，是**战斗世界侧有 23 处直接用 `create_tween()`**，
## 绕开了 `_reg_tween()` ⇒ 它们从来没进过 `battle._sim_tweens` ⇒ `_ts_begin_freeze()` 找不到它们。
## 主场景 48 行的注释早就写着「依赖 `_reg_tween` 的时停契约(**漏注册=时停静默失效**)」——
## 契约在，但没有任何东西守着它。这个文件就是那个守卫。
##
## ══════════════════════════════════════════════════════════════════
##  ★判据形状（三条，各自配分母）
## ══════════════════════════════════════════════════════════════════
## ① **背景远景**（鱼群/气泡，`FarBackdrop` 子树）时停期间 **0 个节点变化**。
##    分母：时停**之前**同样采样必须有一大把在动 —— 否则是空检查。
## ② **非携带者单位的立绘**时停期间位置/帧号/颜色一个都不变。
##    分母：它在时停前是会动的。
## ③ **解除后必须恢复**：`_end_timestop()` 之后背景重新动起来。
##    ——冻死了也是 bug，只验"冻得住"会放过"再也不动了"。
##
## ★为什么不判"变化节点数 == 0"：时停**自己的**演出（蓄力沙漏虚影 / 时之主金辉光 / 停摆钟）
##   和**携带者自己**本来就该继续动（它是唯一能动的人）。判据必须刚好卡住"别人不许动"
##   这个形状，宽一格会造假 bug、窄一格会放过真 bug
##   （memory [[fb-judge-must-fit-the-shape]]）。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s" % t)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


## 采样 `_world` 子树里每个 Node3D 的「会动的三个量」: 世界坐标 / 帧号 / 颜色。
func _snap(n: Node, out: Dictionary, path: String) -> void:
	for c in n.get_children():
		var p: String = path + "/" + c.name
		if c is Node3D:
			var rec: Array = [c.global_position, Color(0, 0, 0, 0), 0]
			if c is SpriteBase3D:
				rec[1] = c.modulate
				rec[2] = c.frame
			out[p] = rec
		_snap(c, out, p)


## 返回 (路径前缀含 `pfx` 的) 变化节点数。`pfx` 为空 = 全部。
func _moved(a: Dictionary, b: Dictionary, pfx: String) -> Array:
	var hit: Array = []
	for k in a.keys():
		if not b.has(k) or (pfx != "" and not str(k).begins_with(pfx)):
			continue
		var x: Array = a[k]
		var y: Array = b[k]
		var dp: float = (x[0] as Vector3).distance_to(y[0] as Vector3)
		var c0: Color = x[1]
		var c1: Color = y[1]
		var dc: float = absf(c0.a - c1.a) + absf(c0.r - c1.r) + absf(c0.g - c1.g) + absf(c0.b - c1.b)
		if dp > 0.0005 or dc > 0.002 or int(x[2]) != int(y[2]):
			hit.append(k)
	return hit


func _wait(nf: int) -> void:
	for _i in range(nf):
		await get_tree().process_frame


## 跑 nf 帧, 返回这段时间里 `_world` 下变化的节点(按前缀过滤)。
func _window(nf: int, pfx: String) -> Array:
	var a: Dictionary = {}
	_snap(_s._world, a, "")
	await _wait(nf)
	var b: Dictionary = {}
	_snap(_s._world, b, "")
	return _moved(a, b, pfx)


func _mk(id: String, side: String, dx: float, star: int) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + Vector2(dx, 0))
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	u["maxHp"] = 99999.0
	u["hp"] = 99999.0
	if star > 0:
		u["equips"] = [{"id": "p2eq_059", "star": star}]
	_s._units.append(u)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 059 沙漏: 时停期间世界到底冻没冻 ===")
	print("   尺子: 参考里定格段帧间运动 0.00~0.81 / 动态段 1.25~90.47 ⇒ 定格 = 一帧都不动")
	_s = RB.new()
	add_child(_s)
	await _wait(40)

	_s._units.clear()
	var carrier: Dictionary = _mk("fortune", "left", -200.0, 3)   # 3★ ⇒ 定格 20 秒, 窗口够长
	var other: Dictionary = _mk("stone", "right", 260.0, 0)       # 不带沙漏的那个: 它必须被冻住
	await _wait(30)
	var other_path: String = "/" + str(other["sprite"].name) if other.get("sprite", null) != null else ""

	# ── ① 分母: 时停【之前】世界在动 ──
	var pre: Array = await _window(90, "")
	var pre_bg: Array = pre.filter(func(k): return str(k).begins_with("/FarBackdrop"))
	_ok("★分母①: 时停【之前】_world 里 %d 个节点在动(其中背景远景 %d 个)" % [pre.size(), pre_bg.size()],
		pre_bg.size() >= 20,
		"背景远景一个都不动 ⇒ 下面「冻住了」是空检查, 不是产品的功劳")
	## ★分母②必须验「它在时停【之前】是会动的」, 光验"节点在场"守不住 ——
	##   那只龟配了 no_move/no_basic, 若它本来就一动不动, 判据② 就是恒真式。
	var pre_other: Array = pre.filter(func(k): return str(k) == other_path)
	_ok("★分母②: 非携带者那只的立绘(%s)在时停【之前】是会动的" % other_path,
		other_path != "" and not pre_other.is_empty(),
		"它本来就不动 ⇒ 判据②「时停期间它不动」是恒真式, 什么都没验到")

	# ── ② 真入口触发时停 ──
	var ts = _s._timestop
	_s._t = 999.0
	ts._ts_update_trigger(0.016)
	ts._ts_update_trigger(10.0)
	_ok("★分母③: 时停真的进了(active=%d, 剩 %.1f 秒)"
		% [(ts._ts_active as Array).size(), float(ts._ts_remaining)],
		not (ts._ts_active as Array).is_empty() and float(ts._ts_remaining) > 5.0,
		"没进时停 ⇒ 下面全是空检查")
	await _wait(40)   # 让入停那一下的演出(反色闪/扩散)跑完 —— 它本来就不该冻

	# ── ③ 判据: 时停期间, 背景一个都不许动 ──
	var dur: Array = await _window(90, "")
	var dur_bg: Array = dur.filter(func(k): return str(k).begins_with("/FarBackdrop"))
	_ok("① 时停期间【背景远景】0 个节点在动(实测 %d 个, 时停前是 %d 个)"
		% [dur_bg.size(), pre_bg.size()],
		dur_bg.is_empty(),
		"这些还在动: %s" % str(dur_bg.slice(0, 6)))

	var dur_other: Array = dur.filter(func(k): return str(k) == other_path)
	_ok("② 时停期间【非携带者那只的立绘】一动不动(位置/帧号/颜色)",
		dur_other.is_empty(),
		"它变了 —— 只有携带者能动, 别人必须定格")

	print("     [探针] 时停期间仍在动的全部节点(应当只剩时停自己的演出 + 携带者自己): %s"
		% str(dur.slice(0, 8)))

	# ── ④ 判据: 灰世界要**一直**灰到解除, 不能灰一下就没了 ──
	## ★★量这条时我自己先栽了一次: VFXLAB 的拍点排在**游戏钟**上, 而时停期间游戏钟是**冻结**的
	##   ⇒ 目标 11.6 / 12.5 / 14.0 三个拍点全部落在 t=11.00 同一个点上, 再往后的拍点
	##   (17/21/26)其实已经是**时停结束之后**了。我照着那组数差点写下"灰世界只持续 1 秒"。
	##   ⇒ 验持续性不能按游戏钟采样, 直接读产品自己的 shader 参数。
	##   (memory [[fb-second-clock-drops-events]]: 两条钟必然丢事件)
	var rect = ts._ts_rect
	var amt_hold: float = -1.0
	var amt_min: float = 999.0
	if rect != null and is_instance_valid(rect) and rect.material != null:
		for _k in range(6):                       # 跨 6 个采样窗口(真实时间), 期间不许掉下去
			await _wait(20)
			amt_hold = float(rect.material.get_shader_parameter("amount"))
			amt_min = minf(amt_min, amt_hold)
	_ok("④ 压暗褪色在整段时停里**一直**满值(6 次采样最小 %.2f)" % amt_min,
		amt_min > 0.95,
		"灰世界中途掉下去了 —— 20 秒的时停只灰开头几帧等于没做")

	# ── ⑤ 判据: 解除后必须恢复 —— 冻死了也是 bug ──
	ts._end_timestop()
	await _wait(20)
	var post: Array = await _window(90, "")
	var post_bg: Array = post.filter(func(k): return str(k).begins_with("/FarBackdrop"))
	_ok("⑤ 解除时停后【背景远景】重新动起来(实测 %d 个, 时停前 %d 个)"
		% [post_bg.size(), pre_bg.size()],
		post_bg.size() >= maxi(20, pre_bg.size() / 2),
		"只验「冻得住」会放过「再也不动了」—— _ts_resume_freeze 必须把 tween play 回来")

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
