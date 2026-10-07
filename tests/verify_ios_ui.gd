extends Node
## verify_ios_ui.gd — iOS 测试包前自检守卫(用户 2026-07-16「打包之前确认: 调试场能点击到/能测所有龟和装备/按钮不超屏不卡住」)
##
## 断言(布局功能层, 观感仍需真机眼验):
##   A. iPhone 横屏画布(1560×720 ≈ 2.167:1)下: 全部菜单 scene 的可见按钮 rect ⊆ 屏幕
##   B. 主菜单有「🛠 调试场」按钮(debug 构建), 按下把 DEBUG_EDIT 打开
##   C. 调试场编辑器: 摆位面板建齐(可选龟覆盖全 28 只)且面板按钮 rect ⊆ 屏幕
##   D. 正常战斗 HUD(REVIEW_DEMO_DEFAULT=false): 暂停/日志等按钮 rect ⊆ 屏幕
##   E. iPad 4:3 画布(1280×960)复检 A(主菜单+调试场面板)
## 匹配按档位匹快照由 tests/verify_ghost_seed 独立守卫(9档全覆盖)。

## 昵称规则 / 墙上文案的事实源 —— 登录墙那节要拿 `NICK_REROLL`。
const _P2C_IOS := preload("res://scripts/gamedata/phase2_config.gd")
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MENU_SCENES := ["MainMenu", "Matchmaking", "TeamSelect", "Inventory", "Shop", "Codex", "Settings", "Leaderboard", "Record"]

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)

func _visible_buttons(n: Node, out: Array) -> void:
	if n is BaseButton and (n as Control).is_visible_in_tree():
		out.append(n)
	for ch in n.get_children():
		_visible_buttons(ch, out)

## 递归收集可见 Button/Label 文本(选龟卡=按钮+名字Label 组合, 光看Button text不够)
func _all_texts(n: Node) -> String:
	var s := ""
	if n is Button and (n as Control).is_visible_in_tree():
		s += str((n as Button).text) + "|"
	elif n is Label and (n as Control).is_visible_in_tree():
		s += str((n as Label).text) + "|"
	for ch in n.get_children():
		s += _all_texts(ch)
	return s

## 按钮是否在 ScrollContainer 内(滚动可达→不算越界; 弹窗网格cards裁剪待滚是正常态)
func _in_scroll(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false

## 按钮 rect 是否全在屏幕内(容差2px); 返回越界按钮描述列表
func _offscreen_buttons(root: Node, vp: Vector2) -> Array:
	var btns: Array = []
	_visible_buttons(root, btns)
	var bad: Array = []
	var screen := Rect2(Vector2(-2, -2), vp + Vector2(4, 4))
	for b in btns:
		if _in_scroll(b):
			continue
		var r: Rect2 = (b as Control).get_global_rect()
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		if not screen.encloses(r):
			bad.append("%s(%s) rect=%s" % [b.name, (b as Button).text.left(8) if b is Button else "-", str(r)])
	return bad

## 按钮是否被【后画的兄弟节点】盖住 —— 返回被遮的按钮描述列表.
##
## 为什么单查"在屏内"不够(用户2026-07-19「移动端选龟界面的返回键被遮住」):
## 选龟页的返回/清空/上次是在 slotBay/网格/详情区之【前】add_child 的, 手机比例下这几个按钮会被
## 夹边逻辑从屏外拉回 y≈6, 正好落进随后才画的面板矩形里. rect ⊆ 屏幕 → 老断言全绿, 但手指点不到。
##
## 判据: 同一 CanvasItem 父链下, 索引比按钮【大】(=画在上面)且不透明(modulate.a>0.05)的 Control,
## 若其 rect 与按钮 rect 的重叠面积 ≥ 按钮面积的 25%, 且它本身不是按钮的祖先/后代 → 判为遮挡。
##
## ★用【面积重叠】而不是【中心点命中】: 2026-07-19 第一版用中心点, 结果对选龟页给出假阴性 ——
## 无头模式下 DisplayServer.window_get_size() 返回 (0,0), TeamSelectScene._stage_to_screen 的
## 偏移折算 (STAGE_OFFSET * vp/win) 因此走了兜底分支, 舞台整体比真机低算约 30px,
## 木托盘(slotBay)刚好落到返回键中心点下方 14px → 中心点没被命中, 测试全绿, 但真机上按钮被木板压住。
## 面积判据对这 30px 的漂移不敏感, 抓得住。
func _occluded_buttons(root: Node, _vp: Vector2) -> Array:
	var btns: Array = []
	_visible_buttons(root, btns)
	var bad: Array = []
	for b in btns:
		var bc: Control = b as Control
		var blocker := _find_blocker(root, bc)
		if blocker != "":
			bad.append("%s(%s) 被 %s 盖住" % [b.name, (b as Button).text.left(8) if b is Button else "-", blocker])
	return bad

func _find_blocker(root: Node, btn: Control) -> String:
	var br: Rect2 = btn.get_global_rect()
	var barea: float = br.size.x * br.size.y
	if barea <= 1.0:
		return ""
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if not (n is Control) or n == btn:
			continue
		var c: Control = n as Control
		if not c.is_visible_in_tree() or c.modulate.a <= 0.05:
			continue
		if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue                                  # 不吃鼠标的纯装饰层不算遮挡
		if btn.is_ancestor_of(c) or c.is_ancestor_of(btn):
			continue                                  # 自己的子孙/祖先(按钮内的图标、包着它的容器)不算
		var inter: Rect2 = c.get_global_rect().intersection(br)
		if inter.size.x * inter.size.y < barea * 0.25:
			continue                                  # 只是蹭到边不算; 盖掉四分之一以上才算遮住
		if not _draws_above(c, btn):
			continue
		## ★2026-10-06: 相邻小键的**触摸外扩区**互相搭边不算「被面板盖住」。
		##   主菜单右上 ?/⚙: 看得见的键 50px、间距 8px, 点击区按触摸线 81px 居中外扩 ⇒ 两块点击区
		##   按设计重叠 23px(28% > 25%)。那不是一块面板, 是另一颗键自己的点击区。
		##   认法: 遮挡者 = 一颗键的点击区(它自己是 Button, 或它里面有一颗铺满它的 Button)
		##   且与被遮者同一量级(面积 ≤ 2 倍) —— 满屏遮罩/弹层(哪怕铺了一颗关闭用的 Button)照样红。
		##   「看得见的键不许重叠」由 verify_mainmenu_layout ② 守。
		if _is_tap_holder(c) and c.size.x * c.size.y <= barea * 2.0:
			continue
		return "%s%s" % [c.name, ("/" + str((c as Button).text).left(6)) if c is Button else ""]
	return ""

## c 是不是「一颗键的点击区」: 自己是 BaseButton, 或者某个后代 BaseButton 铺满了它(±1px)。
func _is_tap_holder(c: Control) -> bool:
	if c is BaseButton:
		return true
	var cr: Rect2 = c.get_global_rect()
	for b in c.find_children("*", "BaseButton", true, false):
		var r: Rect2 = (b as Control).get_global_rect()
		if absf(r.position.x - cr.position.x) <= 1.0 and absf(r.position.y - cr.position.y) <= 1.0 				and absf(r.size.x - cr.size.x) <= 1.0 and absf(r.size.y - cr.size.y) <= 1.0:
			return true
	return false

## a 是否画在 b 上面: 先比 z_index, 同 z 再比【共同父节点下的子索引】(Godot 后加的画在上面).
func _draws_above(a: Control, b: Control) -> bool:
	var pa: Node = a
	while pa != null and not pa.is_ancestor_of(b):
		pa = pa.get_parent()
	if pa == null:
		return false
	var ca: Node = a
	while ca != null and ca.get_parent() != pa:
		ca = ca.get_parent()
	var cb: Node = b
	while cb != null and cb.get_parent() != pa:
		cb = cb.get_parent()
	if ca == null or cb == null or ca == cb:
		return false
	if ca is CanvasItem and cb is CanvasItem and (ca as CanvasItem).z_index != (cb as CanvasItem).z_index:
		return (ca as CanvasItem).z_index > (cb as CanvasItem).z_index
	return ca.get_index() > cb.get_index()

## 选龟页贴边按钮(返回/清空/上次/开始)必须画在最上层 —— 结构断言, 不做几何模拟.
##
## 【为什么不靠几何】用户2026-07-19实机反馈「返回键被木板遮住」, 木板 = _build_slots 的 slotBay 暗托盘,
## 它在这四个按钮【之后】add_child, 手机比例下按钮又被 _place_clamped 夹到屏幕上沿, 正好落进托盘里。
## 但无头测试复现不了: DisplayServer.window_get_size() 返回 (0,0) → _stage_to_screen 的偏移折算
## (STAGE_OFFSET * vp/win) 走兜底, 整个舞台比真机低约 30px, 托盘刚好滑到按钮下面。
## 我先后用「中心点命中」和「面积重叠≥25%」两版几何判据, 都被这 30px 漂移骗成假阴性。
## 所以这里改断【结构不变式】: _raise_edge_btns() 把它们移到 root 末尾 = 最后绘制 = 谁也压不住,
## 与视口尺寸、舞台缩放、窗口尺寸全都无关, 无头环境同样成立。
func _check_teamselect_edge_btns(inst: Node) -> void:
	var root: Control = inst.get_node_or_null("UI/Root")
	if root == null:
		_ok("TeamSelect: 贴边按钮在最上层", false, "找不到 UI/Root")
		return
	## ★★不拿【屏幕上的词】当尺子(2026-09-28)。
	##   旧版写死了 ["‹ 返回", "⊘ 清空", "🔄 上次阵容"] 逐个前缀比 ——
	##   那三个符号正是用户点名要去掉的"网页味", 于是【改文案就红】,
	##   而它想守的那件事(贴边按钮画在木托盘之上)一点没变。
	## ⇒ 改成量【行为】: 拿场景**自己的登记** `_edge_btns`
	##   (`_place_clamped` 建 UI 时逐个登记的贴边按钮)跟 root 末尾比, 零字面量。
	## ★这**不是恒真**: `_edge_btns` 是【创建时】填的, "在末尾" 是
	##   `_raise_edge_btns()` 【另一次调用】产生的结果 —— 那句调用没了,
	##   或者之后又 add_child 了新面板(正是 2026-07-19 实机那个病), 这条当场红。
	var edge: Array = inst.get("_edge_btns") if inst.get("_edge_btns") is Array else []
	_ok("★分母 TeamSelect: 场景真登记了 4 个贴边按钮(返回/清空/上次/开始)",
		edge.size() == 4, "实得 %d 个" % edge.size())
	var n := root.get_child_count()
	var tail: Array = []
	for i in range(maxi(0, n - 4), n):
		tail.append(root.get_child(i))
	var missing: Array = []
	for b in edge:
		if not (b in tail):
			missing.append(str((b as Button).text) if b is Button else str(b))
	_ok("TeamSelect: 贴边按钮在 root 末尾(画在最上层, 不会被木托盘压住)",
		edge.size() == 4 and missing.is_empty(),
		"登记 %d 个 · 不在末4=%s" % [edge.size(), str(missing)])

## 各页"建全了"的可见按钮下限。0 = 不设限。
## ★这些数是【实测出来的】: 先把页面种到正常态量一遍, 再往下留一点余量。
const MIN_BUTTONS := {
	"MainMenu": 8,
	"Shop": 7,       # ★实测 7: 返回/背包/刷新/买经验/购买/我的背包/出战阵容(货架卡是 Panel 不是 Button)。
	                 #   上锁态只有 1 —— 这个 7 就是"页面建全了"与"只有一个返回"的分界线。
	                 #   ★我第一版拍脑袋写 10 结果红了: 错的是我的猜测不是产品。先量再定下限。
	"Codex": 5,      # 四个页签 + 返回(2026-10-07 用户「规则页直接删掉」⇒ 页签 5→4)
	"Inventory": 4,
	"TeamSelect": 8,
}


## 实例化【之前】种状态: 有些页在空存档下走的是上锁/空分支, 量了等于没量。
func _seed_scene_state(scene_name: String) -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.test_mode = true            # ★绝不写玩家真存档
	if scene_name == "Shop":
		gs.season_total_battles = 1     # < 1 ⇒ _build_locked(), 整页只有一个「返回」
		gs.meta_shop_battles = -1       # ≠ season_total_battles ⇒ 强制重新 roll 一套货
		gs.meta_shop_offer = []
		gs.meta_deepsea_coins = 9999


## 实例化【之后】再拨一下: 详情面板这类"要点过才出现"的区域, 不拨就永远量不到。
func _post_scene_state(scene_name: String, inst: Node) -> void:
	if scene_name == "Shop":
		inst.set("_sel", 0)
		if inst.has_method("_rebuild"):
			inst.call("_rebuild")


## ── A2. ★★★【绑定屏】(原来叫登录墙) —— 2026-09-28 才第一次被本门禁量到 ──
##
## ★★★ 2026-09-29 墙拆了(用户「那就不用必须绑定吧」) ⇒ 这一屏不再拦人:
##   它现在是玩家点了主菜单那句「进度没备份」之后才出现的**盖满全屏的绑定屏**,
##   而且**带一颗「关闭」**。本节因此多一条判据: 这一屏必须有那个出口
##   (没出口 = 墙又回来了)。它到底拦不拦得住人由 `verify_login_wall` ⑧ 走真入口守。
##
## 由来(用户真机报「邮箱注册没用, app 里操作没反应」): `MENU_SCENES` 里那个 "Settings"
## 载的是**普通设置页**。这一屏只有 `acct_override = 1` 才造得出来, 而门禁给每个
## 测试 `TURTLE_SUPABASE=" "`(有意关后端) ⇒ `SB.enabled()` 恒假 ⇒ **它从来不在场**。
## 探针 `tests/_probe_wall_hit.gd` 实测: 不注入 `acct_override` 时这一屏扫到 7 个可点元素
## (顶栏返回 + 滑条把手那些), `_email_layer = false` —— **墙一个控件都没量到**。
## 而这一屏是**每个新玩家开游戏看到的第一屏**(关不掉、返回箭头都藏了),
## 本门禁两条主判据(按钮越界 / 按钮被后画的面板盖住)正是为它这种"盖上来的一层"准备的。
## —— memory `fb-gate-subject-never-constructed`: 判据没错, 被测对象不在场。
##
## ★不走 `_check_scene_buttons`: 那个函数要 `await create_timer(1.7)` 等入场 tween,
##   而墙**没有入场动画**, 白等 1.7 秒会把 4000 帧的预算吃掉一块。
func _check_login_wall(vp: Vector2) -> void:
	var ps = load("res://scenes/Settings.tscn")
	if ps == null:
		_ok("登录墙: 载入 Settings.tscn", false, "load 失败")
		return
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.account_email = ""          ## 没绑邮箱 = 墙的条件之一
	var inst = ps.instantiate()
	## ★必须在 `add_child` **之前**注入 —— `_ready` 是 add_child 那一刻跑的,
	##   之后再设就晚了(墙已经按真实配置决定过建不建)。
	inst.acct_override = 1
	add_child(inst)
	for _i in range(8):
		await get_tree().process_frame
	_ok("登录墙: ★分母 墙真的立起来了(没立 ⇒ 下面两条量的是普通设置页, 不是墙)",
		inst._email_layer != null and is_instance_valid(inst._email_layer))
	var btns: Array = []
	_visible_buttons(inst, btns)
	var names: Array = []
	for b in btns:
		names.append(str((b as Button).text) if b is Button else b.name)
	## ★分母②: 墙立起来时背后的设置页是**藏掉的** ⇒ 可见按钮只剩墙上这一步该露的。
	##   数多了就说明墙没盖住(那时量的是另一块屏)。
	## ★★2026-09-28 原来写死 `== 2 且有「发验证码」和「确认」`。墙改成**分两步**之后
	##   第一步只露「发验证码」、「确认」在第二步 ⇒ 这条当场红。
	##   ★但它**红得对**: 它守的是「背后那一屏真的被盖住了」, 而它把「盖住了」
	##   **抄成了一个写死的数字 2** —— 版式一动它就误报。
	##   ⇒ 改成量它真正想守的那件事: **墙上露出来的按钮, 必须全是墙自己的**
	##   (背后设置页那些「重置存档」「调试场」一个都不许露), 数量随步骤走。
	## ★「换一个」(2026-09-29)从产品那一处读, **不在这里再抄一份字** ——
	##   改了屏上那个字而这里还找旧的, 就会拿到一条“背后设置页漏出来了”的假红。
	## ★★★ 2026-09-29 拆墙之后「关闭」不再是**可选项**: 这一屏必须有出口。
	##   白名单里留着它只是「不当漏出来」, 下面另有一条**要求它在**。
	var _wall_ok := ["发送验证码", "确认", "修改邮箱", "关闭",
		str(_P2C_IOS.NICK_REROLL)]
	var _leak: Array = []
	for _n in names:
		if not _wall_ok.has(str(_n)):
			_leak.append(_n)
	_ok("登录墙: ★分母 可见按钮 %d 个, 且全是墙自己的(背后设置页没漏出来)" % btns.size(),
		btns.size() >= 1 and _leak.is_empty(), "漏出来的: %s / 全部: %s" % [str(_leak), str(names)])
	_ok("绑定屏: ★分母 这一步至少露着一个能往下走的键",
		names.has("发送验证码") or names.has("确认"), str(names))
	## ★★★WALL_SOFT: 墙拆了 ⇒ 这一屏必须有**出口**。
	##   旧版本这里守的是反过来那一件(墙上不许有关闭), 而那条需求已作废。
	## ★这一条只管「出口在屏幕上」; 「点下去真的关得掉」由
	##   `verify_login_wall` ②b 真点一次来守(在这里只断言按钮存在 = 数自己插的标记)。
	_ok("绑定屏: ★★★WALL_SOFT 这一屏有出口(一颗「关闭」) —— 没出口 = 墙又回来了",
		names.has("关闭"), str(names))
	var bad := _offscreen_buttons(inst, vp)
	_ok("登录墙: %d 个可见按钮全在屏内" % btns.size(), bad.is_empty(), "; ".join(bad))
	var occ := _occluded_buttons(inst, vp)
	_ok("登录墙: 无按钮被后画的面板盖住", occ.is_empty(), "; ".join(occ))
	inst.queue_free()
	await get_tree().process_frame


func _check_scene_buttons(scene_name: String, vp: Vector2) -> void:
	var ps = load("res://scenes/%s.tscn" % scene_name)
	if ps == null:
		_ok("%s 载入" % scene_name, false, "load失败")
		return
	## ★上锁/空态的页要先种数据再量 —— 否则量的是一块"什么都没有"的屏(2026-08-15)。
	##   实测: 商店没打第一场时是 `_build_locked()`, 整页只有一个「返回」⇒ 这一条
	##   看着 PASS, 其实【整个商店头部与详情面板一个都没量到】。同一形状: 图鉴不选中就只有页签。
	##   这不是"没查出问题", 是"根本没查"。分母必须打出来并焊死下限。
	_seed_scene_state(scene_name)
	var inst = ps.instantiate()
	add_child(inst)
	await get_tree().create_timer(1.7).timeout   # 等入场动画落定(主菜单右栏磁贴滑入到1.39s才完; 1.1s抓中间帧误报)
	_post_scene_state(scene_name, inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var btns: Array = []
	_visible_buttons(inst, btns)
	## ★分母下限: 低于这个数说明页面没建全(上锁态/空态), 后面两条就是空检查。
	var floor_n: int = MIN_BUTTONS.get(scene_name, 0)
	if floor_n > 0:
		_ok("%s: ★分母 可见按钮 %d ≥ %d(不足=页面没建全, 下面两条是空检查)" % [scene_name, btns.size(), floor_n],
			btns.size() >= floor_n)
	var bad := _offscreen_buttons(inst, vp)
	_ok("%s: %d 个可见按钮全在屏内" % [scene_name, btns.size()], bad.is_empty(), "; ".join(bad) if not bad.is_empty() else "")
	var occ := _occluded_buttons(inst, vp)
	_ok("%s: 无按钮被后画的面板盖住" % scene_name, occ.is_empty(), "; ".join(occ) if not occ.is_empty() else "")
	if scene_name == "TeamSelect":
		_check_teamselect_edge_btns(inst)
	inst.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	# ── A. iPhone 横屏画布: 全菜单按钮不越界 ──
	var vp_iphone := Vector2(1560, 720)   # 2.167:1(iPhone 14/15 横屏)·canvas_items+expand 口径
	get_tree().root.size = Vector2i(vp_iphone)
	await get_tree().process_frame
	var vp_real := Vector2(get_tree().root.size)
	print("  (画布=", vp_real, ")")
	for sn in MENU_SCENES:
		await _check_scene_buttons(sn, vp_real)
	await _check_login_wall(vp_real)

	# ── B. 调试场入口存在 + 接线到 DEBUG_EDIT ──
	## ★2026-09-18 入口从主菜单搬到了【设置页】(用户:「调试场可以塞到设置里, 正式上线的不会要调试场」)。
	##   这一节验的是「打包前调试场还点得到」这个需求, 不是「它在哪个屏」—— 判据跟着入口走;
	##   同时补一条「主菜单不许再有它」, 免得搬家搬成两处都有还看不出来。
	var st_scene = load("res://scenes/Settings.tscn").instantiate()
	add_child(st_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	## 设置页的键是 Label+TextureRect 拼的(_text_button), 文字不在 Button.text 上 ——
	## 所以扫 Label, 别拿 Button.text 找不到就判成"入口没了"。
	var dbg_hit := false
	var q: Array = [st_scene]
	while not q.is_empty() and not dbg_hit:
		var nd = q.pop_back()
		for ch in nd.get_children():
			q.append(ch)
			## ★2026-10-07 重排后是真 Button(像素按钮), 字在 Button.text 上 —— Label/Button 都认。
			if (ch is Label and str((ch as Label).text).contains("调试场")) 					or (ch is Button and str((ch as Button).text).contains("调试场")):
				dbg_hit = true
				break
	_ok("设置页有🛠调试场入口(debug构建)", dbg_hit)
	var _sf := FileAccess.open("res://scripts/scenes/SettingsScene.gd", FileAccess.READ)
	var _stxt := _sf.get_as_text() if _sf != null else ""
	if _sf != null: _sf.close()
	_ok("设置页接线到 _open_debug_arena", _stxt.find("_open_debug_arena") >= 0)
	_ok("设置页入口有 debug 构建 gate", _stxt.find("OS.is_debug_build() or OS.has_environment(\"DEVTOOLS\")") >= 0)
	st_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var mm = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	var mm_dbg := false
	var mm_b: Array = []
	_visible_buttons(mm, mm_b)
	for b in mm_b:
		if b is Button and str((b as Button).text).contains("调试场"):
			mm_dbg = true
			break
	_ok("★主菜单不再有调试场入口(搬家不是复制)", not mm_dbg)
	mm.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ── C. 调试场编辑器(子节点实例化·DEBUG_EDIT=true): 面板齐 + 28龟全可选 + 按钮不越界 ──
	RTScene.DEBUG_EDIT = true
	var cs = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(cs)
	await get_tree().create_timer(1.0).timeout
	var is_arena: bool = cs != null
	_ok("调试场场景已进入(DEBUG_EDIT实例化)", is_arena)
	if is_arena:
		var pal_btns: Array = []
		_visible_buttons(cs, pal_btns)
		_ok("调试场面板按钮已建(≥15)", pal_btns.size() >= 15, "共 %d" % pal_btns.size())
		var bad_c := _offscreen_buttons(cs, vp_real)
		_ok("调试场面板按钮全在屏内", bad_c.is_empty(), "; ".join(bad_c) if not bad_c.is_empty() else "")
		cs._debug._edit_open_turtle_grid()                  # 「选龟」二级网格: 28龟全可选
		await get_tree().process_frame
		await get_tree().process_frame
		var texts := _all_texts(cs)
		var missing: Array = []
		var reg = get_node_or_null("/root/DataRegistry")
		if reg != null:
			for p in reg.all_pets:
				var pname := str((p as Dictionary).get("name", ""))
				if pname != "" and not texts.contains(pname):
					missing.append(pname)
		_ok("选龟网格28龟全可选(含每龟名)", missing.is_empty(), "缺: " + str(missing))
		var bad_g := _offscreen_buttons(cs, vp_real)
		_ok("选龟网格全在屏内", bad_g.is_empty(), "; ".join(bad_g.slice(0, 4)) if not bad_g.is_empty() else "")
		cs._debug._edit_close_popup()
		await get_tree().process_frame
		var uu = cs._debug._edit_place_unit("basic", "right", Vector2(600.0, 400.0))   # 装备网格: 选中单位→开
		cs._edit_sel_unit = uu
		cs._debug._edit_open_equip_grid()
		await get_tree().process_frame
		await get_tree().process_frame
		var eq_n: int = cs._review_console._dbg_equip_ids().size()
		_ok("装备网格可开且有货(装备数=%d≥10)" % eq_n, eq_n >= 10)
		var bad_e := _offscreen_buttons(cs, vp_real)
		_ok("装备网格全在屏内", bad_e.is_empty(), "; ".join(bad_e.slice(0, 4)) if not bad_e.is_empty() else "")
		cs._debug._edit_close_popup()
		await get_tree().process_frame
		cs.queue_free()
		await get_tree().process_frame
	RTScene.DEBUG_EDIT = false

	# ── D. 正常战斗 HUD 按钮不越界(非评审: REVIEW_DEMO_DEFAULT 已翻 false) ──
	_ok("REVIEW_DEMO_DEFAULT=false(iOS测试包不劫持战斗)", RTScene.REVIEW_DEMO_DEFAULT == false)
	var bt = RTScene.new()
	add_child(bt)
	await get_tree().process_frame
	await get_tree().process_frame
	bt.set_process(false)
	bt.set_physics_process(false)
	var bad_d := _offscreen_buttons(bt, vp_real)
	_ok("战斗HUD按钮全在屏内", bad_d.is_empty(), "; ".join(bad_d) if not bad_d.is_empty() else "")
	_ok("投降按钮已建(原暂停位·用户2026-07-30 移除暂停)", bt._surrender_btn != null)
	bt.queue_free()
	await get_tree().process_frame

	# ── E. iPad 4:3 画布复检(主菜单) ──
	get_tree().root.size = Vector2i(1280, 960)
	await get_tree().process_frame
	await _check_scene_buttons("MainMenu", Vector2(get_tree().root.size))

	_check_teamselect_stage()

	# ── F2. ★★SETTINGS_NO_OVERLAP: 设置页穷举两两不重叠(见那个函数的头注) ──
	#    ★放在**最后**: 它要临时把后端配上才造得出账号行, 跑完还原 —— 不让它波及上面各段。
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	await _check_settings_no_overlap()

	_done()


## F. 选龟舞台几何 (2026-07-22 用户「选龟界面画面无法匹配 ios 屏幕…画布大小很奇怪」)
##
## ★为什么 A~E 段抓不到这个 bug: 它们只断言"按钮 rect ⊆ 屏幕 / 按钮不被遮挡 / 贴边按钮在末尾",
##   而 contain 之后按钮本来就都在屏内 → 全绿。真正错的是【舞台本身】:
##     ① 竖直余量 slack=0 却仍无条件加 +76px 下移 → 底边被推出屏外
##     ② contain 在 2.167:1 的 iPhone 上左右各留 20.4% 的死板纯色条
##
## 这里是【纯几何断言, 不实例化场景】—— 因为无头下 DisplayServer.window_get_size() 返回 (0,0),
## 真去实例化算出来的舞台会比真机低算约 30px(tests/verify_ios_ui.gd:74 与 TeamSelectScene 里都记过
## 这个坑)。所以直接按公式验, 不受窗口尺寸影响。
func _check_teamselect_stage() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/scenes/TeamSelectScene.gd")
	if src == "":
		_ok("选龟舞台", false, "读不到 TeamSelectScene.gd")
		return
	# ① 偏移必须按可用余量夹住
	var body := src.substr(maxi(0, src.find("\nfunc _stage_to_screen(")), 900)
	_ok("选龟·偏移按余量夹住", body.find("clampf(off.y") >= 0,
		"_stage_to_screen 无条件加 STAGE_OFFSET → slack=0 时必切底")
	# ② 死常量 STAGE_ZOOM 不该再有【活的】定义
	var has_live_zoom := false
	for l in src.split("\n"):
		var s2 := str(l).strip_edges()
		if s2.begins_with("const STAGE_ZOOM"):
			has_live_zoom = true
	_ok("选龟·死常量已删", not has_live_zoom, "STAGE_ZOOM 全仓库零引用, 留着误导")
	# ③ 缩放必须"尽量铺满但不裁内容带"(用户2026-07-22「整个画布和按钮是不能放大吗」)
	_ok("选龟·按内容带缩放", src.find("func _content_band(") >= 0 and src.find("cover") >= 0,
		"_stage_scale 仍是纯 contain → 屏幕两侧留大片死板, 画布看着很小")
	# ④ 公式自检: 三种屏比下 ①内容带必须完整在屏内 ②不该白白留一大片边
	var poc := Vector2(1647.0, 955.0)
	var band_pos := Vector2(160.0, 74.0)      # 与 RL 实测一致(grid.x=160 / back.y=74)
	var band_size := Vector2(1312.0, 709.0)   # x 到 start 右缘 1472, y 到 start 底 783
	for vp in [Vector2(1560, 720), Vector2(1280, 720), Vector2(1280, 960)]:
		var s3: float = minf(maxf(vp.x / poc.x, vp.y / poc.y),
			minf(vp.x / band_size.x, vp.y / band_size.y))
		var bc := band_pos + band_size * 0.5
		var slack: Vector2 = (vp - band_size * s3) * 0.5
		var off := Vector2(clampf(0.0, -maxf(0.0, slack.x), maxf(0.0, slack.x)),
			clampf(76.0, -maxf(0.0, slack.y), maxf(0.0, slack.y)))
		# 内容带在屏幕上的矩形
		var bl: Vector2 = vp * 0.5 + off + (band_pos - bc) * s3
		var br: Vector2 = bl + band_size * s3
		_ok("选龟·%dx%d 内容带完整" % [int(vp.x), int(vp.y)],
			bl.x >= -0.5 and bl.y >= -0.5 and br.x <= vp.x + 0.5 and br.y <= vp.y + 0.5,
			"内容带 x∈[%.0f,%.0f] y∈[%.0f,%.0f] 超出 %.0fx%.0f —— 会丢按钮" % [bl.x, br.x, bl.y, br.y, vp.x, vp.y])
		# 铺满度: 画面至少要被舞台覆盖 88%(否则又变成"中间一小块")
		var cov: float = minf(1.0, (poc.x * s3) / vp.x) * minf(1.0, (poc.y * s3) / vp.y)
		_ok("选龟·%dx%d 铺满度 %.0f%%" % [int(vp.x), int(vp.y), cov * 100.0], cov >= 0.88,
			"舞台只盖住 %.0f%% 屏幕 → 死板留白过大" % (cov * 100.0))
		# ★舞台某轴盖得住就【不许留缝】。上一版只验"内容带完整", 抓不到这个 ——
		#   PC 1280×720 顶部露了 103px 黑缝(PoC 烤死的 STAGE_OFFSET=76 没被夹掉), 全绿照过。
		var stage: Vector2 = poc * s3
		var org: Vector2 = vp * 0.5 + off - bc * s3
		for ax in [0, 1]:
			if stage[ax] >= vp[ax]:
				org[ax] = clampf(org[ax], vp[ax] - stage[ax], 0.0)
			else:
				org[ax] = (vp[ax] - stage[ax]) * 0.5
		var gap_t: float = maxf(0.0, org.y)
		var gap_b: float = maxf(0.0, vp.y - (org.y + stage.y))
		var gap_l: float = maxf(0.0, org.x)
		var gap_r: float = maxf(0.0, vp.x - (org.x + stage.x))
		var must_fill_y: bool = stage.y >= vp.y
		var must_fill_x: bool = stage.x >= vp.x
		_ok("选龟·%dx%d 无黑缝" % [int(vp.x), int(vp.y)],
			(not must_fill_y or (gap_t < 0.5 and gap_b < 0.5)) and (not must_fill_x or (gap_l < 0.5 and gap_r < 0.5)),
			"舞台盖得住却留缝: 上%.0f 下%.0f 左%.0f 右%.0f" % [gap_t, gap_b, gap_l, gap_r])

func _done() -> void:
	get_tree().paused = false
	print("")
	if _fail == 0:
		print("ALL PASS — iOS测试包UI守卫(全菜单按钮不越界/调试场可入28龟可选/战斗HUD不越界)通过")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## ★★SETTINGS_NO_OVERLAP —— 设置页穷举两两不重叠 (2026-09-29 台账 ④)
##
## 由来: `SettingsScene` 账号那两颗按钮的 y **写死成 192**(git blame 2026-09-22, 不是新写的),
##   而音乐条的 48px 拖动带占 196..244 ⇒ 实测重叠 13px; 拖动带**后建、画在按钮上面**
##   ⇒ **点按钮下沿会变成拖音量**。同屏还有账号头行与副行的字 ink 压 2px。
##
## ★★为什么两年没有判据看见过它: 门禁给每个测试 `TURTLE_SUPABASE=" "` ⇒
##   `SettingsScene._acct_on()` 恒假 ⇒ 账号那四行**一次都没建出来**
##   (memory `fb-gate-subject-never-constructed`: 判据没错, 被测对象不在场)。
##   ⇒ 这一节**真把后端配上**(而不是用 `acct_override`, 那条会顺手立起绑定屏把整页藏掉),
##   并且配一条分母断言「账号行真的在场」。
##
## 判据两条, **穷举**不是抽样:
##   ① 任意两个【可点区域】不许重叠 —— 重叠 = 一次点击有两个主人, 后画的吃掉先画的。
##      这一条就是那个 bug 的形状(拖动带吃掉按钮下沿)。
##   ② 任意两行【字的 ink】不许重叠 —— 压字。ink 用 `verify_ui_consistency._ink_rect`,
##      **不自己再写一份**(memory `fb-hand-rolled-copies-drift`): Label 的 rect 是 400 宽的框,
##      拿框比会把所有居中文字都判成互相重叠。
## ★祖孙不算(容器套着自己的按钮是正常的); 铺满全屏的遮罩/背景不算(它们本来就该盖住一切)。
const UIC_INK := preload("res://tests/verify_ui_consistency.gd")


func _check_settings_no_overlap() -> void:
	var ps = load("res://scenes/Settings.tscn")
	if ps == null:
		_ok("SETTINGS_NO_OVERLAP: 载入 Settings.tscn", false, "load 失败")
		return
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_ok("SETTINGS_NO_OVERLAP: ★分母 拿不到 GameState", false)
		return
	var ink = UIC_INK.new()
	## 真把后端配上 —— 见头注。跑完还原, 免得波及本文件后面的小节。
	var env0 := OS.get_environment("TURTLE_SUPABASE")
	var key0 = ProjectSettings.get_setting("turtle/supabase_anon_key", "")
	var mail0 := str(gs.account_email)
	var aid0 := str(gs.account_id)
	OS.set_environment("TURTLE_SUPABASE", "https://example.invalid")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "sb_publishable_forgate")
	gs.account_id = "ae08e589-1111-2222-3333-444455556666"
	## 两种账号态都量: 未绑定(警示橙那行最长) / 已绑定(头行最长)。
	## ★账号行的**行数与字长都随状态变**, 而写死的 y 只对其中一种碰巧成立 —— 所以要穷举状态。
	for mail in ["", "someone@example.com"]:
		gs.account_email = mail
		var inst = ps.instantiate()
		add_child(inst)
		if inst is Control:
			(inst as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
			(inst as Control).size = Vector2(1280, 720)
		for _i in range(16):
			await get_tree().process_frame
		var tag := "未绑定" if mail == "" else "已绑定"
		## ★分母①: 账号那几行真的建出来了 —— 没建出来的话下面全是空检查
		var acct := 0
		for n in _walk_ios(inst):
			if n is Control and str(n.name).begins_with("AcctRow"):
				acct += 1
		_ok("SETTINGS_NO_OVERLAP[%s] ★分母: 账号行真的在场(%d 个 AcctRow* 节点)" % [tag, acct],
			acct >= 3, "< 3 就是后端没配上, 这一节量的会是另一屏")
		_ok("SETTINGS_NO_OVERLAP[%s] ★分母: 没立起绑定屏(立了就把整页藏掉了)" % tag,
			inst._email_layer == null or not is_instance_valid(inst._email_layer))
		## ── 收集 ──
		var hits: Array = []      # 可点区域(取最外层)
		var inks: Array = []      # 字的 ink
		for n in _walk_ios(inst):
			if not (n is Control) or not (n as Control).is_visible_in_tree():
				continue
			var c := n as Control
			var r: Rect2 = c.get_global_rect()
			if r.size.x <= 0.5 or r.size.y <= 0.5:
				continue
			if r.size.x >= 1279.0 and r.size.y >= 719.0:
				continue          # 铺满全屏的背景/遮罩: 它本来就该盖住一切
			if c is Label and str((c as Label).text).strip_edges() != "":
				inks.append({"r": ink._ink_rect(c as Label), "t": str((c as Label).text), "n": c})
			var clickable: bool = (c is BaseButton and not (c as BaseButton).disabled) \
				or (not (c is BaseButton) and c.mouse_filter == Control.MOUSE_FILTER_STOP)
			if clickable and not _has_hit_ancestor(c, inst):
				hits.append({"r": r, "t": _hit_tag(c), "n": c})
		print("  [分母] SETTINGS_NO_OVERLAP[%s]: 可点区域 %d 个 / 有字的 Label %d 个" % [
			tag, hits.size(), inks.size()])
		_ok("SETTINGS_NO_OVERLAP[%s] ★分母: 扫到可点区域(0 个 = 空检查)" % tag, hits.size() >= 6,
			"%d 个" % hits.size())
		_ok("SETTINGS_NO_OVERLAP[%s] ★分母: 扫到字(0 条 = 空检查)" % tag, inks.size() >= 6,
			"%d 条" % inks.size())
		## ── ① 可点区域两两不重叠 ──
		var bad_hit: Array = []
		for i in range(hits.size()):
			for j in range(i + 1, hits.size()):
				var a = hits[i]
				var b = hits[j]
				if _nested_ios(a["n"], b["n"]) or _nested_ios(b["n"], a["n"]):
					continue
				var it: Rect2 = (a["r"] as Rect2).intersection(b["r"])
				if it.size.x > 0.5 and it.size.y > 0.5:
					bad_hit.append("%s × %s 压 %.0f×%.0f" % [
						str(a["t"]), str(b["t"]), it.size.x, it.size.y])
		_ok("SETTINGS_NO_OVERLAP[%s] ★★任意两个可点区域不重叠(重叠=后画的吃掉先画的)" % tag,
			bad_hit.is_empty(), " / ".join(bad_hit))
		## ── ② 字的 ink 两两不重叠 ──
		var bad_ink: Array = []
		for i2 in range(inks.size()):
			for j2 in range(i2 + 1, inks.size()):
				var a2 = inks[i2]
				var b2 = inks[j2]
				if _nested_ios(a2["n"], b2["n"]) or _nested_ios(b2["n"], a2["n"]):
					continue
				var it2: Rect2 = (a2["r"] as Rect2).intersection(b2["r"])
				if it2.size.x > 0.5 and it2.size.y > 0.5:
					bad_ink.append("「%s」× 「%s」压 %.0f×%.0f" % [
						str(a2["t"]).substr(0, 12), str(b2["t"]).substr(0, 12),
						it2.size.x, it2.size.y])
		_ok("SETTINGS_NO_OVERLAP[%s] ★★任意两行字的 ink 不重叠" % tag,
			bad_ink.is_empty(), " / ".join(bad_ink))
		## ── ③ 全在屏内(流水往下算, 别把最后一块推出屏外) ──
		var out_of: Array = []
		for h in hits:
			var hr: Rect2 = h["r"]
			if hr.position.y < -0.5 or hr.end.y > 720.5:
				out_of.append("%s y %.0f..%.0f" % [str(h["t"]), hr.position.y, hr.end.y])
		_ok("SETTINGS_NO_OVERLAP[%s] ★可点区域全在 720 高之内(流水不许把末块推出屏)" % tag,
			out_of.is_empty(), " / ".join(out_of))
		inst.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	## 还原(不还原会波及本文件后面的小节与同进程里别的东西)
	OS.set_environment("TURTLE_SUPABASE", env0)
	ProjectSettings.set_setting("turtle/supabase_anon_key", key0)
	gs.account_email = mail0
	gs.account_id = aid0
	ink.free()


func _walk_ios(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk_ios(c))
	return out


func _nested_ios(a: Node, b: Node) -> bool:
	var p := a.get_parent()
	while p != null:
		if p == b:
			return true
		p = p.get_parent()
	return false


## 这个可点区域的祖先里已经有一个可点区域了吗 —— 有的话只算最外层那个。
## ★`_text_button` 是 `Control`(默认 STOP) 套一个 `TextureRect`(也 STOP), 两个同矩形;
##   不去重的话每颗按钮都会跟自己的壳报一次"重叠"。
func _has_hit_ancestor(c: Control, root_n: Node) -> bool:
	var p := c.get_parent()
	while p != null and p != root_n:
		if p is Control:
			var pc := p as Control
			if pc is BaseButton or pc.mouse_filter == Control.MOUSE_FILTER_STOP:
				return true
		p = p.get_parent()
	return false


## 报错里认得出是哪一块: 按钮自己的字 → 子树里第一行字 → 节点名
func _hit_tag(c: Control) -> String:
	if c is Button and str((c as Button).text).strip_edges() != "":
		return "「%s」" % str((c as Button).text).substr(0, 12)
	for n in _walk_ios(c):
		if n is Label and str((n as Label).text).strip_edges() != "":
			return "「%s」" % str((n as Label).text).substr(0, 12)
	return "%s<%s>" % [str(c.name), c.get_class()]
