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
## 锤击·砸地(2026-10-20 重做 + 改范围技, 逐帧研究 docs/studies/20261020b-变脸龟锤击砸地逐帧.md):
const SLAM_RING := ["twohead-slam-ring.png", 7, 20.0, 2]      # 贴地(2× texel): 地闪 → 冲击环减速扩到判定半径 → 环碎
const SLAM_CRACK := ["twohead-slam-crack.png", 13, 20.0, 1]   # 贴地(1× texel, 与龟同细): 符文地裂从落点窜出 → 薄荷冷却成暗绿 → 碎散
const SLAM_BURST := ["twohead-slam-burst.png", 13, 20.0, 1]    # 竖立: 白核 + 光刺 → 碎石上抛落地 → 尘团鼓起散去
const SLAM_DUST := ["twohead-slam-edgedust.png", 8, 20.0, 2]
## 落点爆炸(10-20 用户看视频后「冲击环没问题，但是起码要有爆炸的特效吧」): 尖刺闪 → 白热团 → 橙红分瓣火球 → 外缘碎裂翻卷 → 灰烟碎散
const SLAM_BOOM := ["twohead-slam-boom.png", 15, 20.0, 1]   # 圈边小尘团(冲击环扫到判定半径边缘时踢起)
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
## ★特效即判定: 贴地表里冲击环满径那几帧的环半径(像素, 量素材第 3~5 帧中位数 96.4)。
##   贴地层 pixel_size = STRIKE_MELEE_RADIUS × WS ÷ 它 ⇒ 环画多大 = 判定多大(现值 200 码 ⇒ 0.05 米/像素 = 龟 texel 的整 2 倍)。
##   门禁 verify_two_head_anim F⑥ 按素材重新量环半径再乘运行期 pixel_size, 不读这个常量。
const SLAM_RING_PX := 96.0
## 竖立两张表里"落点"(画布锚点)在帧中心下方多少像素 ⇒ 用 offset 把锚点对到节点原点(地面)
const SLAM_BURST_FOOT := 36.0
const SLAM_DUST_FOOT := 16.0
## 爆炸表里火球底边(第 7~10 帧最低处 y≈100)在帧中心(73)下方多少像素 ⇒ 火球坐在地面上往上长
const SLAM_BOOM_FOOT := 27.0
## 圈边尘团: 几团、离圆心 = 判定半径 × 多少、冲击环扫到那里的时刻(贴地表第 2 帧, 环已到 92%)
const SLAM_DUST_N := 8
const SLAM_DUST_AT := 0.92
const SLAM_DUST_DELAY := 0.1
## 挥锤弧(SWING 62×82)下端在帧内 x≈12 ⇒ 中心要往回挪 19 像素 ≈ 20 码, 弧尾才正好落在锤头上
const SWING_TAIL_BACK := 20.0
## 挥锤弧从第几帧起播: 第 2 帧 = 完整的 C 形(砸地那一步锤已经挥完, 不该再从弧头起手)
const SWING_START_FRAME := 2
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
	sp.hframes = int(spec[1])
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
#  锤击: 砸地冲击(范围技 ⇒ 冲击环 = 判定半径)
# ═══════════════════════════════════════════════════════════════════
## `at2d` = 施法者落点(sim), `face_right` = 立绘朝向(sim 字段) ⇒ 锤头落点 = TwoHeadSystem.hammer_point(结算圆心同一点)。
## 分段(逐帧研究 20261020b): 命中 = 白核 + 光刺(2 帧, 画在所有单位上面) · 地面响应 = 冲击环 0.15 秒减速扩到判定半径、
##   符文地裂从落点窜出、碎石上抛、圈边尘团在环到达时踢起 · 余韵 = 地裂由白冷却成符文绿再碎散、尘团上升散去。
func hammer_slam(at2d: Vector2, face_right: bool) -> Vector2:
	var hit: Vector2 = TwoHeadSystem.hammer_point(at2d, face_right)
	var R: float = TwoHeadSystem.STRIKE_MELEE_RADIUS
	## ① 贴地两层: 平躺在地面(测深度: 站在环上的龟挡住它身后那段地面)。冲击环 pixel_size 由判定半径算出; 地裂 1× texel(与龟同细, 2× 时读成白色粗折线)
	var g := _once(SLAM_RING, hit, 0.03)
	if g != null:
		g.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		g.axis = Vector3.AXIS_Y
		g.pixel_size = R * battle.WS / SLAM_RING_PX
		g.render_priority = 5
	var k := _once(SLAM_CRACK, hit, 0.02)
	if k != null:
		k.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		k.axis = Vector3.AXIS_Y
		k.render_priority = 5
	## ② 竖立爆点: 锚点(落点)对到地面, 画在所有单位上面(目标就站在落点旁, 不许被挡)
	var b := _once(SLAM_BURST, hit, 0.0, not face_right)
	if b != null:
		b.offset = Vector2(0.0, SLAM_BURST_FOOT)
		over_units(b)
	## ②b 落点爆炸: 与冲击环同一步起爆, 立着、画在所有单位上面(目标就站在旁边)
	var bm := _once(SLAM_BOOM, hit, 0.0, not face_right)
	if bm != null:
		bm.offset = Vector2(0.0, SLAM_BOOM_FOOT)
		over_units(bm)
	## ③ 圈边尘团: 正好落在判定半径上, 冲击环扫到时踢起(在场地外的那几团不放)
	for i in range(SLAM_DUST_N):
		var p: Vector2 = hit + DetMath.rotated(Vector2(R * SLAM_DUST_AT, 0.0), TAU * (float(i) + 0.5) / float(SLAM_DUST_N))
		if not ArenaShape.in_rect_shape(p, battle.ARENA):
			continue
		var d := _once(SLAM_DUST, p, 0.0, p.x < hit.x)
		if d != null:
			d.offset = Vector2(0.0, SLAM_DUST_FOOT)
			d.visible = false                                    # 环到之前不露(帧推进前 _tick_anim_fx 会钳在第 0 帧)
			battle._anim_fx[battle._anim_fx.size() - 1]["t0"] = battle._t + SLAM_DUST_DELAY
			battle._anim_fx[battle._anim_fx.size() - 1]["show_at"] = battle._t + SLAM_DUST_DELAY
	## 挥锤弧: 从完整 C 形那一帧起播(砸地这一步锤已经挥下来了), 弧尾收在锤头落点
	var fwd := 1.0 if face_right else -1.0
	var sw := _once(SWING, at2d + Vector2(fwd * (TwoHeadSystem.STRIKE_MELEE_HEAD_FWD - SWING_TAIL_BACK), 0.0), CHEST_H, face_right)
	if sw != null:
		over_units(sw)
		battle._anim_fx[battle._anim_fx.size() - 1]["t0"] = battle._t - float(SWING_START_FRAME) / float(SWING[2])
		sw.frame = SWING_START_FRAME
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
