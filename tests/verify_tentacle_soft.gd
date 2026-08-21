extends Node
## verify_tentacle_soft.gd — 触手拍击可以柔软, 但【梢端不许在下砸中途回抬】
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
	print("=== 触手: 柔软但梢端不回抬 ===")

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
	var worst := 0.0
	var rises := 0
	for i in range(400):
		tv.tick(1.0 / 120.0)                       # 半帧步长: 采样够密才看得见回抬
		if tv.state_of("left", 0) != 3:
			if not ys.is_empty():
				break                              # 已经走完 SLAM
			continue
		var y: float = tv.tip_y_of("left", 0)
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
	## 柔软那一半也要有分母 —— 光"不回抬"是把它焊成铁棍也能过
	## ★柔软这一半的分母: **横向摆动**必须开着。逐段滞后(S形)实测会放大梢端回抬
	##   (0.10 → 0.0534 vs 基线 0.0287), 所以定为 0 —— 是量出来的取舍, 不是忘了开。
	_ok("★逐段滞后按实测定为 0(放开会放大回抬)", float(tv.SLAM_LAG_K) == 0.0,
		"SLAM_LAG_K=%.2f" % float(tv.SLAM_LAG_K))
	_ok("★柔软没被关死: 拍击期横向摆动有地板值 > 0", float(tv.SLAM_WAVY_MIN) > 0.0,
		"SLAM_WAVY_MIN=%.2f" % float(tv.SLAM_WAVY_MIN))
	_done(scn)


func _done(scn) -> void:
	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 触手柔软且梢端不回抬" if _fail == 0 else "FAIL")
	if scn != null:
		scn.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)
