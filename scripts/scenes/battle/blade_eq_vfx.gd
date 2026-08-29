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
## ★★实拍(_vfxlab_p2eq_081_2.png 放大)后从 82 改到 58: 原来的盾面
## **把携带者从龟壳以下全盖住了**, 只剩壳顶露在外 —— 看不出是谁在举盾。
const GUARD_R_PX := 58.0
## 盾往**面向敌人的那侧**偏多少码 —— 盾是"挡在身前"的, 不是贴在脸上的。
## 偏了之后携带者的身体才露得出来(这才是"目前这只龟在举盾"的可读性)。
const GUARD_OFF_PX := 30.0
## 举起来的行程: 从低位弹到位(临界阻尼, 同本仓其它弹性动画)。
## 旧版只有 alpha 张开 ⇒ 盾是"凭空浮现"的, 没有**举**这个动作。
const GUARD_RISE_M := 0.55
## 举盾贴地环半径(码)
## ★2026-08-08 62→42: 盾面收到 58 之后, 124 码直径的藤环**比盾大一倍多**,
##   画面上是"一个大环外加一小块盾", 主次颠倒 —— 环只是脚下的记号, 不该抢主体。
const GUARD_RING_PX := 42.0
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
## 相邻两枚贝壳点亮的间隔(秒) —— 让整串读成"从自己弹向攻击者", 而不是一次糊上去
const REFLECT_STAGGER := 0.035
## 强化普攻的"回血上涌": 几片贝壳白光 / 上涌多少米 / 相邻两片错开多久
const HEAL_MOTES := 3
const HEAL_RISE_M := 0.85
const HEAL_MOTE_GAP := 0.055
## 单枚贝壳弧的尺寸(码)
const SHELL_PX := 54.0
## 贝壳弧的离地高度(米)。★不能用 `u["height"]` —— 那是**击飞高度**, 常态恒为 0,
##   于是整串贝壳贴在地面被影子和飘字压住(第一版实拍就是这样)。
const SHELL_Y := 0.80
## 贝壳弧取立绘高度的哪一成 —— 护心甲在胸口
const SHELL_FRAC := 0.42

## ③ 083 层数辉光: 20 层归一。ln(1+20) = 3.0445224377234230(字面量 —— GDScript 的 const
##   表达式不接受内建函数调用, 同 BowEqVfx.GOLDEN_ANGLE 那条注释)。
const STACK_CAP := 20.0
const STACK_LN21 := 3.044522437723423
## ★2026-08-07 层数改成【进度弧】: 原来只是"环随层数变亮一点", 20 层与 3 层肉眼一样,
##   而 20 层是这件的**核心资源**。现在环上点亮的那一段弧 = stacks/20,
##   刻度分成 20 格 ⇒ 既能一眼读"满没满", 也能真的数出来是几层。
const STACK_TICKS := 20
## 进度环的直径(码): 0 层这么大 → 20 层这么大
## ★2026-08-08 收小(74/132 → 46/74): 132 码直径横跨半个画面, 龟反而成了配角。
## 读数已进装备图标框, 这圈只负责"我在叠层"的氛围。
const STACK_D0 := 46.0
const STACK_D1 := 74.0
## 潮汐青 —— 全场的命中环/技能环/目标环都是白的, 白环撞形状又撞色
const TIDE_COL := Color(0.24, 0.86, 0.98)

## ④ 084 剑波演出速度(码/秒)。★与 `EqBladeBatch.WAVE_SPD` 焊死相等(门禁验)。
const WAVE_SPD := 900.0
## 十字斩两段的扇形半角(弧度): 横斩 120°/2 · 竖斩 60°/2。
## 十字斩扫过多远(码) —— 规格原文"250 码"。
## ★2026-08-20 现在**真的**共用了: `EqBladeBatch.cross_slash_hit()` 直接引用下面三个常量
##   (`BladeEqVfx.SLASH_HALF_WIDE / SLASH_HALF_NARROW / SLASH_REACH`), 不再自己写字面量。
## ⚠ 在此之前这里的注释写着"与结算侧焊死""共用这一个数" —— **是假的**: 结算侧自己写死了
##   250.0 / 1.0471975512 / 0.5235987756, 两边可以各改各的而没人知道, 也没有任何门禁在验。
##   **"注释说焊死了"不等于焊死了** —— 判据是"有没有那条断言/有没有真的引用同一个符号"。
## ★★2026-08-22 文案根除: 半角原来直接写弧度字面量(1.0471975512 / 0.5235987756),
##   而玩家文案写的是**度数**(120 度 / 60 度) —— 存弧度的话文案只能再手写一个 120。
##   ⇒ 存**语义值**(全角度数), 半角弧度由它推导。同一条规矩已用在
##   龟壳减速(存 20% 不存 ×0.8)、无头镰刀锥角(存全角)上。
const SLASH_DEG_WIDE := 120.0     # 横斩扇形张角(全角·度)
const SLASH_DEG_NARROW := 60.0    # 竖斩扇形张角(全角·度)
const SLASH_HALF_WIDE := deg_to_rad(SLASH_DEG_WIDE * 0.5)
const SLASH_HALF_NARROW := deg_to_rad(SLASH_DEG_NARROW * 0.5)
const SLASH_REACH := 250.0
## 剑刃弧贴图里, 弧的半径占帧宽的几成(见 cross_blade_tex 的 R = n*0.455)
const BLADE_R_FRAC := 0.455

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
static var _tex_blade: ImageTexture = null
static var _tex_wave: ImageTexture = null
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


## 084 十字斩的**剑刃弧**。★为什么不继续用共享的 `VfxTex._make_slash_texture`:
##   那张是 **64px + `a = edge²·taper` 的软渐变**, 放到屏上 250 码 ⇒ 一团**模糊的白雾**
##   (实拍 _vfxlab_p2eq_084_melee 里就是几道糊边白弧), 和全场脆像素完全两个画风。
##   而它还有别的调用方(主场景), 不能就地改硬 —— 所以本件自备一张。
## 剑刃的判据是**剪影**: 外缘一条硬边(刀锋), 内侧收进去(刀背), 两端尖 —— 不是一条羽化的带子。
static func cross_blade_tex() -> ImageTexture:
	if _tex_blade != null:
		return _tex_blade
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c: float = float(n) * 0.5
	var R: float = float(n) * 0.455
	var th: float = float(n) * 0.085
	for y in range(n):
		for x in range(n):
			var dx: float = float(x) - c
			var dy: float = float(y) - c
			var d: float = sqrt(dx * dx + dy * dy)
			if d > R or d < R - th:
				continue                       # ★硬边: 圈外/圈内直接不画, 不做羽化
			var a: float = atan2(dy, dx)
			var f: float = (a - deg_to_rad(-150.0)) / deg_to_rad(180.0)
			if f < 0.0 or f > 1.0:
				continue
			# 两端收尖: 靠**厚度**收(几何), 不靠 alpha 渐隐(羽化)
			var taper: float = sin(PI * f)
			if (R - d) > th * taper:
				continue
			# 刀锋那一层白热(最外 30%), 其余是本色 —— 两级台阶, 不是连续渐变
			var edge: bool = (R - d) < th * 0.30
			img.set_pixel(x, y, Color(1, 1, 1, 1.0) if edge else Color(0.92, 0.96, 1.0, 0.98))
	_tex_blade = ImageTexture.create_from_image(img)
	return _tex_blade


## 084 剑波: 一条**前刃硬、后缘阶梯收**的直波(不是软椭圆透镜)。
static func cross_wave_tex() -> ImageTexture:
	if _tex_wave != null:
		return _tex_wave
	# ★★第一版把内容**铺满整张贴图**, 再乘 250 码的板 ⇒ 屏上是一块比龟还大四倍的
	#   **梯形水杯**(实拍 _vfxlab_p2eq_084_melee 第一轮)。剑波的剪影是**一道弓形的薄刃**,
	#   不是一块板 ⇒ 内容只占纵向中间一小条, 其余留空; 板再大也只是"更长的一道刃"。
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid: float = float(h) * 0.5
	var thick: float = float(h) * 0.055      # 刃厚只占 5.5% ⇒ 屏上是"一道", 不是"一块"
	var bow: float = float(h) * 0.16         # 弓背深度(中间凸出去)
	for x in range(w):
		var t: float = float(x) / float(w - 1)             # 0..1 横向
		var taper: float = sin(PI * t)                      # 两端收尖
		if taper <= 0.02:
			continue
		var cy: float = mid - bow * taper                   # 弓形: 中间凸向 −Y(行进方向)
		var half: float = thick * taper
		var y0: int = int(floor(cy - half))
		var y1: int = int(ceil(cy + half))
		for y in range(maxi(0, y0), mini(h, y1 + 1)):
			var d: float = absf(float(y) - cy) / maxf(0.001, half)
			if d > 1.0:
				continue
			# 两级台阶: 前缘(靠 −Y 一侧)白热, 后半是本色 —— 阶梯读得出"刃"与"背"
			var lead: bool = (float(y) - cy) < -half * 0.25
			img.set_pixel(x, y, Color(1, 1, 1, 1.0) if lead else Color(0.70, 0.86, 1.0, 0.9))
	# 尾迹: 刃后方几道更细的短线(读出"它在往前推")
	for k in range(3):
		var off: float = thick * (2.2 + 2.0 * float(k))
		var a: float = 0.42 - 0.11 * float(k)
		for x in range(w):
			var t2: float = float(x) / float(w - 1)
			var tp: float = sin(PI * t2)
			if tp <= 0.30:
				continue
			var yy: int = int(round(mid - bow * tp + off))
			if yy < 0 or yy >= h:
				continue
			img.set_pixel(x, yy, Color(0.62, 0.80, 1.0, a))
	_tex_wave = ImageTexture.create_from_image(img)
	return _tex_wave


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
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 同 _board: 别把程序化贴图糊掉
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
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 同 _board/_ground: 别糊
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
	var face: float = 1.0 if bool(u.get("face_right", str(u.get("side", "left")) == "left")) else -1.0
	var at: Vector2 = Vector2(u["pos"]) + Vector2(GUARD_OFF_PX * face, 0.0)
	var h_top: float = float(u.get("height", 1.2)) + 0.4
	var shield := _board(vine_shield_tex(), at, h_top - GUARD_RISE_M,
		GUARD_R_PX, Color(1, 1, 1, GUARD_A0), 7)
	_adopt(shield, "guard")
	# ★贴地环: 断续藤条环(16 段), 深绿高饱和 —— 不再是"到处都有的平滑白细环"
	var ring := _ground(vine_ring_tex(), u["pos"], GUARD_RING_PX * 2.0,
		Color(1, 1, 1, 0.9), 5)
	_adopt(ring, "guard_ring")
	_guards.append({"node": shield, "ring": ring, "u": u, "t": 0.0, "face": face, "flash": 0.0})


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


## 挡下一击: 让盾面闪一下白。★实拍时盾**挡住伤害却毫无反馈** ——
## 这件的全部价值就是"这几秒挨的打不算数", 而画面上挨打和没挨打长得一模一样。
func guard_block(u: Dictionary) -> void:
	for g in _guards:
		if is_same(g["u"], u):
			g["flash"] = 1.0
			return


# ── 081 充能条 ──────────────────────────────────────────────────────
## ★★这件装备的**身份就是那条充能条**(累计挨够 40/35/30% 最大生命才举盾),
##   而实拍确认: 画面上**一点都看不见**。玩家读不出"还差多少就举盾",
##   于是举盾看起来像随机发生的。⇒ 头顶给一条真的条。
## 与 079 的金弹条同一套做法(背景条 + 填充条 + 每帧写位置), 但**不共用代码**:
##   那条在 gun_eq_vfx, 这是 blade_eq_vfx; 两层各自独立注入, 跨层调用会把演出层耦死。


## 层数指示格: 一层一格, 摆在条的**上方**。★这是"我手上有几层"的唯一读出口 ——
## 082 的普攻要消耗一层, 玩家读不到层数就不知道下一下普攻会不会触发。

## 条的**绝对**离地高度(米)。★纯函数, 门禁直接验(不用等演出建出来)。
##
## ★★用**本项目已有的头顶锚点** `bar_head_h`(血条就是按它定位的, 见 battle_render:484,
##   大单位如海盗船会覆写它抬高) —— 不自己从立绘尺寸另算一个。
##   第一版我写的是 `sprite_h(u, 1.0) + 0.55`, 实拍出来**条压在龟壳上**:
##   自己造的锚点和全场血条用的那个不是一回事, 一造就偏。这正是"手抄的副本必然落后"。
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
	# ★护心甲在**胸口**, 按携带者立绘取(0.42), 不再写死 0.80 —— 立绘一换尺寸写死的米数就错
	var h: float = GunEqVfx.sprite_h(u, SHELL_FRAC)
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
		# ★★2026-08-08 实拍(_vfxlab_p2eq_082_2.png)量了像素后两处改:
		#   ① **暗**: 主体只有 RGB(28~42, 35~53, 39~55), 地板是 (9,10,16) —— 几乎和背景一样。
		#      根因同 078 霰弹/079 治疗束: `fade` 从出生就线性收 alpha, 半程只剩一半亮。
		#      ⇒ 走 "holdfade"(前 70% 满亮)。
		#   ② **静**: 5 枚贝壳同时出现在路径上, 读不出"从护心甲弹向攻击者"这个方向。
		#      ⇒ 逐枚延迟 REFLECT_STAGGER 秒点亮 ⇒ 一串从自己流向对方的弧。
		_fx.append({"node": mi, "t": -REFLECT_STAGGER * float(i), "life": 0.18 + 0.05 * f,
			"kind": "holdfade", "a0": (0.55 + 0.45 * inten) * (0.60 + 0.40 * f)})
	# ★★2026-08-08 用户:「不应该是敌人身上有个攻击发出后回到自身的感觉吗」——
	#   旧版**只有中间那串贝壳弧**, 两头都没有事情发生 ⇒ 读成"我朝你扔了点东西",
	#   而不是"你打我这一下被甲弹回你自己身上"。⇒ 补两头:
	#     ① 出发端: 护心甲(胸口)一记**格挡白闪** = 这一下被甲挡住了
	#     ② 到达端: 攻击者**身体中段**一记贝壳撞击 = 弹回去打在你自己身上
	#   ②【延后到贝壳串走完才炸】—— 靠负的 t(holdfade 分支显式判 t<0 才不画)。
	var flash := _board(shell_tex(), a, h, SHELL_PX * 0.9, Color(1.0, 1.0, 0.95, 0.95), 9)
	_adopt(flash, "reflect")
	_fx.append({"node": flash, "t": 0.0, "life": 0.14, "kind": "holdfade", "a0": 0.95})
	var lag: float = REFLECT_STAGGER * float(REFLECT_SHELLS)
	var hb: float = GunEqVfx.body_mid_h(src)
	var pop := _board(shell_tex(), b, hb, SHELL_PX * 1.15, Color(0.72, 1.0, 0.92, 1.0), 9)
	_adopt(pop, "reflect")
	_fx.append({"node": pop, "t": -lag, "life": 0.20, "kind": "holdfade", "a0": 1.0})
	var rip := _ground(VfxTex._make_thin_ring_tex(), b, 44.0, Color(0.72, 1.0, 0.92, 0.85), 5)
	_adopt(rip, "reflect")
	_fx.append({"node": rip, "t": -lag, "life": 0.26, "kind": "grow", "d0": 44.0, "d1": 96.0})
	return REFLECT_SHELLS


## 消耗一层充能的强化普攻: 携带者一圈贝壳白光 + 目标一圈冲击。
func clam_burst(u: Dictionary, tgt) -> void:
	if not _has_world():
		return
	# ★★2026-08-08 用户:「强化普攻也没特效吗」—— 旧版就是**两个贴地细圆环**,
	#   而本文件自己的注释早就写着"平滑细圆环全场到处都是(命中环/技能环/目标环)"
	#   ⇒ 遮住颜色就完全分不出, 等于没有特效。这一发要读出**两件事**:
	#     ① 我回了一大口血(5/7/10% 最大生命)  ② 你吃了一记等同我魔抗的魔法伤害
	#   ⇒ ① 用**上涌的贝壳白光**(向上走的才读作治疗, 贴地环读不出);
	#     ② 用**贝壳撞击**砸在目标身体中段(与反伤同一族剪影 ⇒ 一眼认得出是这件装备)。
	var ch: float = GunEqVfx.sprite_h(u, SHELL_FRAC)
	var r1 := _ground(VfxTex._make_thin_ring_tex(), u["pos"], 96.0, Color(0.85, 0.98, 0.95, 0.9), 5)
	_adopt(r1, "clam_burst")
	_fx.append({"node": r1, "t": 0.0, "life": 0.3, "kind": "grow", "d0": 96.0, "d1": 168.0})
	# 回血: 三片贝壳白光**依次上涌**(错开点亮 ⇒ 有流向, 不是一团糊上去)
	for i in range(HEAL_MOTES):
		var f: float = float(i) / float(maxi(1, HEAL_MOTES - 1))
		var mo := _board(shell_tex(), u["pos"], ch + HEAL_RISE_M * f,
			SHELL_PX * (0.55 - 0.16 * f), Color(0.90, 1.0, 0.96, 0.95), 9)
		_adopt(mo, "clam_burst")
		_fx.append({"node": mo, "t": -HEAL_MOTE_GAP * float(i), "life": 0.30,
			"kind": "holdfade", "a0": 0.95})
	if tgt is Dictionary:
		var th: float = GunEqVfx.body_mid_h(tgt)
		var hit := _board(shell_tex(), (tgt as Dictionary)["pos"], th, SHELL_PX * 1.35,
			Color(0.55, 0.92, 1.0, 1.0), 9)
		_adopt(hit, "clam_burst")
		_fx.append({"node": hit, "t": 0.0, "life": 0.22, "kind": "holdfade", "a0": 1.0})
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
	# ★★2026-08-08 实拍(_vfxlab_p2eq_083_4.png)两处改:
	#   ① **环巨大**: 132 码直径在正常机位下横跨半个画面, 主体(龟)反而成了配角。
	#      ⇒ 收到 46→74 码。它是"我在叠层"的**氛围**, 不是读数 ——
	#      读数已经按用户 2026-08-08 的规矩搬进**装备图标框**(PANEL_COUNT["p2eq_083"]),
	#      环不必再兼职当刻度盘。
	#   ② **纯白**: 场上命中环/技能环/目标环全是白的, 遮住颜色就分不出。
	#      ⇒ 改潮汐青(与 083 的"潮汐细剑"同名同色), 满层才转白热。
	var g: float = stack_glow(stacks)
	# ★★2026-08-08 实拍复验后修: 第一版写 `g * 0.65`, 而 g 是**层数的对数刻度** ——
	#   18 层时 g≈0.97 ⇒ 和白色混了 63%, 实测最亮像素 (207,245,239) = **还是白的**。
	#   我按"低层青、满层白"设计, 却没算过实战里的层数分布: 连续命中同一目标时层数
	#   **几秒就堆满**, 所谓"低层"那一段几乎不存在 ⇒ 改色等于没改。
	#   ⇒ 转白只留一点点(0.22), 满层靠**变亮**而不是变白来表达。
	var col: Color = TIDE_COL.lerp(Color(1.0, 1.0, 1.0), g * 0.22)
	var ring := _ground(stack_ring_tex(stacks), u["pos"], stack_diam(stacks),
		Color(col.r, col.g, col.b, 0.62 + 0.38 * g), 5)
	_adopt(ring, "rapier")
	_fx.append({"node": ring, "t": 0.0, "life": 0.34, "kind": "fade"})
	if stacks >= int(STACK_CAP):
		var cap := _ground(stack_ring_tex(int(STACK_CAP)), u["pos"], stack_diam(stacks),
			Color(1.0, 1.0, 1.0, 0.9), 5)
		_adopt(cap, "rapier_cap")
		_fx.append({"node": cap, "t": 0.0, "life": 0.4, "kind": "grow",
			"d0": stack_diam(stacks), "d1": stack_diam(stacks) * 1.7})


# ── 084 后撤十字斩 ──────────────────────────────────────────────────

## 后撤: 起点残影 + 沿路拖影 + 落点扬尘。
##
## ★★2026-08-29 用户点名核对:「释放技能首先是向后退对吧？**这个你怎么实现**」——
##   查下来: 位置是 `u["pos"] = dest` **瞬移**, 演出只有落点一个尘环;
##   而这段函数的头注写着「起点留一道残影」—— **代码里根本没有残影**。
##   注释在替一个不存在的实现背书(memory [[fb-registered-todos-rot]] 同族)。
##
## ★为什么不改成"真的用位移动画退回去": `u["pos"]` 是**结算用的位置** ——
##   横斩/竖斩的扇形都以它为圆心, 后撤 150 码正是这一招的射程设计。
##   让它在 0.25 秒里滑动, 两刀的圆心就变成"退到一半的地方", 伤害几何跟着漂。
##   ⇒ **结算位置照旧瞬移(几何确定), 视觉上补出后跃的过程** —— 起点一道残影、
##     中途几道拖影, 眼睛看到的就是"往后一跃"。
##
## `from2d` = 起跳点(退之前站的地方)。
func cross_retreat(u: Dictionary, dest: Vector2, _dir: Vector2, from2d = null) -> void:
	if not _has_world():
		return
	## ① 起点残影 + 沿路拖影: 从起跳点到落点均匀铺几道, 越靠起点越淡、越先消失
	##    ⇒ 读出来是"人往后拉出一串影子", 而不是凭空出现在后面。
	var src: Vector2 = from2d if from2d is Vector2 else dest
	if (src - dest).length() > 8.0:
		for gi in range(RETREAT_GHOSTS):
			var f: float = float(gi) / float(RETREAT_GHOSTS - 1)     # 0=起点 … 1=落点
			var gp: Vector2 = src.lerp(dest, f)
			var g := _board(VfxTex._make_fire_glow_tex(), gp, GunEqVfx.body_mid_h(u),
				52.0, Color(0.80, 0.88, 1.0, 0.10 + 0.34 * f), 6)
			_adopt(g, "retreat")
			## 越靠起点活得越短 ⇒ 影子是"从后往前"依次消失的, 方向感来自这个时序
			_fx.append({"node": g, "t": 0.0, "life": 0.12 + 0.16 * f, "kind": "fade"})
	## ② 落点扬尘
	var dust := _ground(VfxTex._make_thin_ring_tex(), dest, 70.0, Color(0.85, 0.88, 0.95, 0.8), 5)
	_adopt(dust, "retreat")
	_fx.append({"node": dust, "t": 0.0, "life": 0.26, "kind": "grow", "d0": 70.0, "d1": 130.0})


## 蓄力: 后撤落地 → 第一刀之间那 0.25 秒。
##
## ★★2026-08-29 用户点名:「然后是蓄力, **你做了吗**」—— 没有。那 0.25 秒是**全空的**:
##   `cast_cross_slash` 排完两个待结算段就没别的了, 落地到出刀之间屏幕上什么都不发生。
##   一招"后撤 → 蓄力 → 斩"少了中间那一拍, 读起来就是"退了一下, 然后弧凭空出现"。
##
## 做法: 一圈剑气从外向内**收拢**到龟身前(收拢 = 蓄力的通用语言, 与"爆开"相反),
##   同时龟身做一次 `_anticipate` 预备形变(缩一下再挥出去, 引擎现成的)。
func cross_windup(u: Dictionary, dir: Vector2, sec: float) -> void:
	if not _has_world() or not (u is Dictionary):
		return
	battle._anticipate(u)                                    # 龟身预备形变(引擎现成)
	var org: Vector2 = (u["pos"] as Vector2) + dir * 26.0     # 聚在身前一点点, 朝着要砍的方向
	for i in range(WINDUP_MOTES):
		var a: float = TAU * float(i) / float(WINDUP_MOTES) + 0.4
		var far: Vector2 = org + Vector2(cos(a), sin(a)) * WINDUP_R
		## ★★2026-08-29 实拍修: 原来 22 码的暖橙微光, 在暗场里**根本看不见** ——
		##   门禁只验了"节点存在"(7 个 suck 条目), 守不住"看得见"。
		##   加大到 WINDUP_MOTE_PX、换成白青高亮。
		## ★用【实心亮点】而不是软光斑: `_make_fire_glow_tex` 是很软的径向渐变,
		##   46 码时中心也只有半亮, 暗场里读不出来(2026-08-29 连拍两轮都看不见)。
		##   换成细环贴图 —— 它有硬边, 小尺寸也看得清。
		var m := _board(VfxTex._make_thin_ring_tex(), far, GunEqVfx.body_mid_h(u),
			WINDUP_MOTE_PX, Color(0.72, 0.95, 1.0, 0.0), 7)
		_adopt(m, "windup")
		## kind="suck": 从 far 收到 org, 亮度**先升后收**(不是一出生就淡出 ——
		## 那个病今天记过四次)。收拢比整段稍快一点, 让最后一小段是"攒住了"的静止。
		_fx.append({"node": m, "t": 0.0, "life": maxf(0.08, sec * 0.86), "kind": "suck",
			"org": org, "from": far, "h": GunEqVfx.body_mid_h(u)})
	## ★再补一圈【向内收缩的预警环】—— 点太小时环是主读物,
	##   "环在收" 是全项目通用的"要来了"语言(_skill_ring 到处在用)。
	## ★预警环用 `battle._skill_ring` —— 全项目标准的"要来了"环, 到处在用、一定看得见,
	##   不自己再造一个(自造那版实拍只剩一个针尖大的暗圈)。
	battle._skill_ring(org, Color(0.72, 0.95, 1.0, 0.85), WINDUP_R * 1.6)


## 斩击: 一道新月剑弧, 张角与结算侧同一个数(见 slash_half_rad)。
## ⚠ **已知缺口(不隐瞒)**: `_dir` 现在没被用上 —— 弧是 `Sprite3D` 的 billboard,
##   billboard 会吃掉 roll(本仓 001 飞斩的旧账), 所以这一刀**指不了方向**, 永远按同一个
##   屏幕朝向画。要真指向目标得改用世界坐标顶点建的四边形(同 082 贝壳走 `_quad_along` 那条路)。
##   这一轮先把"尺寸对上规格 250 码 + 亮度读得出是一刀"做掉, 方向留作下一轮。
## 场地方向 → **屏幕平面内的 roll 角**(弧度)。纯函数, 门禁直接调。
## ★为什么要压一下纵深: 本作是 2.5D 斜视, 横向 0.6755 屏幕像素/码、贴地纵深只有 0.5267 px/码
##   ⇒ 场地上的 45° 在屏幕上不是 45°。不压这一下, 斜着劈的刀会指偏。
## ★屏幕 y 向下为正, 而场地 y 向"远处"为正 ⇒ 取负号。
## 084 十字斩的三张新素材(2026-08-29·PixelLab 新生成的**逐帧动画**, 横排 sheet·帧宽=图高)。
##
## ★★用户 2026-08-29 拿专业 AE 素材当参考, 逐条指出旧做法差在哪:
##   · **收放**: 弧身厚 → 急剧收成针尖(旧: 粗细均匀的月牙)
##   · **明暗**: 刀锋白热 + 弧身高饱和紫, 反差极强(旧: 通体浅青, 实拍饱和度只有 0.09)
##   · **分层**: 一笔里好几缕重叠的丝带(旧: 单层实心)
##   · **剑气波**: **扇形的一堵墙**, 由大量平行细丝组成、前缘散开成须状(旧: 一条细直波)
##   · **命中**: 紫色尖锐棱刺炸开 + 橙色火星(旧: **压根没有**)
##
## ★贴图不在时回退到原来的程序生成贴图 —— 没导入的 PNG `ResourceLoader.exists` 是 false,
##   直接 load 返回 null 而一句报错都没有。
## 横斩/竖斩**各用一张**。旧做法两段共用同一张、只换个 tint ⇒
## “十字”根本读不出来; 而且素材就 80 度张角, 两边各错一头
## (横斩少画 40 度、竖斩多画 20 度) ⇒ 演出与判定对不上。
## 现在由 build_eq084_vfx.py 绕圆心做**角向重映射**各出一张,
## 张角就是 SLASH_DEG_WIDE / SLASH_DEG_NARROW 本尊。
const TEX_SLASH_V2 := "res://assets/sprites/vfx/eq084-slash.png"
const TEX_SLASH_WIDE := "res://assets/sprites/vfx/eq084-slash-wide.png"
## ★★竖斩改用**真正新生成的**素材(2026-08-29, PixelLab 9 帧)。
##   之前那张是把横斩的源帧角向重映射+旋转出来的 —— 是变换不是新画。
##   用户三次点名要"新生成", 我三次退回改老图。
## ★前两板失败是因为提示词写的是**几何**("占整圆三分之一的扇形、圆心在右下角"),
##   模型直译成了扇子/车轮。第三板只描述**东西本身**(斜劈下来的刀光拖影)就对了。
const TEX_SLASH_NARROW := "res://assets/sprites/vfx/eq084-chop.png"
const TEX_WAVE_V2 := "res://assets/sprites/vfx/eq084-wave.png"
const TEX_BURST_V2 := "res://assets/sprites/vfx/eq084-burst.png"
## 普攻激光束(6 帧横排)。★新素材, 不复用 fx-energy-beam.png
const TEX_BEAM := "res://assets/sprites/vfx/eq084-beam.png"

const BEAM_HALF_W := 13.0     # 光束半宽(码)。细 —— 参考里是一条细电弧线
const BEAM_SEC := 0.24        # 光束存在多久(秒)。0.16 太短 —— 实拍四个采样点只撞上一次,
                              # 玩家也容易整场看漏。仍然是"闪一下"的量级(holdfade 前 70% 满亮)
const BEAM_ASPECT := 6.0      # 单帧宽高比(384/64), 用来算帧数
## ═════════════════════════════════
##  ★★斩击是一把【扇子】: 圆心 = 握剑的手
## ═════════════════════════════════
## 用户 2026-08-29:「这个像个扇子, 那圆心不是在右下一个点吗」——
## 对。扇子有转轴, 转轴就是握剑的手; 扇面从那一点朝挥砍方向张开。
##
## 旧做法错在**摆的是整张图的几何中心**:
##     _board(tex, u.pos + dir * 105, ...)      # ← _board 摆的是图心, 不是圆心
##   而圆心在帧的**左下角**(实测归一 0.083, 0.766) ⇒ 圆心被甩到龟斜后方半个板宽外。
##   转轴不在手上, 于是"方向怎么调都不对"(用户原话)。那句 `+ dir * 105` 也正是
##   为了补这个偏移才加的 —— 补歪了, 现在圆心钉对了就不需要它了。
##
## 实测(逐帧拟合"所有射线的出发点", 帧 0~5 一致 —— 帧 6~8 是消散段没有相干形状,
## 我第一版的拟合器在那里抓到残渣, 差点让我去"修"一个不存在的圆心跳变):
##   · 圆心归一        (0.664, 0.728)   ← 图像系, 0,0=左上
##   · 弧中线          图像系 -131 度 ⇒ 贴图平面 +131 度(平面 y 向上, 图像 y 向下)
##   · 含 90% 质量的最小弧  116 度 ← 几乎正好 = 横斩判定锥 120 度
##   · r95            0.55 帧宽 ⇒ 帧宽除 0.55 才让弧的外缘落在 SLASH_REACH
##
## ★★前一版我把圆心拟合成了**笔触收束的那一点**(左下 0.083,0.766)。
##   用户在图上标蓝点纠正: 圆心是**这道弧所在圆的圆心**(弧的凹侧、右下)。
##   剑绕着人转 ⇒ 人站在圆心, 不是站在笔触的尾巴上。
const SLASH_PIVOT := Vector2(0.664, 0.728)
const SLASH_ASSET_RAD := deg_to_rad(131.0)
const SLASH_R_FRAC := 0.55
const SLASH_ART_DEG := 116.0
const SLASH_LIFE := 0.90   # 斩击动画时长(秒)。用户 2026-08-29: 0.26 → 0.52 → 0.90
## ══ 竖斩: 120° 扇形、**下缘贴地**、扇面向上张开 ═════════════
##
## 用户 2026-08-29:「素材要不得, 得搞 120 度的, 120 扇形的一边得贴地」。
##
## ★为什么不再是 60° + 往下压: 竖斩的扇面是**竖直平面里的挥剑弧**
##   —— 从举过头顶砍到地面, 这道弧就是 120°; 而 60° 是**地面上的判定锥**,
##   两者本来不是同一个东西。我之前把它们当成一个, 才搞出"把扇面往下压几度"
##   这种凑数 —— 压 38° 时中线还整个掉到判定锥外面去了。
##
## ★怎么实现"贴地": 把扇形的**下缘**对齐到目标方向(屏幕平面内水平),
##   扇面从那条线往**上**张开 120° ⇒ 读成"从头顶砍到地上"。
##   素材的下缘在贴图平面里 = 弧中线(SLASH_ASSET_RAD) 减半个张角。
## ★圆心也跟着落到**脚下**(不再抬 64 码) —— 下缘要真的贴在地上,
##   扇尖就得在地面高度上。
const CHOP_ART_DEG := 120.0
## ★★竖斩那张的圆心**不是** SLASH_PIVOT —— 生成时已经把它旋转+挪到了左下角。
##   两张图的圆心不同位置, 拿错一个就把转轴钉到了别处。
## 竖斩新素材的锚点 = 【刀落地的那一点】(归一, 图像系)。
## ★为什么锚"落地点"而不是"曲率中心": 这张是**新月形刀光**不是扇形,
##   它与地面只有一个接触点; 把那一点钉在龟脚下, 弧自然就在地面之上。
## ★实测(逐帧取刀身最低那一排的中点), 帧 0~7 几乎不动: (0.588, 0.896)。
## ★用户 2026-08-29 拿 Aseprite 逐帧改过竖斩(并删掉了多余的 f6, 9⇒8 帧),
##   重量后落地点从 (0.588, 0.896) 移到 (0.468, 0.893)。
##   数是 `vfx_edit.py done` 量出来的, 不是我拍的 —— 它发现对不上就拒绝收工。
const CHOP_PIVOT := Vector2(0.468, 0.893)
## 刀身重心相对落地点的横向偏移(归一、图像系、负 = 刀在左边)。
## ★逐帧实测平均 -0.138 —— 素材里刀身在落地点的**左边**。
## ★它是"朝哪边砍"的唯一依据: 镜像条件必须让刀身落在**目标那一侧**。
##   我第一版把条件写反了(目标在右时不镜像) ⇒ 刀砍在龟的左后方、背对目标。
##   而当时那条"偏向目标一侧"的断言照样绿 —— 因为它量的是**板子的 +x 轴**,
##   不是刀身实际在哪边。尺子需要匹配被测的概念。
const CHOP_MASS_DX := -0.095
## 竖斩的尺寸相对横斩缩多少。
## ★用户 2026-08-29 实拍后:「要缩小」—— 原来两段共用一个板宽(455 码),
##   实拍量到那道新月跨约 250px 而龟只有 40px —— **6 倍龟身**, 把施法的龟整个罩住,
##   读起来是"一片东西飘在那", 不是"这只龟劈了一刀"。
## ★横斩不能缩 —— 它铺在地上、外缘就是 250 码判定范围。竖斩是竖直平面里的挥剑弧,
##   与地面锥无关, 所以可以单独缩。
const CHOP_SIZE := 0.5
## ★★旋转已经**焊进素材文件**了: 贴地的那条直边在图里就是水平指右(0度)。
##   所以 roll **不能再减一遍素材角** —— 减了就是转两次。
const CHOP_ASSET_RAD := 0.0
const BURST_SIZE := 190.0     # 命中爆点的世界尺寸(码)
const RETREAT_GHOSTS := 5     # 后撤沿路铺几道拖影(含起点那道)
const WINDUP_MOTES := 7       # 蓄力收拢的剑气点数
const WINDUP_R := 78.0        # 剑气从多远收进来(码)
const WINDUP_MOTE_PX := 34.0  # 单颗剑气的世界尺寸(码)。★22 太小, 暗场里看不见(2026-08-29 实拍)
const SCREEN_DEPTH_K := 0.5267 / 0.6755
static func dir_to_roll(dir: Vector2) -> float:
	if dir.length_squared() < 1e-12:
		return 0.0
	return atan2(-dir.y * SCREEN_DEPTH_K, dir.x)


## 扇子的【圆心】相对图心的三维偏移(米)。摆位时用 `图心 = 目标点 - 本函数`。
##
## ★为什么要走 `Basis` 而不是在场地二维里算: 刀光板是**正对镜头**的(face_basis),
##   它所在的平面是斜的; 偏移必须沿着**板子自己的 x/y 轴**走,
##   在场地平面里算会偏。
## ★图像 y 向下、贴图平面 y 向上 ⇒ ly 取负。
## 【铺在地面平面】的基。用户 2026-08-29:「画在地面平面上」。
##
## ★为什么要改: 旧做法是 `face_basis` —— 板子**正对镜头**, 于是玩家看到的
##   120° 张角是**屏幕平面**的, 而伤害判定的 120° 锥是**地面平面**的 —— 两个不同的空间。
##   只有某些方向上它们才重合; `dir_to_roll` 里那个 SCREEN_DEPTH_K 只补中线方向,
##   补不了整个张角。铺到地面上之后 "看到多宽 = 打到多宽" 才是真的。
##
## ★参数 `aim_rad`: 素材里"要对准目标的那条线"在贴图平面的角度(y 向上)。
##   本函数保证: 那条线映到世界后正好沿着 `dir`(场地方向)。
## ★符号不靠推理 —— `_t084_ground_plane` 那几条断言直接量它落在哪儿。
static func ground_basis(dir: Vector2, aim_rad: float) -> Basis:
	var d: Vector2 = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	## 场地 (x, y) → 世界 (x, h, y)。把 d 在地面平面内旋转 -aim, 当作本地 +x。
	## ★★符号由探针定, 不由推理定。推导:
	##   本地 +y = z × x (z = 世界上) ⇒ 本地 +y 对应场地方向转 **-90°**,
	##   所以贴图平面角 A 的特征映到场地后的角 = angle(本地+x) - A。
	##   要让它等于 θ(目标方向) ⇒ angle(本地+x) = θ + A ⇒ 把 d 转 **+aim**。
	## ★我第一版写的是 -aim ⇒ 特征落在 θ - 2×aim, 探针实测三个方向**恒偏 +98°**
	##   (= -2×131° 模 360), 数字对得上 ⇒ 一眼就知道是旋转方向反了。
	var c: float = cos(aim_rad)
	var s2: float = sin(aim_rad)
	var fx: Vector2 = Vector2(d.x * c - d.y * s2, d.x * s2 + d.y * c)
	var bx: Vector3 = Vector3(fx.x, 0.0, fx.y).normalized()
	var bz: Vector3 = Vector3.UP
	var by: Vector3 = bz.cross(bx).normalized()
	return Basis(bx, by, bz)


static func slash_pivot_off3(bas: Basis, frame_m: float, piv: Vector2 = SLASH_PIVOT) -> Vector3:
	var lx: float = (piv.x - 0.5) * frame_m
	var ly: float = -(piv.y - 0.5) * frame_m
	return bas.x * lx + bas.y * ly


func cross_slash(u: Dictionary, _dir: Vector2, seg: int) -> void:
	if not _has_world():
		return
	var half: float = slash_half_rad(seg)
	var col: Color = Color(0.86, 0.92, 1.0) if seg == 1 else Color(1.0, 0.94, 0.78)
	# ★★2026-08-08 尺寸重定。旧写法 `250 * (half/WIDE + 0.5)` 给横斩算出 **375 码**——
	#   比规格的 250 码大了一半, 而这一笔正是"扫过多远"的唯一视觉承诺(演出即判定)。
	#   贴图里弧的半径占帧宽 BLADE_R_FRAC ⇒ 要让弧的**外缘**正好落在 250 码上,
	#   帧宽必须是 250 / BLADE_R_FRAC; 中心也就回到携带者身上(不再往前挪半个身位)。
	## ★★2026-08-29 换成【逐帧动画素材】。旧的是 `cross_blade_tex()` —— 代码算出来的
	##   一张静止半圆环, 拉到 250 码 ⇒ 实拍是一弯灰白月亮挂在半空(饱和度 0.09、跨 712px)。
	##   用户:「不要拿图片贴图敷衍我, **我要动画像素特效**」。
	## ★横斩(seg 1)拿宽那张、竖斩(seg 2)拿窄那张 —— 张角 = 各自的判定锥。
	var _path: String = TEX_SLASH_WIDE if seg == 1 else TEX_SLASH_NARROW
	if not ResourceLoader.exists(_path):
		_path = TEX_SLASH_V2
	var _anim: bool = ResourceLoader.exists(_path)
	var _tex: Texture2D = load(_path) if _anim else cross_blade_tex()
	## ★★摆位: 旧的程序贴图是**半圆环**(中间是空的), 以龟为中心画正好把龟框在弧里;
	##   新素材是**铺满整帧的实心刀光**, 同样摆法会**把龟整个盖住**(实拍只剩一点壳露出来)。
	##   —— 而那个前移是【补歪的】: 真正的毛病是圆心没钉在手上(见上面 SLASH_PIVOT),
	##   圆心钉对了龟就自然坐在扇尖上, 不需要再推开半个身位。
	## 竖斩的握剑手抬到头顶上方。
	## 竖斩的扇尖落在脚下(地面高度), 下缘才贴得住地。
	var _h: float = GunEqVfx.body_mid_h(u) if seg == 1 else 0.0
	var s := _board(_tex, u["pos"] as Vector2, _h,
		SLASH_REACH / BLADE_R_FRAC, Color(col.r, col.g, col.b, 0.95), 7)
	if _anim:
		## 横排 sheet: 帧宽 = 图高。新素材自带白热刀锋与紫弧身, 不再靠 modulate 上色
		## ⇒ modulate 收成白色, 否则把它的紫再乘一遍会脏。
		var _fh: int = maxi(1, _tex.get_height())
		s.hframes = maxi(1, int(_tex.get_width() / _fh))
		s.frame = 0
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.modulate = Color(1, 1, 1, 0.95)
		## ★板宽按【单帧】算, 不是整张 sheet —— `_board` 是按整张图宽归一的,
		##   9 帧的 sheet 直接用会让弧只有该有的 1/9 大(挂多帧贴图最常见的翻车)。
		## ★★尺寸【不能沿用 `SLASH_REACH / BLADE_R_FRAC`】——
		##   那个除法是给**旧的程序生成贴图**算的: 那张图里弧的半径只占帧宽 45.5%,
		##   所以要除回去把它放大到 250 码。新素材的弧**铺满整帧** ⇒ 再除 0.455
		##   等于白白放大 2.2 倍(实拍: 弧 400px 宽而龟只有 54px, **7.4 倍龟身**)。
		##   新素材直接按 SLASH_REACH 给板宽。
		## ★再除 SLASH_R_FRAC: 扇子的最远半径只占帧宽 92%, 不除的话外缘停在 230 码,
		##   而"扫过多远"是这一笔唯一的视觉承诺 —— 承诺 250 就得画到 250。
		var _scale: float = 1.0 if seg == 1 else CHOP_SIZE
		s.pixel_size = (SLASH_REACH / SLASH_R_FRAC * _scale * battle.WS) / float(_fh)
	## ★★2026-08-09 补上"指方向"这个缺口。旧注释写着「`_dir` 没被用上 —— 弧是 billboard,
	##   billboard 会吃掉 roll」。解法不是放弃 billboard 的**朝向**, 而是自己算基:
	##   `face_basis(视轴, roll)` = **正对镜头**(所以不会被 52° 俯视压扁) + **面内旋转**(所以指得出方向)。
	##   这与 094 闪电那条同族: billboard 的"完全对齐相机"包含 roll, 想自己控制 roll 就不能用它。
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	## ★★roll 要**扣掉素材自己的朝向**。`dir_to_roll(dir)` 给的是"目标在屏幕平面的角度",
	##   直接当 roll 用等于假设素材本来朝正右; 而这张素材本来朝**右上 34 度**
	##   ⇒ 每一刀固定偏 34 度。用户:「方向都调不准」就是这个。
	## 竖斩再往下压 CHOP_TILT(贴图平面 y 向上 ⇒ 往下是**减**)。
	## 横斩: 中线对准目标。竖斩: **下缘**对准目标(= 贴地), 扇面往上张。
	## ══ 横斩跟着方向转; 竖斩【不转】, 只左右镜像 ═══════════════
	##
	## ★★探针抓到的真因(2026-08-29): `face_basis` 是把**整个平面**按目标方向转。
	##   目标在左边时 roll≈180° ⇒ 板子**上下颠倒**(实测 basis.y.y = -0.626);
	##   目标在上/下时板子被转 90° ⇒ 扇面躺倒(basis.y.y = 0)。
	##   横斩无所谓(扇面本来就绕着转), 但**竖斩要求扇面永远在地面之上** ——
	##   颠倒过来就成了"从地底下往上劈"。
	## ⇒ 竖斩 roll 恒为 0(贴地边水平), 靠 flip_h 决定朝左还是朝右。
	## ★镜像条件由 CHOP_MASS_DX 的符号定: 刀身在左(负) ⇒ 目标在右时才要镜像。
	##   写成表达式而不是写死方向, 换素材时只要量一下 CHOP_MASS_DX 就跟着对。
	## ★★横斩**不镜像**。
	##   我曾按用户一句"横斩也左右反了"猜测性地给它加了恒镜像,
	##   铺地之后实拍直接看出来是错的: 扇面指向左下方、背对目标。
	## ★原因(可推导也可量): flip_h 把平面角 A 的特征翻到 180°-A ⇒
	##   铺地后中线的场地角 = θ + 2A - 180 = θ + 82°。
	## ★而当时那条"中线正对目标"的断言照样报 0.0° —— 因为它算的是
	##   **未翻转时**的特征方向。已把 flip_h 算进去, 否则它是假绿灯。
	var _mirror: bool = false
	if seg != 1:
		_mirror = (_dir.x * CHOP_MASS_DX < 0.0)
	var _roll: float = (dir_to_roll(_dir) - SLASH_ASSET_RAD) if seg == 1 else 0.0
	## ★横斩铺在地面平面(看到多宽 = 打到多宽); 竖斩仍然立着正对镜头
	##   —— 竖砍躺平了就不成立了。
	if seg == 1:
		s.basis = ground_basis(_dir, SLASH_ASSET_RAD)
	else:
		s.basis = ArcaneEqVfx.face_basis(ArcaneEqVfx.cam_forward_of(battle), _roll)
	## ★★把【圆心】钉到龟身上(而不是把图心摆过去)。`_board` 己经把**图心**
	##   放在了龟的位置 ⇒ 这里减去"圆心相对图心的偏移", 图心退开, 圆心就落到龟手上。
	if _mirror:
		s.flip_h = true
	if _anim:
		## ★镜像了的话圆心的 x 也要镜像, 否则转轴钉到对称的那一边去了。
		var _piv: Vector2 = SLASH_PIVOT if seg == 1 else CHOP_PIVOT
		if _mirror:
			_piv = Vector2(1.0 - _piv.x, _piv.y)
		s.position -= slash_pivot_off3(s.basis, s.pixel_size * float(maxi(1, _tex.get_height())), _piv)
	s.set_meta("slash_roll", _roll)
	_adopt(s, "slash")
	# ★★"一出生就线性淡出" —— 今天第四次同一个病(078 霰弹 / 079 治疗束 / 082 贝壳弧 / 这里)。
	#   一刀只活 0.22 秒, 线性淡出让它**大半辈子处在半亮以下** ⇒ 实拍里读成一道灰弧,
	#   而不是"一刀劈过去"。⇒ holdfade: 前 70% 满亮, 最后一段才收。
	## ★用户 2026-08-29:「斩击动画时间给我翻倍」—— 0.26 → 0.52。
	##   配合 CROSS_T1 0.25→0.40 / CROSS_T3 0.60→1.00, 两刀才看得清。
	_fx.append({"node": s, "t": 0.0, "life": SLASH_LIFE, "kind": "holdfade", "a0": 0.95})


## 命中爆点: 两刀交叉那一下的棱刺爆开 + 火星。
##
## ★★用户 2026-08-29 的参考里有、而旧实现**压根没有**这一段 ——
##   横斩与竖斩各画一道弧就完了, 交叉点什么都不炸, 所以"十字"没有落点、没有重量。
## 贴图不在就静默跳过(不画退化的圆环白球 —— memory [[fb-vfx-defect-families]])。
## 【瞬发激光束】—— 手半剑 084 近战携带时的普攻。
##
## ══════════════════════════════════════════════════════════════════════
##  ★★为什么是【光束】不是【飞行弹体】
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-29 指定的参考是**云顶之弈 S4 的速射火炮**(他原话"就是 S4 版本
## 射程翻倍那个"), 要"红色闪电**激光**"。
##
## 我第一版做成了**会飞的弹体**(飞 0.2~0.7 秒才到) —— 形态就是错的:
##   · 官方 wiki: "Rapid Firecannon **displays a visual beam on attack**"
##   · 用户后来发的四张实拍图: **一条细的亮电弧线**, 从攻击者直接连到目标, 瞬间出现
##   · "激光"这个词本身就是"一条线", 不是"一颗子弹"
##
## ⇒ 一条从龟连到目标的束, 出现即到位, 短促闪一下就收。
##
## ★素材是**新做的**(`eq084-beam.png`, 6 帧逐帧) —— 不复用现成的 `fx-energy-beam.png`。
##   用户 2026-08-03 的铁律: 新内容一律新素材。我差点又破一次, 被他当场拦下。
##
## ★逐帧: 每帧整条束上下抖 + 亮度沿程流动 ⇒ 读成"电在束里跑", 不是一张静图。
func cross_beam(u: Dictionary, tgt: Dictionary) -> void:
	if not _has_world() or not ResourceLoader.exists(TEX_BEAM):
		return
	var t: Texture2D = load(TEX_BEAM)
	if t == null:
		return
	var a2: Vector2 = u["pos"]
	var b2: Vector2 = tgt["pos"]
	var seg: Vector2 = b2 - a2
	if seg.length() < 1.0:
		return
	## 束贴在龟胸口高度, 顺着连线铺开(世界坐标顶点, 与斩击同一条路 —— 方向不可能不准)
	var mi := _quad_along(a2, b2, BEAM_HALF_W, GunEqVfx.body_mid_h(u), t,
		Color(1, 1, 1, 1))
	if mi == null:
		return
	## 多帧: `_quad_along` 建的是 MeshInstance3D, 帧靠改材质的 UV 偏移走
	var mat := mi.material_override as StandardMaterial3D
	if mat != null:
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD      # 激光是发光体
		var nf: int = maxi(1, int(t.get_width() / maxi(1, t.get_height() * BEAM_ASPECT)))
		mat.uv1_scale = Vector3(1.0 / float(nf), 1.0, 1.0)
	_adopt(mi, "beam")
	## 短促: 弹入即满亮, 最后一小段收 —— 激光是"闪一下", 不是慢慢淡
	_fx.append({"node": mi, "t": 0.0, "life": BEAM_SEC, "kind": "beamframe",
		"tex": t, "mat": mat})


func cross_burst(u: Dictionary, at2d: Vector2) -> void:
	if not _has_world() or not ResourceLoader.exists(TEX_BURST_V2):
		return
	var t: Texture2D = load(TEX_BURST_V2)
	if t == null:
		return
	var fh: int = maxi(1, t.get_height())
	var s := _board(t, at2d, GunEqVfx.body_mid_h(u), BURST_SIZE, Color(1, 1, 1, 1.0), 8)
	s.hframes = maxi(1, int(t.get_width() / fh))
	s.frame = 0
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = (BURST_SIZE * battle.WS) / float(fh)
	_adopt(s, "burst")
	_fx.append({"node": s, "t": 0.0, "life": 0.34, "kind": "holdfade", "a0": 1.0})


## 剑波: 沿 dir 匀速推进, 位置由 wave_pos() 给出(与结算侧同一个 WAVE_SPD)。
func cross_wave(u: Dictionary, org: Vector2, dir: Vector2, seg: int) -> void:
	if not _has_world():
		return
	var col: Color = Color(0.74, 0.86, 1.0) if seg == 2 else Color(1.0, 0.9, 0.7)
	var wide: bool = seg == 2
	var _wanim: bool = ResourceLoader.exists(TEX_WAVE_V2)
	var _wtex: Texture2D = load(TEX_WAVE_V2) if _wanim else cross_wave_tex()
	var _wsize: float = 250.0 if wide else 110.0
	var s := _board(_wtex, org, GunEqVfx.body_mid_h(u),
		_wsize, Color(col.r, col.g, col.b, 0.9), 7)
	if _wanim:
		var _wfh: int = maxi(1, _wtex.get_height())
		s.hframes = maxi(1, int(_wtex.get_width() / _wfh))
		s.frame = 0
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.modulate = Color(1, 1, 1, 0.9)
		s.pixel_size = (_wsize * battle.WS) / float(_wfh)
	## ★★剑波必须【按行进方向转】。旧代码一行 roll 都没有 —— 纯 billboard。
	##   旧素材是块近似对称的圆坨, 转不转看不出来; 2026-08-29 把它弯成了
	##   **尖端在后、弧形前缘在前**的扇面(用户:「前部分是弯的」)之后,
	##   方向就成了硬需求: 往左飞的波会把弧指向右。
	## ★素材自己的朝向就是 +x(弯弧时圆心放在 -x 侧、前缘落在最大 x),
	##   所以不像斩击那张需要再扣一个素材角。
	if _wanim:
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		s.basis = ArcaneEqVfx.face_basis(ArcaneEqVfx.cam_forward_of(battle), dir_to_roll(dir))
		s.set_meta("wave_roll", dir_to_roll(dir))
	_adopt(s, "wave")
	_fx.append({"node": s, "t": 0.0, "life": 0.78, "kind": "wave", "org": org, "dir": dir,
		"h": GunEqVfx.body_mid_h(u)})


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
		var sp3: Sprite3D = n
		# 挡下一击的闪白: 每帧衰减, 叠在常驻 alpha 上(不改结构, 只加一个通道)
		g["flash"] = maxf(0.0, float(g.get("flash", 0.0)) - delta * 5.0)
		var fl: float = float(g["flash"])
		sp3.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(Color(2.2, 2.4, 1.6, 1.0), fl)
		sp3.modulate.a = clampf(GUARD_A0 + (GUARD_A1 - GUARD_A0) * a + 0.42 * fl, 0.0, 1.0)
		# ★"举"这个动作: 高度随同一条临界阻尼曲线从低位抬到位(旧版只有 alpha 在张)
		var fx2: float = float(g.get("face", 1.0))
		var top: float = float(uu.get("height", 1.2)) + 0.4
		sp3.position = battle._world_pos(Vector2(uu["pos"]) + Vector2(GUARD_OFF_PX * fx2, 0.0),
			top - GUARD_RISE_M * (1.0 - a))
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
		## ★多帧贴图: 按 x 把整段动画播一遍(不循环) —— 一刀就该只挥一次。
		##   放在 kind 分支【之外】: 任何一类特效换成动画素材都自动逐帧播,
		##   不用每次回来开一次闸(猎人箭矢就是漏开闸, 挂了 4 帧一帧没动过)。
		if n is Sprite3D and int((n as Sprite3D).hframes) > 1:
			var _nf: int = int((n as Sprite3D).hframes)
			(n as Sprite3D).frame = clampi(int(x * float(_nf)), 0, _nf - 1)
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
			"beamframe":
				## 光束逐帧: 改材质 UV 偏移切帧(MeshInstance3D 没有 hframes)。
				## 亮度: 前 70% 满亮, 最后收 —— 与刀光同一条 holdfade 口径。
				var _m = f.get("mat", null)
				if _m is StandardMaterial3D:
					var _tt: Texture2D = f["tex"]
					var _nf: int = maxi(1, int(_tt.get_width() / maxi(1, _tt.get_height() * BEAM_ASPECT)))
					var _fi: int = clampi(int(x * float(_nf)), 0, _nf - 1)
					(_m as StandardMaterial3D).uv1_offset = Vector3(float(_fi) / float(_nf), 0, 0)
				_set_a(n, clampf((1.0 - x) / 0.30, 0.0, 1.0))
			"suck":
				## 蓄力: 剑气点从 `from` 收到 `org`。
				## ★位置用 ease-in(x²) —— 匀速收看着像"飘过去", 加速收才像"被吸住";
				##   亮度**先升后收**(0→满在前 35%, 之后维持到最后一小段才灭),
				##   不做"一出生就线性淡出"(那个病本文件已记过四次)。
				var sp2: Vector2 = (f["from"] as Vector2).lerp(f["org"] as Vector2, x * x)
				(n as Sprite3D).position = battle._world_pos(sp2, float(f["h"]))
				_set_a(n, clampf(x / 0.35, 0.0, 1.0) * clampf((1.0 - x) / 0.22, 0.0, 1.0))
			"holdfade":
				# ★前 70% 满亮, 最后 30% 才收 —— 线性淡出会让效果大半辈子处在半亮以下,
				#   实拍量到贝壳弧主体只有 RGB(42,53,55) 而地板是 (9,10,16)。
				# ★`t` 可以是**负数**(逐枚错开点亮): 还没轮到就完全不画,
				#   否则 x 被 clampf 钳在 0 ⇒ alpha 满 ⇒ 5 枚还是一次糊上去, 错开等于没做。
				if float(f["t"]) < 0.0:
					_set_a(n, 0.0)
				else:
					_set_a(n, float(f.get("a0", 1.0)) * clampf((1.0 - x) / 0.30, 0.0, 1.0))
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
