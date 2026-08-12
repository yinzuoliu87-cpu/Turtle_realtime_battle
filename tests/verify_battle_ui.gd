extends Node
## verify_battle_ui.gd — 守卫 R2a/R2b: 战斗内 UX (结束按钮化 / 投降 / 战斗日志)
## 用户〖2026-07-11〗:「战斗结束不要什么点R/ESC, 要按钮的形式, 暂停, ...日志等都通吗」
## 用户〖2026-07-30〗:「战斗日志按钮移除掉，暂停按钮移除掉，局内不再有退出去或暂停的按钮了，
##   新增投降按钮，点击后有确认认输的提示框」→ A 组从"暂停"改为"投降 + 暂停不许回来"。
##
## 断言(功能层, 像素布局仍需 F5 眼验):
##   A. ★暂停按钮/面板/开关【必须不存在】(反向断言 —— 不是删掉旧断言, 否则谁加回来都没人知道);
##      投降按钮/确认框已建; 弹框→取消不结算 / 弹框→确认走判负三件套; _settled 后不响应。
##   B. 战斗日志 _log 追加 + 封顶 _LOG_CAP(200); _toggle_log 显隐面板且开时重建文本。
##      （U3: 只删了 📜 按钮, _log()/面板/_toggle_log 全保留 —— 所以本组照旧。）
##   C. 结算 _show_banner 生成 2 个操作 Button(再战/返回菜单), 且结算后【投降】按钮被禁。
##
## ★注意: 测试根节点 process_mode=ALWAYS, 且结尾复位 paused=false(否则暂停态会冻住后续 await)。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 按【文案】数按钮 —— 结算页会叠加多层, 只数总数看不出"这一层有没有多长一个"。
func _count_btn_text(n: Node, txt: String) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is Button and (ch as Button).text == txt:
			c += 1
		c += _count_btn_text(ch, txt)
	return c


func _count_buttons(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is Button:
			c += 1
		c += _count_buttons(ch)
	return c


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停时本测试仍能推进
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	# 停掉战斗 _process/_physics: 本测试往 _units 塞精简假单位验统计 UI, 不想触发逐帧战斗逻辑读 pos/sprite 等字段.
	scene.set_process(false)
	scene.set_physics_process(false)

	# ── A. 投降(取代暂停) ──
	# ★反向断言: 暂停的三件东西【一个都不许再出现】。
	#   写成"不存在"而不是把旧断言删掉 —— 删掉的话, 以后谁把暂停加回来, 门禁一声不响。
	_ok("★暂停按钮字段不存在", not ("_pause_btn" in scene))
	_ok("★暂停面板字段不存在", not ("_pause_panel" in scene))
	_ok("★_toggle_pause 已移除", not scene.has_method("_toggle_pause"))
	_ok("★_CamInputRelay 内部类已移除(它只为暂停存在)",
		not FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd").contains("class _CamInputRelay extends Node:"))
	# 投降按钮 + 确认框
	_ok("投降按钮已建", scene._surrender_btn != null)
	_ok("投降确认框已建且默认隐藏",
		scene._surrender_panel != null and not scene._surrender_panel.visible)
	scene._show_surrender_confirm()
	_ok("点投降: 确认框弹出", scene._surrender_panel.visible == true)
	# ★弹框【不暂停】战斗(U6: 用户说"不再有暂停")
	_ok("★弹框期间战斗没被暂停", get_tree().paused == false)
	# 取消 = 什么都不发生
	scene._hide_surrender_confirm()
	_ok("点取消: 确认框收起", scene._surrender_panel.visible == false)
	_ok("★点取消【不】结算(_over 仍 false)", scene._over == false)
	_ok("★点取消【不】结算(_settled 仍 false)", scene._settled == false)
	# 确认认输 = 判负三件套(_over / 喂赛季 / 显横幅)
	scene._show_surrender_confirm()
	scene._do_surrender()
	await get_tree().process_frame
	_ok("★点确认认输: _over=true(判负)", scene._over == true)
	_ok("★点确认认输: 确认框已收起", scene._surrender_panel.visible == false)
	_ok("★点确认认输: 走了横幅路径(_settled=true)", scene._settled == true)
	# _settled 后不响应
	scene._surrender_panel.visible = false
	scene._show_surrender_confirm()
	_ok("★结算后点投降不响应(框不弹)", scene._surrender_panel.visible == false)
	scene._settled = false
	scene._over = false

	# ── B. 战斗日志 ──
	scene._battle_log.clear()
	for i in range(scene._LOG_CAP + 60):
		scene._log("[color=#fff]行 %d[/color]" % i)
	_ok("日志封顶 _LOG_CAP=%d" % scene._LOG_CAP, scene._battle_log.size() == scene._LOG_CAP,
		"实际 %d" % scene._battle_log.size())
	_ok("日志封顶后保留最新(删最旧)", str(scene._battle_log[-1]).find("行 %d" % (scene._LOG_CAP + 59)) >= 0)
	scene._toggle_log()
	_ok("日志面板开", scene._log_panel.visible == true)
	_ok("开面板后富文本非空", scene._log_rt != null and scene._log_rt.get_paragraph_count() > 0)
	scene._toggle_log()
	_ok("日志面板关", scene._log_panel.visible == false)

	# ── D. 战中统计: 类型分桶 + 面板 + 召唤体单列 ──
	_ok("_dmg_bucket raw=真实", scene._dmg_bucket(true, Color("#ff4444")) == "tru")
	_ok("_dmg_bucket 蓝=法术", scene._dmg_bucket(false, Color("#4dabf7")) == "mag")
	_ok("_dmg_bucket 红=物理", scene._dmg_bucket(false, Color("#ff4444")) == "phy")
	var probe: Dictionary = {}
	scene._st_add_type(probe, "_st_dealt_by_type", "phy", 10)
	scene._st_add_type(probe, "_st_dealt_by_type", "phy", 5)
	_ok("_st_add_type 累加同桶", int((probe["_st_dealt_by_type"] as Dictionary).get("phy", 0)) == 15)
	# 造 3 个单位(主龟+召唤体+敌) 喂进 _units
	var ua: Dictionary = {"id": "basic", "name": "甲", "side": "left", "alive": true, "hp": 100, "maxHp": 100, "rarity": "A", "_st_dealt": 300, "_st_dealt_by_type": {"phy": 200, "mag": 80, "tru": 20}, "_st_heal": 50, "_st_shield": 30, "_st_crit": 2, "_st_kills": 1}
	var ub: Dictionary = {"id": "minion", "name": "随从", "side": "left", "alive": true, "hp": 40, "maxHp": 60, "is_summon": true, "_st_dealt": 120, "_st_dealt_by_type": {"phy": 120}}
	var uc: Dictionary = {"id": "stone", "name": "乙", "side": "right", "alive": false, "hp": 0, "maxHp": 100, "rarity": "C", "_st_taken": 420, "_st_taken_by_type": {"phy": 300, "dot": 120}}
	scene._units.clear()
	scene._units.append(ua); scene._units.append(ub); scene._units.append(uc)
	scene._on_dmg_stats_toggle()
	var dsp = scene._dmg_stats
	_ok("战中统计面板开", dsp != null and dsp.panel != null and dsp.panel.visible)
	dsp.render()
	var left_col: VBoxContainer = dsp._cols[0]
	var left_rows: int = left_col.get_child_count()
	_ok("我方列 2 行(主龟+召唤体单列一行)", left_rows == 2, "行数=%d" % left_rows)
	for tb in ["taken", "heal", "shield"]:
		dsp._tab = tb; dsp.render()
	dsp._tab = "dealt"
	_ok("4 Tab 切换渲染不崩", true)

	# ── D2. ★统计面板必须回到最上层("换路后被头像栏盖住"那个 bug) ──
	# 探针实测的数字: 开局 面板 index=21 / 左队头像栏 15 (面板在上, 正常);
	#   换一次路后 面板 19 / 左队栏 20 → 【被盖住】。根因是 _build_team_panels()
	#   在换路时重建左右队头像栏, add_child 让它们落到 _ui_layer 末尾, 把先建的面板压下去。
	# ★只在 toggle() 里提到最前【不够】: 面板【开着的时候换路】不会再调 toggle(),
	#   所以 render() 里也提一次(每 0.4s 自刷 = 自愈)。下面三条分别验:
	#   ①提得动 ②这个 bug 真的存在(否则是空检查) ③自刷能治。
	var lay: CanvasLayer = scene._ui_layer
	dsp._to_front()
	await get_tree().process_frame
	_ok("D2 面板能提到 _ui_layer 最上层",
		lay.get_child(lay.get_child_count() - 1) == dsp.panel,
		"面板 index=%d / 共 %d 个子节点" % [dsp.panel.get_index(), lay.get_child_count()])
	scene._hud._build_team_panels()      # 模拟换路: 重建头像栏 → 追加到末尾
	await get_tree().process_frame
	_ok("D2 ★换路后面板确实被压下去(证明这个 bug 是真的·不是空检查)",
		lay.get_child(lay.get_child_count() - 1) != dsp.panel,
		"面板 index=%d / 共 %d" % [dsp.panel.get_index(), lay.get_child_count()])
	dsp.render()                         # 模拟 0.4s 一次的自刷
	await get_tree().process_frame
	_ok("D2 ★★自刷把面板顶回最上层(面板开着换路也能自愈)",
		lay.get_child(lay.get_child_count() - 1) == dsp.panel,
		"面板 index=%d / 共 %d" % [dsp.panel.get_index(), lay.get_child_count()])
	_ok("D2 面板自带 ✕ 关闭键(不用跑到屏幕另一头再点统计键)",
		FileAccess.get_file_as_string("res://scripts/scenes/battle/dmg_stats_panel.gd").contains('"✕"'))
	scene._on_dmg_stats_toggle()   # 关

	# ── C. 结算按钮化 (此时 _units 已有 3 单位 → 7 列结算表真渲染) ──
	scene._hud._show_banner(true)
	await get_tree().process_frame
	var btns := _count_buttons(scene._ui_layer)
	_ok("结算后 UI 层有操作按钮(再战/返回菜单等 ≥2)", btns >= 2, "共 %d 个 Button" % btns)
	_ok("结算后投降按钮被禁", scene._surrender_btn.disabled == true)

	# ── C2. ★结算页「前往商店」(2026-08-03) ──────────────────────────────
	# 自走棋的循环是【打 → 买 → 再打】, 而原来结算页只有"返回主菜单":
	#   玩家得自己想起来去商店、再自己回主菜单点开始战斗 —— 循环是断的。
	#   (教学模式分支早就给了"前往商店", 只是正式对局没用上。)
	# ⚠ 赛季淘汰(hearts<=0)时【商店是锁的】(MainMenuScene 里锁匹配+商店),
	#   所以那时不能给这个按钮 —— 否则点进去是个锁死的页面。
	# 下面三条: ①按钮在 ②它指的场景真存在 ③★淘汰时不长出来(差分, 不是空检查)。
	# ★用【差分】不用总数: 这个测试前面已经结算过一次(_do_surrender), UI 层里本来就躺着
	#   一张旧结算卡 —— 数总数会把它算进来(实测 2 个, 而每张卡只有 1 个)。
	#   差分 = "再建一张卡, 这张卡里多长出几个" —— 与历史残留无关。
	var gs2 = get_node_or_null("/root/GameState")
	var hearts0: int = int(gs2.hearts)
	var base_n := _count_btn_text(scene._ui_layer, BattleHud.SHOP_BTN_TEXT)
	gs2.hearts = maxi(1, hearts0)        # 未淘汰
	scene._settled = false               # _show_banner 开头有 `if _settled: return`
	scene._hud._show_banner(true)
	await get_tree().process_frame
	var live_n := _count_btn_text(scene._ui_layer, BattleHud.SHOP_BTN_TEXT)
	_ok("C2 结算页给【%s】按钮" % BattleHud.SHOP_BTN_TEXT,
		live_n - base_n == 1, "这一张卡新增 %d 个" % (live_n - base_n))
	_ok("C2 按钮指向的场景真存在(%s)" % BattleHud.SHOP_SCENE,
		ResourceLoader.exists(BattleHud.SHOP_SCENE))
	# ── C2b. ★★结算按钮【必须在屏幕里】—— 用户 2026-08-12 实测:
	#   「结算时数量单位过多还是会导致按钮被挤下去, 我手机是钮点不到」。
	#   结算卡是 CenterContainer 按最小尺寸居中, 数据表行数随参战单位数长 ⇒ 一超视口
	#   就上下溢出, 按钮掉出屏幕 = 整局卡死在结算页。
	#   ★判据必须是【坐标在视口内】: 只断言"按钮存在"守不住 —— 掉到屏幕外的按钮同样存在。
	#   ★灌一张【很长】的数据表再验: 单位少时本来就不会溢出, 那样验等于空检查。
	for _i in range(60):
		var _fake: Dictionary = _mk_unit_for_stats(_i)
		scene._units.append(_fake)
	scene._settled = false
	scene._hud._show_banner(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp_h: float = scene.get_viewport().get_visible_rect().size.y
	var worst_bottom := -1.0
	var found := 0
	for b in _btns_with_text(scene._ui_layer, BattleHud.SHOP_BTN_TEXT):
		found += 1
		var r: Rect2 = (b as Control).get_global_rect()
		worst_bottom = maxf(worst_bottom, r.end.y)
	_ok("C2b ★分母: 灌了 60 个单位后仍找得到结算按钮", found >= 1, "找到 %d 个" % found)
	_ok("C2b ★★按钮整体在视口内(底边 %.0f ≤ 视口高 %.0f) —— 挤出屏幕就是点不到"
			% [worst_bottom, vp_h], found >= 1 and worst_bottom <= vp_h + 0.5)
	# 淘汰态再结算一次: 这一张卡【一个都不该多】。
	## ★重新取基线: 上面 C2b 为了撑长数据表又结算了一张卡, 不重新取会把它算进差分里。
	live_n = _count_btn_text(scene._ui_layer, BattleHud.SHOP_BTN_TEXT)
	gs2.hearts = 0                       # → is_eliminated() = true
	scene._settled = false
	scene._hud._show_banner(false)
	await get_tree().process_frame
	var elim_n := _count_btn_text(scene._ui_layer, BattleHud.SHOP_BTN_TEXT)
	_ok("C2 ★淘汰(0命)时不给商店按钮 —— 商店此时是锁的",
		elim_n - live_n == 0, "淘汰那张卡新增 %d 个(应 0)" % (elim_n - live_n))
	gs2.hearts = hearts0

	# 复位, 防暂停态影响
	get_tree().paused = false
	_done()


func _done() -> void:
	get_tree().paused = false
	print("")
	if _fail == 0:
		print("ALL PASS — 战斗内 UX(结束按钮/投降/日志) 功能守卫通过")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 取出所有文案匹配的按钮节点(判据要量【坐标】, 只数个数守不住"掉出屏幕")。
func _btns_with_text(root: Node, txt: String) -> Array:
	var out: Array = []
	if root is Button and str((root as Button).text) == txt:
		out.append(root)
	for c in root.get_children():
		out.append_array(_btns_with_text(c, txt))
	return out


## 造一个只为撑长结算数据表的假单位。
func _mk_unit_for_stats(i: int) -> Dictionary:
	return {"id": "green", "name": "凑数%d" % i, "side": ("left" if i % 2 == 0 else "right"),
		"alive": false, "hp": 0.0, "maxHp": 100.0, "shield": 0.0,
		"_st_dmg": 100 + i, "_st_taken": 50 + i, "_st_heal": i, "equips": [], "eq_state": {}}
