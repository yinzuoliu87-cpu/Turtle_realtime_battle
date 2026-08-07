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
const HELI_H := 2.6
## 投弹起始高度(码) —— 与 HELI_H 是同一件事的两种单位, 这里只用于前置量公式
const BOMB_DROP_H := 220.0
## 旋翼角速度(弧度/秒)
const ROTOR_OMEGA := 26.0
## 悬链线的"松弛度": 绳长 = slack × 跨度
const BEAM_SLACK := 1.15
## 连锁电弧: 递归深度与首级偏移比例(相对跨度)
const ARC_DEPTH := 4
const ARC_ROUGH := 0.16

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
static func arc_sigma(level: int, span: float, rough: float = ARC_ROUGH) -> float:
	return span * rough * pow(2.0, -0.5 * float(maxi(0, level)))


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
func _band(a2: Vector2, b2: Vector2, h: float, half_w: float, col: Color,
		blend_add: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var dir: Vector2 = b2 - a2
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	var p: Vector2 = Vector2(-dir.y, dir.x).normalized() * half_w
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v: Array = [
		battle._world_pos(a2 + p, h), battle._world_pos(b2 + p, h),
		battle._world_pos(b2 - p, h), battle._world_pos(a2 - p, h)]
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

## 077 开火演出的四个常量(码 / 米 / 秒)。
## ★枪管尖 = 单位中心 + 朝向 × 这个距离。小手枪立绘 40px 宽、col_size 22 码
##   ⇒ 半个枪长约 11 码, 再往外挪 3 码让火焰不压在枪管上。
const PISTOL_MUZZLE_PX := 14.0
## ★26 码是实拍改小后的值: 第一版给 26 但 `_make_fire_glow_tex` 的可见辉光远大于名义半径,
##   13 倍拉近下盖住半个屏幕。按"火焰略大于枪管口径、不该盖住枪身"定 13 码。
##   ⚠ 这类"名义尺寸 ≠ 观感尺寸"只有实拍才抓得到 —— 贴图自带的软边把有效半径放大了约一倍。
const PISTOL_FLASH_PX := 13.0
const PISTOL_FLASH_H_M := 0.42
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
	# 枪口火焰: 生在枪管尖, 与弹道起点同一点。用现成的火光贴图(不新造纹理)。
	var muz: Vector2 = Vector2(p.get("pos", Vector2.ZERO)) + aim * PISTOL_MUZZLE_PX
	var f := _sprite(VfxTex._make_fire_glow_tex(),
		battle._world_pos(muz, PISTOL_FLASH_H_M),
		(PISTOL_FLASH_PX * float(battle.WS)) / 64.0,
		Color(1.0, 0.86, 0.42, 0.95), false)
	_adopt(f, PISTOL_FLASH_SEC, "pistol_flash")


func pistol_deploy(pos: Vector2) -> void:
	_ring(pos, Color(1.0, 0.82, 0.42, 0.85), 70.0, 0.4)


## 携带者阵亡 ⇒ 小手枪失去掩护(封顶 2 → 5)。红环一次, 让玩家读得出状态变了。
func pistol_uncovered(pos: Vector2) -> void:
	_ring(pos, Color(1.0, 0.35, 0.3, 0.9), 90.0, 0.5)


# ══════════════════════════════════════════════════════════════════
#  §通用: 弹迹 / 爆点
# ══════════════════════════════════════════════════════════════════

## 一条子弹弹迹。金弹时按 ⑥ 加亮加粗(亮度 = 该档真伤比例)。
func tracer(a: Vector2, b: Vector2, col: Color, gold_pct: float = 0.0) -> void:
	if not _has_world():
		return
	var g: float = gold_glow(gold_pct)
	var c := Color(col.r + (1.0 - col.r) * g, col.g + (0.9 - col.g) * g, col.b * (1.0 - 0.5 * g), 0.85)
	var mi := _band(a, b, 1.0, 3.0 + 5.0 * g, c)
	_adopt(mi, 0.16, "band", {"a0": c.a})


## 一次爆点: 扩张的贴地环 + 中心光晕。
func blast(pos: Vector2, radius: float, col: Color) -> void:
	if not _has_world():
		return
	_ring(pos, Color(col.r, col.g, col.b, 0.9), radius, 0.45)
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


## 锥形霰弹: 扇形底光 + 若干弹丸。弹丸半径按 ③ 取 r = R√u(面积均匀)。
## ★从**左管口**出膛(不是携带者中心) —— 见 BARREL_OFF 那段注释。
func cone_blast(origin: Vector2, dir: Vector2, range_px: float, half_deg: float,
		col: Color, gold_pct: float = 0.0, pellets: int = 14) -> int:
	if not _has_world():
		return 0
	var g: float = gold_glow(gold_pct)
	var rng: RandomNumberGenerator = battle._juice_rng
	var muz: Vector2 = barrel_flash(origin, dir, true)
	var n := 0
	for i in range(pellets):
		var r: float = cone_r(rng.randf(), range_px)
		var th: float = deg_to_rad(half_deg) * (rng.randf() * 2.0 - 1.0)
		var d: Vector2 = dir.rotated(th)
		var mi := _band(muz, muz + d * r, 0.9, 2.5 + 3.0 * g,
			Color(col.r, col.g + 0.15 * g, col.b, 0.55 + 0.35 * g))
		_adopt(mi, 0.14, "band", {"a0": 0.55 + 0.35 * g})
		n += 1
	_ring(muz, Color(col.r, col.g, col.b, 0.5), range_px * 0.35, 0.22)
	return n


## 右管出膛的那一束电: 从**右管口**打到首目标。返回管口位置(门禁验两管真的分开)。
## ★原来右管一发都没画"从枪口出去"这一段, 只画目标之间的连锁 ⇒ 玩家读不出是右管在响。
func eel_bolt(origin: Vector2, first: Vector2, gold_pct: float = 0.0) -> Vector2:
	var m: Vector2 = barrel_flash(origin, first - origin, false)
	chain_arc(m, first, COL_ARC, gold_pct)
	return m


## 连锁电弧: 中点位移分形(④)。端点精确落在两个目标身上。
## ★双层画法(见 COL_ARC 那段注释): 外层电紫用 **MIX**(重叠不加爆), 内层白热芯才用 ADD。
##   原来 16 段全是 ADD 的浅蓝带, 拐点一叠就成白线 —— 这正是"电弧是白的"的根因。
func chain_arc(a: Vector2, b: Vector2, _col: Color, gold_pct: float = 0.0) -> int:
	if not _has_world():
		return 0
	var g: float = gold_glow(gold_pct)
	var pts: Array = arc_points(a, b, ARC_DEPTH, battle._battle_rng)
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		# 身: 高饱和电紫的宽带, MIX ⇒ 越叠越白在结构上不可能发生
		var body := _band(p0, p1, 1.0, 6.0 + 3.0 * g,
			Color(COL_ARC.r + 0.35 * g, COL_ARC.g, COL_ARC.b, 0.92), false)
		_adopt(body, 0.18, "band", {"a0": 0.92})
		# 芯: 细白热带, ADD(只有它会发亮, 且宽度只有身的三分之一)
		var core := _band(p0, p1, 1.02, 2.4 + 1.2 * g,
			Color(COL_ARC_CORE.r, COL_ARC_CORE.g, COL_ARC_CORE.b, 1.0))
		_adopt(core, 0.16, "band", {"a0": 1.0})
	return pts.size()


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
const HELI_BODY_PX := 58.0
## 旋翼转一圈, 机身立绘播几轮。1.0 = 一圈一轮。
const HELI_FRAME_CYCLES := 1.0
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
	var en_bg := _sprite(VfxTex._make_pixel_block_tex(), Vector3(0, 0.7, 0), 0.02,
		Color(0.06, 0.1, 0.16, 0.75), false)
	en_bg.scale = Vector3(2.6, 0.42, 1.0)
	root.add_child(en_bg)
	var en := _sprite(VfxTex._make_pixel_block_tex(), Vector3(0, 0.7, 0), 0.02,
		Color(0.45, 0.95, 1.0, 0.95), false)
	en.scale = Vector3(0.01, 0.34, 1.0)
	root.add_child(en)
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
		en.scale = Vector3(maxf(0.01, 2.6 * f), 0.34, 1.0)
		en.position = Vector3(-2.6 * 0.02 * (1.0 - f) * 0.5, 0.7, 0.0)


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
func bomb_track(drop_at: Vector2, heading: Vector2, speed: float) -> Vector2:
	var land: Vector2 = drop_at + heading.normalized() * bomb_lead(speed, BOMB_DROP_H)
	if not _has_world():
		return land
	var segs := 6
	for k in range(segs):
		var f0: float = float(k) / float(segs)
		var f1: float = float(k + 1) / float(segs)
		var p0: Vector2 = drop_at.lerp(land, f0)
		var p1: Vector2 = drop_at.lerp(land, f1)
		var h0: float = HELI_H * (bomb_height(BOMB_DROP_H, f0) / BOMB_DROP_H)
		var mi := _band(p0, p1, maxf(0.08, h0), 2.5, Color(1.0, 0.7, 0.35, 0.7))
		_adopt(mi, 0.25, "band", {"a0": 0.7})
	return land


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
		if q >= 1.0:
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
