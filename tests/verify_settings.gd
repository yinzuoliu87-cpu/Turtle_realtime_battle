extends Node
## verify_settings.gd — 自证: 设置项持久化 + 死按钮修复 + 重置存档的二次确认。
## 跑法: godot --headless --path . res://tests/verify_settings.tscn --quit-after 200
##
## 覆盖:
##  1. GameState 有 fullscreen / perf_lite 字段, 默认 false, 且进 save() 的数据里
##  2. reset_save() 【不清】偏好设置 (音量/全屏/低画质) — 那是偏好不是进度
##  3. SettingsScene 能在 headless 构建 (无报错); 分段钮(画质/显示)真按下去真改设置;
##     页面无 emoji、无「」循环键; 正式包条件下不建调试场(2026-10-07 重排)
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

	print("=== 3. SettingsScene 构建 + 分段钮(2026-10-07 重排: 循环木牌 → 分段钮) ===")
	gs.perf_lite = true
	var sc: Control = SettingsSceneScript.new()
	add_child(sc)
	await get_tree().process_frame
	_ok("SettingsScene 在 headless 构建无报错", is_instance_valid(sc))
	## ★量**行为**不量文案: 按名字找分段钮(名字常量在产品那边), 真按下去, 看 GameState 变没变。
	##   原来这里量 `_perf_label()` 的字(「画质「低」」) —— 循环木牌没了, 判据跟着需求走:
	##   「点了真的改设置」+「选中态跟着设置走」。
	var q_low = sc.find_child(SettingsSceneScript.SEG_QUALITY + "Low", true, false)
	var q_high = sc.find_child(SettingsSceneScript.SEG_QUALITY + "High", true, false)
	_ok("★分母: 画质分段钮两段都建出来了(低/高)", q_low is Button and q_high is Button)
	if q_low is Button and q_high is Button:
		_ok("perf_lite=true 开页 ⇒ 选中的是「低」那段", _seg_on(q_low) and not _seg_on(q_high),
			"低=%s 高=%s" % [_seg_on(q_low), _seg_on(q_high)])
		(q_high as Button).pressed.emit()
		await get_tree().process_frame
		_ok("★★点「高」⇒ GameState.perf_lite 真的变 false", gs.perf_lite == false)
		_ok("点「高」⇒ 选中态移到「高」", _seg_on(q_high) and not _seg_on(q_low))
		(q_low as Button).pressed.emit()
		await get_tree().process_frame
		_ok("★★点「低」⇒ GameState.perf_lite 真的变 true", gs.perf_lite == true)
		_ok("点「低」⇒ 选中态移回「低」", _seg_on(q_low) and not _seg_on(q_high))
	var d_win = sc.find_child(SettingsSceneScript.SEG_DISPLAY + "Window", true, false)
	var d_full = sc.find_child(SettingsSceneScript.SEG_DISPLAY + "Full", true, false)
	## 「显示」只在桌面端建(手机上没有窗口模式) —— 门禁跑在桌面, 所以这里必须在。
	_ok("★分母: 桌面端有「显示」分段钮(窗口/全屏)", d_win is Button and d_full is Button)
	if d_win is Button and d_full is Button:
		gs.fullscreen = false
		(d_full as Button).pressed.emit()
		await get_tree().process_frame
		_ok("★★点「全屏」⇒ GameState.fullscreen 真的变 true", gs.fullscreen == true)
		(d_win as Button).pressed.emit()
		await get_tree().process_frame
		_ok("★★点「窗口」⇒ GameState.fullscreen 真的变 false", gs.fullscreen == false)
	## ★不许再有「点一下换字」的循环键: 页面上任何按钮的字都不带「」
	var btxt: Array = []
	_texts(sc, btxt, true)
	var cyc: Array = []
	for s in btxt:
		if str(s).find("「") >= 0:
			cyc.append(s)
	_ok("★分母: 扫到了按钮文字", btxt.size() >= 4, "%d 个" % btxt.size())
	_ok("没有「」包着值的循环按钮", cyc.is_empty(), str(cyc))

	print("=== 3b. ★页面上一个 emoji 都没有 ===")
	var all_t: Array = []
	_texts(sc, all_t, false)
	var emo: Array = []
	for s in all_t:
		if _has_emoji(str(s)):
			emo.append(s)
	_ok("★分母: 扫到了页面上的字(Label + Button)", all_t.size() >= 10, "%d 条" % all_t.size())
	_ok("★★设置页所有 Label/Button 文字不含 emoji 码位", emo.is_empty(), str(emo))
	_ok("★尺子会响: 「⚠ 重置」被判成 emoji", _has_emoji("⚠ 重置") and _has_emoji("调试场 🛠") and not _has_emoji("重置存档"))

	print("=== 3c. ★调试场只在开发包 ===")
	var dev_btn = sc.find_child(SettingsSceneScript.DEV_ARENA_BTN, true, false)
	_ok("★分母: 开发包(门禁进程 is_debug_build)里调试场键在", dev_btn is Button)
	SettingsSceneScript.release_override = true
	var sc_rel: Control = SettingsSceneScript.new()
	add_child(sc_rel)
	await get_tree().process_frame
	var dev_rel = sc_rel.find_child(SettingsSceneScript.DEV_ARENA_BTN, true, false)
	var rel_t: Array = []
	_texts(sc_rel, rel_t, true)
	SettingsSceneScript.release_override = false
	_ok("★★正式包条件下: 调试场键不建", dev_rel == null)
	_ok("★★正式包条件下: 页面上也没有「调试场」「测试时间」字样", not ("调试场" in rel_t) and not ("测试时间" in rel_t), str(rel_t))
	_ok("正式包条件下: 重置存档键照样在(只拿掉开发工具)",
		sc_rel.find_child(SettingsSceneScript.RESET_BTN, true, false) is Button)
	sc_rel.queue_free()
	await get_tree().process_frame

	print("=== 4/5/6. ★重置存档 必须二次确认 ===")
	gs.meta_deepsea_coins = 777
	gs.persistent_bench = [{"id": "p2eq_002", "star": 1}]
	_ok("初始无确认框", sc._confirm_layer == null)

	## ★走真键: 按页面上那颗「重置存档」, 不直接调 `_ask_reset`(那样量不到键接的是谁)
	var rb = sc.find_child(SettingsSceneScript.RESET_BTN, true, false)
	_ok("★分母: 页面上有重置存档键", rb is Button)
	if rb is Button:
		(rb as Button).pressed.emit()
	else:
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
	_ok("战斗视口读 perf_lite", _src_has("res://scripts/scenes/battle/battle_world_builder.gd", "perf_lite"))   # 视口构建已抽到 BattleWorldBuilder(2026-07-26)
	## ★2026-09-18 改了措辞不是放宽: 主菜单背景已从「平铺+25s 漂移」换成静态龟群像,
	##   没有漂移可关了。perf_lite 在主菜单的消费者改成【跳过入场动画】(_slide_in/_slide_in_left),
	##   所以这条仍然在守"低画质开关在主菜单真的有作用", 只是作用换了一个。
	_ok("主菜单读 perf_lite(低画质跳过入场动画)", _src_has("res://scripts/scenes/MainMenuScene.gd", "perf_lite"))
	_ok("图鉴背景漂移读 perf_lite", _src_has("res://scripts/scenes/CodexScene.gd", "perf_lite"))
	_ok("战斗视口低画质关 MSAA", _src_has("res://scripts/scenes/battle/battle_world_builder.gd", "MSAA_DISABLED"))
	_ok("战斗视口低画质降 3D 分辨率", _src_has("res://scripts/scenes/battle/battle_world_builder.gd", "scaling_3d_scale"))

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


## 分段钮这一段是不是选中态。`UISkin.pixel_tab` 选中 = 页签行第 3/4 格(青边), 未选 = 第 1/2 格。
func _seg_on(b: Button) -> bool:
	var sb = b.get_theme_stylebox("normal")
	return sb is StyleBoxTexture and (sb as StyleBoxTexture).region_rect.position.x >= UISkin.PX_CELL.x * 2.0 - 0.5


## 收集可见的 Label/Button 文字。`buttons_only` = 只收按钮。
func _texts(n: Node, out: Array, buttons_only: bool) -> void:
	if n is Button and (n as Button).is_visible_in_tree() and str((n as Button).text) != "":
		out.append(str((n as Button).text))
	elif not buttons_only and n is Label and (n as Label).is_visible_in_tree() and str((n as Label).text) != "":
		out.append(str((n as Label).text))
	for c in n.get_children():
		_texts(c, out, buttons_only)


## emoji / 符号字形码位(这些字形来自 NotoEmoji 回退, 与像素笔触是两套画法)。
## 杂项符号 2600-27BF(⚠✅✨…) / 杂项技术 2300-23FF(⏸⌛…) / 箭头补充 2B00-2BFF(⭐…) /
## 1F000-1FAFF(🛠🎵🔊…) / 变体选择符 FE0F。
func _has_emoji(s: String) -> bool:
	for i in range(s.length()):
		var c := s.unicode_at(i)
		if (c >= 0x2600 and c <= 0x27BF) or (c >= 0x2300 and c <= 0x23FF) or (c >= 0x2B00 and c <= 0x2BFF) \
				or (c >= 0x1F000 and c <= 0x1FAFF) or c == 0xFE0F:
			return true
	return false
