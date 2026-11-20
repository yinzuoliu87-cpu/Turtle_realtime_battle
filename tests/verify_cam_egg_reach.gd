extends Node
## verify_cam_egg_reach.gd — 镜头推到左 / 右头, 两端的龟蛋(含血条)与训龟大师都要推得到队伍卡片内侧。
##
## ★由来(用户 2026-11-20):「摄像头…左右上下移的位置还是太有限了，就是有时候想看龟蛋水条，然后最左边都看不到，那还要调一下。」
##   探针 `tests/probes/_probe_egg_reach.gd` 量到: 拉近(1.5 ~ 2.3)后推到最左, 龟蛋只到屏幕 12 ~ 16%,
##   血条压在左侧队伍卡片(手机约 0 ~ 170 px)边上。根因是平移上限只管「别看到虚空」(`ArenaOuter.pan_limits`
##   的 VIEW_X_EXT − 半视野宽, 总闸 9 米), 没管「两端的东西推不推得进来」。
##
## 判据: 4 个画幅 × 5 档缩放 × 左右两头, 走产品入口(`_apply_cam_zoom` + 往那头猛拖 `_cam_pan_by`)推到头:
##   ① 龟蛋血条(连左侧等级牌)整条在卡片内侧: 左头 血条左沿 ≥ 左卡片右沿; 右头 血条右沿 ≤ 右卡片左沿。
##   ② 训龟大师立绘中心离卡片至少半个身位(PAD_TRAINER 像素)。
##   ★分母: 卡片真建出来了(两列 Control 都有宽度)、每个组合都量到。
##   ★站位与产品同一处: 蛋 = ARENA 边往里 70(源码核对 `dual_lane_flow.gd` 那一行还在), 大师 = `BattleSpawn.TRAINER_INSET`。
## ★不改默认 / 拉远手感: 默认与最远缩放推到头仍 ≤ `ArenaOuter.PAN_MIN`(`verify_cam_extent` ③ 守, 这里不重复)。
##
## 反向验证(2026-11-20): 去掉 `pan_limits` 里的 need_x(退回只按虚空夹) ⇒ ① 红(拉近后蛋血条压卡片);
##   总闸 PAN_LIMIT 改回 9 ⇒ ① 红(最近缩放推不够)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ASPECTS := [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(2400, 1000)]
const EGG_INSET := 70.0          # 与 dual_lane_flow.gd 生成龟蛋那一行同一个数(下面源码核对)
const BADGE_W := 18.0            # 血条左侧等级牌的宽(像素, 含描边)
const PAD_TRAINER := 24.0
var _fail := 0
var _n := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "   ", d)


func _set_view(s, asp: Vector2i) -> void:
	get_tree().root.size = asp
	if s._sub != null and is_instance_valid(s._sub):
		s._sub.size = asp


## 走产品入口推到头(同 verify_cam_extent._set_cam)。
func _push(s, zoom: float, dir: float) -> void:
	s._shake_amp = 0.0
	s._cam_zoom = zoom
	s._cam_pan = Vector3.ZERO
	s._apply_cam_zoom()
	for _k in range(60):
		s._cam_pan_by(-dir * 80.0, 0.0)
	s._cam.position = s._cam_zoom_base


func _ready() -> void:
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	print("=== 镜头推到两头: 龟蛋血条与训龟大师都在队伍卡片内侧 ===")
	var src: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd")
	_ok("★站位核对: 龟蛋仍生成在 ARENA 边往里 %d" % int(EGG_INSET),
		src.contains("battle.ARENA.position.x + 70.0, _cy") and src.contains("battle.ARENA.end.x - 70.0, _cy"),
		"dual_lane_flow 里蛋的站位改了 ⇒ 本测试的 EGG_INSET 要跟着改")
	var s = RB.new()
	add_child(s)
	for _i in range(30):
		await get_tree().process_frame
	var lp: Control = s.get("_team_panel_left")
	var rp: Control = s.get("_team_panel_right")
	_ok("★分母: 两列队伍卡片真建出来了", lp != null and rp != null and lp.size.x > 40.0 and rp.size.x > 40.0,
		"left=%s right=%s" % [str(lp.size) if lp != null else "null", str(rp.size) if rp != null else "null"])
	if lp == null or rp == null:
		_finish()
		return
	var cy: float = RB.ARENA.position.y + RB.ARENA.size.y * 0.5
	var bad: Array = []
	var worst := 999.0
	var combos := 0
	for asp in ASPECTS:
		_set_view(s, asp)
		await get_tree().process_frame
		await get_tree().process_frame
		CamFit.apply(s)
		var vs: Vector2 = s._cam.get_viewport().get_visible_rect().size
		var l_edge: float = lp.get_global_rect().end.x
		var r_edge: float = rp.get_global_rect().position.x
		for z in [RB.CAM_ZOOM_MIN, 1.0, 1.5, 2.0, RB.CAM_ZOOM_MAX]:
			for dir in [-1.0, 1.0]:
				_push(s, float(z), dir)
				var cam: Camera3D = s._cam
				var ex: float = RB.ARENA.position.x + EGG_INSET if dir < 0.0 else RB.ARENA.end.x - EGG_INSET
				var tx: float = RB.ARENA.position.x + BattleSpawn.TRAINER_INSET if dir < 0.0 else RB.ARENA.end.x - BattleSpawn.TRAINER_INSET
				var egg2d := Vector2(ex, cy)
				var bar: Vector2 = cam.unproject_position(BattleRender.bar_anchor(s, {"pos": egg2d, "height": 0.0}))
				var tr: Vector2 = cam.unproject_position(s._world_pos(Vector2(tx, cy - 150.0), 1.0))
				var half: float = float(s.BAR_W) * 0.5
				var margin: float
				if dir < 0.0:
					var bar_l: float = bar.x - half - BattleRender.BADGE_SHIFT - BADGE_W
					margin = minf(bar_l - l_edge, tr.x - PAD_TRAINER - l_edge)
				else:
					var bar_r: float = bar.x + half - BattleRender.BADGE_SHIFT
					margin = minf(r_edge - bar_r, r_edge - (tr.x + PAD_TRAINER))
				combos += 1
				worst = minf(worst, margin)
				if margin < 0.0:
					bad.append("%dx%d 缩放%.2f %s头 差%.0fpx(平移 %.2f)" % [int(vs.x), int(vs.y), z, "左" if dir < 0.0 else "右", -margin, float(s._cam_pan.x)])
	_ok("★分母: 4 画幅 × 5 缩放 × 两头 都量到", combos == ASPECTS.size() * 5 * 2, "%d 个" % combos)
	_ok("① ★★推到头时龟蛋血条(含等级牌)与训龟大师都在队伍卡片内侧", bad.is_empty(),
		"压卡片 %d/%d: %s" % [bad.size(), combos, str(bad.slice(0, 4))])
	print("     最小余量 %.0f px" % worst)
	_finish()


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
