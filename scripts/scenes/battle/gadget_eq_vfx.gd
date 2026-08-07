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

## 086 浮游炮
const DRONE_R_M := 0.16          ## 炮体半径(米)
const DRONE_COLOR := Color(0.70, 0.86, 1.0)
const DRONE_LIFT := 1.55         ## 环绕高度(米·在龟头顶上方)
const SHOT_LIFE := 0.16          ## 射击曳光存续(秒)
const SHOT_THICK := 0.035        ## 曳光粗细(米)
const RAY_LIFE := 0.70           ## 终极射线存续(秒)
const RAY_HALF := 0.20           ## 余辉半衰期(秒)
const RAY_THICK := 0.20          ## 终极射线粗细(米)
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
	return exp(-log(2.0) * maxf(0.0, t) / RAY_HALF)


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
	var r: float = spark_radius(energy)
	var n := _mi(SphereMesh.new(), Color(SPARK_COLOR.r, SPARK_COLOR.g, SPARK_COLOR.b, SPARK_ALPHA), "piezo")
	(n.mesh as SphereMesh).radius = 1.0
	(n.mesh as SphereMesh).height = 2.0
	n.position = battle._world_pos(u["pos"], 0.85)
	n.scale = Vector3.ONE * r
	_transient(n, SPARK_LIFE)
	return n


# ══════════════════════════════════════════════════════════════════
#  §086 浮游炮
# ══════════════════════════════════════════════════════════════════

## 让场上的炮体节点数与逻辑炮数一致, 并把每门摆到它该在的位置。
## `drones` 是 EqGadgetBatch 的逻辑数组(元素含 ang / sx / sy / scat)。
## 086 浮游炮的立绘(缓存一次) 与显示尺寸(码) / 播放速度(帧每秒)。
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
		nodes.append(n)
	for i in range(drones.size()):
		var d: Dictionary = drones[i]
		var at: Vector2
		if float(d.get("scat", 0.0)) > 0.0:
			at = Vector2(float(d.get("sx", 0.0)), float(d.get("sy", 0.0)))   # 终极演出期间飞散在外
		else:
			at = (u["pos"] as Vector2) + Vector2(cos(float(d["ang"])), sin(float(d["ang"]))) * orbit_r
		(nodes[i] as Node3D).position = battle._world_pos(at, DRONE_LIFT)
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
func sextant_shot(u: Dictionary, tgt: Dictionary) -> MeshInstance3D:
	if not _alive():
		return null
	var n := _beam(u["pos"], tgt["pos"], DRONE_LIFT * 0.8, SHOT_THICK,
		Color(DRONE_COLOR.r, DRONE_COLOR.g, DRONE_COLOR.b, 0.8), "sext_shot")
	_transient(n, SHOT_LIFE)
	return n


## 终极射线: `beams` = [[飞散点, 目标点], ...]。每条一根紫色粗光柱 + 指数余辉。
func sextant_ultimate(_u: Dictionary, beams: Array) -> Array:
	if not _alive():
		return []
	var out: Array = []
	for pair in beams:
		if not (pair is Array) or (pair as Array).size() < 2:
			continue
		var n := _beam(pair[0], pair[1], DRONE_LIFT, RAY_THICK,
			Color(RAY_COLOR.r, RAY_COLOR.g, RAY_COLOR.b, 1.0), "sext_ray")
		_transient(n, RAY_LIFE, RAY_HALF)
		out.append(n)
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
			(n as Node).queue_free()
			continue
		var half: float = float(h.get("half", 0.0))
		var a: float = ray_alpha(t) if half > 0.0 else (1.0 - t / life)
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
