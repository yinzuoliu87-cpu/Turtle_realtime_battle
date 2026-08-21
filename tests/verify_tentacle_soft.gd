extends Node
## verify_tentacle_soft.gd — 触手拍击要【像鞭子】: 行波前沿在跑 + 梢端不回抬
##
## 用户 2026-08-20 句7:「拍击时触手没有很柔软的弯曲而是只超一个方向弯曲头部，这样是不行的」
##   选了 (b) 连砸下去也要柔软。
##
## ★★为什么判据是"梢端高度单调不上升"而不是"曲率不许变号":
##   2026-08-05 为根治用户报的「拍下去两次」, 把逐段滞后/横向摆动/反向曲率全关死了 ——
##   那等于**禁止 S 形 = 禁止柔软**, 把孩子和洗澡水一起倒了。
##   而当年"拍两次"的**真因不是 S 形本身**, 是梢端在下压过程中【往回抬】
##   (曲率的积分: 抻直时 curl 从 68° 降到 6°, 等于把梢端角抬高 62°;
##    当年门禁实测回抬 3 次、幅度 +25%)。
##   ⇒ 盯住"梢端一路往下不回头"就够了, 柔软(S形/行波/横摆)可以放开。
##
## ★判据量的是**真几何**: `_rebuild` 每帧把梢端世界 Y 写进 `tip_y`, 这里逐帧读它 ——
##   不是重推一遍公式(重推的副本必然与渲染漂开)。

## 下砸期允许的单帧最大回抬。实测基线(全关柔软)=0.0287, 留余量。★只降不升。
const RISE_CAP := 0.032

## ★★2026-08-21 用户:「这个改的不太行…是像鞭子一样柔软拍下去，什么叫鞭子？」
##   —— 上一版只放开了横向摆动, 交出去的仍然是**一根一起转的棍子**。
##   鞭子的定义性特征是**行波**: 一个弯从根跑到梢, 任一瞬间弯的两侧姿态不同。
##   ⇒ 光"不回抬"守不住这件事(把它焊成铁棍也不回抬), 必须**正面量前沿在不在跑**。
##
## 【怎么量】沿长度取 9 个站点, 逐帧读**产品自己建好的几何高度**(`height_profile_of`),
##   算每个站点"下落到中点"的时刻 = 前沿扫到它的时刻。
##   棍子: 所有站点同时到达(时差≈0); 鞭子: 到达时刻沿长度**依次推后**。
## 前沿从根到梢的最小时差(秒)。T_SLAM=0.50。
const FRONT_SPREAD_MIN := 0.10
## 判定"这个站点下落过"的最小落差 —— 根部几乎不动, 拿它算到达时刻只会得到噪声。
const STATION_DROP_MIN := 0.25
## 伤害结算与梢端真正落地之间允许的最大时差(秒)。
## ★方案书 ⑬ 当年实测 0.07 秒 ——「时机本来就是对的」这句结论就建立在这个数上。
##   行波把落地推后, 所以留一点余量, 但不许无限放大(那就成了"伤害不等演出到达")。
## 【伤害 ↔ 落地 对齐】用户 2026-08-21 拍板:「肯定是落地伤害」。
## 改之前伤害在 `T_WARN+T_REAR` = ST_SLAM 第 0 帧结算, 而那一刻梢端在 y=9.18 **半空**,
## 要到 SLAM+0.29 才砸到 —— **早 0.3 秒(≈20 帧), 一直在出货**。
## (方案书曾写「只差 0.07 秒」是错的: 我把 `SNAP_T`(抽直完成) 当成了落地。已订正。)
## ⇒ `hit_delay` 现在 = `T_WARN + T_REAR + T_TOUCH`。
## ★而 `T_TOUCH` 是**手填的**, 动画常量一改它就会悄悄漂 ⇒ 这里**逐帧量真几何反查它**。
const HIT_GAP_MAX := 0.05
## 落地口径: 梢端走完全程落差的这个比例就算"砸到了"(后面是缓慢沉降)。
const TOUCH_FRAC := 0.90

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	print("=== 触手: 像鞭子(行波前沿) + 梢端不回抬 ===")

	var tv = scn._tentacle_vfx
	_ok("★分母: tentacle_vfx 在场", tv != null)
	if tv == null:
		_done(scn)
		return

	tv.ensure_forced("left", 1)
	## 先推到待机 —— ★用"等到状态真的变成 ST_IDLE"而不是"推固定帧数":
	##   第一版推 80 帧就往下走, 结果触手还在出土(state=0), 下砸期采到 **0 个样本**,
	##   而"单调不上升"那条**空过了** —— 分母断言当场抓到, 否则就是假绿灯。
	var guard := 0
	while guard < 2000 and tv.state_of("left", 0) != 1:
		tv.tick(1.0 / 60.0)
		guard += 1
	_ok("★分母: 触手已出土并待机(state=ST_IDLE)", tv.state_of("left", 0) == 1,
		"state=%d" % tv.state_of("left", 0))

	var root: Vector2 = tv.default_root("left", 0)
	tv.strike("left", 0, root + Vector2(300.0, 0.0), 1.0)

	# 逐帧推进, 只在【下砸期 ST_SLAM=3】采样梢端高度
	var ys: Array = []
	var profs: Array = []          # 每帧一份沿长度的高度剖面(9 站点)
	var worst := 0.0
	var rises := 0
	for i in range(400):
		tv.tick(1.0 / 120.0)                       # 半帧步长: 采样够密才看得见回抬
		if tv.state_of("left", 0) != 3:
			if not ys.is_empty():
				break                              # 已经走完 SLAM
			continue
		var y: float = tv.tip_y_of("left", 0)
		profs.append(tv.height_profile_of("left", 0))
		if not ys.is_empty():
			var d: float = y - float(ys[ys.size() - 1])
			## ★阈值 = **实测基线**(2026-08-05 焊死版自身的回抬 0.0287) + 余量; 不是"理论该为 0"。
			##   这是棘轮: 柔软度调过头会把回抬放大到超过基线, 当场红(实测 滞后0.10 → 0.0534)。
			if d > RISE_CAP:
				rises += 1
				worst = maxf(worst, d)
		ys.append(y)
	print("     下砸期采到 %d 个梢端高度样本, 回抬 %d 次, 最大回抬 %.4f" % [ys.size(), rises, worst])
	_ok("★分母: 真的采到了下砸期的样本(否则是空检查)", ys.size() >= 8,
		"只采到 %d 个" % ys.size())
	_ok("★★梢端在下砸期【单调不上升】(不许回抬 = 不许读成第二次拍击)", rises == 0,
		"回抬 %d 次, 最大 %.4f" % [rises, worst])
	## ══ 鞭子那一半: 【行波前沿必须在跑】 ══════════════════════════
	## ★这条是本门禁的**核心**。上一版只有"不回抬", 而把触手焊成铁棍照样不回抬 ——
	##   判据守不住需求。现在正面量: 前沿有没有沿长度依次推进。
	var dt: float = 1.0 / 120.0
	var arrive: Array = []
	var valid := 0
	if profs.size() >= 8 and (profs[0] as PackedFloat32Array).size() > 0:
		for st in range((profs[0] as PackedFloat32Array).size()):
			var y0: float = float((profs[0] as PackedFloat32Array)[st])
			var y1: float = float((profs[profs.size() - 1] as PackedFloat32Array)[st])
			if y0 - y1 < STATION_DROP_MIN:
				arrive.append(-1.0)      # 这个站点没怎么动(根部) —— 显式登记, 不静默跳过
				continue
			var half: float = y0 - (y0 - y1) * 0.5
			var tt := -1.0
			for fi in range(profs.size()):
				if float((profs[fi] as PackedFloat32Array)[st]) <= half:
					tt = float(fi) * dt
					break
			arrive.append(tt)
			if tt >= 0.0:
				valid += 1
	var shown := PackedStringArray()
	for st2 in range(arrive.size()):
		shown.append("%d:%s" % [st2,
			"—" if float(arrive[st2]) < 0.0 else ("%.3f" % float(arrive[st2]))])
	print("     站点到达时刻(根→梢): %s" % ", ".join(shown))
	_ok("★分母: 至少 5 个站点真的下落过(否则到达时刻是噪声)", valid >= 5,
		"只有 %d 个" % valid)
	var mono := true
	var last := -1.0
	for st3 in range(arrive.size()):
		var tt2: float = float(arrive[st3])
		if tt2 < 0.0:
			continue
		if tt2 < last - 0.0001:
			mono = false
		last = tt2
	_ok("★★前沿沿长度【单调推进】(根先动、梢后动)", mono)
	var first_t := -1.0
	var last_t := -1.0
	for st4 in range(arrive.size()):
		var tt3: float = float(arrive[st4])
		if tt3 < 0.0:
			continue
		if first_t < 0.0:
			first_t = tt3
		last_t = tt3
	var spread: float = (last_t - first_t) if first_t >= 0.0 else 0.0
	## ══ 落地时刻必须对得上伤害时刻 ══════════════════════════════
	## 用户 2026-08-20:「现在难道不是落地的时候出伤吗」。方案书 ⑬ 当年量到的差是 0.07 秒,
	## 那是**旧动画**的数字 —— 行波会把落地推后, 所以这条必须由门禁**当场重算**,
	## 不许抄方案书里那个 0.07(它会烂)。★量的是梢端真到最低点的时刻, 不是我的常量。
	## ★口径 = 走完全程落差的 TOUCH_FRAC, **不是**绝对最低点 ——
	##   最低点后面还有 0.2 秒的缓慢沉降, 拿它当"落地"会把伤害推得过晚。
	var y_top: float = float(ys[0])
	var y_bot: float = float(ys[ys.size() - 1])
	for yi in range(ys.size()):
		y_bot = minf(y_bot, float(ys[yi]))
	var need: float = y_top - (y_top - y_bot) * TOUCH_FRAC
	var bot_i: int = ys.size() - 1
	for yi in range(ys.size()):
		if float(ys[yi]) <= need:
			bot_i = yi
			break
	var bot_t: float = float(bot_i) * dt
	var dmg_t: float = float(tv.hit_delay(1.0)) - float(tv.T_WARN) - float(tv.T_REAR)
	print("     梢端落地(%.0f%%落差) = SLAM 后 %.3f 秒 · 伤害结算 = SLAM 后 %.3f 秒 · 差 %.3f 秒"
		% [TOUCH_FRAC * 100.0, bot_t, dmg_t, absf(bot_t - dmg_t)])
	_ok("★分母: 梢端真的落下来了(落差 > 1.0)", y_top - y_bot > 1.0,
		"落差只有 %.2f" % (y_top - y_bot))
	_ok("★★★伤害结算 = 梢端真正落地(用户:「肯定是落地伤害」), 差 ≤ %.2fs" % HIT_GAP_MAX,
		absf(bot_t - dmg_t) <= HIT_GAP_MAX, "实测差 %.3f 秒" % absf(bot_t - dmg_t))
	_ok("★T_TOUCH 常量没漂: 它必须等于量出来的落地时刻", absf(float(tv.T_TOUCH) - bot_t) <= HIT_GAP_MAX,
		"常量 %.3f vs 实测 %.3f" % [float(tv.T_TOUCH), bot_t])

	print("     根→梢前沿时差 = %.3f 秒 (T_SLAM=%.2f, 占 %.0f%%)" % [
		spread, float(tv.T_SLAM), spread / float(tv.T_SLAM) * 100.0])
	_ok("★★★根梢时差 ≥ %.2fs =【这是鞭子不是棍子】" % FRONT_SPREAD_MIN,
		spread >= FRONT_SPREAD_MIN, "实测 %.3f 秒" % spread)
	_ok("★分母: 行波前沿没被关掉", float(tv.SLAM_FRONT_SPAN) > 0.0,
		"SLAM_FRONT_SPAN=%.2f" % float(tv.SLAM_FRONT_SPAN))
	_ok("★前沿是【越跑越快】的(鞭子渐细), 不是匀速绳子", float(tv.SLAM_FRONT_P) < 1.0,
		"SLAM_FRONT_P=%.2f" % float(tv.SLAM_FRONT_P))
	_ok("★柔软没被关死: 拍击期横向摆动有地板值 > 0", float(tv.SLAM_WAVY_MIN) > 0.0,
		"SLAM_WAVY_MIN=%.2f" % float(tv.SLAM_WAVY_MIN))
	_done(scn)


func _done(scn) -> void:
	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 触手是鞭子(行波前沿在跑)且梢端不回抬" if _fail == 0 else "FAIL")
	if scn != null:
		scn.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)
