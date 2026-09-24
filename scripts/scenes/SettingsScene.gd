extends Control

const TopBar = preload("res://scripts/util/top_bar.gd")
var _top_bar = null

## SettingsScene — 设置 (1:1 PoC SettingsScene.ts): BGM/SFX 音量 + 全屏 + 重置存档.
## Phaser 绝对坐标 (中心原点) → Godot 左上 (position = 中心 - size/2). 视口 1280×720.

const W := 1280.0
const H := 720.0

var _perf_btn: Label = null
var _full_btn: Label = null   # 全屏按钮文字 (切换后要同步, 原来没接住 → 切了还写"全屏")


func _ready() -> void:
	_bg()

	## ★顶栏走全项目同一个原语 `TopBar`(2026-09-19·用户「做」)。
	##   规则来自 599 张/146 个触屏游戏枢纽页的逐张实测, 见 top_bar.gd 头注。
	var _sm: Vector4 = SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	_top_bar = TopBar.new(self, {
		"title": "⚙ 设置",
		"palette": TopBar.DEEP,
		"width": W,
		"safe_left": _sm.x,
		"safe_right": _sm.z,
		## ★★墙上**返回键失效** —— 返回得去的墙不是墙。
		##   ★用**具名方法**不用匿名闭包: 字典字面里放不下多行闭包(语法错),
		##   而且具名之后门禁量得到它接的是谁。
		"on_back": _on_back,
	})

	# 账号行 @ (W/2, 150) — 标题栏与第一个滑条之间那块空地
	_account_row()

	# BGM 滑条 @ (W/2, 220) — 拖动实时生效; 写盘只在松手时一次 (原来每帧 save() = 拖一下写几十次盘)
	_slider(W / 2.0, 220.0, "🎵 BGM 音量", GameState.bgm_volume,
		func(v): GameState.bgm_volume = v; Audio.bgm_volume = v; Audio.apply_bgm_volume(),   # ★补: 原来只设变量没调 apply → 拖动对正在播的BGM无效(用户2026-07-19"音量键根本没效果")
		func(): GameState.save())
	# SFX 滑条 @ (W/2, 330) — 松手才试听 + 写盘 (原来拖动中每帧都播音效)
	_slider(W / 2.0, 330.0, "🔊 音效音量", GameState.sfx_volume,
		func(v): GameState.sfx_volume = v; Audio.sfx_volume = v,
		func(): Audio.play_sfx("hit-physical", 1.0); GameState.save())

	# 全屏 @ (W/2, 410) — PoC 用 ⛶(U+26F6) 做图标, 但打包字体链无此字形(web/linux 豆腐块)且无等义替代 → 只留文字
	_full_btn = _text_button(W / 2.0, 410.0, _fullscreen_label(), _toggle_fullscreen)

	# 低画质模式 @ (W/2, 490) — 现在是【真开关】: 关 MSAA + 3D 渲染分辨率 ×0.75 + 停菜单背景漂移; 持久化到存档.
	_perf_btn = _text_button(W / 2.0, 490.0, _perf_label(), _toggle_perf)

	# 🛠 调试场 @ (W/2, 560) — 用户 2026-09-17:「调试场可以塞到设置里, 正式上线的不会要调试场」。
	#   原来它钉在主菜单中间那条空档上, 而那块地现在给了「本周赛程条」。
	#   ★gate 原样搬过来: OS.is_debug_build() 在导出 release 模板下为 false ⇒ 正式包玩家看不到。
	#   门禁 verify_menu 也跟着搬(它验的是"调试入口不泄漏给玩家", 不是"这行代码在哪个文件")。
	var dev := OS.is_debug_build() or OS.has_environment("DEVTOOLS")
	var reset_y := 580.0
	if dev:
		_text_button(W / 2.0, 560.0, "🛠 调试场", _open_debug_arena)
		reset_y = 640.0     # 让开调试场; 正式包里没这个键, 重置就回到原来的 580(不留空洞)

	# 重置存档 @ (W/2, 580 / 开发构建 640) — ⚠ 破坏性 → 二次确认
	_text_button(W / 2.0, reset_y, "⚠ 重置所有存档", _ask_reset)

	# 底部提示 @ (W/2, H-40), 11px #888
	var hint := _stroked_label("设置自动保存", 11, "#888888", "", 0)   # PoC 字面是"到 localStorage"(浏览器术语), Godot 存 user:// → 去掉误导后缀
	_place_center(hint, W / 2.0, H - 40.0)


	# ★UI 双端适配(用户2026-08-01「有些画面都没有居中」): 把内容装进 1280×720 设计框并居中于真实视口。
	#   本屏原先直接按设计坐标画在视口(0,0) → 21:9 上内容整体坐在左边 200px(审计器实测)。
	#   ★必须放在 _ready 最后 —— UIFrame 收编的是【已经建出来的】子节点。
	#   (异步晚建的节点由 UIFrame._process 的孤儿收编兜住。)
	## ★★2026-09-18 这行差点丢了: 上面那句「## ESC 返回主菜单」本是 `_unhandled_input` 的文档注释,
	##   却写在了 _ready 体内的这行【之前】。我把调试场的 const+func 插在那条注释前面, 于是
	##   `const` 把 _ready 从中间截断, 这行落进了 _open_debug_arena 的函数体 ——
	##   设置页的居中适配变成"只有点调试场时才执行"。verify_ui_layout ② 当场红(偏离 185px)。
	##   ⇒ 往函数之间插代码前, 先确认插入点【不在某个函数体内】(CLAUDE.md §3.7 同族)。
	UIFrame.attach(self)

	## ★★登录墙(2026-09-24 用户「直接改为必须绑定账号吧」): 页面建完再盖上去。
	##   放 `_ready` 末尾而不是开头 —— 开头盖的话底下的控件还没建,
	##   玩家会看到墙先出现、页面在后面一块块长出来。
	_maybe_login_wall()


# ─── D-3 账号行 (2026-09-21) ───────────────────────────────────────
## ★★这一行存在的真正理由不是"显示个 id", 是方案书 D-3 里那句：
##   **「没绑邮箱换设备就是丢档，这一点要在 UI 上说清楚」**。
##   匿名账号是默认态(不强制注册就能玩), 代价就是换手机拿不回来 ——
##   不说清楚的话, 玩家是在**不知情**的前提下承担这个代价。
##
## ★没配后端时**整行不显示**(不是显示"离线"):
##   与 D-1 的三态同一条原则 —— 没配是**有意关掉**, 不该在设置页喊话。
##   做成常驻的"在线/离线"角标是反的: 它等于告诉玩家"你是残缺状态, 去修",
##   而玩家多半修不了 ⇒ 制造焦虑但给不出行动(`remote_pool.gd` 头注记过同样的取舍)。
const _SB_ACC := preload("res://scripts/net/supabase.gd")
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")

func _account_row() -> void:
	if not _SB_ACC.enabled():
		return                                   # 没配后端 = 有意关掉, 什么都不显示
	var aid := str(GameState.account_id)
	var mail := str(GameState.account_email)
	var head := ""
	var sub := ""
	if aid == "":
		## 配了后端但还没拿到身份(刚开机还在登, 或登不上)。不说"失败" —— 说不准。
		head = "账号：连接中…"
		sub = ""
	elif _SB_ACC.session_lost():
		## D-3c: 绑了邮箱的号登录失效了。**不会**自动换成新匿名号(那是静默换身份),
		##   只能用邮箱把同一个号取回来 —— 所以这里要明说该点哪个按钮。
		head = "账号：%s" % mail
		sub = "⚠ 登录已失效 —— 点「用邮箱取回」重新登录"
	elif _SB_ACC.save_conflict():
		## D-8: 两台设备交替玩 ⇒ 云端版本和这台对不上。**不自动选**, 等玩家二选一。
		head = "账号：%s" % mail
		sub = "⚠ 云端存档和这台设备的不一样（可能在别的设备上玩过）"
	elif mail != "":
		## ★D-8 之后这句才是真的: 绑了邮箱的号, 进度会同步到云端(verify_save_sync ⑦ 守着)。
		head = "账号：%s" % mail
		sub = "已绑定 · 换设备可用这个邮箱取回账号和进度"
	else:
		## ★只显前 8 位: 完整 uuid 36 个字符, 在 1280 宽里既放不下也没用 ——
		##   它的用途是「报问题时能对上号」, 前 8 位足够。
		head = "账号：匿名 · %s" % aid.substr(0, 8)
		sub = "⚠ 未绑定邮箱 —— 换设备后账号和进度都找不回来"
	var a := _stroked_label(head, 15, "#cfe3ff", "", 0)
	_place_center(a, W / 2.0, 128.0)
	if sub != "":
		var col := "#ffb454" if mail == "" else "#8fa6bd"    # 未绑定用警示橙, 已绑定用灰
		var b := _stroked_label(sub, 12, col, "", 0)
		_place_center(b, W / 2.0, 148.0)
	## ★★2026-09-21 把「存档」两个字全部换掉 —— 原文案是**不准确的**。
	##   核实过服务端五张表(`accounts` / `ghosts` / `matches` / `standings` /
	##   `service_status`)：**没有一张存玩家存档**(`accounts` 只有
	##   display_name / created_at / last_seen)。龟等级、装备、深海币
	##   全在本机 `user://savegame.json`。
	##   ⇒ 绑邮箱找回的是【账号(赛季身份：排名/战绩/鬼影)】，**不是存档**。
	##   照原文案写等于承诺一件架构上做不到的事。存档同步是另一件事(未决)。
	## ★D-8: 匿名号**不**同步(隐私政策承诺过只有绑定者才上传) ⇒ 两种状态说的话不一样。
	var note := _stroked_label(("（绑定邮箱后，进度会同步到云端）" if mail == ""
		else "（进度会自动同步到云端）"), 11, "#7e8fa0", "", 0)
	_place_center(note, W / 2.0, 166.0)
	## ★D-3c 补上 v0.19.423 漏掉的入口: 那一版只有「绑定邮箱」,
	##   **取回流程写了但点不到** —— 新手机上根本没法用邮箱把号拿回来。
	##   `verify_session_refresh` 没有覆盖到 UI, 这条由 `verify_account` ④ 走真入口验。
	if aid != "" and _SB_ACC.save_conflict():
		_small_button(W / 2.0 - 80.0, 192.0, "处理存档冲突", _open_conflict_dialog)
	elif aid != "":
		_small_button(W / 2.0 - 80.0, 192.0,
			("换个邮箱" if mail != "" else "绑定邮箱"),
			func(): _open_email_dialog(_SB_ACC.FLOW_BIND))
	_small_button((W / 2.0 + 80.0) if aid != "" else W / 2.0, 192.0, "用邮箱取回",
		func(): _open_email_dialog(_SB_ACC.FLOW_RECOVER))


# ─── D-8 存档冲突: 二选一 ──────────────────────────────────────
## ★两个选项**各自写清会丢什么** —— 玩家不知道代价就选, 等于我们替他选了。
## ★不做合并: 合并游戏状态没有安全做法(同一只龟两边各升了一级, 该取哪边?)。
func _open_conflict_dialog() -> void:
	if _confirm_layer != null and is_instance_valid(_confirm_layer):
		return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_confirm_layer = dim

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffb454")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(W / 2.0 - 280, H / 2.0 - 160); box.size = Vector2(560, 320)
	dim.add_child(box)

	var ttl := Label.new()
	ttl.text = "存档冲突"
	ttl.add_theme_font_size_override("font_size", 24)
	ttl.add_theme_color_override("font_color", Color("#ffb454"))
	ttl.position = Vector2(0, 18); ttl.size = Vector2(560, 32)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)

	var msg := Label.new()
	msg.text = "云端的存档被另一台设备更新过，和这台设备上的不一样。选一份留下："
	msg.add_theme_font_size_override("font_size", 14)
	msg.add_theme_color_override("font_color", Color("#c9d6e2"))
	msg.position = Vector2(30, 60); msg.size = Vector2(500, 40)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(msg)

	var opts := [
		["用云端的", "这台设备上次同步之后的进度会被换掉\n（换之前先在本机备份一份）",
			func(): _SB_ACC.resolve_conflict_use_cloud()],
		["用这台的", "另一台设备上的进度会被这台覆盖",
			func(): _SB_ACC.resolve_conflict_use_local()],
	]
	for i in range(opts.size()):
		var o: Array = opts[i]
		var x := 40.0 + float(i) * 250.0
		var b := Button.new()
		b.text = str(o[0])
		b.add_theme_font_size_override("font_size", 17)
		b.position = Vector2(x, 112); b.size = Vector2(230, 44)
		var cb: Callable = o[2]
		b.pressed.connect(func():
			cb.call()
			dim.queue_free(); _confirm_layer = null
			get_tree().reload_current_scene())
		box.add_child(b)
		var cost := Label.new()
		cost.text = str(o[1])
		cost.add_theme_font_size_override("font_size", 12)
		cost.add_theme_color_override("font_color", Color("#ff8a94"))
		cost.position = Vector2(x, 162); cost.size = Vector2(230, 60)
		cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(cost)

	var close := Button.new()
	close.text = "先不选"
	close.add_theme_font_size_override("font_size", 15)
	close.position = Vector2(200, 256); close.size = Vector2(160, 40)
	close.pressed.connect(func(): dim.queue_free(); _confirm_layer = null)
	box.add_child(close)


## 紧凑按钮 —— 账号行下面那一个。`_text_button` 是 260×50 的木框大按钮,
## 塞进 128~192 这段窄地里会压到下面的 BGM 滑条。
func _small_button(cx: float, cy: float, label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 14)
	b.size = Vector2(150, 30)
	b.position = Vector2(cx - 75.0, cy - 15.0)
	b.pressed.connect(cb)
	add_child(b)
	return b


# ─── D-3b 补绑邮箱 / 换设备取回 (2026-09-21) ──────────────────────
## ★两条流程共用这一个弹窗, 只有标题和第二步的判据不同(见 supabase.gd 那节)。
## ★★**邮件里要有验证码**。Supabase 的默认邮件模板只放一条链接,
##   模板里得有 `{{ .Token }}` 才会带码 —— 那是后台面板上的一次性设置。
##   ★位数**不写死**: 2026-09-22 读后台配置实测 `mailer_otp_length = 8`,
##     原来这里写的「6 位」是我凭印象写的, 错了。位数是后台的一个设置, 写死就会漂。
##   提示语写「邮件里的验证码」: 万一收到的邮件没有码,
##   测试者一眼就知道是哪儿的问题, 而不是对着输入框发呆。
var _email_layer: Control = null
var _email_edit: LineEdit = null
var _code_edit: LineEdit = null
var _nick_edit: LineEdit = null
var _email_status: Label = null
var _email_send_btn: Button = null
var _email_ok_btn: Button = null

## `dismissible = false` ⇒ **登录墙**: 没有「关闭」, 关不掉也返回不了。
## ★墙与「设置里主动绑定」共用这一个对话框 —— 另做一份就要把昵称那一行
##   和验证码状态机抄第二遍, 而抄一次永远落后一次。
## 该不该开登录墙。★判据只有 `phase2_config.login_wall_on` 一处 ——
##   主菜单只负责把人送过来, 不自己判(两处各判一份必然漂)。
## 返回主菜单。★★**墙上失效** —— 判据与开墙同一处, 不另写一份。
func _on_back() -> void:
	if _P2C.login_wall_on(_SB_ACC.enabled(), str(GameState.account_email)):
		return
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _maybe_login_wall() -> void:
	if not _P2C.login_wall_on(_SB_ACC.enabled(), str(GameState.account_email)):
		return
	## ★★把返回箭头**藏掉** —— 实拍拓出来的: 顶栏在更高的 CanvasLayer 上,
	##   遮罩盖不住它 ⇒ 它看着能按、按下去却没反应。
	##   本仓原则: **「点了没反应」比「按钮是灰的」糟得多**。
	##   (`_on_back` 里那道判据留着作防御 —— 万一哪天须栏改成同层。)
	if _top_bar != null and _top_bar.back_btn != null:
		_top_bar.back_btn.visible = false
	_open_email_dialog(_SB_ACC.FLOW_BIND, false)


func _open_email_dialog(flow: String, dismissible: bool = true) -> void:
	if _email_layer != null and is_instance_valid(_email_layer):
		return
	_SB_ACC.reset_email_flow()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_email_layer = dim

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#5aa0ff")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	## ★绑定流程多一行「昵称」⇒ 高 340 → 400(取回流程不填, 见下面那个 if)
	var _bh: float = 400.0 if flow == _SB_ACC.FLOW_BIND else 340.0
	box.position = Vector2(W / 2.0 - 260, H / 2.0 - _bh / 2.0); box.size = Vector2(520, _bh)
	dim.add_child(box)

	var ttl := Label.new()
	ttl.text = (_P2C.login_wall_head() if not dismissible
		else ("绑定邮箱" if flow == _SB_ACC.FLOW_BIND else "用邮箱取回账号"))
	ttl.add_theme_font_size_override("font_size", 24)
	ttl.add_theme_color_override("font_color", Color("#cfe3ff"))
	ttl.position = Vector2(0, 18); ttl.size = Vector2(520, 32)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)

	var why := Label.new()
	## ★说清楚它**到底**能做什么、不能做什么 —— 见 `_account_row` 里那段长注释。
	if flow == _SB_ACC.FLOW_BIND:
		## ★墙上第一句先让**老玩家别慌**: 绑定是升级同一个号, 进度一个字节都不会变。
		why.text = (_P2C.login_wall_body() if not dismissible
			else ("绑定之后，换手机能用这个邮箱把【账号】取回来（排名、战绩、你的阵容）。\n"
				+ "⚠ 龟和装备是存在这台手机上的，换设备仍然会丢。"))
	else:
		## ★取回只换【账号】, 这台设备上的龟和装备原样不动 —— 照实说, 不许说成「取回存档」
		##   (服务端现在没有存档, `verify_account` ④ 有一条专门禁这句话)。
		## ★D-8: 取回会把那个号的云存档拉下来**整体替换**本机进度 —— 照实说,
		##   并说清替换之前会先备份(GameState.backup_save)。
		why.text = ("用你绑过的邮箱收一个验证码，把那个账号和它的进度取回到这台设备上。\n"
			+ "⚠ 这台设备现在的进度会被换掉（换之前会先在本机备份一份）。")
	why.add_theme_font_size_override("font_size", 13)
	why.add_theme_color_override("font_color", Color("#9fb4c8"))
	why.position = Vector2(30, 56); why.size = Vector2(460, 54)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(why)

	## ★★昵称(只有绑定流程要填)。用户 2026-09-24:「这个在创建账号应该一起吧」——
	##   这个项目里玩家感知得到的「创建账号」只有这一处(首启建匿名号是**静默**的)。
	##   取回流程不填: 那个号已经有昵称了, 跟着账号一起回来; 在那儿再问等于让玩家改名。
	var _dy: float = 0.0
	if flow == _SB_ACC.FLOW_BIND:
		var nlab := Label.new()
		nlab.text = "起个名字(%d~%d 个字) —— 排行榜和对阵图上别人看到的就是它" % [
			_P2C.NICK_MIN, _P2C.NICK_MAX]
		nlab.add_theme_font_size_override("font_size", 12)
		nlab.add_theme_color_override("font_color", Color("#9fb4c8"))
		nlab.position = Vector2(40, 116); nlab.size = Vector2(440, 18)
		box.add_child(nlab)
		_nick_edit = LineEdit.new()
		_nick_edit.placeholder_text = "你的名字"
		_nick_edit.text = str(GameState.nickname)
		_nick_edit.max_length = _P2C.NICK_MAX * 2   # ★按**规范化后**判长度, 这里只防手滑贴一长串
		_nick_edit.add_theme_font_size_override("font_size", 16)
		_nick_edit.position = Vector2(40, 136); _nick_edit.size = Vector2(440, 40)
		box.add_child(_nick_edit)
		_dy = 60.0

	_email_edit = LineEdit.new()
	_email_edit.placeholder_text = "你的邮箱"
	_email_edit.text = str(GameState.account_email)
	_email_edit.add_theme_font_size_override("font_size", 16)
	_email_edit.position = Vector2(40, 120 + _dy); _email_edit.size = Vector2(300, 40)
	box.add_child(_email_edit)

	_email_send_btn = Button.new()
	_email_send_btn.text = "发验证码"
	_email_send_btn.add_theme_font_size_override("font_size", 15)
	_email_send_btn.position = Vector2(352, 120 + _dy); _email_send_btn.size = Vector2(128, 40)
	_email_send_btn.pressed.connect(func():
		_SB_ACC.send_code_async(_email_edit.text, flow))
	box.add_child(_email_send_btn)

	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "邮件里的验证码"
	_code_edit.add_theme_font_size_override("font_size", 16)
	_code_edit.position = Vector2(40, 172 + _dy); _code_edit.size = Vector2(300, 40)
	box.add_child(_code_edit)

	_email_ok_btn = Button.new()
	_email_ok_btn.text = "确认"
	_email_ok_btn.add_theme_font_size_override("font_size", 15)
	_email_ok_btn.position = Vector2(352, 172 + _dy); _email_ok_btn.size = Vector2(128, 40)
	_email_ok_btn.pressed.connect(func():
		## ★★昵称先过一遍规则再验码 —— 验码成功之后才存就晚了:
		##   那一刻对话框已经关了, 玩家没机会改。规则只有 `phase2_config` 一份。
		if flow == _SB_ACC.FLOW_BIND:
			var err: String = _P2C.nickname_error(_nick_edit.text)
			if err != "":
				_email_status.text = err
				_email_status.add_theme_color_override("font_color", Color("#ff9a9a"))
				return
			GameState.nickname = _P2C.nickname_clean(_nick_edit.text)
			GameState.save()
		_SB_ACC.verify_code_async(_code_edit.text))
	box.add_child(_email_ok_btn)

	_email_status = Label.new()
	_email_status.add_theme_font_size_override("font_size", 13)
	_email_status.position = Vector2(30, 222 + _dy); _email_status.size = Vector2(460, 48)
	_email_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_email_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_email_status)

	## ★★登录墙**不给关闭** —— 关得掉的墙不是墙。
	##   (这一条被 `verify_login_wall` 守着: 墙上不许有可点的关闭。)
	if dismissible:
		var close := Button.new()
		close.text = "关闭"
		close.add_theme_font_size_override("font_size", 16)
		close.position = Vector2(180, 282 + _dy); close.size = Vector2(160, 40)
		close.pressed.connect(func():
			_SB_ACC.reset_email_flow()
			dim.queue_free(); _email_layer = null)
		box.add_child(close)

	## ★用 Timer 子节点轮询, **不用 `create_timer` 闭包** ——
	##   树级计时器接闭包会活过场景释放(本仓有一条门禁专门守这个)。
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	t.timeout.connect(_email_poll)
	dim.add_child(t)
	_email_poll()


## 把网络层那个小状态机画出来。**每一步都要有话说** ——
## 点完「发验证码」什么都不变的话, 玩家只会反复点(还把限流撞满)。
func _email_poll() -> void:
	if _email_status == null or not is_instance_valid(_email_status):
		return
	var st := str(_SB_ACC.email_state())
	var msg := str(_SB_ACC.email_msg())
	var col := "#9fb4c8"
	match st:
		_SB_ACC.EM_SENDING:
			msg = "正在发送…"
		_SB_ACC.EM_VERIFYING:
			msg = "正在验证…"
		_SB_ACC.EM_ERR:
			col = "#ff8a94"
		_SB_ACC.EM_OK:
			col = "#7fe07f"
		_:
			if msg == "":
				msg = "填邮箱 → 发验证码 → 把邮件里的数字填到下面"
	_email_status.text = msg
	_email_status.add_theme_color_override("font_color", Color(col))
	if _email_send_btn != null and is_instance_valid(_email_send_btn):
		_email_send_btn.disabled = (st == _SB_ACC.EM_SENDING or st == _SB_ACC.EM_VERIFYING)
	if _email_ok_btn != null and is_instance_valid(_email_ok_btn):
		## 还没发码就点「确认」是无意义的 —— 直接禁掉比让他点了再报错好。
		_email_ok_btn.disabled = not (st == _SB_ACC.EM_SENT or st == _SB_ACC.EM_ERR)


# ─── 🛠 调试场 (自由摆位测试场; 开发工具, 正式包不出现) ───
## 2026-09-17 从 MainMenuScene 整体搬来 —— 行为一字未改, 只换了入口所在的屏。
const _RB_DEBUG := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

func _open_debug_arena() -> void:
	_RB_DEBUG.DEBUG_EDIT = true    # 调试场=自由摆位编辑器(左键摆龟/拖拽/右键删/装备笔刷/开始暂停·用户2026-07-12恢复)
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.set("dual_active", false)   # 清双路态
	get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")


## ESC 返回主菜单 (原来只能点左上角箭头)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _confirm_layer != null and is_instance_valid(_confirm_layer):
			_confirm_layer.queue_free()   # 确认框开着 → ESC 先取消
			return
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _fullscreen_label() -> String:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return "退出全屏"
	return "全屏"


## ★2026-08-19 缩短: 原文「🪶 低画质模式: 关 (高画质)」在 260 宽的木牌里**装不下** ——
##   木牌两端的花纹柱实测各占 29px, 内部只有 202px, 而这行字的墨迹约 240px ⇒ 字骑在花纹上。
##   (实拍看出来的; 门禁原来查不到, 因为它只把 StyleBoxTexture/NinePatchRect 当框,
##    而这里的框是一个**拉伸的 TextureRect**。已一并补进 verify_ui_consistency。)
##   "开/关" 也去掉了 —— 按钮显示的是**当前是什么**, 不是"这个开关的开关状态", 后者要绕一圈才读懂。
func _perf_label() -> String:
	if GameState.perf_lite:
		return "🪶 画质: 低"
	return "🪶 画质: 高"


## 低画质模式 = 真开关 (原来只改自己的 label, grep 全库无第二处引用 = 死按钮)
## 实际效果见 `apply_perf_lite()` (战斗视口) 与各菜单场景的背景漂移 gate。
func _toggle_perf() -> void:
	GameState.perf_lite = not GameState.perf_lite
	GameState.save()
	if _perf_btn != null:
		_perf_btn.text = _perf_label()
	## 按钮上只剩"高/低", 于是把"低=更流畅"这条信息挪到 toast 里, 不然玩家不知道调它图什么。
	_toast("画质已设为%s%s · 下次进战斗生效" % [
		"低" if GameState.perf_lite else "高",
		" (更流畅)" if GameState.perf_lite else ""])


func _toggle_fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	var to_full: bool = not (m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if to_full else DisplayServer.WINDOW_MODE_WINDOWED)
	GameState.fullscreen = to_full
	GameState.save()                      # 持久化: 原来切了不存, 重启回窗口
	if _full_btn != null:
		_full_btn.text = _fullscreen_label()   # 同步文字: 原来 Label 没接住, 切了还写"全屏"


# ── 重置存档: ⚠ 破坏性, 必须二次确认 ──────────────────────────
var _confirm_layer: Control = null

func _ask_reset() -> void:
	if _confirm_layer != null and is_instance_valid(_confirm_layer):
		return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_confirm_layer = dim

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ff5566")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(W / 2.0 - 260, H / 2.0 - 130); box.size = Vector2(520, 260)
	dim.add_child(box)

	var ttl := Label.new()
	ttl.text = "⚠ 重置所有存档？"
	ttl.add_theme_font_size_override("font_size", 26)
	ttl.add_theme_color_override("font_color", Color("#ff5566"))
	ttl.position = Vector2(0, 22); ttl.size = Vector2(520, 36)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)

	var msg := Label.new()
	msg.text = "将清空：深海币 · 背包装备 · 出战统领 · 赛季进度(命/等级/胜场) · 糖果罐 · 布阵。\n**此操作不可撤销。**（音量/全屏/画质等偏好设置不受影响）"
	msg.add_theme_font_size_override("font_size", 15)
	msg.add_theme_color_override("font_color", Color("#c9d6e2"))
	msg.position = Vector2(30, 74); msg.size = Vector2(460, 90)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(msg)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.position = Vector2(70, 186); cancel.size = Vector2(160, 44)
	cancel.pressed.connect(func(): dim.queue_free(); _confirm_layer = null)
	box.add_child(cancel)

	var ok := Button.new()
	ok.text = "确认清空"
	ok.add_theme_font_size_override("font_size", 18)
	ok.add_theme_color_override("font_color", Color("#ff8a94"))
	ok.position = Vector2(290, 186); ok.size = Vector2(160, 44)
	ok.pressed.connect(func():
		dim.queue_free(); _confirm_layer = null
		_do_reset())
	box.add_child(ok)


func _do_reset() -> void:
	GameState.reset_save()
	_toast("✓ 存档已清空")


# ── 滑条 (PoC renderSlider, track w=380, handle r14) ──
## cb        = 拖动中每次变化都调 (实时生效, 不写盘)
## on_release= 松手/点轨道时调一次 (写盘 / 试听音效). 原实现在 cb 里 save()+play_sfx → 拖一下写几十次盘、爆音。
func _slider(cx: float, cy: float, label: String, init: float, cb: Callable, on_release: Callable = Callable()) -> void:
	var track_w := 380.0
	var left := cx - track_w / 2.0

	# 标签 @ (x - w/2, y - 30) origin(0,0.5), 16px #fff
	var lbl := _stroked_label(label, 16, "#ffffff", "", 0)
	lbl.position = Vector2(left, cy - 30.0 - 8.0)
	add_child(lbl)

	# 轨道 8px 高 #444
	var track := ColorRect.new()
	track.color = Color("#444444")
	track.size = Vector2(track_w, 8.0)
	track.position = Vector2(left, cy - 4.0)
	add_child(track)
	# 填充 #ffd93d
	var fill := ColorRect.new()
	fill.color = Color("#ffd93d")
	fill.size = Vector2(track_w * init, 8.0)
	fill.position = Vector2(left, cy - 4.0)
	add_child(fill)

	# 百分比文字 @ (x + w/2 + 20, y) origin(0,0.5), monospace 14px #ffd93d
	var pct := Label.new()
	pct.text = "%d%%" % int(round(init * 100.0))
	pct.add_theme_font_size_override("font_size", 14)
	pct.add_theme_color_override("font_color", Color("#ffd93d"))
	pct.add_theme_font_override("font", _mono_font())
	pct.size = Vector2(60, 16)
	pct.position = Vector2(cx + track_w / 2.0 + 20.0, cy - 8.0)
	add_child(pct)

	# 圆 handle r14 (用 HSlider 隐藏轨道, 自绘圆) — 用 Button 圆形 grabber
	var handle := _circle(14.0, Color("#ffd93d"))
	handle.position = Vector2(left + track_w * init - 14.0, cy - 14.0)
	# ★2026-08-01: handle 不再自己吃事件 —— 它只有 28×28(手机上 15pt), 是个点不中的把手。
	#   拖拽统一交给下面那条 48px 高的透明命中条(整行都能拖), 视觉不变、可拖范围大得多。
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(handle)

	var apply := func(px: float):
		var clamped: float = clampf(px, left, left + track_w)
		var v: float = (clamped - left) / track_w
		handle.position.x = clamped - 14.0
		fill.size.x = track_w * v
		pct.text = "%d%%" % int(round(v * 100.0))
		cb.call(v)

	# (原来挂在 handle 上的拖拽已删: handle 现在 mouse_filter=IGNORE, 那段代码永远收不到事件 ——
	#  留着就是一段"看起来在工作"的死代码。拖拽全走下面的命中条。)
	# 点轨道跳 (即刻应用 + 一次 on_release)
	# ★手机板触控热区(用户2026-08-01): 轨道本体只有 8px 高 = 手机上【4pt】, 手指绝无可能点中;
	#   handle 也只有 28px(15pt)。所以另铺一条【透明命中条】盖住整行(48px 高 = 26pt),
	#   点/拖它都等价于点轨道 —— 视觉一点没变, 可点范围从 4pt 变成 26pt。
	#   ★命中条要在 handle 【之前】加(add_child 顺序=绘制/命中顺序), 否则它会盖住 handle 的拖拽。
	var hit := Control.new()
	hit.size = Vector2(track_w, 48.0)
	hit.position = Vector2(left, cy - 24.0)
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(hit)
	move_child(hit, handle.get_index())   # 排到 handle 前面
	hit.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			apply.call(hit.global_position.x + ev.position.x)
			if on_release.is_valid(): on_release.call()
		elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			apply.call(hit.global_position.x + ev.position.x))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 命中交给 hit, 轨道只负责显示
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _circle(r: float, col: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(r * 2.0, r * 2.0)
	c.size = Vector2(r * 2.0, r * 2.0)
	var draw := func():
		c.draw_circle(Vector2(r, r), r, col)
	c.draw.connect(draw)
	return c


# ── 按钮: btn-frame.png 整图拉伸 260×50 + 文字描边 + hover/press 动画 ──
func _text_button(cx: float, cy: float, label: String, cb: Callable) -> Label:
	var cont := Control.new()
	cont.size = Vector2(260, 50)
	cont.pivot_offset = Vector2(130, 25)
	cont.position = Vector2(cx - 130.0, cy - 25.0)
	add_child(cont)

	var frame := TextureRect.new()
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = Vector2(260, 50)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://assets/sprites/menu/btn-frame.png"):
		frame.texture = load("res://assets/sprites/menu/btn-frame.png")
	cont.add_child(frame)

	# 文字 18px #3a1f00 stroke #ffe4a0 厚2, 居中
	var txt := _stroked_label(label, 18, "#3a1f00", "#ffe4a0", 2)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.size = Vector2(260, 50)
	txt.position = Vector2(0, -2)
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cont.add_child(txt)

	var pressed_tex := "res://assets/sprites/menu/btn-frame-pressed.png"
	# hover scale→1.05 100ms
	frame.mouse_entered.connect(func():
		var tw := create_tween()
		tw.tween_property(cont, "scale", Vector2(1.05, 1.05), 0.1))
	frame.mouse_exited.connect(func():
		var tw := create_tween()
		tw.tween_property(cont, "scale", Vector2(1, 1), 0.1)
		if ResourceLoader.exists("res://assets/sprites/menu/btn-frame.png"):
			frame.texture = load("res://assets/sprites/menu/btn-frame.png"))
	frame.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if ResourceLoader.exists(pressed_tex):
				frame.texture = load(pressed_tex)
			# press scale→0.96 60ms yoyo
			var tw := create_tween()
			tw.tween_property(cont, "scale", Vector2(0.96, 0.96), 0.06)
			tw.tween_property(cont, "scale", Vector2(1, 1), 0.06)
			## ★2026-08-21: 原来接的是 `get_tree().create_timer()` —— 树级计时器**活过场景释放**,
			##   而 cb 捕获了本场景/场景里的节点 ⇒ 场景被释放后它照响, 报
			##   `Lambda capture at index 0 was freed`(报错在【绑定捕获】那一刻, 函数体没执行,
			##   所以在 cb 里加任何 is_instance_valid 都救不了)。改成挂自己身上的 Timer 子节点。
			var _dt := Timer.new()
			_dt.one_shot = true
			_dt.wait_time = 0.1
			add_child(_dt)
			_dt.start()
			_dt.timeout.connect(cb))
	return txt


func _stroked_label(t: String, size: int, color: String, stroke: String, thick: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(color))
	if thick > 0 and stroke != "":
		l.add_theme_constant_override("outline_size", thick)
		l.add_theme_color_override("font_outline_color", Color(stroke))
	return l


func _place_center(l: Label, cx: float, cy: float) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(400, float(l.get_theme_font_size("font_size")) + 16.0)
	l.position = Vector2(cx - 200.0, cy - l.size.y / 2.0)
	add_child(l)


func _mono_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["monospace", "Consolas", "Courier New"])
	# CJK + emoji 兜底 (SystemFont 在 web/linux 取不到系统字体 → 中文乱码/emoji 豆腐块)
	f.fallbacks = [
		load("res://assets/fonts/NotoSansSC-Regular.otf"),
		load("res://assets/fonts/NotoEmoji-Regular.ttf"),
	]
	return f


## 轻量提示 (1.4s 后淡出)
func _toast(msg: String) -> void:
	var l := _stroked_label(msg, 16, "#06d6a0", "", 0)
	_place_center(l, W / 2.0, 650.0)
	l.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


func _bg() -> void:
	# PoC (index.html menu-bg-active + BootScene:579): 菜单背景 = menu-bg-tile.png 平铺 (512px repeat)
	#   over 深绿底 #1a3a2a, 上叠暗渐变 ::after rgba(8,12,20,.15→.40). 不是 menu-bg.png 废墟图!
	#   1:1 复刻 MainMenuScene._bg(), 与主菜单无缝衔接.
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)   # #1a3a2a 深绿底
	add_child(base)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		# PoC CSS background-size:512px → 把 tile 缩到 512² 再平铺 (图标密度对齐 Phaser)
		tile.texture = PreloadCache.menu_bg_tile_tex()   # 复用缓存512²纹理 (resize只做一次, 消除进场景LANCZOS卡顿)
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 漂移 -512→0 / 25s linear 循环 (1:1 PoC menuBgDrift index.html:79/90, 同MainMenu) — 原静态不动是bug
		var vp := get_viewport_rect().size
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
		if not (GameState != null and GameState.perf_lite):   # 低画质: 不跑常驻背景漂移 tween
			var drift := tile.create_tween().set_loops()
			drift.tween_property(tile, "position", Vector2(0, 0), 25.0).from(Vector2(-512, -512)).set_trans(Tween.TRANS_LINEAR)
	# ::after 暗渐变遮罩 (顶 alpha.15 → 底 .40), 压暗背景
	# 显式设 offsets+colors (别用 set_color/add_point — Gradient 默认 offset1 是白点, 会漏成底部白光)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0.031, 0.047, 0.078, 0.15),
		Color(0.031, 0.047, 0.078, 0.25),
		Color(0.031, 0.047, 0.078, 0.40),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 128
	var ov := TextureRect.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt
	ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)
