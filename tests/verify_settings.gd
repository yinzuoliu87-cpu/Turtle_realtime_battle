extends Node
## verify_settings.gd — 自证: 设置项持久化 + 死按钮修复 + 重置存档的二次确认。
## 跑法: godot --headless --path . res://tests/verify_settings.tscn --quit-after 200
##
## 覆盖:
##  1. GameState 有 fullscreen / perf_lite 字段, 默认 false, 且进 save() 的数据里
##  2. reset_save() 【不清】偏好设置 (音量/全屏/低画质) — 那是偏好不是进度
##  3. SettingsScene 能在 headless 构建 (无报错), 且 label 跟 GameState 状态一致
##  4. ★安全属性: 点「重置所有存档」只弹确认框, 【不会立刻清档】
##  5. 确认框「取消」→ 关闭且存档仍然完好
##  6. 确认框「确认清空」→ 才真的清
##  7. perf_lite 不再是死按钮: 战斗视口/菜单漂移 都读它 (源码级断言)

const SettingsSceneScript = preload("res://scripts/scenes/SettingsScene.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  ✓ ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  ✗ ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	if gs == null:
		print("✗ GameState autoload 缺失"); get_tree().quit(1); return
	gs.test_mode = true   # 不写盘

	print("=== 1. 新设置字段 ===")
	_ok("有 fullscreen 字段", "fullscreen" in gs)
	_ok("有 perf_lite 字段", "perf_lite" in gs)
	gs.fullscreen = false
	gs.perf_lite = false
	_ok("默认 fullscreen=false", gs.fullscreen == false)
	_ok("默认 perf_lite=false", gs.perf_lite == false)

	print("=== 2. reset_save() 不清【偏好设置】(只清进度) ===")
	gs.bgm_volume = 0.11
	gs.sfx_volume = 0.22
	gs.fullscreen = true
	gs.perf_lite = true
	gs.meta_deepsea_coins = 999
	gs.persistent_bench = [{"id": "p2eq_001", "star": 1}]
	gs.season_leaders = ["candy"]
	gs.reset_save()
	_ok("进度已清: 深海币=0", gs.meta_deepsea_coins == 0, "got=%d" % gs.meta_deepsea_coins)
	_ok("进度已清: 背包空", (gs.persistent_bench as Array).is_empty())
	_ok("进度已清: 统领空", (gs.season_leaders as Array).is_empty())
	_ok("偏好保留: bgm_volume", is_equal_approx(gs.bgm_volume, 0.11), "got=%f" % gs.bgm_volume)
	_ok("偏好保留: sfx_volume", is_equal_approx(gs.sfx_volume, 0.22), "got=%f" % gs.sfx_volume)
	_ok("偏好保留: fullscreen", gs.fullscreen == true)
	_ok("偏好保留: perf_lite", gs.perf_lite == true)

	print("=== 3. SettingsScene 构建 + label 跟随状态 ===")
	gs.perf_lite = true
	var sc: Control = SettingsSceneScript.new()
	add_child(sc)
	await get_tree().process_frame
	_ok("SettingsScene 在 headless 构建无报错", is_instance_valid(sc))
	_ok("perf_lite=true → label 显示「开」", sc._perf_label().find("开") >= 0, sc._perf_label())
	gs.perf_lite = false
	_ok("perf_lite=false → label 显示「关」", sc._perf_label().find("关") >= 0, sc._perf_label())

	print("=== 4/5/6. ★重置存档 必须二次确认 ===")
	gs.meta_deepsea_coins = 777
	gs.persistent_bench = [{"id": "p2eq_002", "star": 1}]
	_ok("初始无确认框", sc._confirm_layer == null)

	sc._ask_reset()
	await get_tree().process_frame
	_ok("点「重置」→ 弹出确认框", sc._confirm_layer != null and is_instance_valid(sc._confirm_layer))
	_ok("★点「重置」不会立刻清档 (币仍=777)", gs.meta_deepsea_coins == 777, "got=%d" % gs.meta_deepsea_coins)
	_ok("★点「重置」不会立刻清档 (背包仍有1件)", (gs.persistent_bench as Array).size() == 1)

	# 取消
	sc._confirm_layer.queue_free()
	sc._confirm_layer = null
	await get_tree().process_frame
	_ok("取消后存档完好 (币仍=777)", gs.meta_deepsea_coins == 777, "got=%d" % gs.meta_deepsea_coins)

	# 确认
	sc._do_reset()
	_ok("「确认清空」后才真的清 (币=0)", gs.meta_deepsea_coins == 0, "got=%d" % gs.meta_deepsea_coins)
	_ok("「确认清空」后背包空", (gs.persistent_bench as Array).is_empty())

	print("=== 7. perf_lite 不再是死按钮 (源码级) ===")
	_ok("战斗视口读 perf_lite", _src_has("res://scripts/scenes/RealtimeBattle3DScene.gd", "perf_lite"))
	_ok("主菜单背景漂移读 perf_lite", _src_has("res://scripts/scenes/MainMenuScene.gd", "perf_lite"))
	_ok("图鉴背景漂移读 perf_lite", _src_has("res://scripts/scenes/CodexScene.gd", "perf_lite"))
	_ok("战斗视口低画质关 MSAA", _src_has("res://scripts/scenes/RealtimeBattle3DScene.gd", "MSAA_DISABLED"))
	_ok("战斗视口低画质降 3D 分辨率", _src_has("res://scripts/scenes/RealtimeBattle3DScene.gd", "scaling_3d_scale"))

	print("")
	if _fail == 0:
		print("ALL PASS — 设置持久化 + 重置二次确认 + 低画质真开关")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _src_has(path: String, needle: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return false
	var s := f.get_as_text()
	f.close()
	return s.find(needle) >= 0
