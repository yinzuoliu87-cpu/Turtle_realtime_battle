extends Node
## 审阅台跟拍录像探针(不进门禁; 11-11 录小将铁链 / 忍者用): 镜头跟住左队第一个单位(REC_MID=1 跟它与对手的中点), REC_ZOOM 倍, REC_FRAMES 帧后退出;
##   打印 [EVT] 动作切换 / 放技能 / 铁锁出手、[POS] 每 6 帧位置。跑法: REVIEW=1 REVIEW_TURTLE=<id|minion|elite> + 隔离存档 + WINDOW=1 godot-quiet.sh --write-movie … res://tests/probes/_unit_follow_rec.tscn
var sc: Node = null
var f := 0
var last_cd := {}
var last_act := ""
var last_whip := -1.0
const WARMUP := 60


func _ready() -> void:
	sc = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(sc)


func _process(_d: float) -> void:
	f += 1
	if sc == null or not ("_units" in sc):
		return
	var u = null
	for o in sc._units:
		if str(o.get("side", "")) == "left" and o.get("alive", false) and not o.get("is_trainer", false) and not o.get("is_summon", false):
			u = o
			break
	if u == null:
		return
	var zoom := float(OS.get_environment("REC_ZOOM")) if OS.has_environment("REC_ZOOM") else 2.2
	if f >= WARMUP:
		var c: Vector2 = sc.ARENA.position + sc.ARENA.size * 0.5
		var p: Vector2 = u["pos"]
		var foe = null
		for o in sc._units:
			if str(o.get("side", "")) == "right" and o.get("alive", false) and not o.get("is_trainer", false):
				foe = o
				break
		if foe != null and OS.get_environment("REC_MID") == "1":
			p = (p + (foe["pos"] as Vector2)) * 0.5
		sc._cam_zoom = zoom
		sc._cam_pan = Vector3((p.x - c.x) * sc.WS, 0.0, (p.y - c.y) * sc.WS * 0.6)
		sc._apply_cam_zoom()
	var spr = u.get("sprite", null)
	var file := "-"
	if spr is Sprite3D and is_instance_valid(spr) and (spr as Sprite3D).texture != null:
		file = (spr as Sprite3D).texture.resource_path.get_file()
	var act := "%s/%s" % [str(u.get("anim_action", "")), file]
	if act != last_act:
		print("[EVT] %d 动作 %s h=%.2f" % [f, act, float(u.get("height", 0.0))])
		last_act = act
	var cds: Dictionary = u.get("skill_cd", {})
	for k in cds:
		var v := float(cds[k])
		if last_cd.has(k) and v > float(last_cd[k]) + 0.5:
			print("[EVT] %d 放技能 %s" % [f, str(k)])
		last_cd[k] = v
	var wc := float(u.get("_whip_cd", -1.0))
	if wc != last_whip and wc > 0.0:
		print("[EVT] %d 铁锁出手" % f)
	last_whip = wc
	if f % 6 == 0:
		print("[POS] %d %.1f %.1f h=%.2f slam=%s" % [f, (u["pos"] as Vector2).x, (u["pos"] as Vector2).y, float(u.get("height", 0.0)), str(u.get("_slam", false))])
	if f >= int(OS.get_environment("REC_FRAMES")) if OS.has_environment("REC_FRAMES") else 900:
		get_tree().quit()
