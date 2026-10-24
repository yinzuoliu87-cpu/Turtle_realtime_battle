extends Node
## _shot_slam_video.gd —— 小龟过肩摔录像(2026-10-24, 探针不进门禁; 方案书 docs/plans/20261024-过肩摔重做.md)。
## 用户「全部搞好把视频给我看」。审阅台真场景: 每一幕由本脚本摆位(小龟与主目标拉开、两个旁人在目标附近)、
##   把过肩摔冷却设成马上就绪、镜头拉近对准, 然后让战斗自己放(走真入口: 前摇 → `_do_skill` → 冲刺 → 抱起 → 跳高 → 落地)。
## 跑法(窗口只开右屏·静音; Movie Maker 每帧 = 固定 1/fps 秒游戏时间):
##   REVIEW=1 REVIEW_TURTLE=basic REVIEW_SKILL=3 APPDATA=<单独目录> XDG_DATA_HOME=<单独目录> WINDOW=1 \
##   bash godot-quiet.sh --position 2000,80 --resolution 1560x720 --write-movie <帧目录>/f.png --fixed-fps 60 \
##   res://tests/_shot_slam_video.tscn
## 输出: 控制台打「[VID] 第 N 幕 start/end 帧号」(剪片用)。

## 每一幕: 小龟位置 / 主目标位置(相对场地中心, 码) / 镜头缩放。
const SCENES := [
	{"u": Vector2(-230, 120), "t": Vector2(110, 120), "zoom": 1.9},
	{"u": Vector2(200, 60), "t": Vector2(-110, 200), "zoom": 1.8},
]
const LEAD_FRAMES := 40
## 开场先等这么多帧再摆第一幕: 大师开场头几帧就甩钩, 钩中要拽好几秒, 链子横穿全场(不是过肩摔的)。
const WARMUP := 360
const TAIL_FRAMES := 80
const MAX_WAIT := 600

var scn


func _ready() -> void:
	await get_tree().process_frame
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	for _i in range(WARMUP):
		await get_tree().process_frame
		for uu in scn._units:   # 训龟大师一上场就关掉主动技(钩链挂上之后要好几秒才褪, 摆位时再关就晚了)
			if uu.get("is_trainer", false):
				uu["_tr_active"] = ""
	var f := WARMUP
	for k in range(SCENES.size()):
		var sc: Dictionary = SCENES[k]
		var caster = _caster()
		var foes: Array = _foes()
		if caster == null or foes.size() < 3:
			print("[VID] 场上单位不够: caster=%s foes=%d" % [str(caster != null), foes.size()])
			break
		var c: Vector2 = scn.ARENA.position + scn.ARENA.size * 0.5
		var up: Vector2 = c + sc["u"]
		var tp: Vector2 = c + sc["t"]
		var dn: Vector2 = (tp - up).normalized()
		var side := Vector2(-dn.y, dn.x)
		## 场边训龟大师的钩锁会在画面上拉几条横穿全场的链子(不是过肩摔的) ⇒ 录像里关掉主动技、清掉已挂上的钩
		for uu in scn._units:
			if uu.get("is_trainer", false):
				uu["_tr_active"] = ""
			uu["_hook_pull_until"] = 0.0
		caster["pos"] = up
		caster["hp"] = caster["maxHp"]
		foes[0]["pos"] = tp
		foes[1]["pos"] = tp + dn * 40.0 + side * 120.0
		foes[2]["pos"] = tp + dn * 40.0 - side * 120.0
		for fo in foes:
			fo["hp"] = fo["maxHp"]
			fo["stun_until"] = 0.0
		var cds: Dictionary = caster.get("skill_cd", {})
		for st in cds.keys():
			cds[st] = 99.0
		cds["basicSlam"] = 0.5
		var mid: Vector2 = (up + tp) * 0.5
		scn._cam_zoom = float(sc["zoom"])
		scn._cam_pan = Vector3((mid.x - c.x) * scn.WS, 0.0, (mid.y - c.y) * scn.WS * 0.6)
		scn._apply_cam_zoom()
		print("[VID] 第 %d 幕 摆位 frame %d 距离 %.0f 码" % [k + 1, f, up.distance_to(tp)])
		var started := -1
		var ended := -1
		var w := 0
		while w < MAX_WAIT:
			await get_tree().process_frame
			f += 1
			w += 1
			var on := bool(caster.get("_slam", false))
			if on and started < 0:
				started = f
				print("[VID] 第 %d 幕 start frame %d 目标 knock_immune=%s cc免控=%s _slam=%s airborne=%s egg=%s" % [k + 1, f,
					str(foes[0].get("_knock_immune", false)), str(scn._t < float(foes[0].get("cc_immune_until", 0.0))),
					str(foes[0].get("_slam", false)), str(foes[0].get("airborne", false)), str(foes[0].get("_eggImmune", false))])
			if started > 0 and not on and ended < 0:
				ended = f
				print("[VID] 第 %d 幕 end frame %d phase=%s" % [k + 1, f, str(scn._basic_slam_sys.last_phase)])
			if ended > 0 and f >= ended + TAIL_FRAMES:
				break
	print("[VID] total frames %d" % f)
	get_tree().quit()


func _caster():
	for u in scn._units:
		if str(u.get("id", "")) == "basic" and str(u.get("side", "")) == "left" and u.get("alive", false):
			return u
	return null


func _foes() -> Array:
	var out: Array = []
	for u in scn._units:
		if str(u.get("side", "")) == "right" and u.get("alive", false) and not u.get("is_trainer", false) and not u.get("is_summon", false):
			out.append(u)
	return out
