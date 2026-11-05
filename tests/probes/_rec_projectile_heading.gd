extends Node
## 录像(2026-11-05 用户「它飞的方向和它的这个头就偏离了一定的角度，包括远程小将的火箭筒技能也是」): 改完后的实机画面。
##   审阅台画面(REVIEW=1 REVIEW_TURTLE=basic REVIEW_SKILL=0 NOVERDICT=1), 把发射者与目标摆到画面边上、飞得长、目标横走
##   ⇒ 尖头与飞行方向最容易看出偏差的情形。
##   ① 第 20 帧: 小龟在左下放龟派气波, 目标在右上往下走(聚气 0.6 秒里贴图跟着转、发射时瞄目标当前位置)
##   ② 第 125 帧: 小龟在右上向左下放气波, 目标往右走
##   ③ 第 230 帧: 远程小将的追踪火箭从左上打向右下往上走的目标(弹道拐弯, 机头全程领飞)
##   ④ 第 365 帧: 追踪火箭从右下打向左上往右走的目标
## 用法: NOVERDICT=1 REVIEW=1 REVIEW_TURTLE=basic REVIEW_SKILL=0 <godot> --path . --write-movie .out/heading_rec/demo.avi --fixed-fps 30 --quit-after 520 res://tests/probes/_rec_projectile_heading.tscn
var sc: Node = null
var f := 0
var tgt: Dictionary = {}
var vel := Vector2.ZERO
var shooter: Dictionary = {}
var minion: Dictionary = {}


func _ready() -> void:
	sc = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(sc)


func _c() -> Vector2:
	return sc.ARENA.position + sc.ARENA.size * 0.5


func _quiet_all() -> void:
	for u in sc._units:
		u["no_move"] = true
		u["no_basic"] = true
		u["active_skills"] = []
		u["energy"] = 0.0


func _put(u: Dictionary, p: Vector2) -> void:
	u["pos"] = _c() + p
	u.erase("_home_pos")


func _setup(sp: Vector2, tp: Vector2, v: Vector2, park: Array) -> void:
	_quiet_all()
	var rights: Array = sc._units.filter(func(x): return str(x.get("side", "")) == "right" and x.get("alive", false) and not sc._is_untouchable(x))
	tgt = rights[0]
	_put(tgt, tp)
	vel = v
	for i in range(1, rights.size()):
		_put(rights[i], park[(i - 1) % park.size()])
	if not shooter.is_empty():
		_put(shooter, sp)


func _process(_d: float) -> void:
	if sc == null or not ("_units" in sc) or sc._units.is_empty():
		return
	f += 1
	if not tgt.is_empty():
		tgt["pos"] = tgt["pos"] + vel / 30.0
	if shooter.is_empty():
		for u in sc._units:
			if str(u.get("id", "")) == "basic" and str(u.get("side", "")) == "left":
				shooter = u
	match f:
		20:
			_setup(Vector2(-650, 230), Vector2(550, -250), Vector2(0, 120), [Vector2(600, 300), Vector2(420, 330)])
			sc._sk_basic_chiwave(shooter, tgt)
		125:
			_setup(Vector2(600, -260), Vector2(-600, 230), Vector2(140, 0), [Vector2(-520, -300), Vector2(560, 300)])
			sc._sk_basic_chiwave(shooter, tgt)
		230:
			minion = sc._spawn._make_unit("__minion__", "left", _c() + Vector2(-680, -250), {"minion": true, "role": "back", "level": 6})
			sc._units.append(minion)
			_setup(Vector2(-560, 320), Vector2(560, 240), Vector2(0, -110), [Vector2(620, -300), Vector2(-100, 340)])
			sc._hiding_sys._minion_rocket_fly(minion, tgt, minion["pos"])
		365:
			_setup(Vector2(-560, 320), Vector2(-620, -230), Vector2(130, 0), [Vector2(-640, 300), Vector2(100, -330)])
			_put(minion, Vector2(640, 250))
			sc._hiding_sys._minion_rocket_fly(minion, tgt, minion["pos"])
