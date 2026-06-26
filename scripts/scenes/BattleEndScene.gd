extends Control

## BattleEndScene — 战斗结算屏 (1:1 PoC BattleEndScene.ts)
## 读 GameState.last_battle_result, 显示 胜负 + 伤害统计表 + 龟币奖励 + 按钮路由.
## 龟币: 胜=50+floor(总伤/100), 负/平=10. runEnded/runWon 控战绩计数 (深海中途胜只累币).

const RARITY_COLOR := {
	"C": Color("#06d6a0"), "B": Color("#4cc9f0"), "A": Color("#3a9abf"),
	"S": Color("#c77dff"), "SS": Color("#ffd93d"), "SSS": Color("#ff6b6b"),
}


func _ready() -> void:
	var res: Dictionary = GameState.last_battle_result
	if res.is_empty():
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return

	var won: bool = res.get("player_won", false)
	var tie: bool = res.get("tie", false)
	var mode: String = res.get("mode", "single")
	var stage: int = int(res.get("dungeon_stage", 1))
	var is_dungeon: bool = mode == "dungeon" and stage > 0
	var is_last: bool = res.get("is_boss", false)
	var total_dmg: int = int(res.get("total_dmg", 0))

	# ── 结算: 龟币 + 战绩 + 存档 (PoC BattleEndScene:108-136) ──
	var coin_reward: int = (50 + int(total_dmg / 100.0)) if won else 10
	var run_ended: bool = (not is_dungeon) or (not won) or is_last
	var run_won: bool = won and ((not is_dungeon) or is_last)
	GameState.coins += coin_reward
	if run_ended:
		GameState.battles_total += 1
		if run_won:
			GameState.battles_won += 1
	if is_dungeon and won and stage > GameState.best_dungeon_stage:
		GameState.best_dungeon_stage = stage
	# PoC 结算【不掉装备】(装备只来自 初始3选1 + 商店 + 闯关奖励/事件 → 装备席)。移除自创的胜利随机掉落。
	var dropped := ""
	GameState.save()
	# 记对局 (战绩用) — 深海中途胜不记 (run 未结束)
	if run_ended:
		# lineup 用实际上阵阵容(res.lineup = BattleScene 收的 fighters id) — 比 GameState.left_team 可靠
		#   (默认/教程/野生场 has_team()=false 时 left_team 空 → 战绩无头像 bug)
		var rec_lineup: Array = res.get("lineup", [])
		if rec_lineup.is_empty():
			rec_lineup = GameState.left_team.duplicate()
		GameState.record_match("win" if won else "lose", rec_lineup, mode, int(res.get("turn", 0)))

	# ── 成就 tracker 挂钩 (1:1 PoC BattleEndScene.ts:148-168) ──
	#   深海胜利记最佳层数 (PoC:149-154); 战斗结束累计统计+查成就; 赚币累计.
	#   per_battle 统计来自 player_stats: 总伤(dmgDealt)/总击杀(kills)/全员存活(alive).
	#   暴击数: Godot battle_stats 不记暴击 → 传 0 (crit_100/暴击类成就因统计字段缺跳过, 已在 tracker 注明).
	var new_ach: Array = []
	var result_str: String = "win" if won else "lose"
	if is_dungeon and won:
		AchievementTracker.set_best_dungeon(stage)
	var pb_dmg: int = 0
	var pb_kills: int = 0
	var pb_all_alive: bool = true
	var p_stats: Array = res.get("player_stats", [])
	for ps in p_stats:
		pb_dmg += int(ps.get("dmgDealt", 0))
		pb_kills += int(ps.get("kills", 0))
		if not bool(ps.get("alive", false)):
			pb_all_alive = false
	if p_stats.is_empty():
		pb_all_alive = false
	new_ach = AchievementTracker.on_battle_end(
		result_str, GameState.left_team.duplicate(), res.get("rule", ""),
		pb_dmg, int(res.get("crits", 0)), pb_kills, pb_all_alive)
	for id in AchievementTracker.on_coins_earned(coin_reward):
		if not (id in new_ach):
			new_ach.append(id)

	Audio.play_bgm("menu", 0.6)
	# 胜/负 SFX (PoC BattleEndScene.ts:97: sound.play(isWin ? 'sfx-crit' : 'sfx-defeat', {volume:0.5}))
	#   PoC BootScene: 'sfx-crit'=hit-crit.wav (Godot key "hit-crit"), 'sfx-defeat'=defeat.wav (Godot key "defeat")
	Audio.play_sfx("hit-crit" if won else "defeat", 0.5)
	_build_ui(res, won, tie, is_dungeon, is_last, stage, coin_reward, dropped)
	# 新解锁成就 toast (右侧逐个滑入, PoC BattleEndScene.ts:202-217)
	if not new_ach.is_empty():
		_show_achievement_toasts(new_ach)


const W := 1280.0
const H := 720.0


func _build_ui(res: Dictionary, won: bool, tie: bool, is_dungeon: bool, is_last: bool,
		stage: int, coin_reward: int, dropped: String) -> void:
	# 背景 — PoC BattleEndScene: 相机底 #0a1726 + menu-bg 图(废墟) + 0.7 黑遮罩
	#   (这是唯一真用 menu-bg 橙图的场景: PoC 用 add.image('menu-bg') GameObject, 非 menu-bg-active tile)
	var camera_bg := ColorRect.new()
	camera_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	camera_bg.color = Color("#0a1726")
	add_child(camera_bg)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg.png"):
		bg.texture = load("res://assets/sprites/menu/menu-bg.png")
	add_child(bg)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	add_child(dim)

	# 标题 (PoC: cx,90, 88px bold, 胜金/负红, 描边)
	var title_txt: String
	var title_col: String
	if tie:
		title_txt = "平局"; title_col = "#ccdddd"
	elif won:
		title_txt = "胜利"   # 1:1 PoC BattleEndScene.ts:87 标题恒"胜利"/"失败"; "通关"只在按钮(ts:187), 原 Godot 自创覆盖标题=偏差
		title_col = "#ffd93d"
	else:
		title_txt = "失败"; title_col = "#ff5050"
	var title_lbl := _text(title_txt, W / 2.0, 90, 88, title_col, true, 10)
	# 标题入场 (PoC BattleEndScene.ts:93-94: setScale(0.3).setAlpha(0) → tween scale 1, alpha 1, 500ms back.out)
	title_lbl.pivot_offset = title_lbl.size / 2.0
	title_lbl.scale = Vector2(0.3, 0.3)
	title_lbl.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(title_lbl, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(title_lbl, "modulate:a", 1.0, 0.5)

	# 副标题 (PoC: cx,160, 16px#aaa — 回合 + 规则)
	var rule_txt: String = res.get("rule", "")
	_text("%d 回合%s" % [int(res.get("turn", 0)), (" · " + rule_txt) if rule_txt != "" else ""], W / 2.0, 160, 16, "#aaa", false, 0)

	# 伤害统计表 (PoC renderStatsTable: 表头@240, 分隔线, 行 rowH 28)
	_stats_table(W / 2.0, 200, res.get("player_stats", []))

	# 龟币奖励 (PoC: cx, height-180, 28px金 bold)
	_text("🪙 +%d 龟币" % coin_reward, W / 2.0, H - 180, 28, "#ffd93d", true, 4)
	var loot_txt := ("  ·  🎁 " + EquipmentRuntime.display_name(dropped)) if dropped != "" else ""
	_text("当前: %d 龟币 · 累计 %d 场 · %d 胜%s" % [GameState.coins, GameState.battles_total, GameState.battles_won, loot_txt], W / 2.0, H - 180 + 32, 12, "#888", false, 0)

	# 按钮 (PoC: height-90, 220×50; 双按钮 cx∓130) — PoC delayedCall(600) 后建, 这里直接建
	if is_dungeon and won and not is_last:
		_btn(W / 2.0 - 130, H - 90, "选奖励 → 第 %d 关" % (stage + 1), _on_next_stage)
		_btn(W / 2.0 + 130, H - 90, "主菜单", _on_main_menu)
	elif is_dungeon and won and is_last:
		_btn(W / 2.0, H - 90, "🏆 通关! 返回菜单", _on_main_menu)
	else:
		_btn(W / 2.0 - 130, H - 90, "再战", _on_rematch)
		_btn(W / 2.0 + 130, H - 90, "主菜单", _on_main_menu)


# ── PoC renderStatsTable: 7 列 (龟/出伤/受伤/治疗/暴击/击杀/剩余), 列偏移相对 centerX ──
func _stats_table(center_x: float, top_y: float, stats: Array) -> void:
	# PoC cols: 龟@-360, 出伤@-240, 受伤@-150, 治疗@-60, 暴击@40, 击杀@110, 剩余@220
	var col_x := [-360.0, -240.0, -150.0, -60.0, 40.0, 110.0, 220.0]
	var headers := ["龟", "出伤", "受伤", "治疗", "暴击", "击杀", "剩余"]
	var head_y := top_y + 40.0
	for i in range(headers.size()):
		_cell(headers[i], center_x + col_x[i], head_y, 13, "#ffd93d", true)
	# 分隔线 (PoC: 780×1 @headY+16 #ffd93d.5)
	var sep := ColorRect.new()
	sep.color = Color(1.0, 0.851, 0.239, 0.5)   # #ffd93d @0.5
	sep.size = Vector2(780, 1)
	sep.position = Vector2(center_x - 390, head_y + 16)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sep)
	# 行 (PoC rowH 28, 起始 headY+28)
	var row_h := 28.0
	for i in range(stats.size()):
		var ps: Dictionary = stats[i]
		var y := head_y + 28.0 + i * row_h
		var alive: bool = ps.get("alive", false)
		var col := "#ffffff" if alive else "#888888"
		var suffix := "" if alive else " (阵亡)"
		# 龟名 + 稀有度小角标(@-38)
		_cell("%s%s" % [ps.get("name", "?"), suffix], center_x + col_x[0], y, 13, col, false)
		var rarity: String = ps.get("rarity", "C")
		var rar_col: Color = RARITY_COLOR.get(rarity, Color.WHITE)
		_cell(rarity, center_x + col_x[0] - 38, y, 10, "#%02x%02x%02x" % [int(rar_col.r * 255), int(rar_col.g * 255), int(rar_col.b * 255)], true)
		# PoC healing 字段名: healDone; chain 用 healing — 兼容取
		var heal_v: int = int(ps.get("healDone", ps.get("healing", 0)))
		_cell(str(ps.get("dmgDealt", 0)), center_x + col_x[1], y, 13, col, false)
		_cell(str(ps.get("dmgTaken", 0)), center_x + col_x[2], y, 13, col, false)
		_cell(str(heal_v), center_x + col_x[3], y, 13, col, false)
		_cell(str(ps.get("crits", 0)), center_x + col_x[4], y, 13, col, false)
		_cell(str(ps.get("kills", 0)), center_x + col_x[5], y, 13, col, false)
		_cell("%d/%d" % [int(ps.get("hp", 0)), int(ps.get("maxHp", 0))], center_x + col_x[6], y, 13, col, false)


# ── 表格单元 (Phaser setOrigin(0.5) → 居中, 窄 Label) ──
func _cell(text: String, cx: float, cy: float, size: int, color: String, bold: bool) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(color))
	if bold:
		l.add_theme_constant_override("outline_size", 0)
	l.size = Vector2(120, float(size) + 10)
	l.position = Vector2(cx - 60, cy - (float(size) + 10) / 2.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


# ── 居中文字 (Phaser setOrigin(0.5)) ──
func _text(text: String, cx: float, cy: float, size: int, color: String, bold: bool, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(color))
	if bold and outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", outline)
	l.size = Vector2(900, float(size) + 16)
	l.position = Vector2(cx - 450, cy - (float(size) + 16) / 2.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


# ── 按钮 (PoC makeButton: btn-frame 220×50 + 20px bold 棕字) ──
func _btn(cx: float, cy: float, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size = Vector2(220, 50)
	b.position = Vector2(cx - 110, cy - 25)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color("#3a1f00"))
	if ResourceLoader.exists("res://assets/sprites/menu/btn-frame.png"):
		var sb := StyleBoxTexture.new()
		sb.texture = load("res://assets/sprites/menu/btn-frame.png")
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
	b.pressed.connect(cb)
	add_child(b)
	# 从中心缩放 (pivot) — size 已设定, 立即可用
	b.pivot_offset = b.size / 2.0
	# hover scale 1.05 / press scale 0.96 yoyo (PoC makeButton ts:282-291)
	b.mouse_entered.connect(func() -> void:
		var t := create_tween()
		t.tween_property(b, "scale", Vector2(1.05, 1.05), 0.1))
	b.mouse_exited.connect(func() -> void:
		var t := create_tween()
		t.tween_property(b, "scale", Vector2.ONE, 0.1))
	b.button_down.connect(func() -> void:
		var t := create_tween()
		t.tween_property(b, "scale", Vector2(0.96, 0.96), 0.06)
		t.tween_property(b, "scale", Vector2(1.05, 1.05) if b.get_global_rect().has_point(b.get_global_mouse_position()) else Vector2.ONE, 0.06))
	# 按钮入场 (PoC delayedCall(600) 后才建按钮 → 这里 0.6s delay 淡入)
	b.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(b, "modulate:a", 1.0, 0.2)


func _on_next_stage() -> void:
	# 深海胜利非末关 → 推进关卡号 → 奖励选择 (RewardPick → 50%事件 → Dungeon → Battle)
	GameState.advance_stage()
	get_tree().change_scene_to_file("res://scenes/RewardPick.tscn")


func _on_rematch() -> void:
	if GameState.mode == "single":
		get_tree().change_scene_to_file("res://scenes/TeamSelect.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Battle.tscn")


func _on_main_menu() -> void:
	if GameState.mode == "dungeon":
		GameState.reset_dungeon()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# ── 成就解锁 toast (1:1 PoC BattleEndScene.ts:202-217) ──
#   右侧逐个滑入: 容器锚 (W-20, 100+i*50), 280×36 黑底@0.9 + 2px #ffd93d 边, origin(1,0.5);
#   文字 "🏆 解锁: <name>" 13px #ffd93d bold, origin(1,0.5) 右贴 (-10).
#   入场: alpha0 起于 x=W+100 → tween 到 x=W-20, alpha1, 350ms back.out, 延迟 800+i*1100ms.
#   停留 2500ms 后 alpha→0 300ms 销毁.
#   (PoC 用 id 文本; Godot 改用成就 name 更可读, 取不到则回退 id.)
func _show_achievement_toasts(ids: Array) -> void:
	for i in range(ids.size()):
		var id: String = ids[i]
		var ach: Dictionary = DataRegistry.achievements_by_id.get(id, {})
		var label_txt: String = "🏆 解锁: %s" % ach.get("name", id)
		var anchor_y := 100.0 + float(i) * 50.0
		# 容器 = Control, 右边缘对齐 (origin 1,0.5 → x 是右边缘). 用 right_x 表示右边缘.
		var holder := Control.new()
		holder.size = Vector2(280, 36)
		holder.pivot_offset = Vector2(280, 18)   # origin(1, 0.5)
		holder.position = Vector2((W + 100.0) - 280.0, anchor_y - 18.0)   # 起始: 右边缘在 W+100
		holder.modulate.a = 0.0
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		# 黑底 + 金边
		var bg := Panel.new()
		bg.size = Vector2(280, 36)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.9)
		sb.set_border_width_all(2)
		sb.border_color = Color("#ffd93d")
		bg.add_theme_stylebox_override("panel", sb)
		holder.add_child(bg)
		# 文字 (右贴 -10)
		var txt := Label.new()
		txt.text = label_txt
		txt.add_theme_font_size_override("font_size", 13)
		txt.add_theme_color_override("font_color", Color("#ffd93d"))
		txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		txt.size = Vector2(270, 36)
		txt.position = Vector2(0, 0)
		txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(txt)
		# 入场: 延迟 800+i*1100ms → 滑入 + 淡入 350ms back.out → 停 2500ms → 淡出 300ms
		var target_x := (W - 20.0) - 280.0   # 右边缘对齐 W-20
		var delay := 0.8 + float(i) * 1.1
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.set_parallel(true)
		tw.tween_property(holder, "position:x", target_x, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(holder, "modulate:a", 1.0, 0.35)
		tw.set_parallel(false)
		tw.tween_interval(2.5)
		tw.tween_property(holder, "modulate:a", 0.0, 0.3)
		tw.tween_callback(holder.queue_free)
