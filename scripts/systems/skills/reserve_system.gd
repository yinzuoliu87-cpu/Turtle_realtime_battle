class_name ReserveSystem
extends RefCounted
## 援军小将·四面合围(方案书 docs/plans/20261029-终极战场援军小将.md; 数值 scripts/gamedata/reserve_consts.gd)。
## 锁定一名敌人, 在它的前后左右各出现一道气波, 四道同时往它中心走; 每道打中路上碰到的第一个敌人
##   (可能是目标, 也可能是挡在中间的别人), 造成 100% 攻击力物理 + 该敌人 10% 最大生命值魔法。
## ★结算与几何抽成纯函数(spawn_points / wave_hit), 门禁直接调, 不依赖任何动画 tween(CLAUDE.md §3.5)。

const WAVE_TEX := "res://assets/sprites/vfx/reserve-wave.png"
const WAVE_PX := 48.0

var battle


func _init(b) -> void:
	battle = b


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
	for p in spawn_points(u, t):
		var from: Vector2 = p
		var dir: Vector2 = DetMath.norm(center - from)
		battle._ballistics.fire_skillshot(u, dir, ReserveConsts.WAVE_RADIUS + ReserveConsts.WAVE_OVERSHOOT,
			ReserveConsts.WAVE_SPEED, ReserveConsts.WAVE_HALF_W, WAVE_TEX, WAVE_PX,
			func(o: Dictionary) -> void: wave_hit(uu, o), from)


## 一道气波打中 o: 物理段(100% 攻击力, 走攻击结算) + 魔法段(o 的 10% 真实最大生命值, 只吃魔抗、不掷暴击)。
func wave_hit(u: Dictionary, o: Dictionary) -> void:
	if not o.get("alive", false):
		return
	battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, ReserveConsts.ATK_COEF, o), Color("#ff6a4a"))
	if o.get("alive", false):
		battle._damage._apply_damage_from(u, o,
			battle._damage._magic_after_mr(u, float(o["maxHp"]) * ReserveConsts.MAXHP_PCT, o), Color("#6ab8ff"))
