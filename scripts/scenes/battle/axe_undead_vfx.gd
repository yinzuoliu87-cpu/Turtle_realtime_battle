class_name AxeUndeadVfx
extends RefCounted
## 096 小木斧【亡灵之斧】造物的演出 (2026-09-15 · 方案书 20260915g「E」)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来
## ══════════════════════════════════════════════════════════════════
## 用户看完九段形态视频:「6/9亡灵斧你这是在敷衍我啊，完全没按标准来」。
## 被否的是 `axe_final_vfx.gd` 里那三样代码现算的图形:
##   环 = 程序细环网格一圈半透绿线 / 吸取 = ImmediateMesh 绿线 / 复活 = 6 根 BoxMesh 小方块聚拢。
## 他同一段对别的形态说的话就是尺子:
##   **演出读得出机制 · 范围 = 判定 · 每个效果有自己的画面 · 生效要有反馈**。
##
## 文案(p2eq_096 effectDesc3)每一句对应一段(分段表见方案书):
##   U1 常驻领域 `eq096-undead-field.png`  —— 300 码环, **外缘 = 判定圆**
##   U2 每秒一跳  `eq096-undead-pulse.png` 领域内收 + `eq096-undead-soul.png` 每个挨扣的敌人抽一缕魂
##                + `eq096-undead-drink.png` 斧头吸到了(回血)
##   U3 死亡复活  `eq096-undead-shatter.png` 崩散 → `eq096-undead-wake.png` 倒计时 → `eq096-undead-rise.png` 复活
##
## ★结算不在这里(CLAUDE.md §3.5): 伤害 / 回血 / 复活全在 `axe_final_forms.gd` 的同步函数里,
##   本文件的入口由那几个函数在【同一个模拟步】调用, 只负责画。
## ★时钟: 长驻的(领域 / 倒计时)挂 `battle._follow_vfx` / `battle._anim_fx` —— 按游戏钟 `battle._t` 切帧,
##   顿帧 / 时停一起停; 飞行的魂是 0.45 秒的纯观感 tween(`_reg_tween`, 时停冻得住), lambda 只捕获实例 id。
## ★像素贴图一律 NEAREST、不做 tween 缩放(vfx_discipline_audit A/D 条); 短命的走 `hold_fade` 前 70% 满亮。
const AF := preload("res://scripts/gamedata/axe_final_stats.gd")
const AFV := preload("res://scripts/scenes/battle/axe_final_vfx.gd")
const BladeVfx := preload("res://scripts/scenes/battle/blade_eq_vfx.gd")

const TEX_FIELD := "res://assets/sprites/vfx/eq096-undead-field.png"
const TEX_PULSE := "res://assets/sprites/vfx/eq096-undead-pulse.png"
const TEX_SOUL := "res://assets/sprites/vfx/eq096-undead-soul.png"
const TEX_DRINK := "res://assets/sprites/vfx/eq096-undead-drink.png"
const TEX_SHATTER := "res://assets/sprites/vfx/eq096-undead-shatter.png"
const TEX_WAKE := "res://assets/sprites/vfx/eq096-undead-wake.png"
const TEX_RISE := "res://assets/sprites/vfx/eq096-undead-rise.png"

## 贴地高度(米): 略高于地面, 免得被地板吃掉(同 AxePassiveVfx.FIELD_Y)
const GROUND_Y := 0.06
## 领域循环 8 帧 / 8fps = 1 秒一圈 —— 与「每秒一跳」同一个周期
const FIELD_FPS := 8.0
## 领域常驻透明度: 墓雾与骨纹底是暗色实心像素, 全不透明会把地图压成一块黑板(持续态恒定, 不闪)
const FIELD_ALPHA := 0.88
const FRAMES := 8
const WAKE_FRAMES := 16
## 每一跳的三段时长(秒)
const PULSE_SEC := 0.5
const SOUL_FLY_SEC := 0.45
const DRINK_SEC := 0.6
const SHATTER_SEC := 0.6
const RISE_SEC := 0.6
## 公告板的世界尺寸(码)与挂的高度(米)
const SOUL_YARDS := 44.0
const SOUL_FROM_H := 0.9
const SOUL_TO_H := 1.0
const SOUL_ARC_M := 0.8
const DRINK_YARDS := 90.0
const DRINK_H := 0.9
const SHATTER_YARDS := 110.0
const SHATTER_H := 0.9
const WAKE_YARDS := 170.0
const RISE_YARDS := 130.0
## 复活柱的地面线在画布 y = -0.8(格底往上 10%) ⇒ 公告板中心要抬到 半高 − 10% 格高
const RISE_H := RISE_YARDS * 0.024 * 0.4

var battle = null


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调
# ══════════════════════════════════════════════════════════════════

## 倒计时帧表的帧率: 16 帧正好铺满「死亡 → 复活」的实际间隔。
## ★间隔读排好的复活时刻, 不另写 2.5 —— 结算那边改了延迟, 演出自己跟着变。
static func wake_fps(delay: float) -> float:
	return float(WAKE_FRAMES) / maxf(0.05, delay)


## 魂的飞行位置: a → b 直线插值 + 往上拱的弧(sin), x ∈ [0, 1]。
static func soul_pos(a: Vector3, b: Vector3, x: float) -> Vector3:
	var t: float = clampf(x, 0.0, 1.0)
	var p: Vector3 = a.lerp(b, t)
	p.y += sin(t * PI) * SOUL_ARC_M
	return p


## 飞行进度 → 帧号(0~2 钻出, 3~7 飞行)。**不 drop 最后一帧**。
static func soul_frame(x: float) -> int:
	return clampi(int(clampf(x, 0.0, 1.0) * float(FRAMES)), 0, FRAMES - 1)


# ══════════════════════════════════════════════════════════════════
#  §建节点
# ══════════════════════════════════════════════════════════════════

func _sheet(path: String, hframes: int) -> Sprite3D:
	if not _has_world() or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = hframes
	s.frame = 0
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return s


## 按【单帧】边长把贴图归一到 `yards` 码。
func _size(s: Sprite3D, yards: float) -> void:
	s.pixel_size = yards * float(battle.WS) / float(maxi(1, s.texture.get_height()))


## 贴地放: 整个 basis 交给 BladeVfx.ground_basis(同 AxePassiveVfx._play_sheet 的做法)。
## ★render_priority 为负: 先于龟立绘(优先级 0)画, 龟站在领域上面, 不被盖住。
func _ground(s: Sprite3D, pos2d: Vector2, prio: int) -> void:
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.basis = BladeVfx.ground_basis(Vector2.RIGHT, 0.0)
	s.position = battle._world_pos(pos2d, GROUND_Y)
	s.render_priority = prio


func _billboard(s: Sprite3D, pos2d: Vector2, h: float, prio: int) -> void:
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.position = battle._world_pos(pos2d, h)
	s.render_priority = prio


## 一次性帧表挂在单位身上: 跟着走, 按游戏钟放完一遍自销(`_follow_vfx` 的 anim_fps 分支)。
func _follow_once(s: Sprite3D, u: Dictionary, h: float, sec: float) -> void:
	battle._world.add_child(s)
	battle._follow_vfx.append({"spr": s, "unit": u, "h": h,
		"anim_fps": float(s.hframes) / maxf(0.05, sec), "anim_n": s.hframes, "anim_t0": float(battle._t)})


## ── U1 常驻领域 ────────────────────────────────────────────────
## 保证亡灵之斧脚下有领域。每模拟步由 `AxeFinalForms.undead_field_step` 调; 已经有了就直接返回。
## ★外径 = 2 × UNDEAD_RING_R: 画布边就是判定圆(素材最外一圈亮边外缘 0.992)。
## ★跟随 + 循环切帧 + 斧头死亡自销, 全交给 `_follow_vfx`(全项目"贴着单位走"的既有机制),
##   死亡那一步 `free_field` 还会先同步释放一次, 不等渲染帧。
func ensure_field(ax: Dictionary) -> Sprite3D:
	var cur = ax.get("_undead_field_spr", null)
	if is_instance_valid(cur) and not (cur as Node).is_queued_for_deletion():
		return cur
	if not ax.get("alive", false):
		return null
	var s: Sprite3D = _sheet(TEX_FIELD, FRAMES)
	if s == null:
		return null
	_size(s, AF.UNDEAD_RING_R * 2.0)
	_ground(s, ax.get("pos", Vector2.ZERO), -2)
	s.modulate = Color(1.0, 1.0, 1.0, FIELD_ALPHA)
	battle._world.add_child(s)
	battle._follow_vfx.append({"spr": s, "unit": ax, "h": GROUND_Y,
		"loop_fps": FIELD_FPS, "loop_n": FRAMES, "loop_t0": float(battle._t)})
	ax["_undead_field_spr"] = s
	return s


func free_field(ax: Dictionary) -> void:
	var cur = ax.get("_undead_field_spr", null)
	if is_instance_valid(cur):
		(cur as Node).queue_free()
	ax.erase("_undead_field_spr")


## ── U2 每秒一跳 ────────────────────────────────────────────────
## `hit` = 这一跳【真的被扣了血】的环内敌人(结算那边算好的同一个数组)。
## 返回这一步建出来的节点 {"pulse", "souls": [...], "drink"}, 调用方一般不用管。
func ring_tick(ax: Dictionary, hit: Array) -> Dictionary:
	var out := {"pulse": null, "souls": [], "drink": null}
	if not _has_world() or not (ax is Dictionary):
		return out
	ensure_field(ax)
	## U2a 领域内收: 贴地, 与领域同尺寸, 跟斧头
	var p: Sprite3D = _sheet(TEX_PULSE, FRAMES)
	if p != null:
		_size(p, AF.UNDEAD_RING_R * 2.0)
		_ground(p, ax.get("pos", Vector2.ZERO), -1)
		_follow_once(p, ax, GROUND_Y, PULSE_SEC)
		out["pulse"] = p
	## U2b 每个挨扣的敌人一缕魂 —— 一跳几个敌人就几道
	var to3: Vector3 = battle._world_pos(ax.get("pos", Vector2.ZERO), SOUL_TO_H)
	for o in hit:
		if not (o is Dictionary):
			continue
		var sp: Sprite3D = soul(o, to3)
		if sp != null:
			(out["souls"] as Array).append(sp)
	## U2c 斧头吸到了: 只有真的回了血(环内有人)才建
	if not hit.is_empty():
		var d: Sprite3D = _sheet(TEX_DRINK, FRAMES)
		if d != null:
			_size(d, DRINK_YARDS)
			_billboard(d, ax.get("pos", Vector2.ZERO), DRINK_H, 8)
			_follow_once(d, ax, DRINK_H, DRINK_SEC)
			out["drink"] = d
	return out


## 一缕魂从敌人身上飞回斧头。★纯观感: 伤害与回血在建它之前已经结算完。
func soul(o: Dictionary, to3: Vector3) -> Sprite3D:
	var s: Sprite3D = _sheet(TEX_SOUL, FRAMES)
	if s == null:
		return null
	_size(s, SOUL_YARDS)
	var from3: Vector3 = battle._world_pos(o.get("pos", Vector2.ZERO), float(o.get("height", 0.0)) + SOUL_FROM_H)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.render_priority = 9
	s.position = from3
	battle._world.add_child(s)
	## ★显式标注类型: `battle` 是无类型的注入宿主, `:=` 推不出 Tween(Parse Error)。
	var tw: Tween = battle._reg_tween()
	## ★捕获实例 id 不捕获节点(见 AxeFinalVfx._fade_out 头注: 捕获物先释放会在调用 lambda 那一刻报错)
	var sid: int = s.get_instance_id()
	tw.tween_method(func(x: float) -> void:
		var n = instance_from_id(sid)
		if not is_instance_valid(n):
			return
		(n as Sprite3D).position = soul_pos(from3, to3, x)
		(n as Sprite3D).frame = soul_frame(x)
		(n as Sprite3D).modulate.a = AFV.hold_fade(x)
	, 0.0, 1.0, SOUL_FLY_SEC)
	tw.tween_callback(func() -> void:
		var n2 = instance_from_id(sid)
		if is_instance_valid(n2):
			(n2 as Node).queue_free())
	return s


## ── U3 死亡 → 倒计时 → 复活 ─────────────────────────────────────
## 斧头倒下那一步调(`AxeFinalForms.undead_on_death`)。`revive_at < 0` = 这次不复活(已经复活过一次)。
## 返回 {"shatter", "wake"}。
func on_death(ax: Dictionary, revive_at: float) -> Dictionary:
	var out := {"shatter": null, "wake": null}
	free_field(ax)
	if not _has_world():
		return out
	var pos: Vector2 = ax.get("pos", Vector2.ZERO)
	var t0: float = float(battle._t)
	## U3a 崩散: 死亡位置固定(斧头已死, `_follow_vfx` 会把挂在死者身上的立刻收掉) ⇒ 走 `_anim_fx`
	var sh: Sprite3D = _sheet(TEX_SHATTER, FRAMES)
	if sh != null:
		_size(sh, SHATTER_YARDS)
		_billboard(sh, pos, SHATTER_H, 8)
		battle._world.add_child(sh)
		battle._anim_fx.append({"spr": sh, "t0": t0, "fps": float(FRAMES) / SHATTER_SEC, "n": FRAMES})
		out["shatter"] = sh
	## U3b 倒计时: 16 帧铺满「死亡 → 复活」的实际间隔
	if revive_at > t0:
		var wk: Sprite3D = _sheet(TEX_WAKE, WAKE_FRAMES)
		if wk != null:
			_size(wk, WAKE_YARDS)
			_ground(wk, pos, -1)
			battle._world.add_child(wk)
			battle._anim_fx.append({"spr": wk, "t0": t0, "fps": wake_fps(revive_at - t0), "n": WAKE_FRAMES})
			ax["_undead_wake_spr"] = wk
			out["wake"] = wk
	return out


## 复活结算成功那一步调(`AxeFinalForms.undead_tick_revive`)。倒计时在这一步收掉, 复活柱在这一步起。
func on_revive(ax: Dictionary) -> Sprite3D:
	var wk = ax.get("_undead_wake_spr", null)
	if is_instance_valid(wk):
		(wk as Node).queue_free()
	ax.erase("_undead_wake_spr")
	if not _has_world():
		return null
	var r: Sprite3D = _sheet(TEX_RISE, FRAMES)
	if r != null:
		_size(r, RISE_YARDS)
		_billboard(r, ax.get("pos", Vector2.ZERO), RISE_H, 8)
		_follow_once(r, ax, RISE_H, RISE_SEC)
	ensure_field(ax)
	return r
