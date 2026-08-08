class_name RelicEqVfx
extends RefCounted
## relic_eq_vfx.gd — 遗物两件新装备(091 远古龟甲片 / 094 祖龟碑)的演出层
## (规格 `docs/plans/20260805-装备逐件重做.md` §0.5 ★091 / ★094 · 契约 `20260806-实装契约-批④.md` §7)
##
## ══════════════════════════════════════════════════════════════════════
##  ★判据: 可验证的几何/物理规律, 不是"我调得像"
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-05 立的 3D 水准线是【触手那一版】, 第一条判据是「逐帧量参考做成包络表」。
## ⚠ **诚实记录**: 这两件**一张参考素材都没有** ⇒ 本文件**没有"逐帧量参考"这一步**。
## 代替它的是下面四条**闭式解 / 精确几何**, 判据不是"我调得像", 而是"它满足这几条可验证的等式"。
## 门禁验的正是这几条性质, 手调出来的缓动曲线一条都过不了。
##
## ── ① 091 甲片环: 正六边形密铺的【精确几何】 ────────────────────────
##   六片甲片围着携带者, 是正六边形**边对边密铺**中"中心那片的六个邻居"。
##   密铺给出两条**精确**关系(不是我拍的数):
##       邻居中心距 = √3 · R      (R = 甲片外接圆半径)
##       邻居方位角 = 30° + k·60° (k = 0..5)
##   ⇒ `hex_ring_centers()` 里没有一个手调系数; 门禁 ② 量的是**真实顶点**算出的
##     中心距/夹角/顶点角距, 随便挪一片都会红。
##   ★为什么非要密铺: "龟甲片"这四个字说的就是这个 —— 甲片之间**不留缝也不重叠**,
##     随手摆六个圆点摆不出这个性质。
##
## ── ② 091 回复脉冲: 二维柱面波的能量守恒 ────────────────────────────
##   一跳回复 = 一次点源脉冲。它在地面上铺成一圈, 圈长 2πr ⇒ **单位长度能量 ∝ 1/r**,
##   而能量 ∝ 振幅² ⇒
##       a(r) ∝ r^(−1/2)          `wave_amp()`
##   ★可验证性质(门禁 ③): **a(4r)/a(r) ≡ 1/2**, 与 r 无关。任何 `ease_out` 都给不出这条。
##
##   ★★**振幅与回复量焊死**: 脉冲总能量 ∝ 这一跳回的血 ⇒ 振幅 ∝ √(回复量)。
##     所以血量 <25% 翻 6 倍时, 甲片亮度恰好是 **√6 = 2.4495 倍** ——
##     「6」这个数在本项目里只有一份(`EqRelicBatch.SCUTE_LOW_MULT`), 由系统侧**传进来**,
##     本文件不抄第二遍(memory [[fb-write-without-reader-and-fake-gates]]:
##     抄两遍的话把产品代码改坏、门禁照样绿)。门禁 ③ 量的是**真实材质的 albedo alpha**。
##
## ── ③ 094 立碑: 匀减速上升(软着陆的唯一解) ──────────────────────────
##   碑被从地下顶出来, 到位那一刻速度**恰好为 0**(不是"到了再刹车"、也不是"撞上去弹一下")。
##   匀减速 a = −v₀/T 的唯一解归一后是
##       ĥ(τ) = 2τ − τ²          `rise_profile()`
##   ★三条可验证性质(门禁 ⑤): ĥ(1) ≡ 1 · ĥ′(1) ≡ 0(软着陆) · **ĥ(0.5) ≡ 0.75**。
##     线性上升在半程给 0.5、`ease_out_cubic` 给 0.875 —— 三者一测就分开。
##
## ── ④ 094 石雷: 真自由落体 ──────────────────────────────────────────
##   石块从 H 高处**无初速**落下:  z(t) = H − ½g t²  ⇒ 归一后 ẑ(τ) = 1 − τ²
##       T = √(2H/g)      v_落地 = gT = √(2gH)
##   ★可验证性质(门禁 ⑥): 等距采样的**二阶差分恒为 −2/N²**(抛物线的定义), 且
##     `fall_time(4H) / fall_time(H) ≡ 2`(尺度律)。匀速直线给二阶差分 0, ease 曲线给别的数。
##   落地的爆点**复用** `ShockwaveVfx`(Sedov–Taylor 波前 + Friedlander 超压), 不重造 ——
##   契约 §5「零素材特效原语」点名的就是它。
##
## ── 技术路线 ────────────────────────────────────────────────────────
## 程序化 `ArrayMesh`(`SurfaceTool` 现算) + `ShockwaveVfx`, **零素材**。
## 用户素材铁律「新内容一律新素材, 不许拿别件的立绘顶替」—— 程序化几何不产出图, 天然合规。
## （诚实记录: 祖龟碑若要**像素立绘级**的碑面雕纹, 需要一张新美术; 见交付报告。）
##
## ⚠ 朝向坑 (memory [[fb-axis-y-plus-rotation-cancels]]): 本文件**不用 Sprite3D**,
##   直接建世界坐标顶点 ⇒ 没有 `axis = AXIS_Y` 与 `rotation.x = -90` 互相抵消那层歧义。
##   贴地的东西一律 y = GROUND_Y 的水平顶点, 门禁量 |三角面法线·上| ≈ 1.000。
##
## ⚠ 不用 `create_tween` (CLAUDE.md §3.5): 无头 CI 下 tween 推进不稳, 而且走 sim 的 delta
##   才跟时停/换路同步。**本层每一条形态都由 `tick(delta)` 推进**, 门禁可以同步喂任意 delta。
##
## ⚠ 材质一律 `material_override` 而不是 `set_surface_override_material` ——
##   后者在 `--headless` 的 dummy renderer 下每设一次刷一条
##   `ERROR: Parameter "material" is null.`(shockwave_vfx.gd:244 记的坑, 不在 FATAL 正则里但真的在刷)。


# ══════════════════════════════════════════════════════════════════
#  §几何/物理常数 —— 全部进闭式解, 没有一个是"调得像"调出来的
# ══════════════════════════════════════════════════════════════════

## 节点上打的自定义 meta 键(同 SynergyVfx.META_KEY 的做法: 程序生成的网格没有
## resource_path, 按路径数会全部数成 0)。
const META_KEY := "relic_eq_vfx"

## _owned 的上限, 照 SynergyVfx.OWNED_CAP / RB:_reg_tween 的做法留最后一道闸。
const OWNED_CAP := 256

## ── ① 甲片环(091) ────────────────────────────────────────────────
## 甲片的外接圆半径(场地像素)。密铺关系把环半径完全定死, 不另设参数。
## ★2026-08-07 从 13 提到 21 —— 实战默认视角标尺(1280×720·相机 (0,28,22) look_at (0,0.6,0)·fov 40):
##   横向 0.6755 屏幕像素/码、贴地纵深 0.5267 px/码。13 码外接圆 ⇒ 单片只有 17.6×13.7 px、
##   整环跨度 (2·√3·13 + 26) 码 = 30 px, 挤在龟脚底下一团。
##   21 码 ⇒ 单片 **28.4×22.1 px**、整环跨度 (2·√3·21 + 42) = 114.7 码 = **77.5×60.4 px**,
##   环真的"围着"44 px 高的龟立绘, 而不是垫在它脚下。
const PLATE_R_PX := 21.0
## 甲片数 = 正六边形密铺里"中心那片的邻居数", 是 6 —— 不是可调的美术数。
const PLATE_N := 6
## 甲片贴地高度(米)。略高于地面, 免得被地板 z-fighting 吃掉。
const GROUND_Y := 0.06
## 甲片的基准亮度(mult=1 那一跳)。★**上限校核**: ×√6 = 0.980 < 1.0 ⇒ **量程内不会被钳**,
##   门禁量到的 alpha 比值才是真的 √6 而不是"两边都撞上限所以相等"。
##   ⇒ PLATE_A 的**硬天花板是 1/√6 = 0.4082**, 想再提亮只能走描边/本色, 不能动这个数。
const PLATE_A := 0.40
## 甲片内芯 / 外沿的**顶点色 alpha**。总亮度 = PLATE_A(材质) × 顶点 alpha ⇒
## ★描边不占 alpha 量程: 提亮外沿不会把 ×√6 那条比值断言变成"两边都撞上限"。
## ⚠ 写了顶点色还得有人读 —— 材质必须开 `vertex_color_use_as_albedo`
##   (memory [[fb-write-without-reader-and-fake-gates]]: 生产侧写了消费侧没读, 一天踩三次)。门禁 G6 守这条。
const PLATE_VA_CORE := 0.62
const PLATE_VA_RIM := 1.00
## 外沿描边带的内边界(占外接圆半径的比例)
const PLATE_RIM_IN := 0.80
## 甲片亮度的指数衰减时间常数(秒)。= 一个回复节拍, 于是"上一片还没暗完下一片就亮"。
## ★2026-08-07 0.25 → 0.42: 节拍也是 0.25 秒 ⇒ 旧值让每片在下一跳之前刚好衰到 1/e = 37%,
##   随手截一帧十有八九落在低谷(改后实拍 `_vfxlab_af091_*.png` 三张全是暗的就是这么来的)。
const PLATE_TAU := 0.42
## 甲片亮度的**下限**(占 PLATE_A 的比例)。★这条是"甲片环随时看得见"的结构保证:
##   指数衰减的终点是 0, 意味着只要采样落在两跳之间的低谷, 甲片就是不存在的。
##   加了地板之后甲片环是一个**常驻**的玉青六边形环, 脉冲只是在它上面加亮。
## ⚠ 地板只作用在 `tick()` 的衰减上, **不碰 `scute_pulse` 写下的峰值** ——
##   否则 ×√6 那条比值断言会变成 (floor+a)/(floor+b) ≠ √6。
const PLATE_FLOOR_FRAC := 0.30

## ── 回复微粒(091) ────────────────────────────────────────────
## ★为什么要有它: 甲片脉冲的峰/谷之比被 PLATE_A 的天花板(1/√6)锁死, 实拍量到
##   "一跳只把环带总亮度推 5%" —— 机制在跑, 但**读不出在回血**(2026-08-09 用
##   "变亮像素数" 量出来的: 21393 像素亮起、间隔 0.24 秒 = 节拍, 肉眼却看不见)。
##   微粒不占 alpha 量程, 所以提可读性不会动那条 ×√6 的断言。
const MOTE_LIFE := 0.62
## 微粒升起的高度(米)与横向漂移(米)。
const MOTE_RISE_M := 1.9
const MOTE_DRIFT_M := 0.42
## 微粒边长(场地像素)。
const MOTE_SZ_PX := 3.6
## 一跳放几颗: 平时 1 颗(4 颗/秒, 不糊), <25% 爆发档 4 颗。
const MOTE_N := 1
const MOTE_N_LOW := 4

## ── ② 回复脉冲波(091) ────────────────────────────────────────────
## 柱面波振幅公式的起算半径(归一)。a(x) = √(X0/x), 在 x = X0 处恰为 1。
## ★取 1/16 是为了让"4 倍半径 → 半振幅"这条在 [X0, 1] 内**跨得下两整段**(1/16→1/4→1)。
const WAVE_X0 := 0.0625
## 脉冲波的最大半径(场地像素)与寿命(秒)。
const WAVE_R_PX := 74.0
const WAVE_LIFE := 0.42

## ── ③ 立碑(094) ──────────────────────────────────────────────────
## 碑破土升起的时长(秒)。
const RISE_SEC := 0.85
## 碑体总高(米)、碑座半宽/半深(米)、碑身底/顶半宽(米)、碑身半深(米)。
## ★2026-08-07 整体放大 ×1.55 —— 旧尺寸(H 1.90 / 半宽 0.30)在实战默认视角下
##   只有 **22.5 宽 × 43 高 屏幕像素**(竖直方向 17.62 px/米、横向 28.15 px/米),
##   碑面上再刻什么都只有 2~3 px。放大后 **35 × 66 px**, 刻纹才有地方站。
const STELE_H := 2.95
const PLINTH_H := 0.30
const PLINTH_HW := 0.62
const PLINTH_HD := 0.34
const SHAFT_HW_BOT := 0.46
const SHAFT_HW_TOP := 0.34
const SHAFT_HD := 0.15
## 碑脚符环(贴地)的半径(场地像素)与转速(弧度/秒)。
const RUNE_R_PX := 58.0
const RUNE_SPIN := 0.55

## ── ③b 碑面琥珀刻纹(094 唯一的分星信息) ──────────────────────────
## ★2026-08-07 重做 —— 旧版**一条都看不出来**, 两个根因叠在一起:
##   ① 碑身 `SHADING_MODE_UNSHADED` + albedo 0.62~0.66 ⇒ 碑身本身就是一块自发光的亮灰,
##      刻纹又是 **BLEND_ADD** ⇒ 0.64 + 0.85×0.79 直接饱和成纯白, 刻纹与碑身糊成一块。
##      干净台 4.2 倍实拍(改前图 `_vfxlab_bf094_1.png`)就是一块纯白板。
##   ② 分星靠的是刻纹**宽度** 0.13/0.17/0.22 —— 换算到屏幕是 7.3 / 9.6 / 12.4 px 的
##      竖条宽度差, 就算不烧白, 肉眼也分不出"这条比那条宽 2 px"。
## ⇒ 现在: 碑身压暗(见 COL_STONE) + 刻纹改 **BLEND_MIX**(是刻上去的漆, 不是打上去的光)
##   + **分星改成数条数**: 星级 si ⇒ si+1 道横向刻纹。"数得清"永远比"比得出宽度"可靠。
const GLYPH_N_BASE := 1
## 单条刻纹的半高(米)与半宽占碑身半宽的比例。
const GLYPH_HH := 0.13
const GLYPH_W_FRAC := 0.86
## 相邻两条刻纹的中心间距(米)
const GLYPH_PITCH := 0.46
## 刻纹组的中心高度(从碑座顶面往上算, 占碑身高的比例)
const GLYPH_MID_FRAC := 0.68

## ── ④ 石雷(094) ──────────────────────────────────────────────────
## 石块的起落高度(米)与重力(米/秒²)。★两者一起把落时定死成 T = √(2H/g) = 0.5 秒,
##   不是"我觉得 0.5 秒好看"—— 改任一个, `fall_time()` 与门禁 ⑥ 一起跟着变。
const BOLT_H := 5.25
const BOLT_G := 42.0
## 石块的世界尺寸(米)。
const BOLT_R := 0.30

## 配色。碑=**暗**青灰石 + 琥珀刻纹; 甲片=玉青; 石雷=暖岩。
## ★COL_STONE 从 (0.62,0.64,0.66) 压到 (0.26,0.28,0.31): 材质是 UNSHADED ⇒ albedo 就是自发光,
##   0.64 的灰在纯黑场里已经是"亮白板", 刻纹再画什么都被它顶掉。压暗之后
##   刻纹(luma 0.79) / 碑身(luma 0.28) 的亮度比 = **2.8 倍**, 一眼分得出。
const COL_SCUTE := Color(0.48, 1.00, 0.74, 1.0)
const COL_STONE := Color(0.26, 0.28, 0.31, 1.0)
const COL_GLYPH := Color(1.00, 0.78, 0.34, 1.0)
const COL_BOLT := Color(0.86, 0.62, 0.36, 1.0)


var battle
## 爆点原语(Sedov–Taylor + Friedlander)。★复用不重造 —— 契约 §5。
var _shock: ShockwaveVfx = null

## 本层建出来、还活着的节点(撤场用)。存节点不存单位字典 —— CLAUDE.md §3.2。
var _owned: Array = []

## 网格缓存。★存实例上不存 `static var` —— static 的话进程退出时 Godot 会报
##   `N resources still in use at exit`(shockwave_vfx.gd:146 记的坑)。
var _m_hex: ArrayMesh = null
var _m_ring: ArrayMesh = null
var _m_rock: ArrayMesh = null
var _m_box: ArrayMesh = null

## 091 每个携带者一套常驻甲片环: {u, root, plates:[6], a:[6], n}
var _scutes: Array = []
## 091 正在扩的回复脉冲波: {node, t, amp}
var _waves: Array = []
var _motes: Array = []
## 微粒的横向漂移**不走 rng** —— 用自增计数派生, 保住确定性(战斗 rng 序列一动, 别处钉序列的门禁就错位)。
var _mote_seq: int = 0
## 094 每座碑一套常驻碑体: {root, rune, t, si}
var _steles: Array = []
## 094 在途石块: {node, t, T, from(Vector3), to(Vector3), col}
var _rocks: Array = []
## 094 全队光环的头顶印记: {u, node, t}
var _marks: Array = []
## 正在播的爆点(ShockwaveVfx 句柄)
var _shocks: Array = []


func _init(b) -> void:
	battle = b
	_shock = ShockwaveVfx.new(b)


## 世界在不在。所有对外入口的第一行都是它 ——
## 主场景那几个 vfx 入口不守 `_world == null`, 在"只建单位不建世界"的数值测试里
## 那是 SCRIPT ERROR 而不是 FAIL, 会被 run-tests.sh 的 FATAL 正则接住(SynergyVfx R2 同款)。
func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


func _adopt(n: Node3D, kind: String) -> void:
	n.set_meta(META_KEY, kind)
	battle._world.add_child(n)
	if _owned.size() >= OWNED_CAP:
		_owned = _owned.filter(func(x): return is_instance_valid(x))
	_owned.append(n)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等 tween(契约 §7 / CLAUDE.md §3.5)
# ══════════════════════════════════════════════════════════════════

## 正六边形密铺中, 中心那片的六个邻居的**中心偏移**(场地像素)。
##
## ★两条精确关系, 一个手调系数都没有:
##     距离 = √3 · R   (R = 外接圆半径; 两片共边 ⇒ 中心距 = 2 × 边心距 = 2 · (√3/2)R)
##     方位 = 30° + k·60°   (邻居在边心方向上, 而边心与顶点差 30°)
## 顶点自己在 0°, 60°, …, 300°(见 `_build_hex`)。
static func hex_ring_centers(plate_r: float) -> Array:
	var out: Array = []
	var d: float = sqrt(3.0) * plate_r
	for k in range(PLATE_N):
		var th: float = deg_to_rad(30.0 + 60.0 * float(k))
		out.append(Vector2(d * cos(th), d * sin(th)))
	return out


## 二维柱面波的归一振幅 a(x) = √(X0 / x), x = r / r_max ∈ (0, 1]。
##
## ★由能量守恒推出来的, 不是缓动曲线: 波前铺在周长 2πr 上 ⇒ 线密度 ∝ 1/r,
##   能量 ∝ 振幅² ⇒ 振幅 ∝ r^(−1/2)。
## ★可验证: a(4x)/a(x) ≡ 1/2, 与 x 无关。
static func wave_amp(x: float) -> float:
	return sqrt(WAVE_X0 / maxf(x, WAVE_X0))


## 一次回复脉冲的**初始振幅** = √(回复倍率)。
##
## ★脉冲总能量 ∝ 这一跳回的血, 能量 ∝ 振幅² ⇒ 振幅 ∝ √量。
##   `mult` 由系统侧传进来(平时 1.0 / 血量 <25% 时 `EqRelicBatch.SCUTE_LOW_MULT`),
##   本文件**不抄那个 6**。
static func pulse_amp(mult: float) -> float:
	return sqrt(maxf(mult, 0.0))


## 094 碑面刻纹的几何(★门禁直接调, 不建节点)。
##
## 返回 `si + 1` 条横向刻纹, 每条 `{y, hw, hh}`(单位: 米, y 从**碑座顶面**往上算):
##   · **条数 = si + 1** —— 分星信息落在"数得清的条数"上, 不是"比得出的宽度差"
##   · 半宽 = 该高度处碑身半宽 × GLYPH_W_FRAC ⇒ 刻纹**恒在碑面内**(不会挑出碑外), 且
##     碑身是下宽上窄的锥台 ⇒ 越靠上的刻纹越短, 跟着碑走
##   · 组整体以 GLYPH_MID_FRAC 处为中心上下均分 ⇒ 1/2/3 条时视觉重心都在同一高度
static func glyph_bands(si: int, shaft_h: float) -> Array:
	var n: int = GLYPH_N_BASE + clampi(si, 0, 2)
	var mid: float = shaft_h * GLYPH_MID_FRAC
	var out: Array = []
	for k in range(n):
		var y: float = mid + (float(k) - float(n - 1) * 0.5) * GLYPH_PITCH
		var f: float = clampf(y / maxf(shaft_h, 1e-6), 0.0, 1.0)
		out.append({
			"y": y,
			"hw": lerpf(SHAFT_HW_BOT, SHAFT_HW_TOP, f) * GLYPH_W_FRAC,
			"hh": GLYPH_HH,
		})
	return out


## 匀减速上升的归一高度 ĥ(τ) = 2τ − τ²(τ ∈ [0,1])。
## ★ĥ(1) = 1 且 ĥ′(1) = 0 ⇒ 到位那一刻速度恰为 0(软着陆的唯一解); ĥ(0.5) = 0.75。
static func rise_profile(tau: float) -> float:
	var t: float = clampf(tau, 0.0, 1.0)
	return 2.0 * t - t * t


## 无初速自由落体的归一高度 ẑ(τ) = 1 − τ²。等距采样二阶差分恒为 −2/N²(抛物线的定义)。
static func fall_profile(tau: float) -> float:
	var t: float = clampf(tau, 0.0, 1.0)
	return 1.0 - t * t


## 落时 T = √(2H/g)。★可验证: T(4H)/T(H) ≡ 2。
static func fall_time(h: float, g: float) -> float:
	return sqrt(2.0 * maxf(h, 0.0) / maxf(g, 0.001))


## 落地速度 v = gT = √(2gH)。
static func impact_speed(h: float, g: float) -> float:
	return g * fall_time(h, g)


# ══════════════════════════════════════════════════════════════════
#  §网格 —— 程序化 ArrayMesh, 零素材
# ══════════════════════════════════════════════════════════════════

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	n = n.normalized() if n.length() > 1e-9 else Vector3.UP
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


## 单位外接圆半径的正六边形甲片(贴地·顶点在 0°/60°/…/300°)。
## ★顶点角必须是这六个 —— `hex_ring_centers` 的 30° 偏移是**相对它们**成立的。
##
## ★2026-08-07 加**描边**: 内芯顶点 alpha PLATE_VA_CORE、外沿一圈 PLATE_VA_RIM。
##   原因是 PLATE_A 的天花板被 ×√6 那条比值断言焊死在 1/√6 = 0.408 —— 整片一起提亮
##   最多只能提 1.33 倍, 提不到"看得见"。描边走**顶点色**这条独立通道:
##   最终 alpha = 材质 alpha × 顶点 alpha, 比值断言只看材质那一半, 不受影响。
static func _build_hex() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rin: float = PLATE_RIM_IN
	for k in range(PLATE_N):
		var t0: float = TAU * float(k) / float(PLATE_N)
		var t1: float = TAU * float(k + 1) / float(PLATE_N)
		var i0 := Vector3(rin * cos(t0), 0.0, rin * sin(t0))
		var i1 := Vector3(rin * cos(t1), 0.0, rin * sin(t1))
		var o0 := Vector3(cos(t0), 0.0, sin(t0))
		var o1 := Vector3(cos(t1), 0.0, sin(t1))
		# 内芯扇形(暗)
		_tri_c(st, Vector3.ZERO, i0, i1, PLATE_VA_CORE)
		# 外沿描边带(亮)
		_tri_c(st, i0, o0, o1, PLATE_VA_RIM)
		_tri_c(st, i0, o1, i1, PLATE_VA_RIM)
	return st.commit()


## 带顶点 alpha 的三角面(RGB 恒白 —— 本色由材质 albedo 给, 顶点色只管明暗)。
static func _tri_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, va: float) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	n = n.normalized() if n.length() > 1e-9 else Vector3.UP
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(Color(1.0, 1.0, 1.0, va))
		st.add_vertex(v)


## 单位外半径的贴地圆环带(内半径 inner)。
static func _build_annulus(inner: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(seg):
		var t0: float = TAU * float(i) / float(seg)
		var t1: float = TAU * float(i + 1) / float(seg)
		_quad(st,
			Vector3(inner * cos(t0), 0.0, inner * sin(t0)),
			Vector3(cos(t0), 0.0, sin(t0)),
			Vector3(cos(t1), 0.0, sin(t1)),
			Vector3(inner * cos(t1), 0.0, inner * sin(t1)))
	return st.commit()


## 一块**不规则**石头(单位半径)。顶点是写死的八面体变体, **零随机** ——
## 走 `battle._battle_rng` 也行, 但形状没必要吃确定性预算。
static func _build_rock() -> ArrayMesh:
	var top := Vector3(0.10, 1.00, -0.05)
	var bot := Vector3(-0.08, -1.00, 0.06)
	var eq: Array = [
		Vector3(1.00, 0.12, 0.00), Vector3(0.34, -0.06, 0.88),
		Vector3(-0.70, 0.10, 0.62), Vector3(-0.92, -0.08, -0.28),
		Vector3(0.06, 0.14, -0.96),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(eq.size()):
		var a: Vector3 = eq[i]
		var b: Vector3 = eq[(i + 1) % eq.size()]
		_tri(st, top, a, b)
		_tri(st, bot, b, a)
	return st.commit()


## 单位立方体(±1)。碑座/碑身都是它按 scale 拉出来的。
static func _build_box() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p: Array = [
		Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1),
		Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1),
	]
	_quad(st, p[4], p[7], p[6], p[5])          # 顶
	_quad(st, p[0], p[1], p[2], p[3])          # 底
	_quad(st, p[3], p[2], p[6], p[7])          # +z
	_quad(st, p[1], p[0], p[4], p[5])          # -z
	_quad(st, p[2], p[1], p[5], p[6])          # +x
	_quad(st, p[0], p[3], p[7], p[4])          # -x
	return st.commit()


## `use_vcol` = 让**顶点色**参与 albedo(甲片描边靠它; 见 `_build_hex`)。
## ⚠ 默认关: `_m_ring` / `_m_rock` / `_m_box` 都没有顶点色数组, 全局打开会让它们吃到未定义的默认值。
static func _mat(col: Color, additive: bool, no_depth: bool, prio: int,
		use_vcol: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	m.no_depth_test = no_depth
	m.render_priority = prio
	m.vertex_color_use_as_albedo = use_vcol
	return m


func _mesh_node(mesh: ArrayMesh, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


func _ensure_meshes() -> void:
	if _m_hex == null:
		_m_hex = _build_hex()
	if _m_ring == null:
		_m_ring = _build_annulus(0.74, 48)
	if _m_rock == null:
		_m_rock = _build_rock()
	if _m_box == null:
		_m_box = _build_box()


# ══════════════════════════════════════════════════════════════════
#  §091 远古龟甲片 —— 常驻甲片环 + 回复脉冲波
# ══════════════════════════════════════════════════════════════════

## 找(或建)某个携带者的甲片环句柄。世界不在 → 返回 {}。
func ensure_scutes(u: Dictionary) -> Dictionary:
	if not _has_world() or not (u is Dictionary):
		return {}
	for h in _scutes:
		if is_same(h["u"], u):                # is_same: 单位字典互引成环, == 会深比较→卡死
			return h
	_ensure_meshes()
	var root := Node3D.new()
	var plates: Array = []
	var alphas: Array = []
	var ps: float = PLATE_R_PX * float(battle.WS)
	for c in hex_ring_centers(PLATE_R_PX):
		# no_depth=false: 甲片是**贴地**的(y=GROUND_Y), 开了 no_depth_test 就会画在龟立绘之上
		# ⇒ 六倍档全甲亮起时整片压住龟壳和脸(2026-08-09 实拍确认)。关掉后由深度决定遮挡。
		var mi := _mesh_node(_m_hex, _mat(Color(COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, 0.0), true, false, 8, true))
		mi.scale = Vector3(ps, 1.0, ps)
		mi.position = Vector3(float(c.x) * float(battle.WS), 0.0, float(c.y) * float(battle.WS))
		root.add_child(mi)
		plates.append(mi)
		alphas.append(0.0)
	root.position = battle._world_pos(u["pos"], GROUND_Y)
	_adopt(root, "scute_ring")
	var h2 := {"u": u, "root": root, "plates": plates, "a": alphas, "n": 0}
	_scutes.append(h2)
	return h2


## 一跳回复的演出。**每一跳都调**, `mult` 由系统侧传(平时 1.0 / <25% 时 6.0)。
##
## ★甲片按密铺顺序**轮流**点亮(第 n 跳点第 n%6 片) —— 一秒 4 跳、六片一轮半 ⇒
##   看得出"在一片片长回来"; 而 <25% 时**六片同时**点亮到 √6 倍, 那道悬崖是看得见的。
## ⚠ 本函数返回时甲片亮度就是最终值, 门禁下一行就能量, 不等任何动画。
func scute_pulse(u: Dictionary, _si: int, mult: float) -> Dictionary:
	var h: Dictionary = ensure_scutes(u)
	if h.is_empty():
		return {}
	var amp: float = PLATE_A * pulse_amp(mult)
	var n: int = int(h["n"])
	var plates: Array = h["plates"]
	var alphas: Array = h["a"]
	var low: bool = mult > 1.0
	for k in range(plates.size()):
		if low or k == (n % maxi(1, plates.size())):
			alphas[k] = amp
			var mi = plates[k]
			if is_instance_valid(mi):
				(mi.material_override as StandardMaterial3D).albedo_color = Color(
					COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, amp)
	h["n"] = n + 1
	h["a"] = alphas
	## 微粒从**这一跳点亮的那片甲**上升起(爆发档六片全亮 ⇒ 绕环均摊)
	var lit_k: int = n % maxi(1, plates.size())
	_emit_motes(h, lit_k, MOTE_N_LOW if low else MOTE_N, low)
	if low:
		_emit_wave(u["pos"], amp)
	return h


## 一跳的回复微粒: 从甲片位置升起、边升边淡。
## ⚠ 位置取的是**甲片节点的真实 local position**(不是重算一遍几何) —— 手抄的副本必然落后。
func _emit_motes(h: Dictionary, lit_k: int, cnt: int, low: bool) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	var root = h.get("root", null)
	if not is_instance_valid(root):
		return
	var plates: Array = h["plates"]
	if plates.is_empty():
		return
	var ms: float = MOTE_SZ_PX * float(battle.WS)
	for i in range(cnt):
		var k: int = (lit_k + i * 2) % plates.size()
		var pl = plates[k]
		if not is_instance_valid(pl):
			continue
		# no_depth=false: 微粒从环上升起, 让龟立绘按深度遮挡它 —— 否则前后排的微粒
		# 一律糊在龟脸上(实拍见 m091e)。
		## ⚠ `_adopt` 自己会把节点挂到 World —— 再 `root.add_child` 一次就是
		##   "already has a parent"(实拍 log 里刷了 24 条)。所以这里换算成**世界坐标**。
		var wp: Vector3 = (root as Node3D).position + (pl as Node3D).position
		var mi := _mesh_node(_m_hex, _mat(COL_SCUTE, true, false, 10))
		mi.scale = Vector3(ms, 1.0, ms)
		mi.position = wp
		_adopt(mi, "heal_mote")
		var ph: float = float(_mote_seq)
		_mote_seq += 1
		_motes.append({
			"node": mi, "t": 0.0,
			"p0": wp,
			"dx": cos(ph * 2.399) * MOTE_DRIFT_M,
			"dz": sin(ph * 2.399) * MOTE_DRIFT_M,
			"rise": MOTE_RISE_M * (1.25 if low else 1.0),
		})


## 把 t ∈ [0, MOTE_LIFE] 的微粒写到真实节点上(纯同步, 门禁可直接调)。
func apply_mote(m: Dictionary, t: float) -> void:
	var mi = m.get("node", null)
	if not is_instance_valid(mi):
		return
	var uu: float = clampf(t / MOTE_LIFE, 0.0, 1.0)
	var p0: Vector3 = m["p0"]
	(mi as Node3D).position = Vector3(
		p0.x + float(m["dx"]) * uu, p0.y + float(m["rise"]) * uu, p0.z + float(m["dz"]) * uu)
	## ★holdfade: 前 55% 满亮再收 —— 从出生就淡是本轮改了五次的老毛病
	var a: float = 1.0 if uu < 0.55 else (1.0 - (uu - 0.55) / 0.45)
	((mi as Node3D).get("material_override") as StandardMaterial3D).albedo_color = Color(
		COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, a)


## 一圈柱面波(只在 <25% 的爆发态放 —— 平时 4 次/秒放圈会糊成一片)。
func _emit_wave(pos2d: Vector2, amp: float) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	var mi := _mesh_node(_m_ring, _mat(Color(COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, 0.0), true, true, 9))
	mi.position = battle._world_pos(pos2d, GROUND_Y)
	_adopt(mi, "heal_wave")
	var w := {"node": mi, "t": 0.0, "amp": amp}
	_waves.append(w)
	apply_wave(w, 0.0)


## 把 u ∈ [0,1] 时刻的波形写到**真实节点**上。纯同步 —— 演出与门禁只有这一份实现。
func apply_wave(w: Dictionary, u: float) -> void:
	var mi = w.get("node", null)
	if not is_instance_valid(mi):
		return
	var x: float = maxf(clampf(u, 0.0, 1.0), WAVE_X0)
	var r: float = WAVE_R_PX * float(battle.WS) * x
	mi.scale = Vector3(maxf(r, 1e-4), 1.0, maxf(r, 1e-4))
	(mi.material_override as StandardMaterial3D).albedo_color = Color(
		COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, float(w["amp"]) * wave_amp(x))


## 携带者死了 / 换路: 收掉它的甲片环。
func drop_scutes(u: Dictionary) -> void:
	var keep: Array = []
	for h in _scutes:
		if is_same(h["u"], u):
			var r = h["root"]
			if is_instance_valid(r):
				r.queue_free()
			continue
		keep.append(h)
	_scutes = keep


# ══════════════════════════════════════════════════════════════════
#  §094 祖龟碑 —— 破土立碑 + 碑脚符环 + 石雷 + 全队印记
# ══════════════════════════════════════════════════════════════════

## 在 pos2d 立一座碑。返回句柄; 世界不在时返回 {}。
##
## ⚠ 句柄在本函数返回时就是 **τ=0 的最终值**(整座碑还埋在地下), 门禁下一行就能量。
func raise_stele(pos2d: Vector2, si: int) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	var root := Node3D.new()
	var gl: Color = COL_GLYPH
	# 碑座
	var plinth := _mesh_node(_m_box, _mat(Color(COL_STONE.r * 0.72, COL_STONE.g * 0.74, COL_STONE.b * 0.78, 1.0), false, false, 2))
	plinth.scale = Vector3(PLINTH_HW, PLINTH_H * 0.5, PLINTH_HD)
	plinth.position = Vector3(0.0, PLINTH_H * 0.5, 0.0)
	root.add_child(plinth)
	# 碑身(下宽上窄: 用两段盒子近似锥台 —— 一段盒子做不出收分, 收分正是"碑"的形)
	var shaft_h: float = STELE_H - PLINTH_H
	var seg_n := 4
	for i in range(seg_n):
		var f0: float = float(i) / float(seg_n)
		var f1: float = float(i + 1) / float(seg_n)
		var hw: float = lerpf(SHAFT_HW_BOT, SHAFT_HW_TOP, (f0 + f1) * 0.5)
		var seg := _mesh_node(_m_box, _mat(Color(COL_STONE.r, COL_STONE.g, COL_STONE.b, 1.0), false, false, 2))
		seg.scale = Vector3(hw, shaft_h * (f1 - f0) * 0.5, SHAFT_HD)
		seg.position = Vector3(0.0, PLINTH_H + shaft_h * (f0 + f1) * 0.5, 0.0)
		root.add_child(seg)
	# 碑面刻纹: 两面各 **si+1 道横纹**(条数 = 分星信息), 琥珀 MIX 漆色, 不是加法光
	## ★MIX 不是 ADD: ADD 会把刻纹加进已经很亮的碑身里烧成白, 那正是改前的样子。
	##   而 MIX 是"刻上去的漆" —— 无论碑身多亮, 刻纹处显示的就是琥珀色本身。
	var bands: Array = glyph_bands(si, shaft_h)
	for sgn in [1.0, -1.0]:
		for gb in bands:
			var band := _mesh_node(_m_box, _mat(Color(gl.r, gl.g, gl.b, 1.0), false, false, 6))
			band.scale = Vector3(float(gb["hw"]), float(gb["hh"]), 0.012)
			band.position = Vector3(0.0, PLINTH_H + float(gb["y"]), sgn * (SHAFT_HD + 0.014))
			root.add_child(band)
	# 碑脚符环(贴地·缓慢自转)
	var rune := _mesh_node(_m_ring, _mat(Color(gl.r, gl.g, gl.b, 0.42), true, true, 7))
	var rr: float = RUNE_R_PX * float(battle.WS)
	rune.scale = Vector3(rr, 1.0, rr)
	rune.position = Vector3(0.0, GROUND_Y, 0.0)
	root.add_child(rune)

	root.position = battle._world_pos(pos2d, 0.0)
	_adopt(root, "stele")
	var h := {"root": root, "rune": rune, "pos": pos2d, "t": 0.0, "si": clampi(si, 0, 2)}
	_steles.append(h)
	apply_stele(h, 0.0)
	# 破土: 复用 ShockwaveVfx 的爆点(不重造)
	_blast(pos2d, Color(COL_STONE.r, COL_STONE.g * 0.92, COL_STONE.b * 0.80, 0.9))
	return h


## 把 τ ∈ [0,1] 的升起形态写到**真实节点**上。纯同步。
func apply_stele(h: Dictionary, tau: float) -> void:
	var root = h.get("root", null)
	if not is_instance_valid(root):
		return
	var base: Vector3 = battle._world_pos(h["pos"], 0.0)
	root.position = Vector3(base.x, base.y - STELE_H * (1.0 - rise_profile(tau)), base.z)


## 每帧推进一座碑(升起 + 符环自转)。
func advance_stele(h: Dictionary, delta: float) -> void:
	h["t"] = float(h.get("t", 0.0)) + maxf(delta, 0.0)
	apply_stele(h, float(h["t"]) / RISE_SEC)
	var rune = h.get("rune", null)
	if is_instance_valid(rune):
		rune.rotation.y = fmod(float(h["t"]) * RUNE_SPIN, TAU)


## 收掉一座碑(换路 / 撤场)。
func drop_stele(h: Dictionary) -> void:
	var keep: Array = []
	for x in _steles:
		if x.get("root", null) == h.get("root", null):
			var r = x.get("root", null)
			if is_instance_valid(r):
				r.queue_free()
			continue
		keep.append(x)
	_steles = keep


## 砸一道石雷: 石块从 `to2d` 正上方 BOLT_H 米无初速落下, 落地放爆点。
## 返回句柄; 世界不在时返回 {}。★落时由 `fall_time(BOLT_H, BOLT_G)` 定死。
func stone_bolt(to2d: Vector2, si: int) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	var s: float = BOLT_R * (1.0 + 0.16 * float(clampi(si, 0, 2)))
	var mi := _mesh_node(_m_rock, _mat(Color(COL_BOLT.r, COL_BOLT.g, COL_BOLT.b, 1.0), false, false, 4))
	mi.scale = Vector3(s, s, s)
	_adopt(mi, "stone_bolt")
	var b := {
		"node": mi, "t": 0.0, "T": fall_time(BOLT_H, BOLT_G),
		"pos": to2d, "si": clampi(si, 0, 2),
	}
	_rocks.append(b)
	apply_bolt(b, 0.0)
	return b


## 把 τ ∈ [0,1] 的落体形态写到**真实节点**上。纯同步。
## ★高度走 `fall_profile`(真抛物线), 自转是匀角速(刚体无力矩)。
func apply_bolt(b: Dictionary, tau: float) -> void:
	var mi = b.get("node", null)
	if not is_instance_valid(mi):
		return
	var t: float = clampf(tau, 0.0, 1.0)
	var ground: Vector3 = battle._world_pos(b["pos"], 0.0)
	mi.position = Vector3(ground.x, ground.y + BOLT_H * fall_profile(t) + BOLT_R, ground.z)
	mi.rotation = Vector3(t * 5.6, t * 3.1, 0.0)


## 一次点爆(复用 ShockwaveVfx)。
func _blast(pos2d: Vector2, col: Color) -> void:
	if not _has_world():
		return
	var h: Dictionary = _shock.make_blast(pos2d, col, 1)
	if h.is_empty():
		return
	for k in ShockwaveVfx.NODE_KEYS:
		_adopt(h[k], "blast")
	_shocks.append(h)


## 全队光环的头顶印记 —— **名单由系统侧给**(全场生效、不设半径)。
##
## ★门禁数的就是这个名单的长度: 若哪天有人把光环改成"半径内才吃",
##   印记数会立刻对不上友军数 —— 这正是把"全场"这句话变成可判定的形式。
func set_marks(units: Array) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	var keep: Array = []
	for m in _marks:
		var still := false
		for u in units:
			if u is Dictionary and is_same(m["u"], u):
				still = true
				break
		if still:
			keep.append(m)
		else:
			var n = m.get("node", null)
			if is_instance_valid(n):
				n.queue_free()
	_marks = keep
	for u in units:
		if not (u is Dictionary):
			continue
		var have := false
		for m in _marks:
			if is_same(m["u"], u):
				have = true
				break
		if have:
			continue
		var ps: float = 7.5 * float(battle.WS)
		var mi := _mesh_node(_m_hex, _mat(Color(COL_GLYPH.r, COL_GLYPH.g, COL_GLYPH.b, 0.75), true, true, 9))
		mi.scale = Vector3(ps, 1.0, ps)
		_adopt(mi, "aura_mark")
		_marks.append({"u": u, "node": mi, "t": 0.0})


func mark_count() -> int:
	var n := 0
	for m in _marks:
		if is_instance_valid(m.get("node", null)):
			n += 1
	return n


# ══════════════════════════════════════════════════════════════════
#  §每帧推进 —— 全部走 sim 的 delta, 一个 tween 都不用(CLAUDE.md §3.5)
# ══════════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	if not _has_world():
		clear_all()
		return
	var d: float = maxf(delta, 0.0)
	# 甲片环: 跟随携带者 + 亮度指数衰减
	var ks: Array = []
	for h in _scutes:
		var u = h["u"]
		if not (u is Dictionary) or not u.get("alive", false):
			var r0 = h["root"]
			if is_instance_valid(r0):
				r0.queue_free()
			continue
		var root = h["root"]
		if not is_instance_valid(root):
			continue
		root.position = battle._world_pos(u["pos"], GROUND_Y)
		var decay: float = exp(-d / PLATE_TAU)
		var floor_a: float = PLATE_A * PLATE_FLOOR_FRAC
		var alphas: Array = h["a"]
		for k in range(alphas.size()):
			## ★衰减到地板为止, 不衰到 0 —— 甲片环是常驻物件, 脉冲只是往上加亮
			alphas[k] = maxf(floor_a, float(alphas[k]) * decay)
			var mi = (h["plates"] as Array)[k]
			if is_instance_valid(mi):
				(mi.material_override as StandardMaterial3D).albedo_color = Color(
					COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, float(alphas[k]))
		h["a"] = alphas
		ks.append(h)
	_scutes = ks
	# 回复脉冲波
	var kw: Array = []
	for w in _waves:
		w["t"] = float(w["t"]) + d
		var uu: float = float(w["t"]) / WAVE_LIFE
		if uu >= 1.0 or not is_instance_valid(w.get("node", null)):
			var wn = w.get("node", null)
			if is_instance_valid(wn):
				wn.queue_free()
			continue
		apply_wave(w, uu)
		kw.append(w)
	_waves = kw
	# 回复微粒
	var kmo: Array = []
	for m in _motes:
		m["t"] = float(m["t"]) + d
		if float(m["t"]) >= MOTE_LIFE or not is_instance_valid(m.get("node", null)):
			var mn = m.get("node", null)
			if is_instance_valid(mn):
				mn.queue_free()
			continue
		apply_mote(m, float(m["t"]))
		kmo.append(m)
	_motes = kmo
	# 碑: 升起 + 符环自转
	for h in _steles:
		advance_stele(h, d)
	# 在途石块
	var kr: Array = []
	for b in _rocks:
		b["t"] = float(b["t"]) + d
		var tt: float = float(b["t"]) / maxf(float(b["T"]), 0.001)
		if tt >= 1.0:
			var bn = b.get("node", null)
			if is_instance_valid(bn):
				bn.queue_free()
			_blast(b["pos"], COL_BOLT)
			continue
		apply_bolt(b, tt)
		kr.append(b)
	_rocks = kr
	# 头顶印记: 跟随 + 缓慢起伏(受迫振子的稳态解 —— 纯正弦, 不是随手加的抖动)
	var km: Array = []
	for m in _marks:
		var u = m["u"]
		var mi = m.get("node", null)
		if not (u is Dictionary) or not u.get("alive", false) or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			continue
		m["t"] = float(m.get("t", 0.0)) + d
		var bob: float = 0.07 * sin(TAU * 0.55 * float(m["t"]))
		mi.position = battle._world_pos(u["pos"], 1.15 + bob)
		km.append(m)
	_marks = km
	# 爆点
	var kb: Array = []
	for h in _shocks:
		if _shock.advance(h, d):
			kb.append(h)
			continue
		for k in ShockwaveVfx.NODE_KEYS:
			var n = h[k]
			if is_instance_valid(n):
				n.queue_free()
	_shocks = kb


# ══════════════════════════════════════════════════════════════════
#  §撤场
# ══════════════════════════════════════════════════════════════════

## free 掉本层建出来、还活着的所有节点; 返回真的 free 掉几个。
## ★句柄表也要清 —— 只 free 节点不清表, 下一帧 tick() 会拿着已 free 的句柄继续推
##   (memory [[fb-write-without-reader-and-fake-gates]] 的另一半)。
## ★网格缓存一并放掉: 不放的话进程退出时 Godot 报
##   `RID allocations of type DummyMesh were leaked at exit`(spirit_eq_vfx.gd:828 记的坑)。
func clear_all() -> int:
	var freed := 0
	for n in _owned:
		if is_instance_valid(n):
			n.queue_free()
			freed += 1
	_owned.clear()
	_scutes.clear()
	_waves.clear()
	_motes.clear()
	_steles.clear()
	_rocks.clear()
	_marks.clear()
	_shocks.clear()
	_m_hex = null
	_m_ring = null
	_m_rock = null
	_m_box = null
	# ★连 `_shock` 的三个网格缓存一起放 —— 它是**本层 new 出来的**实例, 生命周期归本层。
	#   实测: 不放的话进程退出刷 `3 RID allocations of type DummyMesh were leaked at exit`
	#   (对照组 verify_synergy_vfx 没有这三条 —— 它没触发过 make_blast, 缓存压根没建)。
	#   这条不在 run-tests.sh 的 FATAL 正则里、不会红门禁, 但它是真的在漏。
	if _shock != null:
		_shock._cache_shell = null
		_shock._cache_ring = null
		_shock._cache_dust = null
	return freed


## 本层还活着的节点数(kind 为空 = 不筛类型)。门禁/调试用。
func alive_count(kind: String = "") -> int:
	var n := 0
	for x in _owned:
		if not is_instance_valid(x):
			continue
		## ★`queue_free()` 是**延迟**的 —— 同一帧里 `is_instance_valid` 仍然为 true。
		##   不排掉它, "收掉了吗"这类断言会读到已经判死的节点(2026-08-08 在 090
		##   的预警圈上栽过一次: 明明收了, 门禁读出"还在")。
		if (x as Node).is_queued_for_deletion():
			continue
		if kind != "" and str(x.get_meta(META_KEY, "")) != kind:
			continue
		n += 1
	return n
