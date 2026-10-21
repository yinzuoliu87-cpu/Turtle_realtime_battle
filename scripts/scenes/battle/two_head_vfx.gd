class_name TwoHeadVfx
extends RefCounted
## 变脸龟(id two_head)技能特效 —— 2026-10-20 整套重做(方案书 docs/plans/20261007-双头龟重绘两形态.md §特效分段表)。
##
## ★素材全是本次新出的 `vfx/twohead-*.png`(PixelLab 特效工作台画的硬边像素表, 逐帧研究见
##   docs/studies/20261020-变脸龟特效逐帧.md)。规矩: 素材不复用(memory fb-no-asset-reuse-unless-told)。
## ★像素贴图一律【恒定 pixel_size + 切帧】, 不 tween 缩放(vfx_discipline A 条)。
##   pixel_size 取龟本体的同一个 texel(立绘 80 像素 = 2 米 ⇒ 0.025 米/像素), 要大只许整数倍。
## ★这些节点全在 **sim 步里** 建(调用方都在 TwoHeadSystem 的技能函数 / 弹道命中里),
##   帧推进挂 `battle._anim_fx` / `battle._follow_vfx`(游戏钟) —— 服务器逐帧直播录得到, 手机只播镜像。
## ★不碰伤害结算: 这里每个函数只建演出节点, 不读写任何战斗数值。

const DIR := "res://assets/sprites/vfx/"
## 出处键用(本文件的 gen_* 纯函数生成贴图, 录流按它让手机现生成)
const SELF := "res://scripts/scenes/battle/two_head_vfx.gd"
## 一个像素多少米 = 龟立绘的 texel(TARGET_BODY_H 2.0 米 / 立绘帧高 80)
const TEXEL := 2.0 / 80.0

## [文件, 帧数, 每秒帧数, 整数放大倍数]
const BOLT := ["twohead-psi-bolt.png", 8, 18.0, 1]          # 远程普攻·灵能弹(弹体, 朝飞行方向)
const BOLT_HIT := ["twohead-psi-hit.png", 8, 18.0, 1]       # 灵能弹命中
const ORB_GROW := ["twohead-psi-orb-grow.png", 8, 20.0, 2]  # 灵能冲击·法球胀大(出手后前 0.4 秒)
const ORB := ["twohead-psi-orb.png", 8, 16.0, 2]            # 灵能冲击·法球飞行(循环)
const BLAST := ["twohead-psi-blast.png", 12, 16.0, 2]       # 灵能冲击·爆炸(闪→壳→火球→烟→碎)
const CREST := ["twohead-mind-crest.png", 6, 30.0, 1]       # 精神干扰·精神波一道波峰
const MIND_HIT := ["twohead-mind-burst.png", 8, 18.0, 1]    # 精神干扰·命中头部(末帧空白不播)
const SWING := ["twohead-hammer-swing.png", 7, 20.0, 1]     # 近战普攻·挥锤弧
## 锤击(2026-10-21 第六版): 照 docs/plans/ref/20261021-杰斯Q逐元素研究.md(按元素整理, 不是逐帧研究) 的 E1~E9 整段重做。
##   用户对前五版:「完全不像」「你只看这个点够么」「你看到他有图形吗」⇒ 这一版按【元素】做: 每个图案是逐帧画的新素材,
##   每个发光层是加色混合 + 柔边渐变、亮度照研究文档实测曲线逐步驱动(不再拿不透明色块当光)。
##   配色: 参考的品红 / 淡紫 → 红橙 / 暗红(战士斗篷), 青 → 符文绿, 深紫星 → 深紫褐, 暖黄爆光保留。
##   素材全部是这一技能专用的新图(PixelLab 特效工作台逐帧画), 不与普攻共用(用户 10-20「不能共用啊」)。
##   [文件, 帧数, 每秒帧数, 整数放大倍数]
const QK_DUST := ["twohead-quake-dust.png", 8, 24.0, 1]        # E1 起跳点一小团灰白尘(48×37)
const QK_ARC := ["twohead-quake-arc.png", 4, 40.0, 1]          # E3 下砸锤迹: 宽桃白月牙带 + 带内红涡卷纹(176×172; 第 4 帧 = 残迹细弧)
const QK_STAR := ["twohead-quake-star.png", 6, 60.0, 1]        # E4 暗星徽记: 深紫褐 9 刺不对称星 + 4 颗符文绿水滴亮斑 + 首帧放射模糊线(136)
const QK_CRYSTAL := ["twohead-quake-crystal.png", 12, 30.0, 1] # E5~E7 能量泡: Voronoi 晶格 + 符文绿裂纹 + 亮边 + 白光刃 → 同心旋转光弧 + 绿碎晶 → 细波纹环(224)
const QK_FLARE := ["twohead-quake-flare.png", 6, 30.0, 1]      # E6 光柱落点白尖刺星芒 → E7 白螺旋烟丝(128×150)
const QK_GROUND := ["twohead-quake-ground.png", 5, 10.4, 1]    # E8 贴地碎晶格印记(与能量泡同一套格子), 格子从外往里碎掉(200)
const QK_EMBERS := ["twohead-quake-embers.png", 4, 12.0, 2]    # E9 橙金有棱角晶体火花, 闪烁、越来越少(72)
## 各图素材里的「锚点」相对帧中心的像素偏移(锚点对到节点原点 ⇒ Sprite3D.offset = (−dx, +dy))
const QK_ARC_TIP := Vector2(40.6, 124.0) - Vector2(88.0, 86.0)    # 锤迹月牙的下端(= 锤头砸到的位置)
const QK_FLARE_CORE := Vector2(64.0, 110.0) - Vector2(64.0, 75.0) # 星芒中心
const QK_DUST_FOOT := 14.5                                         # 尘团底边离帧中心(像素)
## 尺寸(米): 研究文档按目标身高(≈1.8 米)给的比例
const QK_FLASH_D := 4.0        # E5 暖黄爆光直径 ≈ 目标 2 倍(外缘柔, 看得见的那一团 ≈ 3.6 米)
const QK_GLOW_D := 5.6         # 能量泡柔光(含外晕)直径; 泡本体 = 晶格素材 188 像素 × 0.025 ≈ 4.7 米 ≈ 变脸龟身高 2.6 倍
const QK_BALL_D := 1.6         # E7 目标身上红橙光球 ≈ 目标 0.6
const QK_BEAM_H := 9.0         # E6 光柱可见长度(从天上打到目标身上)
const QK_BEAM_W := 0.56        # E6 粗光柱宽 ≈ 目标 0.3
const QK_WIND_D := 0.9         # E1 风痕每一团柔光的直径 ≈ 身宽 0.6
const QK_WIND_STEP := 0.22     # E1 风痕沿轨迹每隔多少米放一团(远小于直径 ⇒ 连成一条柔边长条)
const QK_CENTER_H := 1.0       # 星 / 泡 / 光球 / 星芒的中心离地(米) —— 打在目标身上
const QK_HAMMER_H := 2.3       # 跃起时锤头离地(米, 再加跳跃弧线的 _slam_voff)
const QK_ARC_LEAD := 6.0 / 60.0  # 锤迹在落地前多久出现(参考 #64 → 命中 #68 是 4 帧; 多给 2 帧: 主会话 1× 抽帧没看到锤迹 ⇒ 扫下的三帧各停 1.5 步)
const QK_SEC := 1.0            # 落地后整套演出时长(参考 #68 → #124 ≈ 0.93 秒)
## ★亮度曲线(时刻 = 落地后游戏秒; 参考帧号 #k = 68 + 60×t)。来源: 研究文档「亮度曲线(实测)」。
##   白热(暖黄 → 白): #70 起、#75 峰、#80 回落; 第二峰 #87 是光柱打中(11296 / 18196 = 0.62)
const QK_W := [[0.0, 0.0], [0.02, 0.45], [0.05, 0.75], [0.117, 1.0], [0.15, 0.55], [0.2, 0.25], [0.25, 0.1], [0.3, 0.0]]
##   粉光(→ 红橙泡): #78 峰 48726 = 1.0, 之后约每 0.06 秒减半(32230 / 20097 / 14033 / 8250 / 2107 / 549)
##   ★这是【品红像素数】(面积), 不是不透明度: 染色层的 alpha 取它的 0.6 次方(面积 ∝ 半径², 淡出时先缩的是外圈)
const QK_P := [[0.083, 0.0], [0.117, 0.5], [0.167, 1.0], [0.217, 0.66], [0.267, 0.41], [0.317, 0.29], [0.367, 0.17], [0.467, 0.043], [0.667, 0.011], [0.7, 0.0]]
##   光柱: #68 一根细红线已在; #82~#88 粗(内白外红); #90 起变细淡出 —— [时刻, 宽度倍数, 亮度]
const QK_BEAM_KEYS := [[0.0, 0.1, 0.0], [0.017, 0.1, 0.65], [0.2, 0.1, 0.5], [0.233, 1.0, 1.0], [0.317, 1.0, 1.0], [0.367, 0.45, 0.7], [0.467, 0.25, 0.35], [0.55, 0.15, 0.0]]
##   E7 红橙光球: #90~#96 明亮, #98 起淡
const QK_BALL := [[0.3, 0.0], [0.367, 1.0], [0.467, 1.0], [0.6, 0.0]]
##   E8 地面印记(很淡, 地面纹理清楚可见): #96 出现 → #124 淡没
const QK_GROUND_A := [[0.45, 0.0], [0.5, 0.24], [0.7, 0.2], [0.93, 0.0]]
const QK_GROUND_LIGHT := [[0.45, 0.0], [0.5, 0.22], [0.8, 0.0]]
##   200 码范围细圈: 与泡同时出现、随泡淡出
const QK_RANGE_A := [[0.1, 0.0], [0.15, 0.24], [0.35, 0.2], [0.5, 0.0]]
## 颜色(加色层的 rgb; 亮度走 alpha)
const QK_COL_WARM := Color(1.0, 0.72, 0.32)    # 暖黄
const QK_COL_HOT := Color(1.0, 0.97, 0.9)      # 白热
const QK_COL_BUBBLE := Color(1.0, 0.38, 0.22)  # 红橙泡光
const QK_COL_BUBBLE_TINT := Color(1.0, 0.36, 0.3, 0.18)    # 泡体染色(普通混合, 很淡: 只定颜色不挡目标)
const QK_COL_BUBBLE_GLOW := Color(1.0, 0.5, 0.5, 0.55)     # 泡体柔光(加色暖粉)
const QK_COL_BALL := Color(1.0, 0.45, 0.16)    # 红橙光球
const QK_COL_HAMMER := Color(1.0, 0.8, 0.5)    # 锤头暖金桃光
const QK_COL_HCORE := Color(1.0, 0.4, 0.28)    # 锤头中心红橙光球
const QK_COL_WIND := Color(0.82, 1.0, 0.9)     # 风痕淡白泛绿
const QK_COL_RANGE := Color(1.0, 0.62, 0.45)   # 范围细圈
const QK_COL_GLIGHT := Color(1.0, 0.42, 0.3)   # 地光
## 渲染层次(全部关深度测试画在单位上面, 地面那两层除外): 柔光 8 < 晶格 / 光柱 9 < 暗星 10 < 星芒 11
const QK_PRIO_GLOW := 8
const QK_PRIO_CRYSTAL := 9
const QK_PRIO_STAR := 10
const QK_PRIO_FLARE := 11
const PULL := ["twohead-siphon-pull.png", 8, 20.0, 1]       # 吸收·目标身上生命被攥出
const WISP := ["twohead-siphon-wisp.png", 6, 18.0, 1]       # 吸收·生命精魄飞回(朝飞行方向)
const SWAP := ["twohead-face-swap.png", 7, 20.0, 1]         # 变脸·斗篷甩过那一下的两色烟
const WAVE := ["twohead-fusion-wave.png", 6, 18.0, 2]       # 融合·魔法波(真实=白 / 物理=紫)

const ORB_GROW_SEC := 8.0 / 20.0     # 法球胀大段时长(= ORB_GROW 一遍)
const CHEST_H := 1.0                 # 胸口高度(米) —— 与弹道出手高度一致
const HEAD_H := 1.75                 # 头部高度(米)
const CREST_GAP := 46.0              # 精神波波峰间距(码)
const WISP_GAP := 40.0               # 生命精魄间距(码)
const WAVE_PHYS_TINT := Color(0.78, 0.55, 1.0, 1.0)   # 物理段染紫, 真实段保持白
## ★锤头落点(2026-10-20 二轮): 锤击落点在目标身前 52 码(sim 位移, 不许动), 而立绘里锤头砸在身体中线前方
##   melee_strike 第 6~8 帧锤头(石灰色)重心 x≈24.6~25.7 / 中线 64 ⇒ ≈39 像素 × 0.025 米 ÷ WS 0.024 ≈ 41 码
##   —— 目标在 52 码处, 锤头正好砸在目标身前那一截(门禁 verify_two_head_anim F② 按素材量, 不读这个常量)。
##   旧版裂地画在【施法者脚下】、挥锤只靠立绘自带那道绿弧 ⇒ 两样都被目标立绘挡住一半(目标离镜头更近时)。
##   现在: 裂地画在锤头落点; 另起一道挥锤弧收在落点上; 两者都画在两只龟【上面】(OVER_UNITS)。
## (锤头落点常量 2026-10-20 搬进 TwoHeadSystem.STRIKE_MELEE_HEAD_FWD: 改范围技后它也是伤害圆心, 归结算侧所有)
## 画在单位上面: 单位立绘是 depth_prepass_alpha(会写深度), 只抬渲染优先级挡不住深度 ⇒ 关深度测试 + 抬优先级。
const OVER_UNITS_PRIO := 8
## ★通用护盾罩【退后一层】(只给变脸龟自己那三次给盾): 切近战送盾 / 锤击落地按伤害给盾 / 切近战强化普攻给盾,
##   三次都正好落在变脸龟自己的招牌帧上(变脸挡脸 / 砸地 / 挥锤), 0.3 秒满亮的叠加罩把两只龟连同特效一起洗白。
##   罩本身是全游戏 45 个给盾点共用的、用户 09-11 拍板过的统一语言(叠加混合、实心半透) ⇒ 不改原语,
##   只把这三次的罩排到龟立绘【之前】画: 龟立绘盖住罩心, 罩只在身体四周露出一圈光 —— 仍读得出"拿到盾了"。
const SHELL_BEHIND_PRIO := -1

var battle
var _tex := {}


func _init(b) -> void:
	battle = b


func _t(spec: Array) -> Texture2D:
	var p: String = DIR + str(spec[0])
	if not _tex.has(p):
		_tex[p] = load(p) if ResourceLoader.exists(p) else null
	return _tex[p]


## 建一张帧表精灵(未挂树)。texel 恒定, 只切帧。
func sprite(spec: Array, billboard: bool = true) -> Sprite3D:
	var tex := _t(spec)
	if tex == null:
		return null
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.hframes = int(spec[4]) if spec.size() > 5 else int(spec[1])
	sp.vframes = int(spec[5]) if spec.size() > 5 else 1
	sp.frame = 0
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	sp.shaded = false
	sp.transparent = true
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.pixel_size = TEXEL * float(spec[3])
	return sp


## 原地播一遍(游戏钟切帧, 放完自销)。
func _once(spec: Array, at2d: Vector2, h: float, flip: bool = false, n_override: int = 0) -> Sprite3D:
	if battle._world == null:
		return null
	var sp := sprite(spec)
	if sp == null:
		return null
	sp.flip_h = flip
	sp.render_priority = 6
	sp.position = battle._world_pos(at2d, h)
	battle._world.add_child(sp)
	battle._anim_fx.append({"spr": sp, "t0": battle._t, "fps": float(spec[2]), "n": n_override if n_override > 0 else int(spec[1])})
	return sp


## 跟着单位播一遍(目标被击飞也跟着走)。
func _once_on(spec: Array, u: Dictionary, h: float, n_override: int = 0) -> void:
	if battle._world == null:
		return
	var sp := sprite(spec)
	if sp == null:
		return
	sp.render_priority = 6
	sp.position = battle._world_pos(u["pos"], float(u.get("height", 0.0)) + h)
	battle._world.add_child(sp)
	battle._follow_vfx.append({"spr": sp, "unit": u, "h": h, "anim_fps": float(spec[2]), "anim_n": n_override if n_override > 0 else int(spec[1]), "anim_t0": battle._t})


# ═══════════════════════════════════════════════════════════════════
#  远程普攻·灵能弹
# ═══════════════════════════════════════════════════════════════════
## 弹体贴图交给 battle_ballistics._fire_bolt_from(定向: 弹头朝前)。命中时由弹道调这里。
func bolt_hit(tgt: Dictionary) -> void:
	_once_on(BOLT_HIT, tgt, CHEST_H)


# ═══════════════════════════════════════════════════════════════════
#  近战普攻·挥锤
# ═══════════════════════════════════════════════════════════════════
## 挥锤弧画在【施法者与目标之间】: 素材是朝左挥(项目约定原图朝左), 目标在右就镜像。
func hammer_swing(u: Dictionary, tgt: Dictionary) -> void:
	var d: Vector2 = tgt["pos"] - u["pos"]
	var mid: Vector2 = u["pos"] + d * 0.6
	over_units(_once(SWING, mid, CHEST_H, d.x > 0.0))       # 挥锤弧就落在目标身上 ⇒ 画在目标上面(否则离镜头近的目标挡一半)


## 把一张特效精灵排到所有单位立绘上面(见 OVER_UNITS_PRIO)。
func over_units(sp) -> void:
	if sp is Sprite3D:
		(sp as Sprite3D).no_depth_test = true
		(sp as Sprite3D).render_priority = OVER_UNITS_PRIO


# ═══════════════════════════════════════════════════════════════════
#  灵能冲击: 法球胀大推出 → 飞行 → 爆炸
# ═══════════════════════════════════════════════════════════════════
## 法球节点: 出手时是胀大表的第 0 帧, 由 `orb_step` 按【已飞行时间】切帧(sim 步里推)。
func orb_new(from2d: Vector2) -> Sprite3D:
	var sp := sprite(ORB_GROW)
	if sp == null or battle._world == null:
		return null
	sp.render_priority = 6
	sp.position = battle._world_pos(from2d, CHEST_H)
	battle._world.add_child(sp)
	return sp


## `fly_t` = 出手后已飞行的游戏秒。前 ORB_GROW_SEC 播胀大表, 之后换飞行循环表。
func orb_step(sp, fly_t: float) -> void:
	if not is_instance_valid(sp):
		return
	if fly_t < ORB_GROW_SEC:
		sp.frame = clampi(int(fly_t * float(ORB_GROW[2])), 0, int(ORB_GROW[1]) - 1)
		return
	var lt := _t(ORB)
	if lt != null and sp.texture != lt:
		sp.frame = 0
		sp.texture = lt
		sp.hframes = int(ORB[1])
	sp.frame = int((fly_t - ORB_GROW_SEC) * float(ORB[2])) % int(ORB[1])


func orb_blast(at2d: Vector2) -> void:
	_once(BLAST, at2d, CHEST_H)


# ═══════════════════════════════════════════════════════════════════
#  精神干扰: 符文眼放出精神波 → 命中头部
# ═══════════════════════════════════════════════════════════════════
## 伤害是施放那一刻结算的 ⇒ 波不许"飞过去再到", 整条波同一刻出现、从施法者往目标依次亮起
## (相邻两道相差 1 帧 = 1/30 秒, 整条 ≤ 0.3 秒播完)。
func mind_wave(u: Dictionary, tgt: Dictionary) -> void:
	var a: Vector2 = u["pos"]
	var b: Vector2 = tgt["pos"]
	var d: Vector2 = b - a
	var L: float = DetMath.vlen(d)
	var n: int = clampi(int(L / CREST_GAP), 2, 9)
	var flip: bool = d.x < 0.0          # 波峰素材朝右 ")" ; 目标在左就镜像
	for i in range(n):
		var f: float = float(i + 1) / float(n + 1)
		var sp := _once(CREST, a + d * f, DetMath.flerp(HEAD_H, HEAD_H - 0.25, f), flip)
		if sp != null:
			battle._anim_fx[battle._anim_fx.size() - 1]["t0"] = battle._t + float(i) / float(CREST[2])
	_once_on(MIND_HIT, tgt, HEAD_H, 8)


# ═══════════════════════════════════════════════════════════════════
#  锤击(第六版): 起跳风痕 / 锤头光 / 锤迹 → 暗星徽记 + 暖黄爆光 → 晶格能量泡 → 旋涡光弧 + 光柱 + 星芒
#               → 细波纹环 + 红橙光球 → 地面碎晶印记 + 余火晶体; 另有一道淡细圈标 200 码判定范围
# ═══════════════════════════════════════════════════════════════════
## ★驱动: 每段演出一张「演出表」(st), 表里每个节点一条记录(出现 / 消失时刻、切帧、亮度曲线、宽度曲线)。
##   推进挂一条 sim tween(battle._reg_tween, 按 sim 步喂), 但【时刻读游戏钟 battle._t】—— 顿帧期间游戏钟停, 演出也停,
##   与结算同一条钟(memory fb-second-clock-drops-events)。节点全在 sim 步里建、属性在 sim 步里改 ⇒ 逐帧直播录得到。
## ★不碰伤害结算: 只建演出节点、只读 sim 状态。

## 分段线性取值: keys = [[时刻, 值], …](时刻升序)。
static func curve(keys: Array, t: float) -> float:
	if keys.is_empty():
		return 0.0
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		var k1: Array = keys[i]
		if t <= float(k1[0]):
			var k0: Array = keys[i - 1]
			var span: float = maxf(1e-6, float(k1[0]) - float(k0[0]))
			return lerpf(float(k0[1]), float(k1[1]), (t - float(k0[0])) / span)
	return float(keys[keys.size() - 1][1])


## 曲线逐点取幂(面积 → 不透明度)。
static func _pow_keys(keys: Array, e: float) -> Array:
	var out: Array = []
	for k in keys:
		out.append([k[0], pow(float(k[1]), e)])
	return out


static func _col_curve(keys: Array, t: float) -> Color:
	if t <= float(keys[0][0]):
		return keys[0][1]
	for i in range(1, keys.size()):
		if t <= float(keys[i][0]):
			var span: float = maxf(1e-6, float(keys[i][0]) - float(keys[i - 1][0]))
			return (keys[i - 1][1] as Color).lerp(keys[i][1], (t - float(keys[i - 1][0])) / span)
	return keys[keys.size() - 1][1]


## 柔边径向渐变(加色层用): 白色, alpha = 中心亮、边缘柔; `rim` > 0 时在 0.82 半径处多一圈亮边(能量泡「边缘一圈最亮」), 外面一层淡晕。
## ★出处键: 纯函数(只看参数), 生成后挂 stream_gen ⇒ 逐帧直播的手机按同名同参现生成(StreamMirror.gen_ok 认 gen_ 前缀)。
static var _glow_cache := {}
static func gen_quake_glow(size: int, rim: float) -> ImageTexture:
	var key := "%d:%.3f" % [size, rim]
	if _glow_cache.has(key):
		return _glow_cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (float(size) - 1.0) * 0.5
	for y in range(size):
		for x in range(size):
			var d: float = Vector2(float(x) - c, float(y) - c).length() / (c + 0.5)
			## 平顶柔边(1 − d²)^1.5: 半径一半处仍有 0.65 —— 第一版用 (1 − d)^1.8 只剩中心一个小亮点, 又被暗星盖住, 实拍看不见爆光
			var core: float = pow(clampf(1.0 - d * d, 0.0, 1.0), 1.5)
			var ring: float = maxf(rim, 0.0) * exp(-pow((d - 0.82) / 0.075, 2.0))
			var halo: float = maxf(rim, 0.0) * 0.35 * clampf(1.0 - absf(d - 0.9) / 0.1, 0.0, 1.0)
			var a: float = clampf(core * (1.0 - rim * 0.55) + ring + halo, 0.0, 1.0)
			if rim < 0.0:
				a = smoothstep(1.0, 0.45, d)            # rim < 0: 平顶实心团、只有外缘一圈柔(爆光的体积层)
			if d >= 1.0:
				a = 0.0
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	VfxTex.tag(tex, "gen_quake_glow", [size, rim], SELF)
	_glow_cache[key] = tex
	return tex


## E6 光柱: 竖条, 横向「内核白、外缘红」(颜色烤在贴图里), 纵向顶端淡出(从天而降)。亮度由节点 modulate.a 给。
static var _beam_cache: ImageTexture = null
static func gen_quake_beam() -> ImageTexture:
	if _beam_cache != null:
		return _beam_cache
	var w := 16
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var red := Color(1.0, 0.16, 0.12)
	for y in range(h):
		var fy: float = float(y) / float(h - 1)          # 0 = 顶(天上), 1 = 底(打中处)
		var va: float = clampf(fy / 0.55, 0.0, 1.0)
		for x in range(w):
			var fx: float = absf((float(x) + 0.5) / float(w) * 2.0 - 1.0)   # 0 = 中线, 1 = 边
			var core: float = clampf(1.0 - fx / 0.38, 0.0, 1.0)
			var col: Color = red.lerp(Color(1.0, 0.97, 0.92), core)
			var a: float = clampf(1.0 - pow(fx, 2.2), 0.0, 1.0) * va
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	_beam_cache = ImageTexture.create_from_image(img)
	VfxTex.tag(_beam_cache, "gen_quake_beam", [], SELF)
	return _beam_cache


## 200 码判定范围的淡细圈(贴地): 一道柔边细线, 半径 = 贴图半边宽的 RANGE_RING_R 倍(节点 pixel_size 按判定半径反算)。
const RANGE_RING_R := 0.94
static var _ring_cache: ImageTexture = null
static func gen_quake_range_ring() -> ImageTexture:
	if _ring_cache != null:
		return _ring_cache
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (float(n) - 1.0) * 0.5
	for y in range(n):
		for x in range(n):
			var d: float = Vector2(float(x) - c, float(y) - c).length() / (c + 0.5)
			var a: float = exp(-pow((d - RANGE_RING_R) / 0.012, 2.0))
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a if a > 0.01 else 0.0))
	_ring_cache = ImageTexture.create_from_image(img)
	VfxTex.tag(_ring_cache, "gen_quake_range_ring", [], SELF)
	return _ring_cache


## 加色材质(柔光 / 光柱 / 晶格 / 星芒): Sprite3D 自己没有 blend_mode, 只能整个换材质 ——
##   于是 billboard / 过滤 / 深度 / 优先级都要在材质上再设一遍; 颜色走顶点色(= Sprite3D.modulate, 录流跟踪它)。
var _add_mats := {}
func _add_mat(tex: Texture2D, prio: int, flat: bool, keep_scale: bool = false, nearest: bool = false, add: bool = true) -> StandardMaterial3D:
	var key := "%d:%d:%s:%s:%s:%s" % [tex.get_instance_id(), prio, str(flat), str(keep_scale), str(nearest), str(add)]
	if _add_mats.has(key):
		return _add_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if nearest else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.render_priority = prio
	if flat:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	else:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = keep_scale
		m.no_depth_test = true
	_add_mats[key] = m
	return m


## 一块加色柔光(程序渐变贴图): 直径 `d` 米, 初始藏起来(到点才露)。
func _glow_node(d: float, rim: float, prio: int, flat: bool = false, add: bool = true) -> Sprite3D:
	var tex := gen_quake_glow(128 if rim > 0.0 else 64, rim)
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.shaded = false
	sp.transparent = true
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED if flat else BaseMaterial3D.BILLBOARD_ENABLED
	if flat:
		sp.axis = Vector3.AXIS_Y
	sp.pixel_size = d / float(tex.get_width())
	sp.material_override = _add_mat(tex, prio, flat, false, false, add)
	sp.modulate = Color(1, 1, 1, 0)
	sp.visible = false
	return sp


## 一张逐帧像素表(恒定 texel, 只切帧)。`additive` = 走加色材质(晶格 / 星芒是发光体); `over` = 画在单位上面。
func _sheet_node(spec: Array, prio: int, additive: bool, over: bool = true) -> Sprite3D:
	var sp := sprite(spec)
	if sp == null:
		return null
	if additive:
		sp.material_override = _add_mat(sp.texture, prio, false, false, true)
	elif over:
		sp.no_depth_test = true
		sp.render_priority = prio
	sp.visible = false
	return sp


## 往演出表里登记一个节点。键: at / end = 出现 / 消失时刻(相对 st.t0 的游戏秒); fps / n = 切帧(播完停在末帧);
##   a = 亮度曲线(按 st 时刻, 乘到 col.a 上); cols = 颜色曲线 [[时刻, Color], …]; w = 宽度曲线(写 scale.x, 光柱用)。
func _reg(st: Dictionary, sp: Sprite3D, at2d: Vector2, h: float, e: Dictionary) -> void:
	if sp == null or battle._world == null:
		return
	sp.position = battle._world_pos(at2d, h)
	if e.has("name"):
		sp.name = "quake_%s_%d" % [str(e["name"]), (st["fx"] as Array).size()]   # 门禁 / 自审按名字找节点(程序贴图没有 resource_path); 带序号免得同名被引擎改名
	battle._world.add_child(sp)
	e["spr"] = sp
	(st["fx"] as Array).append(e)


func _drive(_v: float, st: Dictionary) -> void:
	_drive_at(st, float(battle._t) - float(st["t0"]))


func _drive_at(st: Dictionary, t: float) -> void:
	for e in st["fx"]:
		var sp = e["spr"]
		if not is_instance_valid(sp):
			continue
		var at: float = float(e.get("at", 0.0))
		var on: bool = t >= at and t < float(e.get("end", 99.0))
		if sp.visible != on:
			sp.visible = on
		if not on:
			continue
		var n: int = int(e.get("n", 1))
		if n > 1:
			var fr: int = clampi(int((t - at) * float(e["fps"])), 0, n - 1)
			if sp.frame != fr:
				sp.frame = fr
		var col: Color = e.get("col", Color.WHITE)
		if e.has("cols"):
			col = _col_curve(e["cols"], t)
		if e.has("a"):
			var m := Color(col.r, col.g, col.b, col.a * curve(e["a"], t))
			if sp.modulate != m:
				sp.modulate = m
		if e.has("w"):
			var sc := Vector3(curve(e["w"], t), 1.0, 1.0)
			if sp.scale != sc:
				sp.scale = sc


func _free_st(st: Dictionary) -> void:
	for e in st["fx"]:
		if is_instance_valid(e["spr"]):
			e["spr"].queue_free()
	(st["fx"] as Array).clear()


## 起跳 / 空中(由 TwoHeadSystem._two_head_hammer_arc 在 sim 步里每步调, pf = 跳跃进度 0~1)。
##   E1: 起跳点一团灰白尘; 上升段沿身体轨迹一路放柔光团(加色、淡白泛绿、各自 0.16 秒淡掉 ⇒ 连成往下越淡的风痕长条)。
##   E2: 锤头暖金桃光 + 中心红橙光球, 跟着锤头走(参考 #58~#62 最明显)。
##   E3: 落地前 QK_ARC_LEAD 秒出下砸锤迹(另起一张演出表: 落地后残迹还要在泡上方淡出)。
##   状态按单位存(is_same 找, 不拿单位字典当键)。
var _leaps: Array = []

func leap_step(u: Dictionary, pf: float, land2d: Vector2) -> void:
	if battle._world == null:
		return
	var st = null
	for e in _leaps:
		if is_same(e["u"], u):
			st = e
	var voff: Vector3 = u.get("_slam_voff", Vector3.ZERO)
	var h_body: float = QK_CENTER_H + voff.y
	if st == null:
		st = {"u": u, "t0": float(battle._t), "fx": [], "arc": false, "wp": u["pos"], "wh": h_body}
		_leaps.append(st)
		var ds := _sheet_node(QK_DUST, 6, false, false)
		if ds != null:
			ds.offset = Vector2(0.0, QK_DUST_FOOT)
			_reg(st, ds, u["pos"], 0.0, {"at": 0.0, "end": 8.0 / 24.0, "fps": 24.0, "n": 8, "name": "dust"})
		_reg(st, _glow_node(1.7, 0.0, QK_PRIO_GLOW), u["pos"], 0.0, {"col": QK_COL_HAMMER,
			"a": [[0.0, 0.3], [0.15, 0.6], [0.3, 0.85], [0.36, 0.0]], "hammer": true, "name": "hammer_glow"})
		_reg(st, _glow_node(0.6, 0.0, QK_PRIO_GLOW), u["pos"], 0.0, {"col": QK_COL_HCORE,
			"a": [[0.0, 0.0], [0.18, 0.6], [0.3, 1.0], [0.36, 0.0]], "hammer": true, "name": "hammer_core"})
	var t: float = float(battle._t) - float(st["t0"])
	## E1 风痕: 只在上升段(参考 #48~#56), 按「上一位置 → 当前位置」等距插值放, 与每步跑多远无关
	if pf <= 0.4:
		var p0: Vector2 = st["wp"]
		var h0: float = float(st["wh"])
		var seg: float = Vector2(DetMath.vlen(u["pos"] - p0) * battle.WS, h_body - h0).length()
		var n: int = clampi(int(floor(seg / QK_WIND_STEP)), 0, 16)
		for q in range(1, n + 1):
			var f: float = float(q) / float(n)
			_reg(st, _glow_node(QK_WIND_D, 0.0, QK_PRIO_GLOW), p0.lerp(u["pos"], f), lerpf(h0, h_body, f),
				{"at": t, "end": t + 0.16, "col": QK_COL_WIND, "a": [[t, 0.32], [t + 0.05, 0.24], [t + 0.16, 0.0]], "wind": true, "name": "wind"})
		if n > 0:
			st["wp"] = u["pos"]
			st["wh"] = h_body
	for e in st["fx"]:
		if e.get("hammer", false) and is_instance_valid(e["spr"]):
			## 位置跟立绘同一个原点(脚底 + 跳跃偏移), 高度走公告板自己的 offset —— 立绘是公告板, 锤头的「2.3 米」是沿公告板竖直方向量的;
			##   写成世界 y 会被镜头俯角压扁(实拍第一版: 光挂在肩膀上而不是锤头上)
			var hs: Sprite3D = e["spr"]
			hs.position = battle._world_pos(u["pos"], battle.GROUND_LIFT) + voff
			hs.offset = Vector2(0.0, QK_HAMMER_H / hs.pixel_size)
	_drive_at(st, t)
	## E3 下砸锤迹: 素材朝左挥(项目约定), 立绘朝右就镜像; 月牙下端对到锤头落点
	if not bool(st["arc"]) and pf >= 1.0 - QK_ARC_LEAD / TwoHeadSystem.HAMMER_LEAP_SEC:
		st["arc"] = true
		var fr := bool(u.get("face_right", true))
		var hit: Vector2 = TwoHeadSystem.hammer_point(land2d, fr)
		var arc_st := {"t0": float(battle._t), "fx": []}
		var a := _sheet_node(QK_ARC, OVER_UNITS_PRIO, false)
		if a != null:
			a.flip_h = fr
			a.offset = Vector2(QK_ARC_TIP.x if fr else -QK_ARC_TIP.x, QK_ARC_TIP.y)
			## 0~2 帧 40 fps 扫下(#64~#66), 末帧是残迹细弧, 停住在泡上方淡出(#70~#80)
			_reg(arc_st, a, hit, 0.15, {"at": 0.0, "end": 0.32, "fps": 40.0, "n": 4, "col": Color(1, 1, 1, 1),
				"a": [[0.0, 1.0], [0.1, 1.0], [0.32, 0.0]], "name": "arc"})
		_drive_at(arc_st, 0.0)
		var tw = battle._reg_tween()
		tw.tween_method(_drive.bind(arc_st), 0.0, 1.0, 0.5)
		tw.tween_callback(_free_st.bind(arc_st))


## 落地那一步: 收掉这只龟的跳跃演出(尘 / 风痕 / 锤头光)。
func leap_end(u: Dictionary) -> void:
	for k in range(_leaps.size() - 1, -1, -1):
		if is_same(_leaps[k]["u"], u):
			_free_st(_leaps[k])
			_leaps.remove_at(k)


## `at2d` = 施法者落点(sim), `face_right` = 立绘朝向(sim 字段) ⇒ 锤头落点 = TwoHeadSystem.hammer_point(结算圆心同一点)。
## 落地那一步建好整套节点(到点才露), 之后由 sim tween 逐步按游戏钟推进。时刻表见研究文档「总节奏」与 QK_* 曲线。
func hammer_slam(at2d: Vector2, face_right: bool) -> Vector2:
	var hit: Vector2 = TwoHeadSystem.hammer_point(at2d, face_right)
	if battle._world == null:
		return hit
	var R: float = TwoHeadSystem.STRIKE_MELEE_RADIUS
	var st := {"t0": float(battle._t), "fx": [], "hit": hit}
	## E5 暖黄爆光(星后鼓起来, 黄 → 白热 → 转红橙): 白热第一峰 #75。
	##   两层: 下面一层普通混合的暖黄团(定颜色、定体积 —— 只靠加色, 绿地上只剩一点发亮, 第二版实拍看不出有一团光), 上面一层加色(定亮度)
	##   实体层在白热峰(#75)之后比加色层退得快: 泡段(#76 起)目标要透得出来, 剩下的亮由加色层给
	_reg(st, _glow_node(QK_FLASH_D, -1.0, QK_PRIO_GLOW - 1, false, false), hit, QK_CENTER_H, {"at": 0.02, "end": 0.32,
		"a": [[0.0, 0.0], [0.02, 0.45], [0.05, 0.75], [0.117, 1.0], [0.14, 0.35], [0.2, 0.1], [0.25, 0.0]],
		"cols": [[0.03, Color(QK_COL_WARM.r, QK_COL_WARM.g, QK_COL_WARM.b, 0.85)], [0.117, Color(1.0, 0.92, 0.7, 0.9)], [0.2, Color(QK_COL_BUBBLE.r, QK_COL_BUBBLE.g, QK_COL_BUBBLE.b, 0.6)]], "name": "flash_body"})
	_reg(st, _glow_node(QK_FLASH_D * 0.6, 0.0, QK_PRIO_GLOW), hit, QK_CENTER_H, {"at": 0.02, "end": 0.32, "a": QK_W,
		"cols": [[0.03, QK_COL_WARM], [0.117, QK_COL_HOT], [0.2, QK_COL_BUBBLE]], "name": "flash"})
	## E5 能量泡: 一层加色柔光(暖粉, 亮边 + 外晕) 定「发光」+ 一层很淡的普通混合红橙染色 定「颜色」(≤0.2, 目标透得出来)。
	##   亮度走粉光曲线(#78 峰, 每 0.06 秒减半); 粉光是面积(像素数)不是不透明度 ⇒ 取 0.6 次方。
	##   ★第六版初稿用 0.62 的实心红橙染色当泡体 —— 主会话自审:「像一颗橙色陶砖球, 目标龟几乎完全被盖住」。参考 #77/#80 泡是半透明发光的。
	_reg(st, _glow_node(QK_GLOW_D, 0.85, QK_PRIO_GLOW), hit, QK_CENTER_H, {"at": 0.08, "end": 0.7, "a": _pow_keys(QK_P, 0.6),
		"col": QK_COL_BUBBLE_GLOW, "name": "bubble_glow"})
	_reg(st, _glow_node(QK_GLOW_D, 0.85, QK_PRIO_GLOW - 1, false, false), hit, QK_CENTER_H, {"at": 0.08, "end": 0.7, "a": _pow_keys(QK_P, 0.6),
		"col": QK_COL_BUBBLE_TINT, "name": "bubble_tint"})
	## E5~E7 晶格泡素材: #74 起 12 帧 30 fps(晶格 → 旋涡光弧 → 细波纹环); 图案亮度跟粉光走, 但留底(否则图案先于结构消失)
	##   ★加色; 素材本身「格面暗暖粉、格边亮橙细线」(参考: 晶格只是格边 + 很淡的格面) ⇒ 格面只加一层淡暖粉、格边发亮, 目标透得出来。
	var cr := _sheet_node(QK_CRYSTAL, QK_PRIO_CRYSTAL, true)
	if cr != null:
		_reg(st, cr, hit, QK_CENTER_H, {"at": 0.1, "end": 0.5, "fps": 30.0, "n": 12, "col": Color(1, 1, 1, 1),
			"a": [[0.1, 0.5], [0.167, 0.78], [0.217, 0.7], [0.267, 0.65], [0.367, 0.8], [0.45, 0.6], [0.5, 0.2]], "name": "crystal"})
	## E4 暗星徽记: 命中那一步就在(#68), 6 帧 60 fps, 溶进白热光团(#74)
	var sr := _sheet_node(QK_STAR, QK_PRIO_STAR, false)
	if sr != null:
		sr.flip_h = face_right
		_reg(st, sr, hit, QK_CENTER_H, {"at": 0.0, "end": 0.1, "fps": 60.0, "n": 6, "name": "star"})
	## E6 光柱: 从天打到目标身上(底端在 QK_CENTER_H), #68 细红线 → #82~#88 粗 → 变细淡出
	var bm := Sprite3D.new()
	var btex := gen_quake_beam()
	bm.texture = btex
	bm.shaded = false
	bm.transparent = true
	bm.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bm.pixel_size = QK_BEAM_H / float(btex.get_height())
	bm.offset = Vector2(0.0, float(btex.get_height()) * 0.5)
	bm.material_override = _add_mat(btex, QK_PRIO_CRYSTAL, false, true)
	bm.modulate = Color(1, 1, 1, 0)
	bm.visible = false
	var bw: Array = []
	var ba: Array = []
	for k in QK_BEAM_KEYS:
		bw.append([k[0], float(k[1]) * QK_BEAM_W / (float(btex.get_width()) * bm.pixel_size)])
		ba.append([k[0], k[2]])
	_reg(st, bm, hit, QK_CENTER_H, {"at": 0.0, "end": 0.55, "a": ba, "w": bw, "name": "beam"})
	## E6 落点白尖刺星芒(#86~#88) → E7 白螺旋烟丝(#90~#94)
	var fl := _sheet_node(QK_FLARE, QK_PRIO_FLARE, true)
	if fl != null:
		fl.offset = Vector2(-QK_FLARE_CORE.x, QK_FLARE_CORE.y)
		_reg(st, fl, hit, QK_CENTER_H, {"at": 0.3, "end": 0.5, "fps": 30.0, "n": 6, "col": Color(1, 1, 1, 1),
			"a": [[0.3, 1.0], [0.36, 0.9], [0.5, 0.5]], "name": "flare"})
	## E7 目标身上红橙光球(#90~#96 亮, #98 起淡): 普通混合定颜色(加色叠在青色的龟身上会变白) + 一颗小加色亮核
	_reg(st, _glow_node(QK_BALL_D, 0.0, QK_PRIO_FLARE, false, false), hit, QK_CENTER_H, {"at": 0.3, "end": 0.6, "a": QK_BALL, "col": Color(QK_COL_BALL.r, QK_COL_BALL.g, QK_COL_BALL.b, 0.9), "name": "ball"})
	_reg(st, _glow_node(QK_BALL_D * 0.5, 0.0, QK_PRIO_FLARE + 1), hit, QK_CENTER_H, {"at": 0.3, "end": 0.6, "a": QK_BALL, "col": Color(1.0, 0.8, 0.5, 0.7), "name": "ball_core"})
	## 200 码判定范围淡细圈(贴地): 半径读 STRIKE_MELEE_RADIUS ⇒ 判定 = 显示; 与泡同时出现、随泡淡出
	var rg := Sprite3D.new()
	var rtex := gen_quake_range_ring()
	rg.texture = rtex
	rg.shaded = false
	rg.transparent = true
	rg.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	rg.axis = Vector3.AXIS_Y
	rg.pixel_size = R * battle.WS / (float(rtex.get_width()) * 0.5 * RANGE_RING_R)
	rg.material_override = _add_mat(rtex, 5, true)
	rg.modulate = Color(1, 1, 1, 0)
	rg.visible = false
	_reg(st, rg, hit, 0.04, {"at": 0.1, "end": 0.5, "a": QK_RANGE_A, "col": QK_COL_RANGE, "name": "range"})
	## E8 地面碎晶格印记(贴地、很淡, 格子从外往里碎) + 中间淡地光
	var gd := _sheet_node(QK_GROUND, 5, false, false)
	if gd != null:
		gd.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		gd.axis = Vector3.AXIS_Y
		gd.render_priority = 5
		_reg(st, gd, hit, 0.03, {"at": 0.45, "end": 0.93, "fps": 5.0 / 0.48, "n": 5, "col": Color(1, 1, 1, 1), "a": QK_GROUND_A, "name": "ground"})
	_reg(st, _glow_node(QK_GLOW_D * 0.7, 0.0, 5, true), hit, 0.035, {"at": 0.45, "end": 0.8, "a": QK_GROUND_LIGHT, "col": QK_COL_GLIGHT, "name": "ground_light"})
	## E9 余火晶体火花(#104~#124)
	var em := _sheet_node(QK_EMBERS, QK_PRIO_STAR, false)
	if em != null:
		_reg(st, em, hit, 0.7, {"at": 0.6, "end": 0.93, "fps": 12.0, "n": 4, "name": "embers"})
	_drive_at(st, 0.0)
	var tw = battle._reg_tween()
	tw.tween_method(_drive.bind(st), 0.0, 1.0, QK_SEC + 0.3)     # +0.3: 顿帧期间游戏钟停而 tween 照走, 留够余量
	tw.tween_callback(_free_st.bind(st))
	return hit


## 刚由 `_grant_shield` 给这只龟建的通用护盾罩(同一步、同一单位、贴图是 BattleVfx.SHELL_TEX)排到立绘之前画。
## 返回改了几个(门禁用)。罩的材质是 shield_shell 每次新建的, 改它的优先级不影响别的单位。
func shell_behind(u: Dictionary) -> int:
	var n := 0
	for e in battle._follow_vfx:
		if not is_same(e.get("unit", null), u) or absf(float(e.get("anim_t0", -1.0)) - float(battle._t)) > 1e-6:
			continue
		var s = e.get("spr", null)
		if not is_instance_valid(s) or not (s is Sprite3D) or (s as Sprite3D).texture == null:
			continue
		if (s as Sprite3D).texture.resource_path != BattleVfx.SHELL_TEX:
			continue
		var m = (s as Sprite3D).material_override
		if m is BaseMaterial3D:
			(m as BaseMaterial3D).render_priority = SHELL_BEHIND_PRIO
			n += 1
	return n


# ═══════════════════════════════════════════════════════════════════
#  吸收: 攥出生命 → 精魄飞回
# ═══════════════════════════════════════════════════════════════════
func siphon(u: Dictionary, tgt: Dictionary) -> void:
	_once_on(PULL, tgt, CHEST_H)
	## 回血是施放那一刻结算的 ⇒ 精魄不许"慢慢飞回来再加血": 整条从目标到自己同一刻铺开,
	##   由远到近依次播(相邻差 1 帧), 读起来是一股往回涌的血流。
	var a: Vector2 = tgt["pos"]
	var d: Vector2 = u["pos"] - a
	var n: int = clampi(int(DetMath.vlen(d) / WISP_GAP), 1, 4)
	for i in range(n):
		var f: float = float(i + 1) / float(n + 1)
		var w := _once(WISP, a + d * f, CHEST_H, d.x < 0.0)     # 精魄素材朝右飞, 往左回就镜像
		if w != null:
			battle._anim_fx[battle._anim_fx.size() - 1]["t0"] = battle._t + float(i) / float(WISP[2])


# ═══════════════════════════════════════════════════════════════════
#  变脸: 斗篷甩过脸那一刻的两色烟
# ═══════════════════════════════════════════════════════════════════
func face_swap(u: Dictionary) -> void:
	_once_on(SWAP, u, HEAD_H)


# ═══════════════════════════════════════════════════════════════════
#  融合·魔法波(物理紫 / 真实白交替)
# ═══════════════════════════════════════════════════════════════════
func fusion_wave_new(from2d: Vector2, to2d: Vector2, is_true: bool) -> Sprite3D:
	if battle._world == null:
		return null
	var sp := sprite(WAVE)
	if sp == null:
		return null
	sp.flip_h = (to2d.x - from2d.x) < 0.0      # 波峰朝右, 目标在左镜像
	sp.modulate = Color.WHITE if is_true else WAVE_PHYS_TINT
	sp.render_priority = 6
	sp.position = battle._world_pos(from2d, CHEST_H)
	battle._world.add_child(sp)
	return sp


## 飞行中切帧(循环): `fly_t` = 已飞行秒。
func fusion_wave_frame(sp, fly_t: float) -> void:
	if is_instance_valid(sp):
		sp.frame = int(fly_t * float(WAVE[2])) % int(WAVE[1])
