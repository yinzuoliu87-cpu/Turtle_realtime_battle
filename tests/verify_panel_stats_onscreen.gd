extends Node
## verify_panel_stats_onscreen.gd — 详情面板的属性数字【屏幕上真的会变】门禁 (2026-08-19)
##
## ══════════════════════════════════════════════════════════════════
##  为什么要和 verify_info_panel_live 分开
## ══════════════════════════════════════════════════════════════════
## 那一份验的是**取数函数**(`_info_stat_rows_main/minor` 算出来的字符串对不对) ——
## 它拿 `_row(u, "移速 ")` 直接调生成器, **一个屏幕上的 Label 都没碰**。
## 而用户 2026-07-21 的原话是「面板里所有的数值需要实时变化, 比如血条, 移速攻速」,
## 要的是**屏幕上那个数字会变**。这两件事之间隔着一整条链:
##
##     取数函数算对了  →  每帧有人调刷新  →  刷新真的写进那个 Label  →  玩家看见
##
## 「算式是实时的」不等于「屏幕上会变」—— 面板完全可以只在打开那一刻建一次。
## 本门禁把判据落在**面板节点树里取回来的 Label.text**, 不碰生成器。
##
## ★实测抓到的真缺口(本门禁的直接由来): **移速根本不刷新**。
##   攻速在【主属性 8 项】里, `_refresh_info_panel` 每帧按下标对位改文字 ✅;
##   移速在【次要 11 项】里, 而次要那 11 项在建面板时被拼成**一个字符串**捕进
##   「更多属性」入口条的 lambda ⇒ 点开看到的永远是**开面板那一刻**的数。
##   (修法见 info_panel._info_more_row 的 `body_fn` 与 `_more_stats_text`。)
##
## ★等效果不用帧数 / 不用 create_timer / 不用游戏时钟 `_t`(CLAUDE.md §3.5):
##   A/C 两组是**全同步**的(直接调产品的刷新函数, 零 tween 依赖);
##   B 组要证"每帧真的有人调", 只能让场景真跑 —— 那一段用**墙钟**轮询。
##
## ★★2026-10-06 面板重做后的读法(判据一条没放宽, 只换了"屏上那个数在哪"):
##   · 19 项属性全铺成 StatGrid(用户「我们全部要放上去啊」「不要再弄更多属性这样了」),
##     每格 = 图标 TextureRect + 数字 Label, **没有文字标签** ⇒ 不能再按「攻速」两个字找行。
##     改成按【格子里那张图标的文件名】认格子(aspd-icon / move-icon), 读同一格里的数字 Label。
##   · 「更多属性」入口删了 ⇒ C 组的移速改成: ①常驻格子里的移速是活的 ②点移速那一格
##     (真左键)弹出的左侧小卡里的数也是活的, 收起再点开印的仍是现算值。
##
## 跑法: <godot> --headless --path . res://tests/verify_panel_stats_onscreen.tscn --quit-after 3000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EQ_HP_ASPD := "p2eq_083"   # 「每损失 1% 生命 → +0.2/0.3/0.4% 攻速」= 用户说的"掉血加攻速"那件

var _s
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 从【面板节点树】里取回含关键字的那一行 Label 文字。
## ★只认 is_visible_in_tree 的 —— 藏起来的节点不算"玩家看得见"。
func _screen_text(root: Node, key: String) -> String:
	if root == null or not is_instance_valid(root):
		return ""
	if root is Label and (root as Control).is_visible_in_tree() \
			and str((root as Label).text).find(key) >= 0:
		return str((root as Label).text)
	if root is RichTextLabel and (root as Control).is_visible_in_tree():
		var pt := str((root as RichTextLabel).get_parsed_text())
		if pt.find(key) >= 0:
			for ln in pt.split("\n"):
				if str(ln).find(key) >= 0:
					return str(ln).strip_edges()
	for ch in root.get_children():
		var r := _screen_text(ch, key)
		if r != "":
			return r
	return ""


## StatGrid 里【图标文件名 == icon】的那一格(VBox: TextureRect + 数字 Label)。没有 ⇒ null。
## ★只认 is_visible_in_tree 的格子 —— 藏起来的不算"玩家看得见"。
func _tile(icon: String) -> Control:
	if _s._info_panel == null or not is_instance_valid(_s._info_panel):
		return null
	var grid: Node = _s._info_panel.find_child("StatGrid", true, false)
	if grid == null:
		return null
	for cell in grid.get_children():
		if not (cell as Control).is_visible_in_tree():
			continue
		for k in (cell as Node).get_children():
			if k is TextureRect and (k as TextureRect).texture != null \
					and str((k as TextureRect).texture.resource_path).get_file() == icon:
				return cell as Control
	return null


## 那一格里屏幕上的数字(Label.text)。格子不在 ⇒ ""。
func _tile_text(icon: String) -> String:
	var cell := _tile(icon)
	if cell == null:
		return ""
	for k in cell.get_children():
		if k is Label:
			return str((k as Label).text)
	return ""


## 面板左侧小卡(InspectCard)头部那一行的数(属性卡 = 当前值)。没开 / key 不对 ⇒ ""。
func _card_text(key: String) -> String:
	var c = _s._info_sys._card
	if c == null or c.card == null or not is_instance_valid(c.card) or str(c.key) != key:
		return ""
	if not (c.card as Control).is_visible_in_tree():
		return ""
	var ls: Array = c.live.get("stat_lbls", [])
	if ls.is_empty() or not is_instance_valid(ls[0]):
		return ""
	return str((ls[0] as Label).text)


## 从 "攻速 1.25 次/秒" 这类文字里抠第一个数。抠不到返回 -1(**不是 0** —— 0 会和
## 真实的 0 值混起来, 让"没读到"伪装成"读到了 0")。
func _num_in(s: String) -> float:
	var cur := ""
	for i in range(s.length()):
		var c := s[i]
		if (c >= "0" and c <= "9") or (c == "." and cur != ""):
			cur += c
		elif cur != "":
			break
	return cur.to_float() if cur != "" else -1.0


func _mk_carrier() -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", "left", c)
	u["equips"] = [{"id": EQ_HP_ASPD, "star": 3}]
	u["eq_state"] = {}
	u["_b83_si"] = 2                      # 3★ ⇒ 每损失 1% 生命 +0.4% 攻速
	u["maxHp"] = 1000.0
	u["hp"] = 1000.0
	u["move_spd"] = 100.0
	u["move_perm"] = 1.0
	u["slow_until"] = 0.0
	return u


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	var u := _mk_carrier()
	_s._units.clear()
	_s._units.append(u)
	_s._edit_mode = false
	_s._over = false
	_s.set_process(false)

	_s._hud._show_unit_info_panel(u)
	_s._info_sys._refresh_info_panel()
	for _i in range(4):
		await get_tree().process_frame

	print("=== verify_panel_stats_onscreen ===")
	_test_aspd_onscreen(u)
	await _test_refresh_is_wired(u)
	_test_move_spd_onscreen(u)

	## ★把用掉的帧数打出来 —— run-tests.sh 的默认 `--quit-after` 是 500 帧,
	##   帧不够会在半路被掐断(表现是"没打 ALL PASS"而不是某条 FAIL, CLAUDE.md §2 那个坑)。
	##   本行让下一个人不必猜: 余量不够了就去 frames_for() 里给它登记一条。
	print("用掉 %d 帧(默认预算 500)" % Engine.get_process_frames())
	print("总计 %d 条, 失败 %d 条" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)


# ────────────────────────────────────────────────────────────────────────────
#  A) 攻速: 掉血 → 屏幕上那行字变大 (全同步)
# ────────────────────────────────────────────────────────────────────────────
func _test_aspd_onscreen(u: Dictionary) -> void:
	var t0 := _tile_text("aspd-icon.png")
	_ok("★分母: 面板上真的有「攻速」那一格(按 aspd-icon 认格子, 读的是屏幕节点, 不是生成器)",
		t0 != "", "实得 '%s'" % t0)
	var v0 := _num_in(t0)
	_ok("★分母: 那一行里抠得出数字(-1 = 没抠到, 空检查)", v0 > 0.0, "v0=%.3f" % v0)

	# ── 掉一半血, 走【真装备】的每帧 tick(不是我手改 aspd_perm) ──
	u["hp"] = 500.0
	_s._equip_sys._blade_sys.tick_unit(u, 0.1)
	var aspd_after: float = float(u.get("aspd_perm", 1.0))
	_ok("★分母: %s 真的因为掉血改了 aspd_perm(不改 ⇒ 后面全是空检查)" % EQ_HP_ASPD,
		aspd_after > 1.0001, "aspd_perm=%.4f (50%% 生命 × 0.4%%/1%% = 期望 1.20)" % aspd_after)

	_s._info_sys._refresh_info_panel()
	var t1 := _tile_text("aspd-icon.png")
	var v1 := _num_in(t1)
	_ok("★★掉血之后【屏幕上那行字】跟着变(面板不是一次性快照)",
		t1 != t0 and t1 != "", "'%s' → '%s'" % [t0, t1])
	_ok("★★而且方向对: 掉血加攻速 ⇒ 次/秒 变大", v1 > v0, "%.3f → %.3f" % [v0, v1])
	_ok("★★屏幕上印的就是战斗判定用的那个数(battle.aspd_mult / atk_interval)",
		absf(v1 - _s.aspd_mult(u) / maxf(0.001, float(u.get("atk_interval", 1.0)))) < 0.051,
		"屏幕 %.3f vs 判定 %.3f" % [v1, _s.aspd_mult(u) / maxf(0.001, float(u.get("atk_interval", 1.0)))])

	# 反面: 血回满 ⇒ 攻速回落。只涨不落说明是"改过一次就钉住"而不是实时。
	u["hp"] = 1000.0
	_s._equip_sys._blade_sys.tick_unit(u, 0.1)
	_s._info_sys._refresh_info_panel()
	var v2 := _num_in(_tile_text("aspd-icon.png"))
	_ok("★反面: 血回满 ⇒ 屏幕上的攻速跌回去(不是单向钉死)",
		v2 < v1 - 0.001, "%.3f → %.3f" % [v1, v2])


# ────────────────────────────────────────────────────────────────────────────
#  B) 刷新是【每帧被调的】, 不是只有测试自己手动调才动
# ────────────────────────────────────────────────────────────────────────────
## ★这一条才是"屏幕上会变"的关键: A 组是我自己调 _refresh_info_panel,
##   哪怕产品从来没接上这条线, A 组照样全绿(memory: 门禁要量需求不是量我的钩子)。
## ★等的是【游戏内每帧刷新】⇒ 只能用墙钟, 不能用帧数(CI 无头帧率极高)、
##   不能用 create_timer(未钳制 delta)、更不能用 `_t`(结算后会冻结)。
## ★改的是 `aspd_perm` 而不是 `hp` —— 这一条只该测【刷新有没有挂在每帧路径上】,
##   拿"掉血"当输入会把装备的每帧 tick 也串进来: 那条链一旦因为别的原因不跑
##   (单边阵容 ⇒ `_check_end` 直接判完 ⇒ sim 里的装备 tick 停),
##   这一条就会红在"装备没算", 而不是它要测的"面板没刷" —— 判据没卡住那个形状。
##   (第一版正是这么写的, 实测红了 4 秒, 根因是装备 tick 没跑。)
func _test_refresh_is_wired(u: Dictionary) -> void:
	var before := _tile_text("aspd-icon.png")
	_ok("★分母: 开跑前读得到攻速那一格", before != "", "实得 '%s'" % before)
	u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) * 1.75   # 面板每帧都读它(aspd_mult)
	## ★★先证这条断言【会红】: _process 关着的时候, 光过帧不该有任何变化。
	##   没有这一段的话, "字变了"可能只是因为别处也在刷 ⇒ 断言恒绿(空检查)。
	## ★这一段【按帧数】等是对的, 不违反 CLAUDE.md §3.5 —— 那条说的是"等游戏内效果"
	##   (效果按游戏时钟推进, 帧数不是它的尺子)。这里要问的恰恰是"光过帧会不会变",
	##   帧就是被测量本身。而且固定帧数才不会在无头高帧率下把 --quit-after 预算烧光
	##   (原来写 400ms, 500 帧的默认预算只剩个位数余量)。
	for _w in range(20):
		await get_tree().process_frame
	_ok("★分母(反向): _process 关着时屏幕上的字【不变】—— 变了说明这条断言测不到东西",
		_tile_text("aspd-icon.png") == before,
		"实得 '%s'" % _tile_text("aspd-icon.png"))
	_s.set_process(true)                 # ← 从这里开始【产品自己的每帧路径】接管
	var t_start := Time.get_ticks_msec()
	var after := before
	while Time.get_ticks_msec() - t_start < 4000:
		await get_tree().process_frame
		after = _tile_text("aspd-icon.png")
		if after != before and after != "":
			break
	_s.set_process(false)
	_ok("★★【没有人手动调刷新】的情况下, 屏幕上的攻速自己变了 —— 说明刷新真的挂在每帧路径上",
		after != before and after != "",
		"'%s' → '%s' (墙钟 %d ms)" % [before, after, Time.get_ticks_msec() - t_start])
	u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) / 1.75   # 还原, 别污染后面的用例


# ────────────────────────────────────────────────────────────────────────────
#  C) 移速: 常驻格子里是活的, 点开的小卡里也是活的
# ────────────────────────────────────────────────────────────────────────────
## ★这一组的由来: 次要 11 项曾被拼成字符串捕进「更多属性」入口的 lambda,
##   开面板那一刻是多少, 之后点开多少次都是多少。
## ★2026-10-06「更多属性」入口删掉, 移速搬上常驻格子; 点那一格 → 面板左侧弹属性小卡。
##   要守的仍是同一件事: 【屏上】的移速(格子 + 小卡两处)跟着实战移速走, 不是快照。
func _test_move_spd_onscreen(u: Dictionary) -> void:
	u["hp"] = 1000.0
	u["slow_until"] = 0.0
	_s._info_sys._refresh_info_panel()
	## ★「更多属性」入口不许回来(用户 10-06「不要再弄更多属性这样了」)
	_ok("★面板里没有「更多属性」入口(用户 10-06 删掉的)", _screen_text(_s._info_panel, "更多属性") == "",
		_screen_text(_s._info_panel, "更多属性"))
	var cell := _tile("move-icon.png")
	_ok("★分母: 面板上找得到「移速」那一格(按 move-icon 认)", cell != null)
	if cell == null:
		return
	var m0 := _tile_text("move-icon.png")
	var s0 := _num_in(m0)
	_ok("★分母: 移速那一格抠得出数字", s0 > 0.0, "实得 '%s'" % m0)

	# 减速 50% → 常驻格子跟着掉(每帧刷新那条路)
	u["slow_until"] = _s._t + 99.0
	u["slow_mag"] = 0.5
	_s._info_sys._refresh_info_panel()
	var m1 := _tile_text("move-icon.png")
	_ok("★★被减速 ⇒ 屏幕上那一格的移速跟着掉(不是开面板那一刻的快照)",
		m1 != m0 and m1 != "", "'%s' → '%s'" % [m0, m1])
	_ok("★★而且印的就是面板自己的实战移速公式(_eff_move_spd)",
		_num_in(m1) == float(int(round(_s._info_sys._eff_move_spd(u)))),
		"屏幕 %.1f vs 公式 %.1f" % [_num_in(m1), _s._info_sys._eff_move_spd(u)])

	# 点那一格(真左键) → 左侧小卡; 小卡里的数也必须是现算的
	_click(cell)
	var key := "st:%d" % cell.get_index()
	var c1 := _card_text(key)
	_ok("★分母: 点移速那一格 ⇒ 左侧小卡开了且读得到数(key=%s)" % key, c1 != "", "实得 '%s'" % c1)
	_ok("★★小卡里印的是【现在】的移速(减速中)",
		_num_in(c1) == float(int(round(_s._info_sys._eff_move_spd(u)))),
		"'%s' vs 现算 %.1f" % [c1, _s._info_sys._eff_move_spd(u)])
	# 小卡开着时减速过期 ⇒ 小卡里的数跟着回去(每帧刷新那条路, 不是点开那一刻的快照)
	u["slow_until"] = 0.0
	_s._info_sys._refresh_info_panel()
	var c2 := _card_text(key)
	_ok("★★小卡开着时减速过期 ⇒ 卡上的移速跟着回去",
		c2 != c1 and _num_in(c2) == float(int(round(_s._info_sys._eff_move_spd(u)))),
		"'%s' → '%s' vs 现算 %.1f" % [c1, c2, _s._info_sys._eff_move_spd(u)])

	# 收起再点开 —— 重新点开拿到的也必须是现算的
	u["slow_until"] = _s._t + 99.0
	_click(cell)
	_ok("★再点同一格 ⇒ 小卡收起", _card_text(key) == "", "实得 '%s'" % _card_text(key))
	_click(cell)
	var c3 := _card_text(key)
	## ★比【现算值】不比 c1 —— 比 c1 的话, 两次都停在旧快照上时它照样绿。
	_ok("★★收起再点开, 印的仍是【现在】的移速(而不是某一刻的快照)",
		c3 != "" and _num_in(c3) == float(int(round(_s._info_sys._eff_move_spd(u)))),
		"'%s' vs 现算 %.1f" % [c3, _s._info_sys._eff_move_spd(u)])
	_click(cell)

	# 反面: 减速过期 ⇒ 格子回到原值。只跌不回同样是"钉死"。
	u["slow_until"] = 0.0
	_s._info_sys._refresh_info_panel()
	_ok("★反面: 减速过期后格子里的移速回到原值",
		_tile_text("move-icon.png") == m0, _tile_text("move-icon.png"))


## 喂一次真的左键点击给那条入口 —— 走产品自己的 gui_input 回调, 不去调内部函数。
func _click(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	c.gui_input.emit(ev)
