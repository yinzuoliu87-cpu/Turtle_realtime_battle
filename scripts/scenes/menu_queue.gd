extends RefCounted
class_name MenuQueue
## 周六闯关赛排队中回到主菜单: 主按钮排队态 + 左侧取消键 + 锁(2026-10-29 · 方案书 docs/plans/20261029c-闯关赛排队时可回主页.md §4.1 · A7)。
## 从 MainMenuScene 拆出来(那边有 3000 行上限 `tools/arch_budget.py`): 模板照 menu_weekend.gd —— 构造注入主菜单, 那边只剩几行转调。
## 用户 10-29:「我认为用户在开战里锁定了后，还是能回到主页的，只是不能动背包商店，然后开始战斗你得变按钮，在边上也要有取消按钮」;
##   其余按方案书 §5 的建议做(用户「全部今天做完」= 未决点全按建议定, 下面这些**不是用户原话**):
##   取消键在主按钮左侧、不二次确认(U1 / U2); 另锁训龟大师 / 「?」教程 / 好友切磋 / 设置里的删号与邮箱登录(U4)。
##
## ★判据只有一个: `RefereeWatch.queue_locked()`(会话在 提交 / 排队 / 正在退出 / 已配上等进场)。
##   画锁、拦门、主按钮排队态、切磋与设置的拦截都只经 `locked()` 读它 —— 吸取商店锁「锁画在那儿门却是开的」那次的教训
##   (MainMenuScene `_build_page_buttons` 头注)。商店那扇门干脆并进 `_shop_block_kind`(第四条原因), 画与门天然同源。
## ★锁的样子与现有商店锁同一种: 压灰 + 像素锁 + 底边常驻短签「匹配中」; 点了弹现有被拦卡(`MenuWeekend.block_card`)。
##   左列方键直接走 `_square_entry(locked, reason)`(商店那一颗就是它画的); 训龟大师 / 「?」不是方键, 在原按钮上压灰 + 加锁与短签。
## ★会话(`RefereeRun.active`)的 `changed` 一响就重画, 另有 0.25 秒一拍(TICK_SEC): 刷「已等待」那一行、取消键的灰态,
##   并兜住「会话没发信号就没了」。锁态一变 ⇒ 重建左列 / 训龟大师 / 主按钮(不重播滑入), 出队那句(`RefereeWatch.notice`)当场飘。
## ★取消键借排队屏「取消匹配」那颗红键 + ✕(同一个意思; tools/asset_borrow_audit.py CROSS_OK 写了理由)。
##   主按钮排队态的面是这里按像素现画的(与亮黄面同一种画法, 换成冷色 = 「进行中」, 不是「快点我」), 不挂呼吸光晕。

const _RUN := preload("res://scripts/systems/replay/referee_run.gd")
const _RW := preload("res://scripts/systems/replay/referee_watch.gd")

## 取消键: 排队屏「取消匹配」那颗红键底座 + ✕(源图 1 倍, PixelKey 最近邻放大)
const KEY_RED := "res://assets/sprites/ui/replay_bar/key-red.png"
const KEY_RED_DOWN := "res://assets/sprites/ui/replay_bar/key-red-down.png"
const ICON_X := "res://assets/sprites/ui/queue_wait/icon-cancel-x.png"
const ICON_X_K := 5                       # ✕ 7×8 源像素 ×5 = 35×40, 落在 88 高的键面正中

## 被拦卡的说法分几种(句子末尾那半句按入口换)
const K_BAG := "bag"
const K_SHOP := "shop"
const K_TRAINER := "trainer"
const K_TUTORIAL := "tutorial"
const K_DELETE := "delete"
const K_RECOVER := "recover"

const TXT_MATCHING := "匹配中"            # 主按钮第一行 = 锁着的入口底边短签
const TXT_CANCELLING := "正在退出"        # 取消键按下后(灰)
const TXT_LEAD := "正在匹配闯关赛对手，阵容已锁定。"
const TXT_AFTER := {
	K_BAG: "取消匹配后可使用背包。",
	K_SHOP: "取消匹配后可使用商店。",
	K_TRAINER: "取消匹配后可设置训龟大师。",
	K_TUTORIAL: "取消匹配后可开始新手教程。",
	K_DELETE: "取消匹配后可删除账号。",
	K_RECOVER: "取消匹配后可使用邮箱登录。",
}
## 好友页那一行(Spar.my_side_check; 与「教程中无法切磋」同一种写法)
const TXT_SPAR := "闯关赛匹配中，无法切磋"

## 节点名(门禁按名字找)
const N_HERO := "QueueHero"
const N_FACE := "QueueHeroFace"
const N_LINE1 := "QueueHeroTitle"
const N_LINE2 := "QueueHeroWaited"
const N_CANCEL := "QueueCancelKey"
const N_TICK := "QueueMenuTick"
const N_DRESS := "QueueLockDress"
const TICK_SEC := 0.25
const KEY_GAP := 6.0                      # 取消键与排队面之间
const GRAY := Color(0.62, 0.58, 0.55)     # 压灰(= 商店锁方键底的那一档)
const NOTICE_MS := 3000                   # 出队后这么久之内会话补写的那句也照飘

var menu                                  # MainMenuScene
## 重建时不重播滑入(MainMenuScene `_slide_in*` 第一行读)
var quiet := false
## 【门禁注入点】主按钮排队态被点: 回排队屏。默认 = 会话那边的入口(玩家路径)。
var open_queue: Callable = _RUN.open_queue_screen
## 门禁读: 点主按钮排队态真去开排队屏的次数
var opens := 0
var _shown := false                       # 这一屏按哪种锁态画的
var _sess: Node = null                    # 连着 changed 的那个会话
var _tick: Timer = null
var _hero: Control = null
var _cancel: Button = null
var _l2: Label = null
var _help: Control = null
var _notice_until := 0
static var _face_tex: Texture2D = null


func _init(m) -> void:
	menu = m


## ══ 判据与文案(切磋 / 设置也从这里取) ══

static func locked() -> bool:
	return _RW.queue_locked()


static func why(kind: String) -> String:
	return TXT_LEAD + str(TXT_AFTER.get(kind, ""))


## 排队中 ⇒ 在 host 上弹被拦卡(与商店 / 开始战斗被拦同一张, `MenuWeekend.block_card`), 返回 true = 拦住了。
static func block_at(host: Node, kind: String) -> bool:
	if host == null or not locked():
		return false
	MenuWeekend.new(host).block_card(why(kind), [])
	return true


## 当前会话(没有 / 已释放 = null)。
static func session() -> Node:
	var s = _RUN.active
	if s == null or not is_instance_valid(s):
		return null
	return s as Node


## ══ 主菜单那几扇门 ══

## 锁着 ⇒ 弹卡; 没锁 ⇒ 照原来那一下走(主菜单那边仍写着原来的 `_go(...)`)。
func gate(kind: String, go: Callable) -> void:
	if not block_at(menu, kind):
		go.call()


func blocked(kind: String) -> bool:
	return block_at(menu, kind)


## 训龟大师那块木板: 排队中压灰 + 像素锁 + 底边短签; 点了弹卡(门在 `gate`)。
func dress_trainer(holder: Control) -> void:
	if not locked():
		return
	var sz: Vector2 = holder.size
	_dress(holder, Vector2(sz.x - 44.0 - 24.0, 9.0), 2.0, Rect2(Vector2((sz.x - 96.0) / 2.0, sz.y - 25.0), Vector2(96.0, 23.0)))


## 右上「?」: 记下来(锁态变了要摘 / 加), 当场按锁态画一次。
func dress_help(holder: Control) -> void:
	_help = holder
	_apply_help()


func _apply_help() -> void:
	if _help == null or not is_instance_valid(_help):
		return
	var old := _help.get_node_or_null(N_DRESS)
	if old != null:
		_help.remove_child(old)
		old.queue_free()
	for c in _help.get_children():
		if c is CanvasItem and str(c.name) != N_DRESS:
			(c as CanvasItem).self_modulate = Color.WHITE
	if locked():
		## 小键上「?」本身就是图标、没有名字那一行: 锁做成右上角的小角标(不盖住「?」), 短签挂在暗槽下沿(压不到「?」)。
		var vo: float = (float(menu.ICON_TAP) - float(menu.ICON_VIS)) / 2.0
		var vis: float = float(menu.ICON_VIS)
		_dress(_help, Vector2(vo + vis - 16.0, vo - 12.0), 2.0, Rect2(Vector2(vo - 4.0, vo + vis - 8.0), Vector2(vis + 8.0, 20.0)))


## 压灰(self_modulate: 不跟悬停改 modulate 打架)+ 像素锁 + 短签, 都挂在一个 N_DRESS 节点下(摘的时候整块摘)。
func _dress(holder: Control, lock_pos: Vector2, lock_k: float, tag: Rect2) -> void:
	for c in holder.get_children():
		if (c is NinePatchRect or c is Label or c is TextureRect) and str(c.name) != N_DRESS:
			(c as CanvasItem).self_modulate = GRAY
	var d := Control.new()
	d.name = N_DRESS
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.size = holder.size
	d.add_child(menu._pixel_lock(lock_pos, lock_k))
	d.add_child(menu._nine_rect("xpbar.png", Vector4(8, 8, 8, 8), tag))
	var rs: Label = menu._place_outlined(TXT_MATCHING, 14, Color("#ffe6b8"), tag.position, tag.size)
	rs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rs.name = menu.LOCK_REASON_NAME
	rs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_child(rs)
	holder.add_child(d)


## ══ 主按钮 ══

## `_build_page_buttons` 建主按钮之前调: 排队中 ⇒ 建排队态主按钮 + 左侧取消键, 返回 true(调用方不再建「开始战斗」)。
func build_hero() -> bool:
	_watch()
	_shown = locked()
	_hero = null
	_cancel = null
	_l2 = null
	if not _shown:
		return false
	var size: Vector2 = menu.HERO_SIZE
	var inset: Vector2 = menu.HERO_FACE_INSET
	## 木框照旧(同一颗主按钮, 只换里面那块面): 不传字、不当主 CTA(不铺亮黄面), 点它 = 回排队屏。
	var h: Control = menu._frame_button("", _on_hero_tap, false, size, int(menu.FONT_HERO))
	h.name = N_HERO
	h.position = menu.HERO_POS
	var fh: float = size.y - inset.y * 2.0
	## 左: 取消键 —— 与排队面同高的方键(主按钮里分出来: 右边贴屏幕右沿、左边 12 像素外是模式卡, 方案书 §2.12)
	var ck := PixelKey.HitButton.new()
	ck.name = N_CANCEL
	ck.pad = maxf(0.0, (PixelKey.HIT_PX - fh) / 2.0)
	PixelKey.skin(ck, KEY_RED, KEY_RED_DOWN, 0.0, PixelKey.ICON_KEY_BOTTOM)
	ck.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ck.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	ck.expand_icon = false
	ck.add_theme_font_override("font", menu._bold_font())      # 「正在退出」与主按钮同一种粗体
	ck.add_theme_font_size_override("font_size", 22)
	ck.add_theme_color_override("font_disabled_color", Color("#f2e8dc"))
	ck.add_theme_color_override("font_outline_color", Color("#2a2622"))
	ck.add_theme_constant_override("outline_size", 6)
	ck.position = inset
	ck.size = Vector2(fh, fh)
	ck.custom_minimum_size = ck.size
	ck.pressed.connect(_on_cancel)
	## 右: 排队面(冷色「进行中」) + 两行字
	var fx: float = inset.x + fh + KEY_GAP
	var fr := Rect2(Vector2(fx, inset.y), Vector2(size.x - inset.x - fx, fh))
	var face := NinePatchRect.new()
	face.name = N_FACE
	face.texture = face_tex()
	face.patch_margin_left = 8; face.patch_margin_top = 8; face.patch_margin_right = 8; face.patch_margin_bottom = 8
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.position = fr.position
	face.size = fr.size
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(face)
	var l1: Label = menu._menu_label(TXT_MATCHING, 34, Color("#eef5ff"))
	l1.name = N_LINE1
	_outline(l1, 10)
	l1.set_anchors_preset(Control.PRESET_TOP_LEFT)
	l1.position = fr.position + Vector2(0.0, 4.0)
	l1.size = Vector2(fr.size.x, 46.0)
	h.add_child(l1)
	var l2: Label = menu._menu_label("", 22, Color("#bcd2ea"))
	l2.name = N_LINE2
	_outline(l2, 6)
	l2.set_anchors_preset(Control.PRESET_TOP_LEFT)
	l2.position = fr.position + Vector2(0.0, 48.0)
	l2.size = Vector2(fr.size.x, 32.0)
	h.add_child(l2)
	h.add_child(ck)
	_hero = h
	_cancel = ck
	_l2 = l2
	menu._hero_btn = h
	menu._hero_locked = true          # 「点开始战斗」那条首次提示不指着它
	menu.page_box.add_child(h)
	menu._slide_in(h, 5)
	_paint()
	return true


func _outline(l: Label, px: int) -> void:
	l.add_theme_color_override("font_outline_color", Color("#0c1424"))
	l.add_theme_constant_override("outline_size", px)


## 排队态那块面: 与亮黄面(tools/build_menu_hud.py `cta_face`)同一种画法 —— 一圈深描边 + 顶 2 行高光 + 底 3 行压暗 +
##   左上两道斜亮痕, 64×32 ×2 最近邻; 换成冷钢蓝(「进行中」), 全屏唯一的亮黄留给能开打的那一刻。代码现画, 不落盘。
static func face_tex() -> Texture2D:
	if _face_tex != null:
		return _face_tex
	var w := 64
	var hh := 32
	var im := Image.create(w, hh, false, Image.FORMAT_RGBA8)
	var c_out := Color8(14, 22, 40)
	var c_hi := Color8(132, 168, 204)
	var c_body := Color8(54, 86, 126)
	var c_mid := Color8(46, 74, 110)
	var c_lo := Color8(34, 54, 84)
	for y in range(hh):
		for x in range(w):
			if (x == 0 or x == w - 1) and (y == 0 or y == hh - 1):
				continue                                   # 四角缺一格 = 像素圆角
			var c := c_body
			if x == 0 or y == 0 or x == w - 1 or y == hh - 1:
				c = c_out
			elif y <= 2:
				c = c_hi
			elif y >= hh - 4:
				c = c_lo
			elif y >= hh - 9:
				c = c_mid
			im.set_pixel(x, y, c)
	for x0 in [8, 13]:
		for k in range(6):
			if x0 + k < w - 1 and 3 + k < hh - 4:
				im.set_pixel(x0 + k, 3 + k, c_hi)
	im.resize(w * 2, hh * 2, Image.INTERPOLATE_NEAREST)
	_face_tex = ImageTexture.create_from_image(im)
	return _face_tex


## 排队态的字与取消键: 已等待(会话那一份, 0.25 秒一刷)/ 正在退出 ⇒ 取消键灰掉、换成「正在退出」。
func _paint() -> void:
	var s := session()
	if s == null:
		return
	if _l2 != null and is_instance_valid(_l2) and s.has_method("waited_now"):
		var t: String = _RW.queue_waited_text(int(s.waited_now()))
		if _l2.text != t:
			_l2.text = t
	if _cancel != null and is_instance_valid(_cancel):
		var cancelling: bool = str(s.get("state")) == _RW.ST_CANCEL
		if cancelling and not _cancel.disabled:
			_cancel.disabled = true
			_cancel.icon = null
			_cancel.text = TXT_CANCELLING.substr(0, 2) + "\n" + TXT_CANCELLING.substr(2)
		elif not cancelling and (_cancel.disabled or _cancel.icon == null):
			_cancel.disabled = false
			_cancel.text = ""
			_cancel.icon = PixelKey.up(ICON_X, ICON_X_K)


## 取消键: 不二次确认(U2)。回话(取消成功 / 来不及取消照配上)由会话发 changed, 这边跟着重画。
func _on_cancel() -> void:
	var s := session()
	if s == null or not locked() or not s.has_method("cancel_queue"):
		return
	s.cancel_queue()
	_paint()


## 主按钮排队态: 回排队屏(不经过选龟)。点下去那一刻**再判一次**会话还在排队(R7: 刚好收盘 / 刚好出队)。
func _on_hero_tap() -> void:
	if not locked():
		refresh()
		return
	opens += 1
	open_queue.call(menu.get_tree())


## ══ 跟着会话走 ══

func _watch() -> void:
	if _tick == null or not is_instance_valid(_tick):
		## ★挂在主菜单身上的 Timer(不是树级计时器): 主菜单没了它跟着没(tools/tree_timer_audit.py)。
		_tick = Timer.new()
		_tick.name = N_TICK
		_tick.wait_time = TICK_SEC
		_tick.autostart = true
		_tick.timeout.connect(_on_tick)
		menu.add_child(_tick)
	_bind()


func _bind() -> void:
	var s := session()
	if is_same(s, _sess):
		return
	if _sess != null and is_instance_valid(_sess) and _sess.is_connected("changed", _on_changed):
		_sess.disconnect("changed", _on_changed)
	_sess = s
	if s != null and s.has_signal("changed") and not s.is_connected("changed", _on_changed):
		s.connect("changed", _on_changed)


func _on_changed() -> void:
	refresh()


func _on_tick() -> void:
	_bind()
	refresh()
	if not _shown and Time.get_ticks_msec() < _notice_until:
		_say_notice()


## 锁态变了 ⇒ 重建; 没变且在排队 ⇒ 只刷字与取消键。
func refresh() -> void:
	if not is_instance_valid(menu) or not menu.is_inside_tree() or menu.page_box == null:
		return
	var lk := locked()
	if lk == _shown:
		if lk:
			_paint()
		return
	for c in menu.page_box.get_children():
		menu.page_box.remove_child(c)
		c.queue_free()
	quiet = true
	menu._build_page_buttons(menu._strip_now())
	quiet = false
	_apply_help()
	if not lk:
		## 出队了(取消成功 / 收盘 / 心跳断开): 主按钮已恢复「开始战斗」, 会话写的那句当场飘(人在别的页面时由主菜单 _ready 飘)。
		_notice_until = Time.get_ticks_msec() + NOTICE_MS
		_say_notice()


func _say_notice() -> void:
	if str(_RW.notice) != "":
		menu._toast(str(_RW.notice))
		_RW.notice = ""
