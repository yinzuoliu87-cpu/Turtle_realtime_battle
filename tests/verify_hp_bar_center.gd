extends Node
## verify_hp_bar_center.gd — 血条在人物正上方(2026-11-20)
##
## 用户 11-20「这个血条中心和人物中心不一样吗」。探针 tests/probes/_probe_bar_center 量出原来偏 10 ~ 27 像素, 两个原因:
##   ① 透视: 血条挂在脚底正上方 2.8 米(世界竖直), 镜头俯 40° 带透视 ⇒ 离屏幕中线越远被往外甩得越多;
##      立绘是正对镜头的公告板, 不受这个影响(立绘中心与脚底在屏幕上差 < 2 像素)。
##   ② 等级牌挂在血条左边 ⇒ 「牌 + 血条」整体再往左 8 像素(原来只有蛋补了)。
## 修: BattleRender.bar_anchor 沿镜头上方抬; 有等级牌的整体右挪 BADGE_SHIFT。
## 判据(真战斗场景, 开打后量每个活着的单位):
##   ① 「牌 + 血条」整体中心与脚底的屏幕横坐标差 ≤ 2 像素(没有牌的量血条本身)
##   ② 分母: 至少 5 个单位, 且至少一个离屏幕中线 > 150 像素(离中线近的单位透视偏差本来就小, 量不出①)
##   ③ 头顶状态层与血条同一个锚点(BattleRender.bar_anchor)
## 反向验证: bar_anchor 改回世界竖直 ⇒ ① 红(偏 10 像素以上); 去掉 BADGE_SHIFT ⇒ ① 红(偏 8 像素)。

var _n := 0
var _fail := 0
var sc: Node = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 血条在人物正上方 ===")
	sc = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(sc)
	## 等到开打、血条都摆好(开场演出约 5 秒; 每帧真时间推进, 上限 2400 帧)
	var waited := 0
	while waited < 2400:
		await get_tree().process_frame
		waited += 1
		if float(sc.get("_t")) > 1.5 and _visible_bars() >= 5:
			break
	await get_tree().process_frame
	var cam: Camera3D = sc._cam
	var mid: float = get_viewport().get_visible_rect().size.x * 0.5
	var n := 0
	var far := 0
	var bad: Array = []
	var worst := 0.0
	for u in sc._units:
		if not u.get("alive", false):
			continue
		var root = u.get("bar_root", null)
		if not is_instance_valid(root) or not (root as Control).visible:
			continue
		var xf: Transform2D = (root as Control).get_global_transform_with_canvas()
		var l: float = (xf * Vector2(0, 0)).x
		var r: float = (xf * Vector2(sc.BAR_W, 0)).x
		var lb = u.get("level_badge", null)
		if is_instance_valid(lb):
			l = minf(l, ((lb as Control).get_global_transform_with_canvas() * Vector2(0, 0)).x)
		var c: float = (l + r) * 0.5
		var feet: float = cam.unproject_position(sc._world_pos(u["pos"], float(u.get("height", 0.0)))).x
		n += 1
		if absf(feet - mid) > 150.0:
			far += 1
		worst = maxf(worst, absf(c - feet))
		if absf(c - feet) > 2.0:
			bad.append("%s 差 %+.1f(离中线 %.0f)" % [str(u.get("id", "?")), c - feet, feet - mid])
	_ok("★分母: 量了 %d 个单位, 其中离屏幕中线 > 150 像素的 %d 个" % [n, far], n >= 5 and far >= 2)
	_ok("★★★① 每个单位「牌 + 血条」整体中心与脚底横坐标差 ≤ 2 像素(最大 %.1f)" % worst, bad.is_empty(), str(bad))
	## ③ 头顶状态层锚点 = 血条锚点(源码只走 bar_anchor 一处; 量结构不量文案)
	var main_src: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var render_src: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_render.gd")
	_ok("★③ 头顶状态层、血条、持续伤害数字都从 BattleRender.bar_anchor 取锚点",
		main_src.find("BattleRender.bar_anchor(self, u)") >= 0 and render_src.count("bar_anchor(battle, u") >= 2
		and main_src.find("u.get(\"bar_head_h\", 2.4)") < 0)
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 血条在人物正上方")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()


func _visible_bars() -> int:
	var k := 0
	for u in sc._units:
		var root = u.get("bar_root", null)
		if u.get("alive", false) and is_instance_valid(root) and (root as Control).visible:
			k += 1
	return k
