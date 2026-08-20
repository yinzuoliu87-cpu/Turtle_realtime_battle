class_name GadgetEqVfx
extends RefCounted
## gadget_eq_vfx.gd — 奇械三件新装备(085/086/087)的演出层
## (规格 docs/plans/20260805-装备逐件重做.md §0.5 · 实装契约 docs/plans/20260806-实装契约-批④.md §7)
##
## ══════════════════════════════════════════════════════════════════════
##  ★判据: 可验证的物理规律, 不是"我调得像"
## ══════════════════════════════════════════════════════════════════════
## ⚠ **诚实记录**: 这三件**一张参考图都没有**, 所以触手那条"逐帧量参考做成包络表"
##   ([[fb-match-reference-by-measured-curve]])在这里无从下手。替代路线照
##   `bow_eq_vfx.gd` / `shockwave_vfx.gd`: 每条形态落在一个**有闭式解的物理模型**上,
##   门禁验的是那个模型的**性质**(恒等式 / 尺度律 / 极值), 手调出来的曲线一条都过不了。
##   **这不是"逐帧量参考"的等价物**, 是它的替代品。
##
## ── ① 085 压电火花: 常明陶瓷芯 + 面能量密度守恒的辉光冕 ────────────────
##   压电材料受力放电, 放出的能量摊在一片辉光上。若**面能量密度恒定**(材料属性),
##   则 E ∝ 面积 ∝ r² ⇒ 辉光冕 **r_halo ∝ √E**。
##   而陶瓷片**本身是一个有尺寸的实体**, 不管放多少电它都在那儿 ⇒ 总半径
##       r(E) = R0 + K·√E          `spark_radius()`
##   ★可验证性质(门禁): `(r(4E) − R0) / (r(E) − R0) ≡ 2`, 与 E 无关(冕的纯尺度律);
##     且 `r(0) ≡ R0 > 0`(芯常明)。线性半径会给 4, 没有 R0 的旧式在 E→0 时给 0。
##
##   ★★2026-08-07 为什么加 R0 —— 旧式 `r = 0.08·√E` 把**常态压进了不可见区**:
##     常态每下挨打 8~36 伤害 ⇒ E = 0.15×伤害 = 1.2~5.4 ⇒ r = 0.088~0.186 米 ⇒
##     实战默认视角(28.148 屏幕像素/米)下**直径只有 4.9~10.5 屏幕像素**, 比头顶徽章(16 px)还小。
##     纯 √ 律的毛病在于: 想把常态顶上去只能整体放大 K, 而 3★ 每秒上限 E=60 会跟着放大到爆屏。
##     R0 + K√E 把"下限"和"增速"拆成两个独立旋钮 ⇒ 常态 20~29 px、上限 E=60 仍只有 67 px。
##     ⇒ 尺度律没丢, 只是**移到冕上**(它本来就只对冕成立 —— 芯不是放电产物)。
##
## ── ② 086 浮游炮环绕: 正 n 边形排布(最大最小间距) ────────────────────
##   n 门炮环绕, 唯一让**最小两两角距最大化**的排布是正 n 边形(角度 2πk/n)。
##   ★可验证性质(门禁): 任意 n, **最小两两角距 ≡ 2π/n**(精确), 且每门炮到携带者的
##     距离**全都恰好等于 orbit_r**(不是"大概在一圈上")。
##   ⇒ "环绕自身"这四个字有了可判定形式: 等距 + 等半径。
##
## ── ③ 086 终极射线: 长度恒等式 + 指数余辉 ──────────────────────────
##   射线是从**飞散点**打到**目标**的一条实体光柱, 所以它的世界长度必须**恒等于**
##   两点真实距离 × WS —— 不是"看起来差不多长"。
##   ★可验证性质(门禁): `beam_len_m(a, b) ≡ a.distance_to(b) * WS`, 且节点
##     `scale.x` 就是这个数; 节点 basis 的 **+X 轴 ≡ 两点的世界方向单位向量**
##     (朝向坑 [[fb-axis-y-plus-rotation-cancels]]: 光靠"看着对"会栽)。
##   余辉走**指数衰减** a(t) = exp(−ln2 · t / HALF):
##   ★可验证性质: `ray_alpha(HALF) / ray_alpha(0) ≡ 0.5`(半衰期定义), 且
##     `ray_alpha(2·HALF) ≡ 0.25` —— 线性淡出会给 0.0, 一测就分开。
##
## ── ④ 087 水柱: 定长径比柱体 ⇒ 半径 ∝ ∛V ──────────────────────────
##   抽出来的水是**有体积的实体**。柱体保持固定长径比(L = A·r)时 V = πr²L = πA·r³
##   ⇒ **r ∝ V^(1/3)**。
##   ★可验证性质(门禁): `jet_radius(8V) / jet_radius(V) ≡ 2`, 与 V 无关。
##     线性半径会给 8, 面积律(√)会给 2.83, 三者互相分得开。
##
## ── ⑤ 087 压载水位计: 填充宽度 ≡ 底槽 × 水位比 ────────────────────
##   玩家要一眼看出"舱快满了"(满舱 = 15 层 = +45% 移速 +45 护甲, 是这件的核心读数)。
##   ★可验证性质(门禁): `fg.scale.x ≡ GAUGE_W_M × clamp(water/cap, 0, 1)`,
##     且 `bg.scale.x ≡ GAUGE_W_M`(分母, 证明比例真的在动而不是两个都写死)。
##
## ── 技术路线 ────────────────────────────────────────────────────────
## Godot 内置图元(SphereMesh / BoxMesh / TorusMesh)+ `material_override`, **零素材**。
## 用户铁律「不复用素材除非点名」: 程序化几何不产出图, 也**没有借用任何别件装备的立绘**。
##
## ⚠ **不用 tween**: 无头 CI 下 `create_tween()` 推进不稳(CLAUDE.md §3.5,
##   verify_pirate_hook 为此连红三次), 且走 sim 的 delta 才跟时停/换路同步。
##   全部生命周期由本文件的 `tick(delta)` 推进。
## ⚠ 材质一律走 `material_override`, 不用 `set_surface_override_material` ——
##   后者在 `--headless` dummy renderer 下每设一次刷一条 `Parameter "material" is null.`
## ⚠ **每个入口都能被单独调用**(供门禁与 VFXPREVIEW 用), 且**结算不在演出里** ——
##   伤害/回血/龟能全部在 `eq_gadget_batch.gd` 里同步完成, 本文件只画。

# ══════════════════════════════════════════════════════════════════
#  §物理常数 —— 全部来自上面的闭式解
# ══════════════════════════════════════════════════════════════════

## 085 火花: r = SPARK_R0 + SPARK_K·√E (米)。
## ★三个设计点(实战默认视角 28.148 屏幕像素/米, 直径 = 2r):
##     E =  1.2 (挨 8 伤害)  → r 0.360 米 → 直径 **20.3 px**   ← 常态下限, 已高于徽章 16 px
##     E =  5.4 (挨 36 伤害) → r 0.515 米 → 直径 **29.0 px**
##     E = 60.0 (3★ 每秒封顶·硬上限) → r 1.196 米 → 直径 **67.3 px** ← 约 1.5 只龟高, 不爆屏
const SPARK_R0 := 0.22
const SPARK_K := 0.126
const SPARK_LIFE := 0.30
const SPARK_COLOR := Color(0.62, 0.95, 1.0)
## 辉光的不透明度。★从 0.85 降下来: 半径放大 3~6 倍之后, 0.85 的加法混合会盖成一坨实心白球
##   把携带者整只糊住 —— 这是"治好看不见"顺手造出的反向问题。0.60 仍是明确的青白辉光。
const SPARK_ALPHA := 0.60
## 压电裂纹: 几道 / 多粗(米) / 画在胸口多高(米)
const CRACK_N := 5
const CRACK_THICK := 0.07
const PIEZO_CHEST_M := 0.85
## 龟能微粒: 几粒 / 单粒长(码) / 粗(米) / 横向铺开(码) / 上涌多少米 / 活多久 / 相邻错开
## ★金色取的就是**龟能条的色号 #ffce4d**(battle_hud 里那条) —— 同一种资源同一个颜色,
##   玩家不必再学一遍"这个金色是什么"。
const ENERGY_GOLD := Color(1.0, 0.807, 0.302, 0.95)
const MOTE_N := 4
const MOTE_LEN_PX := 16.0
const MOTE_THICK := 0.10
const MOTE_SPREAD_PX := 40.0
const MOTE_RISE_M := 1.15
const MOTE_LIFE := 0.42
const MOTE_GAP := 0.06

## 086 浮游炮
const DRONE_R_M := 0.16          ## 炮体半径(米)
const DRONE_COLOR := Color(0.70, 0.86, 1.0)
const DRONE_LIFT := 1.55         ## 环绕高度(米·在龟头顶上方)
## ★照赛博龟 `_tick_cyber_drones` 的被动编队参数(内外双环·反向·浮动·平滑跟随)
const DRONE_RING_K := 1.42       ## 外环半径 = 内环 × 这个数(赛博: 48 → 76 ≈ 1.58)
const DRONE_RING_REV := 0.8      ## 外环反向公转的角速度比(赛博: −0.8)
const DRONE_RING_H := 0.25       ## 外环比内环高多少米(赛博: +0.25)
const DRONE_BOB_W := 2.2         ## 悬浮上下浮动角频率(赛博: 2.2)
const DRONE_BOB_A := 0.10        ## 浮动幅度(米·赛博: 0.1)
const DRONE_FOLLOW := 6.0        ## 平滑跟随系数(赛博: delta×6)
## 开火三件套(照赛博龟): 炮口闪 / 后坐 / 小而淡的弹
const SHOT_MUZZLE_PX := 12.0     ## 炮口闪离炮体多远(码)
const SHOT_MUZZLE_R := 0.13      ## 炮口闪半径(米)
const SHOT_MUZZLE_SEC := 0.12    ## 炮口闪时长(赛博: 0.12)
const SHOT_KICK_IN := 0.05       ## 后坐缩进用时(赛博: 0.05)
const SHOT_KICK_OUT := 0.10      ## 弹回用时(赛博: 0.10)
const SHOT_KICK_K := 0.82        ## 后坐缩到原尺寸的几成(赛博: 0.82)
const SHOT_BOLT_PS := 0.008      ## 弹丸的 pixel_size(与赛博龟同)
const SHOT_BOLT_A := 0.65        ## 弹的 alpha —— 赛博的注释: "小而淡, 防 20 炮糊屏"
const SHOT_BOLT_SPD := 900.0     ## 弹速(码/秒·赛博按 dist/900 算飞行时间)
const SHOT_LIFE := 0.16          ## 射击曳光存续(秒)
const SHOT_THICK := 0.035        ## 曳光粗细(米)
const RAY_LIFE := 0.70           ## 终极射线存续(秒)
const RAY_HALF := 0.20           ## 余辉半衰期(秒)
const RAY_THICK := 0.19          ## 终极射线粗细(米)。★变更史 2026-08-08 0.20→0.13(旧粗细在实拍里
                                 ##   像横跨全场的**脚手架板**, 不像一道射线), 之后"随光束一起加粗"回到
                                 ##   **现值 0.19** —— 注释原来只停在 0.13, 与代码对不上。
const RAY_CORE_K := 0.34         ## 白热芯相对身的粗细比
const RAY_HOLD := 0.16           ## 满亮保持(秒) —— 之后才按 RAY_HALF 衰减
## ★★照赛博龟阵亡齐射的编排(用户 2026-08-08 指定参考)。那一套是 Gaster Blaster 式:
## 蓄力光球膨胀 → 光球消失 + 炮体后坐 → 双层光束 → 震屏 → 线上命中火花。
## 错峰飞散(照赛博龟): 起飞间隔上限 / 飞行时长下限·上限 / 从飞散开始到发射的总时长
const SEXT_SCATTER_LAG := 0.35
const SEXT_SCATTER_MIN := 0.60
const SEXT_SCATTER_MAX := 1.00
const SEXT_FIRE_DELAY := 1.35    ## 赛博龟阵亡齐射就是 1.35 秒开火
## ★★2026-08-08 用户:「发射完后呢, 凭什么瞬移回来」—— 对的。旧版 `scat` 一归零就
## **瞬移回轨道**。赛博龟那边是"飞向集结点消失"(本体死了要变机甲), 而本件的炮要**继续绕**
## ⇒ 该**飞回来**。回程同样错峰, 且**回到轨道此刻该在的位置**(轨道一直在转, 不是回旧点)。
const SEXT_BACK_LAG := 0.30      ## 回程起飞间隔上限(秒)
const SEXT_BACK_MIN := 0.70      ## 回程飞行时长下限
const SEXT_BACK_MAX := 1.10      ## 回程飞行时长上限
const SEXT_CHARGE := 0.45        ## 口部聚能光球膨胀多久(秒) —— 与赛博龟的 0.45 同一口径
const SEXT_GLOW_COL := Color(1.6, 1.9, 2.2, 1.0)   ## 蓄力时炮身亮到什么程度(与赛博龟同)
const SEXT_MUZZLE_PX := 16.0     ## 光球离炮体多远(码) —— 同赛博龟的 16
const SEXT_ORB_R0 := 0.06        ## 光球起手半径(米)
const SEXT_ORB_R1 := 0.30        ## 光球胀满半径(米)
const SEXT_RECOIL_PX := 30.0     ## 炮体后坐多少码
const SEXT_RECOIL_BACK := 0.08   ## 后坐用时(秒)
const SEXT_RECOIL_HOME := 0.24   ## 回位用时(秒)
const SEXT_SHAKE := 0.03         ## 震屏幅度(与赛博龟同)
const SEXT_BEAM_TEX := "res://assets/sprites/vfx/fx-energy-beam.png"   ## 与赛博龟齐射同一张
## ★2026-08-08 实拍后收一档(120/200 → 78/140): 赛博龟那套是 150/250, 但它一次只朝
## **一个方向**放、且战场铺得开; 本件是**六条同时对着中间几只龟交叉**, 200 码宽的外晕
## 把整个画面洗白了(龟全被盖住)。结构照抄(双层·白核+彩晕·外晕略久), 尺度按场面收。
## ★2026-08-08 用户实拍后:「加粗激光」⇒ 回到赛博龟阵亡齐射的原值 150/250。
## (我先前自己收到 78/140, 理由是"六条同时交叉会洗白画面" —— 用户看了实际效果说要粗,
##  以他的判断为准。)
const SEXT_BEAM_CORE_PX := 150.0 ## 厚白核心束宽(码)
const SEXT_BEAM_HALO_PX := 250.0 ## 紫晕外束宽(码)
const RAY_MUZZLE_R := 0.26       ## 发射端炮口闪半径(米)
const RAY_POP_R := 0.34          ## 命中端爆点半径(米)
const RAY_COLOR := Color(0.72, 0.35, 1.0)   ## 紫色终极射线(规格明写"紫色")

## 087 水柱: r = JET_K·V^(1/3) (米)。JET_ASPECT = 柱长/柱半径(定长径比 ⇒ V ∝ r³)。
const JET_K := 0.055
const JET_ASPECT := 14.0
const JET_LIFE := 0.34
const JET_COLOR := Color(0.35, 0.78, 1.0)

## 087 压载水位计(头顶横条)
const GAUGE_W_M := 1.44          ## 底槽全宽(米)
const GAUGE_H_M := 0.16
const GAUGE_LIFT := 2.05
const GAUGE_BG := Color(0.10, 0.16, 0.24)
const GAUGE_FG := Color(0.30, 0.72, 1.0)

## 087 偷技能瞬闪(青铜令环)
const STEAL_R_M := 0.95
const STEAL_LIFE := 0.42
const STEAL_COLOR := Color(0.95, 0.78, 0.35)

const META_KEY := "gadget_eq_vfx"
const OWNED_CAP := 512

var battle
var _owned: Array = []           ## 本层建过的节点(撤场时统一 free)
var _fx: Array = []              ## 有寿命的瞬时件: {node, t, life, half}


func _init(b) -> void:
	battle = b


func _alive() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 上面五条物理性质的实现。门禁直接调, 不需要任何节点/场景。
# ══════════════════════════════════════════════════════════════════

## ① 辉光冕: 面能量密度守恒 ⇒ 冕半径 ∝ √E(不含常明的陶瓷芯)
static func spark_halo(energy: float) -> float:
	return SPARK_K * sqrt(maxf(0.0, energy))


## ① 火花总半径 = 常明陶瓷芯 + 辉光冕。`spark_radius(0) ≡ SPARK_R0`。
static func spark_radius(energy: float) -> float:
	return SPARK_R0 + spark_halo(energy)


## ② 第 k 门炮的环绕角(正 n 边形): 2πk/n + phase
static func orbit_angle(k: int, n: int, phase: float) -> float:
	if n <= 0:
		return phase
	return phase + TAU * float(k) / float(n)


## ② 第 k 门炮相对携带者的 2D 偏移(码)
static func orbit_offset(k: int, n: int, phase: float, r: float) -> Vector2:
	var a: float = orbit_angle(k, n, phase)
	return Vector2(cos(a), sin(a)) * r


## ③ 两点之间光柱的世界长度(米) —— 恒等于真实距离 × WS
func beam_len_m(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b) * battle.WS


## ③ 指数余辉(半衰期 RAY_HALF)
static func ray_alpha(t: float) -> float:
	# ★★2026-08-08 加保持段。纯指数余辉(半衰期 0.20 / 寿命 0.70)让射线
	#   **大半辈子在 25% 亮度以下** —— 实拍里是几条几乎与背景同暗的**深紫色板**。
	#   这是本轮第五次撞见同一个"淡出病"(078/079/082/084/这里)。
	#   ⇒ 前 RAY_HOLD 秒满亮, 之后才按原来的半衰期衰减(衰减律本身没动, 门禁照旧)。
	if t <= RAY_HOLD:
		return 1.0
	return exp(-log(2.0) * maxf(0.0, t - RAY_HOLD) / RAY_HALF)


## ④ 定长径比柱体: 半径 ∝ V^(1/3)
static func jet_radius(volume: float) -> float:
	return JET_K * pow(maxf(0.0, volume), 1.0 / 3.0)


## ⑤ 水位比(0~1)
static func gauge_fill(water: float, cap: float) -> float:
	if cap <= 0.0:
		return 0.0
	return clampf(water / cap, 0.0, 1.0)


# ══════════════════════════════════════════════════════════════════
#  §节点基建
# ══════════════════════════════════════════════════════════════════

static func _mat(col: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = true
	m.render_priority = 12
	m.albedo_color = col
	return m


func _adopt(n: Node3D, kind: String) -> void:
	n.set_meta(META_KEY, kind)
	battle._world.add_child(n)
	if _owned.size() >= OWNED_CAP:
		_owned = _owned.filter(func(x): return is_instance_valid(x))
	_owned.append(n)


func _mi(mesh: Mesh, col: Color, kind: String, additive: bool = true) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = _mat(col, additive)
	_adopt(n, kind)
	return n


## 一根从 a 到 b 的光柱(单位立方体缩放而成)。
## ★朝向: 绕 Y 转 θ 会把局部 +X 映到 (cosθ, 0, −sinθ) ⇒ θ = atan2(−dz, dx)。
##   门禁验的是**节点 basis 的 +X 轴 ≡ 两点世界方向单位向量**, 不是"看着对"。
func _beam(a: Vector2, b: Vector2, lift: float, thick: float, col: Color, kind: String) -> MeshInstance3D:
	var wa: Vector3 = battle._world_pos(a, lift)
	var wb: Vector3 = battle._world_pos(b, lift)
	var d: Vector3 = wb - wa
	var n := _mi(BoxMesh.new(), col, kind)
	(n.mesh as BoxMesh).size = Vector3.ONE
	n.position = (wa + wb) * 0.5
	n.rotation = Vector3(0.0, atan2(-d.z, d.x), 0.0)
	n.scale = Vector3(maxf(0.001, d.length()), thick, thick)
	return n


func _transient(n: MeshInstance3D, life: float, half: float = 0.0) -> void:
	_fx.append({"node": n, "t": 0.0, "life": maxf(0.01, life), "half": half})


# ══════════════════════════════════════════════════════════════════
#  §085 压电火花
# ══════════════════════════════════════════════════════════════════

## 转了 `energy` 点龟能 ⇒ 在携带者身上闪一片辉光, 半径 ∝ √E(性质 ①)。
func piezo_spark(u: Dictionary, energy: float) -> MeshInstance3D:
	if not _alive() or energy <= 0.0:
		return null
	# ★★2026-08-08 实拍(_vfxlab_p2eq_085_3.png): 旧版是一颗 **SphereMesh 白球**罩在携带者身上
	#   —— 正是用户这一轮开头就点名的"白球家族"。一个球读不出"伤害进来了"与"变成龟能了"
	#   这两件事的任何一半。⇒ 拆成两段, 各管一半:
	#     ① 压电: 胸口炸出几道**短促的放射裂纹**(压电陶瓷受压开裂), 青白、尖、快
	#     ② 转化: 几粒 **龟能金(#ffce4d, 与龟能条同色)的微粒沿身体上涌**
	#        —— "往上走"这个方向本身就是"转成龟能"的读法
	#   尺寸仍由 `spark_radius(energy)` 驱动 ⇒ √E 律那几条门禁照旧管着它。
	var r: float = spark_radius(energy)
	var ctr: Vector2 = u["pos"]
	var head: MeshInstance3D = null
	for i in range(CRACK_N):
		var th: float = TAU * float(i) / float(CRACK_N) + float(u.get("_st_taken", 0)) * 0.7
		var d: Vector2 = Vector2(cos(th), sin(th) * 0.55)          # 压扁: 2.5D 斜视角下才像贴着身体
		# ★★裂纹的**世界长度严格等于 `spark_radius(E)`** —— 门禁断言的正是"真实节点的
		#   scale ≡ 公式值"(不是"公式对了但没写到节点上")。两点的场地码间距 = r / WS,
		#   `_beam` 会把它换算回世界米 ⇒ scale.x 恰好是 r。第一版我按 PX_PER_M 随手换算,
		#   门禁立刻红(scale 0.4246 vs 公式 0.5128) —— 它守住了东西。
		var step: float = r / maxf(0.0001, float(battle.WS))
		var a0: Vector2 = ctr + d * (step * 0.25)
		var b0: Vector2 = a0 + d * step
		var cr := _beam(a0, b0, PIEZO_CHEST_M, CRACK_THICK,
			Color(SPARK_COLOR.r, SPARK_COLOR.g, SPARK_COLOR.b, 0.95), "piezo")
		_transient(cr, SPARK_LIFE * 0.55)
		if head == null:
			head = cr
	for k in range(MOTE_N):
		var f: float = float(k) / float(maxi(1, MOTE_N - 1))
		var off: Vector2 = Vector2((f - 0.5) * MOTE_SPREAD_PX, 0.0)
		var mo := _beam(ctr + off - Vector2(MOTE_LEN_PX * 0.5, 0.0),
			ctr + off + Vector2(MOTE_LEN_PX * 0.5, 0.0),
			PIEZO_CHEST_M, MOTE_THICK, ENERGY_GOLD, "piezo")
		_fx.append({"node": mo, "t": -MOTE_GAP * float(k), "life": MOTE_LIFE,
			"rise": MOTE_RISE_M, "y0": mo.position.y})
	return head


# ══════════════════════════════════════════════════════════════════
#  §086 浮游炮
# ══════════════════════════════════════════════════════════════════

## 让场上的炮体节点数与逻辑炮数一致, 并把每门摆到它该在的位置。
## `drones` 是 EqGadgetBatch 的逻辑数组(元素含 ang / sx / sy / scat)。
## 086 浮游炮的立绘(缓存一次) 与显示尺寸(码) / 播放速度(帧每秒)。
## 新炮淡入时长(秒)。
const DRONE_FADE_IN := 0.30
const DRONE_PX := 26.0
const DRONE_FPS := 9.0
const DRONE_TEX_PATH := "res://assets/sprites/vfx/eq-orbdrone-idle.png"
static var _drone_tex_cache: Texture2D = null
static var _drone_tex_tried := false

func _drone_tex() -> Texture2D:
	if not _drone_tex_tried:
		_drone_tex_tried = true
		if ResourceLoader.exists(DRONE_TEX_PATH):
			_drone_tex_cache = load(DRONE_TEX_PATH)
	return _drone_tex_cache


func sextant_sync(u: Dictionary, drones: Array, orbit_r: float) -> Array:
	if not _alive():
		return []
	var nodes: Array = u.get("_sext_nodes", [])
	nodes = nodes.filter(func(x): return is_instance_valid(x))
	while nodes.size() > drones.size():
		var dead = nodes.pop_back()
		if is_instance_valid(dead):
			(dead as Node).queue_free()
	var dtex: Texture2D = _drone_tex()
	while nodes.size() < drones.size():
		# ★有立绘就用立绘。原来这里是一个 **SphereMesh 小球** —— 「白球家族」的字面意思:
		#   六门炮绕着龟转, 玩家看到的是六个紫色小球, 分不出那是"炮"还是别的什么。
		#   兜底那条(球)保留: 素材缺席时至少还看得见位置, 但那是**兜底不是设计**。
		var n: Node3D
		if dtex != null:
			var sp := Sprite3D.new()
			sp.texture = dtex
			sp.hframes = maxi(1, dtex.get_width() / maxi(1, dtex.get_height()))
			sp.shaded = false
			sp.transparent = true
			sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sp.pixel_size = (DRONE_PX * float(battle.WS)) / float(dtex.get_height())
			battle._world.add_child(sp)
			_owned.append(sp)
			n = sp
		else:
			var mi := _mi(SphereMesh.new(), Color(DRONE_COLOR.r, DRONE_COLOR.g, DRONE_COLOR.b, 0.95), "drone")
			(mi.mesh as SphereMesh).radius = DRONE_R_M
			(mi.mesh as SphereMesh).height = DRONE_R_M * 2.0
			n = mi
		## ★★新炮**淡入** 0.3 秒(2026-08-09 补上一直挂着的缺口)。
		##   没有它, 每 3 秒就有一门炮**凭空出现**在轨道上 —— 六门凑齐的过程读不出"在造炮",
		##   只读成"画面上又多了个东西"。诞生时刻记在节点 meta 上, 由 tick 每帧推。
		##   ⚠ 用 `battle._t`(战斗时钟)而不是墙钟: 顿帧/时停时它跟着停, 与别的演出同步。
		n.set_meta("born_t", float(battle._t))
		if n is Sprite3D:
			(n as Sprite3D).modulate.a = 0.0
		nodes.append(n)
	for i in range(drones.size()):
		var d: Dictionary = drones[i]
		## 淡入: 从诞生起 DRONE_FADE_IN 秒内 0 → 1(之后恒 1, 不再碰它)
		var nd_i = nodes[i] if i < nodes.size() else null
		if nd_i is Sprite3D:
			var age: float = float(battle._t) - float((nd_i as Node).get_meta("born_t", 0.0))
			if age < DRONE_FADE_IN:
				(nd_i as Sprite3D).modulate.a = clampf(age / maxf(DRONE_FADE_IN, 1e-4), 0.0, 1.0)
			elif (nd_i as Sprite3D).modulate.a < 1.0:
				(nd_i as Sprite3D).modulate.a = 1.0
		var at: Vector2
		# 轨道上此刻该在的位置(不管在不在飞散, 都先算出来 —— 回程要飞回**它**)
		var ring0: int = i % 2
		var rr0: float = orbit_r * (1.0 if ring0 == 0 else DRONE_RING_K)
		var aa0: float = float(d["ang"]) * (1.0 if ring0 == 0 else -DRONE_RING_REV)
		var home: Vector2 = (u["pos"] as Vector2) + Vector2(cos(aa0), sin(aa0)) * rr0
		if float(d.get("scat", 0.0)) > 0.0:
			# ★★三段行程(错峰去 → 停在散点 → 错峰回), 每一段各炮的延迟与时长都不同。
			#   `_ease` = SINE EASE_IN_OUT(赛博龟那条 tween 用的就是它)。
			var fe: float = float(d.get("fe", 0.0))
			var sp0: Vector2 = Vector2(float(d.get("sx", 0.0)), float(d.get("sy", 0.0)))
			var o0: Vector2 = Vector2(float(d.get("ox", 0.0)), float(d.get("oy", 0.0)))
			var t_back: float = SEXT_FIRE_DELAY + RAY_LIFE + float(d.get("bd", 0.0))
			if fe < t_back:
				# ① 去程
				var q1: float = clampf((fe - float(d.get("fd", 0.0)))
					/ maxf(0.001, float(d.get("fdur", 1.0))), 0.0, 1.0)
				at = o0.lerp(sp0, 0.5 - 0.5 * cos(PI * q1))
			else:
				# ② 回程: 飞回**轨道此刻该在的位置**
				var q2: float = clampf((fe - t_back)
					/ maxf(0.001, float(d.get("bdur", 1.0))), 0.0, 1.0)
				at = sp0.lerp(home, 0.5 - 0.5 * cos(PI * q2))
		else:
			at = (u["pos"] as Vector2) + Vector2(cos(float(d["ang"])), sin(float(d["ang"]))) * orbit_r
		# ★★2026-08-08 照赛博龟 `_tick_cyber_drones` 的被动编队(用户指定参考的第 ① 点):
		#   **双环反向公转**(内环顺、外环逆) + **悬浮上下浮动** + **平滑跟随**(lerp, 不硬贴)
		#   + **按位置翻面**。旧版是单环、硬贴、不浮动 ⇒ 读成"六个贴在圆周上的贴纸"。
		var ring: int = i % 2
		if float(d.get("scat", 0.0)) <= 0.0:
			var rr: float = orbit_r * (1.0 if ring == 0 else DRONE_RING_K)
			var aa: float = float(d["ang"]) * (1.0 if ring == 0 else -DRONE_RING_REV)
			at = (u["pos"] as Vector2) + Vector2(cos(aa), sin(aa)) * rr
		var hh: float = DRONE_LIFT + DRONE_RING_H * float(ring) 			+ sin(battle._t * DRONE_BOB_W + float(d.get("ang", 0.0))) * DRONE_BOB_A
		var want3: Vector3 = battle._world_pos(at, hh)
		var nd3: Node3D = nodes[i]
		# 平滑跟随: 首帧直接到位(否则新炮会从原点飞过来), 之后才 lerp
		if nd3.position == Vector3.ZERO:
			nd3.position = want3
		else:
			nd3.position = nd3.position.lerp(want3, clampf(DRONE_FOLLOW * 0.05, 0.0, 1.0))
		if nd3 is Sprite3D:
			(nd3 as Sprite3D).flip_h = (at.x - float((u["pos"] as Vector2).x)) < 0.0
		d["_px"] = at.x
		d["_py"] = at.y
		d["_ph"] = hh
		# 帧: 每门炮**错开相位**(用它自己的轨道角当相位) —— 六门同帧齐闪会读成一个整体在闪。
		if nodes[i] is Sprite3D:
			var sp2 := nodes[i] as Sprite3D
			var nfr: int = int(sp2.hframes)
			if nfr > 1:
				var ph: float = fposmod((battle._t * DRONE_FPS + float(d.get("ang", 0.0)) * 2.4) / float(nfr), 1.0)
				sp2.frame = clampi(int(ph * float(nfr)), 0, nfr - 1)
	u["_sext_nodes"] = nodes
	return nodes


## 一门炮打一发: 细曳光。
## ★★2026-08-08 照赛博龟被动开火重做(用户指定参考的第 ① 点)。旧版是
##   `_beam(u["pos"], tgt["pos"])` —— **一条从「携带者身上」瞬时连到目标的光柱**:
##   六门炮绕着龟转, 每一发却都从龟身中心射出去, 读不出是哪门炮打的。
##   赛博龟那套是三件: **炮口青闪 + 炮体后坐脉冲 + 一颗小而淡的弹**(它的注释明写
##   "小而淡……防20炮糊屏" —— 本件六门同时连线只会更糊)。
## `di` = 开火的是第几门炮(−1 = 不知道, 兜底回落到携带者身上)。
func sextant_shot(u: Dictionary, tgt: Dictionary, di: int = -1) -> Node3D:
	if not _alive():
		return null
	var from2: Vector2 = u["pos"]
	var lift: float = DRONE_LIFT
	var nodes: Array = u.get("_sext_nodes", [])
	var drones: Array = (u.get("eq_state", {}) as Dictionary).get("p2eq_086", {}).get("drones", [])
	if di >= 0 and di < drones.size():
		var dd: Dictionary = drones[di]
		if dd.has("_px"):
			from2 = Vector2(float(dd["_px"]), float(dd["_py"]))
			lift = float(dd.get("_ph", DRONE_LIFT))
	var d2: Vector2 = (Vector2(tgt["pos"]) - from2)
	d2 = d2.normalized() if d2.length() > 0.01 else Vector2.RIGHT
	# ① 炮口青闪
	var mz := _mi(SphereMesh.new(), Color(0.55, 0.96, 1.0, 0.92), "sext_shot")
	(mz.mesh as SphereMesh).radius = 1.0
	(mz.mesh as SphereMesh).height = 2.0
	mz.position = battle._world_pos(from2 + d2 * SHOT_MUZZLE_PX, lift)
	mz.scale = Vector3.ONE * SHOT_MUZZLE_R
	_transient(mz, SHOT_MUZZLE_SEC)
	# ② 炮体后坐脉冲(缩一下再弹回) —— 赛博龟用的就是 scale 0.82 → 1.0
	if di >= 0 and di < nodes.size() and is_instance_valid(nodes[di]):
		_fx.append({"node": nodes[di], "t": 0.0, "life": SHOT_KICK_IN + SHOT_KICK_OUT, "kick": true})
	# ③ 一颗**小而淡的弹丸**从这门炮飞到目标。
	#   ★★用户 2026-08-08:「哪里会是射线」—— 对的。赛博龟浮游炮打出去的是
	#   `VfxTex._make_bolt_texture` 的**一颗 Sprite3D 弹丸**(pixel_size 0.008 · alpha 0.65,
	#   它的注释写着"小而淡……防20炮糊屏"), 走标准弹道系统。
	#   我第一版拿 `_beam` 建了一条带再平移 —— **那还是一条线**, 不是弹。
	var bolt := Sprite3D.new()
	bolt.texture = VfxTex._make_bolt_texture(DRONE_COLOR)
	bolt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bolt.shaded = false
	bolt.transparent = true
	bolt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bolt.pixel_size = SHOT_BOLT_PS
	bolt.modulate = Color(1.0, 1.0, 1.0, SHOT_BOLT_A)
	bolt.position = battle._world_pos(from2, lift)
	battle._world.add_child(bolt)
	_owned.append(bolt)
	var fly: float = clampf((Vector2(tgt["pos"]) - from2).length() / SHOT_BOLT_SPD, 0.12, 0.5)
	_fx.append({"node": bolt, "t": 0.0, "life": fly, "bolt": true,
		"p0": from2, "p1": Vector2(tgt["pos"]), "h": lift, "tgt": tgt})
	return bolt


## 终极射线: `beams` = [[飞散点, 目标点], ...]。每条一根紫色粗光柱 + 指数余辉。
## ① 蓄力(照赛博龟): 每门炮在自己的散点上, 口部一颗**聚能光球膨胀** SEXT_CHARGE 秒。
## ★旧版**没有蓄力这一段** —— 光束凭空出现, 玩家读不到"要来了"。
## ★用每帧 tick 推进而不是 tween: 无头 CI 下 tween 推进不稳(CLAUDE.md §3.5),
##   而本层的 `_fx` 是跟着 sim delta 走的。
## 贯穿激光**线上每一个**被打中的目标各出一次火花(照赛博龟: 每个中招的都 `_hit_spark`)。
## ★旧版只打一个目标, 也就没有"线上谁被扫到了"这回事。
func sextant_ray_hit(at: Vector2) -> void:
	if not _alive():
		return
	var n := _mi(SphereMesh.new(), Color(1.0, 0.92, 1.0, 1.0), "sext_ray")
	(n.mesh as SphereMesh).radius = 1.0
	(n.mesh as SphereMesh).height = 2.0
	n.position = battle._world_pos(at, DRONE_LIFT)
	n.scale = Vector3.ONE * RAY_POP_R
	_transient(n, RAY_LIFE * 0.5, RAY_HALF)


func sextant_charge(_u: Dictionary, beams: Array) -> Array:
	if not _alive():
		return []
	var out: Array = []
	for pair in beams:
		if not (pair is Array) or (pair as Array).size() < 2:
			continue
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		var d: Vector2 = (b - a)
		d = d.normalized() if d.length() > 0.01 else Vector2.RIGHT
		var orb := _mi(SphereMesh.new(), Color(0.90, 1.0, 1.0, 0.95), "sext_charge")
		(orb.mesh as SphereMesh).radius = 1.0
		(orb.mesh as SphereMesh).height = 2.0
		orb.position = battle._world_pos(a + d * SEXT_MUZZLE_PX, DRONE_LIFT)
		orb.scale = Vector3.ONE * SEXT_ORB_R0
		_fx.append({"node": orb, "t": 0.0, "life": SEXT_CHARGE, "charge": true})
		out.append(orb)
	# ★炮身在蓄力期间**发亮**(赛博龟: modulate → (1.6,1.9,2.2))。旧版只有光球在胀,
	#   炮体本身一点反应都没有 ⇒ 读不出"是这几门炮在蓄力"。
	for nd in (_u.get("_sext_nodes", []) as Array):
		if is_instance_valid(nd) and nd is Sprite3D:
			_fx.append({"node": nd, "t": 0.0, "life": SEXT_CHARGE, "glow": true})
	return out


func sextant_ultimate(_u: Dictionary, beams: Array) -> Array:
	if not _alive():
		return []
	var out: Array = []
	for pair in beams:
		if not (pair is Array) or (pair as Array).size() < 2:
			continue
		# 身: 紫。芯: 更细的白热 —— 单层实心条读成"一块板", 双层才读成"一道光"
		#   (与 078 电弧同一条做法: 身管颜色、芯管亮)
		var n := _beam(pair[0], pair[1], DRONE_LIFT, RAY_THICK,
			Color(RAY_COLOR.r, RAY_COLOR.g, RAY_COLOR.b, 1.0), "sext_ray")
		_transient(n, RAY_LIFE, RAY_HALF)
		out.append(n)
		var core := _beam(pair[0], pair[1], DRONE_LIFT + 0.02, RAY_THICK * RAY_CORE_K,
			Color(1.0, 0.94, 1.0, 1.0), "sext_ray")
		_transient(core, RAY_LIFE * 0.8, RAY_HALF)
		# 两端: 发射端炮口闪 + 命中端爆点。旧版**两头什么都不发生** ⇒ 读不出
		#   "从这门炮打出去、打在那个目标身上"(与 082 反伤是同一种缺失)
		var muz := _mi(SphereMesh.new(), Color(1.0, 0.90, 1.0, 1.0), "sext_ray")
		(muz.mesh as SphereMesh).radius = 1.0
		(muz.mesh as SphereMesh).height = 2.0
		muz.position = battle._world_pos(pair[0], DRONE_LIFT)
		muz.scale = Vector3.ONE * RAY_MUZZLE_R
		_transient(muz, RAY_LIFE * 0.45, RAY_HALF * 0.6)
		var pop := _mi(SphereMesh.new(), Color(RAY_COLOR.r, RAY_COLOR.g, RAY_COLOR.b, 1.0), "sext_ray")
		(pop.mesh as SphereMesh).radius = 1.0
		(pop.mesh as SphereMesh).height = 2.0
		pop.position = battle._world_pos(pair[1], DRONE_LIFT)
		pop.scale = Vector3.ONE * RAY_POP_R
		_transient(pop, RAY_LIFE * 0.6, RAY_HALF)
		# ★★双层**真素材**光束(照赛博龟): 厚白核心 + 紫晕外束, **外束略久** = 收细消散感。
		#   赛博龟用的就是 `fx-energy-beam.png` 这张; 纯几何 BoxMesh 读成"一块板",
		#   有纹理的束才读成"一道能量"。⚠ 传单帧素材, 别传精灵表(memory [[project-vfx-library-rich]])。
		battle._beam_vfx(SEXT_BEAM_TEX, pair[0], pair[1], SEXT_BEAM_CORE_PX,
			Color(1.0, 1.0, 1.0, 1.0), RAY_LIFE * 0.72, DRONE_LIFT)
		battle._beam_vfx(SEXT_BEAM_TEX, pair[0], pair[1], SEXT_BEAM_HALO_PX,
			Color(RAY_COLOR.r, RAY_COLOR.g, RAY_COLOR.b, 0.75), RAY_LIFE, DRONE_LIFT)
		# 后坐: 炮体(这里用光束起点的一颗亮球代表)向后弹再回位 —— Gaster Blaster 的标志
		var d2: Vector2 = (Vector2(pair[1]) - Vector2(pair[0]))
		d2 = d2.normalized() if d2.length() > 0.01 else Vector2.RIGHT
		var kick := _mi(SphereMesh.new(), Color(0.92, 1.0, 1.0, 1.0), "sext_ray")
		(kick.mesh as SphereMesh).radius = 1.0
		(kick.mesh as SphereMesh).height = 2.0
		kick.scale = Vector3.ONE * RAY_MUZZLE_R * 0.85
		_fx.append({"node": kick, "t": 0.0, "life": SEXT_RECOIL_BACK + SEXT_RECOIL_HOME,
			"recoil": true, "p0": Vector2(pair[0]), "dir": d2})
	if not beams.is_empty():
		battle._shake(SEXT_SHAKE)   # 齐射要有分量 —— 赛博龟那一套也震(同一个幅度)
	return out


# ══════════════════════════════════════════════════════════════════
#  §087 压载舱
# ══════════════════════════════════════════════════════════════════

## 头顶水位计: 底槽(常驻) + 填充条(常驻)。填充宽度 ≡ 底槽 × 水位比(性质 ⑤)。
func dive_gauge(u: Dictionary, water: float, cap: float) -> MeshInstance3D:
	if not _alive():
		return null
	var bg = u.get("_dive_bg", null)
	if not is_instance_valid(bg):
		bg = _mi(BoxMesh.new(), Color(GAUGE_BG.r, GAUGE_BG.g, GAUGE_BG.b, 0.8), "dive_bg", false)
		((bg as MeshInstance3D).mesh as BoxMesh).size = Vector3.ONE
		u["_dive_bg"] = bg
	var fg = u.get("_dive_fg", null)
	if not is_instance_valid(fg):
		fg = _mi(BoxMesh.new(), Color(GAUGE_FG.r, GAUGE_FG.g, GAUGE_FG.b, 0.95), "dive_fg", false)
		((fg as MeshInstance3D).mesh as BoxMesh).size = Vector3.ONE
		u["_dive_fg"] = fg
	var base: Vector3 = battle._world_pos(u["pos"], GAUGE_LIFT)
	var fill: float = gauge_fill(water, cap)
	(bg as MeshInstance3D).position = base
	(bg as MeshInstance3D).scale = Vector3(GAUGE_W_M, GAUGE_H_M, 0.02)
	## 填充从左端长出来 ⇒ 中心要往右挪半个"缺口"
	(fg as MeshInstance3D).position = base + Vector3(-GAUGE_W_M * 0.5 * (1.0 - fill), 0.0, 0.01)
	(fg as MeshInstance3D).scale = Vector3(maxf(0.0001, GAUGE_W_M * fill), GAUGE_H_M * 0.62, 0.02)
	return fg


## 朝最远的敌人喷一根水柱, 体积 = 抽出来的水量 ⇒ 半径 ∝ ∛V(性质 ④)。
## ★柱长按定长径比走(JET_ASPECT × 半径), 但**不超过**到目标的真实距离 —— 水柱是
##   "喷过去"不是"穿过去", 超长会画到目标背后。
func dive_jet(u: Dictionary, tgt: Dictionary, volume: float) -> MeshInstance3D:
	if not _alive() or volume <= 0.0:
		return null
	var r: float = jet_radius(volume)
	var n := _beam(u["pos"], tgt["pos"], 0.75, r * 2.0,
		Color(JET_COLOR.r, JET_COLOR.g, JET_COLOR.b, 0.9), "dive_jet")
	n.scale.x = minf(n.scale.x, r * JET_ASPECT)
	_transient(n, JET_LIFE)
	return n


## 偷到一招时的青铜令环瞬闪。
func dive_steal(u: Dictionary) -> MeshInstance3D:
	if not _alive():
		return null
	var n := _mi(TorusMesh.new(), Color(STEAL_COLOR.r, STEAL_COLOR.g, STEAL_COLOR.b, 0.9), "dive_steal")
	(n.mesh as TorusMesh).inner_radius = STEAL_R_M * 0.82
	(n.mesh as TorusMesh).outer_radius = STEAL_R_M
	n.position = battle._world_pos(u["pos"], 1.25)
	_transient(n, STEAL_LIFE)
	return n


# ══════════════════════════════════════════════════════════════════
#  §生命周期
# ══════════════════════════════════════════════════════════════════

## 推进瞬时件的淡出。`half > 0` 走指数余辉(性质 ③), 否则线性。
func tick(delta: float) -> void:
	if _fx.is_empty():
		return
	var keep: Array = []
	for h in _fx:
		var n = h["node"]
		if not is_instance_valid(n):
			continue
		var t: float = float(h["t"]) + maxf(0.0, delta)
		h["t"] = t
		var life: float = float(h["life"])
		if t >= life:
			# ★★"kick"(炮体后坐)借的是**别人的常驻节点**(浮游炮本体) —— 寿命到了
			#   只能把 scale 还原, **绝不能 queue_free**, 否则一开火就把那门炮删掉。
			#   (这一条是写的时候就险些踩进去的: 本 tick 对所有 fx 一视同仁地 free。)
			if h.get("kick", false):
				(n as Node3D).scale = Vector3.ONE
			elif h.get("glow", false):
				(n as Sprite3D).modulate = Color(1, 1, 1, 1)   # 借的是炮体, 只还原不 free
			else:
				(n as Node).queue_free()
			continue
		var half: float = float(h.get("half", 0.0))
		var a: float = ray_alpha(t) if half > 0.0 else (1.0 - t / life)
		# ★"rise" = 沿 Y 上涌 + 负 t 延后出现。085 的"伤害转化为龟能"靠**一串依次上涌的微粒**
		#   读出来 —— 只有"往上走"这个方向才读得出是在转成龟能, 一颗静止的球读不出任何一半。
		#   ⚠ 负 t 必须显式判(t<0 完全不画): 只靠 alpha 曲线会让它一出生就满亮, 错开等于没做
		#   (082 贝壳串踩过同一个坑)。
		if h.get("bolt", false):
			# 弹丸沿 p0→目标匀速飞。★终点取目标**当前**位置(目标动了不会打空) ——
			#   这是 077/080 上被用户逐条盯出来定下的规矩。
			var bq: float = clampf(t / maxf(0.001, life), 0.0, 1.0)
			var bt = h.get("tgt", null)
			if bt is Dictionary and (bt as Dictionary).get("alive", false):
				h["p1"] = Vector2((bt as Dictionary)["pos"])
			var bp: Vector2 = (h["p0"] as Vector2).lerp(h["p1"] as Vector2, bq)
			(n as Node3D).position = battle._world_pos(bp, float(h["h"]))
			(n as Sprite3D).modulate.a = SHOT_BOLT_A
			keep.append(h)
			continue
		if h.get("kick", false):
			# 炮体后坐脉冲: 缩到 SHOT_KICK_K 再弹回。★这是**别人的常驻节点**,
			#   寿命到了只能把 scale 还原, **绝不能 queue_free**(那会把炮打没)。
			var kn: Node3D = n
			var k: float
			if t < SHOT_KICK_IN:
				k = lerpf(1.0, SHOT_KICK_K, t / maxf(0.001, SHOT_KICK_IN))
			else:
				k = lerpf(SHOT_KICK_K, 1.0, clampf((t - SHOT_KICK_IN) / maxf(0.001, SHOT_KICK_OUT), 0.0, 1.0))
			kn.scale = Vector3.ONE * k
		if h.get("recoil", true) and h.has("recoil"):
			# 后坐 → 回位。前 SEXT_RECOIL_BACK 秒往后弹, 之后弹回原点。
			var rp: Vector2 = h["p0"]
			var rd: Vector2 = h["dir"]
			var back: float
			if t < SEXT_RECOIL_BACK:
				back = SEXT_RECOIL_PX * (t / maxf(0.001, SEXT_RECOIL_BACK))
			else:
				back = SEXT_RECOIL_PX * (1.0 - clampf((t - SEXT_RECOIL_BACK) / maxf(0.001, SEXT_RECOIL_HOME), 0.0, 1.0))
			(n as MeshInstance3D).position = battle._world_pos(rp - rd * back, DRONE_LIFT)
			a = 1.0
		if h.get("charge", false):
			# 蓄力光球: 半径 R0→R1 加速膨胀(TRANS_QUAD/EASE_IN 的等价写法 q²), 亮度全程满。
			# ★"越胀越大"本身就是"要发射了"的读法 —— 旧版这一段完全没有。
			var cq: float = clampf(t / maxf(0.001, life), 0.0, 1.0)
			(n as MeshInstance3D).scale = Vector3.ONE * lerpf(SEXT_ORB_R0, SEXT_ORB_R1, cq * cq)
			a = 1.0
		if h.has("rise"):
			if t < 0.0:
				a = 0.0
			else:
				var q: float = clampf(t / maxf(0.001, life), 0.0, 1.0)
				(n as MeshInstance3D).position.y = float(h["y0"]) + float(h["rise"]) * q
				a = 1.0 - q * q
		# ★★"kick"(炮体后坐)借的是**别人的 Sprite3D**, 不是本层建的 MeshInstance3D ——
		#   底下这段统一按 MeshInstance3D 写 alpha, 对它就是 `material_override on Nil`
		#   (实拍日志里 756 条)。它的 scale 上面已经写完了, 到这里直接收工。
		if h.get("glow", false):
			# 蓄力发亮: 越接近发射越亮(赛博龟是一次性 tween 到 (1.6,1.9,2.2), 这里连续推)
			var gq: float = clampf(t / maxf(0.001, life), 0.0, 1.0)
			(n as Sprite3D).modulate = Color(1, 1, 1, 1).lerp(SEXT_GLOW_COL, gq)
			keep.append(h)
			continue
		if h.get("kick", false):
			keep.append(h)
			continue
		var m = (n as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			var c: Color = (m as StandardMaterial3D).albedo_color
			(m as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, a)
		keep.append(h)
	_fx = keep


## 撤掉挂在某个单位身上的**常驻件**(浮游炮体 + 水位计)。返回 free 了几个。
func detach(u: Dictionary) -> int:
	var freed: int = 0
	for n in u.get("_sext_nodes", []):
		if is_instance_valid(n):
			(n as Node).queue_free()
			freed += 1
	u.erase("_sext_nodes")
	for k in ["_dive_bg", "_dive_fg"]:
		var nd = u.get(k, null)
		if is_instance_valid(nd):
			(nd as Node).queue_free()
			freed += 1
		u.erase(k)
	return freed


## 撤场: free 掉本层还活着的所有节点。返回真的 free 了几个。
func clear() -> int:
	var freed: int = 0
	for n in _owned:
		if is_instance_valid(n):
			(n as Node).queue_free()
			freed += 1
	_owned.clear()
	_fx.clear()
	return freed
