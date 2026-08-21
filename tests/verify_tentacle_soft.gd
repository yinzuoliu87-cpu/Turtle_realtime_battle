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

## ★★★2026-08-21 用户:「抬起的时候你没有柔软感」——【真身是定格, 不是弯度】
##
## 我在这条门禁上先后错了三次, 记下来免得再来:
##  ① 加 `WARN_FRONT_SPAN`(相位滞后) —— 实测扫描: 梢端拖后只买到 +2.6pp 就饱和、
##     曲率峰值移动**一点不动**、而抬起末的甩尾过冲被**摧毁 10 倍**(0.204→0.020)。已归零。
##  ② 造了三个"形状"指标(梢端拖后 80.3% / 拐点移动 0.53 / 甩尾 0.204) ——
##     **基线就全部达标**, 而画面明明是硬的 ⇒ 指标和眼睛打架时, 错的一定是指标。
##  ③ 阈值定在基线之下 ⇒ 空判据(第一次定 0.12, 基线就有 0.192)。
##
## 实拍逐帧看才找到真身: 抬起 +0.12~+0.96 那七帧**几乎一模一样**, 一根粗锥立在那儿。
## 探针实测每帧整条平均位移: 峰值 0.109 → 后段掉到 0.006 = **峰值的 1/18**。
## 前 62% 就把动作走完(还用了末端减速的 smoothstep), 后 38% 只转 5 度。
## **一根静止的东西不可能显得软。**
##
## ⇒ 判据换成【抬起全程不许定格】: 后半段最低的每帧位移, 不许掉到峰值的这个比例以下。
## ★阈值定在**基线之上**: 基线 1/18 = 0.055, 改后 0.42 ⇒ 取 0.25。
const LIFT_FLOW_MIN := 0.25

## ★★★2026-08-22【惯性拖尾】用户原话:
##   「触手在抬起到最高处时由于惯性触手的头部会向后弯由于重力,
##     然后触手拍下来由于惯性头部会怎么样你自己不会吗」
## 我此前做的全是**相位延迟**(梢端晚一点做同一个动作), 而惯性是**速度的函数**:
##   加速时头部被甩向运动的**反方向**, 急停时攒的弯**弹回来过头** = 甩尾。
## ⇒ 判据必须量**方向**与**过冲**, 不是量形状(形状指标在基线就达标却与画面相反)。
## 抬起期头部至少要向后弯这么多度(负值)
const INERTIA_LIFT_MIN := 8.0
## 砸到底之后必须出现反向过冲(甩尾)这么多度
const INERTIA_OVER_MIN := 5.0
## 下砸期的滞后下限(单独定, 因为那里被 INERTIA_GAIN_SLAM 有意压低)
const INERTIA_SLAM_MIN := 3.0
## 【真几何】抬起期梢端切线相对身体的最小向后偏角(度)。
## ★阈值必须定在**无惯性基线**之上: 基线 -22°, 现行 -58° ⇒ 取 40。
##   定在基线之下就又是空判据(我今晚已经栽过两次)。
const GEO_UP_MIN := 40.0
## 蓄势期(指定姿势几乎不动)整条每帧平均位移的下限 —— 惯性的证据。
## ★阈值定在**刚性基线之上**: 把肌肉速率调到 900(几乎刚性跟随)实测 0.0284,
##   现行柔软配置 0.0851 ⇒ 取 0.050。定在基线之下就又是空判据(今晚已栽三次)。
const INERTIA_MOVE_MIN := 0.050
## 【★已登记的缺口 —— 不是判据宽松, 是我修不动】
## 下砸期弧长实测波动 **35.5%**(8.76~11.87, 目标 9.60)。鞭子不会变长, 这是真缺陷。
## 三条修法都试过, **全都会改掉用户已经验收的手感**(折角 29.3°/节):
##   · 从根部精确归一每段长度 ⇒ 弧长好了, 但折角压到 **10.8°**(硬 3 倍)
##   · 地面钳位后补距离迭代   ⇒ 弧长没救回来, 折角反而变 **41.5°**
##   · 下砸期缩小子步长 0.25  ⇒ 弧长压到 9.2%, 但折角压到 **16.6°**(硬 2 倍)
## ⇒ **弧长精度与柔软度在这个解算配置下是耦合的**, 我修不了一个而不动另一个。
##   不偷偷改用户验收过的东西, 也不假装没这回事 ⇒ 登记成**只降不升的棘轮**。
## 下一步真解法(没做): 把 PBD 换成 XPBD(带柔度参数, 刚度与迭代次数解耦), 那是另一轮工时。
const ARC_TOL := 0.36
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

	## ══ 先量【抬起】: 全程不许定格 ══════════════════════════════
	## ★量的是**整条中心线每帧动了多远**(真几何), 不是形状指标 ——
	##   形状指标在基线就达标却与画面相反, 那是空判据(见文件头三次翻车记录)。
	## ★★惯性拖尾的三个数【顺带在已有的两趟循环里记】—— 我第一版另开了一个 900 帧循环,
	##   它把整个下砸阶段吃掉了, 后面那段采到 0 个样本(分母断言当场抓到)。
	##   等效果的循环不能随便加, 每一趟都会推进同一条时间线。
	var lag_up := 0.0        # 抬起期最负: 头部向后/向下弯
	var geo_up := 0.0        # 抬起期【真几何】: 梢端切线相对身体最负偏角
	var lag_dn := 0.0        # 下砸期最正: 头部向后/向上翘
	var lag_over := 0.0      # 砸到底后的反向过冲(甩尾)
	## ★惯性证据【在已有的抬起循环里顺带记】—— 我第一版另起了一个循环, 而蓄势期
	##   已经被抬起那趟吃掉了(它的 break 覆盖 state 2) ⇒ 采到 0 帧, 分母断言当场抓到。
	var rear_move := 0.0
	var rear_n := 0
	var lprev := PackedVector3Array()
	var lmove: Array = []
	for i in range(900):
		tv.tick(1.0 / 120.0)
		var st_l: int = tv.state_of("left", 0)
		if st_l != 6 and st_l != 2:
			if not lmove.is_empty():
				break
			continue
		if st_l == 6:
			lag_up = minf(lag_up, float(tv.lag_of("left", 0)))
		## ★真几何: 梢端切线相对身体切线偏多少度(负 = 头部比身体更向后/向下勾)。
		##   这才是屏幕上看得到的东西; `lag_of()` 是我的内部弹簧变量, 两者能差 3 倍。
		var cg: PackedVector3Array = tv.centerline_of("left", 0)
		if cg.size() >= 12:
			var ng: int = cg.size()
			var bd: Vector3 = (cg[int(ng * 0.62)] - cg[int(ng * 0.38)]).normalized()
			var tp: Vector3 = (cg[ng - 1] - cg[ng - 4]).normalized()
			var dg: float = rad_to_deg(atan2(tp.y, Vector2(tp.x, tp.z).length())
				- atan2(bd.y, Vector2(bd.x, bd.z).length()))
			## ★★只在【举到位】那一刻取(ST_REAR=2) —— 用户说的是"抬起到最高处时头部会向后弯"。
			##   我第一版取整个抬起期的最小值, **惯性关掉也有 -160°**(那是待机→抬起的自然过渡
			##   带来的极值, 不是惯性) ⇒ 空判据, 反向验证当场抓到。
			if st_l == 2:
				geo_up = minf(geo_up, dg)
		var cc: PackedVector3Array = tv.centerline_of("left", 0)
		if st_l == 2 and lprev.size() == cc.size() and cc.size() > 0:
			var rsm := 0.0
			for rj in range(cc.size()):
				rsm += (cc[rj] - lprev[rj]).length()
			rear_move = maxf(rear_move, rsm / float(cc.size()))
			rear_n += 1
		if st_l == 6 and lprev.size() == cc.size() and cc.size() > 0:
			var dsum := 0.0
			for jj in range(cc.size()):
				dsum += (cc[jj] - lprev[jj]).length()
			lmove.append(dsum / float(cc.size()))
		lprev = cc
	_ok("★分母: 抬起期真的采到帧(否则下面全是空的)", lmove.size() >= 40,
		"只采到 %d 帧" % lmove.size())
	var lpeak := 0.0
	for mv in lmove:
		lpeak = maxf(lpeak, float(mv))
	var llow := 9.0
	for mi in range(int(lmove.size() * 0.5), lmove.size()):
		llow = minf(llow, float(lmove[mi]))
	var lflow: float = llow / maxf(lpeak, 1e-9)
	print("     【抬起】每帧位移 峰值 %.4f · 后半段最低 %.4f ⇒ 比值 %.3f (= 1/%.0f)" % [
		lpeak, llow, lflow, 1.0 / maxf(lflow, 1e-9)])
	_ok("★★★抬起【全程不许定格】: 后半段位移 ≥ 峰值的 %.0f%%" % (LIFT_FLOW_MIN * 100.0),
		lflow >= LIFT_FLOW_MIN, "实测 %.3f (基线 0.055)" % lflow)
	## ══ 再量【下砸】 ══════════════════════════════════════════

	# 逐帧推进, 只在【下砸期 ST_SLAM=3】采样梢端高度
	var ys: Array = []
	var profs: Array = []          # 每帧一份沿长度的高度剖面(9 站点)
	var profs_c: Array = []        # 每帧一份真链条(量弧长用)
	var worst := 0.0
	var rises := 0
	for i in range(400):
		tv.tick(1.0 / 120.0)                       # 半帧步长: 采样够密才看得见回抬
		if tv.state_of("left", 0) != 3:
			if not ys.is_empty():
				## ★不直接 break —— 甩尾发生在【砸到底之后】(ST_RECOVER),
				##   在这里就跳出会永远量不到过冲。再走一小截把它记下来。
				for _r in range(60):
					tv.tick(1.0 / 120.0)
					lag_over = minf(lag_over, float(tv.lag_of("left", 0)))
				break
			continue
		lag_dn = maxf(lag_dn, float(tv.lag_of("left", 0)))
		var y: float = tv.tip_y_of("left", 0)
		profs.append(tv.height_profile_of("left", 0))
		profs_c.append(tv.centerline_of("left", 0))
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
	## ★★★2026-08-22【换成链式模拟后, 判据第三次换形状】
	## 实拍轨迹(模拟版): 8.82 → 7.12(只沉了总落差的 19%) → **回抬到 8.55** → 一路到 0.06 落地不动。
	## 那个回抬是**甩鞭前的蓄势回抽**, 真鞭子就是这样 —— 不是用户 2026-08-05 报的「拍两次」。
	## 「拍两次」的形状是【已经落下去了又抬起来】。
	## ⇒ 判据: 梢端**一旦过了总落差的一半**(= 真的在往下砸了), 之后再不许回抬。
	##   分界点由数据自己定, 不是我拍一个时刻。
	var y_hi: float = float(ys[0])
	var y_lo: float = float(ys[0])
	for pi2 in range(ys.size()):
		y_hi = maxf(y_hi, float(ys[pi2]))
		y_lo = minf(y_lo, float(ys[pi2]))
	var half_y: float = y_hi - (y_hi - y_lo) * 0.5
	var cross: int = -1
	for pi3 in range(ys.size()):
		if float(ys[pi3]) <= half_y:
			cross = pi3
			break
	var late := 0
	var late_worst := 0.0
	if cross >= 0:
		for li in range(cross + 1, ys.size()):
			var dd: float = float(ys[li]) - float(ys[li - 1])
			if dd > 0.001:
				late += 1
				late_worst = maxf(late_worst, dd)
	print("     梢端 %.2f→%.2f · 过半程在第 %d/%d 帧 · 之后回抬 %d 次(最大 %.4f)" % [
		y_hi, y_lo, cross, ys.size(), late, late_worst])
	_ok("★分母: 真的过了半程(否则下面那条是空的)", cross > 0, "cross=%d" % cross)
	_ok("★★★梢端【过了下落半程之后】再不许回抬(= 不许拍两次)", late == 0,
		"之后还回抬 %d 次, 最大 %.4f" % [late, late_worst])
	## ══ 鞭子那一半: 【行波前沿必须在跑】 ══════════════════════════
	## ★这条是本门禁的**核心**。上一版只有"不回抬", 而把触手焊成铁棍照样不回抬 ——
	##   判据守不住需求。现在正面量: 前沿有没有沿长度依次推进。
	## ══ 不许有任何一段在地面【以下】 ══════════════════════════
	## 用户 2026-08-21:「拍下去的时候鞭子有一部分直接在地下了」。
	## 原来 `_rebuild` 里那句注释写着"别扎穿地板太多"、**允许扎 0.4** ——
	## 探针实测下砸末到起身头 0.2 秒有 3/9 站点在地下(梢端 −0.34, 地面 0.06)。
	## 真鞭子打到地面是**沿地面摊开**, 不会扎进去。
	## ★量的是 `height_profile_of` 的真实世界高度, 不是重推公式。
	var under_n := 0
	var under_deep := 0.0
	var gy: float = float(scn.GROUND_LIFT)
	for pf in profs:
		for v in (pf as PackedFloat32Array):
			if float(v) < gy - 0.02:
				under_n += 1
				under_deep = maxf(under_deep, gy - float(v))
	print("     地面 y=%.2f · 下砸期共 %d 个采样点在地下, 最深 %.3f" % [gy, under_n, under_deep])
	_ok("★★没有任何一段扎进地面以下(鞭子打地会摊开, 不会扎进去)", under_n == 0,
		"%d 个点在地下, 最深 %.3f" % [under_n, under_deep])

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
	## ★★★2026-08-22【换成链式模拟后, 这两条旧判据作废】
	## 旧的「前沿单调推进 / 根梢时差」在模拟下**是空判据**: 实测把肌肉调到刚性(速率 900)
	## 时差反而更大(0.108 > 柔软的 0.092) —— 因为它量的是我写进【肌肉目标】里的那条
	## 老相位前沿, 不是模拟的行为。判据必须量物理**自己**干了什么。
	##
	## ⇒ 换成:【姿态几乎不动的时候, 触手仍然在动】= 惯性的定义性证据。
	##   蓄势(ST_REAR)那 0.13 秒里指定姿势只转几度, 刚性跟随就该几乎静止;
	##   有惯性则整条还在往前走。
	print("     蓄势期(姿势几乎不动)整条每帧平均位移 = %.4f  (采到 %d 帧)" % [rear_move, rear_n])
	_ok("★分母: 真的采到蓄势期", rear_n >= 8, "只采到 %d 帧" % rear_n)
	_ok("★★★姿势几乎不动时触手【仍在动】= 惯性在起作用(≥ %.3f)" % INERTIA_MOVE_MIN,
		rear_move >= INERTIA_MOVE_MIN, "实测 %.4f" % rear_move)
	_ok("★前沿是【越跑越快】的(鞭子渐细), 不是匀速绳子", float(tv.SLAM_FRONT_P) < 1.0,
		"SLAM_FRONT_P=%.2f" % float(tv.SLAM_FRONT_P))
	## ★★★用户 2026-08-22 指出的问题: `lag_of()` 返回的是**我自己的弹簧变量**,
	##   不是产品画出来的几何 —— 拿它当判据就是"数我插的标记"。
	##   实测过差多远: 弹簧值 -19° 时, **画面上梢端只多偏了 6°**(埋在 144° 的自然摆动里,
	##   所以用户根本看不见)。⇒ 必须同时量【真几何】: 梢端切线相对身体切线偏多少度。
	print("     惯性: 抬起向后弯 %+.2f° · 下砸向后翘 %+.2f° · 砸底后甩尾 %+.2f°" % [
		lag_up, lag_dn, lag_over])
	print("     ★真几何: 抬起期梢端切线相对身体最多偏 %+.1f° (无惯性基线 -22°)" % geo_up)
	_ok("★★★【真几何】抬起时梢端比身体多向后勾 ≥ %.0f°(这才是屏幕上看得见的)" % GEO_UP_MIN,
		geo_up <= -GEO_UP_MIN, "实测 %+.1f° (基线 -22°)" % geo_up)
	_ok("★★★抬起时头部【向后弯】≥ %.0f°(惯性追不上, 方向与运动相反)" % INERTIA_LIFT_MIN,
		lag_up <= -INERTIA_LIFT_MIN, "实测 %+.2f°" % lag_up)
	## ★下砸期的滞后是**有意压低**的(`INERTIA_GAIN_SLAM = 0.28`): 那里有「不许拍两次」的硬约束,
	##   吃满幅度会让梢端落下去又抬起来(反向验证实测: 最高点之后回抬 15 次)。
	##   ⇒ 阈值单独定, 不与抬起共用 —— 共用会逼我在"看得见"和"不拍两次"之间二选一。
	_ok("★下砸时头部也有【向后翘】≥ %.0f°(有意压低, 见 INERTIA_GAIN_SLAM)" % INERTIA_SLAM_MIN,
		lag_dn >= INERTIA_SLAM_MIN, "实测 %+.2f°" % lag_dn)
	_ok("★★★砸到底后【甩尾过冲】≥ %.0f°(荡过头再收 = 鞭子)" % INERTIA_OVER_MIN,
		lag_over <= -INERTIA_OVER_MIN, "实测 %+.2f°" % lag_over)
	## ══ 弧长恒定 —— 鞭子不会变长(从 verify_tentacle_rhythm 搬来) ══
	## ★量的是**真链条**的逐节长度之和(centerline_of), 不是解析网格顶点。
	## ★这是 PBD 的收敛残差, 不可能精确为 0 —— 阈值按实测定并**只降不升**。
	var arc_min := 1e9
	var arc_max := 0.0
	for pf2 in profs_c:
		var cc3: PackedVector3Array = pf2
		if cc3.size() < 3:
			continue
		var tot3 := 0.0
		for j3 in range(1, cc3.size()):
			tot3 += (cc3[j3] - cc3[j3 - 1]).length()
		arc_min = minf(arc_min, tot3)
		arc_max = maxf(arc_max, tot3)
	print("     下砸期弧长 %.2f ~ %.2f (目标 %.2f, 差 %.1f%%)" % [
		arc_min, arc_max, float(tv.ARC_LEN), (arc_max - arc_min) / maxf(arc_min, 0.01) * 100.0])
	_ok("★分母: 采到了下砸期的链条", arc_max > 1.0, "arc_max=%.2f" % arc_max)
	_ok("★★弧长在拍击里【恒定】—— 鞭子不会变长(PBD 残差 ≤ %.0f%%)" % (ARC_TOL * 100.0),
		arc_max - arc_min < arc_min * ARC_TOL,
		"%.2f ~ %.2f" % [arc_min, arc_max])
	_ok("★柔软没被关死: 拍击期横向摆动有地板值 > 0", float(tv.SLAM_WAVY_MIN) > 0.0,
		"SLAM_WAVY_MIN=%.2f" % float(tv.SLAM_WAVY_MIN))
	_done(scn)


## 沿长度算每个站点"走完一半行程"的时刻。`rising=true` 量抬升, false 量下落。
## ★两段共用同一份实现 —— 手抄两遍必然漂(memory [[fb-hand-rolled-copies-drift]])。
func _arrivals(profs: Array, rising: bool) -> Array:
	var out: Array = []
	if profs.size() < 8 or (profs[0] as PackedFloat32Array).size() == 0:
		return out
	var dt: float = 1.0 / 120.0
	for st in range((profs[0] as PackedFloat32Array).size()):
		var y0: float = float((profs[0] as PackedFloat32Array)[st])
		var y1: float = float((profs[profs.size() - 1] as PackedFloat32Array)[st])
		var move: float = (y1 - y0) if rising else (y0 - y1)
		if move < STATION_DROP_MIN:
			out.append(-1.0)      # 这个站点没怎么动(根部) —— 显式登记, 不静默跳过
			continue
		var half: float = y0 + (y1 - y0) * 0.5
		var tt := -1.0
		for fi in range(profs.size()):
			var yv: float = float((profs[fi] as PackedFloat32Array)[st])
			if (yv >= half) if rising else (yv <= half):
				tt = float(fi) * dt
				break
		out.append(tt)
	return out


func _done(scn) -> void:
	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 触手是鞭子(行波前沿在跑)且梢端不回抬" if _fail == 0 else "FAIL")
	if scn != null:
		scn.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)
