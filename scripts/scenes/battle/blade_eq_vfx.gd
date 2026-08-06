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
const GUARD_R_PX := 82.0
## 举盾贴地环半径(码)
const GUARD_RING_PX := 62.0
## 举盾盾面的**起手** alpha。★2026-08-07: 原来是 0.0 —— 建出来那一帧完全透明,
##   要等下一次 `tick()` 才被写成 0.30。挂在演出上没人发现, 但"举盾"最该被看到的
##   就是抬起来那一瞬。现在建出来就有底 alpha, 临界阻尼曲线只负责【继续张开】。
const GUARD_A0 := 0.34
const GUARD_A1 := 0.52
## 藤编的三个色(2026-08-07 重定): 原来是 (0.55,0.82,0.52) 这种**高明度低饱和**的浅绿,
## 在近黑地板上叠出来 ≈ RGB(158,224,140), 肉眼读作"白" —— 用户原话「把藤青烧成白」。
## 现在压明度、提饱和 ⇒ 同样的 alpha 下 RGB ≈ (76,178,56), 是**绿**。
const VINE_BODY := Color(0.24, 0.62, 0.20)     # 藤条本体
const VINE_RIM := Color(0.66, 0.88, 0.42)      # 藤条亮边(编织的高光)
const VINE_GAP := Color(0.05, 0.14, 0.05)      # 编织缝隙(暗) —— 有暗缝才读得出"编"

## ② 082 反伤束的半亮距离 d₀(码)。I(d₀) = I₀/2。
const REFLECT_D0 := 220.0
## 反伤束宽(码)
const REFLECT_W := 14.0
## ★2026-08-07 反伤改成【一串贝壳弧】而不是一条直光束:
##   原来用 `_make_laser_beam_tex` 画一条实心直条 —— 而场上每一发子弹的弹迹也是实心直条,
##   遮住颜色就完全分不出(用户:「撞形状比撞色更要命」)。
##   贝壳弧是**离散的、带肋的扇形**, 剪影上与任何直条/圆环都不同。
const REFLECT_SHELLS := 5
## 单枚贝壳弧的尺寸(码)
const SHELL_PX := 54.0
## 贝壳弧的离地高度(米)。★不能用 `u["height"]` —— 那是**击飞高度**, 常态恒为 0,
##   于是整串贝壳贴在地面被影子和飘字压住(第一版实拍就是这样)。
const SHELL_Y := 0.80

## ③ 083 层数辉光: 20 层归一。ln(1+20) = 3.0445224377234230(字面量 —— GDScript 的 const
##   表达式不接受内建函数调用, 同 BowEqVfx.GOLDEN_ANGLE 那条注释)。
const STACK_CAP := 20.0
const STACK_LN21 := 3.044522437723423
## ★2026-08-07 层数改成【进度弧】: 原来只是"环随层数变亮一点", 20 层与 3 层肉眼一样,
##   而 20 层是这件的**核心资源**。现在环上点亮的那一段弧 = stacks/20,
##   刻度分成 20 格 ⇒ 既能一眼读"满没满", 也能真的数出来是几层。
const STACK_TICKS := 20
## 进度环的直径(码): 0 层这么大 → 20 层这么大
const STACK_D0 := 74.0
const STACK_D1 := 132.0

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

## 程序化贴图的静态缓存(整个进程建一次)。★全部逐像素现算, 没有从 assets/ 拿任何一张现成图。
static var _tex_vine_shield: ImageTexture = null
static var _tex_vine_ring: ImageTexture = null
static var _tex_shell: ImageTexture = null
static var _tex_stack: Dictionary = {}     # stacks(int) → ImageTexture, 最多 21 张

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


## ③ 进度弧点亮的比例 ≡ stacks / 20。★与 `stack_glow` 的对数刻度**分工不同**:
##   对数那条管"亮度"(低层区间拉开), 这条管"读数"(必须线性, 否则数不出是几层)。
static func stack_frac(stacks: int) -> float:
	return clampf(float(stacks) / STACK_CAP, 0.0, 1.0)


## ③ 进度环直径(码): 与层数线性 —— 与亮度那条对数曲线各管一头。
static func stack_diam(stacks: int) -> float:
	return lerpf(STACK_D0, STACK_D1, stack_frac(stacks))


## ★★`"grow"` 的两条曲线【必须分开】(2026-08-07, 与主场景 `_skill_ring` 同一个 bug)
##
## 旧写法是**同一个归一时间 x** 同时驱动尺寸与 alpha:
##     pixel_size = lerp(d0, d1, x)   ·   modulate.a = 1 − x
## ⇒ 环**长到最大的那一帧 alpha 恰好 = 0**, 肉眼只看得见中间那一段。
##   受害的是 082 `clam_burst`(120→190 / 60→130) 与 084 `cross_retreat`(70→130)。
## ⇒ 拆成两段: `x ≤ GROW_KNEE` 只扩张(alpha 满), 之后才淡出。
## ★可验证性质(门禁): **`grow_alpha(GROW_KNEE) ≡ 1.0` 且 `grow_size_frac(GROW_KNEE) ≡ 1.0`**
##   —— "尺寸到顶那一刻 alpha 也在顶"。旧写法在这一点上是 0.0, 一测就分开。
const GROW_KNEE := 0.55

## 扩张进度: [0, KNEE] 内 0→1, 之后恒 1(长满就不再变大)。
static func grow_size_frac(x: float) -> float:
	return clampf(clampf(x, 0.0, 1.0) / GROW_KNEE, 0.0, 1.0)


## 不透明度: [0, KNEE] 恒 1(扩张期不淡), 之后线性到 0。
static func grow_alpha(x: float) -> float:
	var q: float = clampf(x, 0.0, 1.0)
	if q <= GROW_KNEE:
		return 1.0
	return clampf(1.0 - (q - GROW_KNEE) / (1.0 - GROW_KNEE), 0.0, 1.0)


## ② 第 i 枚贝壳弧在 a→b 上的位置(等距铺, 两端都不贴在单位身上)。
static func shell_pos(a: Vector2, b: Vector2, i: int, n: int) -> Vector2:
	if n <= 1:
		return (a + b) * 0.5
	return a.lerp(b, 0.15 + 0.70 * float(i) / float(n - 1))


# ══════════════════════════════════════════════════════════════════════
#  §程序化贴图 —— 逐像素现算, 零素材; 判据是【剪影】不是颜色
# ══════════════════════════════════════════════════════════════════════

## 藤编圆盾的盾面。★为什么不能继续用 `_make_disc_texture`(实心圆):
##   场上"敌人脚下的命中闪光"也是一个白圆盘, 遮住颜色就是同一个东西。
##   这里的剪影是**上平下尖的盾形** + 内部**斜向编织**, 圆盘一眼就分得开。
static func vine_shield_tex() -> ImageTexture:
	if _tex_vine_shield != null:
		return _tex_vine_shield
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(n):
		for x in range(n):
			var nx: float = (float(x) / float(n - 1)) * 2.0 - 1.0     # −1..1
			var ny: float = (float(y) / float(n - 1)) * 2.0 - 1.0     # −1(上) .. 1(下)
			# 盾形轮廓: 上缘圆角、腰身直、下缘收尖
			var wmax := 1.0
			if ny < -0.72:
				var t: float = (ny + 0.72) / 0.28                      # −1..0
				wmax = sqrt(maxf(0.0, 1.0 - t * t))
			elif ny > 0.0:
				wmax = maxf(0.0, 1.0 - pow(ny, 1.55))
			var d: float = absf(nx) / maxf(0.001, wmax)                # 1.0 = 轮廓上
			if d > 1.0 or ny > 0.995:
				continue
			# 编织: 两族斜向条带交错(经/纬), 缝隙留暗 ⇒ 读得出"编"而不是"一块塑料"
			var u: float = float(x) * 0.72 + float(y) * 0.72
			var v: float = float(x) * 0.72 - float(y) * 0.72
			var weave: float = maxf(sin(u * 0.55), sin(v * 0.55))      # −1..1
			var col: Color = VINE_GAP.lerp(VINE_BODY, clampf(weave * 0.5 + 0.65, 0.0, 1.0))
			var a := 0.92
			if d > 0.86 or ny > 0.90:                                  # 亮边(藤条外圈)
				col = VINE_RIM
				a = 1.0
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	_tex_vine_shield = ImageTexture.create_from_image(img)
	return _tex_vine_shield


## 举盾的贴地环: **断续的藤条环**(16 段), 不是平滑细圆环。
## ★平滑细圆环全场到处都是(命中环/技能环/目标环) —— 断续段是这一件自己的剪影。
static func vine_ring_tex() -> ImageTexture:
	if _tex_vine_ring != null:
		return _tex_vine_ring
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var dx: float = (float(x) - c) / c
			var dy: float = (float(y) - c) / c
			var r: float = sqrt(dx * dx + dy * dy)
			if r < 0.80 or r > 1.0:
				continue
			var seg: float = fposmod(atan2(dy, dx) / TAU * 16.0, 1.0)   # 16 段
			if seg > 0.64:                                              # 段与段之间留缝
				continue
			var band: float = 1.0 - absf(r - 0.90) / 0.10
			var a: float = clampf(band, 0.0, 1.0) * (1.0 if seg < 0.56 else (0.64 - seg) / 0.08)
			if a <= 0.02:
				continue
			var col: Color = VINE_BODY.lerp(VINE_RIM, clampf(band, 0.0, 1.0) * 0.55)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
	_tex_vine_ring = ImageTexture.create_from_image(img)
	return _tex_vine_ring


## 082 反伤的一枚**贝壳弧**: 带径向肋的扇形(尖端朝 +X)。
static func shell_tex() -> ImageTexture:
	if _tex_shell != null:
		return _tex_shell
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var dx: float = (float(x) - c) / c
			var dy: float = (float(y) - c) / c
			var r: float = sqrt(dx * dx + dy * dy)
			if r < 0.42 or r > 0.99:
				continue
			var th: float = atan2(dy, dx)
			if absf(th) > 1.25:                       # ±72°的扇
				continue
			var rib: float = 0.55 + 0.45 * cos(th * 9.0)              # 贝壳的径向肋
			var edge: float = clampf((0.99 - r) / 0.14, 0.0, 1.0) * clampf((r - 0.42) / 0.10, 0.0, 1.0)
			var a: float = rib * edge
			if a <= 0.02:
				continue
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	_tex_shell = ImageTexture.create_from_image(img)
	return _tex_shell


## 083 的**层数进度环**: 20 格刻度, 点亮 `stacks` 格。★每个层数各一张(最多 21 张), 静态缓存。
## ★这是"20 层是核心资源"这条信息在画面上的唯一出口 —— 数得出来才算数。
static func stack_ring_tex(stacks: int) -> ImageTexture:
	var k: int = clampi(stacks, 0, int(STACK_CAP))
	if _tex_stack.has(k):
		return _tex_stack[k]
	var n := 192
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(n - 1) * 0.5
	var lit: int = k
	for y in range(n):
		for x in range(n):
			var dx: float = (float(x) - c) / c
			var dy: float = (float(y) - c) / c
			var r: float = sqrt(dx * dx + dy * dy)
			if r < 0.74 or r > 0.99:
				continue
			# 从正上方(−Y)开始顺时针的格号
			var frac: float = fposmod(atan2(dx, -dy) / TAU, 1.0)
			var slot: int = int(frac * float(STACK_TICKS))
			var inside: float = fposmod(frac * float(STACK_TICKS), 1.0)
			if inside > 0.80:                                # 格与格之间的分隔缝 ⇒ 数得出来
				continue
			var band: float = clampf((0.99 - r) / 0.09, 0.0, 1.0) * clampf((r - 0.74) / 0.07, 0.0, 1.0)
			var on: bool = slot < lit
			# ★空格不能太暗: 进度条没有"轨道"就只是一段弧, 读不出"还差多少"
			var a: float = band * (1.0 if on else 0.34)
			var col: Color = Color(0.80, 0.98, 1.0) if on else Color(0.30, 0.52, 0.66)
			if on and slot == lit - 1:                       # 弧头再亮一档(读得出"刚涨的是这一格")
				col = Color(1.0, 1.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
	var t := ImageTexture.create_from_image(img)
	_tex_stack[k] = t
	return t


# ══════════════════════════════════════════════════════════════════════
#  §建节点
# ══════════════════════════════════════════════════════════════════════

## 给"任何一种"节点写 alpha —— Sprite3D 走 modulate, 网格走 material_override。
static func _set_a(n, a: float) -> void:
	if n is Sprite3D:
		(n as Sprite3D).modulate.a = clampf(a, 0.0, 1.0)
	elif n is MeshInstance3D:
		var m = (n as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			var c: Color = (m as StandardMaterial3D).albedo_color
			(m as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))


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


## 一块**沿 a2→b2 摊平**的带贴图四边形(贴图 +X 指向 b2)。
## ★为什么不用 `Sprite3D` + `rotation.z`: `BILLBOARD_ENABLED` 会**吃掉 roll**
##   (本仓库 001 飞斩踩过的坑) —— 贝壳弧就会全部朝右, 而且不报错。
##   世界坐标顶点直接建 ⇒ 朝向由几何决定, 不靠 billboard 猜。
func _quad_along(a2: Vector2, b2: Vector2, half_w: float, y_m: float,
		tex: Texture2D, col: Color) -> MeshInstance3D:
	var dir: Vector2 = b2 - a2
	if dir.length() < 0.001:
		return null
	var p: Vector2 = Vector2(-dir.y, dir.x).normalized() * half_w
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v: Array = [battle._world_pos(a2 + p, y_m), battle._world_pos(b2 + p, y_m),
					battle._world_pos(b2 - p, y_m), battle._world_pos(a2 - p, y_m)]
	var uv: Array = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[idx])
		st.add_vertex(v[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 8
	mat.albedo_texture = tex
	mat.albedo_color = col
	mi.material_override = mat
	return mi


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
	# ★盾面: 上平下尖的【藤编盾形】+ 起手就有 alpha(GUARD_A0)。
	#   原来是 `_make_disc_texture` 实心圆 + alpha 0.0 —— 圆盘与"敌人脚下的命中闪光"
	#   撞形状, 而 alpha 0 让抬起来那一帧根本看不见。两条都在这里治掉。
	var shield := _board(vine_shield_tex(), u["pos"], float(u.get("height", 1.2)) + 0.4,
		GUARD_R_PX, Color(1, 1, 1, GUARD_A0), 7)
	_adopt(shield, "guard")
	# ★贴地环: 断续藤条环(16 段), 深绿高饱和 —— 不再是"到处都有的平滑白细环"
	var ring := _ground(vine_ring_tex(), u["pos"], GUARD_RING_PX * 2.0,
		Color(1, 1, 1, 0.9), 5)
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
		var r := _ground(vine_ring_tex(), u["pos"], 96.0, Color(1, 1, 1, 0.7), 5)
		_adopt(r, "guard_off")
		_fx.append({"node": r, "t": 0.0, "life": 0.24, "kind": "grow", "d0": 96.0, "d1": 46.0})


func guard_count() -> int:
	return _guards.size()


# ── 082 护心反伤 ────────────────────────────────────────────────────

## 反伤: 从携带者【弹回】攻击者的一串贝壳弧, 亮度按平方反比。返回铺了几枚(门禁分母)。
##
## ★2026-08-07 从"一条直光束"改成"一串贝壳弧"。原因不是好看:
##   直光束与**每一发子弹的弹迹**是同一个剪影(实心细长条), 只有颜色不同 ——
##   而颜色在混战里最先丢。离散的带肋扇形 ⇒ 遮住颜色也认得出。
## ★平方反比亮度那条模型**没动**(门禁 ② 仍然焊着 I(d₀)/I(0) ≡ 0.5), 只是把它
##   从"整条束的 alpha"改成"每一枚贝壳的 alpha", 语义一样。
func clam_reflect(u: Dictionary, src) -> int:
	if not _has_world() or not (src is Dictionary):
		return 0
	var a: Vector2 = u["pos"]
	var b: Vector2 = (src as Dictionary)["pos"]
	var d: float = a.distance_to(b)
	var inten: float = reflect_intensity(d, REFLECT_D0)
	var dir: Vector2 = (b - a)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var h: float = SHELL_Y + float(u.get("height", 0.0))
	for i in range(REFLECT_SHELLS):
		var f: float = float(i) / float(maxi(1, REFLECT_SHELLS - 1))
		var sz: float = SHELL_PX * (0.72 + 0.5 * f)
		var c2: Vector2 = shell_pos(a, b, i, REFLECT_SHELLS)
		# ★用世界坐标顶点建, 不用 `Sprite3D.rotation.z` —— billboard 会把 roll 吃掉
		#   (本仓库 001 飞斩的旧账), 贝壳就会全部朝右而且不报错。
		var mi := _quad_along(c2 - dir * sz * 0.5, c2 + dir * sz * 0.5, sz * 0.5, h, shell_tex(),
			Color(0.62, 0.95, 0.84, (0.55 + 0.45 * inten) * (0.60 + 0.40 * f)))
		if mi == null:
			continue
		_adopt(mi, "reflect")
		_fx.append({"node": mi, "t": 0.0, "life": 0.18 + 0.05 * f, "kind": "fade"})
	return REFLECT_SHELLS


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

## 叠层: 一圈 **20 格的进度环**, 点亮 `stacks` 格。
##
## ★2026-08-07 从"一圈随层数变亮的细环"改成进度环。原来 3 层和 19 层肉眼一模一样,
##   而 20 层是这件的核心资源 —— 这条信息以前一点都没给到玩家。
##   现在: 点亮弧长 = stacks/20(线性, 才数得出来), 直径也线性涨(远看也读得出多寡),
##   亮度仍走原来的对数刻度 `stack_glow`(低层区间被拉开)。
## ★满 20 层时整圈点亮并再补一圈外扩的白环, 把"到顶了"这一下做实。
func rapier_stack(u: Dictionary, stacks: int) -> void:
	if not _has_world():
		return
	var g: float = stack_glow(stacks)
	var ring := _ground(stack_ring_tex(stacks), u["pos"], stack_diam(stacks),
		Color(1.0, 1.0, 1.0, 0.55 + 0.45 * g), 5)
	_adopt(ring, "rapier")
	_fx.append({"node": ring, "t": 0.0, "life": 0.34, "kind": "fade"})
	if stacks >= int(STACK_CAP):
		var cap := _ground(stack_ring_tex(int(STACK_CAP)), u["pos"], stack_diam(stacks), Color(1, 1, 1, 0.9), 5)
		_adopt(cap, "rapier_cap")
		_fx.append({"node": cap, "t": 0.0, "life": 0.4, "kind": "grow",
			"d0": stack_diam(stacks), "d1": stack_diam(stacks) * 1.7})


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
		# ★起手就是 GUARD_A0(不是 0) —— 临界阻尼只负责从 A0 继续张到 A1
		(n as Sprite3D).modulate.a = GUARD_A0 + (GUARD_A1 - GUARD_A0) * a
		(n as Sprite3D).position = battle._world_pos(uu["pos"], float(uu.get("height", 1.2)) + 0.4)
		var r = g.get("ring", null)
		if r != null and is_instance_valid(r):
			(r as Sprite3D).position = battle._world_pos(uu["pos"], GROUND_Y)
			(r as Sprite3D).modulate.a = 0.62 + 0.34 * a
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
				# ★尺寸与 alpha 走【两条】曲线(见 GROW_KNEE): 先扩张、长满之后才淡出。
				#   同一个 x 同时驱动两者 ⇒ 最大的那一帧正好全透明(旧版的病)。
				var d: float = lerpf(float(f["d0"]), float(f["d1"]), grow_size_frac(x))
				var w: float = maxf(1.0, float((n as Sprite3D).texture.get_width()))
				(n as Sprite3D).pixel_size = (d * battle.WS) / w
				_set_a(n, grow_alpha(x))
			"wave":
				var p: Vector2 = wave_pos(f["org"], f["dir"], float(f["t"]))
				(n as Sprite3D).position = battle._world_pos(p, float(f["h"]))
				_set_a(n, 1.0 - x * x)
			_:
				# ★不能再假设"全是 Sprite3D" —— 082 的贝壳弧是 MeshInstance3D(要真朝向)
				_set_a(n, 1.0 - x)
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
