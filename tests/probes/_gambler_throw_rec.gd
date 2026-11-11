extends Node
## 赌神普攻出牌录像探针(11-10 用户「它什么动作到哪一帧的时候，它手上的牌才发出去，然后这一帧是否适合？」; 不进门禁)。
## 审阅台真场景(REVIEW=1 REVIEW_TURTLE=gambler): 赌神对假人只打普攻(技能冷却每帧压住), 镜头拉近对准赌神。
## 每帧打印: [ATK] 帧号 动作帧下标 / 飞牌屏幕坐标与缩放 / 按 _gambler_card_from 算出的手上牌屏幕坐标 —— 量出手那一帧牌是不是从手上出去的。
## 跑法(窗口只开右屏·静音; Movie Maker 每帧 = 固定 1/fps 秒游戏时间):
##   REVIEW=1 REVIEW_TURTLE=gambler REVIEW_SKILL=0 APPDATA=<单独目录> XDG_DATA_HOME=<单独目录> TURTLE_SUPABASE=" " WINDOW=1 \
##   bash godot-quiet.sh --position 2000,80 --resolution 1280x720 --write-movie .out/gambler/rec/f.png --fixed-fps 60 \
##   res://tests/probes/_gambler_throw_rec.tscn
const WARMUP := 90
const REC := 600
const ZOOM := 2.6

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
		if str(o.get("id", "")) == "gambler" and str(o.get("side", "")) == "left":
			u = o
			break
	if u == null:
		return
	var cds: Dictionary = u.get("skill_cd", {})
	for k in cds.keys():
		cds[k] = 99.0
	u["energy"] = 0.0
	if f == WARMUP:
		var c: Vector2 = sc.ARENA.position + sc.ARENA.size * 0.5
		var p: Vector2 = u["pos"]
		sc._cam_zoom = ZOOM
		sc._cam_pan = Vector3((p.x - c.x) * sc.WS, 0.0, (p.y - c.y) * sc.WS * 0.6)
		sc._apply_cam_zoom()
		placed = true
		print("[REC] start frame %d" % f)
	if not placed:
		return
	var cam = sc._cam
	var sd: Dictionary = u.get("anim_sd", {})
	var ai: int = int(float(u.get("anim_t", 0.0)) * float(sd.get("fps", 0.0)))
	var line := "[ATK] %d act=%s fi=%d fps=%.1f flip=%s st=%s pend=%s st_t=%.2f cd=%.2f wind=%s multi=%d" % [f, str(u.get("anim_action", "")), ai, float(sd.get("fps", 0.0)), str((u["sprite"] as Sprite3D).flip_h),
		str(u.get("state", "")), str(u.get("pending", "")), float(u.get("state_t", 0.0)), float(u.get("atk_cd", 0.0)), str(u.get("_atk_wind", false)), int(u.get("_multi_n", 0))]
	var hand: Vector3 = sc._ballistics._gambler_card_from(u, Vector3(-999, -999, -999))
	if hand.x > -998.0:
		var hs: Vector2 = cam.unproject_position(hand)
		line += " hand=(%d,%d)" % [int(hs.x), int(hs.y)]
	for pr in sc._projectiles:
		if pr.get("card_spin", false) and is_instance_valid(pr["node"]):
			var n: Node3D = pr["node"]
			var ps: Vector2 = cam.unproject_position(n.global_position)
			line += " card=(%d,%d) t=%.3f s=%.2f hand=%s" % [int(ps.x), int(ps.y), float(pr["t"]), n.global_transform.basis.get_scale().x, str(pr.get("card_hand", false))]
	print(line)
	if f >= WARMUP + REC:
		get_tree().quit()
