class_name CamFit
extends RefCounted
## 画幅取景(2026-11-16): 镜头只保证【竖直】方向看全(Camera3D KEEP_HEIGHT), 画面比手机窄的时候
## 场地两头的蛋会钻到两侧头像栏底下 —— 16:9 压住半个罩子, iPad 4:3 两个蛋整个出画(51° 时就这样, 改 40° 前实拍过)。
## ⇒ 按【真实画幅 + 真实头像栏位置 + 真实蛋的位置】算镜头沿视轴退多远, 让两个蛋连罩子都落在两栏之间。
##   · 只退不进: 手机宽屏(1560×720)本来就放得下 ⇒ k = 1, 画面一个像素不变。
##   · 方向不变(俯角仍是 BattleCam.PITCH_DEG), 只改距离 ⇒ 看上去和手机一样, 只是整体小一点。
##   · 改的是镜头基准 `_cam_base`; 玩家的缩放 / 平移照旧叠在它上面(`_apply_cam_zoom`)。
##   · 纯演出, 不进 sim(裁判机没相机直接返回; verify_rules_fingerprint 守)。
## 门禁: tests/verify_cam_fit.gd(真对局 × 三种画幅量蛋罩外沿 vs 头像栏内沿)。

## 蛋罩半径(米)。实测手机 40° 画面: 罩子左沿离蛋心 88 px ÷ 28.15 px/米 ≈ 3.1 米, 取 3.2。
const EGG_R := 3.2
## 罩子外沿离头像栏内沿至少留这么多(画面像素)
const MARGIN_PX := 12.0
## 头像栏还没建出来 / 没量到尺寸时按这个宽度算(画面像素; 实测两栏外沿 10 + 框宽 158)
const PANEL_FALLBACK_W := 170.0
## 双路开局蛋离战场左右边的距离(码) —— 与 dual_lane_flow 摆蛋那两行同一个数; 场上没有蛋(调试场)时拿它推
const EGG_INSET := 70.0
## 最多退到原距离的这么多倍(再远蛋就太小; 4:3 实算约 1.7)
const K_MAX := 2.2


## 镜头要退的倍数(≥ 1)。pts = 要放进两栏之间的世界点; left_edge / right_edge = 两栏内沿的画面 x(像素);
## vp = 画面尺寸; fov_deg = 竖直视场角。
## 推导: 机位 = TARGET − FORWARD·DIST·k(只沿视轴推拉, 横向不动) ⇒ 点 p 的深度 = (p−TARGET)·FORWARD + DIST·k,
##   横向偏移 x = (p−TARGET)·右向(与 k 无关); 画面上离中线 x·f/深度 ≤ safe ⇒ k ≥ (|x|·f/safe − (p−TARGET)·FORWARD) / DIST。
static func scale_for(pts: Array, vp: Vector2, left_edge: float, right_edge: float, fov_deg: float) -> float:
	if vp.x < 2.0 or vp.y < 2.0:
		return 1.0
	var hf: float = deg_to_rad(fov_deg) * 0.5
	var f: float = (vp.y * 0.5) * DetMath.dcos(hf) / DetMath.dsin(hf)   ## = (vp.y/2) / tan(半视场角); 走 DetMath(det_math_lint)
	var cx: float = vp.x * 0.5
	var k := 1.0
	for p in pts:
		var rel: Vector3 = (p as Vector3) - BattleCam.TARGET
		var x: float = rel.x                                  # 镜头不偏航 ⇒ 右向 = 世界 +x
		var along: float = rel.dot(BattleCam.FORWARD)
		var safe: float = (right_edge - MARGIN_PX - cx) if x > 0.0 else (cx - left_edge - MARGIN_PX)
		if safe < 1.0:
			return K_MAX
		k = maxf(k, (absf(x) * f / safe - along) / BattleCam.DIST)
	return minf(k, K_MAX)


## 两个蛋罩的左右外沿(世界点)。场上有蛋就用真蛋的位置; 没有(调试场)就按双路摆蛋的规则从战场边界推。
static func egg_points(b) -> Array:
	var out: Array = []
	for u in b._units:
		if u is Dictionary and bool(u.get("_isEgg", false)):
			var w: Vector3 = b._world_pos(u.get("pos", Vector2.ZERO), 0.0)
			out.append(w + Vector3(EGG_R, 0.0, 0.0))
			out.append(w - Vector3(EGG_R, 0.0, 0.0))
	if out.is_empty():
		var ar: Rect2 = b.ARENA
		var cy: float = ar.position.y + ar.size.y * 0.5
		for px in [ar.position.x + EGG_INSET, ar.end.x - EGG_INSET]:
			var w2: Vector3 = b._world_pos(Vector2(px, cy), 0.0)
			out.append(w2 + Vector3(EGG_R, 0.0, 0.0))
			out.append(w2 - Vector3(EGG_R, 0.0, 0.0))
	return out


## 两栏内沿的画面 x。栏没建 / 还没排版(尺寸 0)就用 PANEL_FALLBACK_W。
static func panel_edges(b, vp: Vector2) -> Vector2:
	var le: float = PANEL_FALLBACK_W
	var re: float = vp.x - PANEL_FALLBACK_W
	var pl = b.get("_team_panel_left")
	var pr = b.get("_team_panel_right")
	if is_instance_valid(pl) and pl is Control and (pl as Control).is_inside_tree() and (pl as Control).size.x > 1.0:
		le = (pl as Control).get_global_rect().end.x
	if is_instance_valid(pr) and pr is Control and (pr as Control).is_inside_tree() and (pr as Control).size.x > 1.0:
		re = (pr as Control).get_global_rect().position.x
	return Vector2(le, re)


## 当前画幅要退的倍数。
static func fit_k(b) -> float:
	if b == null or not is_instance_valid(b) or b._cam == null or not is_instance_valid(b._cam):
		return 1.0
	var vp: Vector2 = (b._cam as Camera3D).get_viewport().get_visible_rect().size
	var e: Vector2 = panel_edges(b, vp)
	return scale_for(egg_points(b), vp, e.x, e.y, (b._cam as Camera3D).fov)


## 按当前画幅重设镜头基准(玩家的缩放 / 平移不动)。头像栏刚建出来那一帧还没排版 ⇒ 下一帧再量一次。
static func apply(b) -> void:
	if b == null or not is_instance_valid(b) or b._cam == null or not is_instance_valid(b._cam):
		return
	var k: float = fit_k(b)
	b._cam_base = BattleCam.TARGET + (BattleCam.POS - BattleCam.TARGET) * k
	b.set_meta("cam_fit_k", k)
	b._apply_cam_zoom()


## 头像栏建好后调: 本帧先按兜底宽度摆一次(不闪), 下一帧栏排好版再按真实内沿量一次; 之后画面尺寸变了也重算。
## ★「下一帧」与「尺寸变了」都交给挂在对局节点下的 Watch 子节点 —— 信号连在它自己的方法上, 对局释放时随它一起断开。
##   (第一版把静态函数 bind 了对局再连到根视口的 size_changed: 网页播放器里同一帧建两次头像栏 ⇒
##    「Signal 'size_changed' is already connected」, verify_web_player 抓到。)
static func apply_now_and_next_frame(b) -> void:
	apply(b)
	if b == null or not is_instance_valid(b):
		return
	var w = b.get_meta("cam_fit_watch", null)
	if not is_instance_valid(w):
		w = Watch.new()
		w.name = "CamFitWatch"
		w.b = b
		b.set_meta("cam_fit_watch", w)
		b.add_child.call_deferred(w)
	(w as Watch).pending = true


class Watch extends Node:
	var b = null
	var pending := false

	func _ready() -> void:
		get_viewport().size_changed.connect(_on_size_changed)

	func _on_size_changed() -> void:
		pending = true

	func _process(_d: float) -> void:
		if not pending:
			return
		pending = false
		if is_instance_valid(b):
			CamFit.apply(b)
