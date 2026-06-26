extends Control

## DualLaneMapScene — 双路龟蛋 大地图 (二阶段战斗枢纽, 壳/占位美术)
##
## 进场看到: 左右两颗龟蛋基地 + 三条路(上路/终极战场/下路)连起来. 每打完一路回到这张图,
## 推进下一路, 全决出后显示结果. 是 duallane 模式的入口 + 各路之间的中转站.
## 占位美术: 蛋=圆角面板+🥚, 路=色条, 节点=面板. 真美术后替.
##
## 流程: _show_result(duallane) 打完一路 → 回本图 → 按 current_lane 给"进入X路"按钮 → Battle.tscn.

const W := 1280
const H := 720
const P2 := preload("res://scripts/engine/phase2_config.gd")
const DualLane := preload("res://scripts/engine/phase2_duallane.gd")
const Backend := preload("res://scripts/engine/backend.gd")

# 占位演示阵容 (每方 3 统领, 设计 V3.2: 选将3只→分路; auto_split 现 2上+1下)
const DEMO_LEFT := ["basic", "stone", "bamboo"]
const DEMO_RIGHT := ["rainbow", "lightning", "phoenix"]

var content_root: Control
var _font_cache: FontVariation = null
var _assigning: bool = false        # 分路暗选阶段 (玩家把3龟分上/下路)
var _player_team: Array = []         # 玩家3统领 id (待分路)
var _assign: Dictionary = {}         # pet_id → "top"/"bottom" (玩家分路选择)
const Equip := preload("res://scripts/engine/phase2_equip.gd")


func _ready() -> void:
	await get_tree().process_frame
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await get_tree().process_frame
	Audio.play_bgm("menu", 1.0, 0.4)
	# 新局(无进行中分路) → 进分路暗选阶段; 否则(打完一路回来)→ 直接看战况图.
	var top_a: Array = GameState.lane_assign.get("top", [])
	var bot_a: Array = GameState.lane_assign.get("bottom", [])
	_assigning = (GameState.mode != "duallane") or (top_a.is_empty() and bot_a.is_empty())
	if _assigning:
		# 选龟来的真阵容优先, 否则 demo (直接进图调试时)
		var picked: Array = GameState.left_team if GameState.left_team.size() == 3 else DEMO_LEFT.duplicate()
		var enemy: Array = GameState.right_team if GameState.right_team.size() == 3 else DEMO_RIGHT.duplicate()
		if OS.has_environment("SMOKE_LEFT"):   # dev冒烟: 换测试队伍(逗号分隔龟id), 覆盖更多龟/对局组合
			picked = []
			for _sl in OS.get_environment("SMOKE_LEFT").split(","):
				picked.append(_sl.strip_edges())
		if OS.has_environment("SMOKE_RIGHT"):
			enemy = []
			for _sr in OS.get_environment("SMOKE_RIGHT").split(","):
				enemy.append(_sr.strip_edges())
		GameState.reset_dual_lane()
		GameState.mode = "duallane"
		_player_team = picked
		_assign = {}
		# V2: 注入局外背包配好的 build (persistent_equipped → 左侧 equipped_p2; 让背包装的装备真进战斗, 闭合循环)
		# 持久=source of truth, 战斗读副本 → 装备永不丢 (不在战斗fighter上, dead也不丢)
		for _pid in GameState.persistent_equipped.keys():
			if str(_pid) in picked:
				GameState.equipped_p2[GameState.p2eq_key("left", str(_pid))] = (GameState.persistent_equipped[_pid] as Array).duplicate(true)
		# 敌方分路: V2 优先用对手快照 (ghost.lane_assign); 无则 auto_split (兜底老路)
		var _gla: Dictionary = GameState.dual_ghost.get("lane_assign", {}) if GameState.dual_ghost is Dictionary else {}
		GameState.enemy_lane_assign = _gla.duplicate(true) if (_gla.has("top") or _gla.has("bottom")) else DualLane.auto_split(enemy)
		# 选龟平均等级 → 固定平均级(小将等级 + 龟蛋HP 用)。局内等级(商店档)= TFT 式从 1 起、买经验涨。
		#   (用户报"商店局内等级一直是10": 原 dual_level 被存档龟均级顶到10=已满档→买经验失效。现解耦, 局内等级纯局内进度。)
		#   敌方镜像玩家均级(敌龟非玩家pet, get_pet_level查不到真级; 见 docs/specs/学派羁绊-实装-疑问点.md Q1b)。
		var avg_lv: int = GameState.team_avg_level(picked)
		GameState.dual_level = {"left": 1, "right": 1}   # 局内等级从1起 (商店档/装备槽随买经验涨, 不再被龟存档等级顶满)
		GameState.dual_avg_level = {"left": avg_lv, "right": avg_lv}   # 固定: 小将等级 + 龟蛋HP 仍按队伍均级
		var ehp: int = P2.egg_hp(avg_lv)
		GameState.egg_hp = {"left": ehp, "right": ehp}
		GameState.egg_hp_max = {"left": ehp, "right": ehp}
		GameState.lane_assign = {"top": [], "bottom": []}
		GameState.dual_coins = {"left": 4, "right": 4}   # 起手少量局内币 (占位)
		# 敌方装备: V2 优先注入对手快照 (ghost.equipped → 右侧 equipped_p2 带 right:: 前缀); 无则 ai_dual_shop 现买 (兜底)
		var _geq: Dictionary = GameState.dual_ghost.get("equipped", {}) if GameState.dual_ghost is Dictionary else {}
		if not _geq.is_empty():
			for _pid in _geq.keys():
				GameState.equipped_p2[GameState.p2eq_key("right", str(_pid))] = (_geq[_pid] as Array).duplicate(true)
		else:
			GameState.ai_dual_shop()   # 敌方AI用起手币买装备
	# 路间敌方再购已移除 (2026-06-18): 敌方现每战斗回合在战中购物 (BattleScene:1322), 与玩家对称;
	# 原 elif 路间 ai_dual_shop 是 2026-06-13 删玩家大地图商店后遗留的单边优势, 移除恢复对称.
	_bg()
	content_root = Control.new()
	content_root.size = Vector2(W, H)
	content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_root)
	_center_content()
	_build()
	get_viewport().size_changed.connect(_center_content)
	if OS.has_environment("DUALLANE_SMOKE"):
		_smoke_auto_advance()


## 无头冒烟: 地图不等点击, 自动推进 (分路→各路→终极→结束).
func _smoke_auto_advance() -> void:
	await get_tree().create_timer(0.3).timeout
	if _assigning:
		# 用实际选龟队伍分路(前2上路, 第3下路) — 不再硬编 demo basic/stone/bamboo
		#   (换队伍时硬编名不在队里→分路全空→战斗无有效阵容→反复重启不结束=之前冒烟卡死的真因)
		_assign = {}
		for _ak in range(_player_team.size()):
			_assign[str(_player_team[_ak])] = "bottom" if _ak == 2 else "top"
		if _player_team.size() >= 3:
			_assign_turtle(str(_player_team[2]), "bottom")   # 触发 lane_assign 重建 + rebuild
		await get_tree().create_timer(0.2).timeout
		_confirm_assign()
		return
	var winner := GameState.dual_match_over()
	if winner == "" and GameState.current_lane == "done":
		winner = "left" if GameState.egg_frac("right") < GameState.egg_frac("left") else "right"
	if winner != "":
		print("[SMOKE] 整局结束 winner=%s (左蛋%d/右蛋%d)" % [winner, int(GameState.egg_hp.get("left", 0)), int(GameState.egg_hp.get("right", 0))])
		get_tree().quit()
	else:
		print("[SMOKE] 进入 %s (左蛋%d 右蛋%d Lv%d)" % [GameState.current_lane, int(GameState.egg_hp.get("left", 0)), int(GameState.egg_hp.get("right", 0)), int(GameState.dual_level.get("left", 1))])
		get_tree().change_scene_to_file("res://scenes/Battle.tscn")


func _center_content() -> void:
	if content_root != null:
		content_root.position = ((get_viewport_rect().size - Vector2(W, H)) / 2.0).round()


func _bg() -> void:
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color("#0a1622")   # 深海底
	add_child(base)
	# 暗渐变压顶
	var grad := Gradient.new()
	grad.set_offset(0, 0.0); grad.set_color(0, Color(0.04, 0.09, 0.14, 1.0))
	grad.set_offset(1, 1.0); grad.set_color(1, Color(0.02, 0.04, 0.07, 1.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad; gt.fill_from = Vector2(0.5, 0.0); gt.fill_to = Vector2(0.5, 1.0)
	var tr := TextureRect.new(); tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.texture = gt; tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)


func _font(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", _bold_font())
	l.add_theme_color_override("font_color", color)
	return l


func _bold_font() -> FontVariation:
	if _font_cache == null:
		var cjk := SystemFont.new()
		cjk.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "WenQuanYi Micro Hei", "sans-serif"])
		cjk.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK 网页/iOS 兜底 (SystemFont 在 web 取不到系统字体→中文乱码)
		cjk.font_weight = 700
		cjk.allow_system_fallback = true
		cjk.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font_cache = FontVariation.new()
		_font_cache.base_font = load("res://assets/fonts/m6x11.ttf") as FontFile
		_font_cache.fallbacks = [cjk]
	return _font_cache


func _build() -> void:
	# 整局已分胜负 → 结算面板 (不再显地图)
	if not _assigning and GameState.dual_match_over() != "":
		_build_settlement()
		return
	# 标题
	var title := _font(34, Color("#ffd93d"))
	title.text = "分路暗选 — 把 3 只统领分上 / 下路" if _assigning else "双路龟蛋攻防战"
	title.size = Vector2(W, 44); title.position = Vector2(0, 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(title)

	# 三条路 y 中心
	var lane_y := {"top": 200, "final": 380, "bottom": 560}
	var egg_left_cx := 120
	var egg_right_cx := 1160
	var lane_x0 := 250    # 路左端 (贴左蛋)
	var lane_x1 := 1030   # 路右端 (贴右蛋)

	# 先画路 (色条 + 节点), 再画蛋压在两端上方
	for lane in ["top", "final", "bottom"]:
		_build_lane(lane, lane_y[lane], lane_x0, lane_x1)

	# 左右龟蛋基地
	_build_egg("left", egg_left_cx, "我方龟蛋", Color("#5aa9ff"))
	var opp_name: String = str(GameState.dual_opponent.get("name", "")) if not GameState.dual_opponent.is_empty() else ""
	_build_egg("right", egg_right_cx, (opp_name + " 龟蛋") if opp_name != "" else "敌方龟蛋", Color("#ff6b6b"))

	# 局内等级 HUD (玩家) — 等级/XP条 (像TFT左下角). 买经验 + 统领装备 按钮已移除 (用户 2026-06-13:
	#   地图上不放买经验/统领装备; 装备改在战中常驻商店里上身, 经验走被动/战中).
	_build_level_hud()

	# 底部: 分路阶段=分配托盘; 否则=行动按钮
	if _assigning:
		_build_assign_tray()
	else:
		_build_action_bar()


func _build_lane(lane: String, cy: int, x0: int, x1: int) -> void:
	var names := {"top": "上路", "final": "终极战场", "bottom": "下路"}
	var winner := str(GameState.lane_results.get(lane, ""))
	var is_current: bool = GameState.current_lane == lane and winner == ""
	var done := winner != ""

	# 路色条
	var path := ColorRect.new()
	path.size = Vector2(x1 - x0, 14)
	path.position = Vector2(x0, cy - 7)
	if done:
		path.color = Color("#3a4a5a")
	elif is_current:
		path.color = Color("#ffd93d")
	else:
		path.color = Color("#23323f")
	content_root.add_child(path)

	# 中央战场节点
	var node_w := 200
	var node := _panel(Color("#16242f"), Color("#ffd93d") if is_current else Color("#33485a"), is_current)
	node.size = Vector2(node_w, 96)
	node.position = Vector2((x0 + x1) / 2.0 - node_w / 2.0, cy - 48)
	content_root.add_child(node)

	var lbl := _font(22, Color("#ffe9a8") if is_current else Color("#cfe3f5"))
	lbl.text = names[lane]
	lbl.size = Vector2(node_w, 30); lbl.position = Vector2(0, 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_child(lbl)

	# 状态行
	var st := _font(16, Color("#9fb6c9"))
	st.size = Vector2(node_w, 24); st.position = Vector2(0, 46)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if done:
		st.text = "🐢 我方胜" if winner == "left" else "👹 敌方胜"
		st.add_theme_color_override("font_color", Color("#7fd98a") if winner == "left" else Color("#ff9e9e"))
	elif is_current:
		st.text = "▶ 当前"
		st.add_theme_color_override("font_color", Color("#ffd93d"))
	else:
		st.text = "待战"
	node.add_child(st)

	# 该路双方阵容 (final 不显; 分路阶段敌方暗选→显❓)
	if lane != "final":
		var ll: Array = GameState.lane_assign.get(lane, [])
		var rr: Array = GameState.enemy_lane_assign.get(lane, [])
		var enemy_str := ("❓".repeat(maxi(1, rr.size())) if _assigning else _emojis(rr))
		if not ll.is_empty() or not enemy_str.is_empty():
			var info := _font(15, Color("#9fb6c9"))
			info.text = "%s  vs  %s" % [_emojis(ll) if not ll.is_empty() else "—", enemy_str]
			info.size = Vector2(560, 22); info.position = Vector2((x0 + x1) / 2.0 - 280, cy + 52)
			info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			content_root.add_child(info)


func _emojis(ids: Array) -> String:
	var out := ""
	for pid in ids:
		var pet: Dictionary = DataRegistry.pet_by_id.get(str(pid), {})
		out += str(pet.get("emoji", "🐢"))
	return out


func _build_egg(side: String, cx: int, label: String, accent: Color) -> void:
	var base := _panel(Color("#10202c"), accent, true)
	base.size = Vector2(190, 320)
	base.position = Vector2(cx - 95, 200)
	content_root.add_child(base)

	var emo := _font(72, Color.WHITE)
	emo.text = "🥚"
	emo.size = Vector2(190, 90); emo.position = Vector2(0, 30)
	emo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	base.add_child(emo)

	var name_l := _font(20, accent)
	name_l.text = label
	name_l.size = Vector2(190, 28); name_l.position = Vector2(0, 130)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	base.add_child(name_l)

	# 蛋血条
	var cur: int = int(GameState.egg_hp.get(side, 0))
	var mx: int = maxi(1, int(GameState.egg_hp_max.get(side, 0)))
	var frac := clampf(float(cur) / float(mx), 0.0, 1.0)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color("#0a1016"); bar_bg.size = Vector2(150, 20); bar_bg.position = Vector2(20, 175)
	base.add_child(bar_bg)
	var fill := ColorRect.new()
	fill.color = Color("#7fd98a") if frac > 0.3 else Color("#ff6b6b")
	fill.size = Vector2(150 * frac, 20); fill.position = Vector2(20, 175)
	base.add_child(fill)
	var hp_l := _font(15, Color.WHITE)
	hp_l.text = "%d / %d" % [cur, mx]
	hp_l.size = Vector2(150, 20); hp_l.position = Vector2(20, 175)
	hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	base.add_child(hp_l)


func _build_action_bar() -> void:
	var winner := GameState.dual_match_over()   # 胜负只看蛋: 谁蛋碎谁败
	var cur := GameState.current_lane
	if winner == "" and cur == "done":   # 终极打完但蛋未碎(极端安全网) → 按蛋血比例判
		winner = "left" if GameState.egg_frac("right") < GameState.egg_frac("left") else "right"
	var btn := Button.new()
	btn.add_theme_font_override("font", _bold_font())
	btn.add_theme_font_size_override("font_size", 24)
	btn.size = Vector2(360, 64)
	btn.position = Vector2(W / 2.0 - 180, 648)
	content_root.add_child(btn)

	if winner != "":
		# 整局已决出
		btn.text = "🏆 我方获胜 — 返回" if winner == "left" else "💀 战败 — 返回"
		btn.pressed.connect(func(): GameState.reset_dual_lane(); GameState.mode = "single"; get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	else:
		var names := {"top": "上路", "bottom": "下路", "final": "终极战场"}
		btn.text = "⚔ 进入%s" % names.get(cur, "战斗")
		btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Battle.tscn"))

	# 返回菜单小按钮
	var back := Button.new()
	back.add_theme_font_override("font", _bold_font())
	back.add_theme_font_size_override("font_size", 16)
	back.text = "← 退出"
	back.size = Vector2(90, 36); back.position = Vector2(24, 24)
	back.pressed.connect(func(): GameState.reset_dual_lane(); GameState.mode = "single"; get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	content_root.add_child(back)


# ─── 局内等级 HUD ────────────────────────────────────────────
func _build_level_hud() -> void:
	var lv := int(GameState.dual_level.get("left", 1))
	var xp := int(GameState.dual_xp.get("left", 0))
	var need := P2.xp_to_next(lv)
	var coins := int(GameState.dual_coins.get("left", 0))
	var panel := _panel(Color("#10202c"), Color("#5aa9ff"), false)
	panel.size = Vector2(250, 116); panel.position = Vector2(24, 70)
	content_root.add_child(panel)
	var lvl := _font(22, Color("#ffd93d"))
	lvl.text = "局内等级  Lv %d" % lv
	lvl.size = Vector2(230, 28); lvl.position = Vector2(12, 8)
	lvl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lvl)
	# XP 条
	var bar_bg := ColorRect.new(); bar_bg.color = Color("#0a1016")
	bar_bg.size = Vector2(226, 16); bar_bg.position = Vector2(12, 42)
	panel.add_child(bar_bg)
	if lv < P2.MAX_LEVEL:
		var fill := ColorRect.new(); fill.color = Color("#7fd98a")
		fill.size = Vector2(226 * clampf(float(xp) / float(need), 0.0, 1.0), 16); fill.position = bar_bg.position
		panel.add_child(fill)
	var xpl := _font(12, Color.WHITE)
	xpl.text = ("XP %d / %d" % [xp, need]) if lv < P2.MAX_LEVEL else "满级"
	xpl.size = Vector2(226, 16); xpl.position = Vector2(12, 42)
	xpl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xpl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(xpl)
	# 币 (买经验按钮已移除 — 用户 2026-06-13: 地图上不放买经验)
	var coin_l := _font(15, Color("#ffd166"))
	coin_l.text = "🪙 %d" % coins
	coin_l.size = Vector2(80, 24); coin_l.position = Vector2(12, 80)
	coin_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(coin_l)


# ─── 分路暗选 ───────────────────────────────────────────────
func _build_assign_tray() -> void:
	var ty := 666
	var cw := 300
	var xs := [30, 345, 660]
	for i in range(_player_team.size()):
		var pid: String = _player_team[i]
		var pet: Dictionary = DataRegistry.pet_by_id.get(pid, {})
		var cur := str(_assign.get(pid, ""))
		var chip := _panel(Color("#10202c"), Color("#ffd93d") if cur != "" else Color("#33485a"), cur != "")
		chip.size = Vector2(cw, 46); chip.position = Vector2(xs[i], ty)
		content_root.add_child(chip)
		var lbl := _font(17, Color.WHITE)
		lbl.text = "%s %s" % [str(pet.get("emoji", "🐢")), str(pet.get("name", pid))]
		lbl.size = Vector2(178, 46); lbl.position = Vector2(10, 0)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(lbl)
		var tb := _mini_btn("↑上", cur == "top")
		tb.position = Vector2(186, 6); tb.size = Vector2(52, 34)
		tb.pressed.connect(_assign_turtle.bind(pid, "top"))
		chip.add_child(tb)
		var bb := _mini_btn("↓下", cur == "bottom")
		bb.position = Vector2(242, 6); bb.size = Vector2(52, 34)
		bb.pressed.connect(_assign_turtle.bind(pid, "bottom"))
		chip.add_child(bb)
	# 开战 (全分配后启用)
	var all_assigned: bool = _player_team.all(func(t): return str(_assign.get(t, "")) != "")
	var go := Button.new()
	go.add_theme_font_override("font", _bold_font()); go.add_theme_font_size_override("font_size", 20)
	go.size = Vector2(265, 46); go.position = Vector2(985, ty)
	go.disabled = not all_assigned
	go.text = "⚔ 开战" if all_assigned else "把3只都分路"
	go.pressed.connect(_confirm_assign)
	content_root.add_child(go)
	# 返回
	var back := Button.new()
	back.add_theme_font_override("font", _bold_font()); back.add_theme_font_size_override("font_size", 16)
	back.text = "← 退出"; back.size = Vector2(90, 36); back.position = Vector2(24, 24)
	back.pressed.connect(func(): GameState.reset_dual_lane(); GameState.mode = "single"; get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	content_root.add_child(back)


func _assign_turtle(pid: String, lane: String) -> void:
	_assign[pid] = lane
	var top: Array = []
	var bot: Array = []
	for t in _player_team:
		var a := str(_assign.get(t, ""))
		if a == "top":
			top.append(t)
		elif a == "bottom":
			bot.append(t)
	GameState.lane_assign = {"top": top, "bottom": bot}
	_rebuild()


func _confirm_assign() -> void:
	_assigning = false
	GameState.current_lane = "top"
	get_tree().change_scene_to_file("res://scenes/Battle.tscn")


func _rebuild() -> void:
	for c in content_root.get_children():
		c.queue_free()
	_build()


func _mini_btn(text: String, on: bool) -> Button:
	var b := Button.new()
	b.add_theme_font_override("font", _bold_font())
	b.add_theme_font_size_override("font_size", 14)
	b.text = text
	if on:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#ffd93d"); sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", Color("#16242f"))
	return b


# ─── 结算面板 (整局结束) ─────────────────────────────────────
var _settlement_rewarded: bool = false
var _last_settlement_reward: int = 0
var _last_was_exhibition: bool = false
## V2 战后结算给币 (设计§三/§十五#2): 25 + 2×现有心 + 5×已失心 + (赢15). 心数玩法在阶段4, 此处用 hearts 字段(默认8).
func _grant_settlement_reward(won: bool) -> void:
	if _settlement_rewarded:
		return
	_settlement_rewarded = true
	_last_was_exhibition = GameState.is_eliminated()   # 进场前已0命 = 表演赛 (无stake)
	if not won and not _last_was_exhibition:
		GameState.lose_heart()   # V2 输→失一颗心 (0命=is_eliminated 淘汰); 表演赛不再掉命
	if _last_was_exhibition:
		_last_settlement_reward = 5   # 表演赛: 少量练手币, 不掉命/不计总战斗/不上榜 (设计§十五#2, 防送命换币刷)
	else:
		var lost_hearts: int = maxi(0, 8 - int(GameState.hearts))   # 8 = 赛季初始命数
		_last_settlement_reward = 25 + 2 * int(GameState.hearts) + 5 * lost_hearts + (15 if won else 0)
		GameState.season_total_battles += 1
		GameState.add_season_xp(2)   # V2: 每场 +2 大轮经验 (升级 → 驱动商店出货档 + 装备槽)
		if won:
			GameState.season_eggs_killed += 1   # 击碎对方龟蛋 → 排行榜口径 +1
		# 上传自己阵容快照进 ghost 池 (供别人异步匹配到; 非表演赛才传)
		var _gid := "g_%d_%d" % [int(GameState.season_id), int(Time.get_unix_time_from_system())]
		var _av := str(GameState.left_team[0]) if GameState.left_team.size() > 0 else "basic"
		Backend.upload_ghost(Backend.build_ghost_snapshot(_gid, {"name": "玩家阵容", "avatar": _av, "id": _gid}))
	GameState.meta_deepsea_coins += _last_settlement_reward
	GameState.save()


func _build_settlement() -> void:
	var winner := GameState.dual_match_over()
	var won := winner == "left"
	_grant_settlement_reward(won)   # V2 战后给币 (一次性, 设计§三)
	var accent := Color("#ffd93d") if won else Color("#ff6b6b")
	var big := _font(64, accent)
	big.text = "🏆 胜利!" if won else "💀 失败!"
	big.size = Vector2(W, 84); big.position = Vector2(0, 60); big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(big)
	var panel := _panel(Color("#0c1a26"), accent, true)
	panel.size = Vector2(660, 408); panel.position = Vector2(W / 2.0 - 330, 168)
	content_root.add_child(panel)
	# 对手头像
	var av_path := "res://assets/sprites/avatars/%s.png" % str(GameState.dual_opponent.get("avatar", "basic"))
	if ResourceLoader.exists(av_path):
		var tr := TextureRect.new(); tr.texture = load(av_path)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.size = Vector2(84, 84); tr.position = Vector2(330 - 42, 16)
		panel.add_child(tr)
	var vs_l := _font(22, Color.WHITE)
	vs_l.text = "你   VS   %s %s" % [str(GameState.dual_opponent.get("name", "野生对手")), str(GameState.dual_opponent.get("id", ""))]
	vs_l.size = Vector2(660, 28); vs_l.position = Vector2(0, 108); vs_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(vs_l)
	# 路结果
	var y := 160
	for lr in [["top", "上路"], ["bottom", "下路"]]:
		var w := str(GameState.lane_results.get(lr[0], ""))
		var res := "🐢 你赢" if w == "left" else ("👹 对手赢" if w == "right" else "—")
		var l := _font(20, Color("#cfe3f5"))
		l.text = "%s 战场：%s" % [lr[1], res]
		l.size = Vector2(560, 28); l.position = Vector2(60, y)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(l)
		y += 34
	var fin := _font(20, accent)
	fin.text = "终极：" + ("🐢 你击碎了对方龟蛋!" if won else "💀 你的龟蛋被击碎了")
	fin.size = Vector2(560, 28); fin.position = Vector2(60, y); fin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(fin)
	y += 40
	# 龟蛋最终血量
	var egg_l := _font(17, Color("#9fb6c9"))
	egg_l.text = "🥚 你 %d/%d    ·    🥚 对手 %d/%d" % [
		int(GameState.egg_hp.get("left", 0)), int(GameState.egg_hp_max.get("left", 0)),
		int(GameState.egg_hp.get("right", 0)), int(GameState.egg_hp_max.get("right", 0))]
	egg_l.size = Vector2(660, 24); egg_l.position = Vector2(0, y); egg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(egg_l)
	# V2 结算奖励 (深海币) — 设计§三
	var rwd_l := _font(20, Color("#ffd93d"))
	rwd_l.text = "💠 深海币 +%d   (累计 %d)" % [_last_settlement_reward, int(GameState.meta_deepsea_coins)]
	rwd_l.size = Vector2(660, 28); rwd_l.position = Vector2(0, y + 30); rwd_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(rwd_l)
	# V2 命数变化 (输→-1; 0命=淘汰; 赢→保住) — 设计§二/§十五
	var hp_txt: String
	if _last_was_exhibition:
		hp_txt = "🎯 表演赛 (已淘汰 · 0 命 · 无 stake)"
	elif GameState.is_eliminated():
		hp_txt = "💀 0 命 — 本赛季淘汰 (下局起表演赛)"
	elif won:
		hp_txt = "❤ 命 %d/8 (保住)" % int(GameState.hearts)
	else:
		hp_txt = "💔 失去 1 命 → 剩 %d/8" % int(GameState.hearts)
	var hp_l := _font(18, Color("#9fe6b0") if won else Color("#ff9aa2"))
	hp_l.text = hp_txt
	hp_l.size = Vector2(660, 26); hp_l.position = Vector2(0, y + 58); hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hp_l)
	# 返回
	var back := Button.new()
	back.add_theme_font_override("font", _bold_font()); back.add_theme_font_size_override("font_size", 22)
	back.text = "返回主菜单"
	back.size = Vector2(300, 56); back.position = Vector2(W / 2.0 - 150, 620)
	back.pressed.connect(func():
		GameState.reset_dual_lane(); GameState.dual_opponent = {}; GameState.mode = "single"
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	content_root.add_child(back)


# 圆角占位面板 (StyleBoxFlat)
func _panel(bg: Color, border: Color, glow: bool) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2 if not glow else 3)
	sb.border_color = border
	p.add_theme_stylebox_override("panel", sb)
	return p
