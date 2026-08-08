class_name ArcaneEqVfx
extends RefCounted
## arcane_eq_vfx.gd — 法器三件新装备的演出层
## 088 涨潮碑 · 089 蚀月符纸 · 090 镇海杵
##
## 效果本体在 `scripts/systems/equip/eq_arcane_batch.gd`(EqArcaneBatch), 由它 `new` 出本类。
## 契约 = `docs/plans/20260806-实装契约-批④.md` §7。
##
## ══════════════════════════════════════════════════════════════════════
##  ★三条自我约束(逐条对应踩过的坑)
## ══════════════════════════════════════════════════════════════════════
## ① **零素材**: 全部是程序化 `ArrayMesh`/`SurfaceTool` + Godot 内置图元, 不新建资源、
##    也**没有借用任何别件装备的立绘**(用户铁律「不复用素材除非点名」——程序化几何不产图,
##    不吃这条约束)。
## ② **不用 tween**: 无头 CI 下 `create_tween()` 推进不稳(CLAUDE.md §3.5,
##    `verify_pirate_hook` 为此连红三次), 且走 sim 的 delta 才跟时停/换路同步。
##    全部生命周期由本文件的 `tick(delta)` 推进 —— 门禁可以同步喂任意 delta。
## ③ **形态由闭式解给, 不手调系数**(memory [[fb-match-reference-by-measured-curve]]):
##    三条曲线各有物理模型, 全部抽成 `static func` 供门禁直接验, 不必建节点、不必等演出。
##
## ⚠ 朝向坑(memory [[fb-axis-y-plus-rotation-cancels]]): 本文件**不用 Sprite3D**,
##   直接建世界坐标顶点 —— 没有 `axis = AXIS_Y` 与 `rotation.x = -90` 互相抵消那层歧义。
##   贴地几何一律是 y = GROUND_Y 的水平顶点。
##
## ⚠ 材质一律走 `material_override`, 不用 `set_surface_override_material` ——
##   后者在 `--headless` dummy renderer 下每设一次刷一条 `Parameter "material" is null.`。


# ══════════════════════════════════════════════════════════════════
#  §物理常数 —— 每条都对应一个模型, 不是手调出来的
# ══════════════════════════════════════════════════════════════════

## ① 088 碑体上涌: 临界阻尼(ζ=1)阶跃响应 x̂(t) = 1 − (1+ωt)·e^(−ωt)。
##    性质: x̂(0)=0 · 单调增 · **恒 < 1(永不过冲)** —— 碑是"顶上来"不是"弹出来"。
##    ω 用「上涌到 98% 所需时间」定标: (1+ωt)e^(−ωt)=0.02 ⇒ ωt≈5.83。
const RISE_WT98 := 5.834681
## 碑从冒头到站定用的秒数
const RISE_SEC := 0.55
## 碑体尺寸(码): 宽 / 厚 / 高
const STELE_W_PX := 26.0
const STELE_D_PX := 14.0
const STELE_H_PX := 78.0

## ② 潮涌环(每秒一跳的那一圈): **匀速**外扩 —— 浅水重力波在固定水深下相速恒定,
##    所以 r(t) = R·(t/T) 是线性的, 不是爆轰那种减速的。
const PULSE_SEC := 0.55

## ③ 090 猛砸: **Sedov–Taylor 点爆轰** r ∝ t^(2/5) —— 强激波在均匀介质里的自相似解。
##    与潮涌环的线性外扩形成对比(一个是波、一个是爆), 肉眼分得出来。
const SEDOV_EXP := 0.4
const SLAM_SEC := 0.85

## ④ 089 符纸悬浮: 简谐上下 + 【面内】小幅摇摆。周期 1.6 秒, 幅度 4 码。
const BOB_OMEGA := 3.926990816987241
const BOB_AMP_PX := 4.0
## ★2026-08-07 拆掉的雷 ——【周期性整张消失】
##   旧实现: 符纸是一块 16×22×0.6 码的 BoxMesh, 绕 Y 轴**匀速自转** 1.35 rad/s。
##   薄片转过 π/1.35 = **2.33 秒就正好侧对镜头**, 那一刻投影宽度从 16 码掉到 0.6 码 ⇒ 整张消失。
##   干净台 22 倍实拍逐帧坐实(改前图 `_vfxlab_bf089_0/_2.png`: 一张是白方块、另一张只剩一根竖线)。
##   现在改成**恒定正对镜头 + 面内摇摆**(见 `face_basis` / `talisman_roll`):
##   投影面积恒定 ⇒ "转到侧面"这件事在**结构上**不可能再发生, 不是靠调参数躲开。
const TALISMAN_ROLL_MAX := 0.22
## 面内摇摆角频率: TAU/3 ⇒ 3 秒一个来回(有生气, 又慢到不抢眼)
const TALISMAN_ROLL_OMEGA := 2.0943951023931953
## 符纸尺寸(码)与悬停高度(米)
## ★2026-08-07 放大 ——【实战下只有 10.8×9.3 屏幕像素】
##   实战默认视角(1280×720·相机 (0,28,22) look_at (0,0.6,0)·fov 40)的标尺:
##     · 与视轴垂直的方向  28.148 px/米 = **0.6755 px/码**
##     · **世界竖直**方向还要乘 22/35.139 = 0.6261 ⇒ 只有 **0.4229 px/码**
##   旧版符纸是【世界竖直】的片 ⇒ 16 码宽 → 10.8 px、22 码高 → 9.3 px, 低于头顶徽章的 16 px。
##   改成正对镜头后两个方向都吃满 0.6755, 再把尺寸提到 30×44 码 ⇒ **20.3 × 29.7 屏幕像素**。
const TALISMAN_W_PX := 30.0
const TALISMAN_H_PX := 44.0
## 悬停高度(米)。★1.05 → 1.62: 放大到 30×44 码之后, 1.05 米正好把符纸压在目标龟的
##   脸和身体上(实拍 `_vfxlab_af089_0.png` 一看就知道) —— 治好了"看不见"却挡住了被贴的人。
##   抬到 1.62 让它浮在龟壳上沿, 既完整可见又不遮挡。
const TALISMAN_Y := 1.62
## 符纸程序化纹理的分辨率(与 30:44 同比 —— 不同比会把月牙拉扁)
const TALISMAN_TEX_W := 64
const TALISMAN_TEX_H := 94
## 月牙的几何(纹理像素): 外圆 / 被减掉的圆。两圆之差 = 月牙。
const MOON_C := Vector2(32.0, 30.0)
const MOON_R := 17.0
const MOON_CUT_C := Vector2(39.0, 28.0)
const MOON_CUT_R := 14.0
## 符纸的四种语义色(程序化纹理里只出现这四种 + 内框线, 门禁数色阶)
const TX_PAPER := Color(0.20, 0.10, 0.34, 0.82)   # 纸面(半透深紫)
const TX_EDGE := Color(0.80, 0.58, 1.00, 1.00)    # 外边框
const TX_INNER := Color(0.36, 0.20, 0.56, 0.94)   # 内框细线
const TX_MOON := Color(0.96, 0.92, 1.00, 1.00)    # 月牙
const TX_RUNE := Color(0.86, 0.66, 1.00, 1.00)    # 符文笔画

## ⑤ 090 浪潮每一跳的抛物线拱高 = 跨度的这个比例(4·h·s(1−s) 的 h)
const ARC_PEAK_FRAC := 0.18
## 浪潮折线的带宽(码)与存活秒数
const WAVE_W_PX := 18.0
const WAVE_SEC := 0.42
## 符纸转移那道光带的存活秒数
const TRANSFER_SEC := 0.30
## 起跳光柱的存活秒数(由调用方传入起跳时长时以它为准)
const PILLAR_H_M := 3.6

## ⑥ 088 的【区域边界】(2026-08-07): 原来碑的那一圈与潮涌环用的是同一张软环网格 ——
##    内沿渐隐、外沿也只是 0.30 alpha 的软边, 于是"圈内 / 圈外"根本读不出来,
##    而 088 的攻速增益**只在圈内**, 边界就是这件的全部信息。
##    改法三条(都在 `_build_boundary_ring` 里, **不动潮涌/猛砸共用的 `_build_ring`**):
##      · 外沿做成**硬边**(BOUNDARY_RIM 那一窄圈 alpha 拉满) —— 一眼看得出线在哪
##      · 圈内铺一层**极淡的底色**(BOUNDARY_FILL) —— "里面"与"外面"不是同一块地
##      · 沿圈每 15° 一根**向内的刻度**(BOUNDARY_TICKS) —— 读作"这是一条界线"而不是"一圈光"
const BOUNDARY_RIM := 0.955          # 硬边从这个归一半径起到 1.0
const BOUNDARY_FILL := 0.085         # 圈内底色 alpha
const BOUNDARY_TICKS := 24           # 刻度根数(每 15°)
const BOUNDARY_TICK_IN := 0.86       # 刻度从这个归一半径伸到硬边

## ⑦ 090 起跳的三件读数(2026-08-07): 原来只有一根**不动的白光柱**, 起跳/滞空/砸落
##    在画面上完全一样 —— 节奏读不出来。现在:
##      · **水柱**高度 ≡ 携带者的真实滞空高度 `u["height"]`(不是自己另跑一条曲线)
##      · **地面影子**随高度收缩 —— 这是"它在多高"的经典读数
##      · **落点预告环**从 1.18× 收到 1.0×, 收满的那一刻就是砸落 ⇒ 读得出"要砸了"
const LEAP_SHADOW_PX := 96.0         # 贴地影子在【地面】时的直径(码)
const LEAP_SHADOW_MIN := 0.45        # 升到顶点时影子缩到这个比例
## ★收势环(wind-up)的终了半径(码)与起手倍数。
##   ⚠ **诚实记录**: 它不是"1000 码 AOE 的预告圈" —— 1000 码半径 = 2000 码直径,
##   在 1280 px 的屏幕上根本装不下(实拍确认整圈在画面外)。所以这里画的是
##   **收势**(起跳时张开、砸落瞬间收到最小), 表达的是"什么时候砸"而不是"砸多大";
##   "砸多大"由砸落那一圈 Sedov 激波(半径 = 真实的 SLAM_R_PX)自己说。
const LEAP_WINDUP_PX := 110.0
const LEAP_TELE_R0 := 2.6            # 收势环起手是终了半径的这个倍数
## ★下面两个是**结算侧数值的镜像**, 门禁焊死它们与 `EqArcaneBatch` 逐个相等:
##   `SLAM_R_PX ≡ EqArcaneBatch.PESTLE_RADIUS` · `LEAP_APEX_M ≡ EqArcaneBatch.PESTLE_APEX_M`。
##   为什么要镜像而不是直接引用: 本文件与 `EqArcaneBatch` 的引用是**单向**的
##   (见文件头 —— 效果本体引演出层的 COL_*), 反向再引一次 const 会形成循环依赖、Godot 解析期就炸。
##   ⇒ 拿"门禁焊死"换"不循环依赖", 与 `BladeEqVfx.WAVE_SPD` 是同一条老路。
const SLAM_R_PX := 1000.0
const LEAP_APEX_M := 2.4

## 贴地几何的离地高度(米) —— 高于地板顶面才不会被吞
const GROUND_Y := 0.06
## 环的经向分段
const RING_LON := 48
## 浪潮拱线的分段数
const ARC_SEG := 12

## 四件演出的语义色。★**颜色的单一事实源在演出层**(本文件), 效果本体
## `EqArcaneBatch` 反过来引用 `ArcaneEqVfx.COL_*` 当伤害飘字色 —— 引用是**单向**的,
## 免得两个 class_name 互相引用形成循环依赖(Godot 解析 const 时会炸)。
const COL_TIDE := Color("#5fd8ff")     # 088 潮汐(青)
const COL_STELE_BODY := Color(0.30, 0.52, 0.62, 0.96)   # 碑身: 湿石青(MIX, 不发亮)
const COL_STELE_BASE := Color(0.16, 0.28, 0.34, 0.96)   # 底座: 更暗一档
const STELE_BASE_K := 1.55                              # 底座相对碑身宽多少倍
const COL_STELE_RUNE := Color(0.62, 0.94, 1.0, 1.0)     # 顶端符带: 亮潮汐青(MIX, 提亮不靠加法)
const COL_MOON := Color("#b98cff")     # 089 蚀月(紫)
const COL_SLAM := Color("#7ec8ff")     # 090 猛砸(蓝白)
const COL_WAVE := Color("#8ff0ff")     # 090 浪潮(浅青)

## 节点身份标记(程序生成的网格 `resource_path` 是空串, 按路径数会全数成 0)
const META_KEY := "arcane_eq_vfx"
## `_owned` 上限, 同 SynergyVfx.OWNED_CAP 的口径(最后一道闸)
const OWNED_CAP := 256

var battle

## 本层建出来、还活着的节点(撤场用)。★存节点不存单位字典 —— CLAUDE.md §3.2。
var _owned: Array = []
## 正在播的特效 [{node, t, life, kind, …}] —— 每帧由 `tick()` 推进, **不用 tween**。
var _fx: Array = []
## 单位半径的贴地环网格(整局建一次; 材质**不能**共享, 会串色)
var _mesh_ring: ArrayMesh = null
## 088 的区域边界环(硬边 + 圈内底色 + 刻度) —— 与上面那张软环**分开**, 见 `_build_boundary_ring`
var _mesh_boundary: ArrayMesh = null
## 089 符纸的程序化纹理(整局画一次)。★存实例上不存 static —— static 的话进程退出时
##   Godot 会刷 `N resources still in use at exit`(relic_eq_vfx.gd:137 记的同款坑)。
var _tex_talisman: ImageTexture = null


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等演出(契约 §7: 全部同步判定)
# ══════════════════════════════════════════════════════════════════

## 碑体上涌的归一高度 x̂(t/T)。ζ=1 临界阻尼阶跃响应的解析解。
## ★性质(门禁逐条验): x̂(0)=0 · 严格单调增 · **恒 < 1** · x̂(T)≈0.98。
static func rise_frac(t: float, sec: float) -> float:
	if t <= 0.0 or sec <= 0.0:
		return 0.0
	var w: float = RISE_WT98 * (t / sec)
	return 1.0 - (1.0 + w) * exp(-w)


## 潮涌环半径: **匀速**外扩(浅水波相速恒定) r(t) = R·t/T。
static func pulse_radius(t: float, sec: float, r_max: float) -> float:
	if sec <= 0.0:
		return r_max
	return r_max * clampf(t / sec, 0.0, 1.0)


## 猛砸激波半径: Sedov–Taylor 自相似解 r(t) = R·(t/T)^(2/5)。
## ★与 `pulse_radius` 的**线性**形成对比: 同样走到一半时间, 爆轰已经跑了 R·0.5^0.4 = 0.758R,
##   而潮涌环才 0.5R —— 前段快后段慢, 这是"爆"该有的样子。
static func blast_radius(t: float, sec: float, r_max: float) -> float:
	if sec <= 0.0:
		return r_max
	return r_max * pow(clampf(t / sec, 0.0, 1.0), SEDOV_EXP)


## 符纸悬浮的竖直偏移(码)。简谐: A·sin(ωt)。
static func bob_offset(t: float) -> float:
	return BOB_AMP_PX * sin(BOB_OMEGA * t)


## 符纸的【面内】摇摆角(弧度)。有界简谐 —— 幅度恒 ≤ TALISMAN_ROLL_MAX。
## ★这是"自转"的替代品: 旧的匀速自转会走遍 [0, 2π) 从而必然经过侧对镜头的相位;
##   有界摇摆连"侧对"那个角度都到不了, 而且它是**绕视轴**转的, 根本不改变投影面积。
static func talisman_roll(t: float) -> float:
	return TALISMAN_ROLL_MAX * sin(TALISMAN_ROLL_OMEGA * t)


## 让一块【局部平面在 XY、法线 +Z】的片正对镜头, 并绕视轴滚 `roll` 弧度。
##
## ★可验证性质(门禁逐条验, 与 roll 无关):
##     返回 basis 的 **+Z 轴 ≡ −cam_fwd**  ⇒ 片永远正对镜头, 投影面积恒定
##     三根轴两两正交且长度 ≡ 1            ⇒ 不会顺手把片拉伸/镜像
##   任何"绕世界 Y 轴转"的实现都过不了第一条 —— 这正是旧版消失的根因。
static func face_basis(cam_fwd: Vector3, roll: float) -> Basis:
	var n: Vector3 = -cam_fwd.normalized()
	var ref: Vector3 = Vector3.UP
	if absf(n.dot(ref)) > 0.999:
		ref = Vector3.FORWARD
	var right: Vector3 = ref.cross(n).normalized()
	var up: Vector3 = n.cross(right).normalized()
	var c: float = cos(roll)
	var s: float = sin(roll)
	return Basis(right * c + up * s, up * c - right * s, n)


## 镜头前向(单位向量)。
## ★拿不到相机时退回**默认战斗机位的视轴**(0,28,22) → (0,0.6,0) —— 本项目相机方向恒定
##   (缩放只改 fov、平移只挪机位, 见 `RB._cam_zoom_base` 的算法), 所以这个退路是真值不是凑数。
func _cam_forward() -> Vector3:
	if battle != null and is_instance_valid(battle._cam):
		return -((battle._cam as Camera3D).global_transform.basis.z).normalized()
	return Vector3(0.0, -27.4, -22.0).normalized()


# ══════════════════════════════════════════════════════════════════
#  §089 符纸的程序化纹理 —— 零素材(代码现画一张 Image, 不落任何资源文件)
# ══════════════════════════════════════════════════════════════════

## 一张符纸的图: 外边框 + 内框细线 + 月牙 + 符文笔画。
##
## ★为什么非画不可: 改前干净台 22 倍拉近占大半屏, 符纸是**一张纯白空白四边形** ——
##   没有符文、没有月、没有边框。装备叫"蚀月符纸", 画面上却没有任何一个字对得上。
## ★门禁量的是**这张 Image 的真实像素**(色阶数 / 边框比纸面亮 / 月牙面积占外圆的比例
##   落在"是月牙不是满月也不是空"的区间 / 符文区亮像素数), 不是"我看着像"。
static func talisman_tex_image() -> Image:
	var img := Image.create(TALISMAN_TEX_W, TALISMAN_TEX_H, false, Image.FORMAT_RGBA8)
	img.fill(TX_PAPER)
	var w: int = TALISMAN_TEX_W
	var h: int = TALISMAN_TEX_H
	# ① 外边框(3 px)
	for y in range(h):
		for x in range(w):
			if x < 3 or x >= w - 3 or y < 3 or y >= h - 3:
				img.set_pixel(x, y, TX_EDGE)
	# ② 内框细线(inset 5, 1 px)
	for x in range(5, w - 5):
		img.set_pixel(x, 5, TX_INNER)
		img.set_pixel(x, h - 6, TX_INNER)
	for y in range(5, h - 5):
		img.set_pixel(5, y, TX_INNER)
		img.set_pixel(w - 6, y, TX_INNER)
	# ③ 月牙 = 外圆减去偏置的内圆(这是"蚀月"四个字的字面几何)
	for y in range(h):
		for x in range(w):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			if p.distance_to(MOON_C) <= MOON_R and p.distance_to(MOON_CUT_C) > MOON_CUT_R:
				img.set_pixel(x, y, TX_MOON)
	# ④ 符文笔画: 一根中竖 + 三道横 + 两笔斜挑(下半张)
	_stroke(img, 30, 52, 34, 88)
	_stroke(img, 19, 56, 45, 59)
	_stroke(img, 23, 67, 41, 70)
	_stroke(img, 17, 78, 47, 81)
	## 两笔斜挑。★上界收在 y = 89 —— 再往下就压到 91 起的下边框上, 会把边框啃出缺口
	##   (纹理是自己画的, 越界不报错、只是画面上少一段边, 属于"改完不看图就发现不了"那类)。
	for k in range(6):
		_stroke(img, 22 - k, 82 + k, 25 - k, 84 + k)
		_stroke(img, 39 + k, 82 + k, 42 + k, 84 + k)
	return img


## 画一个实心矩形笔画(纹理像素坐标, 含边界), 越界自动裁掉。
static func _stroke(img: Image, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(maxi(0, mini(y0, y1)), mini(img.get_height() - 1, maxi(y0, y1)) + 1):
		for x in range(maxi(0, mini(x0, x1)), mini(img.get_width() - 1, maxi(x0, x1)) + 1):
			img.set_pixel(x, y, TX_RUNE)


## ★优先用**真立绘**(PixelLab 出的黄纸朱砂符, 2026-08-07)。
##   `talisman_tex_image()` 那张程序化的留着当兜底 —— 它是"几个矩形拼的符文",
##   v0.19.37 之前它甚至是一张**纯白空板**(10.8×9.3 屏幕像素, 无符文/无月/无边框)。
##   ⚠ 返回类型放宽到 Texture2D: 立绘是 CompressedTexture2D, 不是 ImageTexture。
##     写死 ImageTexture 会在这里静默走不进去(只有实拍能发现)。
const TALISMAN_TEX_PATH := "res://assets/sprites/vfx/eq-talisman.png"
var _tex_talisman_file: Texture2D = null
var _tex_talisman_tried := false

func _talisman_tex() -> Texture2D:
	if not _tex_talisman_tried:
		_tex_talisman_tried = true
		if ResourceLoader.exists(TALISMAN_TEX_PATH):
			_tex_talisman_file = load(TALISMAN_TEX_PATH)
	if _tex_talisman_file != null:
		return _tex_talisman_file
	if _tex_talisman == null:
		_tex_talisman = ImageTexture.create_from_image(talisman_tex_image())
	return _tex_talisman


## ⑦ 起跳影子的收缩比例。性质(门禁逐条验): f(0) ≡ 1 · f(apex) ≡ LEAP_SHADOW_MIN · 严格单调减。
## ★"影子随高度收缩"是全行业通用的高度读数, 不是我编的曲线 —— 所以它可以是线性的。
static func leap_shadow_scale(h_m: float, apex_m: float) -> float:
	return lerpf(1.0, LEAP_SHADOW_MIN, clampf(h_m / maxf(0.001, apex_m), 0.0, 1.0))


## ⑦ 收势环的半径。性质: r(0) = LEAP_TELE_R0·R · **r(1) ≡ R(精确)** · 严格单调减。
## ★r(1) 精确落在终了半径上 —— 收不到位就读不出“砸落就是现在”。
static func telegraph_radius(q: float, r_max: float) -> float:
	return r_max * lerpf(LEAP_TELE_R0, 1.0, clampf(q, 0.0, 1.0))


## 浪潮一跳的拱高(米制无关的比例形): 4·h·s(1−s), s∈[0,1]。
## ★s=0 与 s=1 处为 0(两端贴着单位), 峰在 s=0.5 处 = h。
static func arc_height(s: float, peak: float) -> float:
	var x: float = clampf(s, 0.0, 1.0)
	return 4.0 * peak * x * (1.0 - x)


## 折线总长(码) —— 浪潮跳了多远的可量形式。
static func path_length(pts: Array) -> float:
	var sum: float = 0.0
	for i in range(1, pts.size()):
		sum += (pts[i] as Vector2).distance_to(pts[i - 1] as Vector2)
	return sum


# ══════════════════════════════════════════════════════════════════
#  §几何 —— 程序化 ArrayMesh, 零素材
# ══════════════════════════════════════════════════════════════════

static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


static func _flat(r: float, th: float, a: float) -> Array:
	return [Vector3(r * cos(th), GROUND_Y, r * sin(th)), Color(1, 1, 1, a)]


## 单位半径的贴地环(外沿硬 = 区域边界, 内沿渐隐)。
static func _build_ring() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		for q in [[0.80, 0.0, 0.96, 0.85], [0.96, 0.85, 1.0, 0.30]]:
			var r0: float = q[0]
			var a0: float = q[1]
			var r1: float = q[2]
			var a1: float = q[3]
			_tri(st, _flat(r0, t0, a0), _flat(r1, t0, a1), _flat(r1, t1, a1))
			_tri(st, _flat(r0, t0, a0), _flat(r1, t1, a1), _flat(r0, t1, a0))
	st.commit(mesh)
	return mesh


func _ring_mesh() -> ArrayMesh:
	if _mesh_ring == null:
		_mesh_ring = _build_ring()
	return _mesh_ring


## 088 专用的【区域边界】环(单位半径)。★与 `_build_ring` 分开是**有意的**:
##   那张软环是给"潮涌 / 猛砸"这类**扩散波**用的, 波本来就该软; 而 088 要的是一条**界线**。
##   共用一张 = 又要软又要硬, 只能两边都不像。三层结构:
##     ① 圈内底色(0 → BOUNDARY_TICK_IN, alpha = BOUNDARY_FILL) —— "里面"是一块地
##     ② 硬边(BOUNDARY_RIM → 1.0, alpha = 1.0, 内外都不渐隐) —— 线在哪一眼看得出
##     ③ 每 15° 一根向内的刻度 —— 读作界线而不是"一圈光"
static func _build_boundary_ring() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		# ① 圈内底色: 从圆心铺到刻度起点(用扇形三角, 内半径 0)
		_tri(st, _flat(0.0, t0, BOUNDARY_FILL), _flat(BOUNDARY_TICK_IN, t0, BOUNDARY_FILL),
			_flat(BOUNDARY_TICK_IN, t1, BOUNDARY_FILL))
		# ② 硬边: 内外沿都不渐隐 ⇒ 边界是"线"不是"雾"
		_tri(st, _flat(BOUNDARY_RIM, t0, 1.0), _flat(1.0, t0, 1.0), _flat(1.0, t1, 1.0))
		_tri(st, _flat(BOUNDARY_RIM, t0, 1.0), _flat(1.0, t1, 1.0), _flat(BOUNDARY_RIM, t1, 1.0))
	# ③ 向内的刻度(每 TAU/BOUNDARY_TICKS 一根)
	var half: float = TAU / float(BOUNDARY_TICKS) * 0.16
	for k in range(BOUNDARY_TICKS):
		var th: float = float(k) / float(BOUNDARY_TICKS) * TAU
		_tri(st, _flat(BOUNDARY_TICK_IN, th - half, 0.0), _flat(BOUNDARY_RIM, th - half, 0.95),
			_flat(BOUNDARY_RIM, th + half, 0.95))
		_tri(st, _flat(BOUNDARY_TICK_IN, th - half, 0.0), _flat(BOUNDARY_RIM, th + half, 0.95),
			_flat(BOUNDARY_TICK_IN, th + half, 0.0))
	st.commit(mesh)
	return mesh


func _boundary_mesh() -> ArrayMesh:
	if _mesh_boundary == null:
		_mesh_boundary = _build_boundary_ring()
	return _mesh_boundary


## 边界环的材质: **MIX 而不是 ADD**。ADD 会把硬边和刻度一起加成一片白, 边界反而更糊
##   —— 与 089 符纸那条同源(`_mat_paper` 的注释)。
static func _mat_boundary(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = 9
	m.albedo_color = col
	return m


static func _mat(col: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	## ⚠ render_priority 在【材质】上, MeshInstance3D 没有这个属性
	m.render_priority = prio
	m.albedo_color = col
	return m


## 贴图片材质(符纸用)。★与 `_mat` 的两处关键差别:
##   · **MIX 而不是 ADD** —— ADD 会把纸面/边框/符文一起加成一片白, 正是旧版"纯白空白"的一半原因
##   · `no_depth_test` —— 符纸贴在敌人身上, 不穿透就会被立绘挡掉半张
## **实体**材质(碑体用)。★与 `_mat` 的关键差别是 **MIX 而不是 ADD**:
## ADD 下一个实心盒子的正反两面(CULL_DISABLED)会互相叠加 ⇒ 青色 #5fd8ff **爆成纯白**,
## 实拍里 088 的碑就是一块**纯白长方块**(白球/白块家族)。实体物要 MIX + 只画正面。
static func _mat_solid(col: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = prio
	m.albedo_color = col
	return m


static func _mat_paper(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = true
	m.render_priority = 11
	m.albedo_color = Color(1, 1, 1, 1)
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素画风, 别插值糊掉笔画
	return m


func _adopt(n: Node3D, kind: String) -> void:
	n.set_meta(META_KEY, kind)
	battle._world.add_child(n)
	if _owned.size() >= OWNED_CAP:
		_owned = _owned.filter(func(x): return is_instance_valid(x))
	_owned.append(n)


func _node(mesh: Mesh, mat: StandardMaterial3D, org: Vector3, kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = org
	_adopt(mi, kind)
	return mi


## 一条 A→B 的光带(细长盒体, 沿 +X 拉伸后绕 Y 对齐)。
func _band(a2d: Vector2, b2d: Vector2, col: Color, width_px: float, y_m: float) -> MeshInstance3D:
	var wf: Vector3 = battle._world_pos(a2d, y_m)
	var wt: Vector3 = battle._world_pos(b2d, y_m)
	var seg: Vector3 = wt - wf
	var l: float = seg.length()
	if l < 0.001:
		return null
	var bm := BoxMesh.new()
	bm.size = Vector3(l, width_px * float(battle.WS), width_px * float(battle.WS))
	var mi := _node(bm, _mat(col, 12), wf + seg * 0.5, "band")
	mi.rotation.y = -atan2(seg.z, seg.x)
	return mi


# ══════════════════════════════════════════════════════════════════
#  §088 涨潮碑
# ══════════════════════════════════════════════════════════════════

## 立碑: 一圈贴地边界(半径 = 效果半径) + 一块从地里顶上来的碑体。
## ★环的半径**就是** 250 码的效果半径 —— 不是"贴片尺寸"
##   (memory [[fb-verify-must-run-the-real-path]] 那次把效果半径当贴片尺寸, 公式全对但长 19.2 米)。
func stele_raise(pos2d: Vector2, radius_px: float, sec: float) -> Node3D:
	if not _has_world():
		return null
	var root := Node3D.new()
	root.position = battle._world_pos(pos2d, 0.0)
	_adopt(root, "stele")
	# ★2026-08-07 换成【区域边界环】: 硬外沿 + 圈内底色 + 每 15° 一根刻度。
	#   旧的是与潮涌/猛砸共用的软环 ⇒ 圈内与圈外读不出差别, 而 088 的攻速增益
	#   **只在圈内**, 那条边界就是这件的全部信息。共用软环也照旧留着(潮涌还在用)。
	var ring := MeshInstance3D.new()
	ring.mesh = _boundary_mesh()
	ring.material_override = _mat_boundary(COL_TIDE)
	ring.scale = Vector3(radius_px * float(battle.WS), 1.0, radius_px * float(battle.WS))
	root.add_child(ring)
	# ★★2026-08-08 实拍(_vfxlab_p2eq_088)后重做碑体。旧版是**一块纯白长方块** ——
	#   根因不是颜色而是 `_mat` 走 **ADD**: 实心盒子的正反两面叠加把 #5fd8ff 爆成白。
	#   ⇒ 走 `_mat_solid`(MIX + 只画正面), 并拆成三段做出**碑的剪影**:
	#     底座(宽而矮·暗) / 碑身(窄而高·石青) / 顶端符带(亮青, 这块是"它在生效"的信号)
	var ws: float = float(battle.WS)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(STELE_W_PX * ws, STELE_H_PX * ws, STELE_D_PX * ws)
	slab.mesh = bm
	slab.material_override = _mat_solid(COL_STELE_BODY, 10)
	root.add_child(slab)
	var base := MeshInstance3D.new()
	var bbm := BoxMesh.new()
	bbm.size = Vector3(STELE_W_PX * STELE_BASE_K * ws, STELE_H_PX * 0.16 * ws,
		STELE_D_PX * STELE_BASE_K * ws)
	base.mesh = bbm
	base.material_override = _mat_solid(COL_STELE_BASE, 9)
	base.position = Vector3(0.0, -STELE_H_PX * 0.42 * ws, 0.0)
	slab.add_child(base)
	var rune := MeshInstance3D.new()
	var rbm := BoxMesh.new()
	rbm.size = Vector3(STELE_W_PX * 1.08 * ws, STELE_H_PX * 0.055 * ws, STELE_D_PX * 1.08 * ws)
	rune.mesh = rbm
	# ⚠ 这里**也不能用 ADD**: 实心盒正反面叠加照样把青爆成白(第一版符带就是一条白带,
	#   跟碑体是同一个根因, 只是换了个小零件)。要"发亮"靠**提亮颜色**, 不靠加法混合。
	rune.material_override = _mat_solid(COL_STELE_RUNE, 11)
	rune.position = Vector3(0.0, STELE_H_PX * 0.24 * ws, 0.0)
	slab.add_child(rune)
	## ★把【效果半径】记在节点自己身上, 门禁量真实对象而不是在测试里把公式抄一遍
	##   (memory [[fb-write-without-reader-and-fake-gates]]:「门禁模拟公式 ≠ 量真实对象」)。
	root.set_meta("radius_px", radius_px)
	_fx.append({"node": root, "slab": slab, "t": 0.0, "life": maxf(0.05, sec), "kind": "stele"})
	return root


## 每秒一跳的潮涌环(匀速外扩)。
func stele_pulse(pos2d: Vector2, radius_px: float) -> Node3D:
	return _ring_fx(pos2d, radius_px, COL_TIDE, PULSE_SEC, "pulse")


# ══════════════════════════════════════════════════════════════════
#  §089 蚀月符纸
# ══════════════════════════════════════════════════════════════════

## 给目标贴一张悬浮符纸(跟着它走, 上下轻浮 + 慢自转)。
## ★状态里存的是**单位字典本身**(放在 `_fx` 条目的 value 位) —— 允许;
##   禁止的是拿它当 Dictionary 的**键**(CLAUDE.md §3.2)。
func talisman_stick(u, sec: float) -> Node3D:
	if not _has_world() or not (u is Dictionary):
		return null
	## ★QuadMesh 而不是 BoxMesh: 片就是片, 没有"厚度"这一维就没有"侧对镜头"这件事可发生。
	var qm := QuadMesh.new()
	qm.size = Vector2(TALISMAN_W_PX * float(battle.WS), TALISMAN_H_PX * float(battle.WS))
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = _mat_paper(_talisman_tex())
	mi.position = battle._world_pos((u as Dictionary)["pos"] as Vector2, TALISMAN_Y)
	mi.basis = face_basis(_cam_forward(), 0.0)
	_adopt(mi, "talisman")
	_fx.append({"node": mi, "unit": u, "t": 0.0, "life": maxf(0.05, sec), "kind": "talisman"})
	return mi


## 符纸从尸体飞向新目标的那道紫光。
func talisman_transfer(from2d: Vector2, to2d: Vector2) -> Node3D:
	if not _has_world():
		return null
	var mi := _band(from2d, to2d, COL_MOON, 10.0, TALISMAN_Y)
	if mi == null:
		return null
	_fx.append({"node": mi, "t": 0.0, "life": TRANSFER_SEC, "kind": "transfer"})
	return mi


# ══════════════════════════════════════════════════════════════════
#  §090 镇海杵
# ══════════════════════════════════════════════════════════════════

## 起跳 → 滞空 → 砸落的**节奏读数**(存活 = 起跳到砸落的时长)。
##
## ★2026-08-07 重做。原来是一根**从头到尾不动**的白光柱: 起跳、滞空、下落三段在画面上
##   完全一样, 玩家只看到"地上多了一根白条", 节奏一点都读不出来(用户原话
##   「跳起来那一段读不出」)。现在三样各管一件事, **全部跟着携带者的真实滞空高度走**:
##     · **水柱**: 高度 ≡ `u["height"]`(主循环 airborne 积分出来的那个数, 不是另跑一条曲线)
##       ⇒ 柱子长 = 它跳了多高, 上升/悬停/下落一眼分得出
##     · **地面影子**: 按 `leap_shadow_scale` 收缩 —— "东西在多高"的经典读数
##     · **落点预告环**: 半径从 1.18× 收到 1.0×(`telegraph_radius`), **收满即砸落**
##       ⇒ 提前告诉玩家"这一下要砸多大、什么时候砸"; 用的是 088 那张**硬边**网格,
##         因为它要表达的确实是一条边界。
func pestle_leap(u, sec: float) -> Node3D:
	if not _has_world() or not (u is Dictionary):
		return null
	var pos2: Vector2 = (u as Dictionary)["pos"]
	var root := Node3D.new()
	root.position = battle._world_pos(pos2, 0.0)
	_adopt(root, "leap")
	# 水柱(局部原点在底面 ⇒ 只要改 scale.y 与 position.y 就能"长高")
	var bm := BoxMesh.new()
	bm.size = Vector3(22.0 * float(battle.WS), 1.0, 22.0 * float(battle.WS))
	var col := MeshInstance3D.new()
	col.mesh = bm
	# ★MIX 而不是 ADD: ADD 会把水柱加成一根纯白条(旧版就是这样, 读不出是水)
	col.material_override = _mat_boundary(Color(COL_SLAM.r, COL_SLAM.g, COL_SLAM.b, 0.85))
	root.add_child(col)
	# 地面影子
	var sh := MeshInstance3D.new()
	sh.mesh = _ring_mesh()
	sh.material_override = _mat(COL_WAVE, 8)
	sh.scale = Vector3(LEAP_SHADOW_PX * 0.5 * float(battle.WS), 1.0, LEAP_SHADOW_PX * 0.5 * float(battle.WS))
	root.add_child(sh)
	# 落点预告环(硬边) —— 半径就是真实的砸落半径, 不是"贴片尺寸"
	var tele := MeshInstance3D.new()
	tele.mesh = _boundary_mesh()
	tele.material_override = _mat_boundary(COL_SLAM)
	var r0: float = telegraph_radius(0.0, LEAP_WINDUP_PX) * float(battle.WS)
	tele.scale = Vector3(r0, 1.0, r0)
	root.add_child(tele)
	root.set_meta("radius_px", SLAM_R_PX)
	_fx.append({"node": root, "unit": u, "col": col, "shadow": sh, "tele": tele,
		"t": 0.0, "life": maxf(0.05, sec), "kind": "leap"})
	return root


## 砸落: 一圈 Sedov 激波(半径 = 1000 码的真实效果半径)。
func pestle_slam(pos2d: Vector2, radius_px: float) -> Node3D:
	return _ring_fx(pos2d, radius_px, COL_SLAM, SLAM_SEC, "slam")


## 浪潮折线: 每一跳画一段拱形(4·h·s(1−s)), 拱高 = 跨度的 ARC_PEAK_FRAC。
## ★同步建完就返回 —— 伤害早在 `EqArcaneBatch.wave_chain` 里结算过了, 这里纯画。
func wave_path(pts: Array) -> Node3D:
	if not _has_world() or pts.size() < 2:
		return null
	var root := Node3D.new()
	root.position = Vector3.ZERO
	_adopt(root, "wave")
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var span: float = a.distance_to(b)
		var peak: float = span * ARC_PEAK_FRAC * float(battle.WS)
		var prev: Vector3 = battle._world_pos(a, 0.55)
		for k in range(1, ARC_SEG + 1):
			var s: float = float(k) / float(ARC_SEG)
			var p2: Vector2 = a.lerp(b, s)
			var cur: Vector3 = battle._world_pos(p2, 0.55 + arc_height(s, peak))
			var seg: Vector3 = cur - prev
			var l: float = seg.length()
			if l > 0.0005:
				var bm := BoxMesh.new()
				bm.size = Vector3(l, WAVE_W_PX * float(battle.WS), WAVE_W_PX * float(battle.WS))
				var mi := MeshInstance3D.new()
				mi.mesh = bm
				mi.material_override = _mat(COL_WAVE, 12)
				mi.position = prev + seg * 0.5
				mi.rotation.y = -atan2(seg.z, seg.x)
				mi.rotation.z = asin(clampf(seg.y / l, -1.0, 1.0))
				root.add_child(mi)
			prev = cur
	root.set_meta("path_len", path_length(pts))
	_fx.append({"node": root, "t": 0.0, "life": WAVE_SEC, "kind": "wave"})
	return root


# ══════════════════════════════════════════════════════════════════
#  §驱动与撤场
# ══════════════════════════════════════════════════════════════════

func _ring_fx(pos2d: Vector2, radius_px: float, col: Color, sec: float, kind: String) -> Node3D:
	if not _has_world():
		return null
	var mi := _node(_ring_mesh(), _mat(col, 9), battle._world_pos(pos2d, 0.0), kind)
	mi.scale = Vector3(0.001, 1.0, 0.001)
	mi.set_meta("radius_px", radius_px)
	_fx.append({"node": mi, "t": 0.0, "life": sec, "kind": kind, "r": radius_px})
	return mi


## 每帧推进。★纯同步, 门禁可以喂任意 delta; 不依赖 tween。
func tick(delta: float) -> void:
	if delta <= 0.0 or _fx.is_empty():
		return
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		var n = f.get("node", null)
		if not is_instance_valid(n):
			_fx.remove_at(i)
			continue
		f["t"] = float(f["t"]) + delta
		var t: float = float(f["t"])
		var life: float = maxf(0.001, float(f["life"]))
		var k: String = str(f["kind"])
		match k:
			"stele":
				var slab = f.get("slab", null)
				if is_instance_valid(slab):
					var h: float = STELE_H_PX * float(battle.WS)
					var fr: float = rise_frac(t, RISE_SEC)
					## 碑从地下顶上来: 站定时中心在 h/2, 冒头时中心在 −h/2
					(slab as Node3D).position.y = h * (fr - 0.5)
				if t >= life:
					_free_fx(i)
			"pulse", "slam":
				var rp: float = float(f.get("r", 100.0))
				var r: float = (blast_radius(t, life, rp) if k == "slam" else pulse_radius(t, life, rp))
				var s: float = maxf(0.001, r * float(battle.WS))
				(n as Node3D).scale = Vector3(s, 1.0, s)
				_set_alpha(n, 1.0 - clampf(t / life, 0.0, 1.0))
				if t >= life:
					_free_fx(i)
			"talisman":
				var u = f.get("unit", null)
				if u is Dictionary and (u as Dictionary).get("alive", false):
					var p: Vector2 = (u as Dictionary)["pos"]
					(n as Node3D).position = battle._world_pos(p, TALISMAN_Y + bob_offset(t) * float(battle.WS))
					## ★每帧重新对准镜头 —— 相机会跟着战况平移/缩放, 只在建的时候对一次,
					##   镜头一动就又斜了(而"斜"到极限就是旧版那种整张消失)。
					(n as Node3D).basis = face_basis(_cam_forward(), talisman_roll(t))
				if t >= life or not (u is Dictionary) or not (u as Dictionary).get("alive", false):
					_free_fx(i)
			"leap":
				# ★三样各管一件事, 全部跟着**真实滞空高度** `u["height"]` 走
				#   (那是主循环 airborne 积分出来的数 —— 不另跑一条曲线, 演出与物理天然同步)
				var lu = f.get("unit", null)
				var hm: float = float((lu as Dictionary).get("height", 0.0)) if lu is Dictionary else 0.0
				var q: float = clampf(t / life, 0.0, 1.0)
				if lu is Dictionary:
					(n as Node3D).position = battle._world_pos((lu as Dictionary)["pos"] as Vector2, 0.0)
				var lcol = f.get("col", null)
				if is_instance_valid(lcol):
					var hh: float = maxf(0.06, hm)          # 柱高 = 它跳了多高
					(lcol as Node3D).scale.y = hh
					(lcol as Node3D).position.y = hh * 0.5
				var lsh = f.get("shadow", null)
				if is_instance_valid(lsh):
					var ss: float = LEAP_SHADOW_PX * 0.5 * leap_shadow_scale(hm, LEAP_APEX_M) * float(battle.WS)
					(lsh as Node3D).scale = Vector3(ss, 1.0, ss)
				var lte = f.get("tele", null)
				if is_instance_valid(lte):
					var tr: float = telegraph_radius(q, LEAP_WINDUP_PX) * float(battle.WS)
					(lte as Node3D).scale = Vector3(tr, 1.0, tr)
					_set_alpha(lte, 0.30 + 0.55 * q)        # 越接近砸落越亮 ⇒ "要来了"
				if t >= life:
					_free_fx(i)
			_:
				_set_alpha(n, 1.0 - clampf(t / life, 0.0, 1.0))
				if t >= life:
					_free_fx(i)


func _set_alpha(n, a: float) -> void:
	if n is MeshInstance3D:
		var m = (n as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			var c: Color = (m as StandardMaterial3D).albedo_color
			(m as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))
	elif n is Node3D:
		for ch in (n as Node3D).get_children():
			_set_alpha(ch, a)


func _free_fx(i: int) -> void:
	var f: Dictionary = _fx[i]
	var n = f.get("node", null)
	if is_instance_valid(n):
		(n as Node).queue_free()
	_fx.remove_at(i)


## 撤场: 全部释放。返回释放了几个(门禁数它)。
func clear() -> int:
	var n: int = 0
	for x in _owned:
		if is_instance_valid(x):
			(x as Node).queue_free()
			n += 1
	_owned.clear()
	_fx.clear()
	## ★缓存一并放掉: 不放的话进程退出时 Godot 刷
	##   `RID allocations of type DummyMesh/DummyTexture were leaked at exit`
	##   (relic_eq_vfx.gd:717 记的同款坑)。下次要用会 lazy 重建, 不影响功能。
	_mesh_ring = null
	_tex_talisman = null
	return n


## 还活着的本层节点数(可按 kind 过滤) —— 门禁量真实对象用。
func alive_count(kind: String = "") -> int:
	var n: int = 0
	for x in _owned:
		if not is_instance_valid(x):
			continue
		if kind != "" and str((x as Node).get_meta(META_KEY, "")) != kind:
			continue
		n += 1
	return n
