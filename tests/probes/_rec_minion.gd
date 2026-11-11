extends Node
## 录像探针(不进门禁; 11-11 三种小将重做实录): 空场地只放一只小将 + 一只不还手的普通龟, 按脚本依次触发各招,
##   镜头框住两者中点, 离地越高取景越往上。REC_KIND = back(远程) / elite(精英); 近战用 _rec_melee_minion.tscn。
## 跑法: APPDATA=$U XDG_DATA_HOME=$U TURTLE_SUPABASE=" " NOVERDICT=1 REC_KIND=elite WINDOW=1 bash godot-quiet.sh --rendering-driver opengl3
##   --resolution 1600x900 --position 5000,5000 --write-movie .out/rec/x.avi --fixed-fps 60 res://tests/probes/_rec_minion.tscn
##   (目标用普通龟: 石头龟有反伤, 血堆高了接触那一下会把小将弹死; 小将不设不可选中: 结束判定会把它当不计胜负的单位)

const SkillForms := preload("res://scripts/gamedata/skill_forms.gd")   # 不是全局类名(技能脚本里各自 preload)

var s
var f := 0
var mn = null
var foe = null
var kind := "back"
var last := ""
var cam_up := 0.0
var cam_zoom_now := 3.0
var end_f := 600


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	kind = OS.get_environment("REC_KIND") if OS.has_environment("REC_KIND") else "back"
	s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for _i in range(6):
		await get_tree().process_frame
	s._deterministic = true
	for u in s._units.duplicate():
		_purge(u)
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var gap: float = 560.0 if kind == "back" else 280.0
	var spec := {"minion": true, "role": "back", "level": 6} if kind == "back" else {"minion": true, "elite": true, "level": 6}
	mn = s._spawn._make_unit("__minion__", "left", c + Vector2(-gap * 0.5, 0.0), spec)
	## 精英: 目标往镜头那侧挪 90 码 —— 铁锁把精英拉到目标身后, 同一行的话之后每招都被龟身挡住(第一版录像 112 / 125 / 545 帧几乎看不到人)
	foe = s._spawn._make_unit("basic", "right", c + Vector2(gap * 0.5, 90.0 if kind == "elite" else 0.0), {})
	foe["maxHp"] = 30000.0; foe["hp"] = 30000.0
	foe["no_basic"] = true; foe["no_move"] = true; foe["move_spd"] = 0.0
	foe["active_skills"] = []
	if kind == "elite":
		mn["_whip_cd"] = float(s._t) + 1.0      # 第 1 秒甩铁锁(距离 280 在 150 ~ 350 之间)
		end_f = 900
	else:
		end_f = 560
	s._units.append(mn)
	s._units.append(foe)


func _purge(u: Dictionary) -> void:
	for k in ["sprite", "shadow", "ring", "contact", "bar_root"]:
		var n = u.get(k, null)
		if n is Node and is_instance_valid(n):
			(n as Node).queue_free()
	u["alive"] = false
	s._units.erase(u)


func _evt(t: String) -> void:
	print("[EVT] %d %s" % [f, t])


func _process(_d: float) -> void:
	if mn == null:
		return
	f += 1
	for k in ["_team_panel_left", "_team_panel_right"]:
		var tp = s.get(k)
		if tp is CanvasItem and is_instance_valid(tp):
			(tp as CanvasItem).visible = false
	mn["energy"] = 0.0
	if kind == "back" and f == 330:
		_evt("放追踪火箭筒")
		s._hiding_sys._sk_minion_rocket(mn, foe)
	if kind == "elite":
		if f == 470:
			_evt("旋刃")
			s._elite_sys._elite_whirl(mn)
		if f == 540:
			_evt("铁锤")
			s._elite_sys._sk_elite_hammer(mn, foe)
		if f == 640:
			_evt("大跳铁锤")
			SkillForms.pin_form(mn, "eliteHammer", 1)
			s._elite_sys._sk_elite_hammer(mn, foe)
			SkillForms.unpin_form(mn, "eliteHammer")
		if f == 790:
			_evt("目标压到 10% 血 → 吞噬")
			foe["hp"] = float(foe["maxHp"]) * 0.10
			s._elite_sys._elite_try_consume(mn, foe)
	var spr = mn.get("sprite", null)
	var file := "-"
	if spr is Sprite3D and is_instance_valid(spr) and (spr as Sprite3D).texture != null:
		file = (spr as Sprite3D).texture.resource_path.get_file()
	var act := "%s/%s" % [str(mn.get("anim_action", "")), file]
	if act != last:
		_evt("动作 %s h=%.2f" % [act, float(mn.get("height", 0.0))])
		last = act
	var cc: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var p: Vector2 = ((mn["pos"] as Vector2) + (foe["pos"] as Vector2)) * 0.5
	if kind == "back":   # 远程隔 400 码, 中点取景人太小(第二版录像看不清前压 / 后坐) ⇒ 镜头跟住小将、往目标方向偏 130 码
		p = (mn["pos"] as Vector2) + DetMath.norm((foe["pos"] as Vector2) - (mn["pos"] as Vector2)) * 130.0
	var hh: float = float(mn.get("height", 0.0))
	cam_up += (hh * 0.85 - cam_up) * 0.12
	var zoom: float = 3.6 if kind == "back" else 3.2
	cam_zoom_now += (zoom * (1.0 - 0.055 * hh) - cam_zoom_now) * 0.12
	## 游戏镜头倍数上限 CAM_ZOOM_MAX = 2.3(_apply_cam_zoom 会夹住); 录像要看清动作 ⇒ 绕过上限直接摆镜头(只在探针里)
	s._cam_pan = Vector3((p.x - cc.x) * s.WS, 0.0, (p.y - cc.y) * s.WS * 0.6 - cam_up)
	var anchor: Vector3 = s.CAM_TARGET + s._cam_pan
	s._cam_zoom = cam_zoom_now
	s._cam_zoom_base = anchor + (s._cam_base - s.CAM_TARGET) / cam_zoom_now
	if s._cam != null and is_instance_valid(s._cam):
		s._cam.position = s._cam_zoom_base
	if f >= end_f:
		get_tree().quit()
