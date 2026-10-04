extends Node
## verify_result_reachable.gd — 结算屏【按钮必须点得到】门禁 (2026-08-10)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 用户实测「战斗结束后如果名单很多, 根本点不到回到主菜单的按钮」
## ══════════════════════════════════════════════════════════════════
## (2026-08-10 当时) 结算卡是 `CenterContainer > PanelContainer > VBoxContainer`, 按钮行加在
## 【数据表下面】。★2026-10-04 起结算屏是三页(settle_screen.gd): 左栏页签 + 金属框正文,
## 按钮行在页体外面; 本门禁的判据(按钮完整在屏内 / 引擎命中测试 / 提示行数对得上)照旧,
## 只是「找结算卡」改成找 `SettleScreen` 里的 `SettleFrame`, 长名单改在【我方页】上量。而数据表那个 ScrollContainer **没有任何高度上限** ——
## 名单一长, 整张卡就比视口还高; CenterContainer 居中它 ⇒ **上下两头都溢出屏幕**,
## 按钮行正好在下面那一头 ⇒ 点不到, 玩家被卡死在结算屏(只能杀进程)。
##
## ★这条为什么必须量【真实屏幕矩形】而不是"算一下高度":
##   memory [[fb-write-without-reader-and-fake-gates]] —— 门禁模拟公式 ≠ 量真实对象。
##   这里一律走 `get_global_rect()`, 并要求它**完整落在视口内**。
##
## ★分母: 必须真的造出一份【长名单】, 否则卡片不够高、这条断言永远绿(空检查)。
##   所以先塞满单位再开结算, 并断言"卡片确实比某个下限高"。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_result_reachable.tscn --quit-after 1800

const SCENE := "res://scenes/RealtimeBattle3D.tscn"
## 副标题那句话的**唯一出处** —— 测试不许自己拼那几个字(拼一遍就是抄第二份)。
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
## 结算屏本体(三页)。提示行的格式串从它那里取。
const SS := preload("res://scripts/scenes/battle/settle_screen.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])


func _ready() -> void:
	await get_tree().process_frame
	## ★★强制真实视口: 无头下 `--resolution` **不生效**(实测四个分辨率全拿到 1280x1280),
	##   而项目是 canvas_items + expand / 基准 1280x720 ⇒ 真机上逻辑高度恒为 720。
	##   不强制的话这条门禁测的是一个现实中不存在的方形视口 —— **永远拓不到 bug**。
	var _vpw: int = int(OS.get_environment("RR_W")) if OS.get_environment("RR_W") != "" else 1280
	var _vph: int = int(OS.get_environment("RR_H")) if OS.get_environment("RR_H") != "" else 720
	get_tree().root.content_scale_size = Vector2i(_vpw, _vph)
	get_tree().root.size = Vector2i(_vpw, _vph)
	for _q in range(4):
		await get_tree().process_frame
	var sc = load(SCENE).instantiate()
	get_tree().root.add_child(sc)
	for _i in range(30):
		await get_tree().process_frame

	# ── 造一份【长名单】: 两边各塞满, 让数据表撑到最高 ──────────────
	var made := 0
	for side in ["left", "right"]:
		for k in range(14):
			var u = sc._spawn._make_unit("green", side, sc.ARENA.position + sc.ARENA.size * 0.5
				+ Vector2(-260.0 + 34.0 * float(k), -140.0 + 120.0 * (0.0 if side == "left" else 1.0)))
			if u is Dictionary:
				# 给点伤害数据, 否则统计表可能整行不画
				u["dmg_done"] = 1000.0 + 137.0 * float(k)
				u["dmg_taken"] = 500.0 + 91.0 * float(k)
				u["heal_done"] = 40.0 * float(k)
				## ★★必须真的推进 `_units` —— 第一版只调了 `_make_unit`, 它不入队,
				##   结果统计面板只按场上原有 9 个单位画 ⇒ 面板才 306 高,
				##   根本够不到 y=511 那行按钮 ⇒ **断言假绿**。
				##   名单长度就是这条门禁的被测条件, 塑不够高等于没测。
				if not sc._arr_has_unit(sc._units, u):
					sc._units.append(u)
				made += 1
	_ok("★分母: 造出 %d 个单位(名单要足够长, 否则这条是空检查)" % made, made >= 24, "made=%d" % made)
	for _i in range(6):
		await get_tree().process_frame

	# ══ ★★先把【伤害统计面板】打开 ══
	#   用户实测「名单很多时点不到回主菜单」—— 那个面板有个 **0.4 秒自刷计时器**,
	#   `render()` 第一行就是 `_to_front()` ⇒ 它会把自己反复提到 _ui_layer 最前。
	#   而 `_show_banner()` 只收了投降面板, 没管它 ⇒ 结算卡建好后 0.4 秒内被盖住。
	#   ★所以这条门禁必须①真的把面板开着 ②喂过 0.4 秒 —— 少一样都拓不到。
	sc._on_dmg_stats_toggle()   ## ★走真入口(它会先 setup 再 toggle), 不直接调内部函数
	for _i in range(4):
		await get_tree().process_frame
	_ok("★分母: 伤害统计面板真的开着(没开 = 下面那条是空检查)",
		sc._dmg_stats.panel != null and sc._dmg_stats.panel.is_visible_in_tree())

	# ── 开结算 ────────────────────────────────────────────────────
	sc._hud._show_banner(true)
	## ★喂过 0.4 秒的自刷周期 —— 面板就是在那一刻把自己提到最前的。
	##   只等几帧的话结算卡还在上面, 断言会假绿。
	var _w := 0.0
	while _w < 0.9:
		await get_tree().process_frame
		_w += get_process_delta_time()
	for _i in range(10):
		await get_tree().process_frame

	var vp: Vector2 = sc.get_viewport().get_visible_rect().size
	var vrect := Rect2(Vector2.ZERO, vp)
	_ok("★分母: 拿到视口尺寸", vp.x > 100.0 and vp.y > 100.0, str(vp))

	# ── 找到结算屏上所有按钮, 量它们的真实屏幕矩形 ──────────────────
	var btns: Array = []
	_collect_buttons(sc._ui_layer, btns)
	_ok("★分母: 结算屏上找到 %d 个按钮(0 个 = 没开出来, 下面全是空检查)" % btns.size(),
		btns.size() >= 1, "btns=%d" % btns.size())

	var shell: Control = _find_shell(sc._ui_layer)
	## ★长名单在【我方页】上 —— 默认停在「战果」页(那一页没有表), 不翻过去量的就不是长名单。
	var scr0 = sc._hud._settle
	if scr0 != null:
		scr0.show_page(1)
		for _i in range(6):
			await get_tree().process_frame
	var outside: Array = []
	for b in btns:
		var r: Rect2 = (b as Control).get_global_rect()
		# 完整落在视口内才算"点得到" —— 露出一半也可能点不中
		if r.position.y < 0.0 or r.end.y > vp.y or r.position.x < 0.0 or r.end.x > vp.x:
			outside.append("%s @ %s" % [str((b as Button).text), str(r)])
	_ok("★★结算屏每个按钮都完整落在屏幕内(名单再长也点得到)",
		outside.is_empty(), "溢出的: %s" % str(outside))

	# 卡片本体也不该比视口高 —— 高了就说明没有任何高度约束
	if shell != null:
		var sr: Rect2 = shell.get_global_rect()
		var nrow: int = 0
		var grids0: Array = []
		_collect_cls(shell, "GridContainer", grids0)
		for g in grids0:
			if (g as Control).is_visible_in_tree():
				for ch in (g as Node).get_children():
					if ch is HBoxContainer:
						nrow += 1
		_ok("★分母: 我方页上真的排着 %d 行 —— 不够长说明名单没塞进去" % nrow,
			nrow >= 14, "行 %d" % nrow)
		_ok("★★结算屏正文框整体不超出视口(超出 ⇒ 上下两头够不到)",
			sr.position.y >= -1.0 and sr.end.y <= vp.y + 1.0,
			"卡 %s / 视口高 %.0f" % [str(sr), vp.y])

	# ══ ★★真实命中测试: "在屏幕内" 不等于 "点得到" ══
	#   可能被别的 Control 盖住(mouse_filter 不是 IGNORE 就会吃掉点击)。
	#   ★★不自己写"找最上层" —— 第一版我手写了一个遍历, 它的顺序根本不是
	#   Godot 的命中顺序, 直接造出 5 条假阳性。改成**推一个鼠标移动事件进去,
	#   读引擎自己的 `gui_get_hovered_control()`** —— 那才是真正会收到点击的控件。
	#   (memory [[fb-hand-rolled-copies-drift]]: 就地手写标准层已有的东西 = 拄一次永远落后一次。)
	var vpt: Viewport = sc.get_viewport()
	## ★只查【结算卡内】的按钮: 战斗 HUD 自己的按钮被结算暗幕盖住是**应该的**,
	##   把它们一起算进来会造出一堆假阳性(第一版就是这么红的)。
	var card_btns: Array = []
	if shell != null:
		_collect_buttons(_screen_of(shell), card_btns)     ## 整屏: 左栏页签也要点得到
	_ok("★分母: 结算卡内找到 %d 个按钮" % card_btns.size(), card_btns.size() >= 1)
	var unclickable: Array = []
	for b in card_btns:
		var bc: Control = b
		var ctr: Vector2 = bc.get_global_rect().get_center()
		var mm := InputEventMouseMotion.new()
		mm.position = ctr
		mm.global_position = ctr
		vpt.push_input(mm)
		await get_tree().process_frame
		var hov: Control = vpt.gui_get_hovered_control()
		if hov != bc:
			unclickable.append("%s 上面是 %s(%s)" % [str((bc as Button).text),
				(hov.name if hov != null else "<null>"), (hov.get_class() if hov != null else "-")])
	# ── 诊断: 面板到底在哪、树序多少 ──
	var _pn: Control = sc._dmg_stats.panel
	if _pn != null:
		print("    [探针] 面板 rect=%s  树序=%d  可见=%s"
			% [str(_pn.get_global_rect()), _pn.get_index(), str(_pn.is_visible_in_tree())])
	if shell != null:
		print("    [探针] 结算卡 rect=%s  center 树序=%d"
			% [str(shell.get_global_rect()), shell.get_parent().get_index()])
	print("    [探针] battle._units = %d  _ui_layer 子节点 %d"
		% [sc._units.size(), sc._ui_layer.get_child_count()])
	for b in card_btns:
		print("    [探针] 按钮 '%s' rect=%s" % [str((b as Button).text), str((b as Control).get_global_rect())])

	_ok("★★每个按钮中心点真的能命中它自己(引擎命中测试, 不是我手算的)",
		unclickable.is_empty(), str(unclickable))


	## ══════════════════════════════════════════════════════════════════════
	##  ★★★封存那一屏: 玩家屏幕上真的出现了那几行字 (S3 · 2026-09-27)
	## ══════════════════════════════════════════════════════════════════════
	## `verify_finals_settle` ⑤g 量的是**纯函数说了什么**; 这一段量的是**它真的被画出来了**。
	## 两条缺任何一条都能假绿: 只有前者 ⇒ 文案对但没人画;
	## 只有后者 ⇒ 画了但内容能被悄悄改空(而「有个 Label」照样成立)。
	##
	## ★★上面那张卡是**未封存**的(`_show_banner(true)`) ⇒ 它天然就是本判据的**对照组**:
	##   先证明「没封存时屏幕上写的是胜利、没有封存字样」, 再喂封存态重建一张。
	##   没有这个对照, 「屏幕上有『结果已封存』」可能只是因为它**恒真**。
	print("  ── ⑩ 封存那一屏真的说清了在等什么 ──")
	var _before: Array = _all_label_texts(sc)
	var _has_win: bool = false
	var _has_seal0: bool = false
	for _t in _before:
		if str(_t) == "胜利":
			_has_win = true
		if str(_t).find("结果已封存") >= 0:
			_has_seal0 = true
	_ok("⑩ ★对照组: 未封存时屏幕上写着「胜利」", _has_win, "共 %d 个 Label" % _before.size())
	_ok("⑩ ★对照组: 未封存时屏幕上**没有**封存字样", not _has_seal0)

	## 喂封存态再建一张。`_show_banner` 有 `if battle._settled: return` 闸 ⇒ 要复位。
	## ★只动这个表现层的 bool, **不碰赛季结算** —— 三件套里 `_settle_season` 是另一步,
	##   `_show_banner` 本身纯表现(见 RealtimeBattle3DScene.gd:1217 的注释)。
	var _gs = get_node_or_null("/root/GameState")
	_ok("⑩ ★分母: 拿到 GameState", _gs != null)
	if _gs != null:
		var _had0: bool = (_gs.finals_pending_reveal as Dictionary).is_empty()
		_gs.test_mode = true                      ## 不许写真存档
		_gs.finals_pending_reveal = {"round": 1, "match": 0}
		sc._settled = false
		sc._hud._show_banner(false)               ## won=false: 封存时这个参数**不该被采信**
		for _i in range(8):
			await get_tree().process_frame
		## 只看**新增**的 Label —— 上一张卡还在树上, 整树扫会把它的「胜利」也算进来。
		var _after: Array = _all_label_texts(sc)
		var _seen: Dictionary = {}
		for _t in _before:
			_seen[str(_t)] = int(_seen.get(str(_t), 0)) + 1
		var _new: Array = []
		for _t in _after:
			var _k: String = str(_t)
			if int(_seen.get(_k, 0)) > 0:
				_seen[_k] = int(_seen[_k]) - 1
			else:
				_new.append(_k)
		_ok("⑩ ★分母: 封存那张卡真的建出来了(新增 %d 个 Label)" % _new.size(), _new.size() >= 2,
			str(_new).substr(0, 180))
		var _blob: String = ""
		## ★★`_why` 是**给红行看的**: 新增的 Label 绝大多数是统计表里的数字,
		##   拿 `_blob` 前 120 字当 detail 印出来就是一串「57」—— 红了也不知道红在哪。
		##   ⇒ detail 只印**像句子的那几条**(长度 ≥3 且不是纯数字)。
		var _why: String = ""
		for _t in _new:
			_blob += str(_t) + "\n"
			var _k2: String = str(_t).strip_edges()
			if _k2.length() >= 3 and not _k2.is_valid_float():
				_why += "「" + _k2.replace("\n", "⏎") + "」 "
		_ok("⑩ ★★★屏幕上写着「结果已封存」", _blob.find("结果已封存") >= 0, _why.substr(0, 200))
		_ok("⑩ ★★★封存时屏幕上**不许**出现胜利/失败(这就是「两边都赢」的出处)",
			_blob.find("胜利") < 0 and _blob.find("失败") < 0, _why.substr(0, 200))
		## 副标题 —— 与 `verify_finals_settle` ⑤g 同一份纯函数, 这里验它**上了屏**。
		## ★不在测试里自己拼那几个字: 拼一遍就是抄第二份, 抄本必然落后。
		var _sub: String = P2C.finals_sealed_sub()
		_ok("⑩ ★分母: 纯函数的副标题非空", _sub.strip_edges() != "", _sub)
		var _l0: String = _sub.split("\n")[0]
		_ok("⑩ ★★★副标题**逐字**上了屏", _blob.find(_l0) >= 0, "要的: 「%s」 / 屏上: %s" % [_l0, _why.substr(0, 200)])
		## 收尾: 还原, 不留痕(铁律④ 测试不许污染真存档)
		_gs.finals_pending_reveal = {}
		_ok("⑩ ★收尾: `finals_pending_reveal` 已还原",
			(_gs.finals_pending_reveal as Dictionary).is_empty() and _had0)

	sc.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	await _scan_budget()          ## ⑪ BUDGET_SAME_SOURCE

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 结算屏按钮可达" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## ======================================================================
##  ⑪ BUDGET_SAME_SOURCE —— 穷举行数 (2026-09-29)
## ======================================================================
## 用户原话:「每场打完后结算界面能下滑吗, 不能啊, 有很多单位看不到啊」。
##
## 量的就是用户说的那个形状: 某一档行数下, 卡片被裁掉了,
##   而全屏一根滚动条 / 一句提示都没有。
##
## 判据三条, 都量真实节点:
##   A. (2026-10-04 三页之后) 没有外层滚动区了 ⇒ 改成: 三页的内容任何行数下都放得进页体,
##      正文框不出视口 —— 只有队伍表自己会滚(而它滚的时候有提示, 见 B)
##   B. 穷举 R=7..16: 不存在「有行看不到而屏上没有任何提示」的那一档
##   C. 分母: 扇描里真的出现过「有行看不到」, 也出现过「全看得到」
##
## ★提示的文字不在这里抄第二份: 拿 `SS.MORE_FMT`(settle_screen.gd)自己算
##   (memory [[fb-hand-rolled-copies-drift]]).
func _scan_budget() -> void:
	print("  ── ⑪ BUDGET_SAME_SOURCE: 穷举行数, 不许有「溢出了而屏上没提示」的档 ──")
	var sc2 = load(SCENE).instantiate()
	get_tree().root.add_child(sc2)
	for _i in range(30):
		await get_tree().process_frame
	## 停掉 sim —— 不然清 `_units` 会触发它自己的结算/死亡逻辑, 量到的就不是我摆的那一档
	sc2.set_process(false)
	sc2.set_physics_process(false)
	await get_tree().process_frame
	var base: int = sc2._ui_layer.get_child_count()
	var vp: Vector2 = sc2.get_viewport().get_visible_rect().size
	var built: int = 0
	var n_over: int = 0
	var n_clean: int = 0
	var silent: Array = []
	var outer_bad: Array = []
	var wrong_n: Array = []
	var btn_out: Array = []
	for r in range(7, 17):
		# ── 收掉上一档的结算幕 ──
		var kids: Array = sc2._ui_layer.get_children()
		for i in range(kids.size() - 1, base - 1, -1):
			(kids[i] as Node).queue_free()
		await get_tree().process_frame
		# ── 摆这一档的名单 ──
		sc2._units.clear()
		for side in ["left", "right"]:
			for k in range(r):
				var u = sc2._spawn._make_unit("green", side, sc2.ARENA.position + sc2.ARENA.size * 0.5
					+ Vector2(-260.0 + 34.0 * float(k), -140.0 + 120.0 * (0.0 if side == "left" else 1.0)))
				if u is Dictionary:
					u["_st_dealt"] = 1000 + 137 * k
					u["_st_taken"] = 500 + 91 * k
					u["_st_heal"] = 40 * k
					if not sc2._arr_has_unit(sc2._units, u):
						sc2._units.append(u)
		for _i in range(4):
			await get_tree().process_frame
		sc2._settled = false
		sc2._hud._show_banner(true)
		## ★只数帧不看墙钟: 排版是逐帧级联的(deferred + 协程), 与机器快慢无关
		for _i in range(16):
			await get_tree().process_frame

		var shell: Control = _find_shell(sc2._ui_layer)
		var scr = sc2._hud._settle
		if shell == null or scr == null:
			continue
		built += 1
		# ── A. 页体放得下页内容(放不下 = 被 clip 静默裁掉), 正文框不出视口 ──
		var body: Control = (scr.pages[0] as Control).get_parent()
		for pg in scr.pages:
			var need: float = (pg as Control).get_combined_minimum_size().y
			if need > body.size.y + 0.5:
				outer_bad.append("R=%d 第 %s 页最小高 %.0f > 页体 %.0f" % [r, str(pg.name), need, body.size.y])
		var fr: Rect2 = shell.get_global_rect()
		if fr.position.y < -0.5 or fr.end.y > vp.y + 0.5:
			outer_bad.append("R=%d 正文框 %s 出了视口" % [r, str(fr)])
		var oscrollable: float = 0.0
		var hidden: int = 0
		var rows: Array = []
		# ── B/C. 我方 / 敌方两页各量一遍: 有几行看不到, 屏上那句提示对不对 ──
		for pi in [1, 2]:
			scr.show_page(pi)
			for _i in range(6):
				await get_tree().process_frame
			var prow: Array = []
			var grids: Array = []
			_collect_cls(scr.pages[pi], "GridContainer", grids)
			for g in grids:
				if not (g as Control).is_visible_in_tree():
					continue
				for ch in (g as Node).get_children():
					if ch is HBoxContainer:
						prow.append(ch)
			var ph: int = 0
			for rr in prow:
				if not _clip_of(rr, vp).encloses((rr as Control).get_global_rect()):
					ph += 1
			rows += prow
			var want: String = SS.MORE_FMT % ph
			var pre: String = SS.MORE_FMT.split("%d")[0]     # 「▼ 还有 」—— 派生出来的, 不是我又抄一份
			var seen_exact: bool = false
			var seen_any: String = ""
			for l in _visible_labels(shell, vp):
				if str(l) == want:
					seen_exact = true
				if str(l).begins_with(pre):
					seen_any = str(l)
			if ph > 0:
				hidden += ph
				if seen_any == "":
					silent.append("R=%d 页%d 共 %d 行·看不到 %d 行, 屏上一句提示没有" % [r, pi, prow.size(), ph])
				elif not seen_exact:
					wrong_n.append("R=%d 页%d 该写「%s」屏上写的是「%s」" % [r, pi, want, seen_any])
			elif seen_any != "":
				wrong_n.append("R=%d 页%d 全看得到, 却还写着「%s」" % [r, pi, seen_any])
		if hidden > 0:
			n_over += 1
		else:
			n_clean += 1
		# ── 按钮还完整在屏内吗 ──
		var bs: Array = []
		_collect_buttons(_screen_of(shell), bs)
		for b in bs:
			var br: Rect2 = (b as Control).get_global_rect()
			if br.position.y < 0.0 or br.end.y > vp.y or br.position.x < 0.0 or br.end.x > vp.x:
				btn_out.append("R=%d '%s' @%s" % [r, str((b as Button).text), str(br)])
		print("     R=%2d 两页行=%2d 页体高=%4.0f 看不到=%2d 提示=%s"
			% [r, rows.size(), body.size.y, hidden, scr.more_hint.text])

	_ok("⑪ ★分母: 10 档里都把结算卡建出来了", built == 10, "built=%d" % built)
	_ok("⑪ ★分母: 扇描里真的出现过「有行看不到」(0 次 ⇒ 下面那条是空检查)",
		n_over > 0, "看不到行的档=%d" % n_over)
	_ok("⑪ ★分母: 也出现过「全看得到」的档(提示不是恒亮的)",
		n_clean > 0, "全看得到的档=%d" % n_clean)
	_ok("⑪ ★★任何行数下: 三页的内容都放得进页体, 正文框不出视口(只有队伍表自己会滚)",
		outer_bad.is_empty(), str(outer_bad))
	_ok("⑪ ★★★不存在「有行看不到而屏上没有任何提示」的那一档",
		silent.is_empty(), str(silent))
	_ok("⑪ ★提示上的数字 = 真的看不到的行数", wrong_n.is_empty(), str(wrong_n))
	_ok("⑪ ★每档的按钮都完整落在屏内", btn_out.is_empty(), str(btn_out))
	sc2.queue_free()
	await get_tree().process_frame


func _collect_cls(n: Node, cls: String, out: Array) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children(true):
		_collect_cls(c, cls, out)


## 全部祖先 `clip_contents` 矩形的交集 —— 玩家**真正**看得见的那一块。
## ★不能只看内层滚动区: 结算卡是两层嵌套滚动,
##   内层以为自己有 400px 可用, 可它的下沿可能被外层裁在半路 —— 那就是这次那 56px 的现场。
func _clip_of(c: Control, vp: Vector2) -> Rect2:
	var r := Rect2(Vector2.ZERO, vp)
	var p: Node = c
	while p != null:
		if p is Control and (p as Control).clip_contents:
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r


## 屏幕上真看得见的 Label 文字: 可见 + 矩形完整落在 clip 交集内。
## ★「有个 Label」不算 —— 被裁掉的提示对玩家而言就是没有提示。
func _visible_labels(root: Node, vp: Vector2) -> Array:
	var out: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var n = st.pop_back()
		if n is Label and (n as Control).is_visible_in_tree():
			var t: String = str((n as Label).text)
			if t.strip_edges() != "" and _clip_of(n, vp).encloses((n as Control).get_global_rect()):
				out.append(t)
		for ch in n.get_children():
			st.append(ch)
	return out


func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button and (n as Control).is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)


## 结算屏正文 = 最后建的那个 `SettleScreen` 里的金属框 `SettleFrame`(左栏页签 + 它 = 整屏)。
## ★取【最后一个】: 本测试会连建好几张, 旧的还躺在树上。
func _find_shell(n: Node) -> Control:
	var found: Control = null
	for c in n.get_children():
		if str(c.name).begins_with("SettleScreen"):
			var f = c.find_child("SettleFrame", true, false)
			if f != null:
				found = f
	return found

## 金属框往上找到整屏根(SettleScreen) —— 页签在左栏, 不在框里。
func _screen_of(c: Node) -> Node:
	var p: Node = c
	while p != null and not str(p.name).begins_with("SettleScreen"):
		p = p.get_parent()
	return p if p != null else c


## 把整棵树上所有 Label 的文字收成一张平表。
## ★为什么不按节点名/路径找: 名字是我起的, 拿它当判据等于「我说是就是」;
##   而「玩家看得见的字」就是**所有 Label 的 text**, 与结构怎么搭无关。
func _all_label_texts(root: Node) -> Array:
	var out: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var n = st.pop_back()
		if n is Label and str((n as Label).text).strip_edges() != "":
			out.append(str((n as Label).text))
		for ch in n.get_children():
			st.append(ch)
	return out
