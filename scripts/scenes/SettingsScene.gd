extends Control

const TopBar = preload("res://scripts/util/top_bar.gd")
var _top_bar = null

## SettingsScene — 设置 (1:1 PoC SettingsScene.ts): BGM/SFX 音量 + 全屏 + 重置存档.
## Phaser 绝对坐标 (中心原点) → Godot 左上 (position = 中心 - size/2). 视口 1280×720.

const W := 1280.0
const H := 720.0

## ── 竖向流水 (2026-09-29 台账 ④) ──────────────────────────────────────
## ★★为什么不是一串写死的 y: 原来每一块自己写死(账号按钮 192 / 音乐 220 / 音效 330 /
##   全屏 410 / 画质 490 / 调试场 560 / 重置 580~640)。账号行有四行高 ⇒ 那两颗按钮
##   (实测 y 177..209)整个落进音乐条那条 **48px 拖动带**(196..244)里, 重叠 13px ——
##   而拖动带是后建的、画在按钮上面 ⇒ **点按钮下沿会变成拖音量**。
##   写死的坐标之间没有任何东西保证它们不相撞, 而账号行的行数还是**随状态变的**
##   (连接中 / 未绑定 / 已绑定 / 存档冲突 → 一到四行)。
## ★★这个 bug 只有**真玩家**碰得到: 门禁给每个测试 `TURTLE_SUPABASE=" "` ⇒
##   `_acct_on()` 恒假 ⇒ 账号那四行**一次都没建出来**, 所以从 2026-09-22 起
##   没有任何判据看见过它(memory `fb-gate-subject-never-constructed`)。
##   判据 SETTINGS_NO_OVERLAP(`tests/verify_ios_ui.gd`)是拿 `acct_override = 1`
##   把这一屏造出来再穷举两两重叠的。
## ⇒ 现在每一块从**上一块的下沿**算出来: 账号行多一句话, 下面整叠自动让位。
const _FLOW_TOP := 96.0        # TopBar 高 87, 往下留 9
const _GAP_LINE := 4.0         # 同一块里两行之间
const _GAP_BLOCK := 14.0       # 块与块之间
const _SLD_LABEL_GAP := 30.0   # 名牌顶沿到槽中心的距离(原来写死在 _slider 里的那个 30)
const _SLD_HIT_H := 48.0       # 滑条的透明触摸带高(26pt, 见 _slider 末尾那段)
const _ACCT_BTN_H := 34.0      # _small_button 的占位高(设的是 30, 九宫格内边距顶到 32, 留 2)
const _BTN_H := 50.0           # _text_button 的高(见那个函数里的 Vector2(260, 50))

var _perf_btn: Label = null
var _full_btn: Label = null   # 全屏按钮文字 (切换后要同步, 原来没接住 → 切了还写"全屏")


func _ready() -> void:
	_bg()

	## ★顶栏走全项目同一个原语 `TopBar`(2026-09-19·用户「做」)。
	##   规则来自 599 张/146 个触屏游戏枢纽页的逐张实测, 见 top_bar.gd 头注。
	var _sm: Vector4 = SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	_top_bar = TopBar.new(self, {
		## ★★2026-09-28 去掉页名前的 ⚙(理由与图鉴/背包/战绩同, 见 `CodexScene` 那条长注释):
		##   146 款参考的枢纽页顶栏一律是「返回箭头 + 裸页名」, 没有一款给页名挂图标;
		##   而 ⚙ 的字形来自 NotoEmoji, 与这一屏的像素笔触是两套画法。
		"title": "设置",
		"palette": TopBar.DEEP,
		"width": W,
		"safe_left": _sm.x,
		"safe_right": _sm.z,
		## ★★墙上**返回键失效** —— 返回得去的墙不是墙。
		##   ★用**具名方法**不用匿名闭包: 字典字面里放不下多行闭包(语法错),
		##   而且具名之后门禁量得到它接的是谁。
		"on_back": _on_back,
	})

	# ── 从这里开始走【竖向流水】(见文件头 `_FLOW_TOP` 那段) ──
	var y := _FLOW_TOP

	# 账号行 — 标题栏与第一个滑条之间。行数随状态变(一到四行), 所以它自己报下沿
	y = _account_row(y)
	y += _GAP_BLOCK

	# BGM 滑条 — 拖动实时生效; 写盘只在松手时一次 (原来每帧 save() = 拖一下写几十次盘)
	## ★★2026-09-28 文案去"网页/开发者味": 原来是「🎵 BGM 音量」「🔊 音效音量」。
	##   ① **BGM 是开发者黑话** —— 玩家的词是「音乐」。项目里给玩家看的字从不写英文缩写
	##     (「深海币」「出战统领」「糖果罐」), 只有这一处漏了。
	##   ② 「音量」两个字是多余的: 右边就写着 45%, 而它前面是一根音量条 ——
	##     「标签: 值」那套是网页表单的读法, 条自己就说清了它是什么。
	## ★★2026-09-28 去掉 🎵/🔊 两个 emoji —— 它们是**纯装饰**:
	##   每条滑条前面写着「音乐」「音效」、右边就写着百分比, 信息一点不少。
	##   而它们的字形来自回退链第三级 NotoEmoji(矢量描边), 与整屏 3~4px 像素笔触
	##   **同屏两套画法** —— 用户 2026-09-27 点名的「ai 味/网页味」就是这一类。
	##   仓库里没有音乐/音效的像素图标(已 grep: music/sound/audio 全无),
	##   而素材铁律是「不拿语义不符的图顶替」 ⇒ 先只留字, 图标已登进缺口表。
	y = _slider_row(y, "音乐", GameState.bgm_volume,
		func(v): GameState.bgm_volume = v; Audio.bgm_volume = v; Audio.apply_bgm_volume(),   # ★补: 原来只设变量没调 apply → 拖动对正在播的BGM无效(用户2026-07-19"音量键根本没效果")
		func(): GameState.save())
	y += _GAP_BLOCK
	# SFX 滑条 — 松手才试听 + 写盘 (原来拖动中每帧都播音效)
	y = _slider_row(y, "音效", GameState.sfx_volume,
		func(v): GameState.sfx_volume = v; Audio.sfx_volume = v,
		func(): Audio.play_sfx("hit-physical", 1.0); GameState.save())
	y += _GAP_BLOCK

	# 全屏 — PoC 用 ⛶(U+26F6) 做图标, 但打包字体链无此字形(web/linux 豆腐块)且无等义替代 → 只留文字
	_full_btn = _text_button(W / 2.0, y + _BTN_H / 2.0, _fullscreen_label(), _toggle_fullscreen)
	y += _BTN_H + _GAP_BLOCK

	# 低画质模式 — 现在是【真开关】: 关 MSAA + 3D 渲染分辨率 ×0.75 + 停菜单背景漂移; 持久化到存档.
	_perf_btn = _text_button(W / 2.0, y + _BTN_H / 2.0, _perf_label(), _toggle_perf)
	y += _BTN_H + _GAP_BLOCK

	# 🛠 调试场 — 用户 2026-09-17:「调试场可以塞到设置里, 正式上线的不会要调试场」。
	#   原来它钉在主菜单中间那条空档上, 而那块地现在给了「本周赛程条」。
	#   ★gate 原样搬过来: OS.is_debug_build() 在导出 release 模板下为 false ⇒ 正式包玩家看不到。
	#   门禁 verify_menu 也跟着搬(它验的是"调试入口不泄漏给玩家", 不是"这行代码在哪个文件")。
	#   ★正式包里没这个键 ⇒ 下面的重置自动往上收, 不留空洞(原来这里是 580/640 两个写死的数)。
	var dev := OS.is_debug_build() or OS.has_environment("DEVTOOLS")
	if dev:
		_text_button(W / 2.0, y + _BTN_H / 2.0, "🛠 调试场", _open_debug_arena)
		y += _BTN_H + _GAP_BLOCK

	# 重置存档 — ⚠ 破坏性 → 二次确认
	_text_button(W / 2.0, y + _BTN_H / 2.0, "⚠ 重置所有存档", _ask_reset)

	# 底部提示 @ (W/2, H-40)
	## ★★2026-09-28 这一行原来是 **11px 的 #888 灰小字**「设置自动保存」——
	##   网页页脚的标准长相(最小号、纯灰、贴底居中), 而且说的是**系统在做什么**,
	##   不是玩家关心的事。改成 13px 的暖羊皮色 + 描边(和这一屏其它字同一套),
	##   话也换成玩家听得懂的: 他想知道的是「我还要不要点保存」。
	##   (PoC 字面是"到 localStorage" —— 浏览器术语, 那一版就已经去掉了后缀。)
	var hint := _stroked_label("调完就记住了，下次进来还是这样", 13, "#d8c49a", "#2a1b08", 3)
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

	## ★★绑定屏: 页面建完再盖上去。放 `_ready` 末尾而不是开头 ——
	##   开头盖的话底下的控件还没建, 玩家会看到它先出现、页面在后面一块块长出来。
	## ★★★ 2026-09-29 拆墙之后它**不再是开机就立**的: 只有玩家从主菜单那句
	##   非阻塞提示点过来(`open_bind_on_entry`)才立 —— 见 `_maybe_bind_screen`。
	_maybe_bind_screen()


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

## 【门禁注入点】0 = 真实(读后端配置与存档) / 1 = 强制当作「后端开着且邮箱为空」。
##
## ★为什么要它: 门禁给每个测试 `TURTLE_BACKEND=" "`(有意关后端) ⇒ `_SB_ACC.enabled()`
##   恒假 ⇒ 整块账号 UI 与**登录墙**一次都没建出来 ⇒ 那一屏的毛病任何门禁都没看见过。
##   2026-09-27 拿真后端一跑当场 4 条红(默认皮按钮 ×4 / 热区不足 ×4 / 文字相撞 / 圆角盒),
##   而那是**每个新玩家开游戏看到的第一屏**(关不掉的墙)。
##   —— memory `fb-gate-subject-never-constructed`: 判据没错, 被测对象不在场。
##
## ★默认 0 ⇒ **玩家路径一字不动**(与 v0.19.446 的 `clock_override_ts` 同一个模式)。
##
## ★★★ 2026-09-29 拆墙之后它的含义稍微平移了: 拆墙之前「后端开着 + 邮箱为空」
##   **自动就意味着那一屏会立起来**; 拆墙之后不再自动立 ⇒ 如果这个缝只改条件,
##   那三条靠它把绑定屏造出来的门禁(`verify_ui_consistency` 的「登录墙」屏 /
##   `verify_click_targets_alive` / `verify_ios_ui`)就会静默地去量**普通设置页** ——
##   被测对象不在场(memory `fb-gate-subject-never-constructed`)。
##   ⇒ 它现在的意思是「**强制把绑定屏造出来**(并且当作后端开着、邮箱为空)」,
##   它要量的那一屏一直是同一屏。
var acct_override: int = 0


## 【从主菜单过来的请求】true = 这一次进设置页是为了绑定, 直接把绑定屏打开。
##
## ★★为什么是 static: 主菜单那句非阻塞提示要把人送到**另一个场景**去,
##   而绑定屏的代码在这一侧 ⇒ 跨场景传一个布尔。同 `vkb_override_vp` 那个模式。
## ★**读完就清**(一次性): 不清的话以后每次进设置页都会弹绑定屏 ——
##   那就是把刚拆的墙换个地方重建一遍。
static var open_bind_on_entry: bool = false


## 【账号行的节点名前缀】—— `verify_account` ⑤ 靠它量「这一行到底建没建出来」。
##
## ★★为什么要有它: ⑤ 守的需求是「没配后端 ⇒ **整行不显示**(不是显示"离线")」,
##   而它原来的实现是 `not _find_text(s3, "账号：")` —— **拿一个字面量当尺子**。
##   2026-09-28 去掉那个半角/全角冒号(`label: value` 是网页表单的读法)的同一刻,
##   那条断言就变成**恒真**: 找不到是因为词改了, 不是因为行没建。
##   ⇒ 把判据从「屏幕上有没有这个词」平移到「这一族节点在不在树上」。
## ★**常量在产品这边**, 门禁 `preload` 它来读 —— 门禁自己抄一份字符串,
##   就是 memory `fb-hand-rolled-copies-drift` 那条"抄一次永远落后一次"。
const ACCT_ROW_PREFIX := "AcctRow"


## 账号功能开着吗。**判据只从这一处取** —— 两处各判一份必然漂。
func _acct_on() -> bool:
	return true if acct_override == 1 else _SB_ACC.enabled()


## 当前绑的邮箱。注入态下恒空 = 「还没绑」, 那才是墙会弹出来的条件。
func _acct_mail() -> String:
	return "" if acct_override == 1 else str(GameState.account_email)


## 返回这一块的**下沿** —— 行数随状态变(连接中/未绑定/已绑定/存档冲突 → 一到四行),
## 所以下面那一叠的位置只能由它报出来, 不能各自写死(见文件头 `_FLOW_TOP` 那段)。
func _account_row(top: float) -> float:
	if not _acct_on():
		return top                               # 没配后端 = 有意关掉, 什么都不显示
	var aid := str(GameState.account_id)
	var mail := _acct_mail()
	var head := ""
	var sub := ""
	if aid == "":
		## 配了后端但还没拿到身份(刚开机还在登, 或登不上)。不说"失败" —— 说不准。
		head = "账号 · 连接中…"
		sub = ""
	elif _SB_ACC.session_lost():
		## D-3c: 绑了邮箱的号登录失效了。**不会**自动换成新匿名号(那是静默换身份),
		##   只能用邮箱把同一个号取回来 —— 所以这里要明说该点哪个按钮。
		head = "账号 · %s" % mail
		sub = "⚠ 登录已失效 —— 点「用邮箱取回」重新登录"
	elif _SB_ACC.save_conflict():
		## D-8: 两台设备交替玩 ⇒ 云端版本和这台对不上。**不自动选**, 等玩家二选一。
		head = "账号 · %s" % mail
		sub = "⚠ 云端存档和这台设备的不一样（可能在别的设备上玩过）"
	elif mail != "":
		## ★D-8 之后这句才是真的: 绑了邮箱的号, 进度会同步到云端(verify_save_sync ⑦ 守着)。
		head = "账号 · %s" % mail
		sub = "已绑定 · 换设备可用这个邮箱取回账号和进度"
	else:
		## ★只显前 8 位: 完整 uuid 36 个字符, 在 1280 宽里既放不下也没用 ——
		##   它的用途是「报问题时能对上号」, 前 8 位足够。
		head = "账号 · 匿名 %s" % aid.substr(0, 8)
		sub = "⚠ 未绑定邮箱 —— 换设备后账号和进度都找不回来"
	## ★★2026-09-28 这一族**必须有名字**(`ACCT_ROW_PREFIX`)。
	##   由来: `verify_account` ⑤ 守的是「没配后端 ⇒ 整行不显示」, 但它原来的实现是
	##   `not _find_text(s3, "账号：")` —— **拿字面量当尺子**。
	##   于是我把「账号：」的冒号去掉(那是 `label: value` 的网页表单读法)的同一刻,
	##   那条断言就**恒真**了: 找不到是因为这个词没了, 不是因为行没建
	##   (memory `fb-gate-tautological-when-it-spans-a-frame` 同族: 判据不再卡住那个形状)。
	##   ⇒ 判据平移到**行为**: 这一族节点在不在树上。文案以后怎么改都不影响它。
	var y := top
	var a := _stroked_label(head, 15, "#cfe3ff", "", 0)
	y = _place_flow(a, y)
	a.name = ACCT_ROW_PREFIX + "Head"
	if sub != "":
		var col := "#ffb454" if mail == "" else "#8fa6bd"    # 未绑定用警示橙, 已绑定用灰
		var b := _stroked_label(sub, 12, col, "", 0)
		y = _place_flow(b, y + _GAP_LINE)
		b.name = ACCT_ROW_PREFIX + "Sub"
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
	y = _place_flow(note, y + _GAP_LINE)
	note.name = ACCT_ROW_PREFIX + "Note"
	## ★D-3c 补上 v0.19.423 漏掉的入口: 那一版只有「绑定邮箱」,
	##   **取回流程写了但点不到** —— 新手机上根本没法用邮箱把号拿回来。
	##   `verify_session_refresh` 没有覆盖到 UI, 这条由 `verify_account` ④ 走真入口验。
	## ★★这两颗按钮的 y **原来写死成 192**, 而那正好落在音乐条的 48px 拖动带里(见文件头那段)。
	##   现在钉在账号文字的下沿之后 —— 账号行多一句话, 它自己往下走。
	var by := y + _GAP_LINE + _ACCT_BTN_H / 2.0
	if aid != "" and _SB_ACC.save_conflict():
		_small_button(W / 2.0 - 80.0, by, "处理存档冲突", _open_conflict_dialog).name = \
			ACCT_ROW_PREFIX + "BtnConflict"
	elif aid != "":
		_small_button(W / 2.0 - 80.0, by,
			("换个邮箱" if mail != "" else "绑定邮箱"),
			func(): _open_email_dialog(_SB_ACC.FLOW_BIND)).name = ACCT_ROW_PREFIX + "BtnBind"
	_small_button((W / 2.0 + 80.0) if aid != "" else W / 2.0, by, "用邮箱取回",
		func(): _open_email_dialog(_SB_ACC.FLOW_RECOVER)).name = ACCT_ROW_PREFIX + "BtnRecover"
	return by + _ACCT_BTN_H / 2.0


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
	## ★★2026-09-28 与重置框一起换成金属九宫格(理由见 `_ask_reset` 里那段)。
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffb454")
	sb.set_border_width_all(3); sb.set_corner_radius_all(0)
	var ctex := UISkin.nine("panel-frame.png", 20, sb)
	if ctex is StyleBoxTexture:
		(ctex as StyleBoxTexture).modulate_color = UISkin.tint_of(Color("#ffb454"))
	box.add_theme_stylebox_override("panel", ctex)
	box.position = Vector2(W / 2.0 - 280, H / 2.0 - 170); box.size = Vector2(560, 340)
	dim.add_child(box)

	var ttl := Label.new()
	ttl.text = "两边的存档对不上"
	ttl.add_theme_font_size_override("font_size", 24)
	ttl.add_theme_color_override("font_color", Color("#ffb454"))
	ttl.position = Vector2(0, 18); ttl.size = Vector2(560, 32)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)

	var msg := Label.new()
	msg.text = "云端的存档被另一台设备更新过，和这台设备上的不一样。留哪一份？"
	msg.add_theme_font_size_override("font_size", 14)
	msg.add_theme_color_override("font_color", Color("#c9d6e2"))
	msg.position = Vector2(30, 60)
	## ★中文按字断行(理由见 `_ask_reset` 的 msg)。
	msg.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(msg)
	msg.size = Vector2(500, 44)     # ★入树后再设一次, 写在 add_child 前的那次不一定算数

	var opts := [
		["用云端那份", "这台设备上次同步之后的进度会被换掉\n（换之前先在本机备份一份）",
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
		b.position = Vector2(x, 110); b.size = Vector2(230, 50)
		## ★★原来是裸 `Button.new()` = Godot 默认皮(圆角灰板)。换皮走共享层 `UISkin`。
		UISkin.button(b)
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
		cost.position = Vector2(x, 168)
		cost.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(cost)
		cost.size = Vector2(230, 64)

	var close := Button.new()
	close.text = "先不选"
	close.add_theme_font_size_override("font_size", 15)
	## ★160x40 短边 40 < 81 触摸线; 拉成 240x48 的长条(宽的那边过 200, 热区判据也放行)。
	close.position = Vector2(160, 262); close.size = Vector2(240, 48)
	UISkin.button(close)
	close.pressed.connect(func(): dim.queue_free(); _confirm_layer = null)
	box.add_child(close)


## 【输入框换皮】(2026-09-28)
##
## ★由来: 默认的 `LineEdit` 是**圆角灰盒 + 细边**, 那就是网页表单字段的长相,
##   而这三个框(昵称/邮箱/验证码)正长在**每个新玩家看到的第一屏**(关不掉的登录墙)上。
##   这一屏 2026-09-27 已经把对话框和按钮都换成金属件了, 只剩输入框还是网页的。
##
## ★用哪张图是**量出来选的**, 不是挑好看的: `bar-frame.png` 源图 96x24,
##   本来就是给横条画的(战斗血条/龟能条用的同一张), 中间是真黑深槽 ——
##   而"输入框"在像素 UI 里本来就该是个凹槽。
##   边距从贴图量: 左右边带 7px、上下 4px ⇒ 取 8 / 5(各留 1px 把斜切角整个盖进去);
##   8+8=16 < 440、5+5=10 < 44, 装得下(`UISkin` 铁律③: 边距之和必须小于目标尺寸)。
##
## ★`content_margin` 必须自己给: `StyleBoxTexture` 不像 `StyleBoxFlat` 那样自带内边距,
##   不给的话文字会**压在左边那道金属沿上**(本仓「文字压边带」判据抓的就是这一类)。
func _skin_edit(e: LineEdit) -> void:
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color("#0e1726")
	fb.border_color = Color("#3c5570")
	fb.set_border_width_all(2)
	fb.set_corner_radius_all(0)          # ★退回的那一份也不许带圆角
	for slot in ["normal", "focus", "read_only"]:
		## ★★这里**不能**开 `tile`(TILE_FIT) —— 试过, 实拍更糟: 96→440 要铺 4~5 份,
		##   每一份的左右边沿都在黑槽里留一道竖线, 四个输入框看着像四张带列线的表格。
		##   `bar-frame` 的中段本来就是一块匀色深槽, **拉伸不掉细节**(没细节可掉),
		##   会被抻平的只有上下沿那两条光带, 而那两条本来就是平的。
		##   ⇒ 「拉伸 vs 平铺」看中段有没有图案, 不看倍数。
		var sb := UISkin.nine("bar-frame.png", 8, fb)
		if sb is StyleBoxTexture:
			var stx := sb as StyleBoxTexture
			stx.set_texture_margin(SIDE_TOP, 5)
			stx.set_texture_margin(SIDE_BOTTOM, 5)
			## 聚焦时把整块槽提亮一档 —— 一张中性贴图 modulate 出所有状态,
			## 不另做一张图(`UISkin` 铁律②)。
			## ★常态压到 0.7 档: 原样(白)出来的金属沿**比对话框自己的框还亮**
			##   (框走的是 `UISkin.tint_of(#5aa0ff)` ≈ 0.8/0.89/1.0), 实拍三个输入框
			##   抢走了整块墙的视线。边框比内容响 = 又一种"表单"长相。
			stx.modulate_color = Color(1.02, 1.06, 1.0) if slot == "focus" else Color(0.66, 0.73, 0.84)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		e.add_theme_stylebox_override(slot, sb)
	e.add_theme_color_override("font_color", Color("#e8f0ff"))
	e.add_theme_color_override("font_placeholder_color", Color("#7d93ac"))
	e.add_theme_color_override("caret_color", Color("#ffd93d"))


## 紧凑按钮 —— 账号行下面那一个。`_text_button` 是 260×50 的木框大按钮,
## 塞进 128~192 这段窄地里会压到下面的 BGM 滑条。
func _small_button(cx: float, cy: float, label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 14)
	b.size = Vector2(150, 30)
	b.position = Vector2(cx - 75.0, cy - 15.0)
	## ★★换皮走共享层 `UISkin`, 不在这里手写 StyleBox —— 抄一份就永远落后
	##   (memory `fb-hand-rolled-copies-drift`)。`UISkin.button` 自己按真实尺寸挑框:
	##   短边 ≥56 且面积 ≥5000 用 `frame-rect`(源图 666x161), 否则 `chip-frame`。
	## ★2026-09-27 之前这几个按钮是**裸 `Button.new()`** ⇒ Godot 默认皮(圆角灰板),
	##   而它们正长在**每个新玩家看到的第一屏**(关不掉的登录墙)上。
	UISkin.button(b)
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
## 对话框那块框本体。★位置**不在建的时候写死**, 由 `_email_relayout()` 每帧算
##   (居中于真实视口 + 给虚拟键盘让位) —— 见那个函数的头注。
var _email_box: Panel = null
## 【门禁注入点】虚拟键盘高度(**视口单位**)。< 0 = 真实读 `DisplayServer`。
##
## ★为什么必须有它: 无头 `DisplayServer.has_feature(FEATURE_VIRTUAL_KEYBOARD)` **实测为 false**
##   (探针 `tests/_probe_ds_vkb.gd`), `window_get_size()` 还是 `(0,0)` ⇒ 键盘让位那一支
##   在门禁里**永远走不到**, 判据就是空检查(memory `fb-gate-subject-never-constructed`)。
## ★默认 -1 ⇒ **玩家路径一字不动**(与 `acct_override` / `clock_override_ts` 同一个模式)。
static var vkb_override_vp: float = -1.0
## 键盘让位时, 可点元素与键盘上沿(以及与屏幕上沿)之间留的余量。
const _KB_GAP := 8.0
## 这一次弹出来的是**盖满全屏的绑定屏**还是设置页里那个小对话框。
## ★两者在成功之后该做的事不一样: 绑定屏要**放人进游戏**(他本来就是从
##   主菜单过来的), 设置页里自己点开的只要染绿等他关。
## ★★名字从 `_email_wall` 改成这个(2026-09-29 拆墙): 名字里再带「墙」就是指错路了,
##   它现在分的是「盖满全屏 / 嵌在设置页里」, 不是「关得掉 / 关不掉」。
var _email_standalone: bool = false
var _email_edit: LineEdit = null
var _code_edit: LineEdit = null
var _nick_edit: LineEdit = null
var _email_status: Label = null
var _email_send_btn: Button = null
var _email_ok_btn: Button = null
## 「回上一步改邮箱」—— 第二步唯一的退路。★没有它这堵墙是**死局**:
##   邮箱打错一个字母, 码永远收不到, 而墙关不掉 ⇒ 只能杀进程。
var _email_back_btn: Button = null
## 说明文字(第一步那段长的 / 第二步那一行)。
var _email_why: Label = null
var _email_why2: Label = null
## 靶子上方那一行小字(第一步 = 昵称规则; 第二步 = 码发到哪个邮箱了)。
var _email_hint: Label = null
## 版本号那一行(墙上才有)。★位置跟着框底走, 不写死。
var _email_ver: Label = null

# ─── 44pt 触摸线重排: 竖向网格 (2026-09-28 候选 A) ──────────────────
##
## ══════════════════════════════════════════════════════════════════════
##  为什么非得**分两步** —— 这不是版式偏好, 是算出来无解
## ══════════════════════════════════════════════════════════════════════
## 上一版(v0.19.470)的实测剖面(探针 `tests/_probe_wall_vprofile.gd`):
##   5 个可点元素短边 42/44/46/44/46 px = **22.8~25.0pt**, 全部低于 44pt 触摸线;
##   相邻间隙只有 **4 / 6 / 12 / 6 px** ⇒ 瞄「发验证码」高 7px 就点进邮箱框,
##   而那一下正好弹出键盘 ⇒ 玩家看到的就是「点了没反应」。
##
## 把 5 个都撑到 81px(= 44pt, 本仓 `TOUCH_MIN`)、间隙 12px, 需要竖向
##   5×81 + 4×12 = **453px**。
## 而**键盘让位**那道公式(`_email_relayout`)要同时成立两件事 ——
## 「一个可点元素都不在键盘底下」+「一个可点元素都不许顶出屏幕上沿」——
## 留给可点元素的竖向净空只有
##   `av.y - 键盘高 - 2×_KB_GAP`
## 720 高的视口上实测(同一份探针):
##   · 键盘 41.5%(iPhone 横屏 ASCII) ⇒ 上限 **405px**
##   · 键盘 52.0%(中文候选条)        ⇒ 上限 **330px**
##   · 键盘 58.0%(窄屏+候选条 最坏)   ⇒ 上限 **286px**
## ⇒ 453 > 405 > 330 > 286: **一屏五行, 连最宽松的那一档都装不下。**
##   四行(4×81+3×12 = 360)也只过得了 41.5% 那一档, 中文键盘就破。
##   **三行 = 3×81 + 2×12 = 267 ≤ 286**, 三档全过 —— 所以一步最多三行。
##
## ⇒ 流程切成两步: ①昵称/邮箱/发验证码 ②验证码/确认/回上一步改邮箱。
##   两步都恰好三行, 框高两步相同(不跳)。
##
## ★数字的依据分两类, 别混:
##   · `_W_ROW_H = 81` —— **不是我拍的**: 本仓 `TOUCH_MIN` 就是 81px(= iOS HIG 44pt),
##     `top_bar.gd` / `verify_ui_consistency` 一直用它。
##   · `_W_ROW_GAP = 21` —— **2026-09-29 由上面那道除法反解出来的**, 不再是拍的。
##     参考真值(`python tools/login_screen_audit.py thresholds`, 13 屏逐像素):
##     最小相邻间隙中位 **23.3pt(≈43px)**, 地板 Hungry Shark **8.2pt** / Free Fire 9.2pt。
##     原来的 12px = 6.5pt **低于参考里任何一屏**。
##     往上抬的天花板就是最坏那一档键盘:  3×81 + 2×gap ≤ 286.4  ⇒  gap ≤ 21.7
##     ⇒ 取 **21px = 11.4pt**(留 1.4px 余量)。
##     ★★**中位 43px 在「一步三行 44pt」的前提下算不出来**: 3×81 + 2×43 = 329 > 286.4。
##     要到中位只能一步两行, 那就得分三步 —— 而参考的「分几步」中位数是 **1**,
##     我们已经是 2 了。抬间隙 ⇔ 多一步, 两头都是参考在管的指标 ⇒ 这一格到此为止。
##   · `_W_ROWS = 3` —— **量出来的**, 就是上面那道除法。
## 墙背后的游戏美术。★抽到外面了(`RefCounted` + 构造注入, 拆法照
##   `scripts/scenes/battle/dmg_stats_panel.gd`): 它不在任何每帧链上, 纯摆设,
##   素材路径与摆位几何都在那边(`WALL_ART_TEX` / `place_logo`)。
const _WALL_ART := preload("res://scripts/scenes/settings/login_wall_art.gd")
const _W_PAD := 40.0            ## 框内左右边距(沿用旧值)
const _W_CW := 440.0            ## 内容宽 = 520 - 2×40
const _W_ROW_H := 81.0          ## 一行靶子的高 = 44pt
const _W_ROW_GAP := 21.0        ## 相邻靶子之间的空(由净空除法反解, 见上)
const _W_ROW_Y0 := 158.0        ## 第一行靶子的顶(标题+说明+小字之下)
const _W_ROWS := 3              ## 一步最多三行 —— 见上面那道除法
## 副按钮(「关闭」/「换一个」)与主控件并排时的宽度切分: 260 + 21 + 159 = 440。
## ★并排**不占新的一行** ⇒ band 不变, 键盘让位那道判据照样成立。
## ★横向的空**单立一个常量**: 竖向那道净空除法只管竖向,
##   两边共用一个常量的话, 以后竖向被键盘逼回去会把横向也一起拽回去。
const _W_COL_GAP := 21.0
const _W_MAIN_W := 260.0
## ★算出来而不是写死: 改了 `_W_COL_GAP` 而忘了改它, 并排那一行就会戳出框外。
const _W_SIDE_W := _W_CW - _W_MAIN_W - _W_COL_GAP
const _W_SIDE_X := _W_PAD + _W_MAIN_W + _W_COL_GAP

## 现在停在第几步(1 = 填昵称/邮箱, 2 = 填验证码)。
var _email_step: int = 1
## 每一步各自的**行控件**(按从上到下的顺序), 外加只在那一步露脸的说明。
var _email_rows1: Array = []
var _email_rows2: Array = []
## 第一步那一行小字(第二步换成「验证码已发到 …」)。
var _email_hint1: String = ""
## 「关闭」—— 只有玩家自己点开的对话框才有。**与主按钮并排**, 不占新的一行。
var _email_close_btn: Button = null
## 某一行旁边的**副按钮**: {行控件 → 副按钮}。现在只有昵称那一行的「换一个」。
## ★做成表而不是再加一个成员: 下一个并排需求就不用再抄一份摆位代码。
## ★★键是 **Control 对象**(按引用哈希), 不是 Dictionary —— CLAUDE.md §3.2 禁的是
##   拿**字典**当键(递归哈希会卡死), 节点对象当键是安全的。
var _email_side: Dictionary = {}
## 墙背后那张游戏的标。★只墙上有; 位置跟着框走(见 `_email_relayout`)。
var _email_logo: TextureRect = null


## 框里的一行说明文字。★三处(第一步整段 / 第二步那一句 / 小字)形状一模一样,
## 抄三遍必然漂 —— 见 memory `fb-hand-rolled-copies-drift`。
## ★★`size` 必须**入树之后**再设一次: 写在 `add_child` 之前会被入树时重算掉
##   (2026-09-27 实测正文变成 586 宽、戳出 520 的框外左右各 33px)。
## ★`ARBITRARY` 不是 `WORD_SMART`: 中文本来就按字断行, `WORD_SMART` 在这段中文里
##   找不到断点, 于是 Label 的最小宽被撑成 586。
func _wall_text(box: Control, txt: String, fs: int, col: String, y: float, h: float) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(col))
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	## ★★★**入树前后各设一次**, 两次都不能省 —— 2026-09-28 实测:
	##   只在入树**后**设 ⇒ 控件入树那一刻宽是 0, 自动换行按 1 个字一行算,
	##   最小高被算成 **1400px**(35 行), 而 `size.y` 会被最小高钳住 ⇒ 说明文字
	##   把下面整叠靶子全压在身下(剖面探针当场打出 `高 1400`)。
	##   只在入树**前**设 ⇒ 入树时尺寸被重算掉(2026-09-27 那条: 正文变 586 宽戳出框外)。
	l.position = Vector2(30, y)
	l.size = Vector2(460, h)
	box.add_child(l)
	l.position = Vector2(30, y)
	l.size = Vector2(460, h)
	return l


## 框里的一个整行按钮。★尺寸要在 `UISkin.button` **之前**给 ——
##   它按 `b.size` 挑框(短边 ≥56 且面积 ≥5000 才用 `frame-rect`, 否则 `chip-frame`),
##   而 (0,0) 的按钮会被判成小签牌、拿到一张 48x24 的贴图拉 9 倍。
## ★真正的 y / 宽由 `_email_set_step` 统一给(两步共用同一份网格)。
func _wall_btn(box: Control, label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 15)
	b.size = Vector2(_W_CW, _W_ROW_H)
	b.pressed.connect(cb)
	UISkin.button(b)
	box.add_child(b)
	b.size = Vector2(_W_CW, _W_ROW_H)
	return b


## 换步: 摆位 + 显隐。**全框只有这一处摆行控件的 y** —— 两步各写一份必然漂。
##
## ★为什么要有"步": 见 `_W_ROW_*` 那段的除法 —— 五行 44pt 靶子(453px)装不进
##   键盘让位留下的净空(最宽松一档 405px), 三行(267px)三档全过。
## ★门禁也调这个函数把墙推到第二步(`verify_login_wall` ⑥), 用的是**产品自己的入口**,
##   不另开测试后门(memory `fb-gate-must-measure-requirement-not-my-hook`)。
func _email_set_step(step: int) -> void:
	if _email_box == null or not is_instance_valid(_email_box):
		return
	_email_step = 2 if step == 2 else 1
	var rows: Array = _email_rows2 if _email_step == 2 else _email_rows1
	for c in (_email_rows1 if _email_step == 2 else _email_rows2):
		(c as Control).visible = false
		## ★并排的副按钮跟着它那一行走 —— 漏掉这两行, 「换一个」就会在
		##   第二步飘在验证码框旁边(而那一步没名字可换), 而且会被
		##   `_email_ctl_band` 算进 band 里。
		var h0 = _email_side.get(c)
		if h0 != null and is_instance_valid(h0):
			(h0 as Control).visible = false
	var last: int = rows.size() - 1
	for i in range(rows.size()):
		var c := rows[i] as Control
		c.visible = true
		## 这一行要是得给副按钮(「换一个」)或「关闭」让地方, 就让出
		## 260 + `_W_COL_GAP`; 否则整行 440。
		var side = _email_side.get(c)
		var has_side: bool = side != null and is_instance_valid(side)
		var w: float = _W_MAIN_W if (has_side or (i == last and _email_close_btn != null)) else _W_CW
		c.position = Vector2(_W_PAD, _W_ROW_Y0 + float(i) * (_W_ROW_H + _W_ROW_GAP))
		c.size = Vector2(w, _W_ROW_H)
		if has_side:
			(side as Control).visible = true
			(side as Control).position = Vector2(_W_SIDE_X, c.position.y)
			(side as Control).size = Vector2(_W_SIDE_W, _W_ROW_H)
	var bot: float = _W_ROW_Y0 + float(maxi(last, 0)) * (_W_ROW_H + _W_ROW_GAP) + _W_ROW_H
	if _email_close_btn != null and is_instance_valid(_email_close_btn):
		_email_close_btn.position = Vector2(_W_SIDE_X, bot - _W_ROW_H)
		_email_close_btn.size = Vector2(_W_SIDE_W, _W_ROW_H)
	## 状态行紧跟**这一步的**最后一行 —— 取回流程第一步只有两行,
	## 写死成三行的位置就会在中间留一个 93px 的窟窿。
	if _email_status != null and is_instance_valid(_email_status):
		_email_status.position = Vector2(30, bot + 8.0)
		_email_status.size = Vector2(460, 48)
	if _email_why != null and is_instance_valid(_email_why):
		_email_why.visible = _email_step == 1
	if _email_why2 != null and is_instance_valid(_email_why2):
		_email_why2.visible = _email_step == 2
	if _email_hint != null and is_instance_valid(_email_hint):
		## ★第二步这一行**必须写出邮箱** —— 玩家在这一屏唯一要判断的事就是
		##   "码到底发去哪了", 而他上一屏刚打完那个地址、现在看不见了。
		## ★不能只靠状态行: 状态行是**会被覆盖的**(验错一次就变成「码不对」),
		##   地址一没了他就无从判断是不是自己打错了邮箱。
		## ★地址空着(理论上到不了第二步)也要有话说, 不许留一句「已发到 」的断句。
		if _email_step == 1:
			_email_hint.text = _email_hint1
		else:
			var _to: String = str(_SB_ACC.email_pending()).strip_edges()
			if _to == "" and _email_edit != null and is_instance_valid(_email_edit):
				_to = str(_email_edit.text).strip_edges()
			_email_hint.text = ("验证码已发到 %s" % _to) if _to != "" else "把邮件里那串数字填进来"
	_email_relayout()

## ★绑定屏与「设置里主动绑定」共用这一个对话框 —— 另做一份就要把昵称那一行
##   和验证码状态机抄第二遍, 而抄一次永远落后一次。
## ★★两个开关各管一件, **不许再用一个布尔兼职两件事**(拆墙之前就是那样):
##   · `dismissible` —— 有没有「关闭」。**现在永远是 true**(墙拆了),
##     它留着只为了 `WALL_BLOCKS` 翻回来时能当场复原(反向验证走得通)。
##   · `standalone` —— 这一屏**就是绑定屏本身**(背后没别的内容):
##     铺游戏美术 + 印版本号 + 藏返回箭头 + 绑成功后送回主菜单。
## 返回主菜单。★★**真上墙时失效** —— 判据与开墙同一处(`login_wall_on`),
##   而那一处 2026-09-29 起恒假 ⇒ 这一道现在从不生效, 留着作反向验证的配件。
func _on_back() -> void:
	if _P2C.login_wall_on(_acct_on(), _acct_mail()):
		return
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


## 进设置页时该不该把**绑定屏**盖上去。
##
## ★★★ 2026-09-29 拆墙: 原来这里的判据是「`login_wall_on` 为真就盖」,
##   而主菜单会把没绑邮箱的人**强行送进来** ⇒ 那就是墙。现在三个入口:
##     ① `open_bind_on_entry` —— 玩家自己点了主菜单那句「进度没备份」(唯一的玩家路径)
##     ② `acct_override == 1` —— 门禁注入点(把这一屏造出来给它量, 见那个变量的注释)
##     ③ `login_wall_on()` —— **恒假**。留着只为一件事: 翻回 `WALL_BLOCKS` 时
##        这一条把墙原封不动地恢复(包括不给「关闭」), 门禁那条反向验证才走得通。
## ★**关不关得掉**只看 ③: 真上墙时 `dismissible = false`, 其余情况都给「关闭」。
func _maybe_bind_screen() -> void:
	var blocking: bool = _P2C.login_wall_on(_acct_on(), _acct_mail())
	var asked: bool = open_bind_on_entry or acct_override == 1
	## ★读完就清(一次性) —— 不清就是把刚拆的墙换个地方重建一遍。
	open_bind_on_entry = false
	if not (blocking or asked):
		return
	## ★★把返回箭头**藏掉** —— 实拍拓出来的: 顶栏在更高的 CanvasLayer 上,
	##   遮罩盖不住它 ⇒ 它看着能按、按下去却没反应。
	##   本仓原则: **「点了没反应」比「按钮是灰的」糟得多**。
	##   ★拆墙之后它**仍然要藏**: 这一屏盖满全屏, 一个浮在美术上的顶栏箭头
	##   既不好看也多余 —— 现在屏上有「关闭」, 出口不靠它。
	if _top_bar != null and _top_bar.back_btn != null:
		_top_bar.back_btn.visible = false
	## ★★把绑定屏**背后**的设置页藏掉。遮罩只有 0.65 ⇒ 底下的音量百分比「45%」
	##   从半透里浮上来, 正好压在正文上
	##   (`verify_ui_consistency` 的「两段文字压在一起」当场抓到)。
	## ★只藏 `self` 下的 Control(顶栏在更高的 CanvasLayer 上, 上面单独藏了它的返回键);
	##   遮罩与对话框是**这一行之后**才建的 ⇒ 不会被一起藏掉。
	## ★★★**记下藏了哪几个**(不是关的时候 `visible = true` 一抹) ——
	##   拆墙之后这一屏是**关得掉**的, 关掉之后得把设置页原样交还给玩家;
	##   而设置页上本来就可能有有意隐掉的东西, 一抹就把它们也翻出来了。
	_hidden_by_screen.clear()
	for ch in get_children():
		if ch is Control and (ch as Control).visible:
			_hidden_by_screen.append(ch)
			(ch as Control).visible = false
	_open_email_dialog(_SB_ACC.FLOW_BIND, not blocking, true)


## 被 `_maybe_bind_screen` 藏起来的设置页控件 —— 关掉绑定屏时原样交还。
var _hidden_by_screen: Array = []


func _open_email_dialog(flow: String, dismissible: bool = true,
		standalone: bool = false) -> void:
	if _email_layer != null and is_instance_valid(_email_layer):
		return
	_email_standalone = standalone
	_SB_ACC.reset_email_flow()
	_wall_reset_state()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_email_layer = dim
	## ★★★这一屏盖满全屏, 而它原来**一只龟都看不见**。
	##   (★ 2026-09-29 拆墙之后它不再是「每个新玩家看到的第一屏」—— 第一屏是主菜单;
	##    这一屏只在玩家点了「进度没备份」之后才出现。美术的理由不变: 它仍然盖满整屏。)
	##   探针 `tests/_probe_wall_look.gd` 实测: `_maybe_bind_screen`(当时叫 `_maybe_login_wall`) 把 self 下的
	##   Control **整批藏掉**, 连 `_bg()` 建的底色/平铺砖/渐变一起藏 
	##   (探针打出来那三个节点都是 visible=false) ⇒ 玩家看到的是一块深蓝面板
	##   压在**自动载入的 `PersistentBg` 那张平铺花砖**上 —— 全屏没有任何
	##   属于这个游戏的东西。
	## ★参考里 Arknights / Free Fire / Disney Mirrorverse / Hungry Shark 的账号控件
	##   **直接浮在游戏美术上**, 没有对话框、没有纯黑遮罩。
	## ★★只盖满全屏那一屏铺: 玩家自己在设置里点开的那个对话框背后本来就是设置页,
	##   再铺一层美术只是把他正在看的东西盖掉。
	if standalone:
		_email_logo = _WALL_ART.build(dim)

	var box := _wall_make_box(dim, standalone)
	_wall_title(box, flow, standalone)
	_wall_explain(box, flow, standalone)
	_wall_build_step1(box, flow)
	_wall_build_step2(box, flow)
	_wall_build_footer(box, dim, dismissible, standalone)

	## ★★所有行控件的 y / 宽 / 显隐都在 `_email_set_step` 里一处算出来。
	##   这一行必须在**全部 add_child 之后** —— `ctrl.size = X` 写在 add_child 前不生效。
	_email_set_step(1)
	## ★用 Timer 子节点轮询, **不用 `create_timer` 闭包** ——
	##   树级计时器接闭包会活过场景释放(本仓有一条门禁专门守这个)。
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	t.timeout.connect(_email_poll)
	dim.add_child(t)
	_email_poll()


## 重开一次就要**清干净**。★抽成一个函数而不是就地写:
##   新加一个 `_email_*` 成员忘了在这里清, 表现是「第二次打开时摆一批死对象」,
##   而它只在**关了再开**这个场景里发作(memory `fb-restart-is-a-separate-scenario`)。
func _wall_reset_state() -> void:
	## ★★重开一次就要**清干净**: 这几个是成员变量, 不清的话第二次打开
	##   `_email_rows*` 里还躺着上一次那批已经 `queue_free` 的节点
	##   ⇒ `_email_set_step` 去摆一批死对象。(「关了再开」是另一个场景, 要单列 —— memory
	##   `fb-restart-is-a-separate-scenario`。)
	_email_step = 1
	_email_rows1 = []
	_email_rows2 = []
	_email_hint1 = ""
	_email_close_btn = null
	_email_back_btn = null
	_email_why = null
	_email_why2 = null
	_email_hint = null
	_email_ver = null
	_nick_edit = null
	_email_side = {}
	_email_logo = null


## 建框: 金属九宫格 + 从网格算出来的高。★返回那块框, 并已经入树·已经摆好位。
func _wall_make_box(dim: Control, standalone: bool) -> Panel:
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	## ★★2026-09-27 换**金属九宫格框**(和背包/图鉴/战绩/排行榜同一张 panel-frame)。
	##   这块 520x堆高, 远超 `UISkin.MIN_FRAME_PX`(40) ⇒ 装得下框。
	##   原来是 `border 3 + 圆角 12` 的 StyleBoxFlat —— **全游戏唯一一个还长着 CSS
	##   长相的对话框**, 而它正是每个新玩家开游戏看到的第一屏(关不掉的墙)。
	## ★`sb` 降级成 fallback(贴图缺失时才用), 并且**也改成直角**:
	##   `UISkin` 铁律① 说贴图缺失要优雅退回, 但退回的那份不该把 ai 味带回来。
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#5aa0ff")
	sb.set_border_width_all(3); sb.set_corner_radius_all(0)
	var btex := UISkin.nine("panel-frame.png", 20, sb)
	if btex is StyleBoxTexture:
		(btex as StyleBoxTexture).modulate_color = UISkin.tint_of(Color("#5aa0ff"))
	box.add_theme_stylebox_override("panel", btex)
	## ★★★2026-09-28 框高**从网格算**, 不再一处一处加减 —— 见上面 `_W_ROW_*` 那段。
	##   三行靶子 + 状态行 + (墙上才有的)版本号。**两步共用同一个高度** ⇒ 换步不跳。
	var _rows_bot: float = _W_ROW_Y0 + float(_W_ROWS - 1) * (_W_ROW_H + _W_ROW_GAP) + _W_ROW_H
	var _bh: float = _rows_bot + 8.0 + 48.0 + 20.0
	## ★★★墙上要印版本号。
	##   用户实测撞上的: 他被墙挡住、报「邮箱注册没用」, 而**说不出版本号** ——
	##   因为版本号只画在**主菜单右下角**, 而这堤墙**挡在主菜单之前**。
	##   ⇒ 最需要报版本的人, 恰恰是唯一看不到版本的人。
	## ★读 ProjectSettings, **不写死**(门禁扫硬编码字面量)。
	if standalone:
		_bh += 30.0
	box.size = Vector2(520, _bh)
	## ★★位置**不在这里写死** —— 交给 `_email_relayout()`(居中于真实视口 + 键盘让位)。
	##   原来这一行是 `Vector2(W / 2.0 - 260, H / 2.0 - _bh / 2.0)`, 即 1280x720 的
	##   **设计坐标**, 而 iPhone 横屏视口是 1560x720(canvas_items + expand 锁高)
	##   ⇒ 探针 `_probe_wall_hit` 实测整块墙**偏左 140px**。
	_email_box = box
	dim.add_child(box)
	_email_relayout()
	return box


## 标题。
func _wall_title(box: Control, flow: String, standalone: bool) -> void:
	var ttl := Label.new()
	## ★标题**两步共用一份**, 不随步骤换字 —— 墙上那句话是
	##   `verify_ui_consistency` 的真分母(“墙那句话真的在屏幕上”), 换字就量不到了。
	ttl.text = (_P2C.login_wall_head() if standalone
		else ("绑定邮箱" if flow == _SB_ACC.FLOW_BIND else "用邮箱取回账号"))
	ttl.add_theme_font_size_override("font_size", 24)
	ttl.add_theme_color_override("font_color", Color("#cfe3ff"))
	ttl.position = Vector2(0, 18); ttl.size = Vector2(520, 32)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)


## 说明文字: 按流程 / 是不是墙 选一段, 再按步切成两份。
func _wall_explain(box: Control, flow: String, standalone: bool) -> void:
	## ★★★说明文字**一个字都不删**(用户 2026-09-24 点名:「没绑邮箱换设备就是丢档,
	##   这一点要在 UI 上说清楚」)。第一步照旧把**整段**印出来;
	##   第二步再把**最后那一句**留在屏幕上 —— 墙上那句恰好是
	##   「收不到验证码？看看垃圾邮件…」, 而第二步就是等码的那一步,
	##   它在那儿才真的用得上。
	## ★切点用作者自己写的 `\n`, **不重写文案** —— 文案的事实源在
	##   `phase2_config.login_wall_body()`, 不在这一屏。
	var body: String = ""
	if flow == _SB_ACC.FLOW_BIND:
		## ★墙上第一句先让**老玩家别慌**: 绑定是升级同一个号, 进度一个字节都不会变。
		body = (_P2C.login_wall_body() if standalone
			else ("绑定之后，换手机能用这个邮箱把【账号】取回来（排名、战绩、你的阵容）。\n"
				+ "⚠ 龟和装备是存在这台手机上的，换设备仍然会丢。"))
	else:
		## ★取回只换【账号】, 这台设备上的龟和装备原样不动 —— 照实说, 不许说成「取回存档」
		##   (服务端现在没有存档, `verify_account` ④ 有一条专门禁这句话)。
		## ★D-8: 取回会把那个号的云存档拉下来**整体替换**本机进度 —— 照实说,
		##   并说清替换之前会先备份(GameState.backup_save)。
		body = ("用你绑过的邮箱收一个验证码，把那个账号和它的进度取回到这台设备上。\n"
			+ "⚠ 这台设备现在的进度会被换掉（换之前会先在本机备份一份）。")
	## ★★第一步只印**除最后一句以外的全部**。原来第一步把**整段**都印上去,
	##   而墙上最后那句恰好是「收不到验证码？…」—— 第一步还没发码,
	##   这句话在那里一点用处也没有, 就是白白多两行字。
	##   (参考里说明文字的中位数是 **0 行**。我们删不到 0 —— 用户点名
	##   「换设备会丢档要说清楚」; 但至少不要在用不上的那一步印它。)
	## ★切点还是作者自己写的换行, **不在这一屏重写文案**。
	var parts: PackedStringArray = body.split("\n")
	var head_lines: PackedStringArray = parts.slice(0, maxi(parts.size() - 1, 1))
	_email_why = _wall_text(box, "\n".join(head_lines), 13, "#9fb4c8", 58.0, 64.0)
	_email_why2 = _wall_text(box, str(parts[parts.size() - 1]), 13, "#9fb4c8", 58.0, 64.0)


## 第一步的三行: 昵称(+「换一个」并排) / 邮箱 / 发验证码。
## ★那一行小字两步共用一个 Label, 所以它也建在这里。
func _wall_build_step1(box: Control, flow: String) -> void:
	## 靶子上方那一行小字。第一步 = 昵称规则(只绑定流程有);
	## 第二步 = 码发到哪个邮箱了(没这一行, 第二步就是一屏没上下文的空框)。
	## ★两步共用**一个 Label**, 文字由 `_email_set_step` 统一给 —— 两份各写一份必然漂。
	_email_hint = _wall_text(box, "", 12, "#9fb4c8", 128.0, 22.0)
	if flow == _SB_ACC.FLOW_BIND:
		## ★★昵称(只有绑定流程要填)。用户 2026-09-24:「这个在创建账号应该一起吧」——
		##   这个项目里玩家感知得到的「创建账号」只有这一处(首启建匈名号是**静默**的)。
		##   取回流程不填: 那个号已经有昵称了, 跟着账号一起回来。
		_email_hint1 = "起个名字(%d~%d 个字) —— 排行榜上别人看到的就是它，以后随时能改" % [
			_P2C.NICK_MIN, _P2C.NICK_MAX]
		_nick_edit = LineEdit.new()
		_nick_edit.placeholder_text = "你的名字"
		## ★★★**预填一个龟世界的随机名** —— 参考里取名那一步的设计目标是
		##   「玩家一个字都不打也能过去」(Sonic Rumble 预填 `Player_561962` 直接点 OK)。
		##   而这一屏是每个新玩家开游戏的第一屏, 原来是**空框**: 第一件事就是
		##   用虚拟键盘打中文 —— 而中文键盘带候选条, 正是把下面那些钮盖住的
		##   那一档高度(见 `_email_relayout` 头注)。
		## ★已经有名字的人**不覆盖**: 老玩家升级过来会被墙挡一次, 名字得留住。
		_nick_edit.text = _P2C.nickname_clean(str(GameState.nickname))
		if not _P2C.nickname_valid(_nick_edit.text):
			_nick_edit.text = _P2C.nickname_suggest()
		_nick_edit.max_length = _P2C.NICK_MAX * 2   # ★按**规范化后**判长度, 这里只防手滑贴一长串
		_nick_edit.add_theme_font_size_override("font_size", 16)
		_skin_edit(_nick_edit)
		box.add_child(_nick_edit)
		_email_rows1.append(_nick_edit)
		## ★★「换一个」—— 与昵称框**并排**, 不占新的一行。
		##   占了就是四行(4×81 + 3×21 = 387), 中文键盘那一档(上限 330)当场破。
		## ★★★`nickname_suggest(avoid)` 保证给的**不是**现在这个名字 ——
		##   按下去还是同一个名字, 就是本仓最忌的那种「点了没反应」。
		_email_side[_nick_edit] = _wall_btn(box, _P2C.NICK_REROLL, func():
			_nick_edit.text = _P2C.nickname_suggest(_nick_edit.text))

	_email_edit = LineEdit.new()
	_email_edit.placeholder_text = "你的邮箱"
	_email_edit.text = str(GameState.account_email)
	## ★★键盘**类型**要对(2026-09-28)。它不只是方便: 中文键盘的候选条会让键盘再高
	##   一档(41.5% → ≈52% 屏高), 而这一屏的按钮就在那条线附近(见 `_email_relayout` 头注)。
	##   `KEYBOARD_TYPE_EMAIL_ADDRESS` 直接给 ASCII + `@` 键, 没有候选条。
	_email_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_email_edit.add_theme_font_size_override("font_size", 16)
	_skin_edit(_email_edit)
	box.add_child(_email_edit)
	_email_rows1.append(_email_edit)

	_email_send_btn = _wall_btn(box, "发验证码", func():
		_SB_ACC.send_code_async(_email_edit.text, flow))
	_email_rows1.append(_email_send_btn)


## 第二步的三行: 验证码 / 确认 / 回上一步改邮箱。
func _wall_build_step2(box: Control, flow: String) -> void:
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "邮件里的验证码"
	## ★码是纯数字(`verify_code_async` 的提示原话:「把邮件里那串数字填进来」)
	##   ⇒ 给数字键盘。同上: 顺带避掉中文候选条那一档高度。
	_code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_code_edit.add_theme_font_size_override("font_size", 16)
	_skin_edit(_code_edit)
	box.add_child(_code_edit)
	_email_rows2.append(_code_edit)

	_email_ok_btn = _wall_btn(box, "确认", func():
		## ★★昵称先过一遍规则再验码 —— 验码成功之后才存就晚了:
		##   那一刻对话框已经关了, 玩家没机会改。规则只有 `phase2_config` 一份。
		## ★★分两步之后昵称框在第二步是**隐的**(节点还在、字还在) ⇒
		##   这里照旧读得到它; 而规则不过时把人**送回第一步**, 否则他看到
		##   一条“名字不对”却找不到名字框在哪里 —— 那就是又一个「点了没反应」。
		if flow == _SB_ACC.FLOW_BIND:
			var err: String = _P2C.nickname_error(_nick_edit.text)
			if err != "":
				_email_set_step(1)
				_email_status.text = err
				_email_status.add_theme_color_override("font_color", Color("#ff9a9a"))
				return
			GameState.nickname = _P2C.nickname_clean(_nick_edit.text)
			GameState.save()
		_SB_ACC.verify_code_async(_code_edit.text))
	_email_rows2.append(_email_ok_btn)

	## ★★★第二步必须有退路。没它这堤墙是**死局**: 邮箱打错一个字母,
	##   码永远收不到, 而墙关不掉 ⇒ 唯一出路是杀进程。
	##   (memory `fb-a-wall-must-let-the-unblocking-action-through`: 加了拦截就要验
	##    「被拦住的人能不能完成解锁动作」。)
	_email_back_btn = _wall_btn(box, "回上一步改邮箱", func():
		## ★必须把流程也重置 —— 不然 `_email_poll` 下一跳看到 state 还是 SENT,
		##   当场把玩家又弹回第二步(自己造一个“点了没反应”)。
		_SB_ACC.reset_email_flow()
		_email_set_step(1))
	_email_rows2.append(_email_back_btn)


## 框底那几样: 状态行 + (墙上的)版本号 / (对话框的)关闭。
## ★版本号的 y 从 **框自己的高**算, 不再传 `_bh` 进来 —— 传一份数就是抄一份。
func _wall_build_footer(box: Control, dim: Control, dismissible: bool,
		standalone: bool) -> void:
	_email_status = Label.new()
	_email_status.add_theme_font_size_override("font_size", 13)
	_email_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_email_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_email_status)

	## ★★★盖满全屏那一屏要**印版本号**。理由与 2026-09-28 那次一样, 不是“顺便印”:
	##   这一屏盖满全屏 ⇒ 主菜单右下角那个版本号被盖掉了, 而玩家就是在这一屏
	##   碰到邮箱问题、在这一屏报 bug。设置页里那个小对话框不印(背后就是设置页)。
	## ★读 ProjectSettings, **不写死**(门禁扫硬编码字面量)。
	if standalone:
		_email_ver = Label.new()
		_email_ver.text = "版本 " + str(ProjectSettings.get_setting("application/config/version", "?"))
		_email_ver.name = ACCT_ROW_PREFIX + "WallVer"
		_email_ver.add_theme_font_size_override("font_size", 13)
		_email_ver.add_theme_color_override("font_color", Color("#7f8fa6"))
		_email_ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_email_ver)
		## ★位置是**量出来的**不是摆的: 框走 panel-frame 九宫格, 边带 13px。
		##   `_bh - 44` ⇒ 底 = `_bh - 20`, 离边带内沿还剩 7px。
		##   ★★**入树之后**再设尺寸(本文件 `why.size` 那段记的同一坑)。
		_email_ver.position = Vector2(_W_PAD, box.size.y - 44.0)
		_email_ver.size = Vector2(_W_CW, 24)
	## ★★「关闭」与主按钮**并排在同一行**, 不占新的一行 ——
	##   占了就是四行(4×81+3×21 = 387), 中文键盘那一档(上限 330)当场破。
	##   它也仍然是 159×81 ⇒ 短边 81px = 44pt, 过线。
	## ★★★ 2026-09-29 拆墙之后**盖满全屏那一屏也有它**。那正是「拦不住人」
	##   在屏幕上的样子: 这一屏给了一个出口, 而那个出口通回游戏。
	if dismissible:
		_email_close_btn = _wall_btn(box, "关闭", func():
			_close_email_dialog(dim))


## 把对话框/绑定屏关掉。
##
## ★★★抽成一个函数而不是写在闭包里: 盖满全屏那一屏关掉时要做三件事,
##   写在闭包里的话以后谁动那一屏都要把这三件抄一遍:
##     ① 把被藏起来的设置页原样交还(只翻回自己藏的那几个, 不是 `visible = true` 一抹)
##     ② 把顶栏返回箭头还回来
##     ③ 如果这一屏就是当前场景(= 玩家从主菜单那句提示点过来的), **送他回主菜单**
##       —— 他点「关闭」要的是回去玩, 不是落在一页设置里。
## ★③ 那道 `current_scene == self` 的守卫不是可选的: 门禁/实拍常把设置页当子节点
##   挂起来量东西, 在那种情况下 `change_scene_to_file` 会把**宿主的**场景树换掉
##   (本仓踩过这个; 主菜单那边的跳转也带着同一道守卫)。
func _close_email_dialog(dim: Control) -> void:
	_SB_ACC.reset_email_flow()
	if dim != null and is_instance_valid(dim):
		dim.queue_free()
	_email_layer = null
	_email_box = null
	var was_standalone: bool = _email_standalone
	_email_standalone = false
	for ch in _hidden_by_screen:
		if ch != null and is_instance_valid(ch) and ch is Control:
			(ch as Control).visible = true
	_hidden_by_screen.clear()
	if _top_bar != null and _top_bar.back_btn != null:
		_top_bar.back_btn.visible = true
	if was_standalone and get_tree() != null and get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _email_relayout() -> void:
	if _email_box == null or not is_instance_valid(_email_box):
		return
	var av: Vector2 = _email_avail()
	## ★★照 `UIFrame` 自己那条居中公式(`_center()`: 设计框居中于可用区), **不另发明一套** ——
	##   这样墙和别的屏落在同一个坐标系里(memory `fb-hand-rolled-copies-drift`)。
	var origin: Vector2 = ((av - UIFrame.DESIGN) * 0.5).round()
	origin.x = maxf(0.0, origin.x)
	origin.y = maxf(0.0, origin.y)
	var p: Vector2 = origin + Vector2(W / 2.0 - 260.0, H / 2.0 - _email_box.size.y / 2.0)
	## 键盘让位: **只往上挪, 绝不往下**(往下只会把东西推得更深)。
	##
	## ★★让位量按「**最低的那个可点元素**」算, 不按框底算 —— 框底下面还有状态行和
	##   版本号那两行**只读的字**, 它们躲进键盘后面完全没关系。按框底算会白挪 65px,
	##   把标题顶出屏幕去换两行不用看的字, 那是**判据没匹配被测概念**。
	## ★★能挪到的最上限是「**说明文字可以顶出去, 可点元素一个都不许顶出去**」:
	##   玩家正在打字, 他要看见输入框和那个钮; 而「你的进度还在…」那段他已经读过了。
	var kb: float = _vkb_height_vp(av)
	if kb > 0.0:
		var band: Vector2 = _email_ctl_band()      ## x = 最高可点元素顶, y = 最低可点元素底
		p.y = minf(p.y, maxf(_KB_GAP - band.x, av.y - kb - band.y - _KB_GAP))
	_email_box.position = p.round()
	## 标的位置**跟着框走**: 摆在框左边那块空地的正中, 竖向居中于可用区。
	## ★它是**背景**, 不跟着键盘让位一起挑 —— 让位是为了让要打字的那几个
	##   东西露出来, 把一张标也一起往上挑只会把它顶出屏幕。
	## ★★空地不够宽就**整个不显示**, 而不是压到框上去。
	_WALL_ART.place_logo(_email_logo, _email_box.position.x, av.y)


## 框里**可点元素**竖向占的那一段(框内局部坐标): x = 最上沿, y = 最下沿。
## ★从真实子节点量, 不写死 y 值 —— 绑定/取回两条流程行数不同(`_dy`),
##   写死就是抄一份永远落后(memory `fb-hand-rolled-copies-drift`)。
func _email_ctl_band() -> Vector2:
	var lo: float = -1.0
	var hi: float = 0.0
	if _email_box != null and is_instance_valid(_email_box):
		for ch in _email_box.get_children():
			if not (ch is LineEdit or ch is BaseButton):
				continue
			var c := ch as Control
			## ★★★分两步之后**另一步的控件还在树上, 只是 visible = false** ——
			##   不跳过它们, band 就会把两步的行全算进去(高 267 → 453),
			##   键盘让位当场算出一个装不下的量, 而屏幕上根本没有那些东西。
			##   (门禁那边 `_hot()` 用的是 `is_visible_in_tree()`, 两边口径要一致。)
			if not c.is_visible_in_tree():
				continue
			lo = c.position.y if lo < 0.0 else minf(lo, c.position.y)
			hi = maxf(hi, c.position.y + c.size.y)
	if lo < 0.0:
		return Vector2(0.0, _email_box.size.y if _email_box != null else 0.0)
	return Vector2(lo, hi)


## 这一屏的可用区。★优先用根 Control 自己的矩形(.tscn 里是铺满视口的),
## 拿不到再退视口, 最后退设计尺寸 —— 与 `UIFrame._avail()` 同一套退路。
## (门禁里有 `SET.new()` 裸实例这种用法, 那时 `size` 是 0, 必须退得下去。)
func _email_avail() -> Vector2:
	var s: Vector2 = size
	if s.x < UIFrame.DESIGN.x or s.y < 360.0:
		var vp := get_viewport()
		s = Vector2(vp.get_visible_rect().size) if vp != null else UIFrame.DESIGN
	return Vector2(maxf(s.x, UIFrame.DESIGN.x), maxf(s.y, UIFrame.DESIGN.y))


## 虚拟键盘现在有多高, **换算成视口单位**。没有键盘 ⇒ 0。
##
## ★`has_feature` 要先问一声: 桌面/无头直接调 `virtual_keyboard_get_height()` 会
##   **每帧刷一条 WARNING**(实测 `Virtual keyboard not supported by this display server`)。
## ★门禁注入(`vkb_override_vp`)优先 —— 无头下 `has_feature` 实测就是 false,
##   不给缝的话键盘那一支永远走不到, 判据变空检查。
func _vkb_height_vp(av: Vector2) -> float:
	if vkb_override_vp >= 0.0:
		return vkb_override_vp
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return 0.0
	return _vkb_to_vp(float(DisplayServer.virtual_keyboard_get_height()),
		av, Vector2(DisplayServer.window_get_size()))


## 物理窗口像素 → 视口单位。**纯函数**, 门禁直接量它。
##
## ★为什么要折算: `virtual_keyboard_get_height()` 给的是**物理窗口像素**
##   (iPhone 14 横屏 3x: 键盘 162pt = 486px, 窗口 390pt = 1170px),
##   而视口是 1280x720 拉伸的 ⇒ 不折算就会挪错量(486 而不是 299)。
## ★`window_get_size()` 无头返回 `(0, 0)`(实测) ⇒ 除零要挡住。
static func _vkb_to_vp(kb_px: float, av: Vector2, win: Vector2) -> float:
	if kb_px <= 0.0 or win.y <= 1.0 or av.y <= 1.0:
		return 0.0
	return kb_px * (av.y / win.y)


## ★只在对话框开着的时候动 —— 这一屏平时不需要每帧做事。
func _process(_dt: float) -> void:
	if _email_layer != null and is_instance_valid(_email_layer):
		_email_relayout()


## 把网络层那个小状态机画出来。**每一步都要有话说** ——
## 点完「发验证码」什么都不变的话, 玩家只会反复点(还把限流撞满)。
## 绑定成功之后该把人送去哪。`""` = 留在原地。
##
## ★抽成**纯函数**是为了让门禁量得到这个决策 —— 直接写在 `_email_poll` 里的话,
##   门禁一调它就 `change_scene_to_file`, **当场把自己拆掉**(本仓 `verify_mainmenu_layout`
##   2026-09-26 正是这样一周有两天整份不算数)。现在门禁量决策、探针量端到端。
## ★★★判据不是「我自认绑完了」而是 `bind_needed` **已经变假**(= 邮箱真的落盘了),
##   与主菜单那句提示、与开墙全是同一条条件 —— 两处各判一份必然漂。
## ★★为何不再读 `login_wall_on`(拆墙之前读的就是它): 那一处现在**恒假**
##   ⇒ `not login_wall_on(...)` 恒真 ⇒ 这个函数会在**还没绑**的时候就把人送走,
##   而门禁 ④ 那条分母「这一刻还不能放人走」当场红。这就是 memory
##   `fb-changing-a-param-meaning-makes-gates-tautological` 那一类: 名字没变、
##   类型没变、编译器不拦, 只有跑起来才看得见。
func _post_bind_dest() -> String:
	if _email_standalone and not _P2C.bind_needed(_acct_on(), _acct_mail()):
		return "res://scenes/MainMenu.tscn"
	return ""


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
			## ★★★绑成功之后必须**放人过去**。2026-09-27 探针实测(`_probe_wall_escape`):
			##   原来这里只把字染成绿色 —— 遮罩不消、返回箭头还藏着 ⇒ 玩家看着
			##   「邮箱绑好了」**一步也走不了**, 唯一出路是杀进程重开(重开能进,
			##   因为邮箱已经写盘)。下周 10 人测试**第一个动作**就会撞上它。
			##   —— memory `fb-a-wall-must-let-the-unblocking-action-through`:
			##      加了拦截就要验「被拦住的人能不能完成解锁动作」。
			##
			## ★判据不是「我自认是墙」, 而是 `login_wall_on` **已经变假** —— 与开墙
			##   同一处判据(两处各判一份必然漂)。`_email_standalone` 只用来分
			##   「盖满全屏的绑定屏 / 设置页里自己点开的」。
			## ★去主菜单而不是只关遮罩: 他在墙上绑定, 想要的就是**进游戏**;
			##   而设置页本体在墙立起来时就没什么可看的了。
			var _dest: String = _post_bind_dest()
			if _dest != "":
				_email_status.text = msg if msg != "" else "邮箱绑好了"
				get_tree().change_scene_to_file(_dest)
				return
		_:
			if msg == "":
				## ★★原话是「…把邮件里的数字填到**下面**」。分两步之后那个「下面」
				##   在第一步根本不存在(码框在下一屏)、在第二步反而在**上面**
				##   ⇒ 指错方向比不指更糟。换成不带方位的说法。
				msg = "填邮箱 → 发验证码 → 填邮件里那串数字"
	_email_status.text = msg
	_email_status.add_theme_color_override("font_color", Color(col))
	## ★★★码发出去了 ⇒ 自己翻到第二步。**不给玩家一个「下一步」去找** ——
	##   他刚按的那个钮就叫「发验证码」, 发完该看到的就是填码那一屏。
	## ★只认 `EM_SENT`: `EM_ERR`(限流/地址不对/断网)要**留在第一步**让他改邮箱,
	##   把人推去第二步等一个永远不会到的码, 正好是「点了没反应」的另一种长相。
	if _email_step == 1 and st == _SB_ACC.EM_SENT:
		_email_set_step(2)
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


## ★★2026-09-28 与下面的画质键统一成【状态式】: 牌子上写的是**现在是什么**,
##   不是"按下去会发生什么"。原来这一个是动作式(「全屏」/「退出全屏」)、
##   旁边那个是状态式 —— 同一列两种读法, 玩家要在两种语法之间来回切。
##   状态式那条原则是这一屏自己定的(见 `_perf_label` 头注), 这里把它补齐。
## ★用「」而不是半角冒号: `画质: 高` 那种 `标签: 值` 就是网页表单的长相,
##   而「」是这个项目通篇在用的引用号(「用邮箱取回」「财神龟」)。
func _fullscreen_label() -> String:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return "画面「全屏」"
	return "画面「窗口」"


## ★2026-08-19 缩短: 原文「🪶 低画质模式: 关 (高画质)」在 260 宽的木牌里**装不下** ——
##   木牌两端的花纹柱实测各占 29px, 内部只有 202px, 而这行字的墨迹约 240px ⇒ 字骑在花纹上。
##   (实拍看出来的; 门禁原来查不到, 因为它只把 StyleBoxTexture/NinePatchRect 当框,
##    而这里的框是一个**拉伸的 TextureRect**。已一并补进 verify_ui_consistency。)
##   "开/关" 也去掉了 —— 按钮显示的是**当前是什么**, 不是"这个开关的开关状态", 后者要绕一圈才读懂。
## ★★2026-09-28 去掉那个**半角冒号**。「画质: 高」= `label: value`,
##   是网页表单/设置页最典型的一行; 换成「」之后它读起来是一块写着当前状态的牌子。
##   宽度没变大(冒号+空格 2 个半角 ≈ 「」1 个全角), 仍远小于木牌 202px 的内部净宽。
## ★★2026-09-28 去掉 🪶(羽毛)。它既不是「画质」也不是「高/低」的图形,
##   是当时随手挖的一个装饰字符; 而它的字形来自 NotoEmoji ⇒ 这块木牌上
##   一个矢量羽毛 + 一排像素字。信息全在后面那四个字里, 直接去掉。
func _perf_label() -> String:
	if GameState.perf_lite:
		return "画质「低」"
	return "画质「高」"


## 低画质模式 = 真开关 (原来只改自己的 label, grep 全库无第二处引用 = 死按钮)
## 实际效果见 `apply_perf_lite()` (战斗视口) 与各菜单场景的背景漂移 gate。
func _toggle_perf() -> void:
	GameState.perf_lite = not GameState.perf_lite
	GameState.save()
	if _perf_btn != null:
		_perf_btn.text = _perf_label()
	## 按钮上只剩"高/低", 于是把"低=更流畅"这条信息挪到 toast 里, 不然玩家不知道调它图什么。
	## ★2026-09-28 换成说人话的版本: 「已设为」是设置面板的腔调, 玩家听的是"下一场就不卡了"。
	_toast("画质换成「%s」了%s · 下一场开打时生效" % [
		"低" if GameState.perf_lite else "高",
		"，手机会跑得更顺" if GameState.perf_lite else ""])


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
	## ★★2026-09-28 换**金属九宫格框**(`panel-frame`, 与邮箱对话框/背包/图鉴/战绩同一张)。
	##   原来是 `border 3 + 圆角 12` 的 StyleBoxFlat —— 这一屏最后两个还长着 CSS 卡片
	##   长相的盒子之一(另一个是存档冲突框)。邮箱对话框 2026-09-27 已经换过,
	##   这两个漏了, 因为它们**默认不显示** ⇒ `verify_ui_consistency` 的棘轮从没量到过。
	##   —— memory `fb-gate-subject-never-constructed`: 判据没错, 被测对象不在场。
	## ★`sb` 降级成 fallback(贴图缺失时才用), 圆角一并抹成 0: `UISkin` 铁律①说要优雅退回,
	##   但退回的那一份不该把网页味带回来。
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ff5566")
	sb.set_border_width_all(3); sb.set_corner_radius_all(0)
	var rtex := UISkin.nine("panel-frame.png", 20, sb)
	if rtex is StyleBoxTexture:
		(rtex as StyleBoxTexture).modulate_color = UISkin.tint_of(Color("#ff5566"))
	box.add_theme_stylebox_override("panel", rtex)
	## 高 260→300: 两个键从 160x44(短边 44 < 81 触摸线)改成 210x52。
	box.position = Vector2(W / 2.0 - 260, H / 2.0 - 150); box.size = Vector2(520, 300)
	dim.add_child(box)

	var ttl := Label.new()
	ttl.text = "⚠ 重置所有存档？"
	ttl.add_theme_font_size_override("font_size", 26)
	ttl.add_theme_color_override("font_color", Color("#ff5566"))
	ttl.position = Vector2(0, 20); ttl.size = Vector2(520, 36)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)

	var msg := Label.new()
	## ★★原文案里**带着字面量 `**`**(`**此操作不可撤销。**`) —— 那是 Markdown 的粗体语法,
	##   Label 不解析它, 屏幕上就是四个星号。写文案的人当时在写文档不是在写 UI。
	## ★「此操作不可撤销」是条款腔; 玩家要听的是「清了就拿不回来」。
	msg.text = ("会清空：深海币 · 背包装备 · 出战统领 · 赛季进度（命/等级/胜场）· 糖果罐 · 布阵。\n"
		+ "⚠ 清掉就拿不回来了。音量、全屏、画质这些不动。")
	msg.add_theme_font_size_override("font_size", 15)
	msg.add_theme_color_override("font_color", Color("#c9d6e2"))
	msg.position = Vector2(30, 72)
	## ★中文没有词边界, `WORD_SMART` 在这一段里找不到断点 ⇒ Label 的最小宽把自己撑出框外
	##   (邮箱对话框 2026-09-27 实测被撑到 586 / 框只有 520)。中文本来就按字断行。
	msg.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(msg)
	## ★★**入树之后再设一次尺寸** —— 控件入树时尺寸会被重算掉,
	##   写在 `add_child` 之前的那次不一定算数(同一坑见 `_open_email_dialog` 的 `why`)。
	msg.size = Vector2(460, 96)

	var cancel := Button.new()
	cancel.text = "先不清"
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.position = Vector2(40, 196); cancel.size = Vector2(210, 52)
	## ★★原来是**裸 `Button.new()`** = Godot 默认皮(圆角灰板)。换皮走共享层 `UISkin`,
	##   不在这里手写 StyleBox(memory `fb-hand-rolled-copies-drift`)。
	UISkin.button(cancel)
	cancel.pressed.connect(func(): dim.queue_free(); _confirm_layer = null)
	box.add_child(cancel)

	var ok := Button.new()
	ok.text = "清空，我确定"
	ok.add_theme_font_size_override("font_size", 18)
	ok.position = Vector2(270, 196); ok.size = Vector2(210, 52)
	## 破坏性那一侧染红 —— 两个键长得一样时, 玩家分不出哪个是"会出事"的那个。
	UISkin.button(ok, Color("#ff5566"))
	ok.add_theme_color_override("font_color", Color("#ffdfe2"))
	ok.pressed.connect(func():
		dim.queue_free(); _confirm_layer = null
		_do_reset())
	box.add_child(ok)


func _do_reset() -> void:
	GameState.reset_save()
	_toast("存档清空了 · 从头再来")


# ── 音量条 (track w=380) ──────────────────────────────────────
## cb        = 拖动中每次变化都调 (实时生效, 不写盘)
## on_release= 松手/点轨道时调一次 (写盘 / 试听音效). 原实现在 cb 里 save()+play_sfx → 拖一下写几十次盘、爆音。
##
## ═══ ★★2026-09-28 整条重画: 这是全屏最像网页的一个控件 ═══
## 原来是 —— 8px 高的 `#444444` 细灰条 + `#ffd93d` 纯色填充 + 一个纯色**圆球**把手。
## 那三件凑在一起就是 `<input type="range">` 的默认长相(灰轨/实心进度/圆 thumb),
## 与它上下左右那些金属木牌完全不是一个世界的东西。
##
## 换成本仓已有的像素件, **一张新素材都不用画**:
##   · 槽  = `battlehud/bar-frame.png`(战斗血条/龟能条那张九宫格金属条)
##   · 刻度 = 槽里的四道暗口子(1/5 一格), 只在**没填到的那段**看得见 —— 填充盖住走过的
##   · 填充 = 三层像素明暗(顶高光 / 主色 / 底暗边), 不是一块纯色
##   · 把手 = 有描边和高光的方钮, 中间两道握纹(`_knob`), 不是几何圆
## 边距是**从贴图量的**(96x24: 左右边带 7、上下 4 ⇒ 取 8 / 5), 不是拍的 ——
## 与 `info_panel._bar_frame` 对同一张图的做法一致。
const _SLD_H := 26.0            # 槽总高(含金属边带)
const _SLD_BAND_X := 8.0        # 槽左右边带厚度(量自贴图)
const _SLD_BAND_Y := 5.0        # 槽上下边带厚度(量自贴图)

## 按流水放一条滑条: 顶沿钉在 top, 返回下沿。
## ★一条滑条占的竖向空间 = 名牌(槽中心往上 `_SLD_LABEL_GAP`) 到 触摸带下沿(槽中心往下 24) ——
##   **触摸带比槽本身各往外宽 11px**, 忘了它就是 2026-09-29 那条"按钮压进拖动带"的来源。
func _slider_row(top: float, label: String, init: float, cb: Callable,
		on_release: Callable = Callable()) -> float:
	var cy := top + _SLD_H / 2.0 + _SLD_LABEL_GAP
	_slider(W / 2.0, cy, label, init, cb, on_release)
	return cy + _SLD_HIT_H / 2.0


func _slider(cx: float, cy: float, label: String, init: float, cb: Callable, on_release: Callable = Callable()) -> void:
	var track_w := 380.0
	var left := cx - track_w / 2.0
	## 填充的可用区 = 槽减掉金属边带。把值映射到这一段而不是整条,
	## 否则 0% 时会有一截颜色压在左边那道金属沿上。
	var fx := left + _SLD_BAND_X
	var fw := track_w - _SLD_BAND_X * 2.0
	var fy := cy - _SLD_H / 2.0 + _SLD_BAND_Y
	var fh := _SLD_H - _SLD_BAND_Y * 2.0

	## 名牌: 加描边 —— 这一屏的背景是平铺的图案砖, 无描边的白字在上面发糊。
	var lbl := _stroked_label(label, 17, "#ffe9b0", "#2a1b08", 4)
	lbl.position = Vector2(left, cy - _SLD_H / 2.0 - _SLD_LABEL_GAP)
	add_child(lbl)

	## ① 金属槽(九宫格)。`mouse_filter=IGNORE` —— 命中全交给下面那条 48px 的透明条。
	var groove := NinePatchRect.new()
	if ResourceLoader.exists("res://assets/sprites/battlehud/bar-frame.png"):
		groove.texture = load("res://assets/sprites/battlehud/bar-frame.png")
	groove.patch_margin_left = int(_SLD_BAND_X); groove.patch_margin_right = int(_SLD_BAND_X)
	groove.patch_margin_top = int(_SLD_BAND_Y); groove.patch_margin_bottom = int(_SLD_BAND_Y)
	groove.size = Vector2(track_w, _SLD_H)
	groove.position = Vector2(left, cy - _SLD_H / 2.0)
	groove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## ★★染成**青铜**。`bar-frame` 是战斗 HUD 的件, 主体色量出来是 (119,178,250) 的
	##   矢车菊蓝 —— 直接拿过来放在这一屏, 它是整块画面里唯一的冷色, 实拍一眼就是"外来件"。
	##   乘数是按目标色**算**的不是拍的: 119×1.51≈180 / 178×0.79≈141 / 250×0.28≈70,
	##   落在木牌那身 #c8862a 的同一族里。黑色乘出来还是黑, 深槽不受影响。
	##   (`UISkin` 铁律②: 状态/配色走 modulate, 不为此另做一张图。)
	groove.self_modulate = Color(1.51, 0.79, 0.28)
	add_child(groove)

	## ② 槽底。贴图里那块是**纯黑**, 在暖色画面里读起来是个洞;
	##   铺一层暗棕当底(贴图缺失时它也正好当兜底, 不用再写一支 if)。
	var channel := ColorRect.new()
	channel.color = Color("#241a0c")
	channel.size = Vector2(fw, fh)
	channel.position = Vector2(fx, fy)
	channel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(channel)

	## ③ 刻度口子(1/5 一格)。★先加 ⇒ 后面的填充会盖住它们,
	##   于是刻度**只在空着的那一段**露出来 —— 一眼看得出还剩多少。
	##   ★颜色要比槽底**亮**: 第一版用的是半透明黑, 压在黑槽上等于没画(实拍一道都看不见)。
	for i in range(1, 5):
		var tick := ColorRect.new()
		tick.color = Color("#5a431d")
		tick.size = Vector2(2.0, fh)
		tick.position = Vector2(fx + fw * (float(i) / 5.0) - 1.0, fy)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tick)

	## ④ 填充: 三层像素明暗, 不是一块纯色(纯色 = 网页进度条)。
	var fill := ColorRect.new()
	fill.color = Color("#e0a020")
	fill.size = Vector2(fw * init, fh)
	fill.position = Vector2(fx, fy)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)
	var fill_hi := ColorRect.new()             # 顶高光
	fill_hi.color = Color("#ffe066")
	fill_hi.size = Vector2(fw * init, 4.0)
	fill_hi.position = Vector2(fx, fy)
	fill_hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill_hi)
	var fill_lo := ColorRect.new()             # 底暗边
	fill_lo.color = Color("#9c5a08")
	fill_lo.size = Vector2(fw * init, 3.0)
	fill_lo.position = Vector2(fx, fy + fh - 3.0)
	fill_lo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill_lo)

	## ⑤ 百分比。★不再用 `monospace` SystemFont —— 等宽字体是终端/代码的字,
	##   放在木牌旁边一眼就是"开发者面板"。改用全局中文字体 + 描边, 并**右对齐**:
	##   右边缘钉死 ⇒ 45%→100% 位数变了也不会左右跳(等宽当初就是为了防跳)。
	var pct := Label.new()
	pct.text = "%d%%" % int(round(init * 100.0))
	pct.add_theme_font_size_override("font_size", 18)
	pct.add_theme_color_override("font_color", Color("#ffe066"))
	pct.add_theme_constant_override("outline_size", 4)
	pct.add_theme_color_override("font_outline_color", Color("#2a1b08"))
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.size = Vector2(66, 22)
	pct.position = Vector2(cx + track_w / 2.0 + 12.0, cy - 12.0)
	add_child(pct)

	## ⑥ 方钮把手。★2026-08-01 起它不吃事件(28x28 = 手机上 15pt, 点不中),
	##   拖拽统一交给下面那条 48px 高的透明命中条 —— 这里只负责"看得见拖到哪了"。
	var knob := _knob(18.0, 34.0)
	knob.position = Vector2(fx + fw * init - 9.0, cy - 17.0)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(knob)

	var apply := func(px: float):
		var clamped: float = clampf(px, fx, fx + fw)
		var v: float = (clamped - fx) / fw
		knob.position.x = clamped - 9.0
		fill.size.x = fw * v
		fill_hi.size.x = fw * v
		fill_lo.size.x = fw * v
		pct.text = "%d%%" % int(round(v * 100.0))
		cb.call(v)

	# 点轨道跳 (即刻应用 + 一次 on_release)
	# ★手机板触控热区(用户2026-08-01): 槽本体只有 26px 高, 把手 18px 宽 —— 手指都难点中。
	#   所以另铺一条【透明命中条】盖住整行(48px 高 = 26pt), 点/拖它都等价于点轨道。
	#   ★命中条要在把手【之前】加(add_child 顺序=绘制/命中顺序), 否则它会盖住把手。
	var hit := Control.new()
	hit.size = Vector2(track_w, 48.0)
	hit.position = Vector2(left, cy - 24.0)
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(hit)
	move_child(hit, knob.get_index())   # 排到把手前面
	hit.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			apply.call(hit.global_position.x + ev.position.x)
			if on_release.is_valid(): on_release.call()
		elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			apply.call(hit.global_position.x + ev.position.x))


## 音量条的把手 —— 带描边/高光/握纹的方钮, 不是 `draw_circle` 画的纯色圆球。
## ★全靠 `draw_rect` 拼, 不引新贴图: 圆球那一版是几何图元(网页 thumb 的长相),
##   而像素 UI 里的把手是**有厚度的一块金属**: 暗描边 + 主面 + 顶高光 + 底暗边 + 两道握纹。
func _knob(w: float, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.size = Vector2(w, h)
	var draw := func():
		c.draw_rect(Rect2(0, 0, w, h), Color("#2a1b08"))                    # 描边
		c.draw_rect(Rect2(2, 2, w - 4, h - 4), Color("#e8b33c"))            # 主面
		c.draw_rect(Rect2(2, 2, w - 4, 6), Color("#fff0b3"))                # 顶高光
		c.draw_rect(Rect2(2, h - 8, w - 4, 6), Color("#a8670c"))            # 底暗边
		var gy := h * 0.5 - 6.0
		c.draw_rect(Rect2(w * 0.5 - 4.0, gy, 2, 12), Color("#8a5407"))      # 握纹
		c.draw_rect(Rect2(w * 0.5 + 2.0, gy, 2, 12), Color("#8a5407"))
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


## 按【流水】放一行居中文字: 顶沿钉在 top, 返回它的下沿。
## ★返回的是**控件矩形**的下沿(比字的 ink 高 8px 左右) —— 宁可多留一点也不要压住下一行。
func _place_flow(l: Label, top: float) -> float:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(400, float(l.get_theme_font_size("font_size")) + 16.0)
	l.position = Vector2(W / 2.0 - 200.0, top)
	add_child(l)
	return top + l.size.y


func _place_center(l: Label, cx: float, cy: float) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(400, float(l.get_theme_font_size("font_size")) + 16.0)
	l.position = Vector2(cx - 200.0, cy - l.size.y / 2.0)
	add_child(l)


## (`_mono_font()` 2026-09-28 删除: 全屏唯一的调用点是音量条的百分比,
##  而那处已经改用全局中文字体 + 右对齐。留一个零调用者的函数就是下一个人的坑。)


## 轻量提示 (1.4s 后淡出)
func _toast(msg: String) -> void:
	var l := _stroked_label(msg, 16, "#06d6a0", "", 0)
	_place_center(l, W / 2.0, 650.0)
	l.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, UIPalette.T_TRANS)
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
