extends Control
## mainsite_link_row.gd —— 设置页账号框里「龟投账号」那一行(2026-11-08 · 方案书 docs/plans/20261107-龟战主站对接.md §4.1)。
##
## 长相: 与上面「未绑定邮箱」状态卡同一种(压暗底 + 左边一道状态色竖条), 左边两行字、右边一颗按钮:
##   「龟投账号」(小字标签) / 状态(未绑定 · 等待确认 · 已绑定 · 登录码已过期 …)  +  [绑定] / [取消]; 已绑定时没有按钮。
## ★用户 11-07 定的叫法是「龟投账号」+「未绑定 / 已绑定」+「绑定」。标签与状态分两行写, 不拼成「龟投账号 · 未绑定」——
##   「·」把两件事拼成一行是 verify_ui_copy 禁用模式第 2 条(用户 11-01 文案规矩), 一行一件事。
## ★不出现「主站」「龟币」「金额」(用户 11-06 / 11-07); 这一行只在设置页, 选龟页不放任何龟投的入口或提示。
## ★状态每帧从 `MainsiteLink` 读(登录过程挂在 root 上的轮询节点里, 离开设置页也不断); 变了才重排。
## ★换号确认: 状态到 ST_SWITCH_ASK 时在宿主(设置页)上弹 `mainsite_link_dialog`; 确认后重开设置页(新账号的名字 / 玩家 ID)。
## 守卫: tests/verify_mainsite_link.gd

const ML := preload("res://scripts/net/mainsite_link.gd")
const DLG := preload("res://scripts/scenes/settings/mainsite_link_dialog.gd")

## 【节点名】前缀与设置页账号框同一族(`SettingsScene.ACCT_ROW_PREFIX` = "AcctRow"): 没配后端时整族都不建。
const N_ROW := "AcctRowMainsite"
const N_HEAD := "AcctRowMainsiteHead"
const N_STATE := "AcctRowMainsiteState"
const N_BTN := "AcctRowMainsiteBtn"

const HEAD := "龟投账号"
const S_UNBOUND := "未绑定"
const S_BOUND := "已绑定"
const S_CONNECTING := "连接中…"
const S_WAIT := "等待确认"
const S_EXPIRED := "登录码已过期"
const S_CANCELLED := "登录已取消"
const S_ERR := {
	ML.R_NET: "无法连接服务器",
	ML.R_OFF: "无法连接服务器",
	ML.R_AUTH: "登录已失效",
	ML.R_BLOCKED: "请更新游戏后重试",
	ML.R_BAD: "登录失败",
}
const L_BIND := "绑定"
const L_CANCEL := "取消"

const C_UNBOUND := "#ffb454"     # 与「未绑定邮箱」同一种警示橙
const C_BOUND := "#7fe0b0"       # 与「已绑定：邮箱」同一种绿
const C_WAIT := "#8fc7ff"
const C_ERR := "#ff8a94"

## 按钮宽 = 账号框半宽键(「黑名单」「删除账号」那一排), 右沿与下面几排对齐。
const BTN_W := 170.0

## 【门禁注入点】有效 ⇒ 换号完成后调它而不是重开设置页(门禁不能把自己的场景树换掉)。默认无效 = 玩家路径。
static var after_switch_hook: Callable = Callable()

var _host: Control = null
var _bar: ColorRect = null
var _head: Label = null
var _state: Label = null
var _btn: Button = null
var _sig := ""


## 纯函数: 这一刻这一行长什么样。`linked` 取 `MainsiteLink.linked_state()`(1 / 0 / -1 不知道);
##   `lost` 取 `MainsiteLink.lost_mode()`(0 没失效 / 1 失效、可用龟投账号重新登录 / 2 失效、不是龟投的号)。
## 返回 {state, col, btn("" = 没有按钮), btn_on, act("bind" / "cancel" / "")}。
## ★登录已失效(主会话 11-08): 龟投的号照样给「绑定」—— 点了先建临时匿名会话再发起登录(`MainsiteLink.start_link`);
##   状态行用现成的「登录已失效」, 不加新字。不是龟投的号不给按钮(走账号框里的「邮箱登录」)。
static func view_of(st: String, linked: int, why: String, me_busy: bool, lost: int = 0) -> Dictionary:
	match st:
		ML.ST_STARTING:
			return {"state": S_CONNECTING, "col": C_WAIT, "btn": L_BIND, "btn_on": false, "act": ""}
		ML.ST_PENDING, ML.ST_SWITCH_ASK:
			return {"state": S_WAIT, "col": C_WAIT, "btn": L_CANCEL, "btn_on": st == ML.ST_PENDING, "act": "cancel"}
	if lost == 1 and not (st == ML.ST_EXPIRED or st == ML.ST_CANCELLED or st == ML.ST_ERROR):
		return {"state": S_ERR[ML.R_AUTH], "col": C_ERR, "btn": L_BIND, "btn_on": true, "act": "bind"}
	if lost == 2:
		return {"state": S_ERR[ML.R_AUTH], "col": C_ERR, "btn": "", "btn_on": false, "act": ""}
	if linked == 1 and lost == 0:
		return {"state": S_BOUND, "col": C_BOUND, "btn": "", "btn_on": false, "act": ""}
	match st:
		ML.ST_EXPIRED:
			return {"state": S_EXPIRED, "col": C_ERR, "btn": L_BIND, "btn_on": true, "act": "bind"}
		ML.ST_CANCELLED:
			return {"state": S_CANCELLED, "col": C_UNBOUND, "btn": L_BIND, "btn_on": true, "act": "bind"}
		ML.ST_ERROR:
			return {"state": str(S_ERR.get(why, S_ERR[ML.R_NET])), "col": C_ERR, "btn": L_BIND, "btn_on": true, "act": "bind"}
	if linked < 0 and me_busy:
		return {"state": S_CONNECTING, "col": C_WAIT, "btn": L_BIND, "btn_on": false, "act": ""}
	return {"state": S_UNBOUND, "col": C_UNBOUND, "btn": L_BIND, "btn_on": true, "act": "bind"}


## 建在设置页账号框里。`r` = 这一行在设计框里的位置(宽 = 账号框内容宽, 高 = 账号按钮高)。
func setup(host: Control, r: Rect2) -> void:
	_host = host
	name = N_ROW
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = r.position
	size = r.size
	var bg := ColorRect.new()
	bg.color = Color("#141a2c")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.position = Vector2.ZERO
	bg.size = r.size
	add_child(bg)
	_bar = ColorRect.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.position = Vector2.ZERO
	_bar.size = Vector2(4.0, r.size.y)
	add_child(_bar)
	## 两行都 15 号: iPad 比例下整页缩到 0.75, 14 号的「龟投账号」糊成一团(实拍 960×720 量的)。
	_head = _label(N_HEAD, HEAD, 15, "#9fb4c8", 0)
	_head.position = Vector2(18.0, 4.0)
	_state = _label(N_STATE, "", 15, C_UNBOUND, 3)
	_state.position = Vector2(18.0, 28.0)
	_btn = Button.new()
	_btn.name = N_BTN
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 17)
	_btn.position = Vector2(r.size.x - BTN_W, 0.0)
	_btn.size = Vector2(BTN_W, r.size.y)
	UISkin.pixel_button(_btn, UISkin.PX_SLATE, 4)      # 与账号框里其余按钮同一套像素按钮(`SettingsScene._pix_button`)
	_btn.pressed.connect(_on_btn)
	add_child(_btn)
	_btn.position = Vector2(r.size.x - BTN_W, 0.0)
	_btn.size = Vector2(BTN_W, r.size.y)
	_refresh()


func _label(nm: String, t: String, fs: int, col: String, outline: int) -> Label:
	var l := Label.new()
	l.name = nm
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(col))
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color("#0a0d16"))
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _ready() -> void:
	## 进页问一次服务器(换设备 / 别的设备上绑过 ⇒ 本机缓存不知道)。登录进行中不问(结果由轮询给)。
	if ML.state() != ML.ST_PENDING and ML.state() != ML.ST_STARTING:
		ML.refresh_me()


func _process(_dt: float) -> void:
	_refresh()


func _refresh() -> void:
	if _state == null:
		return
	var st := ML.state()
	var v := view_of(st, ML.linked_state(), ML.reason(), ML.me_inflight(), ML.lost_mode())
	var sig := "%s|%s|%s|%s" % [v["state"], v["col"], v["btn"], v["btn_on"]]
	if sig != _sig:
		_sig = sig
		_state.text = str(v["state"])
		_state.add_theme_color_override("font_color", Color(str(v["col"])))
		_bar.color = Color(str(v["col"]))
		var has_btn := str(v["btn"]) != ""
		_btn.visible = has_btn
		_btn.text = str(v["btn"])
		_btn.disabled = not bool(v["btn_on"])
		_btn.set_meta("act", str(v["act"]))
		var tw := size.x - 18.0 - (BTN_W + 8.0 if has_btn else 12.0)
		_head.size = Vector2(tw, 23.0)
		_state.size = Vector2(tw, 24.0)
	## ★等宿主整页建完再弹(建页途中弹的话, 后建的两块框会盖在弹框上面)。
	var ask := st == ML.ST_SWITCH_ASK and _host != null and is_inside_tree() and _host.is_node_ready()
	if ask and _host.get_node_or_null(DLG.LAYER) == null:
		## 内部邮箱(服务器补的)不算玩家绑过邮箱 ⇒ 照「没绑邮箱」说(`MainsiteLink.user_email`)。
		DLG.open(_host, ML.user_email() != "", _on_switch_ok, ML.decline_switch)


func _on_btn() -> void:
	match str(_btn.get_meta("act", "")):
		"bind":
			## 周六闯关赛排队中不许绑定(可能换号; 会话还在为这个账号排队 —— 与「邮箱登录」同一种闸)。
			if MenuQueue.block_at(_host, MenuQueue.K_MAINSITE):
				return
			ML.start_link()
		"cancel":
			ML.cancel_link()
	_refresh()


func _on_switch_ok() -> void:
	if MenuQueue.block_at(_host, MenuQueue.K_MAINSITE):
		ML.decline_switch()
		return
	if not ML.confirm_switch():
		return
	if after_switch_hook.is_valid():
		after_switch_hook.call()
		return
	## 重开设置页(新账号的名字 / 玩家 ID)。★走 SceneNav.go, 不用 reload_current_scene(理由见设置页存档冲突框那条)。
	SceneNav.go(get_tree(), "res://scenes/Settings.tscn")
