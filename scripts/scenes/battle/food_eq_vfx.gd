class_name FoodEqVfx
extends RefCounted
## food_eq_vfx.gd — 食物四件新装备(069/070/071/072)的演出层
## (方案书 docs/plans/20260805-装备逐件重做.md §0.5 · 实装契约 docs/plans/20260805-实装契约.md §6)
##
## ══════════════════════════════════════════════════════════════════════
##  ★判据: 与 shockwave_vfx.gd 同一条路 —— 用【可验证的物理规律】当形态的事实源
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-05:「要触手水准, 除非你用 pixel 的特效动画能做完美」。
## 触手那套的第一条(逐帧量参考做成包络表)**这批无从下手** —— 一件参考素材都没有。
## 所以照怒气冲击波的替代路: **形态全部来自闭式解**, 门禁验的是这些解的【性质】
## (尺度不变性 / 极值位置 / 二阶差分恒定 / 对数减缩), 手调缓动一条都过不了。
##
## ── ① 069 三块糖糕: 等分圆轨道 + 真抛物线送入口 ──────────────────────
##   轨道: θᵢ(t) = ω·t + i·2π/3 ⇒ **任意时刻三块两两角距恒为 120°**(与 t 无关)。
##   ★这不是美术摆位: 三体等分圆轨道是"剩几块一眼能数出来"的唯一稳定构型 ——
##     随机摆位在旋转时会互相遮挡, 数不清还剩几块(用户要求"吃掉的过程要可见")。
##   送入口: 常重力抛体 y(x) = h₀ + v₀x − ½gx²。
##   ★可验证性质(门禁): **等步长采样的二阶差分恒为 −g·Δx²**, 与采样位置无关。
##     任何 ease_in/out/back 缓动的二阶差分都随位置变 ⇒ 一测就露。
##
## ── ② 070 溅射冠: Worthington 冠状水花(空腔自相似) ────────────────────
##   重物砸进液面 ⇒ Rayleigh 空腔自相似解 **R(t) ∝ t^(1/2)** ⇒ 归一 R̂(x) = √x。
##   ★可验证性质: **尺度不变性 R̂(4x)/R̂(x) ≡ 2**, 与 x 无关。
##   冠壁的液滴走弹道 ⇒ 高度 ĥ(x) = 4x(1−x): 极大值恰好 1.0 恰在 **x = 0.5**,
##   且二阶差分恒定(纯弹道)。⇒ "冠"是先冲高再落回, 不是单调淡出。
##
## ── ③ 071 奶油壳破裂: Taylor–Culick 边缘回缩 ───────────────────────────
##   液膜上开一个洞, 洞缘以**恒定速度** V_TC = √(2σ/ρh) 回缩(1959 年的经典结果):
##     · 洞半径 **r(t) = V·t —— 严格线性**(二阶差分恒 0)
##     · 回缩边缘把扫过的膜全卷进去 ⇒ 卷入质量 **m(t) ∝ r² ∝ t²**(m(2x)/m(x) ≡ 4)
##   ★这两条一起决定观感: 洞匀速张开、边缘却越来越粗重 —— 这正是奶油/牛奶膜破裂的样子,
##     而"环扩散 + 淡出"给不出"边缘变粗"这一半。
##   壳面本身的涟漪走**毛细波色散** ω² = (σ/ρ)k³ ⇒ 相速 c(k) ∝ √k:
##   ★可验证性质: **c(4k)/c(k) ≡ 2** ⇒ 短波跑得快, 壳面纹路会自动拉开层次。
##
## ── ④ 072 铁皮盒开合 / 分裂弹出 ────────────────────────────────────────
##   盒盖 = 铰链上的**扭转弹簧-惯量二阶系统**的阶跃响应(欠阻尼):
##     θ̂(x) = 1 − e^(−ζωx)[cos ω_d x + (ζω/ω_d) sin ω_d x],  ω_d = ω√(1−ζ²)
##   ★可验证性质: **对数减缩** —— 相邻两次过冲峰值之比恒为 exp(−2πζ/√(1−ζ²)),
##     与是第几个峰无关。这条是"盖子啪一声合上还弹两下"的物理来源, 手调补不出。
##   分裂弹出: 抛体 + **恢复系数 e** 的多次弹跳 ⇒ 相邻弹跳高度之比恒为 e²,
##   落地那一下的形变量 ∝ 触地速度(动量守恒), 不是拍脑袋的 scale。
##
## ── 技术路线 ──────────────────────────────────────────────────────────
## 程序化几何(`ArrayMesh`/`SurfaceTool`) + `VfxTex` 逐像素现算纹理, **零素材**。
## 用户素材铁律(新内容一律新素材)下, 程序化不产出图、不吃这条约束;
## **一张别件装备的现成立绘都没有复用**。
##
## ⚠ 朝向坑(memory [[fb-axis-y-plus-rotation-cancels]]): 贴地几何一律**直接建世界顶点**
##   (y = GROUND_Y 的水平面), 不用 `Sprite3D.axis` + `rotation.x` 那对会互相抵消的组合。
##   门禁量 |三角面法线·上| ≈ 1.000。

# ══════════════════════════════════════════════════════════════════
#  §物理常数 —— 闭式解的参数, 不是调出来的观感系数
# ══════════════════════════════════════════════════════════════════

## 贴地几何离地高度(米)。地板在 y=0, 抬一点免 z-fighting(同 shockwave_vfx)。
const GROUND_Y := 0.06
## 贴地环的经向分段
const RING_LON := 48

## ── 069 ──
## 三块糖糕 = 三体等分圆轨道
const CAKE_N := 3
## 轨道角速度(rad/s)。慢到能看清"还剩几块"
const CAKE_OMEGA := 1.15
## 轨道半径(码)与悬停高度(米)
const CAKE_ORBIT_PX := 46.0
const CAKE_HOVER_H := 1.55
## 送入口的抛物线: 归一重力(高度单位 = 起始悬停高)。
## ★ v0 = 1.0 / g = 2.0 ⇒ 顶点在 x=0.5、抬升 0.25, 终点 x=1 回到 0 —— 一条完整抛物线。
const BITE_V0 := 1.0
const BITE_G := 2.0
const BITE_SEC := 0.42

## ── 070 ──
## Worthington 冠: 半径 √x, 冠高 4x(1−x)
const CROWN_SEC := 0.46
## 冠壁的经向分段
const CROWN_LON := 32

## ── 071 ──
## Taylor–Culick: 归一后洞缘速度 = 1(半径严格线性)
const TC_SEC := 0.40
## 奶油壳的毛细波模数(k 越大波长越短)。相速 ∝ √k ⇒ 三层纹路自动拉开
const CREAM_MODES := [3.0, 7.0, 13.0]
## 壳面起伏的相对幅度(壳半径的比例)。三层按 1/k 递减 = 毛细波的自然谱
const CREAM_AMP := 0.055

## ── 072 ──
## 盒盖二阶系统: 阻尼比 ζ 与固有角频率 ω
## ★ζ=0.22 落在欠阻尼区(0<ζ<1) ⇒ 有过冲、有"啪嗒"回弹; ζ≥1 就没有第二个峰了
const LID_ZETA := 0.22
const LID_OMEGA := 22.0
const LID_SEC := 0.34
## 盖子张开的最大角(度)
const LID_OPEN_DEG := 78.0

## 分裂弹出: 恢复系数(相邻弹跳高度比 = e²)
const HOP_E := 0.55
const HOP_SEC := 0.62
## 弹出水平距离(码)
const HOP_DIST_PX := 92.0
## 落地形变: 触地速度 → 压扁比例的线性系数(动量 → 形变)
const HOP_SQUASH_K := 0.42

## 嘲讽环半径(码) —— ★这是【效果半径】本身, 与 072 的 550 码嘲讽同一个数。
## 与冲击波那件相反: 那件"没有 AOE 半径可言"所以演出尺寸要压着做,
## 这件的嘲讽**真的**是 550 码的范围, 画小了才是骗人。
const TAUNT_RANGE_PX := 550.0
## ── 072 出盒烟雾(2026-08-11 用户: 「护盾被打破变为本体时, 需要做个烟雾爆开特效」)──
## 烟团数 / 时长(秒) / 初速(码每秒) / 阻力时间常数 τ(秒) / 浮升(米每秒) / 初始与终末团径(码)
## ★物理: 湍流烟团被空气拖住 ⇒ 径向 r(t) = v₀·τ·(1−e^(−t/τ)) —— **减速**扩散(不是匀速环),
##   同时靠卷吸把体积撑大 ⇒ 团径 ∝ √t。这两条都是可验证性质, 门禁量真实节点:
##   · 减速: r(2Δ) / r(Δ) < 2(匀速恰为 2)  · 卷吸: d(4x)/d(x) = 2
const SMOKE_N := 12
const SMOKE_SEC := 0.62
const SMOKE_V0 := 300.0
const SMOKE_TAU := 0.16
const SMOKE_RISE := 1.35
const SMOKE_D0 := 16.0
const SMOKE_D1 := 52.0

## 蛋糕法阵半径(码), 与 072 礼盒技能的 300 码同一个数
const CAKE_FIELD_PX := 300.0
## 法阵裱花外环的波瓣数 / 辐条数 / 辐条层自旋角速度(rad/s)
## (2026-08-11 用户: 「如果是法阵你这个效果就很敷衍了」—— 素圈+8点不配叫法阵,
##  重做成: 波浪裱花外环(外沿均值仍= 300 码判定半径) + 缓旋辐条内环层 + 奶糕点缀)
const FIELD_SCALLOPS := 24
const FIELD_SPOKES := 8
const FIELD_SPIN := 0.5
## 裱花波瓣的相对振幅(±3%, 外沿均值不动 —— 判定半径不许被观感改掉)
const FIELD_WAVE_AMP := 0.03
## 溅射环半径(码), 与 070 的 250 码同一个数
const SPLASH_RANGE_PX := 250.0
## ★070 冲击环速度(码/秒) —— 视觉扩张与伤害调度共用的【同一个】常量(2026-08-11 用户:
##   「溅射范围不是250吗…主要是炸开一道环, 环碰到敌人才跳伤害」)。
##   环半径 r(t) = BRICK_WAVE_SPEED·t 恒速扩到 250 码; 圈内每个敌人的伤害延时
##   = 距离 / 同一个速度(eq_food_batch._eq_ballast_brick 的 _pending_shots 调度)
##   ⇒ 环碰到谁, 谁那一刻掉血。改这个数, 视觉与伤害一起变, 不会各错各的。
const BRICK_WAVE_SPEED := 550.0

var battle

## 网格缓存(同 shockwave_vfx: 网格可共享、材质不行 —— 材质带着这一发自己的亮度)
var _cache_ring: ArrayMesh = null
var _cache_crown: ArrayMesh = null
var _cache_scallop: ArrayMesh = null
var _cache_spoke: ArrayMesh = null

## 活动中的演出句柄(每帧 advance)
var _live: Array = []


func _init(b) -> void:
	battle = b


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等 tween(CLAUDE.md §3.5)
# ══════════════════════════════════════════════════════════════════

## 069 第 i 块糖糕在时刻 t 的轨道角。三块严格等分。
static func cake_angle(i: int, t: float) -> float:
	return t * CAKE_OMEGA + float(i) * TAU / float(CAKE_N)


## 069 送入口的抛物线高度(归一: 0 = 嘴的高度, 1 = 起始悬停高)。
## y(x) = 1 − x + [v₀x − ½gx²]  ←  前半是从悬停高直线降到嘴, 后半是抛体的抬升
## ★用 v₀=1, g=2 ⇒ 抬升项 x − x², 顶点 x=0.5 抬 0.25, x=0/1 处为 0。
static func bite_height(x: float) -> float:
	var xx: float = clampf(x, 0.0, 1.0)
	return (1.0 - xx) + (BITE_V0 * xx - 0.5 * BITE_G * xx * xx)


## 070 Worthington 冠的归一半径 R̂(x) = √x(Rayleigh 空腔自相似)。
## ★性质: R̂(k·x) = √k · R̂(x) 对任意 k、任意 x 成立(只要 k·x ≤ 1)。
static func crown_radius(x: float) -> float:
	return sqrt(clampf(x, 0.0, 1.0))


## 070 冠壁的归一高度 = 纯弹道抛物线, 极大 1.0 恰在 x = 0.5。
static func crown_height(x: float) -> float:
	var xx: float = clampf(x, 0.0, 1.0)
	return 4.0 * xx * (1.0 - xx)


## 070 冲击环半径(码), t 单位是秒: 恒速扩张、到 250 码封顶。
## ★演出缩放与伤害延时都只从这一个函数/常量出数(环到达时刻 = 伤害时刻)。
static func brick_wave_radius(t: float) -> float:
	return minf(BRICK_WAVE_SPEED * maxf(t, 0.0), SPLASH_RANGE_PX)


## 071 Taylor–Culick 洞半径: **严格线性**(边缘恒速回缩)。
static func tc_hole_radius(x: float) -> float:
	return clampf(x, 0.0, 1.0)


## 071 洞缘卷入的膜质量 ∝ 洞面积 ∝ r²。
static func tc_rim_mass(x: float) -> float:
	var r: float = tc_hole_radius(x)
	return r * r


## 071 毛细波相速(归一 σ/ρ=1): ω² = k³ ⇒ c = ω/k = √k。
static func capillary_speed(k: float) -> float:
	return sqrt(maxf(k, 0.0))


## 071 奶油壳表面在角 th、时刻 t 的相对起伏(三层毛细波叠加, 各自按 c(k)=√k 传播)。
## 幅度按 1/k 递减 = 毛细波的自然谱(短波幅度小)。
static func cream_surface(th: float, t: float) -> float:
	var s := 0.0
	for k in CREAM_MODES:
		var kk: float = float(k)
		s += (1.0 / kk) * sin(kk * th - capillary_speed(kk) * kk * t)
	return s * CREAM_AMP


## 072 盒盖的欠阻尼阶跃响应(归一: 0 = 合上, 1 = 到位)。
## θ̂(x) = 1 − e^(−ζωx)[cos ω_d x + (ζω/ω_d) sin ω_d x]
static func lid_step(x: float) -> float:
	var xx: float = maxf(x, 0.0)
	var wd: float = LID_OMEGA * sqrt(1.0 - LID_ZETA * LID_ZETA)
	var e: float = exp(-LID_ZETA * LID_OMEGA * xx)
	return 1.0 - e * (cos(wd * xx) + (LID_ZETA * LID_OMEGA / wd) * sin(wd * xx))


## 072 对数减缩 δ = 2πζ/√(1−ζ²) ⇒ **相邻两个同向峰**(相隔一个完整阻尼周期)之比 = e^(−δ)。
## ★这是二阶系统的**恒等式**, 与 ω、与是第几个峰都无关 —— 门禁直接拿它当尺子。
## ⚠ 别写成 e^(−δ/2): 那是【相邻两个反向极值】(相隔半周期)之比。
##   我第一版就写成了 /2, 门禁量到 0.2424 而公式给 0.4924 —— 正好差一个平方, 一测就红。
static func lid_peak_ratio() -> float:
	return exp(-TAU * LID_ZETA / sqrt(1.0 - LID_ZETA * LID_ZETA))


## 072 分裂盒弹出的归一高度: 抛体 + 恢复系数 e 的连续弹跳。
## 第 n 段的峰高 = e^(2n), 第 n 段时长 = e^n(自由落体时间 ∝ √h)。
static func hop_height(x: float) -> float:
	var xx: float = clampf(x, 0.0, 1.0)
	# 归一化: 各段时长按 e^n 递减, 总时长 = Σ e^n
	var total := 0.0
	for n in range(4):
		total += pow(HOP_E, float(n))
	var acc := 0.0
	for n in range(4):
		var seg: float = pow(HOP_E, float(n)) / total
		if xx <= acc + seg or n == 3:
			var lp: float = clampf((xx - acc) / maxf(seg, 1e-6), 0.0, 1.0)
			return pow(HOP_E, 2.0 * float(n)) * 4.0 * lp * (1.0 - lp)
		acc += seg
	return 0.0


## 072 落地形变: 压扁比例 ∝ 触地速度。第 n 次触地速度 ∝ e^n。
static func hop_squash(n: int) -> float:
	return HOP_SQUASH_K * pow(HOP_E, float(maxi(n, 0)))


## 070 灰色血条在【血条局部坐标】里的位置与宽度。
## 返回 [x0, w]: 从"当前生命"的右端起画, 长度 = 灰条 / 最大生命 —— 语义正好是
## "已经掉了、但这一段会回来"。★钳在血条右边界内: 灰条可能比已损失生命还多。
static func grey_rect(bar_w: float, hp: float, maxhp: float, grey: float) -> Array:
	var m: float = maxf(maxhp, 1.0)
	var x0: float = bar_w * clampf(hp / m, 0.0, 1.0)
	var w: float = bar_w * clampf(grey / m, 0.0, 1.0)
	return [x0, minf(w, maxf(0.0, bar_w - x0))]


## 效果半径(码) → 世界半径(米)。★"尺子要匹配被测概念": 嘲讽/法阵/溅射这三个环
##   画的就是效果半径本身, 门禁拿同一个换算比对, 不许各算各的。
func range_m(px: float) -> float:
	return px * float(battle.WS)


# ══════════════════════════════════════════════════════════════════
#  §几何 —— 程序化 ArrayMesh, 零素材
# ══════════════════════════════════════════════════════════════════

## 单位半径的贴地环(内沿 RING_IN 渐隐, 外沿硬边)
static func _build_ring_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		for q in [[0.86, 0.0, 0.97, 1.0], [0.97, 1.0, 1.0, 0.55]]:
			var ri: float = float(q[0])
			var ai: float = float(q[1])
			var ro: float = float(q[2])
			var ao: float = float(q[3])
			_quad(st, ri, ai, ro, ao, t0, t1)
	st.commit(mesh)
	return mesh


## 单位半径的"冠"(Worthington crown): 一圈朝上外翻的壁, 底在地面、顶在 y=1。
## ★顶点的 y 由调用方用 crown_height 缩放 —— 网格本身只是单位形状。
static func _build_crown_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(CROWN_LON):
		var t0: float = float(j) / float(CROWN_LON) * TAU
		var t1: float = float(j + 1) / float(CROWN_LON) * TAU
		# 冠壁: 底沿(r=0.88, y=0, 亮) → 顶沿(r=1.0, y=1, 透) —— 外翻
		var a := [Vector3(0.88 * cos(t0), GROUND_Y, 0.88 * sin(t0)), Color(1, 1, 1, 1.0)]
		var b := [Vector3(cos(t0), 1.0, sin(t0)), Color(1, 1, 1, 0.0)]
		var c := [Vector3(cos(t1), 1.0, sin(t1)), Color(1, 1, 1, 0.0)]
		var d := [Vector3(0.88 * cos(t1), GROUND_Y, 0.88 * sin(t1)), Color(1, 1, 1, 1.0)]
		_tri(st, a, b, c)
		_tri(st, a, c, d)
	st.commit(mesh)
	return mesh


## 072 法阵·裱花波浪外环: 外沿 r = 1 + AMP·sin(Nθ)(奶油挤花边), 内沿 0.88 渐隐。
## ★外沿【均值】= 1.0 ⇒ 缩放到 rm 后就是 300 码判定半径本身, 波瓣只是 ±3% 的装饰起伏。
static func _build_scallop_ring_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 96
	for j in range(seg):
		var t0: float = float(j) / float(seg) * TAU
		var t1: float = float(j + 1) / float(seg) * TAU
		var o0: float = 1.0 + FIELD_WAVE_AMP * sin(FIELD_SCALLOPS * t0)
		var o1: float = 1.0 + FIELD_WAVE_AMP * sin(FIELD_SCALLOPS * t1)
		var a := [Vector3(0.88 * cos(t0), GROUND_Y, 0.88 * sin(t0)), Color(1, 1, 1, 0.0)]
		var b := [Vector3(o0 * cos(t0), GROUND_Y, o0 * sin(t0)), Color(1, 1, 1, 1.0)]
		var c := [Vector3(o1 * cos(t1), GROUND_Y, o1 * sin(t1)), Color(1, 1, 1, 1.0)]
		var d := [Vector3(0.88 * cos(t1), GROUND_Y, 0.88 * sin(t1)), Color(1, 1, 1, 0.0)]
		_tri(st, a, b, c)
		_tri(st, a, c, d)
	st.commit(mesh)
	return mesh


## 072 法阵·旋转辐条层: 0.55~0.60 内环带 + 8 根往外收细的辐条(0.60→0.94)。
## 整个节点绕 y 缓旋(FIELD_SPIN) —— 法阵的"活"就在这一层, 素圈是转不起来的。
static func _build_spoke_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		_quad(st, 0.55, 0.30, 0.575, 0.85, t0, t1)
		_quad(st, 0.575, 0.85, 0.60, 0.30, t0, t1)
	for k in range(FIELD_SPOKES):
		var th: float = float(k) * TAU / float(FIELD_SPOKES)
		var a := _flat_vert(0.60, th - 0.050, 0.85)
		var b := _flat_vert(0.94, th - 0.018, 0.25)
		var c := _flat_vert(0.94, th + 0.018, 0.25)
		var d := _flat_vert(0.60, th + 0.050, 0.85)
		_tri(st, a, b, c)
		_tri(st, a, c, d)
	st.commit(mesh)
	return mesh


static func _quad(st: SurfaceTool, ri: float, ai: float, ro: float, ao: float, t0: float, t1: float) -> void:
	var a := _flat_vert(ri, t0, ai)
	var b := _flat_vert(ro, t0, ao)
	var c := _flat_vert(ro, t1, ao)
	var d := _flat_vert(ri, t1, ai)
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func _flat_vert(r: float, th: float, a: float) -> Array:
	return [Vector3(r * cos(th), GROUND_Y, r * sin(th)), Color(1, 1, 1, a)]


static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


## 加性发光材质(零素材, 顶点色当亮度)。
## ⚠ 一材质一节点、走 material_override —— `set_surface_override_material` 在
##   headless dummy renderer 下每设一次刷一条 `Parameter "material" is null.`
##   (shockwave_vfx.gd 那段血泪注释, 实测过)。
static func _mat(no_depth: bool, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = no_depth
	m.render_priority = prio   # ⚠ render_priority 在【材质】上, MeshInstance3D 没这个属性
	m.albedo_color = Color(1, 1, 1, 0)
	return m


func _ring_mesh() -> ArrayMesh:
	if _cache_ring == null:
		_cache_ring = _build_ring_mesh()
	return _cache_ring


func _crown_mesh() -> ArrayMesh:
	if _cache_crown == null:
		_cache_crown = _build_crown_mesh()
	return _cache_crown


func _scallop_mesh() -> ArrayMesh:
	if _cache_scallop == null:
		_cache_scallop = _build_scallop_ring_mesh()
	return _cache_scallop


func _spoke_mesh() -> ArrayMesh:
	if _cache_spoke == null:
		_cache_spoke = _build_spoke_mesh()
	return _cache_spoke


func _mk_node(mesh: ArrayMesh, mat: StandardMaterial3D, org: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = org
	if is_instance_valid(battle._world):
		battle._world.add_child(mi)
	return mi


func _mk_sprite(tex: Texture2D, pos2d: Vector2, h: float, size_px: float, col: Color) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = col
	s.pixel_size = (size_px * float(battle.WS)) / float(maxi(1, tex.get_height()))
	s.position = battle._world_pos(pos2d, h)
	if is_instance_valid(battle._world):
		battle._world.add_child(s)
	return s


# ══════════════════════════════════════════════════════════════════
#  §069 珊瑚糖糕 —— 头顶三块糕(等分轨道) + 吃掉那一下的抛物线
# ══════════════════════════════════════════════════════════════════

## 建/更新头顶那三块糕。`left` = 还剩几块(0~3) ⇒ **剩几块就画几块**, 用户要的"可见"。
## 返回句柄(存在 eq_state 里), 由 `cake_orbit_update` 每帧推进。
## 像素糖糕贴图(11×10): 樱桃顶 + 奶油带 + 粉霜(带糖屑) + 珊瑚底。静态缓存, NEAREST 保像素感。
## ★旧的 15 码淡粉圆点在实拍里只有 ~5px 半透明 —— 「剩几块糖」这个核心读数等于隐形。
static var _cake_tex_cache: ImageTexture = null


static func _cake_tex() -> ImageTexture:
	if _cake_tex_cache != null:
		return _cake_tex_cache
	var img := Image.create(11, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cherry := Color(0.90, 0.15, 0.25)
	var cream := Color(1.0, 0.95, 0.86)
	var pink := Color(1.0, 0.62, 0.75)
	var coral := Color(0.95, 0.45, 0.40)
	var dark := Color(0.78, 0.34, 0.32)
	img.set_pixel(5, 0, cherry)
	for x in range(4, 7): img.set_pixel(x, 1, cherry)
	for x in range(2, 9): img.set_pixel(x, 2, cream)
	for x in range(1, 10):
		img.set_pixel(x, 3, cream if x % 3 == 0 else pink)
		img.set_pixel(x, 4, pink)
		img.set_pixel(x, 5, pink if x % 4 != 1 else cream)
	for x in range(1, 10):
		img.set_pixel(x, 6, coral)
		img.set_pixel(x, 7, coral)
	for x in range(2, 9):
		img.set_pixel(x, 8, dark)
	for x in range(3, 8):
		img.set_pixel(x, 9, dark)
	_cake_tex_cache = ImageTexture.create_from_image(img)
	return _cake_tex_cache


func cake_orbit_make(u: Dictionary, left: int) -> Dictionary:
	var tex: Texture2D = _cake_tex()
	var h := {"spr": [], "t": 0.0, "left": clampi(left, 0, CAKE_N)}
	for i in range(CAKE_N):
		var s := _mk_sprite(tex, u["pos"], CAKE_HOVER_H, 24.0, Color(1, 1, 1, 1))
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		(h["spr"] as Array).append(s)
	cake_orbit_update(u, h, 0.0)
	return h


## 每帧: 三块沿等分圆轨道旋转, 已吃掉的隐藏。**纯同步**, 门禁可直接喂 delta。
func cake_orbit_update(u: Dictionary, h: Dictionary, delta: float) -> void:
	if h.is_empty():
		return
	h["t"] = float(h.get("t", 0.0)) + delta
	var t: float = float(h["t"])
	var left: int = int(h.get("left", 0))
	var arr: Array = h.get("spr", [])
	for i in range(arr.size()):
		var s = arr[i]
		if not is_instance_valid(s):
			continue
		s.visible = i < left
		var a: float = cake_angle(i, t)
		var off := Vector2(cos(a), sin(a) * 0.45) * CAKE_ORBIT_PX
		s.position = battle._world_pos(u["pos"] + off, CAKE_HOVER_H + 0.07 * sin(t * 3.0 + float(i) * 2.1))


func cake_orbit_free(h: Dictionary) -> void:
	for s in h.get("spr", []):
		if is_instance_valid(s):
			s.queue_free()
	h["spr"] = []


## 吃掉第 idx 块: 那一块沿**真抛物线**飞进嘴里(常重力), 同时缩小。
## ★门禁不等这条 tween —— 形状由 `bite_height` 给, 门禁直接采样那个纯函数。
func cake_bite_fx(u: Dictionary, idx: int) -> void:
	if not is_instance_valid(battle._world):
		return
	var tex: Texture2D = _cake_tex()
	var a: float = cake_angle(idx, 0.0)
	var from2: Vector2 = u["pos"] + Vector2(cos(a), sin(a) * 0.45) * CAKE_ORBIT_PX
	var s := _mk_sprite(tex, from2, CAKE_HOVER_H, 24.0, Color(1, 1, 1, 1))
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_live.append({"kind": "bite", "spr": s, "unit": u, "from": from2, "t": 0.0, "dur": BITE_SEC})


# ══════════════════════════════════════════════════════════════════
#  §070 压舱咸鱼砖 —— 溅射冠 + 灰色血条
# ══════════════════════════════════════════════════════════════════

## 以命中点为心的 Worthington 冠(半径 √x · 冠高 4x(1−x)), 半径落在 250 码。
func splash_crown(pos2d: Vector2) -> Dictionary:
	if not is_instance_valid(battle._world):
		return {}
	## 冠只是"砸出水花"的落点读数(70 码水花本体); 【250 码溅射范围】由 brick_wave
	## 冲击环诚实表达 —— 环恒速扩到 250 码, 环碰到谁谁那一刻掉血(2026-08-11 用户拍板)。
	var rm: float = range_m(70.0)
	var crown := _mk_node(_crown_mesh(), _mat(true, 10), battle._world_pos(pos2d, 0.0))
	var ring := _mk_node(_ring_mesh(), _mat(true, 11), battle._world_pos(pos2d, 0.0))
	var h := {"kind": "crown", "crown": crown, "ring": ring, "r_m": rm, "t": 0.0, "dur": CROWN_SEC}
	crown_apply_at(h, 0.0)
	_live.append(h)
	return h


## ★整个冠形态的单一事实源 —— 演出与门禁都只读这一个函数(不许抄第二遍)。
func crown_apply_at(h: Dictionary, x: float) -> void:
	if h.is_empty():
		return
	var rm: float = float(h["r_m"])
	var r: float = maxf(crown_radius(x) * rm, 1e-4)
	var hh: float = maxf(crown_height(x) * rm * 0.55, 1e-4)
	var fade: float = 1.0 - clampf(x, 0.0, 1.0)
	var cw = h.get("crown", null)
	if is_instance_valid(cw):
		cw.scale = Vector3(r, hh, r)
		(cw.material_override as StandardMaterial3D).albedo_color = Color(0.98, 0.86, 0.62, 0.75 * fade)
	var rg = h.get("ring", null)
	if is_instance_valid(rg):
		rg.scale = Vector3(r, r, r)
		(rg.material_override as StandardMaterial3D).albedo_color = Color(0.86, 0.72, 0.48, 0.85 * fade)


## 070 冲击环: 从砸点炸开、恒速扩到 250 码(= 真实溅射半径, 画小了才是骗人)。
## ★环半径只读 brick_wave_radius —— 伤害调度(eq_food_batch)用同一个常量,
##   环扫到哪个敌人, 哪个敌人那一刻跳伤害。
func brick_wave(pos2d: Vector2) -> Dictionary:
	if not is_instance_valid(battle._world):
		return {}
	var ring := _mk_node(_ring_mesh(), _mat(true, 11), battle._world_pos(pos2d, 0.0))
	var h := {"kind": "bwave", "ring": ring, "t": 0.0, "dur": SPLASH_RANGE_PX / BRICK_WAVE_SPEED}
	bwave_apply_at(h, 0.0)
	_live.append(h)
	return h


## ★冲击环形态的单一事实源 —— 演出与门禁都只读这一个函数。
## 前 78% 满亮(fb-vfx-defect-families 淡出病: 短命特效不许一出生就线性淡出), 尾段收干净。
func bwave_apply_at(h: Dictionary, x: float) -> void:
	if h.is_empty():
		return
	var rg = h.get("ring", null)
	if not is_instance_valid(rg):
		return
	var xx: float = clampf(x, 0.0, 1.0)
	var r: float = maxf(range_m(brick_wave_radius(xx * float(h.get("dur", 0.45)))), 1e-4)
	rg.scale = Vector3(r, r, r)
	var fade: float = 1.0 - smoothstep(0.78, 1.0, xx)
	(rg.material_override as StandardMaterial3D).albedo_color = Color(0.99, 0.86, 0.55, 0.92 * fade)


## 灰色血条: 直接挂在【那个单位自己的血条 Control】上, 玩家一眼看懂"这段会回来"。
## ★不改 battle_render.gd(主会话的地盘) —— 这里是运行时往 bar_root 里加一个 ColorRect,
##   位置/宽度由纯函数 `grey_rect` 算, 门禁量的是**真实节点**的 size/position, 不是公式。
func grey_bar_update(u: Dictionary, grey: float) -> void:
	var root = u.get("bar_root", null)
	if not is_instance_valid(root):
		return
	var rect = u.get("_grey_rect", null)
	if not is_instance_valid(rect):
		rect = ColorRect.new()
		rect.name = "GreyHp"
		## ★深灰(2026-08-11 用户: 「血条的灰我要的是深灰色的」), 不是浅银灰
		rect.color = Color(0.32, 0.33, 0.36, 0.95)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.z_index = 3
		root.add_child(rect)
		u["_grey_rect"] = rect
	var g: Array = grey_rect(float(battle.BAR_W), float(u["hp"]), float(u["maxHp"]), grey)
	rect.position = Vector2(float(g[0]), 8.0)
	rect.size = Vector2(float(g[1]), float(battle.BAR_H))
	rect.visible = grey > 0.5 and u.get("alive", false)


# ══════════════════════════════════════════════════════════════════
#  §071 炼乳罐 —— 奶油壳(毛细波) + Taylor–Culick 破膜
# ══════════════════════════════════════════════════════════════════

## 破膜时洞缘甩出的奶油滴颗数(等角确定性摆, 无 randf —— rng_discipline 门禁扫裸随机)
const CREAM_DROP_N := 12

## 奶油壳的像素立绘(26×16): 三个圆鼓的奶油峰 + 底沿垂滴 —— 要读得出"这只龟被奶油裹着"。
## ★为什么是手画像素而不是发光贴图: 旧版壳用 `VfxTex._make_glow_texture()`(软发光球),
##   2026-08-11 实拍是一坨罩在龟下半身的灰白雾球 —— 正是用户明令禁止的「程序生成白球敷衍」,
##   而且读起来像影子/落地光, 完全不是"奶油"。069 的糖糕走过同一条路(淡粉圆点→11×10 像素糕),
##   这里照同一个修法: 逐像素画真形状, NEAREST 保像素感。静态缓存。
static var _cream_shell_tex_cache: ImageTexture = null


static func _cream_shell_tex() -> ImageTexture:
	if _cream_shell_tex_cache != null:
		return _cream_shell_tex_cache
	var W := 26
	var H := 14
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# ── 第一遍: 形状掩码 ——【底沿垂坠的圆瓣】是奶油的签名笔画。
	#   ★为什么签名在底沿不在顶沿(2026-08-11 第一版实拍教训): 壳画在龟身前下方,
	#   顶沿那排奶油峰整个被龟壳挡住 ⇒ 剩下"平顶白板 + 三条直腿", 被读成【桌子】。
	#   俯拍机位下永远露在外面的是底沿 ⇒ 把"往下淌的圆瓣"画在那里, 挡不住。
	var mask: Array = []
	var lobes := [Vector3(3.5, 8.5, 2.3), Vector3(8.0, 10.0, 2.6), Vector3(13.0, 8.8, 2.2),
		Vector3(18.5, 10.5, 2.8), Vector3(23.0, 8.6, 2.2)]   # (cx, cy, r) 五瓣, 深浅错落
	for y in range(H):
		var row: Array = []
		for x in range(W):
			var inside: bool = (y >= 3 and y <= 7 and x >= 0 and x <= 25)   # 主体环带
			for lb in lobes:
				if Vector2(float(x), float(y)).distance_to(Vector2(lb.x, lb.y)) <= lb.z:
					inside = true
			row.append(inside)
		mask.append(row)
	# ── 第二遍: 上光下影 + 贴边描暗(黑场/亮龟前都读得出轮廓) ──
	for y in range(H):
		for x in range(W):
			if not bool((mask[y] as Array)[x]):
				continue
			var col := Color(1.00, 0.95, 0.86)          # 奶油本体
			if y <= 3: col = Color(1.00, 0.99, 0.95)    # 顶带受光
			elif y >= 10: col = Color(0.90, 0.77, 0.58) # 垂瓣尖最深
			elif y >= 8: col = Color(0.95, 0.85, 0.68)  # 下腹阴影
			var edge := false
			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + off.x
				var ny: int = y + off.y
				if nx < 0 or nx >= W or ny < 0 or ny >= H or not bool((mask[ny] as Array)[nx]):
					edge = true
			if edge:
				col = Color(col.r * 0.80, col.g * 0.78, col.b * 0.72)
			img.set_pixel(x, y, col)
	_cream_shell_tex_cache = ImageTexture.create_from_image(img)
	return _cream_shell_tex_cache


## 奶油滴(7×8 泪滴): 破膜时从洞缘甩出来的那几颗。静态缓存。
static var _cream_drop_tex_cache: ImageTexture = null


static func _cream_drop_tex() -> ImageTexture:
	if _cream_drop_tex_cache != null:
		return _cream_drop_tex_cache
	var img := Image.create(7, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(8):
		for x in range(7):
			var inside: bool = Vector2(float(x), float(y)).distance_to(Vector2(3.0, 4.6)) <= 2.6
			if x == 3 and y >= 1 and y <= 2: inside = true   # 上头的小尖尾巴(泪滴形)
			if not inside:
				continue
			var col := Color(1.00, 0.96, 0.88) if y <= 4 else Color(0.92, 0.80, 0.62)
			img.set_pixel(x, y, col)
	_cream_drop_tex_cache = ImageTexture.create_from_image(img)
	return _cream_drop_tex_cache


## 给 `u` 套一层奶油壳(像素奶油裹层, 跟随单位)。壳面按毛细波起伏(三层, c(k)=√k)。
func cream_shell_make(u: Dictionary) -> Dictionary:
	if not is_instance_valid(battle._world):
		return {}
	# 30 码高 ⇒ 26:14 宽高比下约 56 码宽, 正好裹住 ~44 码的龟身下半 —— 头探出来, 读作"被裹住"
	var s := _mk_sprite(_cream_shell_tex(), u["pos"], 0.45, 30.0, Color(1, 1, 1, 0.93))
	var h := {"spr": s, "t": 0.0}
	battle._follow_vfx.append({"spr": s, "unit": u, "h": 0.45, "pulse": false})
	return h


## 壳面每帧的呼吸: 用毛细波叠加当缩放调制 —— 短波跑得快 ⇒ 纹路层次自动拉开。
## ★★壳的尺寸【只有呼吸, 不随盾量/受击缩小】(2026-08-11 用户钉死:「不要做那种被打缩小的」):
##   盾从满打到 1 点, 壳都保持全尺寸(呼吸幅度 ±3% 上下); 破的那一刻走 cream_burst 的
##   【炸开】路径(TC 破膜 + 甩奶油滴), 绝不是逐渐瘪掉。这里的 k 只依赖时间 t,
##   任何人往这条里引入"盾量→scale"的耦合都会被门禁 ⑦-6l/6m 那组抓红。
func cream_shell_update(h: Dictionary, delta: float) -> void:
	if h.is_empty():
		return
	h["t"] = float(h.get("t", 0.0)) + delta
	var s = h.get("spr", null)
	if not is_instance_valid(s):
		return
	var k: float = 1.0 + cream_surface(0.0, float(h["t"]))
	s.scale = Vector3(k, k, k)


func cream_shell_free(h: Dictionary) -> void:
	var s = h.get("spr", null)
	if is_instance_valid(s):
		s.queue_free()
	h["spr"] = null


## 特殊护盾段在【血条局部坐标】里的位置与宽度(071 奶油段 / 072 终极段共用的纯函数)。
## 返回 [x0, w]: 从「当前生命 + 前面已画的段」右端起画, 长度 = 本段余额 / 最大生命, 钳在条内。
## ★为什么画在血条上: 068 法力盾定过规矩(用户 2026-08-11「应该是给一个特殊颜色护盾条,
##   这是特殊护盾」——hp_bar 的法力蓝第四段)。奶油盾/终极盾同是 SpecialBalance 余额,
##   不进 u["shield"] ⇒ 血条上原本【完全没有】它们的读数, 玩家无从得知盾还剩多少。
##   hp_bar.gd 是别人的地盘 ⇒ 照 070 灰条的既有做法: 运行时往 bar_root 加 ColorRect,
##   几何走本纯函数, 门禁量真实节点。`before` = 排在本段前面的其他余额合计(段与段不重叠)。
static func shield_seg_rect(bar_w: float, hp: float, maxhp: float, before: float, val: float) -> Array:
	var m: float = maxf(maxhp, 1.0)
	var x0: float = bar_w * clampf((maxf(hp, 0.0) + maxf(before, 0.0)) / m, 0.0, 1.0)
	var w: float = bar_w * clampf(val / m, 0.0, 1.0)
	return [x0, minf(w, maxf(0.0, bar_w - x0))]


## 071 奶油护盾段(奶油白黄): 挂在单位自己的血条上, 每帧由 _cream_tick 的友军巡回喂值。
## 排序: 排在 070 灰条之后(灰条语义是"会回来的血", 更贴 hp; 盾类靠外)。
func cream_bar_update(u: Dictionary, val: float) -> void:
	var root = u.get("bar_root", null)
	if not is_instance_valid(root):
		return
	var rect = u.get("_cream_rect", null)
	if not is_instance_valid(rect):
		rect = ColorRect.new()
		rect.name = "CreamShield"
		## ★奶黄(炼乳金) —— 特意压深饱和度(2026-08-11 用户点名要奶油护盾条):
		##   圣盾段是淡白黄 #FFF4C0、普通盾段是灰白, 若取"奶油白"会和这两段都撞脸;
		##   炼乳本来就是金奶色, #FFD98F 一眼分得开(hp_bar._HOLY_L 对照)。
		rect.color = Color(1.0, 0.85, 0.56, 0.95)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.z_index = 3
		root.add_child(rect)
		u["_cream_rect"] = rect
	var before: float = battle._spec.val(u, EqFoodBatch.KEY_GREY)
	var g: Array = shield_seg_rect(float(battle.BAR_W), float(u["hp"]), float(u["maxHp"]), before, val)
	rect.position = Vector2(float(g[0]), 8.0)
	rect.size = Vector2(float(g[1]), float(battle.BAR_H))
	rect.visible = val > 0.5 and u.get("alive", false)


## 破壳: Taylor–Culick 洞缘恒速张开(r 线性), 边缘卷入质量 ∝ r²(所以越张越粗)。
## 半径落在 300 码 = 071 的 AOE 半径本身。
## ★洞缘同时甩出 12 颗奶油滴(2026-08-11 补验收): TC 回缩边缘的 Plateau–Rayleigh 失稳 ——
##   卷粗的边缘会碎成液滴甩出去, 这是"奶油壳炸开"区别于"又一个圈"的可读证据。
##   颗数/角度全确定性(等角), 高度走纯弹道 4x(1−x)(与 crown_height 同族闭式解),
##   每颗幅度按 (i·7 mod 12)/11 的确定性杂色分层 —— 无一处 randf。
func cream_burst(pos2d: Vector2) -> Dictionary:
	if not is_instance_valid(battle._world):
		return {}
	var rm: float = range_m(300.0)
	var hole := _mk_node(_ring_mesh(), _mat(true, 12), battle._world_pos(pos2d, 0.0))
	var drops: Array = []
	for i in range(CREAM_DROP_N):
		drops.append(_mk_sprite(_cream_drop_tex(), pos2d, 0.25, 13.0, Color(1, 1, 1, 1)))
	var h := {"kind": "tc", "hole": hole, "drops": drops, "c2": pos2d, "r_m": rm, "t": 0.0, "dur": TC_SEC}
	tc_apply_at(h, 0.0)
	_live.append(h)
	return h


## ★破膜形态的单一事实源。演出与门禁只读这一个。
func tc_apply_at(h: Dictionary, x: float) -> void:
	if h.is_empty():
		return
	var rm: float = float(h["r_m"])
	var r: float = maxf(tc_hole_radius(x) * rm, 1e-4)
	var node = h.get("hole", null)
	if not is_instance_valid(node):
		return
	node.scale = Vector3(r, r, r)
	# 边缘亮度 ∝ 卷入质量(r²) —— 洞匀速张开、边却越来越重, 这是 TC 的核心观感
	var m: float = tc_rim_mass(x)
	var fade: float = 1.0 - clampf(x, 0.0, 1.0) * 0.35
	(node.material_override as StandardMaterial3D).albedo_color = Color(
		1.0, 0.95, 0.80, clampf(0.25 + 0.75 * m, 0.0, 1.0) * fade)
	# ── 洞缘的奶油滴: 径向钉在 r(t) 上(与洞同一把尺), 高度纯弹道, 前 70% 满亮再收尾 ──
	#   (淡出病对照: 不做"一出生就线性淡出", 满亮期读得出"滴在飞")
	var rf: float = rm / maxf(float(battle.WS), 1e-6)   # 场地码半径, 从 r_m 反推 —— 不另抄一个 300
	var drops: Array = h.get("drops", [])
	var xx: float = clampf(x, 0.0, 1.0)
	for i in range(drops.size()):
		var d = drops[i]
		if not is_instance_valid(d):
			continue
		var th: float = float(i) * TAU / float(maxi(drops.size(), 1))
		var kk: float = 0.55 + 0.45 * float((i * 7) % 12) / 11.0
		var p2: Vector2 = Vector2(h.get("c2", Vector2.ZERO)) + Vector2(cos(th), sin(th)) * tc_hole_radius(x) * rf
		d.position = battle._world_pos(p2, 0.20 + kk * 4.0 * xx * (1.0 - xx))
		d.modulate.a = 1.0 if xx < 0.7 else maxf(0.0, 1.0 - (xx - 0.7) / 0.3)


# ══════════════════════════════════════════════════════════════════
#  §072 铁皮蛋糕盒 —— 盖子开合 / 嘲讽环 / 双抗反馈 / 分裂弹出
# ══════════════════════════════════════════════════════════════════

## 变身: 盒盖【合上】(θ 从开到合走欠阻尼阶跃) + 一圈铁皮反光。
func box_close_fx(u: Dictionary) -> void:
	_lid_fx(u, false)


## 出盒: 盒盖【打开】(同一个二阶系统, 方向反过来)。
func box_open_fx(u: Dictionary) -> void:
	_lid_fx(u, true)


func _lid_fx(u: Dictionary, opening: bool) -> void:
	if not is_instance_valid(battle._world):
		return
	## ★2026-08-11 补验收: 旧盖子是一张白圆盘(VfxTex disc) ——「白球/圆盘敷衍」族。
	##   换成本件自己的礼盒立绘(BOX_FORM_TEX, 072 专属素材, 不算复用别件),
	##   仍由同一个欠阻尼 lid_step 驱动竖向压扁 ⇒「啪嗒回弹」落在真实盒子形象上。
	##   合盒铁皮蓝 / 出盒金黄; 素材缺失时回退旧盘(不崩)。
	var col := Color(1.0, 0.85, 0.55, 0.95) if opening else Color(0.86, 0.90, 1.0, 0.95)
	var tex: Texture2D = load(EqFoodBatch.BOX_FORM_TEX) if ResourceLoader.exists(EqFoodBatch.BOX_FORM_TEX) else VfxTex._make_disc_texture()
	var s := _mk_sprite(tex, u["pos"], 1.05, 62.0, col)
	_live.append({"kind": "lid", "spr": s, "unit": u, "open": opening, "t": 0.0, "dur": LID_SEC})
	battle._skill_ring(u["pos"], col, 56.0)


## 蛋糕法阵的粉霜奶糕饰点(9×10 像素): 粉霜漩身 + 樱桃顶。静态缓存。
## ★为什么要有它: 法阵原来只有一个 300 码的裸粉圈 ——「无含义圆环」族(memory
##   fb-vfx-defect-families)。圈是效果半径本身(允许), 但"蛋糕"两个字全靠这几颗奶糕撑。
static var _cake_dollop_tex_cache: ImageTexture = null


static func _cake_dollop_tex() -> ImageTexture:
	if _cake_dollop_tex_cache != null:
		return _cake_dollop_tex_cache
	var img := Image.create(9, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cherry := Color(0.88, 0.10, 0.22)
	for p in [Vector2i(4, 0), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)]:
		img.set_pixel(p.x, p.y, cherry)
	img.set_pixel(4, 0, Color(0.98, 0.35, 0.42))   # 樱桃高光
	for y in range(2, 10):
		for x in range(9):
			if Vector2(float(x), float(y)).distance_to(Vector2(4.0, 5.6)) > 3.7:
				continue
			var col := Color(1.00, 0.68, 0.80)                       # 粉霜本体
			if (x + y) % 3 == 0: col = Color(1.00, 0.83, 0.90)       # 螺旋纹亮条
			if y >= 8: col = Color(0.84, 0.50, 0.64)                 # 底沿阴影
			img.set_pixel(x, y, col)
	_cake_dollop_tex_cache = ImageTexture.create_from_image(img)
	return _cake_dollop_tex_cache


## 072 出盒烟团贴图(13×13 手画): 三档灰的絮状团 + 顶部亮沿。
## ★不是 disc/glow 球(白球族), 也没复用别件素材 —— 逐像素现画, NEAREST 采样。
static var _smoke_tex_cache: ImageTexture = null


static func _smoke_tex() -> ImageTexture:
	if _smoke_tex_cache != null:
		return _smoke_tex_cache
	var img := Image.create(13, 13, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 三个偏心的团叠出"絮状"轮廓(单个正圆 = 又一个圆球)
	var lobes := [[Vector2(6.0, 7.0), 5.2], [Vector2(4.0, 5.0), 3.6], [Vector2(8.6, 5.4), 3.2]]
	var light := Color(0.86, 0.85, 0.86)
	var mid := Color(0.66, 0.65, 0.68)
	var dark := Color(0.45, 0.44, 0.48)
	for y in range(13):
		for x in range(13):
			var p := Vector2(float(x), float(y))
			var inside := false
			var near_top := false
			for lb in lobes:
				var d: float = p.distance_to(lb[0] as Vector2)
				if d <= float(lb[1]):
					inside = true
					if d <= float(lb[1]) - 1.6 and y <= int((lb[0] as Vector2).y):
						near_top = true
			if not inside:
				continue
			var col: Color = mid
			if near_top:
				col = light                      # 顶部受光
			elif y >= 9:
				col = dark                       # 底部阴影
			elif (x * 3 + y * 5) % 7 == 0:
				col = dark                       # 絮状杂点(确定性, 无 randf)
			img.set_pixel(x, y, col)
	_smoke_tex_cache = ImageTexture.create_from_image(img)
	return _smoke_tex_cache


## 072 烟团的归一径向距离: 带阻力的自由膨胀 r̂(t) = 1 − e^(−t/τ)。
## ★性质(门禁): 减速 ⇒ r̂(2Δ)/r̂(Δ) < 2(匀速恰 = 2)。
static func smoke_radius(t: float) -> float:
	return SMOKE_V0 * SMOKE_TAU * (1.0 - exp(-maxf(t, 0.0) / SMOKE_TAU))


## 072 烟团直径(码): 卷吸把体积撑大 ⇒ 团径 ∝ √x, 从 D0 长到 D1。
## ★性质(门禁): (d(x)−D0) 的比值满足 √4 = 2。
static func smoke_diam(x: float) -> float:
	return SMOKE_D0 + (SMOKE_D1 - SMOKE_D0) * sqrt(clampf(x, 0.0, 1.0))


## 072【护盾被打破 → 变回本体】那一下的烟雾爆开(2026-08-11 用户点名)。
## 12 团等分角射出 + 浮升 + 膨胀; 前 70% 满亮再散(短命特效不许一出生就淡出)。
## ★确定性: 角度等分 + 按序号取的固定偏差表, 一个 randf 都没有(rng_discipline)。
func unbox_smoke(u: Dictionary) -> Array:
	if not is_instance_valid(battle._world):
		return []
	var out: Array = []
	var tex: Texture2D = _smoke_tex()
	var c: Vector2 = u["pos"]
	for i in range(SMOKE_N):
		var th: float = float(i) * TAU / float(SMOKE_N) + 0.13
		# 大小/速度/高度的错落: 序号取模的固定表(确定性, 但看着不是一圈整齐的钟表)
		var vk: float = [1.0, 0.78, 0.92, 0.66][i % 4]
		var hk: float = [0.55, 0.95, 0.72, 1.15][i % 4]
		var s := _mk_sprite(tex, c, 0.5 + 0.35 * hk, SMOKE_D0, Color(1, 1, 1, 1))
		_live.append({"kind": "smoke", "spr": s, "c": c, "th": th, "vk": vk, "hk": hk,
			"t": 0.0, "dur": SMOKE_SEC})
		out.append(s)
	return out


## 072 终极护盾段(礼盒粉): 挂在携带者血条上, 每帧由 _box_tick 喂真实余额。
## 与 071 奶油段共用 shield_seg_rect 这把尺; 排序在灰条/奶油段之后(段与段不重叠)。
## ⛔ 这里曾经是 `ult_bar_update()`(072 终极盾自画一条 ColorRect)。
##   2026-08-12 改走 HpBar(镜像 `_ultShieldVal`)后**零调用者** ⇒ 删掉, 不留空壳:
##   零调用者的死函数会被"断言函数存在"型门禁保护住(memory [[fb-verify-must-run-the-real-path]])。
##   它的老毛病也记在这: 用 maxHp 当分母算段起点 ⇒ 满血时段宽恒为 0, 玩家一次没看见过。


## 072 法阵每秒结算的读数: 被治疗的友军身上升起一颗小奶糕(0.6 秒, 前 70% 满亮)。
## ★"每秒回 50/70/120"没有画面证据就等于没做 —— 台子默认关飘字, 这颗是滴答的唯一读数。
func field_heal_fx(u: Dictionary) -> void:
	if not is_instance_valid(battle._world):
		return
	_live.append({"kind": "healdrop", "spr": _mk_sprite(_cake_dollop_tex(), u["pos"], 0.55, 13.0, Color(1, 1, 1, 1)),
		"p2": Vector2(u["pos"]), "t": 0.0, "dur": 0.6})


## 嘲讽环 + 双抗反馈: 半径 = 550 码(嘲讽范围本身); 亮度/内环随【当前锁定自己的敌人数】实时变。
## ★"实时"是这件的核心 —— 敌人切目标就掉, 所以这一圈每帧都在跟着变, 不是施加时算一次。
func taunt_ring_update(u: Dictionary, lockers: int) -> void:
	var node = u.get("_box_ring", null)
	if not is_instance_valid(node):
		node = _mk_node(_ring_mesh(), _mat(true, 8), battle._world_pos(u["pos"], 0.0))
		u["_box_ring"] = node
	var rm: float = range_m(TAUNT_RANGE_PX)
	node.scale = Vector3(rm, rm, rm)
	node.position = battle._world_pos(u["pos"], 0.0)
	# 亮度随锁定人数升: 0 人 = 淡淡一圈, 6 人 = 满亮(视觉上就能读出"它现在有多硬")
	var k: float = clampf(float(lockers) / 6.0, 0.0, 1.0)
	(node.material_override as StandardMaterial3D).albedo_color = Color(
		1.0, 0.55 + 0.30 * k, 0.30 + 0.20 * k, 0.16 + 0.50 * k)


func taunt_ring_free(u: Dictionary) -> void:
	var node = u.get("_box_ring", null)
	if is_instance_valid(node):
		node.queue_free()
	u["_box_ring"] = null


## 蛋糕法阵(2026-08-11 二轮: 用户「如果是法阵你这个效果就很敷衍了」——素圈不配叫法阵):
##   ① 裱花波浪外环(外沿均值 = 300 码技能判定半径本身, ±3% 波瓣 = 奶油挤花边)
##   ② 缓旋辐条内环层(法阵的"活"), ③ 环沿 8 颗粉霜奶糕。
##   颜色改饱和蛋糕粉 —— 旧版淡粉+加色被泛光直接洗成白圈(fb-vfx-defect-families 无含义白圈)。
## ★奶糕角度等分全确定性(无 randf); 0.20 的相位偏移只是别让第一颗压在正右方向的敌人身上。
func cake_field_fx(u: Dictionary, dur: float) -> Dictionary:
	if not is_instance_valid(battle._world):
		return {}
	var pos2d: Vector2 = u["pos"]
	var rm: float = range_m(CAKE_FIELD_PX)
	var ring := _mk_node(_scallop_mesh(), _mat(true, 9), battle._world_pos(pos2d, 0.0))
	ring.scale = Vector3(rm, rm, rm)
	(ring.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.45, 0.62, 0.62)
	var spokes := _mk_node(_spoke_mesh(), _mat(true, 9), battle._world_pos(pos2d, 0.0))
	spokes.scale = Vector3(rm, rm, rm)
	(spokes.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.62, 0.74, 0.50)
	var deco: Array = []
	for i in range(8):
		var th: float = float(i) * TAU / 8.0 + 0.20
		deco.append(_mk_sprite(_cake_dollop_tex(),
			pos2d + Vector2(cos(th), sin(th)) * CAKE_FIELD_PX, 0.12, 15.0, Color(1, 1, 1, 1)))
	## "unit" 引用 = 跟随的事实源(2026-08-11 用户拍板「是要跟随的」): 每帧 tick 里
	## 环/辐条/奶糕全部搬到携带者当前位置 —— 判定(box_field_pulse 读 u["pos"])同一个点。
	var h := {"kind": "field", "unit": u, "ring": ring, "spokes": spokes, "deco": deco, "t": 0.0, "dur": maxf(dur, 0.1)}
	_live.append(h)
	return h


## 分裂弹出: 抛体 + 恢复系数 e 的多次弹跳, 落地按触地速度形变。
## ★2026-08-11 补验收: 弹出去的就是【礼盒】—— 用本件自己的礼盒立绘, 不再是白圆盘。
func box_split_hop(from2: Vector2, dir: Vector2) -> void:
	if not is_instance_valid(battle._world):
		return
	var tex: Texture2D = load(EqFoodBatch.BOX_FORM_TEX) if ResourceLoader.exists(EqFoodBatch.BOX_FORM_TEX) else VfxTex._make_disc_texture()
	var s := _mk_sprite(tex, from2, 0.4, 46.0, Color(1, 1, 1, 1))
	_live.append({"kind": "hop", "spr": s, "from": from2, "dir": dir, "t": 0.0, "dur": HOP_SEC})


# ══════════════════════════════════════════════════════════════════
#  §每帧推进(由 EqFoodBatch 调, 全局一次)
# ══════════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	if _live.is_empty():
		return
	var keep: Array = []
	for h in _live:
		h["t"] = float(h.get("t", 0.0)) + maxf(delta, 0.0)
		var x: float = float(h["t"]) / maxf(float(h.get("dur", 0.4)), 0.001)
		var alive: bool = x < 1.0
		match str(h.get("kind", "")):
			"crown":
				crown_apply_at(h, x)
				if not alive:
					_free_keys(h, ["crown", "ring"])
			"bwave":
				bwave_apply_at(h, x)
				if not alive:
					_free_keys(h, ["ring"])
			"tc":
				tc_apply_at(h, x)
				if not alive:
					_free_keys(h, ["hole"])
					_free_list(h, "drops")
			"field":
				var rg = h.get("ring", null)
				var f_fade: float = 1.0 - clampf(x, 0.0, 1.0) * 0.6
				# ★跟随携带者(2026-08-11 用户拍板): 中心 = unit 当前位置, 与治疗判定同点。
				#   单位死了/没了就停在原地淡出(不追尸体也不闪没)。
				var fun = h.get("unit", null)
				var fc2: Vector2 = (fun as Dictionary)["pos"] if (fun is Dictionary and (fun as Dictionary).get("alive", false)) else Vector2.INF
				if is_instance_valid(rg):
					if fc2 != Vector2.INF:
						rg.position = battle._world_pos(fc2, 0.0)
					(rg.material_override as StandardMaterial3D).albedo_color = Color(
						1.0, 0.45, 0.62, 0.62 * f_fade)
				var fsp = h.get("spokes", null)
				if is_instance_valid(fsp):
					# 法阵的"活": 辐条层缓旋(素圈转不起来 —— 2026-08-11 用户打回的正是素圈)
					if fc2 != Vector2.INF:
						fsp.position = battle._world_pos(fc2, 0.0)
					fsp.rotation.y = float(h["t"]) * FIELD_SPIN
					(fsp.material_override as StandardMaterial3D).albedo_color = Color(
						1.0, 0.62, 0.74, 0.50 * f_fade)
				var fdk: Array = h.get("deco", [])
				for di in range(fdk.size()):
					var dp = fdk[di]
					if is_instance_valid(dp):
						if fc2 != Vector2.INF:
							var dth: float = float(di) * TAU / 8.0 + 0.20
							dp.position = battle._world_pos(fc2 + Vector2(cos(dth), sin(dth)) * CAKE_FIELD_PX, 0.12)
						dp.modulate.a = f_fade
				if not alive:
					_free_keys(h, ["ring", "spokes"])
					_free_list(h, "deco")
			"smoke":
				# 出盒烟雾: 径向带阻力减速 + 浮升 + 卷吸膨胀; 前 70% 满亮(不许一出生就淡)
				var sm = h.get("spr", null)
				if is_instance_valid(sm):
					var st_: float = float(h["t"])
					var rad: float = smoke_radius(st_) * float(h["vk"])
					var th2: float = float(h["th"])
					var hh2: float = 0.5 + 0.35 * float(h["hk"]) + SMOKE_RISE * st_ * float(h["hk"])
					sm.position = battle._world_pos(
						(h["c"] as Vector2) + Vector2(cos(th2), sin(th2) * 0.55) * rad, hh2)
					var dia: float = smoke_diam(x)
					sm.scale = Vector3.ONE * (dia / SMOKE_D0)
					sm.modulate.a = 1.0 - smoothstep(0.70, 1.0, x)
				if not alive:
					_free_keys(h, ["spr"])
			"bite":
				var sp = h.get("spr", null)
				var un = h.get("unit", null)
				if is_instance_valid(sp) and un is Dictionary:
					var f: Vector2 = h["from"]
					var to: Vector2 = (un as Dictionary)["pos"]
					var p: Vector2 = f.lerp(to, clampf(x, 0.0, 1.0))
					sp.position = battle._world_pos(p, CAKE_HOVER_H * bite_height(x))
					var k: float = 1.0 - 0.7 * clampf(x, 0.0, 1.0)
					sp.scale = Vector3(k, k, k)
				if not alive:
					_free_keys(h, ["spr"])
			"lid":
				var sp2 = h.get("spr", null)
				var un2 = h.get("unit", null)
				if is_instance_valid(sp2) and un2 is Dictionary:
					var th: float = lid_step(x * LID_SEC)   # ← 秒为单位喂进二阶系统
					if not bool(h.get("open", false)):
						th = 1.0 - th
					sp2.position = battle._world_pos((un2 as Dictionary)["pos"], 1.05)
					# 盖子转角 → 视觉上的"厚度"(cos) —— 合上时压扁成一条线
					var c: float = maxf(cos(deg_to_rad(LID_OPEN_DEG) * th), 0.06)
					sp2.scale = Vector3(1.0, c, 1.0)
					# 前 65% 满亮定住, 后 35% 收尾 —— 淡出病对照(memory fb-vfx-defect-families):
					# 旧写法出生即线性淡出, 0.34 秒的演出有一多半时间是半透明的
					sp2.modulate.a = 0.95 if x < 0.65 else 0.95 * maxf(0.0, 1.0 - (clampf(x, 0.0, 1.0) - 0.65) / 0.35)
				if not alive:
					_free_keys(h, ["spr"])
			"hop":
				var sp3 = h.get("spr", null)
				if is_instance_valid(sp3):
					var f3: Vector2 = h["from"]
					var d3: Vector2 = h["dir"]
					var p3: Vector2 = f3 + d3 * HOP_DIST_PX * clampf(x, 0.0, 1.0)
					sp3.position = battle._world_pos(p3, 0.25 + hop_height(x) * 1.1)
					var n: int = _hop_seg(x)
					var sq: float = hop_squash(n) * (1.0 - clampf(hop_height(x) * 4.0, 0.0, 1.0))
					sp3.scale = Vector3(1.0 + sq, maxf(1.0 - sq, 0.15), 1.0)
				if not alive:
					_free_keys(h, ["spr"])
			"healdrop":
				# 072 法阵滴答: 小奶糕原地升起(线性升 1 米), 前 70% 满亮再收尾
				var sp4 = h.get("spr", null)
				if is_instance_valid(sp4):
					var xh: float = clampf(x, 0.0, 1.0)
					sp4.position = battle._world_pos(Vector2(h.get("p2", Vector2.ZERO)), 0.55 + 1.0 * xh)
					sp4.modulate.a = 1.0 if xh < 0.7 else maxf(0.0, 1.0 - (xh - 0.7) / 0.3)
				if not alive:
					_free_keys(h, ["spr"])
		if alive:
			keep.append(h)
	_live = keep


## 当前处在第几段弹跳(供落地形变取触地速度)
static func _hop_seg(x: float) -> int:
	var total := 0.0
	for n in range(4):
		total += pow(HOP_E, float(n))
	var acc := 0.0
	for n in range(4):
		acc += pow(HOP_E, float(n)) / total
		if x <= acc:
			return n
	return 3


func _free_keys(h: Dictionary, keys: Array) -> void:
	for k in keys:
		var n = h.get(k, null)
		if is_instance_valid(n):
			n.queue_free()
		h[k] = null


## 句柄里存的是【节点数组】的键(071 奶油滴 drops / 072 法阵饰点 deco)用这个清
func _free_list(h: Dictionary, key: String) -> void:
	for n in h.get(key, []):
		if is_instance_valid(n):
			n.queue_free()
	h[key] = []


## 换路/撤场: 把还在飞的演出全清掉(节点跟着 _world 走, 这里只清账)。
##
## ⚠ 诚实记录:【本函数目前没有调用者】。不是漏接, 是因为换路会整个重建 `_world`,
##   本层建的节点全是 `_world` 的子节点 ⇒ 跟着一起走; `_live` 里剩下的条目也只会
##   在下一次 `tick()` 里被 `is_instance_valid` 挡掉并按时长自然出列(不会崩、不会泄漏)。
##   留着它是给【撤场点】用的: 换路清理挂在 `dual_lane_flow.gd`(主会话的文件),
##   要接的话在 `battle._spec.clear_all()` 旁边加一行 `_equip_sys._food_sys._vfx.clear_all()` 即可。
func clear_all() -> void:
	for h in _live:
		_free_keys(h, ["crown", "ring", "hole", "spr", "spokes"])
		_free_list(h, "drops")   # 071 奶油滴
		_free_list(h, "deco")    # 072 法阵饰点
	_live.clear()
