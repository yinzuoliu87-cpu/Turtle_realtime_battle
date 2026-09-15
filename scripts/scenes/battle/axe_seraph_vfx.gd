class_name AxeSeraphVfx
extends RefCounted
## 096 炽天使主动【回旋镖】的演出 (2026-09-15)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-15:「7/9的回旋镖同样是在敷衍我啊，回旋镖是什么？以及特效和实际伤害范围完全不一样啊，也没有命中特效」
## 旧演出(`AxeFinalVfx.seraph_boomerang`, 已删): 一根 0.55×0.10×0.16 米的橙色 BoxMesh 直线飞 0.45 秒、不回来;
##   判定却是半宽 300 码的带, 出手当帧全部结算; 命中没有任何特效。
##
## ══════════════════════════════════════════════════════════════════
##  ★三件事, 各自怎么对上需求
## ══════════════════════════════════════════════════════════════════
##   ① 「回旋镖是什么」: 贴地旋转的炽天使羽翼 V 形镖(Blender 烘焙, 俯视 8 帧转一圈),
##      飞行路径由 `AxeFinalForms.tick_boomerangs` 按战斗时钟逐步走(飞出去 → 折返 → 飞回斧头),
##      这里只负责把节点搬到当前中心、按飞行时间切帧。
##   ② 「特效和实际伤害范围不一样」: 节点帧宽 × pixel_size = **2 × SERAPH_BOOM_R**(`boom_pixel_size`),
##      烘焙时相机正交宽度 = 2R ⇒ 格子边缘就是判定半径, 翼尖流光画到 0.965R。
##      判定 = 敌人中心到镖中心走过的线段 ≤ SERAPH_BOOM_R ⇒ **转起来扫出的那一圈就是打到人的那一圈**。
##   ③ 「没有命中特效」: 每次命中在被命中者身上一个公告板火花(6 帧: 亮点 → 八道放射 → 羽毛飘开), 一次性。
##
## ★结算不在这里(CLAUDE.md §3.5): 伤害 / 灼烧在 `AxeFinalForms._boom_sweep` 里同步结算, 演出掉了也不影响数值。
## ★不用 tween: 镖身与火花都由 `tick`(战斗时钟)推进 ⇒ 时停期间 `tick_global` 整块不跑、演出天然冻住,
##   也不会出现「tween 按真实时间走、结算按游戏时间走」两条时钟打架(memory: 两条时钟必然丢事件)。
## ★像素贴图一律 NEAREST, 不做任何连续缩放(特效纪律 A 条); 火花淡出走 `hold_fade`(前 70% 满亮)。
const AF := preload("res://scripts/gamedata/axe_final_stats.gd")
const AFV := preload("res://scripts/scenes/battle/axe_final_vfx.gd")
## ★贴地朝向调 blade 那份已验收的 `ground_basis`, 不自己写第二套(与 axe_passive_vfx 同一个理由)。
const BladeVfx := preload("res://scripts/scenes/battle/blade_eq_vfx.gd")

const TEX_BOOM := "res://assets/sprites/vfx/eq096-seraph-boomerang.png"
const TEX_HIT := "res://assets/sprites/vfx/eq096-seraph-boom-hit.png"
## 镖身: 8 帧转一整圈; 20 帧/秒 ⇒ 每秒 2.5 圈(一去一回 0.94 秒约转 2.3 圈, 读得出"在旋")
const BOOM_FRAMES := 8
const BOOM_FPS := 20.0
## 离地高度(米): 贴地但高过接触影, 站在圈里的龟腿以上照常露出来(开深度测试, 见 boom_spawn)
const BOOM_Y := 0.30
## 命中火花: 6 帧 × 15 帧/秒 = 0.4 秒; 64 格画满约 90 码(≈2.2 米, 比龟身 1.4 米略大一圈)
const HIT_FRAMES := 6
const HIT_FPS := 15.0
const HIT_SIZE_PX := 90.0
const HIT_Y := 0.75

var battle = null
## 在场的火花: [{id: 节点实例 id, t: 已播秒数, tgt: 被命中者}] —— 由 tick 推进。
## ★存实例 id 不存节点: 换路重建世界时节点先被释放, instance_from_id 返回 null 即静默丢弃。
var _sparks: Array = []


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调
# ══════════════════════════════════════════════════════════════════

## 镖身在飞了 `t` 秒时该显示第几帧(按飞行时间循环)。
static func boom_frame(t: float) -> int:
	return int(floor(maxf(0.0, t) * BOOM_FPS)) % BOOM_FRAMES


## 镖身节点的 pixel_size: **帧宽 × pixel_size = 2 × SERAPH_BOOM_R 码**(演出 = 判定)。
static func boom_pixel_size(frame_w_px: int, ws: float) -> float:
	return (2.0 * AF.SERAPH_BOOM_R * ws) / float(maxi(1, frame_w_px))


## 火花在播了 `t` 秒时该显示第几帧(一次性, 停在最后一帧)。
static func hit_frame(t: float) -> int:
	return clampi(int(floor(maxf(0.0, t) * HIT_FPS)), 0, HIT_FRAMES - 1)


# ══════════════════════════════════════════════════════════════════
#  §建节点
# ══════════════════════════════════════════════════════════════════

## 出手: 在出手点建一把贴地的镖。返回节点(无世界 / 缺图时 null —— 无头测试里正常)。
func boom_spawn(pos2d: Vector2) -> Sprite3D:
	if not _has_world() or not ResourceLoader.exists(TEX_BOOM):
		return null
	var tex: Texture2D = load(TEX_BOOM)
	if tex == null:
		return null
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = BOOM_FRAMES
	s.frame = 0
	s.shaded = false
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	## ★硬边像素画走 alpha 裁切(不透明管线, 写深度): 600 码的镖铺满半个场地,
	##   若 no_depth_test 盖在所有单位上面, 圈里的龟整只被羽毛遮住; 裁切 + 深度测试 ⇒ 龟腿以上照常露出。
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.render_priority = 6
	s.pixel_size = boom_pixel_size(int(tex.get_width() / BOOM_FRAMES), float(battle.WS))
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.basis = BladeVfx.ground_basis(Vector2.RIGHT, 0.0)
	s.position = battle._world_pos(pos2d, BOOM_Y)
	battle._world.add_child(s)
	return s


## 每步: 把镖搬到当前中心、按飞行时间切帧。
func boom_step(s, pos2d: Vector2, t: float) -> void:
	if not (s is Sprite3D) or not is_instance_valid(s):
		return
	(s as Sprite3D).position = battle._world_pos(pos2d, BOOM_Y)
	(s as Sprite3D).frame = boom_frame(t)


## 飞回斧头 / 源头离场: 收掉节点。
func boom_free(s) -> void:
	if s is Node and is_instance_valid(s):
		(s as Node).queue_free()


## 命中: 在被命中者身上建一个一次性火花。返回节点。
func hit_spark(tgt: Dictionary) -> Sprite3D:
	if not _has_world() or not (tgt is Dictionary) or not ResourceLoader.exists(TEX_HIT):
		return null
	var tex: Texture2D = load(TEX_HIT)
	if tex == null:
		return null
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = HIT_FRAMES
	s.frame = 0
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.render_priority = 9
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.pixel_size = (HIT_SIZE_PX * float(battle.WS)) / float(maxi(1, tex.get_height()))
	s.position = battle._world_pos(tgt.get("pos", Vector2.ZERO), HIT_Y)
	battle._world.add_child(s)
	_sparks.append({"id": s.get_instance_id(), "t": 0.0, "tgt": tgt})
	return s


## 每个模拟步推进火花(由 `AxeFinalForms.tick_boomerangs` 调, 同一条战斗时钟)。
func tick(delta: float) -> void:
	if _sparks.is_empty():
		return
	var dur: float = float(HIT_FRAMES) / HIT_FPS
	var keep: Array = []
	for sp in _sparks:
		var n = instance_from_id(int(sp["id"]))
		if not is_instance_valid(n):
			continue
		var t: float = float(sp["t"]) + maxf(0.0, delta)
		if t >= dur:
			(n as Node).queue_free()
			continue
		sp["t"] = t
		var s := n as Sprite3D
		s.frame = hit_frame(t)
		s.modulate.a = AFV.hold_fade(t / dur)
		var tgt = sp.get("tgt", null)
		if tgt is Dictionary:
			s.position = battle._world_pos((tgt as Dictionary).get("pos", Vector2.ZERO), HIT_Y)
		keep.append(sp)
	_sparks = keep
