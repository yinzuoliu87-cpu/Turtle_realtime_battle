class_name GunEqVfx
extends RefCounted
## gun_eq_vfx.gd — 枪线四件新装备(077/078/079/080)的演出层
## (规格 docs/plans/20260805-装备逐件重做.md §0.5 · 实装契约 docs/plans/20260806-实装契约-批④.md §7)
##
## ══════════════════════════════════════════════════════════════════════
##  ★判据: 可验证的物理规律, 不是"我调得像"
## ══════════════════════════════════════════════════════════════════════
## 本项目 3D 演出的水准线(memory [[fb-3d-quality-bar-tentacle]])第一条是
## 「逐帧量参考做成包络表」——**这四件一张参考图都没有**, 那一步无从下手。
## 替代路线照 `shockwave_vfx.gd` / `bow_eq_vfx.gd`: 每条形态都落在一个**有闭式解的模型**上,
## 门禁验的是那个模型的**性质**(恒等式 / 尺度律 / 分布函数 / 帧率无关性),
## 手调出来的缓动曲线一条都过不了。
##
## ⚠ **诚实记录**: 没有参考素材 ⇒ 本文件**没有"逐帧量参考"这一步**。
##   下面五条模型是这一步的替代品, 不是它的等价物。**四件都还缺真美术**(见交付报告)。
##
## ── ① 080 投弹: 自由落体 + 前置量(真实轰炸机的"投弹提前量") ──────────
##   炸弹离机时带着直升机的水平速度 v, 竖直方向自由落体 ⇒
##       t_fall = √(2h/g)          lead = v · t_fall
##   ⇒ 弹着点在投放点**前方** lead 码, 弹迹是一条真抛物线而不是垂直掉下去。
##   ★两条可验证性质(门禁 ①):
##     · **尺度律 t_fall(4h) / t_fall(h) ≡ 2**(√ 关系)。匀速下落给 4, 任何 ease 给别的数。
##     · **lead 与 v 严格成正比**(悬停 v=0 时前置量恰为 0)。
##
## ── ② 080 旋翼: 相位积分器, 帧率无关 ───────────────────────────────
##   转子相位 φ(t) = (ω t) mod 2π。实现用**增量积分** φ += ω·dt ⇒
##   ★可验证性质(门禁 ②): 把同一段时间切成 1 步 / 100 步 / 不等长步, 末相位**逐点相等**。
##     这条挡的是"按帧号 ++"那种写法 —— 它在无头 CI 的高帧率下会转成陀螺(§3.5 的同源坑)。
##
## ── ③ 078 左管霰弹: 面积均匀散布(不是半径均匀) ─────────────────────
##   在半径 R 的扇形里**面积均匀**地取点, 半径必须取 r = R·√u (u~U(0,1))。
##   ★可验证性质(门禁 ③): 落在 R/2 以内的比例 ≡ **1/4**(面积比), 不是半径均匀的 1/2。
##   ⚠ 这不是美术偏好: 半径均匀会让弹丸在锥尖挤成一坨、锥口空掉 —— 看着像"喷了口气"而不是霰弹。
##
## ── ④ 078 右管连锁电弧: 中点位移分形(自仿射, H = 1/2) ──────────────
##   闪电的经典构造: 取线段中点, 沿法向偏移 σ, 递归。要"放大看还是闪电"就必须**自仿射**:
##       σ(k+1) / σ(k) ≡ 1/√2      (H = 1/2, 即布朗轨迹)
##   ★两条可验证性质(门禁 ④): 逐级比值恒为 1/√2; 端点**精确**落在两个目标身上(不漂)。
##     取 1/2(H=1)会得到一条光滑折线, 取 1(H=0)会得到白噪声毛球, 两者一测就分开。
##
## ── ⑤ 079 治疗光束: 真悬链线(不是抛物线, 也不是"手调一个 sag") ───────
##   一条**只受自重**的柔性绳的形状是悬链线 y = a(cosh(x/a) − 1), 其弧长
##       L = 2a·sinh(s / 2a)
##   给定跨度 s 与"绳比跨度长多少"(slack, 这里 1.15) 反解 a ⇒ 垂度完全由物理定死, 没有可调旋钮。
##   ★两条可验证性质(门禁 ⑤): 反解出的 a 满足弧长恒等式(误差 < 1e-6);
##     **垂度与跨度严格成正比** sag(2s)/sag(s) ≡ 2(同一根绳按比例放大)。
##     抛物线近似在 slack 1.15 这种"松绳"下会差出 3% 以上, 拿恒等式一验就露。
##
## ── ⑥ 金弹辉光 ≡ 该档金弹的真伤比例 ────────────────────────────────
##   "这一发是金弹" 必须在画面上读得出来。亮度不另设一张表, 直接用**羁绊给的真伤比例**
##   (1/2/3 档 = 60/80/100%) ⇒ 一个数两处用。
##   ★可验证性质(门禁 ⑥): `gold_glow(pct) ≡ pct`, 且产品侧传进来的 pct 与
##     `RealtimeBattle3DScene._queue_shots` 源码里那张表逐档相等。
##
## ── 技术路线 ────────────────────────────────────────────────────────
## · **零素材**: 全部用 `VfxTex` 程序化纹理 + 就地生成的 `ArrayMesh` 平面带, 不新建资源文件。
## · **不用 tween**: 所有瞬时效果的生命周期由本文件的 `tick(delta)` 自己推进
##   (CLAUDE.md §3.5: 无头 CI 下 `create_tween()` 推进不稳, 埋在 tween 链末尾的东西永远等不到)。
##   ⇒ 门禁可以同步喂 delta 把整段演出跑完, 且**结算根本不在演出里**(结算在 eq_gun_batch.gd)。
## · 每个入口都能**单独调用**(供 VFXPREVIEW 与门禁用)。

## 重力(码/秒²)。★不是 9.8: 本项目的长度单位是"码"(≈像素), 这里取的是让
## 直升机高度 220 码时落弹约 0.42 秒的量级 —— 读得出"投下去→炸开"这个节拍。
const G_PX := 2500.0
## 直升机的飞行高度(演出用世界高度, 米)与它在 2D 场上的"影子"偏移(码)
## ★2.6 → 5.2: 用户 2026-08-07 问「高度？」。龟约 **2.4 米**高(实测 80 屏幕像素 ÷ 33.5 px/米),
##   2.6 米等于**贴着龟头顶飞** —— 读起来不像空中单位, 也解释不了"它为什么打不到"。
##   5.2 米 ≈ 龟高的 2.2 倍, 明显在头顶之上, 而且仍在画面内(1.9 倍俯瞰下约 174 px)。
##   ⚠ 与 `BOMB_DROP_H`(220 码, 前置量公式用的**物理**下落高度)是两件事, 不要合并 ——
##     一个是演出高度、一个是弹道计算, 合并会让"看着高了" 变成 "炸弹提前量也变了"。
const HELI_H := 5.2
## 投弹起始高度(码) —— 与 HELI_H 是同一件事的两种单位, 这里只用于前置量公式
const BOMB_DROP_H := 220.0
## 旋翼角速度(弧度/秒)
const ROTOR_OMEGA := 26.0
## 悬链线的"松弛度": 绳长 = slack × 跨度
const BEAM_SLACK := 1.15
## 连锁电弧: 递归深度与首级偏移比例(相对跨度)
const ARC_DEPTH := 5            ## 2026-08-08 4→5(17→33 点): 17 点画出来是平滑水管, 不是电
const ARC_ROUGH := 0.34         ## 2026-08-08 0.16→0.34: 折角要真的折得出来
const ARC_MAX_DEV := 26.0       ## 单级横向位移的绝对上限(码) —— 长跨度不允许荡成大正弦波

## ── 078 的两个已确认问题(用户 2026-08-07 实拍)与改法 ─────────────────
## ①【电弧是白的不是电色】。根因**不是"没上色"**, 是两件事叠加:
##    · 原色 `COL_MAGIC #9bdcff` 明度 100%、饱和度只有 39% —— 在近黑场上本来就读作白;
##    · 折线有 2^4=16 段, 每段一块 **BLEND_MODE_ADD** 的带, 段与段在拐点重叠 ⇒ 直接加爆成白。
##    ⇒ 改成**双层**: 外层宽带用高饱和电紫(MIX 混合, 不会越叠越白),
##      内层窄带才用白热芯(ADD)。这样"芯是白的、身是紫的" = 闪电该有的样子,
##      而且**越叠越白在结构上被堵死**(叠的是 MIX 层)。
const COL_ARC := Color(0.47, 0.34, 1.0)        # 电紫(身)
const COL_ARC_CORE := Color(0.80, 0.95, 1.0)   # 白热芯
## ②【左右两管的相位读不出来】。原来两管**共用携带者中心一个出膛点**, 且右管(电击)
##    根本没画"从枪口打出去"这一段(只画目标之间的连锁) ⇒ 玩家看不到是哪一管在响。
##    ⇒ 左管从**上管口**出、右管从**下管口**出(垂直瞄准线各偏 BARREL_OFF 码),
##      并各自补一记**管口闪**; 右管再补一条"枪口 → 首目标"的电束。
const BARREL_OFF := 22.0
## 管口闪的长度/宽度(码)
const BARREL_FLASH_LEN := 34.0
const BARREL_FLASH_W := 7.0

var battle
## 自管生命周期的瞬时效果: [{node, t, life, kind, ...}]
var _fx: Array = []
## 长驻节点(直升机机体/旋翼/龟能条 · 炮台充能条), 撤场一次性拔掉
var _owned: Array = []
## 炮台充能条: [{u, root, fill}] —— 单位字典只当**值**存, 绝不当键(CLAUDE.md §3.2)
var _charge: Array = []


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and battle._world != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等演出
# ══════════════════════════════════════════════════════════════════

## ① 自由落体时间: t = √(2h/g)
static func bomb_fall_time(h_px: float) -> float:
	return sqrt(2.0 * maxf(0.0, h_px) / G_PX)


## ① 投弹前置量: lead = v · t_fall(与 v 严格成正比; 悬停时恰为 0)
static func bomb_lead(v_px: float, h_px: float) -> float:
	return v_px * bomb_fall_time(h_px)


## ① 弹道高度(码): 从 h 自由落体, 走完 f∈[0,1] 的行程时还剩多高
static func bomb_height(h_px: float, f: float) -> float:
	var q: float = clampf(f, 0.0, 1.0)
	return maxf(0.0, h_px * (1.0 - q * q))


## ② 旋翼相位积分器(帧率无关): 把 dt 累加进相位再取模, **不是**按帧号 ++
static func rotor_phase(prev: float, omega: float, dt: float) -> float:
	return fposmod(prev + omega * dt, TAU)


## ③ 面积均匀的扇形散布半径: r = R·√u
static func cone_r(u01: float, radius: float) -> float:
	return radius * sqrt(clampf(u01, 0.0, 1.0))


## ④ 中点位移分形的逐级偏移(自仿射 H = 1/2 ⇒ 逐级 ÷√2)
## ★2026-08-08 加 ARC_MAX_DEV 绝对上限。实拍(_vfxlab_p2eq_078_4.png)里长跨度的电弧
##   被 span×rough 放大成一个**从龟脚下荡下去的大正弦波** —— 200 码跨度的一级位移就有 68 码。
##   电弧要的是"高频小折角", 不是"低频大摆荡"。上限只钳**基幅**, 逐级 ÷√2 的自仿射律不变
##   (门禁 ⑥ 验的就是那个比值)。
static func arc_sigma(level: int, span: float, rough: float = ARC_ROUGH) -> float:
	return minf(span * rough, ARC_MAX_DEV) * pow(2.0, -0.5 * float(maxi(0, level)))


## ④ 生成一条闪电折线。端点**精确**是 a / b; 中间点按 H=1/2 的中点位移。
## ★随机走传进来的 rng(产品侧传 `battle._battle_rng`) —— 裸 randf 会破坏确定性。
static func arc_points(a: Vector2, b: Vector2, depth: int, rng: RandomNumberGenerator,
		rough: float = ARC_ROUGH) -> Array:
	var pts: Array = [a, b]
	var span: float = (b - a).length()
	var dir: Vector2 = (b - a).normalized() if span > 0.001 else Vector2.RIGHT
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	for lv in range(maxi(0, depth)):
		var s: float = arc_sigma(lv + 1, span, rough)
		var out: Array = [pts[0]]
		for i in range(pts.size() - 1):
			var m: Vector2 = (Vector2(pts[i]) + Vector2(pts[i + 1])) * 0.5
			var j: float = (rng.randf() * 2.0 - 1.0) if rng != null else 0.0
			out.append(m + perp * s * j)
			out.append(Vector2(pts[i + 1]))
		pts = out
	return pts


## ⑤ 悬链线参数 a: 解 2a·sinh(s/2a) = slack·s。单调 ⇒ 二分法, 40 步足够到 1e-9。
static func catenary_a(span: float, slack: float = BEAM_SLACK) -> float:
	var s: float = maxf(1.0, span)
	if slack <= 1.0:
		return 1.0e9                     # 绷直的绳没有垂度
	var lo := s * 0.01
	var hi := s * 100.0
	for _i in range(60):
		var mid: float = (lo + hi) * 0.5
		if catenary_len(s, mid) > slack * s:
			lo = mid                      # a 越大越平 ⇒ 弧长越短, 所以太长要把 a 调大
		else:
			hi = mid
	return (lo + hi) * 0.5


## ⑤ 悬链线弧长 L = 2a·sinh(s/2a)
static func catenary_len(span: float, a: float) -> float:
	return 2.0 * a * sinh(span / (2.0 * maxf(0.0001, a)))


## ⑤ 垂度 sag = a(cosh(s/2a) − 1)。★与跨度严格成正比(同一根绳按比例放大)
static func catenary_sag(span: float, slack: float = BEAM_SLACK) -> float:
	var a: float = catenary_a(span, slack)
	return a * (cosh(span / (2.0 * maxf(0.0001, a))) - 1.0)


## ⑤ 悬链线上 f∈[0,1] 处的下垂量(端点为 0, 中点为 sag)
static func catenary_drop(span: float, f: float, slack: float = BEAM_SLACK) -> float:
	var a: float = catenary_a(span, slack)
	var x: float = (clampf(f, 0.0, 1.0) - 0.5) * span
	return a * (cosh(span / (2.0 * maxf(0.0001, a))) - cosh(x / maxf(0.0001, a)))


## ⑥ 金弹辉光强度 ≡ 该档金弹的真伤比例(一个数两处用, 不另设表)
static func gold_glow(pct: float) -> float:
	return clampf(pct, 0.0, 1.0)


# ══════════════════════════════════════════════════════════════════
#  §零素材原语
# ══════════════════════════════════════════════════════════════════

func _adopt(n: Node3D, life: float, kind: String, extra: Dictionary = {}) -> Node3D:
	if not _has_world():
		return n
	battle._world.add_child(n)
	if life <= 0.0:
		_owned.append(n)
		return n
	var d: Dictionary = {"node": n, "t": 0.0, "life": life, "kind": kind}
	for k in extra:
		d[k] = extra[k]
	_fx.append(d)
	return n


## 贴地(或指定高度)的一条**平面带**: 沿 a→b 的矩形, 宽 half_w×2 码。
## 用 ArrayMesh 直接建 —— 零素材, 且朝向由几何决定(不靠 billboard 猜)。
##
## ★`h_b >= 0` = **两端不同高**(a 端 h、b 端 h_b), 带整体是倾斜的。
##   2026-08-08 加的: 电弧原来两端都写死 1.0 米, 于是一条链**水平贯穿全场**,
##   跟每个目标的实际身高毫无关系 —— 和 080「子弹全程平飞在头顶」是同一族错误。
func _band(a2: Vector2, b2: Vector2, h: float, half_w: float, col: Color,
		blend_add: bool = true, h_b: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var hb: float = h if h_b < 0.0 else h_b
	var dir: Vector2 = b2 - a2
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	var p: Vector2 = Vector2(-dir.y, dir.x).normalized() * half_w
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v: Array = [
		battle._world_pos(a2 + p, h), battle._world_pos(b2 + p, hb),
		battle._world_pos(b2 - p, hb), battle._world_pos(a2 - p, h)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(v[idx])
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# ★ADD 让重叠处越叠越亮 —— 折线拐点重叠 16 次就会加爆成白(078 电弧的旧账)。
	#   要"身"保持颜色的地方一律传 blend_add=false。
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if blend_add else BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = col
	mi.material_override = mat
	return mi


func _sprite(tex: Texture2D, pos3: Vector3, px: float, col: Color, flat: bool) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = col
	s.position = pos3
	s.pixel_size = px
	if flat:
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		s.axis = Vector3.AXIS_Y     # ★AXIS_Y 本身就是躺平贴地, 不要再加 rotation.x(会掰成竖环)
	else:
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return s


func _ring(pos2: Vector2, col: Color, radius: float, life: float) -> void:
	if not _has_world():
		return
	var s := _sprite(VfxTex._make_thin_ring_tex(), battle._world_pos(pos2, 0.06),
		(radius * 2.0 * battle.WS) / 256.0, col, true)
	_adopt(s, life, "ring", {"ps0": s.pixel_size * 0.35, "ps1": s.pixel_size, "a0": col.a})


# ══════════════════════════════════════════════════════════════════
#  §077 小手枪
# ══════════════════════════════════════════════════════════════════

## 077 开火演出的常量(码 / 米 / 秒)。★★全部来自 2026-08-07 的**实测探针**, 不是估的:
##   探针打出来 —— 枪精灵 pixel_size=0.0196、贴图一帧 40×40、`WS=0.0240`
##   ⇒ **半个枪长 = 16.37 码**、**精灵中心世界高度 y = 0.036 米**(基本贴地)。
##   我第一版把火焰写在 0.42 米、弹道写在 1.0 米 ⇒ 实拍里火焰掉在枪【下方】、
##   弹道从枪【上方】飞出还**穿过携带者的龟壳**。差了一整个身位, 而门禁全绿 ——
##   因为没有一条断言问过"它们在不在枪身上"。
## ⇒ 枪管尖 = 单位中心 + 朝向 × 18 码(16.37 半枪长 + 1.6 让火焰不压在枪管上)。
## ★★枪口在**贴图内**的位置(相对帧中心, 单位=帧宽/帧高的比例)。★这两个数改过三版, 全是实测逼出来的:
##   第①版 `半帧宽 / 帧中心` —— 猜的。用户实拍:「枪口火焰在哪？偏到哪里去了」。
##   第②版 `+0.4125 / −0.10` —— 量了贴图, 但**量错了哪一端**: 我默认"枪管在右",
##     于是拿最右列当枪口。逐列数不透明像素才发现: **x0~9 每列只有 12~14 px 高(细枪管)、
##     x30~36 才是圆润的枪托** ⇒ **枪管在贴图的【左】端**。
##   第③版(现在) —— 探针又打出决定性的一条: **`flip_h = true`**。
##     渲染层把整张图水平翻转了(所以屏幕上枪口朝右), 而我按"没翻转"算, 符号正好取反,
##     火焰落到 local x = −0.324 = 枪的【左后方】。
##   ⇒ 这两个数是**贴图坐标系**里的值; 显示位置要再乘一次翻转符号, 见下面 mx 的算式。
##   实测: 枪口列 x=0(16 帧全部一致) ⇒ 水平 (0.5−20)/40 = −0.4875 帧宽
##         枪口那一列的 y 中心, 16 帧中位数 ⇒ 竖直 +0.215 帧高(Godot 局部 +y 朝上)
##   ⇒ 直接记**枪口在贴图里的像素坐标**(左上原点), 换算交给上面那条真实公式:
##     x=0 (枪口列, 16 帧全一致) · y=11 (枪口那一列的 y 中心, 16 帧中位)
const MUZZLE_PX_X := 0.0
const MUZZLE_PX_Y := 11.0
## (旧常量, 现仅用于没有精灵时的兜底)
const PISTOL_MUZZLE_PX := 15.0
## ★26 码是实拍改小后的值: 第一版给 26 但 `_make_fire_glow_tex` 的可见辉光远大于名义半径,
##   13 倍拉近下盖住半个屏幕。按"火焰略大于枪管口径、不该盖住枪身"定 13 码。
##   ⚠ 这类"名义尺寸 ≠ 观感尺寸"只有实拍才抓得到 —— 贴图自带的软边把有效半径放大了约一倍。
## ★13 → 9: 13 码的软辉光在 11 倍拉近下是一大团, **连它自己的中心在哪都读不准**
##   (我为此多花了两轮去对锚点)。收小后枪口位置一眼可判。
const PISTOL_FLASH_PX := 9.0
## ★弹道的世界高度。枪精灵中心实测在 0.036 米、枪管比中心再低 0.1 帧高(≈0.08 米) ⇒ 约 0.0 米。
##   ⚠ 不写 0 —— 贴地会被地面 z-fight。0.05 刚好在枪管高度、又高于地面。
##   (枪口火焰不用这个数 —— 它是枪的子节点, 高度由 MUZZLE_FY 决定, 不经过世界坐标。)
const PISTOL_MUZZLE_H_M := 0.05
const PISTOL_FLASH_SEC := 0.09
## 后坐行程(码)。★不设时长常量 —— 时长按实际攻击间隔折算, 见 pistol_fire。
const PISTOL_KICK_PX := 7.0


## 077 开火: **枪口火焰 + 后坐力**。
##
## ★★为什么这两样用代码而不是精灵表(2026-08-07 实拍两轮后的定论):
##   PixelLab 出的 fire 动画连出两版, 火焰都画在**枪机**位置而不是枪口
##   (燧发枪历史上确实在那儿闪, 但读起来不像"开枪"), 后坐力也几乎看不出。
##   ⇒ **枪身用素材(idle 帧表)、这两样用代码**。代码的两个不可替代的好处:
##   ① 锚点算得准 —— 火焰生在**枪管尖**(朝向 × 半个枪长), 与弹道起点同一点;
##   ② **跟着实际射速缩放** —— 小手枪基础攻速 2/秒, 被枪羁绊顶档能到 4/秒。
##      固定帧数的精灵表在 0.25 秒的节拍下**播不完就被下一发打断**, 看起来是抽搐;
##      后坐时长按 `iv` 折算就永远占满一个攻击周期。
##
## `iv` = 这一发到下一发的间隔(秒)。`aim` = 单位朝向(已归一)。
func pistol_fire(p: Dictionary, aim: Vector2, iv: float) -> void:
	if not _has_world() or not (p is Dictionary):
		return
	var spr = p.get("sprite", null)
	if is_instance_valid(spr):
		# 后坐: 沿枪口反方向弹开, 再**临界阻尼**回位(永不过冲)。行程与时长都按射速缩放。
		p["_pistol_kick_t"] = 0.0
		p["_pistol_kick_T"] = clampf(iv * 0.55, 0.08, 0.30)
		p["_pistol_kick_d"] = -aim * PISTOL_KICK_PX
	# ★★枪口火焰: **挂成枪精灵的子节点**, 不算世界坐标。
	#   由来(2026-08-07 实拍): 第一版用 `_world_pos(muz, 高度)` 算, 火焰掉在枪的【下方】。
	#   根因是**我在用两套坐标系拼一个点** —— 水平偏移用场地码、高度用世界米,
	#   而枪精灵自己的世界 y 是渲染层定的(实测 0.036), 我猜了个 0.42 又猜了个 0.10, 都不对。
	#   ⇒ 挂子节点后, 偏移只剩**一个局部量**: 半枪长 = 半帧宽 × pixel_size。
	#     它天然跟着枪走 —— 连**后坐时火焰也跟着往后弹**, 而世界坐标版做不到这一点。
	if is_instance_valid(spr) and spr is Sprite3D:
		var gs: Sprite3D = spr
		var fw: float = float(gs.texture.get_width() / maxi(1, int(gs.hframes)))
		var fh: float = float(gs.texture.get_height() / maxi(1, int(gs.vframes)))
		# ★★2026-08-07 第二次修。第一版用"半帧宽 + 帧中心", 用户实拍:「枪口火焰在哪？偏到哪里去了」。
		#   量了贴图才知道两处都错(逐帧扫不透明像素, 帧 0/4/8 结论一致):
		#     · 不透明像素只到 x = 36/40 ⇒ 枪管尖在 **0.4125 帧宽**处, 不是 0.5(右边有 3.5px 留白)
		#     · 枪管的竖直中心在 y ≈ 24 而帧中心是 20 ⇒ 枪管**低于精灵中心 0.1 帧高**。
		#       这一项我第一版**完全没算**(默认写了 0)。
		#   ⇒ 锚点必须来自"贴图里枪管画在哪", 而不是"精灵框有多大"。这两件事不是一回事。
		# ★★第⑤版 —— 前四版全错, 每一版错在一个不同的假设上, 全部写下来当教训:
		#   ① `半帧宽 / 帧中心` —— 纯猜。用户:「枪口火焰在哪？偏到哪里去了」。
		#   ② `最右列当枪口` —— 量了贴图但**量错了哪一端**: 逐列数不透明像素才发现
		#      x0~9 每列只有 12~14 px 高(细枪管)、x30~36 才是圆润的枪托 ⇒ **枪管在左端**。
		#   ③ `符号没管 flip_h` —— 探针打出 **flip_h = true**(渲染层把整张图翻过来了,
		#      所以屏幕上枪口朝右), 我按没翻转算, 符号取反, 火焰落到枪的左后方。
		#   ④ `用 get_aabb()` —— 它返回的是 **1.571 米的立方体**(billboard 的保守包围盒,
		#      边长 = 帧尺寸的 2 倍), **根本不是精灵的可视范围**, 于是偏右一大截。
		#   ⑤ (现在) 探针打出决定性的最后一条: **`offset = (0, 20)` 贴图像素** ——
		#      精灵被整体上移 20px × pixel_size = **0.393 米**, 也就是说
		#      **节点位置在枪的【底部】而不是中心**。前四版全都默认了"节点=中心",
		#      这就是竖直方向一直偏低 0.393 米(屏幕上约 85 px)的原因。
		#   ⇒ 现在按【贴图像素 → 局部坐标】的真实换算式来, 三个因素一个不漏:
		#      居中(−fw/2) · 翻转(flip_h) · 偏移(offset)。
		var px_off: float = ((MUZZLE_PX_X + 0.5) - fw * 0.5) * gs.pixel_size
		if gs.flip_h:
			px_off = -px_off
		var mx: float = px_off + gs.offset.x * gs.pixel_size
		var my: float = (fh * 0.5 - (MUZZLE_PX_Y + 0.5)) * gs.pixel_size + gs.offset.y * gs.pixel_size
		var f := Sprite3D.new()
		f.texture = VfxTex._make_fire_glow_tex()
		f.shaded = false
		f.transparent = true
		f.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		f.modulate = Color(1.0, 0.92, 0.55, 1.0)
		f.pixel_size = (PISTOL_FLASH_PX * float(battle.WS)) / 64.0
		# 枪立绘朝右 ⇒ 枪口在 +x; 若被翻转过就取负(现在没翻, 留着防以后)
		f.position = Vector3(mx, my, 0.0)
		gs.add_child(f)
		_fx.append({"node": f, "t": 0.0, "life": PISTOL_FLASH_SEC, "kind": "puff", "a0": 0.95})
		# 弹道起点也用这一点(换算回场地码), 两者天然对齐。
		# ★只给**水平**分量: 枪立绘永远朝右不转向, 枪口就在 +x ——
		#   第一版让弹道沿 `aim` 斜出去(aim 指向目标, 是右下方) ⇒ 弹从枪的右下角冒出来, 不是枪口。
		p["_muzzle_px"] = mx / float(battle.WS)
		# ★弹道的**高度**也要用这个点 —— 第④版之前弹道高度写死 0.05 米,
		#   而枪口的真实全局高度是 `枪节点 y + my` ≈ 0.62 米。弹于是从枪底下飞出去。
		p["_muzzle_h"] = gs.global_position.y + my


func pistol_deploy(pos: Vector2) -> void:
	_ring(pos, Color(1.0, 0.82, 0.42, 0.85), 70.0, 0.4)


## 携带者阵亡 ⇒ 小手枪失去掩护(封顶 2 → 5)。红环一次, 让玩家读得出状态变了。
func pistol_uncovered(pos: Vector2) -> void:
	_ring(pos, Color(1.0, 0.35, 0.3, 0.9), 90.0, 0.5)


# ══════════════════════════════════════════════════════════════════
#  §通用: 弹迹 / 爆点
# ══════════════════════════════════════════════════════════════════

## 一条子弹弹迹。金弹时按 ⑥ 加亮加粗(亮度 = 该档真伤比例)。
## ★★2026-08-07 重做。原来这里是【一整条从枪连到目标的静止粗带】, 存活 0.16 秒。
##   实拍五帧, 它**每一帧都在、位置一模一样** —— 读起来不是"一颗弹飞过去", 是一根横在场上的棍
##   (用户 08-07 原话:「长方形也能算子弹」; 这一根就是我自己做的那一根)。
##   而且它起点是**单位中心**、高度写死 **1.0 米**, 而枪的精灵中心实测在 **0.036 米**
##   ⇒ 弹道从枪的上方飞出, 还**穿过携带者的龟壳**。
##
## 现在: **一颗真的在飞的弹** —— 从枪管尖出发, 按 BULLET_SPD 飞到目标, 后面拖一小截尾焰。
##   · 起点 = 枪管尖(与枪口火焰**同一个锚点**, 两者天然对齐)
##   · 高度 = 枪身高度(不再穿龟)
##   · 飞行时间 = 距离 / 速度 ⇒ **近的目标弹到得快、远的慢**, 这本身就是可读的信息
## ⚠ 仍然不用 tween: 位置由本文件的 `tick()` 推(CLAUDE.md §3.5)。
## ★★2026-08-08 ⑮【手枪和机炮打出一模一样的弹】用户实测指出:
##   077 是**单发大威力手铳**(0.5 秒一发)、080 三星是**一轮 10 发的机炮** ——
##   而两者调的是同一个 `tracer`: 同速度、同外观、同尾焰、同命中。视觉上完全没有区别。
##   ⇒ 分成两型。**区别不在弹道曲线**(用户明确说子弹不需要重力), 在**速度/粗细/长短**:
##     · 手铳 = 慢、粗、短尾, 一发一发看得清 —— "有分量"
##     · 机炮 = 快、细、长尾, 连成串 —— "泼出去"
enum { BUL_PISTOL, BUL_MG }
## 速度(码/秒) / 头段长(码) / 尾段长(码) / 头粗 / 尾粗 / 弹头辉光(码)
const BULLET_SPEC := {
	BUL_PISTOL: {"spd": 390.0, "head": 16.0, "tail": 30.0, "hw": 2.6, "tw": 1.4, "px": 9.0},
	BUL_MG:     {"spd": 980.0, "head": 26.0, "tail": 62.0, "hw": 1.5, "tw": 0.9, "px": 5.0},
}
const BULLET_SPD := 390.0       ## 码/秒。★用户 2026-08-07 两次实拍后定: 2600 →(−70%) 780 →(再 −50%) **390**。
                                ## 260 码 ≈ 0.67 秒到 —— 一发的飞行完整看得清, 而攻击间隔是 0.5 秒
                                ## ⇒ **场上会同时有两发在飞**, 这本身就读得出"射速比弹速快"。
const BULLET_PX := 9.0          ## 弹头辉光尺寸(码) —— 只负责"热", 方向交给流线
const BULLET_HEAD := 16.0       ## 弹头流线长度(码)
const BULLET_TAIL := 30.0       ## 尾焰长度(码, 向后画)
## 目标**身体中段**的世界高度(米)。★从目标自己的立绘算, 不写死 ——
## 实测假人立绘高 2.00 米, 中段 ≈ 1.0 米。
static func body_mid_h(tgt) -> float:
	if tgt is Dictionary:
		var sp = (tgt as Dictionary).get("sprite", null)
		if is_instance_valid(sp) and sp is Sprite3D:
			var s2: Sprite3D = sp
			if s2.texture != null:
				var full: float = s2.pixel_size * float(s2.texture.get_height() / maxi(1, int(s2.vframes)))
				return maxf(0.2, full * BODY_HIT_FRAC) + float((tgt as Dictionary).get("height", 0.0))
	return 1.0


## ★★2026-08-07 用户:「我问你子弹打到了假人身体的哪个地方」——
##   实测: 弹道**全程飞在枪口高度**, 从来没往目标身上落。
##     · 077 手枪 0.62 米 ÷ 假人 2.00 米 = **31%** ⇒ 打在**脚踝**
##     · 080 直升机 **5.20 米** ⇒ **从头顶上方 3.2 米飞过去**, 根本没碰到身体
##   ⇒ 弹道高度从**枪口**线性降到**目标身体中段**(由目标立绘算, 见 body_mid_h)。
##   `h_to < 0` 表示"沿用出膛高度"(供不需要落点的调用方)。
const BODY_HIT_FRAC := 0.5
## `tgt`: 传目标字典的话, 弹会**跟着它走**(见下面 ⑬)。返回**飞行时间(秒)**, 供结算对齐。
##
## ★★2026-08-08 ⑬【终点在开火瞬间锁死】用户实测指出:
##   原来 `b` 是开火那一刻抄下来的坐标, 弹飞 0.67 秒期间目标只要动了,
##   弹就**打到它刚才站的地方**并在那儿炸出命中火花 —— 目标已经走了。
##   ⇒ 传了 `tgt` 就每帧读它**当前**位置; 目标死了/丢了才退回锁死的那个点。
func tracer(a: Vector2, b: Vector2, col: Color, gold_pct: float = 0.0, h_m: float = PISTOL_MUZZLE_H_M,
		h_to: float = -1.0, tgt = null, kind: int = BUL_PISTOL) -> float:
	var sp: Dictionary = BULLET_SPEC[kind]
	if not _has_world():
		return clampf((b - a).length() / float(sp["spd"]), 0.05, 0.5)   # 无世界也要给飞行时间(结算靠它)
	var g: float = gold_glow(gold_pct)
	var c := Color(col.r + (1.0 - col.r) * g, col.g + (0.9 - col.g) * g, col.b * (1.0 - 0.5 * g), 0.95)
	var dist: float = (b - a).length()
	var life: float = clampf(dist / float(sp["spd"]), 0.05, 0.5)
	if not _has_world():
		return life
	var dir: Vector2 = (b - a).normalized() if dist > 0.001 else Vector2.RIGHT
	# ★★2026-08-07 用户问「子弹方向有考虑吗」—— 上一版**没有**: 弹头是一团**圆的**辉光,
	#   圆形没有方向, 只有后面那条尾焰暗示了走向。现在整颗弹是一条**沿飞行方向的流线**:
	#     · 弹头 = 短而亮的带(BULLET_HEAD 长), 从当前位置**向前**画
	#     · 尾焰 = 长而暗的带(BULLET_TAIL 长), 从当前位置**向后**画
	#   两段都由 dir 定向 ⇒ 不管往哪个方向打, 弹的长轴永远和航线重合。
	#   ⚠ 不能靠旋转 Sprite3D 解决: 弹头原来用的是 billboard 精灵, billboard 会一直正对相机,
	#     它的"旋转"在 2.5D 斜视角下与场地方向对不上。带(平面网格)是贴着场地画的, 才对得上。
	var _h2: float = h_m if h_to < 0.0 else h_to
	# ★★2026-08-08 ⑬ 的实现事故: v0.19.53 我把 `return life` 插在了这三段**上面**,
	#   于是弹头辉光和它携带的 `tgt`(跟踪目标的唯一载体)**从那次起一次都没被创建过** ——
	#   tick() 里的 "bullet" 分支写得好好的, 但零生产者。宣称做了 ⑬, 实际全程没跑。
	#   ⇒ 三段都建完再 return; 且 `tgt` 同时挂到两条 bullettail 上, 让**看得见的那条亮线**
	#     也跟着目标走(只挂辉光的话, 亮线仍然打向旧坐标 = 用户看到的还是打空)。
	var head := _band(a, a + dir * float(sp["head"]), h_m, float(sp["hw"]) + 3.0 * g, c)
	_adopt(head, life, "bullettail", {"from": a, "to": b, "a0": c.a, "h": h_m, "h2": _h2, "tgt": tgt})
	var tail := _band(a - dir * float(sp["tail"]), a, h_m, float(sp["tw"]) + 2.2 * g,
		Color(c.r, c.g, c.b, 0.40))
	_adopt(tail, life, "bullettail", {"from": a, "to": b, "a0": 0.40, "h": h_m, "h2": _h2, "tgt": tgt})
	# 弹头再叠一点点辉光(只是"热", 不承担方向)
	var s := _sprite(VfxTex._make_fire_glow_tex(), battle._world_pos(a, h_m),
		(float(sp["px"]) * (1.0 + 0.5 * g) * float(battle.WS)) / 64.0, c, false)
	_adopt(s, life, "bullet", {"from": a, "to": b, "a0": c.a, "h": h_m, "h2": _h2, "tgt": tgt})
	return life


## 爆炸立绘(11 帧一次性动画)。★**不做乒乓** —— 乒乓会让火球缩回去 = 倒放, 爆炸只能单向播。
const BLAST_TEX_PATH := "res://assets/sprites/vfx/eq-blast.png"
const BLAST_SEC := 0.55
## 爆炸立绘的帧宽 = 伤害半径 × 这个系数。★不是 2.0(=直径)：
##   立绘里的火球只占帧宽的一部分, 而**烟柱还往帧外的观感上延伸** ——
##   按直径给, 实拍下整团把龟全吞掉、像一堵墙。1.3 让**可见火球**大致等于伤害半径,
##   而"这一炸波及多大"由**贴地环**负责讲清楚(环画的是真半径, 一码不差)。
const BLAST_ART_K := 1.3
static var _blast_tex_cache: Texture2D = null
static var _blast_tex_tried := false

func _blast_tex() -> Texture2D:
	if not _blast_tex_tried:
		_blast_tex_tried = true
		if ResourceLoader.exists(BLAST_TEX_PATH):
			_blast_tex_cache = load(BLAST_TEX_PATH)
	return _blast_tex_cache


## 弹着火花: 一小团亮闪 + 一圈很小的冲击环。★尺寸**远小于**炸弹的爆炸 ——
## 它要说的是"这一发打中了", 不是"这里炸了个大坑"; 做大了会和地毯轰炸的爆点混淆。
const IMPACT_PX := 22.0
const IMPACT_SEC := 0.16

## `col` 默认暖白(弹着)。078 的电击链传电色 ⇒ 玩家一眼分得出"这一下是电还是弹"。
## ★公开(不带下划线)是因为 078 要在**伤害真的落下的那一刻**从外面调它 —— 见 eq_gun_batch。
func hit_spark(at: Vector2, h_m: float, col: Color = Color(1.0, 1.0, 0.92, 1.0)) -> void:
	_bullet_impact(at, h_m, col)


func _bullet_impact(at: Vector2, h_m: float, col: Color = Color(1.0, 1.0, 0.92, 1.0)) -> void:
	if not _has_world():
		return
	# ★★两版都错过, 教训写在这:
	#   ①「一团淡黄辉光」—— 打在绿色龟壳上读成"一小片反光", 实拍几乎看不出打中了。
	#   ②「白热芯 + 4 根放射火花(_band)」—— 火花在实拍里是**黑棍**(短带贴在地面高度、
	#      被龟的立绘压住), 而冲击环**大了整整 4 倍**: 我把 `_make_thin_ring_tex` 的尺寸
	#      **硬编码成 64**, 而 `_ring` 里写的是 **256**(纹理真实尺寸)。
	#      —— 又是"硬编码贴图尺寸"这一族, 今晚第三次(枪口 half_len、爆炸 BLAST_ART_K)。
	#   ⇒ 现在只剩两样, 都走**现成的原语**, 不自己算尺寸:
	#     · 白热芯: 一小团 glow(billboard, 跟着目标身高)
	#     · 冲击环: 直接调 `_ring`(它自带正确的 256 换算与扩张动画)
	var sp := _sprite(VfxTex._make_fire_glow_tex(), battle._world_pos(at, h_m),
		(IMPACT_PX * float(battle.WS)) / 64.0, col, false)
	_adopt(sp, IMPACT_SEC, "puff", {"a0": 1.0})
	_ring(at, Color(col.r, col.g * 0.88, col.b * 0.55 + 0.2, 0.75), IMPACT_PX * 0.9, IMPACT_SEC * 1.4)


## 一次爆点。★★2026-08-07 用户:「爆炸特效？」—— 原来这里是
##   **一个扩张的贴地环 + 一团圆辉光**, 也就是用户说的「瞎画个圈也算特效」。
##   现在是真爆炸立绘(火球 → 碎块飞溅 → 烟尘消散, 11 帧)。
##   ⚠ 贴地环**保留**但降到配角(alpha 0.9 → 0.35): 它标的是**伤害半径**, 是信息不是装饰;
##     去掉它玩家就读不出这一炸波及多大。火球负责"好看", 环负责"讲清楚"。
func blast(pos: Vector2, radius: float, col: Color) -> void:
	if not _has_world():
		return
	# ★★2026-08-08 去掉这里原来那个贴地扩张环 —— 用户:「什么圈圈？」
	#   预警圈(收缩)与它(扩张)**同样 360 码、同一个点、同时播**, 一收一放互相打架。
	#   现在: 预警圈负责"炸多大 + 还有多久", 落地后**只剩火球**, 不再有第二个环。
	var bt: Texture2D = _blast_tex()
	if bt != null:
		var nf: int = maxi(1, bt.get_width() / maxi(1, bt.get_height()))
		# ★尺寸 = **真实伤害直径**(2 × 半径), 不再乘"怕它太大"的系数 ——
		#   1.3 × 半径 = 234 码, 而伤害直径是 360 码 ⇒ **火球比伤害范围小 35%**,
		#   同一次爆炸里圈和火球自相矛盾。要"别太满"该由素材构图解决, 不是把它整体缩小。
		# ★底边贴地: 原来画在 0.30 米、billboard 居中 ⇒ **下半个火球埋在地面以下**。
		var one_h: float = float(bt.get_height())
		var sp := _sprite(bt, battle._world_pos(pos, 0.02),
			(radius * 2.0 * float(battle.WS)) / one_h, Color(1, 1, 1, 1), false)
		sp.hframes = nf
		sp.frame = 0
		sp.offset = Vector2(0.0, one_h * 0.5)
		_adopt(sp, BLAST_SEC, "blastanim", {"nf": nf})
		return
	# 兜底(素材缺席): 老的圆辉光
	var s := _sprite(VfxTex._make_fire_glow_tex(), battle._world_pos(pos, 0.5),
		(radius * 0.9 * battle.WS) / 96.0, Color(col.r, col.g, col.b, 0.8), false)
	_adopt(s, 0.35, "puff", {"a0": 0.8})


# ══════════════════════════════════════════════════════════════════
#  §078 左管锥形霰弹 / 右管连锁电弧
# ══════════════════════════════════════════════════════════════════

## 某一管的**管口位置**(纯几何, 门禁直接验): 左管在瞄准线上侧、右管在下侧, 各偏 BARREL_OFF 码。
## ★这是"两管相位"的唯一信息载体 —— 两管出膛点必须**真的分开**, 不是靠颜色暗示。
static func barrel_muzzle(origin: Vector2, dir: Vector2, left: bool) -> Vector2:
	var d: Vector2 = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	var perp: Vector2 = Vector2(-d.y, d.x)
	return origin + perp * (-BARREL_OFF if left else BARREL_OFF) + d * 12.0


## 管口闪: 出膛点朝射向的一小道亮条。左管铜橙、右管电紫 ⇒ 相位一眼分得出。
func barrel_flash(origin: Vector2, dir: Vector2, left: bool) -> Vector2:
	var m: Vector2 = barrel_muzzle(origin, dir, left)
	if not _has_world():
		return m
	var d: Vector2 = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	var c: Color = Color(1.0, 0.80, 0.38) if left else COL_ARC_CORE
	var mi := _band(m, m + d * BARREL_FLASH_LEN, 1.0, BARREL_FLASH_W * 0.5, Color(c.r, c.g, c.b, 0.95))
	_adopt(mi, 0.12, "band", {"a0": 0.95})
	return m


## 霰弹弹丸: 速度(码/秒) / 单颗流线长(码) / 半宽(码)。
## ★2026-08-08 实拍(_vfxlab_p2eq_078_0.png)后重做。旧版是 **14 条 0.14 秒的静态土棍**
##   从龟身中央散开, 长度随机、一动不动、穿过敌人也不停 —— 看着像一把扫帚, 不像开枪。
const PELLET_SPD := 900.0
const PELLET_LEN := 26.0
const PELLET_HW := 1.6

## 锥形霰弹: 一把**真的飞出去**的弹丸。弹丸半径按 ③ 取 r = R√u(面积均匀)。
## ★从**左管口**出膛(不是携带者中心) —— 见 BARREL_OFF 那段注释。
## ★★2026-08-08 三处重做(实拍 _vfxlab_p2eq_078_0.png):
##   ① 弹丸从静态棍改成**沿飞行方向平移的流线**(复用 bullettail: 建短段 + 每帧平移),
##      于是"射出去"这件事本身有了过程 —— 而不是一帧糊 14 根线上去。
##   ② 高度从写死 0.9 米改成 **出膛高度 → 目标身体中段**(h_to), 和 077/080 的曳光同一条规矩。
##   ③ **删掉那个套在携带者身上的 140 码大圆环**。它既不是射程(400)也不是任何判定,
##      玩家只会读成"这里有个范围" —— 正是用户在 080 追问的「什么圈圈？」。
##      管口的存在感交给 barrel_flash(它就在管口, 尺寸只有 34 码, 不冒充范围)。
func cone_blast(origin: Vector2, dir: Vector2, range_px: float, half_deg: float,
		col: Color, gold_pct: float = 0.0, pellets: int = 14, h_from: float = 0.9,
		h_to: float = -1.0) -> int:
	if not _has_world():
		return 0
	var g: float = gold_glow(gold_pct)
	var rng: RandomNumberGenerator = battle._juice_rng
	var muz: Vector2 = barrel_flash(origin, dir, true)
	var hb: float = h_from if h_to < 0.0 else h_to
	var n := 0
	for i in range(pellets):
		var r: float = cone_r(rng.randf(), range_px)
		var th: float = deg_to_rad(half_deg) * (rng.randf() * 2.0 - 1.0)
		var d: Vector2 = dir.rotated(th)
		var dst: Vector2 = muz + d * r
		# ★★弹速**逐颗抖动**。等速时全部弹丸永远在同一个半径上 ⇒ 一道整齐的弧形阵面,
		#   实拍(重做第一版)里读成一把**梳子/百叶窗**在平移, 完全不像喷出去的霰弹。
		#   抖了速度, 任一瞬间弹丸就散在不同半径上, 扇面本身才浮出来。
		var spd: float = PELLET_SPD * (0.62 + 0.76 * rng.randf())
		var life: float = clampf(r / spd, 0.05, 0.6)
		# 长度跟着速度走(快的拉得长) —— 等长的短棍是"梳齿"的另一半原因
		var seg: float = PELLET_LEN * (0.7 + 0.9 * spd / PELLET_SPD)
		# ★ADD 混合下 alpha 就是亮度: 0.62 的暖金 (1.0,0.81,0.42) 加出来是 (0.62,0.50,0.26)
		#   = 一根**土棕色的棍**。实拍里整把霰弹灰扑扑的根因就在这一个数, 不在颜色常量。
		var a0: float = 0.92 + 0.08 * g
		var mi := _band(muz, muz + d * seg, h_from, PELLET_HW + 2.0 * g,
			Color(col.r, col.g + 0.15 * g, col.b, a0))
		_adopt(mi, life, "bullettail", {"from": muz, "to": dst, "a0": a0, "h": h_from, "h2": hb, "fade0": 0.75})
		n += 1
	return n


## 右管出膛的那一束电: 从**右管口**打到首目标。返回管口位置(门禁验两管真的分开)。
## ★原来右管一发都没画"从枪口出去"这一段, 只画目标之间的连锁 ⇒ 读不出是右管在响。
func eel_bolt(origin: Vector2, first: Vector2, gold_pct: float = 0.0,
		h_from: float = 1.0, h_to: float = -1.0) -> Vector2:
	var m: Vector2 = barrel_flash(origin, first - origin, false)
	chain_arc(m, first, COL_ARC, gold_pct, h_from, h_to)
	return m


## 电弧的分叉: 每条链甩出几根**打不到人的短枝**。
## ★这是"像不像电"的关键 —— 一条光滑的主干读成水管, 有枝杈才读成放电。
const ARC_FORKS := 3
const ARC_FORK_FRAC := 0.15     ## 枝长 = 主干跨度 × 这个比例(上限)。★0.34 太长，实拍里甩成一个套马索的大圈

## 连锁电弧: 中点位移分形(④)。端点精确落在两个目标身上。
## ★双层画法(见 COL_ARC 那段注释): 外层电紫用 **MIX**(重叠不加爆), 内层白热芯才用 ADD。
##   原来 16 段全是 ADD 的浅蓝带, 拐点一叠就成白线 —— 这正是"电弧是白的"的根因。
##
## ★★2026-08-08 实拍(_vfxlab_p2eq_078_3.png)后三处重做:
##   ① **太粗太平滑** —— 6.0 码的紫带 + 2.4 的白芯, 加上 rough=0.16/depth=4 只有 17 个点,
##      画出来是一条平滑的紫色**水管**(实拍里像穿了 4 只龟的晾衣绳)。
##      ⇒ 收细到 3.2/1.1, 粗糙度 0.16→0.34、层数 4→5(33 点) ⇒ 出尖锐折角。
##   ② **没有分叉** —— 见 ARC_FORKS。
##   ③ **两端写死 1.0 米** —— 一条水平直线贯穿全场, 跟目标身高无关。⇒ 两端各自取高度。
func chain_arc(a: Vector2, b: Vector2, _col: Color, gold_pct: float = 0.0,
		h_a: float = 1.0, h_b: float = -1.0) -> int:
	if not _has_world():
		return 0
	var g: float = gold_glow(gold_pct)
	var hb: float = h_a if h_b < 0.0 else h_b
	var rng: RandomNumberGenerator = battle._battle_rng
	var pts: Array = arc_points(a, b, ARC_DEPTH, rng)
	var last: int = maxi(1, pts.size() - 1)
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		# 高度沿链**线性插值** ⇒ 从这一端的身体中段斜到那一端的身体中段
		var q0: float = lerpf(h_a, hb, float(i) / float(last))
		var q1: float = lerpf(h_a, hb, float(i + 1) / float(last))
		# 身: 高饱和电紫的窄带, MIX ⇒ 越叠越白在结构上不可能发生
		var body := _band(p0, p1, q0, 3.2 + 1.6 * g,
			Color(COL_ARC.r + 0.35 * g, COL_ARC.g, COL_ARC.b, 0.92), false, q1)
		_adopt(body, 0.13, "band", {"a0": 0.92})
		# 芯: 细白热带, ADD(只有它会发亮, 且宽度只有身的三分之一)
		var core := _band(p0, p1, q0 + 0.02, 1.1 + 0.7 * g,
			Color(COL_ARC_CORE.r, COL_ARC_CORE.g, COL_ARC_CORE.b, 1.0), true, q1 + 0.02)
		_adopt(core, 0.12, "band", {"a0": 1.0})
	# 分叉: 从主干中段随机挑几个节点甩出短枝(纯装饰, 不参与任何判定)
	var span: float = (b - a).length()
	for _f in range(ARC_FORKS):
		var k: int = 1 + int(rng.randf() * float(maxi(1, pts.size() - 2)))
		k = clampi(k, 1, pts.size() - 2)
		var root: Vector2 = pts[k]
		var seg: Vector2 = Vector2(pts[k + 1]) - Vector2(pts[k - 1])
		var pdir: Vector2 = Vector2(-seg.y, seg.x).normalized() if seg.length() > 0.001 else Vector2.UP
		var sgn: float = 1.0 if rng.randf() < 0.5 else -1.0
		var tip: Vector2 = root + (pdir * sgn + seg.normalized() * 0.5).normalized() \
			* span * ARC_FORK_FRAC * (0.4 + 0.6 * rng.randf())
		var fh: float = lerpf(h_a, hb, float(k) / float(last))
		for fp in _fork_pts(root, tip, rng):
			var fb := _band(fp[0], fp[1], fh, 1.4 + 0.6 * g,
				Color(COL_ARC.r + 0.3 * g, COL_ARC.g, COL_ARC.b, 0.6), false)
			_adopt(fb, 0.11, "band", {"a0": 0.6})
	return pts.size()


## 一根枝: 折两下就完(枝不需要主干那么细的分形)。返回若干 [p0, p1] 段。
func _fork_pts(root: Vector2, tip: Vector2, rng: RandomNumberGenerator) -> Array:
	var pts: Array = arc_points(root, tip, 2, rng, ARC_ROUGH * 0.8)
	var segs: Array = []
	for i in range(pts.size() - 1):
		segs.append([pts[i], pts[i + 1]])
	return segs


# ══════════════════════════════════════════════════════════════════
#  §079 医疗炮台
# ══════════════════════════════════════════════════════════════════

func tower_deploy(pos: Vector2) -> void:
	_ring(pos, Color(0.45, 1.0, 0.72, 0.9), 120.0, 0.5)


## 治疗光束: 真悬链线(⑤)。金弹(治疗翻倍)时画两股、更亮。
func heal_beam(a: Vector2, b: Vector2, col: Color, doubled: bool = false) -> int:
	if not _has_world():
		return 0
	var span: float = (b - a).length()
	if span < 1.0:
		return 0
	var segs := 10
	var drop_scale: float = 0.004 * battle.WS   # 码 → 世界米(垂度画在高度上)
	var n := 0
	for k in range(segs):
		var f0: float = float(k) / float(segs)
		var f1: float = float(k + 1) / float(segs)
		var p0: Vector2 = a.lerp(b, f0)
		var p1: Vector2 = a.lerp(b, f1)
		var h0: float = 1.2 - catenary_drop(span, f0) * drop_scale
		var mi := _band(p0, p1, maxf(0.15, h0), (3.0 if not doubled else 5.0),
			Color(col.r, col.g, col.b, 0.55 if not doubled else 0.9))
		_adopt(mi, 0.3, "band", {"a0": 0.55 if not doubled else 0.9})
		n += 1
	return n


## 炮台的金弹充能条: 已射满几发 / 还差几发出金弹。
## ★这条正是 `[4,3,2]` 那张表在**画面上**的出口 —— 玩家看得见"再打 2 发就出金弹"。
func tower_charge(t: Dictionary, ct: int, per: int) -> float:
	var frac: float = clampf(float(ct) / float(maxi(1, per)), 0.0, 1.0)
	if not _has_world():
		return frac
	var slot = null
	for c in _charge:
		if is_same(c["u"], t):
			slot = c
			break
	if slot == null:
		var bg := _sprite(VfxTex._make_pixel_block_tex(), Vector3.ZERO, 0.02,
			Color(0.05, 0.12, 0.1, 0.7), false)
		bg.scale = Vector3(3.2, 0.5, 1.0)
		var fl := _sprite(VfxTex._make_pixel_block_tex(), Vector3.ZERO, 0.02,
			Color(1.0, 0.85, 0.35, 0.95), false)
		fl.scale = Vector3(0.01, 0.42, 1.0)
		_adopt(bg, 0.0, "bar")
		_adopt(fl, 0.0, "bar")
		slot = {"u": t, "bg": bg, "fill": fl}
		_charge.append(slot)
	var base: Vector3 = battle._world_pos(Vector2(t["pos"]), 1.9)
	slot["bg"].position = base
	slot["fill"].position = base + Vector3(-3.2 * 0.03 * (1.0 - frac), 0.0, 0.0)
	slot["fill"].scale = Vector3(maxf(0.01, 3.2 * frac), 0.42, 1.0)
	return frac


# ══════════════════════════════════════════════════════════════════
#  §080 直升机
# ══════════════════════════════════════════════════════════════════

## 机体 = 发光球(机身) + 平面带(尾梁) + 旋转的双叶旋翼 + 龟能条。全部零素材。
## 080 机身立绘的显示高度(码)与素材路径。★立绘缓存一次 —— 每架直升机都 load 一遍
## 会在坠机重生时反复读盘; `null` 与"没查过"要分开存, 否则没素材时每帧都去 exists() 一次。
## ★58 → 96: 用户实拍「直升机小了」。58 码在 1.9 倍俯瞰下只有 74 屏幕像素,
##   **比一只龟(84 px)还小** —— 一架直升机比龟小, 读起来就不像直升机。
##   ★96 仍然被用户判为「小了」(第二次)。根因是 HELI_BODY_PX 定的是**帧宽**,
##   而直升机在 64×64 的帧里是**又扁又宽**的一条(只占中间约 1/3 的高度) ——
##   所以「帧宽 96 码」实际画出来只有约 40 码高, **比龟(80 px)矮一半** ⇒ 读起来就是小。
##   ⇒ 160 码。判据不是「帧宽等于几」, 而是**画出来的机身要明显大于一只龟**。
const HELI_BODY_PX := 160.0
## 起手提示: 警示环半径(码) / 时长(秒) / 震屏强度
const ALERT_R := 190.0
const ALERT_SEC := 0.42
const ALERT_SHAKE := 4.0
## 地面投影相对机身宽度的比例
const SHADOW_K := 0.62
## 起手闪白持续(秒)与坠机冒烟间隔(秒)
const ALERT_FLASH := 0.35
const CRASH_SMOKE_IV := 0.09
## 旋翼转一圈, 机身立绘播几轮。1.0 = 一圈一轮。
const HELI_FRAME_CYCLES := 1.0
## ★★机头在**贴图内**的像素坐标(左上原点)。这两个数我第一版**认反了两端**, 教训写在这:
##   我逐列数不透明像素, 看到 x53~58 每列只有 2px 就判成"细尾梁在右, 所以贴图朝左"。
##   实拍出来机头永远反着 ⇒ 把原图渲染出来一看: **圆胖座舱在右、尾梁+尾桨在左**,
##   而 x53~58 那 2px 根本不是尾梁, 是**横贯全宽的旋翼叶片**。
##   ⇒ **贴图原生朝右**。逐列统计对"哪端是什么"是不可靠的判据 —— 该看图的时候就得看图。
const HELI_NOSE_PX_X := 52.0
const HELI_NOSE_PX_Y := 36.0
const HELI_TEX_PATH := "res://assets/sprites/vfx/eq-heli-idle.png"
static var _heli_tex_cache: Texture2D = null
static var _heli_tex_tried := false

func _heli_tex() -> Texture2D:
	if not _heli_tex_tried:
		_heli_tex_tried = true
		if ResourceLoader.exists(HELI_TEX_PATH):
			_heli_tex_cache = load(HELI_TEX_PATH)
	return _heli_tex_cache


func heli_spawn(h: Dictionary) -> void:
	if not _has_world():
		return
	var root := Node3D.new()
	root.name = "GunEq_Heli"
	battle._world.add_child(root)
	_owned.append(root)
	# ★机身: 有立绘就用立绘, 没有才退回发光球。
	#   退回那条是**兜底不是设计** —— 发光球缩成 1.4×0.9 在场上读起来就是"一个灰长方形",
	#   用户 2026-08-07 原话:「瞎画个圈也算特效，长方形也能算子弹」。素材在位就一定走上面这条。
	var body: Sprite3D
	var htex: Texture2D = _heli_tex()
	if htex != null:
		body = _sprite(htex, Vector3.ZERO, (HELI_BODY_PX * float(battle.WS)) / float(htex.get_height()),
			Color(1, 1, 1, 1), false)
		body.hframes = maxi(1, htex.get_width() / maxi(1, htex.get_height()))
		# ★立绘已镜像成【机头朝右】(与 077 手枪同一约定), 所以只有右队要再翻回去。
		#   ⚠ 队伍字段是 **`owner["side"]` 的字符串 "left"/"right"** ——
		#     直升机字典自己**没有** `side` 键(它只有 `owner`)。我第一版写的
		#     `int(h.get("side", 0)) == 1` 两头都错: 取不到键、且拿字符串当整数。
		#     这种"读了个不存在的键、默认值又恰好不报错"的写法**永远静默**, 只有实拍能抓。
		var _ow = h.get("owner", null)
		if _ow is Dictionary and str(_ow.get("side", "left")) == "right":
			body.flip_h = true
	else:
		body = _sprite(VfxTex._make_fire_glow_tex(), Vector3.ZERO, 0.022,
			Color(0.85, 0.92, 1.0, 0.95), false)
		body.scale = Vector3(1.4, 0.9, 1.0)
	root.add_child(body)
	var rotor := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 0.06
	var hl := 1.05
	var quad: Array = [Vector3(-hl, 0, -hw), Vector3(hl, 0, -hw), Vector3(hl, 0, hw), Vector3(-hl, 0, hw)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(quad[idx])
	rotor.mesh = st.commit()
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rm.albedo_color = Color(0.7, 0.85, 1.0, 0.55)
	rotor.material_override = rm
	# ★有立绘时**不画**这块几何旋翼: 立绘自带旋翼模糊盘, 两个叠着就是两套旋翼,
	#   而这块在实拍里读起来就是"一根横穿机身的灰长方形"(用户 2026-08-07 点名的那个)。
	#   仍然建出来但不入树 —— heli_update 照旧积分它的相位(相位还要驱动机身帧), 只是不显示。
	if htex == null:
		root.add_child(rotor)
	# ③ 龟能条 —— 原来是两个像素方块, 又窄又暗, 读不出"这是能量条、还差多少"。
	#   现在: 深色描边框 + 深底 + 亮填充, 加宽加高; 满格时由 heli_update 让它闪。
	var en_ol := _sprite(VfxTex._make_pixel_block_tex(), Vector3(0, 0.92, 0), 0.02,
		Color(0.02, 0.03, 0.05, 0.9), false)
	en_ol.scale = Vector3(4.3, 0.78, 1.0)
	root.add_child(en_ol)
	var en_bg := _sprite(VfxTex._make_pixel_block_tex(), Vector3(0, 0.92, 0), 0.02,
		Color(0.10, 0.16, 0.22, 0.95), false)
	en_bg.scale = Vector3(4.0, 0.56, 1.0)
	root.add_child(en_bg)
	var en := _sprite(VfxTex._make_pixel_block_tex(), Vector3(0, 0.92, 0), 0.02,
		Color(0.45, 0.95, 1.0, 1.0), false)
	en.scale = Vector3(0.01, 0.5, 1.0)
	root.add_child(en)
	# ㉓ 地面投影(挂在 _world 而不是 root —— root 在 5.2 米高, 影子必须贴地)
	var shd := _sprite(VfxTex._make_fire_glow_tex(), Vector3.ZERO,
		(HELI_BODY_PX * SHADOW_K * float(battle.WS)) / 64.0, Color(0.02, 0.03, 0.05, 0.34), true)
	_owned.append(shd)
	h["_shadow"] = shd
	h["node"] = root
	h["_body_spr"] = body
	h["_rotor"] = rotor
	h["_en"] = en
	h["_body"] = body


## 每帧: 位置跟随 + 旋翼相位积分(②) + 龟能条。
func heli_update(h: Dictionary, delta: float) -> void:
	h["rotor"] = rotor_phase(float(h.get("rotor", 0.0)), ROTOR_OMEGA, delta)
	var root = h.get("node", null)
	if not (root is Node3D) or not is_instance_valid(root):
		return
	# ★★2026-08-07 用户:「直升机方向」—— 原来 `flip_h` 只在**生成时**按队伍设一次,
	#   之后**永远不转**。一架直升机倒着飞而机头始终朝一边, 一眼就假。
	#   ⇒ 按**实际移动方向**转向: **贴图原生朝右** ⇒ 往【左】飞才翻转。
	#   ⚠ 用位移而不是"目标在哪边" —— 脱离/进场时它是**背对目标飞**的, 按目标转会转反。
	#   ⚠ 死区 0.5 码/帧: 悬停时的微小抖动不该让它来回翻面(那比不转还难看)。
	var prev: Vector2 = h.get("_last_pos", Vector2(h["pos"]))
	var dx: float = float(h["pos"].x) - prev.x
	h["_last_pos"] = Vector2(h["pos"])
	var bs2 = h.get("_body_spr", null)
	if bs2 is Sprite3D and is_instance_valid(bs2) and absf(dx) > 0.5:
		(bs2 as Sprite3D).flip_h = dx < 0.0
	# 机头的**场地坐标**回填给效果层 —— 机炮从这里出膛(和 077 手枪同一套做法)
	if bs2 is Sprite3D and is_instance_valid(bs2):
		var b2: Sprite3D = bs2
		var fw2: float = float(b2.texture.get_width() / maxi(1, int(b2.hframes)))
		var nx: float = ((HELI_NOSE_PX_X + 0.5) - fw2 * 0.5) * b2.pixel_size
		if b2.flip_h:
			nx = -nx
		h["_muzzle_px"] = nx / float(battle.WS)
	_heli_shadow(h)
	# ㉒ 起手闪白: 机身在 ALERT_FLASH 秒里由亮转常, 让"它要放大招了"在机身上也读得到
	if bs2 is Sprite3D and is_instance_valid(bs2):
		var at2: float = float(h.get("_alert_t", 9.0)) + delta
		h["_alert_t"] = at2
		var kf: float = clampf(1.0 - at2 / ALERT_FLASH, 0.0, 1.0)
		(bs2 as Sprite3D).modulate = Color(1.0 + kf * 1.6, 1.0 + kf * 1.2, 1.0 + kf * 0.7, 1.0)
	# ㉔ 坠机: 机身摇摆 + 持续冒烟, 让那 10 秒之后的坠落**看得出是失控**
	if str(h.get("state", "")) == "crash":
		if bs2 is Sprite3D and is_instance_valid(bs2):
			(bs2 as Sprite3D).rotation.z = sin(float(h["rotor"]) * 0.8) * 0.35
		h["_smoke_t"] = float(h.get("_smoke_t", 0.0)) + delta
		while float(h["_smoke_t"]) >= CRASH_SMOKE_IV:
			h["_smoke_t"] = float(h["_smoke_t"]) - CRASH_SMOKE_IV
			var pf := _sprite(VfxTex._make_fire_glow_tex(),
				battle._world_pos(Vector2(h["pos"]), HELI_H * 0.85),
				(26.0 * float(battle.WS)) / 64.0, Color(0.22, 0.20, 0.19, 0.85), false)
			_adopt(pf, 0.7, "puff", {"a0": 0.85})
	root.position = battle._world_pos(Vector2(h["pos"]), HELI_H)
	var rotor = h.get("_rotor", null)
	if rotor is Node3D and is_instance_valid(rotor):
		rotor.rotation = Vector3(0.0, float(h["rotor"]), 0.0)
	# 机身立绘的帧: 用**旋翼相位**驱动(不另起时钟) —— 旋翼相位本来就是每帧积分出来的,
	# 拿它取模就天然与"旋翼在转"同步, 也不会因为暂停/变速跑掉。
	var bs = h.get("_body_spr", null)
	if bs is Sprite3D and is_instance_valid(bs) and int(bs.hframes) > 1:
		var nf: int = int(bs.hframes)
		var ph: float = fposmod(float(h["rotor"]) / TAU * HELI_FRAME_CYCLES, 1.0)
		bs.frame = clampi(int(ph * float(nf)), 0, nf - 1)
	var en = h.get("_en", null)
	if en is Sprite3D and is_instance_valid(en):
		var f: float = clampf(float(h.get("energy", 0.0)) / 100.0, 0.0, 1.0)
		en.scale = Vector3(maxf(0.01, 4.0 * f), 0.5, 1.0)
		en.position = Vector3(-4.0 * 0.02 * (1.0 - f) * 0.5, 0.92, 0.0)
		# ★满格闪 —— "可以放大招了"必须能读出来(原来只是条到头了, 没有任何变化)
		var blink: float = 1.0 if f < 0.999 else (0.55 + 0.45 * sin(float(h["rotor"]) * 3.0))
		en.modulate = Color(0.45 + 0.5 * (1.0 - blink), 0.95, 1.0, blink)


## ㉒【大招零提示】用户:「直升机释放技能会怎么样」—— 答案是**画面上什么都没发生**:
##   机身不变、无起手、无屏幕信号, 而这是一件 5 费装备的大招。
##   ⇒ 起飞轰炸的那一刻: 机身闪白脉冲 + 脚下爆一圈警示环 + 一记轻震屏。
func heli_alert(h: Dictionary) -> void:
	if not _has_world():
		return
	h["_alert_t"] = 0.0
	_ring(Vector2(h["pos"]), Color(1.0, 0.55, 0.22, 0.95), ALERT_R, ALERT_SEC)
	if battle != null and battle.has_method("_shake"):
		battle._shake(ALERT_SHAKE)


## ㉓【空中单位没有地面投影】—— 2.5D 场上读不出它在哪、多高。
## 影子跟着 2D 位置走、贴地; 大小按高度收缩(越高越小越淡, 全行业通用的高度读数)。
func _heli_shadow(h: Dictionary) -> void:
	var sh = h.get("_shadow", null)
	if not (sh is Sprite3D) or not is_instance_valid(sh):
		return
	var s2: Sprite3D = sh
	s2.position = battle._world_pos(Vector2(h["pos"]), 0.04)
	var f: float = clampf(1.0 - (HELI_H / 8.0), 0.35, 1.0)
	s2.pixel_size = (HELI_BODY_PX * SHADOW_K * f * float(battle.WS)) / 64.0
	s2.modulate.a = 0.34 * f


func heli_free(h: Dictionary) -> void:
	var root = h.get("node", null)
	if root is Node3D and is_instance_valid(root):
		_owned.erase(root)
		root.queue_free()
	h["node"] = null


## 地毯轰炸的航线预告: 800×120 的贴地带。
func lane_marker(a: Vector2, b: Vector2, width: float) -> void:
	if not _has_world():
		return
	var mi := _band(a, b, 0.05, width * 0.5, Color(1.0, 0.55, 0.25, 0.30))
	_adopt(mi, 1.8, "band", {"a0": 0.30})


## 一枚炸弹的下落弹迹: 按 ① 的自由落体 + 前置量画出来(不是垂直掉下去)。
## 返回弹着点 —— 门禁验的是这个几何量, 不用等演出跑完(CLAUDE.md §3.5)。
## 080 炸弹立绘: 显示尺寸(码)、下落演出时长(秒)、素材路径(缓存一次)。
const BOMB_PX := 22.0
## 炸弹尾迹长度(码)
const BOMB_TAIL_LEN := 46.0
## ★★2026-08-08 用户:「投弹是直升机投, 为什么我看到的是在直升机很后面的位置凭空出现」
##   探针查证: 炸弹**确实在直升机位置生成**(水平差 0~10 码)。但**机身有 160 码宽、
##   炸弹只有 22 码 ⇒ 生成那一刻整颗弹被机身完全盖住**。直升机以 500 码/秒飞走,
##   要 0.16 秒才把弹"让"出来 —— 那时它已经飞出 **80 码**, 于是看起来是
##   "弹在直升机后面凭空冒出来"。**不是凭空生成, 是从机身背后钻出来的。**
##   ⇒ 弹从**机腹**出膛: 实测机腹(不透明像素第 97 百分位, 16 帧中位 47/64)
##     在机身中心**下方 0.234 帧高 = 0.90 世界米**。从那儿出来第一帧就露在机身之外。
const BOMB_BAY_DROP := 0.90
const BOMB_FALL_SEC := 0.42
## 预警贴花在一次下落里转多少弧度(半圈)。★不是随手取的: 转太快像雷达扫描、
## 转太慢看不出在动; 半圈刚好"一眼看得出它活着"又不抢注意力。
const WARN_SPIN := PI
const WARN_TEX_PATH := "res://assets/sprites/vfx/eq-bomb-warn.png"
static var _warn_tex_cache: Texture2D = null
static var _warn_tex_tried := false

func _warn_tex() -> Texture2D:
	if not _warn_tex_tried:
		_warn_tex_tried = true
		if ResourceLoader.exists(WARN_TEX_PATH):
			_warn_tex_cache = load(WARN_TEX_PATH)
	return _warn_tex_cache
const BOMB_TEX_PATH := "res://assets/sprites/vfx/eq-bomb.png"
static var _bomb_tex_cache: Texture2D = null
static var _bomb_tex_tried := false

func _bomb_tex() -> Texture2D:
	if not _bomb_tex_tried:
		_bomb_tex_tried = true
		if ResourceLoader.exists(BOMB_TEX_PATH):
			_bomb_tex_cache = load(BOMB_TEX_PATH)
	return _bomb_tex_cache


## 一枚炸弹的**完整演出**: 落点预警圈 + 真炸弹沿抛物线落下 + 一条淡尾迹。
##
## ★★2026-08-07 这个函数被重写过, 原因写在这儿当教训:
##   v0.19.41 我做了「真炸弹立绘沿抛物线落下」并写进 CHANGELOG 说修好了 ——
##   而那个函数(`bomb_track`)**零调用者**, 炸弹**从来没在游戏里出现过**。
##   我"目视确认"看的是一个死函数。memory [[fb-verify-must-run-the-real-path]] 记的就是这条,
##   我又犯了一次。⇒ 现在它由 `_heli_bomb_run` 在**每次投弹时真的调用**。
##
## ★`land` 由**效果层传进来**(它是伤害真正结算的那个点), 本函数**不重算** ——
##   预警圈和实际伤害范围必须是同一个数, 各算一次迟早对不上, 那就是骗玩家。
func bomb_drop(from2: Vector2, land: Vector2, blast_r: float) -> void:
	if not _has_world():
		return
	# ① 落点预警贴花
	# ★★2026-08-07 用户:「橙色圈圈的半径你画的多大啊？这是180？我看到1000码的圈」——
	#   **他是对的**: `_make_thin_ring_tex()` 是 **256px**(它自己的注释写着"大范围预告圈用"),
	#   而我这里除的是 **64** ⇒ 圈被画成设计值的 **4 倍**: 本该 360 码直径, 实际 **1440 码**。
	#   ⚠ 我几十分钟前刚在**命中环**上修过一模一样的错, 却没回头查预警圈是我写的同一行。
	#   ⇒ 尺寸一律**从纹理自己的高度算**, 不再写任何字面量。
	# ★★2026-08-08 换成**真贴花素材**(`eq-bomb-warn.png`): 断续粗刻度环 + 中心靶标,
	#   中间**留空**——360 码直径能盖住 8 只龟并排, 填充式会把站在里面的单位整个糊掉。
	# ★★素材的刻度环**外缘已裁到贴图边界**(不透明包围盒 = 0..63) ⇒
	#   `sprite 宽度 = 伤害直径`, **代码里一个系数都不需要**。
	#   今晚那个"预警圈大 4 倍"、爆炸"小 35%"两个错, 根子都是"素材内容 ≠ 贴图边界、我得现推系数"
	#   —— 系数就是错误的来源, 直接从素材上消灭掉。
	# ★倒计时**不靠缩放**: 贴花缓慢自转(rotation.y, 贴地件不能碰 rotation.x)+ 越近越亮,
	#   落地那一刻由爆炸接手。尺寸自始至终 = 真实伤害直径, 一码不变 ⇒ 玩家读到的圈就是会挨炸的圈。
	var _wt: Texture2D = _warn_tex()
	if _wt != null:
		var _wps: float = (blast_r * 2.0 * float(battle.WS)) / float(maxi(1, _wt.get_height()))
		var warn := _sprite(_wt, battle._world_pos(land, 0.06), _wps, Color(1, 1, 1, 0.9), true)
		_adopt(warn, BOMB_FALL_SEC, "bombwarn", {"a0": 0.9})
	else:
		var _rt: Texture2D = VfxTex._make_thin_ring_tex()
		var _rps: float = (blast_r * 2.0 * float(battle.WS)) / float(maxi(1, _rt.get_height()))
		var w2 := _sprite(_rt, battle._world_pos(land, 0.06), _rps, Color(1.0, 0.42, 0.20, 0.85), true)
		_adopt(w2, BOMB_FALL_SEC, "bombwarn", {"a0": 0.85})
	# ② 尾迹 —— ★★2026-08-08 改成**跟着炸弹飞**。
	#   原来是把整条弧线**一次性铺完**、0.25 秒就消失: 炸弹还在天上, 它的"尾迹"已经没了,
	#   而且那条弧是静止的, 根本不是尾迹, 是"预先画好的轨迹线"。
	var _tdir: Vector2 = (land - from2).normalized() if (land - from2).length() > 0.001 else Vector2.RIGHT
	var tr := _band(from2 - _tdir * BOMB_TAIL_LEN, from2, HELI_H - BOMB_BAY_DROP, 1.6,
		Color(1.0, 0.72, 0.38, 0.5))
	_adopt(tr, BOMB_FALL_SEC, "bombtail", {"from": from2, "to": land, "a0": 0.5})
	# ③ 真炸弹: 位置由**和门禁验的前置量公式同一个** `bomb_height` 驱动
	var btex: Texture2D = _bomb_tex()
	if btex != null:
		var b := _sprite(btex, battle._world_pos(from2, HELI_H - BOMB_BAY_DROP),
			(BOMB_PX * float(battle.WS)) / float(btex.get_height()), Color(1, 1, 1, 1), false)
		_adopt(b, BOMB_FALL_SEC, "bomb", {"from": from2, "to": land, "a0": 1.0})


# ══════════════════════════════════════════════════════════════════
#  §生命周期 —— 自己推进, 不用 tween
# ══════════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		var n = f.get("node", null)
		if not (n is Node3D) or not is_instance_valid(n):
			_fx.remove_at(i)
			continue
		f["t"] = float(f["t"]) + delta
		var q: float = clampf(float(f["t"]) / maxf(0.001, float(f["life"])), 0.0, 1.0)
		match str(f.get("kind", "")):
			"ring":
				var s: Sprite3D = n
				s.pixel_size = lerpf(float(f.get("ps0", 0.0)), float(f.get("ps1", 0.0)), q)
				s.modulate.a = float(f.get("a0", 1.0)) * (1.0 - q)
			"band":
				var mat = (n as MeshInstance3D).material_override
				if mat is StandardMaterial3D:
					(mat as StandardMaterial3D).albedo_color.a = float(f.get("a0", 1.0)) * (1.0 - q)
			"puff":
				var sp: Sprite3D = n
				sp.modulate.a = float(f.get("a0", 1.0)) * (1.0 - q)
				sp.scale = Vector3.ONE * (0.6 + 0.9 * q)
			"bullet":
				var bl: Sprite3D = n
				var fa: Vector2 = f.get("from", Vector2.ZERO)
				var fb: Vector2 = f.get("to", Vector2.ZERO)
				# 高度也随行程插值 ⇒ 弹是**斜着落到身上**的, 不是平飞过去
				var _hA: float = float(f.get("h", PISTOL_MUZZLE_H_M))
				var _hB: float = float(f.get("h2", _hA))
				# ★⑬ 终点跟着目标走(目标还活着的话), 不再打到它开火那一刻站的地方
				var _tg = f.get("tgt", null)
				if _tg is Dictionary and (_tg as Dictionary).get("alive", false):
					fb = Vector2((_tg as Dictionary)["pos"])
					f["to"] = fb
				bl.position = battle._world_pos(fa.lerp(fb, q), lerpf(_hA, _hB, q))
				bl.modulate.a = float(f.get("a0", 1.0)) * (1.0 if q < 0.8 else (1.0 - q) / 0.2)
			"bullettail":
				# 弹头段 / 尾焰段都跟着弹走: 整块带**平移**(不重建网格) ⇒ 每帧零分配。
				# ★★2026-08-08 用户:「这明显是在角色的很上方啊」—— 他是对的:
				#   这两段原来**只在 2D 平面里平移, 高度从头到尾都是出膛高度**(直升机 5.2 米),
				#   一路平飞到目标头顶; 只有那个**几乎看不见的小弹头辉光**才真的降到 1.0 米。
				#   而玩家看到的"那条亮线"就是这两段 ⇒ 观感上子弹全程在角色上方飞过。
				#   ⇒ 平移量必须**带上高度插值**, 和弹头走同一条线。
				# ★两段建出来时都以**出膛点 a** 为基准(头段 a→a+dir·HEAD, 尾段 a−dir·TAIL→a),
				#   所以平移量对两段是同一个: 当前位置 − a。不需要再各自算 dir 偏移
				#   (上一版给头段传了 −dir 去补偿, 那是错的, 会让头段落后半个身位)。
				var tm: MeshInstance3D = n
				var ta: Vector2 = f.get("from", Vector2.ZERO)
				var tb: Vector2 = f.get("to", Vector2.ZERO)
				# ★⑬ 这一条也要跟目标走。**它才是玩家看到的那条亮线** ——
				#   只让那颗几乎看不见的辉光跟着跑, 观感上仍然是"打向开火那一刻的旧坐标"。
				var _ttg = f.get("tgt", null)
				if _ttg is Dictionary and (_ttg as Dictionary).get("alive", false):
					tb = Vector2((_ttg as Dictionary)["pos"])
					f["to"] = tb
				var here: Vector2 = ta.lerp(tb, q)
				var _thA: float = float(f.get("h", PISTOL_MUZZLE_H_M))
				var _thB: float = float(f.get("h2", _thA))
				tm.position = battle._world_pos(here, lerpf(_thA, _thB, q)) - battle._world_pos(ta, _thA)
				var tmat = tm.material_override
				if tmat is StandardMaterial3D:
					# ★"fade0" = 从行程的百分之几才开始淡出(默认 0 = 一出膛就开始暗)。
					#   霰弹丸传 0.75: 前四分之三全程满亮, 最后一段才收。
					#   ★★ADD 混合下 alpha 就是亮度 ⇒ 线性淡出让弹飞到一半只剩一半亮,
					#   实拍里整把霰弹是**土棕色的棍** —— 根因在这一行, 不在颜色常量
					#   (我先改了两次颜色/alpha 都没用, 量了像素才看出是淡出曲线)。
					var _f0: float = float(f.get("fade0", 0.0))
					var _fa: float = (1.0 - q) if _f0 <= 0.0 else clampf((1.0 - q) / maxf(0.001, 1.0 - _f0), 0.0, 1.0)
					(tmat as StandardMaterial3D).albedo_color.a = float(f.get("a0", 0.45)) * _fa
			"blastanim":
				# 逐帧播一遍(不循环、不倒放)。末帧停住那一小会儿由 alpha 收尾。
				var ba: Sprite3D = n
				var bn: int = int(f.get("nf", 1))
				ba.frame = clampi(int(q * float(bn)), 0, maxi(0, int(ba.hframes) * int(ba.vframes) - 1))
				# ★不再用 alpha 收尾 —— 素材末几帧画的就是"烟尘消散",
				#   从 q=0.82 起淡出等于**把美术画好的收尾盖掉**(不信任素材、再叠一层程序控制)。
			"bombwarn":
				# ★尺寸**全程不变** = 真实伤害直径(玩家读到的圈就是会挨炸的圈)。
				#   倒计时靠**自转 + 越来越亮**, 不再用缩放(那是我一直只会用的三个通道之一)。
				#   ⚠ 淡出是常见错法 —— 最关键的最后一刻反而最看不见, 所以这里是越近越亮。
				var wr: Sprite3D = n
				wr.rotation.y = q * WARN_SPIN
				wr.modulate.a = float(f.get("a0", 0.9)) * (0.5 + 0.5 * q)
			"bombtail":
				# 与炸弹**同一条落体曲线**平移 ⇒ 尾巴始终挂在弹后面
				var tm2: MeshInstance3D = n
				var ta2: Vector2 = f.get("from", Vector2.ZERO)
				var tb2: Vector2 = f.get("to", Vector2.ZERO)
				var th: float = (HELI_H - BOMB_BAY_DROP) * (bomb_height(BOMB_DROP_H, q) / BOMB_DROP_H)
				tm2.position = battle._world_pos(ta2.lerp(tb2, q), th) - battle._world_pos(ta2, HELI_H - BOMB_BAY_DROP)
				var tmat2 = tm2.material_override
				if tmat2 is StandardMaterial3D:
					(tmat2 as StandardMaterial3D).albedo_color.a = float(f.get("a0", 0.5)) * (1.0 - q * 0.5)
			"bomb":
				# ★水平匀速 + 竖直自由落体, **高度直接调 `bomb_height`** ——
				#   与门禁验的前置量公式是同一条曲线, 不另写一条缓动。
				#   (演出自己写一条 ease 就会出现"数字对、画面不对", 那种分歧最难查。)
				var bs: Sprite3D = n
				var a2: Vector2 = f.get("from", Vector2.ZERO)
				var b2: Vector2 = f.get("to", Vector2.ZERO)
				var here: Vector2 = a2.lerp(b2, q)
				# ★起算高度是**机腹**不是机身中心(见 BOMB_BAY_DROP 的长注释) ——
				#   否则第一帧会从机腹"跳回"机身中心, 又被机身盖住。
				var hh: float = (HELI_H - BOMB_BAY_DROP) * (bomb_height(BOMB_DROP_H, q) / BOMB_DROP_H)
				bs.position = battle._world_pos(here, hh)
				# ★★2026-08-08 不再提前淡出 —— 原来从 q=0.85 起收掉, **炸弹在触地前就消失了**,
				#   而"落地"本来就该是它最重要的一刻(现在爆炸也等到那一刻才播)。
				bs.modulate.a = 1.0
				# ★朝**下落方向**转: 立绘固定画成朝右下, 航线往左飞时原来是倒着落。
				#   billboard 精灵在屏幕平面内用 rotation.z 转(**不能碰 rotation.x** —— 那是贴地件的坑)。
				#   俯角由"竖直掉了多少 / 水平走了多少"算, 与落体曲线同源。
				var _dx: float = (b2 - a2).length() * float(battle.WS)
				var _dy: float = HELI_H * (bomb_height(BOMB_DROP_H, minf(1.0, q + 0.08)) - bomb_height(BOMB_DROP_H, q)) / BOMB_DROP_H
				bs.flip_h = (b2.x - a2.x) < 0.0
				bs.rotation.z = atan2(-_dy, maxf(0.001, _dx * 0.08)) * (-1.0 if bs.flip_h else 1.0)
		if q >= 1.0:
			# ★★2026-08-07 用户:「子弹打到哪里」—— 实拍确认: **什么都没有**。
			#   弹飞到目标就凭空消失, 没有任何命中反馈 ⇒ 玩家读不出"这一发打中了"。
			#   ⇒ 弹的寿命一到, 在**终点**炸一小下(火花 + 一圈极小的冲击环)。
			#   ⚠ 只对 "bullet" 做; 尾焰(bullettail)不做, 否则一发弹会闪两次。
			if str(f.get("kind", "")) == "bullet":
				# 命中火花放在**终点高度**(目标身体中段), 不是出膛高度
				_bullet_impact(f.get("to", Vector2.ZERO),
					float(f.get("h2", f.get("h", PISTOL_MUZZLE_H_M))))
			n.queue_free()
			_fx.remove_at(i)


## 撤场: 拔掉一切自己建的节点。返回拔了几个(门禁验"真的清干净了")。
func clear() -> int:
	var n := 0
	for f in _fx:
		var x = f.get("node", null)
		if x is Node3D and is_instance_valid(x):
			x.queue_free()
			n += 1
	_fx.clear()
	for o in _owned:
		if o is Node3D and is_instance_valid(o):
			o.queue_free()
			n += 1
	_owned.clear()
	_charge.clear()
	return n


## 现存节点数(门禁分母用)
func alive_count() -> int:
	var n := 0
	for f in _fx:
		var x = f.get("node", null)
		if x is Node3D and is_instance_valid(x):
			n += 1
	for o in _owned:
		if o is Node3D and is_instance_valid(o):
			n += 1
	return n
