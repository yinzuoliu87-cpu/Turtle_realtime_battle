extends Node
## 录像探针(不进门禁; 11-11 近战小将珊瑚骑士新动作实录给用户看): 空场地只放近战小将 + 一只不还手的石头龟,
##   小将自己跑过去普攻 → 第 SKILL_F 帧放人体浪板 → 落地后接着砍。镜头框住两者中点, 小将离地越高取景越往上(跳 5.76 米不出画)。
## 跑法(屏幕外静音窗口, 每帧 = 1/60 秒游戏时间):
##   APPDATA=$U XDG_DATA_HOME=$U TURTLE_SUPABASE=" " WINDOW=1 bash godot-quiet.sh --rendering-driver opengl3 --resolution 1280x720
##     --position 5000,5000 --write-movie .out/rec/melee.avi --fixed-fps 60 res://tests/probes/_rec_melee_minion.tscn
## 环境: REC_ZOOM(默认 2.6) REC_GAP(起始距离码, 默认 420) REC_FRAMES(默认 720) REC_SKILL_F(默认 330)
##   打印 [EVT] 动作切换(帧号 / 动作 / 高度), 对照时间轴用。

var s
var f := 0
var mn = null
var foe = null
var last := ""
var cam_up := 0.0
var cam_zoom_now := 3.0
var zoom := 2.6
var skill_f := 330
var end_f := 720


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	zoom = float(OS.get_environment("REC_ZOOM")) if OS.has_environment("REC_ZOOM") else 3.0
	cam_zoom_now = zoom
	skill_f = int(OS.get_environment("REC_SKILL_F")) if OS.has_environment("REC_SKILL_F") else 330
	end_f = int(OS.get_environment("REC_FRAMES")) if OS.has_environment("REC_FRAMES") else 720
	var gap: float = float(OS.get_environment("REC_GAP")) if OS.has_environment("REC_GAP") else 420.0
	s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for _i in range(6):
		await get_tree().process_frame
	s._deterministic = true
	for u in s._units.duplicate():
		_purge(u)
	var ar: Rect2 = s.ARENA
	var c: Vector2 = ar.position + ar.size * 0.5
	mn = s._spawn._make_unit("__minion__", "left", c + Vector2(-gap * 0.5, 0.0), {"minion": true, "role": "front", "level": 6})
	## 目标用普通龟: 石头龟有反伤被动, 血堆到 90 万时接触那一下(目标最大生命 10%)反弹回来直接把小将弹死(11-11 第二版踩过)
	foe = s._spawn._make_unit("basic", "right", c + Vector2(gap * 0.5, 0.0), {})
	foe["maxHp"] = 30000.0; foe["hp"] = 30000.0
	foe["no_basic"] = true; foe["no_move"] = true; foe["move_spd"] = 0.0
	foe["active_skills"] = []
	## (不设不可选中: 结束判定会把它当「不计胜负」的单位, 第一下伤害就判负 —— 11-11 录第一版踩过)
	s._units.append(mn)
	s._units.append(foe)


## 场上原有单位整个拿掉(不播阵亡, 免得画面里有别的东西)
func _purge(u: Dictionary) -> void:
	for k in ["sprite", "shadow", "ring", "contact", "bar_root"]:
		var n = u.get(k, null)
		if n is Node and is_instance_valid(n):
			(n as Node).queue_free()
	u["alive"] = false
	s._units.erase(u)


func _process(_d: float) -> void:
	if mn == null:
		return
	f += 1
	## 两侧队伍栏还挂着开场被清掉的默认龟(画面里会误导), 录像时藏掉; 顶栏 / 血条 / 伤害数字留着
	for k in ["_team_panel_left", "_team_panel_right"]:
		var tp = s.get(k)
		if tp is CanvasItem and is_instance_valid(tp):
			(tp as CanvasItem).visible = false
	if f < skill_f:
		mn["energy"] = 0.0                       # 技能在指定帧放(不让 AI 提前攒满)
	if f == skill_f:
		print("[EVT] %d 放人体浪板" % f)
		mn["energy"] = 0.0
		s._hiding_sys._sk_minion_bodysurf(mn, foe)
	var spr = mn.get("sprite", null)
	var file := "-"
	if spr is Sprite3D and is_instance_valid(spr) and (spr as Sprite3D).texture != null:
		file = (spr as Sprite3D).texture.resource_path.get_file()
	var act := "%s/%s" % [str(mn.get("anim_action", "")), file]
	if act != last:
		print("[EVT] %d 动作 %s h=%.2f" % [f, act, float(mn.get("height", 0.0))])
		last = act
	## 镜头: 两者中点; 离地高度的一半往「屏幕上方」挪(平滑), 跳到顶也框得住
	var ar: Rect2 = s.ARENA
	var cc: Vector2 = ar.position + ar.size * 0.5
	var p: Vector2 = ((mn["pos"] as Vector2) + (foe["pos"] as Vector2)) * 0.5
	## 第一版(取景上移 = 高度 × 0.55, 定倍 2.6): 跳到顶时头贴着画面上边 ⇒ 上移加到 0.85, 离地越高越往回拉(5.76 米时约 0.7 倍)
	var hh: float = float(mn.get("height", 0.0))
	var want_up: float = hh * 0.85
	cam_up += (want_up - cam_up) * 0.12
	cam_zoom_now += (zoom * (1.0 - 0.055 * hh) - cam_zoom_now) * 0.12
	s._cam_zoom = cam_zoom_now
	s._cam_pan = Vector3((p.x - cc.x) * s.WS, 0.0, (p.y - cc.y) * s.WS * 0.6 - cam_up)
	s._apply_cam_zoom()
	if f > skill_f - 5 and (f % 10 == 0 or (f > 425 and f < 445)):
		print("[POS] %d mn=(%.0f,%.0f) h=%.2f foe=(%.0f,%.0f) over=%s slam=%s t=%.2f mn_alive=%s foe_alive=%s foe_hp=%.0f mn_hp=%.0f" % [f, (mn["pos"] as Vector2).x, (mn["pos"] as Vector2).y, float(mn.get("height", 0.0)), (foe["pos"] as Vector2).x, (foe["pos"] as Vector2).y, str(s._over), str(mn.get("_slam", false)), float(s._t), str(mn.get("alive", false)), str(foe.get("alive", false)), float(foe.get("hp", 0.0)), float(mn.get("hp", 0.0))])
	if f >= end_f:
		get_tree().quit()
