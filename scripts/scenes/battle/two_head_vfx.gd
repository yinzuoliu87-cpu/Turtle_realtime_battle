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
const SLAM := ["twohead-hammer-slam.png", 12, 14.0, 1]      # 锤击·落地符文裂地
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
	_once(SWING, mid, CHEST_H, d.x > 0.0)


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
#  锤击: 落地符文裂地(单体技 ⇒ 不画范围环)
# ═══════════════════════════════════════════════════════════════════
func hammer_slam(at2d: Vector2) -> void:
	_once(SLAM, at2d, 0.08)


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
