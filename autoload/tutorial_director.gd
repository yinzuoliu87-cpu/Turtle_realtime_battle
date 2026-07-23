extends Node
## TutorialDirector — 新手教学的跨场景导演 (用户 2026-07-23)。Autoload 单例。
##
## 用户流程: 战斗1(选龟站位) → 商店买 → 背包装+调位置 → 图鉴 → 战斗2 → 回菜单不给奖励。
##
## 只在 GameState.tutorial_active 为真时起作用。每个场景在"该离开去下一站"时问 director:
##   next_scene_after(here) → 返回下一个场景路径, director 内部把 tutorial_stage 推进。
##
## ★为什么用 autoload 而不是散在各场景: 跨 4 个场景的顺序状态机, 挂在任一场景都会随场景销毁丢失,
##   而 GameState.tutorial_stage 记"走到哪"、director 记"下一步是什么", 组合起来跨场景稳定。

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const SHOP := "res://scenes/Shop.tscn"
const INVENTORY := "res://scenes/Inventory.tscn"
const CODEX := "res://scenes/Codex.tscn"

## 教学固定阵容(用户拍板: 固定阵容+弱对手必赢)。3 只上手简单的龟。
const FIXED_TEAM := ["basic", "stone", "bamboo"]
## 弱对手阵容(必赢): 低配, 让新手两把都稳赢。
const WEAK_FOE := ["basic"]


func is_active() -> bool:
	return GameState != null and bool(GameState.get("tutorial_active"))


func stage() -> String:
	return str(GameState.get("tutorial_stage")) if GameState != null else ""


## 从某个场景"完成"后, 该去哪。同时把 tutorial_stage 推进到下一阶段。
## here ∈ battle / shop / inventory / codex
func next_scene_after(here: String) -> String:
	if not is_active():
		return MAIN_MENU
	var st := stage()
	match here:
		"battle":
			if st == "match1":
				GameState.tutorial_stage = "shop"
				return SHOP
			elif st == "match2":
				return _finish()          # 第二把打完 → 教学结束
			return MAIN_MENU
		"shop":
			GameState.tutorial_stage = "inventory"
			return INVENTORY
		"inventory":
			GameState.tutorial_stage = "codex"
			return CODEX
		"codex":
			GameState.tutorial_stage = "match2"
			return BATTLE
	return MAIN_MENU


## 教学结束: 关沙盒、置 onboarded、存档、回菜单、不给奖励(奖励在 _settle_season 已被沙盒拦)。
func _finish() -> String:
	if GameState != null:
		GameState.onboarded = true
		GameState.tutorial_active = false
		GameState.tutorial = false
		GameState.tutorial_stage = "done"
		GameState.tutorial_mandatory = false
		GameState.save()
	return MAIN_MENU


## 教学模式下给商店/背包/图鉴挂一个醒目的"下一站"按钮(右上角), 走导演推进。
## 非教学模式什么都不做。here ∈ shop / inventory / codex。
func attach_next_button(host: CanvasItem, here: String) -> void:
	if not is_active():
		return
	var dest: String = next_scene_after(here)
	# next_scene_after 已经推进了 stage —— 这里只建按钮, 点了才 change_scene。撤回推进:
	# ★不能让"建按钮"这个副作用改状态。改用只读的 _peek_next。
	dest = _peek_next(here)
	var label: String = {
		"shop": "装备买好了 → 去背包",
		"inventory": "装好了 → 看看图鉴",
		"codex": "看完了 → 打第二把 ▶",
	}.get(here, "继续 ▶")
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color("#3a1f00"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#ffc23c"); sb.set_corner_radius_all(9)
	sb.content_margin_left = 20; sb.content_margin_right = 20
	sb.content_margin_top = 9; sb.content_margin_bottom = 9
	btn.add_theme_stylebox_override("normal", sb)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.position = Vector2(-btn.get_minimum_size().x - 220.0, 24.0)
	btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btn.pressed.connect(func() -> void:
		var d: String = next_scene_after(here)   # 点了才真推进 + 跳转
		host.get_tree().change_scene_to_file(d))
	var layer := CanvasLayer.new()
	layer.layer = 7000
	layer.add_child(btn)
	host.add_child(layer)


## 只读: 从 here 出发下一站是哪(不改 stage)。给 attach_next_button 显示用。
func _peek_next(here: String) -> String:
	var st := stage()
	match here:
		"shop": return INVENTORY
		"inventory": return CODEX
		"codex": return BATTLE
		"battle": return SHOP if st == "match1" else MAIN_MENU
	return MAIN_MENU


## 当前阶段该挂哪套引导步骤(TutorialGuide 的 key)。空=这场景本阶段没有引导。
func steps_key_for(scene: String) -> String:
	if not is_active():
		return ""
	var st := stage()
	if scene == "battle" and st == "match1":
		return "team_select"      # 战斗1: 选龟站位(选龟其实在战斗场的放置阶段)
	if scene == "battle" and st == "match2":
		return "battle"           # 战斗2: 战斗操作引导
	if scene == "shop":
		return "shop"
	if scene == "inventory":
		return "inventory"
	if scene == "codex":
		return "codex"
	return ""
