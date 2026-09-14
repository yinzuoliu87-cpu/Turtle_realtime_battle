extends Node
## verify_line_band_vfx.gd — 「演出必须盖住判定」那一类 (2026-09-14)
##   ①②③ 三件「文案写明判定半宽」的横向覆盖 · ④ 043 浪墙的**纵向时间轴**对齐
##
## ════════════════════════════════════════════════════════════════════════
##  ★这条门禁守的是什么
## ════════════════════════════════════════════════════════════════════════
## 扫了全部 96 件装备的 effectDesc, 文案里写明「中线两侧各 N 码」的共 **3 件**:
##
##   | 件 | 文案半宽 | 我量到的演出地面横向覆盖 | 比例 |
##   |---|---|---|---|
##   | 029 冰封水母    | 90 码 | 冰刺散布写死 `randf_range(-46, 46)`       | 51%  |
##   | 030 迷你水晶球A | 55 码 | 两条 `bolt_line` 细线 + 碎晶只撒在中线上  | ≈0   |
##   | 051 激光手枪    | 50 码 | `_laser_beam` 是**立起来**的带子          | 恒 0 |
##
## 051 的 0 不是估的, 是几何事实: 那个带子的顶点只在 ±Y 上偏移(`up = Vector3(0, half_w, 0)`),
## 四个角在地面 (X,Z) 上完全重合成一条线。玩家看到一条细线, 实际挨打的是 100 码宽的带子。
##
## ★判据**量真实创建出来的节点的世界坐标**, 不读任何常量 ——
##   读常量就成了恒真式(memory [[fb-verify-check-can-fail]]);
##   而"断言我自己插的标记"更糟(memory [[fb-gate-must-measure-requirement-not-my-hook]])。
##   做法: 记下 `_world` 调用前的孩子数 → 跑真入口 → 只看**新增**的那些节点,
##   Mesh 读顶点数组、Sprite3D 读 position, 换算回码, 取对中线的最大垂距。
##
## ★期望值写死在门禁自己这儿(见 EXP_*), **不从产品常量读**。
##   产品那三个常量改了这里就该红 —— 那正是它存在的意义。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 文案写明的判定半宽(码)。改产品常量而不改文案 ⇒ 这里当场红。
const EXP_ICE_HALF := 90.0        # 029 冰封水母 · IceSystem.FISSURE_HALF_W
const EXP_XTAL_HALF := 55.0       # 030 迷你水晶球A · CrystalSystem.LINE_HALF_W
const EXP_LASER_HALF := 50.0      # 051 激光手枪 · EquipSystem.PISTOL_LASER_BAND

## 演出至少要盖住判定带的多少 —— 留 10% 余量给"最外一圈刚好落在边界上"的取整,
## 但**不许再松**: 松到 0.5 就等于放过了 029 原来那个 51%(那正是要抓的缺陷)。
const COVER_MIN := 0.90

## 高于这个高度(世界单位)的网格不按顶点算横向覆盖 —— 见 `_spread` 里那段注释。
const GROUND_Y := 0.30

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(px: float, py: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, Vector2(px, py))
	u["hp"] = 100000.0
	u["maxHp"] = 100000.0
	u["atk"] = 100.0
	u["alive"] = true
	u["crit"] = 0.0
	u["critDmg"] = 1.0
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["no_basic"] = true
	u["no_move"] = true
	return u


## 世界坐标 → 场地码。`_world_pos(p,h) = ((p.x-cx)*WS, h, (p.y-cy)*WS)` 的逆。
func _to_yards(v: Vector3) -> Vector2:
	var c: Vector2 = _s._arena_center
	return Vector2(v.x / _s.WS + c.x, v.z / _s.WS + c.y)


## 调用效果之前先拍一张"现有孩子"的名册。
## ★不能用"记下孩子数, 之后按下标切片" —— 推游戏钟会让**先前**那些特效 `queue_free`,
##   孩子被摘掉后下标整体前移, 切片就指到别处去了(第一版就是这么写的)。
func _roster() -> Dictionary:
	var d: Dictionary = {}
	for ch in _s._world.get_children():
		d[ch.get_instance_id()] = true
	return d


## 量**名册之外**的新节点对 (org, dir) 这条中线的最大垂距(码)。
## 返回 [量到的节点数(分母), 最大垂距]。
func _spread(before: Dictionary, org: Vector2, dir: Vector2) -> Array:
	var best: float = 0.0
	var cnt: int = 0
	for ch in _s._world.get_children():
		if before.has(ch.get_instance_id()):
			continue
		var pts: Array = []
		if ch is MeshInstance3D:
			var m = ch.mesh
			if m != null and m.get_surface_count() > 0:
				var arr: Array = m.surface_get_arrays(0)
				if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
					var hi: float = -1e9
					for v in arr[Mesh.ARRAY_VERTEX]:
						pts.append(ch.position + v)
						hi = maxf(hi, (ch.position + v).y)
					## ★★**朝相机的方块不算地面横向覆盖**。`bolt_line` 把光束画成一串
					##   朝相机的小方块, 而相机有俯角 ⇒ 它的"上"向量带 Z 分量,
					##   方块四角会斜进地面。实测这让 030 报出 74 码, 而它真实的地面
					##   覆盖是 55 —— **判据宽了 19 码, 足以放过一件真的太窄的装备**
					##   (memory [[fb-judge-must-fit-the-shape]]: 宽一格造假 bug)。
					##   ⇒ 只有**贴地的网格**(全部顶点都在 y<0.3)才按顶点算,
					##     立起来的网格一律折成它的中心点。
					if hi >= GROUND_Y:
						var ctr := Vector3.ZERO
						for v in pts:
							ctr += v
						pts = [ctr / float(maxi(1, pts.size()))]
		elif ch is Sprite3D:
			## ★★position 恰好是 (0,0,0) 的一律跳过 —— 那是**还没被摆过**的新生节点,
			##   不是"摆在世界原点"。030 的水晶叠层碎片就是这样: 它们的位置由
			##   `_tick_follow_vfx` 每帧写, 而那条 tick 挂在 `_process` 上(测试里关着),
			##   于是它们停在原点; 原点换算回码 = `_arena_center`(868, 474),
			##   离中线正好 74 码 —— 我一开始把这 74 当成了 030 的真实覆盖。
			##   (合法的贴地演出都带非零高度, 不会落在精确的 (0,0,0) 上)
			if ch.position == Vector3.ZERO:
				continue
			pts.append(ch.position)
		if pts.is_empty():
			continue
		cnt += 1
		for v in pts:
			var rel: Vector2 = _to_yards(v) - org
			if rel.dot(dir) < -2.0:
				continue                      # 中线**身后**的东西不算(枪口闪那类)
			best = maxf(best, absf(rel.cross(dir)))
	return [cnt, best]


## ★★`_sim_step` **自己会推 `_t`** —— 但战斗一旦判定结束(`_over`)产品就把 `_t` 冻住
##   (CLAUDE.md §3.5 写着这条)。下面 029 那一节只放了携带者、没有敌人 ⇒ 当场判定结束
##   ⇒ `_t` 恒定不动 ⇒ `_equip_tick_sys` 的到期判据(`battle._t >= at`)永远不成立,
##   探针实测推 200 步后 `_t = 0.02`、队列 77 项一项没排空。
## ⇒ 只在**产品没推**的时候由测试补一步。写成无条件 `_t += dt` 的话, 一旦哪天这里
##   加了敌人, 时钟就会**双倍速**走(我第一版就是这样, 另一个探针里量到 s._t 是浪自己
##   那条时间轴的整两倍, 差点当成"浪走得太慢"去改产品)。
func _advance(sec: float) -> void:
	var steps: int = int(sec / _s.SIM_DT) + 1
	for _k in range(steps):
		var t0: float = _s._t
		_s._sim_step(_s.SIM_DT, false, false)
		if absf(_s._t - t0) < 1e-6:
			_s._t += _s.SIM_DT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 演出必须盖住文案写明的判定带: 029 冰封水母 / 030 迷你水晶球A / 051 激光手枪 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false

	_ok("★分母: `_world` 建出来了", _s._world != null,
		"没有 _world 的话下面每一条都在量空气(memory fb-gate-subject-never-constructed)")
	if _s._world == null:
		_finish(); return

	var dir := Vector2(1.0, 0.0)

	# ══════════════ 051 激光手枪: 中线两侧各 50 码 ══════════════
	_s._units.clear()
	_s._pending_shots.clear()
	var c51: Dictionary = _mk(300.0, 400.0, "left")
	_s._units.append(c51)
	_s._units.append(_mk(700.0, 400.0, "right"))
	var i0: Dictionary = _roster()
	_s._equip_sys._eq_laser_pistol(c51, 2)
	var r51: Array = _spread(i0, c51["pos"], dir)
	_ok("① ★分母: 051 开火后 `_world` 新增了 %d 个可量的节点" % int(r51[0]),
		int(r51[0]) > 0, "0 个 = 演出根本没创建, 下面那条会假绿")
	_ok("① ★★★051 演出地面横向覆盖 %.1f 码, 判定半宽 %.0f 码(应 ≥ %.1f)"
		% [float(r51[1]), EXP_LASER_HALF, EXP_LASER_HALF * COVER_MIN],
		float(r51[1]) >= EXP_LASER_HALF * COVER_MIN,
		"文案写「中线两侧各 %.0f 码」—— 画面读不出这个宽度就是缺陷" % EXP_LASER_HALF)

	# ══════════════ 030 迷你水晶球A: 中线两侧各 55 码 ══════════════
	_s._units.clear()
	_s._pending_shots.clear()
	var c30: Dictionary = _mk(300.0, 400.0, "left")
	_s._units.append(c30)
	_s._units.append(_mk(800.0, 400.0, "right"))
	var i1: Dictionary = _roster()
	_s._crystal_sys._crystal_line_seg(c30, 2, dir)
	var r30: Array = _spread(i1, c30["pos"], dir)
	_ok("② ★分母: 030 发射后新增 %d 个可量的节点" % int(r30[0]), int(r30[0]) > 0)
	_ok("② ★★★030 演出地面横向覆盖 %.1f 码, 判定半宽 %.0f 码(应 ≥ %.1f)"
		% [float(r30[1]), EXP_XTAL_HALF, EXP_XTAL_HALF * COVER_MIN],
		float(r30[1]) >= EXP_XTAL_HALF * COVER_MIN,
		"原来两条 bolt_line 都在中线上, 横向宽度 ≈ 0")

	# ══════════════ 029 冰封水母: 中线两侧各 90 码 ══════════════
	## ★冰刺是**错峰**窜起的(沿线距离 ÷ 冰道长 × FISSURE_SWEEP_SEC), 且 2026-09-14 起
	##   挂在 `_equip_tick_sys`(游戏钟)上而不是 tween ⇒ 这里必须**推游戏钟**才等得到。
	##   原来挂 tween 时无头下一根都不会生成, 这条判据当时根本无法成立。
	_s._units.clear()
	_s._pending_shots.clear()
	var c29: Dictionary = _mk(200.0, 400.0, "left")
	_s._units.append(c29)
	var i2: Dictionary = _roster()
	_s._ice_sys._ice_fissure_go(c29, 2, c29["pos"], dir)
	var mid29: Array = _spread(i2, c29["pos"], dir)
	_advance(3.0)
	var r29: Array = _spread(i2, c29["pos"], dir)
	_ok("③ ★分母: 029 推 3 秒游戏钟后新增 %d 个可量的节点(推之前只有 %d 个)"
		% [int(r29[0]), int(mid29[0])],
		int(r29[0]) > int(mid29[0]),
		"数量没涨 = 错峰那批根本没生成(以前挂 tween 时就是这样, 无头永远量不到)")
	_ok("③ ★★★029 演出地面横向覆盖 %.1f 码, 判定半宽 %.0f 码(应 ≥ %.1f)"
		% [float(r29[1]), EXP_ICE_HALF, EXP_ICE_HALF * COVER_MIN],
		float(r29[1]) >= EXP_ICE_HALF * COVER_MIN,
		"原来写死 ±46 码 = 只盖住判定的 51%")

	# ══════════════ 043 海浪护符: 伤害落地那一刻, 人必须在浪体里 ══════════════
	## ★★守的是【演出与判定共用同一条时间轴】。伤害延时是 `windup + fwd/tdist*travel`
	##   (线性), 所以浪的推进也必须线性 —— 我 2026-09-14 给推进加过 smoothstep 起步慢,
	##   探针当场量出: 携带者脚下那个 t=0.87 挨打而浪只推到 330 码(人在 400) ⇒ 差 70 码,
	##   前方 300 码那个差 19 码。**肉眼看不出来, 只有量才知道。**
	## ★判据量的是**真实网格顶点**在行进方向上的覆盖区间, 不读任何常量。
	_s._units.clear()
	_s._pending_shots.clear()
	## ★★上一节(029)只放了携带者、没有敌人 ⇒ `_check_end` 当场把战斗判成结束(`_over`),
	##   而 `_pending_shots` 的排空是被 `_over` 门住的 ⇒ 这一节的伤害一条都不会落,
	##   四个探针全是 0，下面那两条就成了空检查。
	##   (memory [[fb-gate-subject-never-constructed]]: 判据没错, 被测对象不在场)
	_s._over = false
	var cw: Dictionary = _mk(500.0, 470.0, "left")
	_s._units.append(cw)
	var startc: Vector2 = cw["pos"] - dir * _s._equip_sys.WAVE_BACK
	var probes: Array = []
	## ★★把**身后**的位置也纳进来(2026-09-14 用户拍板把起浪点挪到 1200 码之后):
	##   原来站在携带者身后 670 码以外的单位会被一道从未碰到它的浪打到。
	##   −600 / −900 这两个点就是钉住那条修复的。
	for fw in [-900.0, -600.0, 0.0, 300.0, 700.0, 1100.0]:
		var e: Dictionary = _mk(maxf(90.0, 500.0 + fw), 470.0, "right")
		_s._units.append(e)
		probes.append({"u": e, "fwd": fw, "hp0": float(e["hp"]), "t": -1.0, "ok": false, "gap": 0.0})
	## ★★只认**这一次**新建出来的网格。第一版是"顶点数 ≥500 的网格全算", 结果把
	##   ②那一节留下的 `bolt_line` 也算了进来(它的点串顶点数也超 500, 而且 tween 在
	##   无头下不推进 ⇒ 一直没被释放) ⇒ 浪的"前缘"被撑到 1704 码, 判据宽了一千多码,
	##   条条都过但过得莫名其妙(实测越界读数 -1304 而真值该在 -80 上下)。
	##   这已是本轮第三次"判据比要量的形状宽"(前两次: 朝相机的方块 / 停在原点的碎片)。
	var wroster: Dictionary = _roster()
	_s._equip_sys._eq_water_wave(cw, 2)
	var tt: float = 0.0
	for _k in range(180):
		var t0w: float = _s._t
		_s._sim_step(_s.SIM_DT, false, false)
		if absf(_s._t - t0w) < 1e-6:
			_s._t += _s.SIM_DT
		tt += _s.SIM_DT
		for pr in probes:
			if float(pr["t"]) >= 0.0:
				continue
			if float(pr["u"]["hp"]) >= float(pr["hp0"]) - 0.5:
				continue
			pr["t"] = tt
			var span: Array = _wave_span(wroster, startc, dir)
			var mf: float = ((pr["u"]["pos"] as Vector2) - startc).dot(dir)
			pr["ok"] = bool(span[0]) and mf >= float(span[1]) and mf <= float(span[2])
			pr["gap"] = mf - float(span[2])
	var hit_n: int = 0
	for pr in probes:
		if float(pr["t"]) >= 0.0:
			hit_n += 1
	_ok("④ ★分母: 043 的六个探针单位全都被结算到了(%d/6)" % hit_n, hit_n == 6,
		"没被打到的话下面那条就是空检查")
	for pr in probes:
		_ok("④ ★★★纵深 %+.0f 码那个: t=%.2f 挨打时人在浪体内(越界 %+.0f 码)"
			% [float(pr["fwd"]), float(pr["t"]), float(pr["gap"])],
			bool(pr["ok"]),
			"伤害延时是线性的 ⇒ 浪的推进也必须线性, 加缓动就会「伤害先落、浪后到」")

	_finish()


## 浪的网格在 dir 方向上的覆盖区间(码)。返回 [找到没有, 最后缘, 最前缘]。
## ★只认顶点数 ≥500 的那张网格 —— 那是浪; 别的小网格(光束/点串)不是。
func _wave_span(before: Dictionary, org: Vector2, dir: Vector2) -> Array:
	var lo := 1e9
	var hi := -1e9
	var found := false
	for ch in _s._world.get_children():
		if before.has(ch.get_instance_id()):
			continue
		if not (ch is MeshInstance3D):
			continue
		var m = ch.mesh
		if m == null or m.get_surface_count() == 0:
			continue
		var arr: Array = m.surface_get_arrays(0)
		if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		var vs = arr[Mesh.ARRAY_VERTEX]
		if vs.size() < 500:
			continue
		found = true
		for v in vs:
			var f: float = (_to_yards(ch.position + v) - org).dot(dir)
			lo = minf(lo, f)
			hi = maxf(hi, f)
	return [found, lo, hi]


func _finish() -> void:
	print("---- %d 条, 失败 %d ----" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS — 直线判定带演出覆盖")
	else:
		print("有 %d 条 FAIL" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
