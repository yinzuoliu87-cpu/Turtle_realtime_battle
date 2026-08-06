class_name BladeEqVfx
extends RefCounted
## blade_eq_vfx.gd — 盾+剑四件新装备(081/082/083/084)的演出层
## (规格 docs/plans/20260805-装备逐件重做.md §0.5 · 实装契约 docs/plans/20260806-实装契约-批④.md §7)
##
## ══════════════════════════════════════════════════════════════════════
##  ★判据: 可验证的几何/物理性质, 不是"我调得像"
## ══════════════════════════════════════════════════════════════════════
## ⚠ **诚实记录**: 这四件**一张视觉参考图都没有** ⇒ 触手立的那条第一判据
##   (「逐帧量参考做成包络表」, memory [[fb-match-reference-by-measured-curve]])在这里**无从下手**。
##   下面这些是它的**替代品, 不是等价物** —— 每条演出落在一个有闭式解的模型上, 门禁验模型的**性质**。
##
## ── ① 081 举盾: 临界阻尼开合(ζ=1) ────────────────────────────────
##   盾牌张开用 x̂(t) = 1 − (1+ωt)e^(−ωt)。ζ=1 是"不过冲的前提下收敛最快",
##   正是"举盾"该有的手感 —— 抬起来就稳住, 不晃。
##   ★可验证性质(门禁): x̂(0)=0 · 严格单调增 · **恒 < 1(永不过冲)** · x̂(1/ω)=1−2/e=0.2642411。
##   欠阻尼(ζ<1)会 >1, 一测就分开。
##
## ── ② 082 反伤束: 亮度按距离平方反比 ─────────────────────────────
##   反伤是"从护心甲弹回攻击者"的一束能量。束的亮度用点光源的**平方反比律**
##   I(d) = I₀ / (1 + (d/d₀)²) —— 近处刺眼、远处只剩一条细线。
##   ★可验证性质(门禁): **I(d₀)/I(0) ≡ 0.5** 与 d₀ 无关(纯尺度律);
##     线性衰减会给 0.5 以外的数, 指数衰减给 1/e=0.368。
##
## ── ③ 083 层数辉光: 对数刻度 ─────────────────────────────────────
##   20 层要在同一条视觉尺子上分得开, 线性刻度会让 1→2 层几乎看不出、19→20 层挤成一坨。
##   用 log(1+s)/log(1+20) 归一 ⇒ 低层区间被拉开。
##   ★可验证性质(门禁): g(0)=0 · g(20)=1 · **g(4) > 4/20**(前段被拉开, 线性时恰等于 0.2)。
##
## ── ④ 084 剑波: 匀速直线, 与结算侧【同一个速度常数】 ──────────────
##   波的演出位置 = 出发点 + 方向 × SPD × t, 与 `EqBladeBatch._step_waves` 里推进伤害判定用的
##   **是同一个 `WAVE_SPD`** —— 门禁有一条焊死它俩相等。
##   演出跟结算用两个数是本项目翻过的车(演出到了、伤害还没到 / 反过来)。
##   十字斩两段扇形的半角同理: `slash_half_rad(seg)` 与结算侧的判据焊死。
##
## ══════════════════════════════════════════════════════════════════════
##  ★零素材(用户铁律「新内容一律新素材, 只有背包/商店装备图标可复用」)
## ══════════════════════════════════════════════════════════════════════
## 本层所有贴图都是 `VfxTex` 逐像素**现算**的 —— 程序化生成【不产出可复用的图】,
## 与 vfx_textures.gd 已确立的立场一致。门禁断言这些贴图的 `resource_path` 是空串
## (= 不是从磁盘 load 来的资源)。**没有从 assets/ 拿任何一张现成图来顶替**。
##
## ★贴地类【只设 axis, 不加 rotation】(memory [[fb-axis-y-plus-rotation-cancels]]):
##   Sprite3D.axis = AXIS_Y 本身就是平铺, 再叠 rotation.x = −90 会把它掰成竖环。
##
## ★**每帧自己推进, 不用 tween**(CLAUDE.md §3.5): 无头 CI 下 `create_tween()` 推进不稳,
##   而且走 sim 的 delta 才跟顿帧/时停/换路同步。所有短命特效进 `_fx`, 由 `tick(delta)` 推。
##
## ★每个入口都能被**单独调用**(供门禁与将来的 VFXPREVIEW), 且第一行都过 `_has_world()` ——
##   "只建单位不建世界"的数值测试里直接 `_world.add_child` 是 SCRIPT ERROR 不是 FAIL。

## ① 081 举盾开合的角频率(rad/s)。ζ=1 临界阻尼。
const GUARD_OMEGA := 11.0
## 举盾盾面的最终直径(码)
const GUARD_R_PX := 78.0
## 举盾贴地环半径(码)
const GUARD_RING_PX := 62.0

## ② 082 反伤束的半亮距离 d₀(码)。I(d₀) = I₀/2。
const REFLECT_D0 := 220.0
## 反伤束宽(码)
const REFLECT_W := 14.0

## ③ 083 层数辉光: 20 层归一。ln(1+20) = 3.0445224377234230(字面量 —— GDScript 的 const
##   表达式不接受内建函数调用, 同 BowEqVfx.GOLDEN_ANGLE 那条注释)。
const STACK_CAP := 20.0
const STACK_LN21 := 3.044522437723423

## ④ 084 剑波演出速度(码/秒)。★与 `EqBladeBatch.WAVE_SPD` 焊死相等(门禁验)。
const WAVE_SPD := 900.0
## 十字斩两段的扇形半角(弧度): 横斩 120°/2 · 竖斩 60°/2。★与结算侧焊死。
const SLASH_HALF_WIDE := 1.0471975512
const SLASH_HALF_NARROW := 0.5235987756

## 贴地几何离地高度(米)
const GROUND_Y := 0.07
## 本层节点上打的 meta 键 —— 门禁按 meta 数, 不按节点名/贴图路径
## (程序生成贴图 resource_path 是空串, 按路径数会全数成 0)
const META_KEY := "blade_eq_vfx"
## _owned 上限(最后一道闸, 同 SynergyVfx.OWNED_CAP 的口径)
const OWNED_CAP := 256

var battle
## 本层建出来、还活着的节点(撤场用)。★存节点不存单位字典 —— CLAUDE.md §3.2
var _owned: Array = []
## 正在播的短命特效 [{node, t, life, kind, …}] —— 每帧由 tick() 推进, 不用 tween
var _fx: Array = []
## 举盾期常驻盾面: [{node, u, t}]。★存单位字典【值】不当键, 比较一律 is_same
var _guards: Array = []


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等演出
# ══════════════════════════════════════════════════════════════════════

## ① 临界阻尼(ζ=1)阶跃响应 x̂(t) = 1 − (1+ωt)e^(−ωt)。
## 性质: x̂(0)=0 · 单调增 · 恒 < 1(永不过冲) · x̂(1/ω) = 1 − 2/e = 0.2642411。
static func guard_open(omega: float, t: float) -> float:
	if t <= 0.0:
		return 0.0
	var w: float = omega * t
	return 1.0 - (1.0 + w) * exp(-w)


## ② 平方反比亮度 I(d)/I₀ = 1 / (1 + (d/d₀)²)。性质: I(d₀)/I(0) ≡ 0.5, 与 d₀ 无关。
static func reflect_intensity(dist: float, d0: float) -> float:
	if d0 <= 0.0:
		return 1.0
	var x: float = dist / d0
	return 1.0 / (1.0 + x * x)


## ③ 层数辉光的对数刻度 g(s) = ln(1+s)/ln(1+20)。性质: g(0)=0 · g(20)=1 · g(4) > 0.2。
static func stack_glow(stacks: int) -> float:
	# 说明见文件头 ③: 低层区间被拉开, 20 层才在同一条尺子上分得清
	var s: float = clampf(float(stacks), 0.0, STACK_CAP)
	return log(1.0 + s) / STACK_LN21


## ④ 剑波在 t 秒后的位置(匀速直线)。★演出与结算共用 WAVE_SPD。
static func wave_pos(org: Vector2, dir: Vector2, t: float) -> Vector2:
	return org + dir * (WAVE_SPD * t)


## 十字斩某段的扇形半角(弧度)。★结算侧 `EqBladeBatch.cross_slash_hit` 用同一组数, 门禁焊死。
static func slash_half_rad(seg: int) -> float:
	return SLASH_HALF_WIDE if seg == 1 else SLASH_HALF_NARROW


# ══════════════════════════════════════════════════════════════════════
#  §建节点
# ══════════════════════════════════════════════════════════════════════

func _adopt(n: Node3D, kind: String) -> void:
	n.set_meta(META_KEY, kind)
	battle._world.add_child(n)
	if _owned.size() >= OWNED_CAP:
		var old = _owned.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	_owned.append(n)


## 贴地圆盘/圆环的通用构造(躺平·只设 axis·不加 rotation)。
func _ground(tex: Texture2D, pos2d: Vector2, diam_px: float, col: Color, prio: int = 5) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = prio
	s.modulate = col
	s.position = battle._world_pos(pos2d, GROUND_Y)
	var w: float = maxf(1.0, float(tex.get_width()))
	s.pixel_size = (diam_px * battle.WS) / w
	return s


## 面向相机的公告板(斩击/盾面/能量束都用它)。
func _board(tex: Texture2D, pos2d: Vector2, height_m: float, size_px: float, col: Color, prio: int = 6) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = prio
	s.modulate = col
	s.position = battle._world_pos(pos2d, height_m)
	var w: float = maxf(1.0, float(tex.get_width()))
	s.pixel_size = (size_px * battle.WS) / w
	return s


# ── 081 举盾 ────────────────────────────────────────────────────────

## 举盾: 一面藤青色圆盾以临界阻尼张开 + 一圈贴地护环。
## ★同步入口: 本函数返回时节点已在 _world 里、参数已是最终值, 门禁下一行就能判。
func guard_raise(u: Dictionary) -> void:
	if not _has_world() or not (u is Dictionary):
		return
	guard_lower(u)   # 同一只龟不叠两面盾
	var shield := _board(VfxTex._make_disc_texture(), u["pos"], float(u.get("height", 1.2)) + 0.4,
		GUARD_R_PX, Color(0.55, 0.82, 0.52, 0.0), 7)
	_adopt(shield, "guard")
	var ring := _ground(VfxTex._make_thin_ring_tex(), u["pos"], GUARD_RING_PX * 2.0,
		Color(0.62, 0.88, 0.55, 0.85), 5)
	_adopt(ring, "guard_ring")
	_guards.append({"node": shield, "ring": ring, "u": u, "t": 0.0})


## 落盾: 收掉这只龟的常驻盾面。
## ★阵亡那条路(puff=false)也要收 —— 不收的话盾面会一直挂在死人身上直到换路。
func guard_lower(u: Dictionary, puff: bool = true) -> void:
	var keep: Array = []
	var found := false
	for g in _guards:
		if is_same(g["u"], u):
			found = true
			for k in ["node", "ring"]:
				var n = g.get(k, null)
				if n != null and is_instance_valid(n):
					n.queue_free()
			continue
		keep.append(g)
	_guards = keep
	if found and puff and _has_world():
		var r := _ground(VfxTex._make_thin_ring_tex(), u["pos"], 96.0, Color(0.62, 0.88, 0.55, 0.7), 5)
		_adopt(r, "guard_off")
		_fx.append({"node": r, "t": 0.0, "life": 0.24, "kind": "grow", "d0": 96.0, "d1": 46.0})


func guard_count() -> int:
	return _guards.size()


# ── 082 护心反伤 ────────────────────────────────────────────────────

## 反伤: 从携带者射向攻击者的一束能量, 亮度按平方反比。
func clam_reflect(u: Dictionary, src) -> void:
	if not _has_world() or not (src is Dictionary):
		return
	var a: Vector2 = u["pos"]
	var b: Vector2 = (src as Dictionary)["pos"]
	var d: float = a.distance_to(b)
	var inten: float = reflect_intensity(d, REFLECT_D0)
	var s := Sprite3D.new()
	s.texture = VfxTex._make_laser_beam_tex(Color(0.62, 0.95, 0.84))
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 6
	s.modulate = Color(0.62, 0.95, 0.84, 0.35 + 0.55 * inten)
	s.position = battle._world_pos((a + b) * 0.5, float(u.get("height", 1.2)) * 0.6)
	var w: float = maxf(1.0, float(s.texture.get_width()))
	s.pixel_size = (maxf(8.0, d) * battle.WS) / w
	_adopt(s, "reflect")
	_fx.append({"node": s, "t": 0.0, "life": 0.18, "kind": "fade"})


## 消耗一层充能的强化普攻: 携带者一圈贝壳白光 + 目标一圈冲击。
func clam_burst(u: Dictionary, tgt) -> void:
	if not _has_world():
		return
	var r1 := _ground(VfxTex._make_thin_ring_tex(), u["pos"], 120.0, Color(0.85, 0.98, 0.95, 0.9), 5)
	_adopt(r1, "clam_burst")
	_fx.append({"node": r1, "t": 0.0, "life": 0.3, "kind": "grow", "d0": 120.0, "d1": 190.0})
	if tgt is Dictionary:
		var r2 := _ground(VfxTex._make_thin_ring_tex(), (tgt as Dictionary)["pos"], 60.0,
			Color(0.5, 0.9, 1.0, 0.9), 5)
		_adopt(r2, "clam_burst")
		_fx.append({"node": r2, "t": 0.0, "life": 0.28, "kind": "grow", "d0": 60.0, "d1": 130.0})


# ── 083 潮汐细剑层数 ────────────────────────────────────────────────

## 叠层: 一圈随层数(对数刻度)变亮变大的潮汐蓝细环。
func rapier_stack(u: Dictionary, stacks: int) -> void:
	if not _has_world():
		return
	var g: float = stack_glow(stacks)
	var ring := _ground(VfxTex._make_thin_ring_tex(), u["pos"], 46.0 + 46.0 * g,
		Color(0.35 + 0.45 * g, 0.75 + 0.2 * g, 1.0, 0.35 + 0.6 * g), 5)
	_adopt(ring, "rapier")
	_fx.append({"node": ring, "t": 0.0, "life": 0.22, "kind": "fade"})


# ── 084 后撤十字斩 ──────────────────────────────────────────────────

## 后撤: 起点留一道残影 + 落点扬尘。
func cross_retreat(u: Dictionary, dest: Vector2, _dir: Vector2) -> void:
	if not _has_world():
		return
	var dust := _ground(VfxTex._make_thin_ring_tex(), dest, 70.0, Color(0.85, 0.88, 0.95, 0.8), 5)
	_adopt(dust, "retreat")
	_fx.append({"node": dust, "t": 0.0, "life": 0.26, "kind": "grow", "d0": 70.0, "d1": 130.0})


## 斩击: 一道新月剑弧, 张角与结算侧同一个数(见 slash_half_rad)。
func cross_slash(u: Dictionary, dir: Vector2, seg: int) -> void:
	if not _has_world():
		return
	var half: float = slash_half_rad(seg)
	var col: Color = Color(0.86, 0.92, 1.0) if seg == 1 else Color(1.0, 0.94, 0.78)
	var mid: Vector2 = u["pos"] + dir * 125.0
	var s := _board(VfxTex._make_slash_texture(col), mid, float(u.get("height", 1.2)) * 0.75,
		250.0 * (half / SLASH_HALF_WIDE + 0.5), Color(col.r, col.g, col.b, 0.95), 7)
	_adopt(s, "slash")
	_fx.append({"node": s, "t": 0.0, "life": 0.22, "kind": "fade"})


## 剑波: 沿 dir 匀速推进, 位置由 wave_pos() 给出(与结算侧同一个 WAVE_SPD)。
func cross_wave(u: Dictionary, org: Vector2, dir: Vector2, seg: int) -> void:
	if not _has_world():
		return
	var col: Color = Color(0.74, 0.86, 1.0) if seg == 2 else Color(1.0, 0.9, 0.7)
	var wide: bool = seg == 2
	var s := _board(VfxTex._make_wave_texture(col), org, float(u.get("height", 1.2)) * 0.7,
		(250.0 if wide else 110.0), Color(col.r, col.g, col.b, 0.9), 7)
	_adopt(s, "wave")
	_fx.append({"node": s, "t": 0.0, "life": 0.78, "kind": "wave", "org": org, "dir": dir,
		"h": float(u.get("height", 1.2)) * 0.7})


# ══════════════════════════════════════════════════════════════════════
#  §每帧推进(不用 tween) + 撤场
# ══════════════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	# 举盾常驻盾面: 临界阻尼张开
	var gkeep: Array = []
	for g in _guards:
		var n = g.get("node", null)
		if n == null or not is_instance_valid(n):
			continue
		g["t"] = float(g["t"]) + delta
		var a: float = guard_open(GUARD_OMEGA, float(g["t"]))
		var uu: Dictionary = g["u"]
		(n as Sprite3D).modulate.a = 0.30 + 0.55 * a
		(n as Sprite3D).position = battle._world_pos(uu["pos"], float(uu.get("height", 1.2)) + 0.4)
		var r = g.get("ring", null)
		if r != null and is_instance_valid(r):
			(r as Sprite3D).position = battle._world_pos(uu["pos"], GROUND_Y)
			(r as Sprite3D).modulate.a = 0.35 + 0.5 * a
		gkeep.append(g)
	_guards = gkeep
	# 短命特效
	var keep: Array = []
	for f in _fx:
		var n = f.get("node", null)
		if n == null or not is_instance_valid(n):
			continue
		f["t"] = float(f["t"]) + delta
		var x: float = clampf(float(f["t"]) / maxf(0.001, float(f["life"])), 0.0, 1.0)
		match str(f.get("kind", "fade")):
			"grow":
				var d: float = lerpf(float(f["d0"]), float(f["d1"]), x)
				var w: float = maxf(1.0, float((n as Sprite3D).texture.get_width()))
				(n as Sprite3D).pixel_size = (d * battle.WS) / w
				(n as Sprite3D).modulate.a = 1.0 - x
			"wave":
				var p: Vector2 = wave_pos(f["org"], f["dir"], float(f["t"]))
				(n as Sprite3D).position = battle._world_pos(p, float(f["h"]))
				(n as Sprite3D).modulate.a = 1.0 - x * x
			_:
				(n as Sprite3D).modulate.a = 1.0 - x
		if x >= 1.0:
			n.queue_free()
			continue
		keep.append(f)
	_fx = keep


## ★换路撤场: 本层建的每个节点都进 _owned, 这里一次性收掉还活着的。
func clear() -> void:
	for n in _owned:
		if is_instance_valid(n):
			n.queue_free()
	_owned.clear()
	_fx.clear()
	_guards.clear()


## 本层现在挂了几个节点(门禁按 meta 数)。
func owned_count() -> int:
	var n := 0
	for x in _owned:
		if is_instance_valid(x) and (x as Node).has_meta(META_KEY):
			n += 1
	return n
