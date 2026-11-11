extends Node
## 审阅台普攻录像探针(不进门禁): 11-10 赌神出牌、11-11 忍者普攻重画(build_ninja_slash.py)都用它录。
## 审阅台真场景(REVIEW=1 REVIEW_TURTLE=gambler): 赌神对假人只打普攻(技能冷却每帧压住), 镜头拉近对准赌神。
## 每帧打印: [ATK] 帧号 动作帧下标 / 飞牌屏幕坐标与缩放 / 按 _gambler_card_from 算出的手上牌屏幕坐标 —— 量出手那一帧牌是不是从手上出去的。
## 跑法(窗口只开右屏·静音; Movie Maker 每帧 = 固定 1/fps 秒游戏时间):
##   REVIEW=1 REVIEW_TURTLE=gambler REVIEW_SKILL=0 APPDATA=<单独目录> XDG_DATA_HOME=<单独目录> TURTLE_SUPABASE=" " WINDOW=1 \
##   bash godot-quiet.sh --position 2000,80 --resolution 1280x720 --write-movie .out/gambler/rec/f.png --fixed-fps 60 \
##   res://tests/probes/_rec_review_attack.tscn
const WARMUP := 90
const REC := 720
const ZOOM := 3.6

var sc: Node = null
var f := 0
var placed := false


func _ready() -> void:
	sc = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(sc)


func _process(_d: float) -> void:
	f += 1
	if sc == null or not ("_units" in sc):
		return
	var u = null
	for o in sc._units:
		if str(o.get("id", "")) == (OS.get_environment("REVIEW_TURTLE") if OS.has_environment("REVIEW_TURTLE") else "ninja") and str(o.get("side", "")) == "left":
			u = o
			break
	if u == null:
		return
	if f >= WARMUP:
		var c: Vector2 = sc.ARENA.position + sc.ARENA.size * 0.5
		var p: Vector2 = u["pos"]
		var foe = null
		for o in sc._units:
			if str(o.get("side", "")) == "right" and o.get("alive", false) and not o.get("is_trainer", false):
				foe = o
				break
		sc._cam_zoom = ZOOM
		sc._cam_pan = Vector3((p.x - c.x) * sc.WS, 0.0, (p.y - c.y) * sc.WS * 0.6)
		sc._apply_cam_zoom()
		if not placed:
			print("[REC] start frame %d" % f)
		placed = true
	if not placed:
		return
	var cam = sc._cam
	var sd: Dictionary = u.get("anim_sd", {})
	var ai: int = int(float(u.get("anim_t", 0.0)) * float(sd.get("fps", 0.0)))
	var line := "[ATK] %d act=%s fi=%d fps=%.1f flip=%s st=%s pend=%s st_t=%.2f cd=%.2f wind=%s multi=%d" % [f, str(u.get("anim_action", "")), ai, float(sd.get("fps", 0.0)), str((u["sprite"] as Sprite3D).flip_h),
		str(u.get("state", "")), str(u.get("pending", "")), float(u.get("state_t", 0.0)), float(u.get("atk_cd", 0.0)), str(u.get("_atk_wind", false)), int(u.get("_multi_n", 0))]
	var spr: Sprite3D = u["sprite"]
	line += " file=%s frame=%d glide=%s" % [spr.texture.resource_path.get_file() if spr.texture != null else "-", spr.frame, str(u.get("_ninja_gliding", false))]
	print(line)
	if f >= WARMUP + REC:
		get_tree().quit()
