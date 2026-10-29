class_name ReserveSystem
extends RefCounted
## 援军小将·四面合围(方案书 docs/plans/20261029-终极战场援军小将.md; 数值 scripts/gamedata/reserve_consts.gd)。
## 锁定一名敌人, 在它的前后左右各出现一道气波, 四道同时**追着它**飞(用户 2026-10-29: 直飞当时的位置会落空 ⇒ 要追踪);
##   每道打中路上碰到的第一个敌人(可能是目标, 也可能是挡在中间的别人)就消失,
##   造成 100% 攻击力物理 + 该敌人 10% 最大生命值魔法。
## ★结算与几何抽成纯函数(spawn_points / wave_hit), 门禁直接调, 不依赖任何动画 tween(CLAUDE.md §3.5)。

const WAVE_TEX := "res://assets/sprites/vfx/reserve-wave.png"         ## 回落: 公告板圆球(有方向的那张没画好时)
const WAVE_PX := 48.0
## 有方向的动态气波(机头朝 +X, 横排多帧): 非公告板 Sprite3D, 每步按飞行方向转(同远程小将导弹的做法)。
const WAVE_DIR_TEX := "res://assets/sprites/vfx/reserve-wave-dir.png"
## 用户 2026-10-29 看录屏:「气波太小了，要大一点」⇒ 72 → 120(= 40 像素 × 3 码, 与演出素材同一像素密度)。
const WAVE_DIR_LEN := 120.0             ## 弹体在场上的长度(码)
## 每步重排的延时比 SKILLSHOT_STEP 短这么一点: 0.05 秒 = 3 个 1/60 秒 sim 步, 但浮点里 0.05 − 3 × (1/60) 略大于 0
##   ⇒ 不减它要第 4 步才到点(实测速度只有标称的 3/4, 而且每 3 帧顿 1 帧)。只对援军气波生效, 共用的 fire_skillshot 不动。
const STEP_EPS := 0.0001
## 普攻气弹(用户 2026-10-29「他普攻有弹道吗？」—— 原来是全体远程共用的程序小光点): 弹头朝 +X、4 帧循环, 贴地按飞行方向转。
const SHOT_TEX := "res://assets/sprites/vfx/reserve-shot.png"
const SHOT_LEN := 48.0                  ## 普攻气弹在场上的长度(码) = 16 像素 × 3 码

## ══ 立绘与动作(2026-10-29 PixelLab 新画: 黄铜潜水盔 + 背负气瓶与橙色信号旗的深海援军兵) ══
## 全部 112×112 方帧、west 侧面(原图朝左, 同远程小将口径)。★各动作第 0 帧逐像素等于立绘
##   `pets/minion-reserve.png`(头像/图鉴同一张) ⇒ 待机↔动作切换不跳大小、不跳位置
##   (verify_minion_idle_align 焊住; 归一数据在主场景 ANIM_NORM 的 "__minion_reserve__" 行)。
const IDLE_SHEET := "res://assets/sprites/pets/animations/reserve/idle.png"
const IDLE_FPS := 7.0                   ## 7 帧呼吸循环 = 1.0 秒一轮
## 技能动作(由 `_melee_anim` 按动画键 "__minion_reserve__" 查这张表)。
## ★动画时长 == 施法定身 CAST_ROOT: 帧数 ÷ fps = 0.5 秒。短了角色站着发呆, 长了被下一段打断(verify_elite_anim 对账)。
const SKILL_FRAMES := 8
const ACTION_RESERVE := {
	"skill": ["pets/animations/reserve/skill.png", SKILL_FRAMES / ReserveConsts.CAST_ROOT],
}

var battle
var vfx: ReserveVfx                     ## 演出(纯表现; 无头裁判没有 _world ⇒ 各入口自己直接返回)


func _init(b) -> void:
	battle = b
	vfx = ReserveVfx.new(b)


## 战场立绘字典(待机循环)。battle_spawn._make_unit 的小将分支在 role == "reserve" 时取它。
func sprite_dict() -> Dictionary:
	var tex: Texture2D = load(IDLE_SHEET) if ResourceLoader.exists(IDLE_SHEET) else null
	var th: int = tex.get_height() if tex != null else 64
	var n: int = maxi(1, tex.get_width() / th) if tex != null else 1
	return {"tex": tex, "frames": n, "fps": IDLE_FPS, "frame_h": th, "hframes": n, "vframes": 1, "loop": true}


## 普攻弹体(纯表现): battle_ballistics._fire_bolt_from 见到援军小将就来这里拿。贴图缺失 ⇒ null(回落通用光点)。
func shot_sprite() -> Sprite3D:
	if not ResourceLoader.exists(SHOT_TEX):
		return null
	var tex: Texture2D = load(SHOT_TEX)
	if tex == null:
		return null
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = maxi(1, int(tex.get_width() / (tex.get_height() * 2)))   # 单帧宽 = 2 × 高
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = (SHOT_LEN * battle.WS) / float(maxi(1, int(tex.get_width() / s.hframes)))
	return s


## 四个出发点: 以「施法者 → 目标」定前后, 垂直方向定左右; 距目标 WAVE_RADIUS。纯向量运算(DetMath), 不用三角函数和随机数。
func spawn_points(u: Dictionary, tgt: Dictionary) -> Array:
	var tp: Vector2 = tgt["pos"]
	var d: Vector2 = (u["pos"] as Vector2) - tp
	var f: Vector2 = DetMath.norm(d) if DetMath.vlen(d) > 1.0 else (Vector2.LEFT if bool(u.get("face_right", true)) else Vector2.RIGHT)
	var s := Vector2(-f.y, f.x)
	var r: float = ReserveConsts.WAVE_RADIUS
	return [tp + f * r, tp - f * r, tp + s * r, tp - s * r]


func cast(u: Dictionary, tgt) -> void:
	if tgt == null or not (tgt as Dictionary).get("alive", false):
		return
	var t: Dictionary = tgt
	var center: Vector2 = t["pos"]
	u["face_right"] = (center - (u["pos"] as Vector2)).x >= 0.0
	u["_slam"] = true                                   # 施法定身
	battle._melee_anim(u, "skill")
	var uu := u
	battle._pending_shots.append({"delay": ReserveConsts.CAST_ROOT, "fn": func() -> void: uu["_slam"] = false, "src": u})
	var pts: Array = spawn_points(u, t)
	vfx.converge_spawn(pts, center)
	for p in pts:
		fly_wave(u, t, p)


## 一道追踪气波: 每 SKILLSHOT_STEP 重新对准目标**当前**位置(目标死了就飞到它最后的位置消散), 碰到的第一个敌人结算后消失;
##   最多飞 WAVE_MAX_FLY 码。命中判定与直线技能同一个 `_first_on_segment`(带往回补查), 纯 DetMath, 结算不依赖任何 tween。
## ★施法者中途阵亡: 已经飞出去的照常结算(条目不带 cc ⇒ `_step_pending_shots` 不取消)。
func fly_wave(u: Dictionary, t: Dictionary, from: Vector2) -> void:
	var step: float = battle._ballistics.SKILLSHOT_STEP
	var spr: Sprite3D = _wave_sprite(from)
	var st := {"pos": from, "flown": 0.0, "aim": t["pos"], "dir": DetMath.norm((t["pos"] as Vector2) - from),
		"hold": roundi(ReserveConsts.WAVE_HOLD / step),
		"spr_id": spr.get_instance_id() if spr != null else 0}
	var uu := u
	var tt := t
	st["step"] = func() -> void:
		var node: Sprite3D = instance_from_id(int(st["spr_id"])) as Sprite3D if int(st["spr_id"]) != 0 else null
		if tt.get("alive", false):
			st["aim"] = tt["pos"]
		var p0: Vector2 = st["pos"]
		var to: Vector2 = (st["aim"] as Vector2) - p0
		var dir: Vector2 = DetMath.norm(to) if DetMath.vlen(to) > 0.5 else (st["dir"] as Vector2)
		st["dir"] = dir
		## 出现后原地停 WAVE_HOLD 秒: 不动、不判命中, 弹体照常逐帧动并转向对准目标(按步数数, 不累加浮点)
		if int(st["hold"]) > 0:
			st["hold"] = int(st["hold"]) - 1
			_wave_move(node, p0, p0, dir, step)
			if tt.get("alive", false):
				vfx.lock_follow(tt["pos"])
			battle._pending_shots.append({"delay": step - STEP_EPS, "fn": st["step"], "src": uu})
			return
		var adv: float = ReserveConsts.WAVE_SPEED * step
		var hit = battle._ballistics._first_on_segment(uu, p0, dir, adv, ReserveConsts.WAVE_HALF_W, ReserveConsts.WAVE_CATCHUP)
		if hit != null:
			_wave_move(node, p0, (hit as Dictionary)["pos"], dir, step)
			battle._ballistics._skillshot_free(node, step)
			vfx.wave_hit((hit as Dictionary)["pos"], dir)
			wave_hit(uu, hit)
			return
		var p1: Vector2 = p0 + dir * adv
		_wave_move(node, p0, p1, dir, step)
		vfx.wave_trail(p1, dir, WAVE_DIR_LEN)
		if tt.get("alive", false):
			vfx.lock_follow(tt["pos"])
		st["pos"] = p1
		st["flown"] = float(st["flown"]) + adv
		var reached: bool = not tt.get("alive", false) and DetMath.vlen((st["aim"] as Vector2) - p1) <= adv
		if float(st["flown"]) >= ReserveConsts.WAVE_MAX_FLY or reached:
			battle._ballistics._skillshot_free(node, step)
			vfx.wave_fizzle(p1)
			return
		battle._pending_shots.append({"delay": step - STEP_EPS, "fn": st["step"], "src": uu})
	battle._pending_shots.append({"delay": 0.0, "fn": st["step"], "src": u})


## 气波弹体节点(纯表现)。有方向的那张在 ⇒ 非公告板, 按飞行方向转; 不在 ⇒ 回落公告板圆球。无头(裁判)没有 _world ⇒ null。
func _wave_sprite(at: Vector2) -> Sprite3D:
	if not ResourceLoader.exists(WAVE_DIR_TEX):
		return battle._ballistics._skillshot_sprite(WAVE_TEX, WAVE_PX, at, ReserveConsts.WAVE_HOLD + ReserveConsts.WAVE_MAX_FLY / ReserveConsts.WAVE_SPEED)
	var tex: Texture2D = load(WAVE_DIR_TEX)
	if tex == null or battle._world == null:
		return null
	var fh: int = maxi(1, tex.get_height())
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = maxi(1, int(tex.get_width() / (fh * 2)))   # 单帧宽 = 2 × 高(机头朝 +X 的横条)
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.shaded = false
	s.transparent = true
	s.pixel_size = (WAVE_DIR_LEN * battle.WS) / float(maxi(1, int(tex.get_width() / s.hframes)))
	s.position = battle._world_pos(at, 1.0)
	battle._world.add_child(s)
	## 兜底: 换路会清 _pending_shots ⇒ 满程时长后无论如何收掉(bind_node: 节点先没了 tween 自动作废)
	var tw: Tween = battle._reg_tween()
	tw.bind_node(s)
	tw.tween_interval(ReserveConsts.WAVE_HOLD + ReserveConsts.WAVE_MAX_FLY / ReserveConsts.WAVE_SPEED + 0.5)
	tw.tween_callback(s.queue_free)
	return s


## 每步: 位置补间到 b, 朝向对准飞行方向, 帧往下翻一格(纯表现)。
func _wave_move(node: Sprite3D, a: Vector2, b: Vector2, dir: Vector2, dur: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	battle._ballistics._skillshot_move(node, a, b, dur)
	if node.billboard == BaseMaterial3D.BILLBOARD_DISABLED:
		battle._orient_billboard_dir(node, battle._world_pos(a + dir * 10.0, 1.0) - battle._world_pos(a, 1.0))
		node.frame = (node.frame + 1) % maxi(1, node.hframes)


## 一道气波打中 o: 物理段(100% 攻击力, 走攻击结算) + 魔法段(o 的 10% 真实最大生命值, 只吃魔抗、不掷暴击)。
func wave_hit(u: Dictionary, o: Dictionary) -> void:
	if not o.get("alive", false):
		return
	battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, ReserveConsts.ATK_COEF, o), Color("#ff6a4a"))
	if o.get("alive", false):
		battle._damage._apply_damage_from(u, o,
			battle._damage._magic_after_mr(u, float(o["maxHp"]) * ReserveConsts.MAXHP_PCT, o), Color("#6ab8ff"))
