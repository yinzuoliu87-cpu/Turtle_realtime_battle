extends Node
## 043 海浪护符·真对局录屏台(不是门禁, 2026-11-14 浪墙重做用; 方案书 docs/plans/20261114-海浪护符浪墙重做.md)。
## 真战斗场、默认镜头、两队照常开打; 开打第 2 帧给我方(左)第一只龟塞一件 043(REC_STAR 星),
##   第 REC_MANA_AT 秒用法力系统自己的入口 `add_mana` 灌满 ⇒ 走真入口涌浪(不是直接调演出)。
## 录 REC_SECS 秒后自己 quit; [REC] 行打涌浪时刻与浪墙节点数。
##
## 跑法(窗口只开右屏、静音):
##   SHIP=1 APPDATA=<单独目录> XDG_DATA_HOME=<同一目录> WINDOW=1 bash godot-quiet.sh --position 2000,80 \
##     --resolution 1560x720 --write-movie <输出>/wave.avi --fixed-fps 60 --quit-after 1500 res://tests/_rec_wave_ingame.tscn
## 可选: REC_SECS(默认 9) · REC_STAR(默认 3) · REC_MANA_AT(默认 3.0 秒)
##   REC_ONLY_FX=1: 只看海浪的特效(用户 11-14「只留下海浪相关的特效，把场地什么的无关因素…全部都不要」) ——
##     对局照常跑(浪打在同样的时刻、同样的位置), 但每帧把 `_world` 里不是浪墙 / 召浪 / 打中水花的东西都藏掉,
##     界面层(CanvasLayer: 血条、飘字、HUD、海底背景)全藏, 底色换成纯深色。

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"

var _scn = null
var _el := 0.0
var _secs := 9.0
var _mana_at := 3.0
var _armed := false
var _kicked := false
var _carrier = null
var _walls_max := 0


func _ready() -> void:
	await get_tree().process_frame
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	if OS.has_environment("REC_SECS"):
		_secs = float(OS.get_environment("REC_SECS"))
	if OS.has_environment("REC_MANA_AT"):
		_mana_at = float(OS.get_environment("REC_MANA_AT"))
	var star: int = int(OS.get_environment("REC_STAR")) if OS.has_environment("REC_STAR") else 3
	_scn = load(BATTLE_SCENE).instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame
	for u in _scn._units:
		if u is Dictionary and str(u.get("side", "")) == "left" and u.get("alive", false) \
				and not u.get("is_trainer", false) and not u.get("is_summon", false):
			_carrier = u
			break
	if _carrier == null:
		print("REC FAIL: 左方没有能带装备的龟")
		get_tree().quit(1)
		return
	var eqs: Array = (_carrier.get("equips", []) as Array).duplicate()
	eqs.append({"id": "p2eq_043", "star": star})
	_carrier["equips"] = eqs
	_scn._synergy.clear()
	_scn._synergy.apply_all()
	print("[REC] 带 043(%d 星)的龟 %s" % [star, str(_carrier.get("id", "?"))])
	## REC_BIGNUM=1: 飘出 7 位数以上的数字时打印调用栈(11-14 录像里出现过一次白色暴击 1000107, 追来源)
	if OS.get_environment("REC_BIGNUM") == "1":
		get_tree().node_added.connect(func(nd: Node) -> void:
			var tx: String = str(nd.get("text")) if (nd is Label3D or nd is Label) else ""
			var digits: String = tx.replace("+", "").replace("-", "").strip_edges()
			if digits.length() >= 7 and digits.is_valid_int():
				print("[BIG] %.2f 秒 %s" % [_el, tx])
				for fr in get_stack():
					print("    ", fr))
	_armed = true


## 是不是海浪护符自己的特效节点: 浪墙(材质是 tide_wall 着色器)/ 召浪、打中水花(贴图 tide-cast / tide-hit)
func _is_tide(n: Node) -> bool:
	if n is MeshInstance3D:
		var m = (n as MeshInstance3D).material_override
		return m is ShaderMaterial and (m as ShaderMaterial).shader != null \
			and str((m as ShaderMaterial).shader.resource_path).ends_with("tide_wall.gdshader")
	if n is Sprite3D:
		var tx = (n as Sprite3D).texture
		return tx != null and str(tx.resource_path).get_file().begins_with("tide-")
	return false


func _only_fx() -> void:
	RenderingServer.set_default_clear_color(Color(0.04, 0.06, 0.09))
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		## 3D 画面是渲进 SubViewport 再贴在「WorldLayer」这一层上显示的(battle_world_builder `_build_viewport`) ⇒ 这一层留着
		if str(n.name) != "WorldLayer":
			(n as CanvasLayer).visible = false
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (n as WorldEnvironment).environment
		if env != null:
			env.background_mode = Environment.BG_CLEAR_COLOR
	## 3D 视口里所有画东西的节点(含挂得深的: 单位立绘下面的技能扇形、瞄准线、飘字 Label3D …)逐个过: 不是海浪的就藏
	for c in _scn._sub.find_children("*", "VisualInstance3D", true, false):
		if (c as Node3D).visible and not _is_tide(c) and not (c is Light3D):
			(c as Node3D).visible = false
	## 2D 叠层: 视口里的 2D 节点、WorldLayer 上除「显示 3D 的那个容器」以外的 2D(技能扇形 / 瞄准线是画在这里的)
	for c in _scn._sub.find_children("*", "CanvasItem", true, false):
		(c as CanvasItem).visible = false
	for wl in get_tree().root.find_children("WorldLayer", "CanvasLayer", true, false):
		for c in wl.get_children():
			if c is CanvasItem and not (c is SubViewportContainer):
				(c as CanvasItem).visible = false


func _process(delta: float) -> void:
	if not _armed:
		return
	## ★只看特效: 挂在「每帧开画之前」藏 —— 放在 _process 里会被战斗场同一帧的更新(每帧重建的线 / 自己把 visible 设回 true 的演出)盖回去
	if OS.get_environment("REC_ONLY_FX") == "1" and not RenderingServer.frame_pre_draw.is_connected(_only_fx):
		RenderingServer.frame_pre_draw.connect(_only_fx)
	_el += delta
	if not _kicked and _el >= _mana_at:
		_kicked = true
		## REC_DIR=<度>: 放浪前把携带者挪到场地中央、敌人摆到那个方向 ⇒ 浪朝那个方向推(看各方向的浪; 用户 11-14「各种方向的海浪都给我看看」)
		##   2D 坐标 y 朝下 = 朝镜头: 0 →, 90 ↓(朝镜头), 180 ←, 270 ↑(背镜头)
		if OS.has_environment("REC_DIR"):
			var ang: float = deg_to_rad(float(OS.get_environment("REC_DIR")))
			var dv := Vector2(cos(ang), sin(ang))
			var pv := dv.orthogonal()
			var cc: Vector2 = _scn._arena_center
			_carrier["pos"] = cc - dv * 150.0
			var k := 0
			for uu in _scn._units:
				if uu is Dictionary and str(uu.get("side", "")) == "right" and uu.get("alive", false) and not uu.get("is_trainer", false):
					uu["pos"] = cc + dv * 250.0 + pv * (float(k % 4) - 1.5) * 70.0 + dv * float(k / 4) * 60.0
					k += 1
			print("[REC] 方向 %s 度: 携带者挪到中央, %d 个敌人摆到这个方向" % [OS.get_environment("REC_DIR"), k])
		_scn._staff_syn.add_mana(_carrier, 99999.0)
		print("[REC] %.2f 秒 灌满法力" % _el)
	## REC_BIGNUM=1: 谁的累计输出一帧之内涨了 10 万以上 ⇒ 打印是谁、带什么、第几秒(追 11-14 录像里的白色暴击 1000107)
	if OS.get_environment("REC_BIGNUM") == "1":
		for uu in _scn._units:
			if not (uu is Dictionary):
				continue
			var dd: float = float(uu.get("dmg_dealt", 0.0))
			var prev: float = float(uu.get("_rec_dd", 0.0))
			if dd - prev > 100000.0:
				var eqn: Array = []
				for e in uu.get("equips", []):
					eqn.append(str(e.get("id", "")) if e is Dictionary else str(e))
				print("[BIGDMG] %.2f 秒 %s(%s) 一帧输出 +%.0f · 装备 %s · 技能 %s" % [_el, str(uu.get("id", "?")), str(uu.get("side", "?")), dd - prev, str(eqn), str(uu.get("active_skills", []))])
			uu["_rec_dd"] = dd
	var n: int = (_scn._equip_tick_sys._tide_walls as Array).size()
	if n > _walls_max:
		print("[REC] %.2f 秒 浪墙在场 %d 道" % [_el, n])
		_walls_max = n
		## 带护符那只龟此刻在画面上的像素位置(裁并排对比视频用: 照参考把镜头凑近到龟和英雄一样大)
		## 3D 画在 SubViewport(_sub) 里, 相机是 _scn._cam ⇒ 先投到子视口像素, 再按子视口 → 窗口的比例换算
		var cam: Camera3D = _scn._cam
		if cam != null and _carrier != null and _scn._sub != null:
			var sp: Vector2 = cam.unproject_position(_scn._world_pos(_carrier["pos"], 0.5))
			var sub: Vector2 = Vector2(_scn._sub.size)
			var vs: Vector2 = get_viewport().get_visible_rect().size
			print("[REC] 起手位置 %.3f %.3f(画面比例)" % [sp.x / sub.x, sp.y / sub.y])
	if _el >= _secs:
		_armed = false
		print("REC OK" if _walls_max >= 1 else "REC FAIL: 没涌浪")
		get_tree().quit(0 if _walls_max >= 1 else 1)
