extends Node
## verify_scene_transition.gd — 切页过场(2026-11-05, scripts/util/scene_fader.gd)
##
## 由来: 用户 11-05「商店这个卡顿…整个游戏里面会不会有很多这种问题呢？」—— 实走各页: 进选龟页最长一帧 343 毫秒(加载 164 + 搭界面 671)。
##   做法: 暗幕淡入 + 后台线程加载 + 暗幕盖满后才换场 + 新页画过后淡出。无头默认不走过场, 这里把 SceneNav.transition_in_headless 打开来量。
## 判据(真入口 SceneNav.go, 换到图鉴页):
##   ① 换场那一刻(current_scene 第一次变成新页的那一帧)暗幕不透明度 ≥ 0.99 —— 新页搭界面在暗幕下面
##   ② 过场期间暗幕挡点击(MOUSE_FILTER_STOP); 结束后不挡、暗幕隐藏
##   ③ 过场中再点一次切到别的页 ⇒ 丢掉(最后停在第一次要去的页)
##   ④ 新页是后台线程加载的(last.ok, 等加载 + 搭界面耗时打出来); 从发起到结束有限时间内完成
##   ⑤ 关掉开关(无头默认)⇒ 原来的同步换场: 不建暗幕
## ★分母: 每条先断言「那一步真的发生了」(真的换了页 / 第二次请求真的发出去了)。

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	var tree := get_tree()
	## 本节点不当 current_scene(换场会把 current_scene 释放掉): 放一个替身
	var stand := Node.new()
	stand.name = "Stand"
	tree.root.add_child(stand)
	tree.current_scene = stand
	await tree.process_frame

	print("=== 切页过场 ===")
	SceneNav.transition_in_headless = true
	SceneNav.go(tree, "res://scenes/Codex.tscn")
	var f: SceneFader = tree.root.get_node_or_null("SceneFader")
	_ok("分母: 发起换页后建了暗幕层", f != null and f.busy)
	await tree.process_frame
	var blocked: bool = f != null and f._rect.mouse_filter == Control.MOUSE_FILTER_STOP
	## ③ 过场中再点一次切到别的页
	SceneNav.go(tree, "res://scenes/Settings.tscn")
	var alpha_at_swap := -1.0
	var frames := 0
	var hint_seen := false
	var seen: Array = []   # 过场期间出现过的每一页(换场次数 = 这里的个数)
	var last_cs: Node = stand
	var settle := 0
	## 走到过场结束, 再多等 400 帧: 连点的第二次请求若没被丢掉, 它的过场会在这段里把页换走
	while frames < 3000 and settle < 400:
		if f.busy or tree.current_scene == stand:
			settle = 0
		else:
			settle += 1
		var cs := tree.current_scene
		if cs != null and cs != last_cs:
			last_cs = cs
			seen.append(str(cs.scene_file_path))
			if alpha_at_swap < 0.0:
				alpha_at_swap = f._rect.color.a
		hint_seen = hint_seen or f._hint.visible
		await tree.process_frame
		frames += 1
	var cur := tree.current_scene
	var cur_path := str(cur.scene_file_path) if cur != null else ""
	_ok("分母: 真的换到了新页(图鉴)", cur_path == "res://scenes/Codex.tscn", cur_path)
	_ok("① 换场那一刻暗幕已盖满(新页在暗幕下搭界面)", alpha_at_swap >= 0.99, "不透明度 %.2f" % alpha_at_swap)
	_ok("② 过场期间暗幕挡点击", blocked)
	_ok("② 结束后暗幕隐藏、不挡点击", not f.visible and f._rect.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_ok("③ 过场中再点去设置页 ⇒ 丢掉: 只换过一次页、停在图鉴、设置页从没出现", cur_path == "res://scenes/Codex.tscn" and seen == ["res://scenes/Codex.tscn"], str(seen))
	_ok("④ 新页由后台线程加载成功、过场在限时内走完", bool(f.last.get("ok", false)) and frames < 3000,
		"淡入 %d · 等加载 %d · 搭界面 %d · 全程 %d 毫秒 · %d 帧" % [int(f.last.get("fade_out_ms", 0)), int(f.last.get("wait_load_ms", 0)),
		int(f.last.get("build_ms", 0)), int(f.last.get("total_ms", 0)), frames])
	var long_wait: bool = int(f.last.get("wait_load_ms", 0)) > int(SceneFader.HINT_AFTER_SEC * 1000.0) + 100
	_ok("④ 等加载超过 %.2f 秒时亮过「加载中」、结束后收起" % SceneFader.HINT_AFTER_SEC, (hint_seen or not long_wait) and not f._hint.visible,
		"等加载 %d 毫秒 · 亮过 %s" % [int(f.last.get("wait_load_ms", 0)), hint_seen])
	## ⑤ 关掉开关 ⇒ 原来的同步换场, 不走暗幕
	SceneNav.transition_in_headless = false
	var f_busy_before: bool = f.busy
	SceneNav.go(tree, "res://scenes/Settings.tscn")
	var k := 0
	while k < 30 and str(tree.current_scene.scene_file_path) != "res://scenes/Settings.tscn":
		await tree.process_frame
		k += 1
	_ok("⑤ 无头默认(开关关)⇒ 同步换场, 暗幕没动", str(tree.current_scene.scene_file_path) == "res://scenes/Settings.tscn" and not f.busy and not f_busy_before and not f.visible, "%d 帧" % k)
	print("")
	_ok("分母: 断言条数 %d ≥ 9" % _n, _n >= 9)
	print("ALL PASS — 切页过场" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
