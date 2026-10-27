class_name QueueWaitView
extends Control
## 周六闯关赛「在线排队」等待屏(只在 MatchmakingScene 的周六服务器那一支里建; 积分赛的匹配屏不碰它)。
##
## ★由来(2026-10-27): 原来排队时停在「匹配中」雷达环那一屏, 只多三行字 + 一颗棕底「取消匹配」——
##   看不到自己锁定的阵容, 也看不到离晋级 / 出局还差几场。照 12 款商业「带战绩排队」画面的共同做法
##   (皇室战争经典挑战 / 万智牌精选轮抽 / Marvel Snap / 云顶 / 斯普拉遁战绩卡)改成:
##     标题「闯关赛  第 N 场」· 战绩格(胜 4 格圆、负 3 格菱形)· 我锁定的阵容卡(+ 锁徽记)VS 对手空位(剪影轮换 + 扫描亮带)·
##     已等待计时 · 红色取消键 · 水下底纹。用户看了方向稿与风格稿回「行吧」。
##   素材全是这一屏专门新画的(tools/build_replay_queue_ui.py → assets/sprites/ui/queue_wait/), ×3 最近邻;
##   取消键用回放条那一张红键底座(同一套键, asset_borrow_audit CROSS_OK 写了理由)。
##   用户 10-27 定: 排队屏去掉左上「←」, 只留「取消」(匹配屏那一侧收起它); 小字用正文字体。
## ★阵容卡画的是**交上去的那份快照**(`referee_run.lineup` = `RefereeWatch.my_snapshot()` 进队那一刻的那一份):
##   每一路按 `lane_assign`(统领)+ `minions`(小将)逐个画, 龟头像用游戏里的 `avatars/<id>.png`(与对局过场头像同一来源)。
## ★节点名(门禁 / 陪练号驱动 sim_driver 按名字找): QueueBox(本节点)/ QueueCell / QueueWaited / QueueCancel ——
##   与改之前同名; MatchmakingScene 的 QUEUE_* 常量就是这里的 N_*。

const S := 3                       # 源像素 → 屏幕像素
const FW := 1280.0                 # 设计框(与 MatchmakingScene.W / H 同一个)
const FH := 720.0

const BG := "res://assets/sprites/ui/queue_wait/bg.png"
const CELL_WIN := "res://assets/sprites/ui/queue_wait/cell-win.png"
const CELL_WIN_ON := "res://assets/sprites/ui/queue_wait/cell-win-on.png"
const CELL_LOSS := "res://assets/sprites/ui/queue_wait/cell-loss.png"
const CELL_LOSS_ON := "res://assets/sprites/ui/queue_wait/cell-loss-on.png"
const FRAME_ME := "res://assets/sprites/ui/queue_wait/frame-me.png"
const FRAME_FOE := "res://assets/sprites/ui/queue_wait/frame-foe.png"
const SOCKET := {
	"C": "res://assets/sprites/ui/queue_wait/socket-c.png",
	"B": "res://assets/sprites/ui/queue_wait/socket-b.png",
	"A": "res://assets/sprites/ui/queue_wait/socket-a.png",
	"S": "res://assets/sprites/ui/queue_wait/socket-s.png",
	"SS": "res://assets/sprites/ui/queue_wait/socket-ss.png",
	"minion": "res://assets/sprites/ui/queue_wait/socket-minion.png",
}
const SOCKET_FOE := "res://assets/sprites/ui/queue_wait/socket-foe.png"
const LOCK := "res://assets/sprites/ui/queue_wait/lock.png"
const QMARK := "res://assets/sprites/ui/queue_wait/qmark.png"
const SIL_ATLAS := "res://assets/sprites/ui/queue_wait/sil-atlas.png"
const SCAN := "res://assets/sprites/ui/queue_wait/scan.png"
const ICON_CANCEL_X := "res://assets/sprites/ui/queue_wait/icon-cancel-x.png"
## 取消键 = 回放条的红键底座(同一套键)
const KEY_RED := "res://assets/sprites/ui/replay_bar/key-red.png"
const KEY_RED_DOWN := "res://assets/sprites/ui/replay_bar/key-red-down.png"
## 小将头像(游戏真内容; 与对局过场 dual_lane_flow 的小将头像同一张)
const MINION_AVATAR := "res://assets/sprites/pets/minion.png"
## 剪影图集里的格序(与 tools/build_replay_queue_ui.py SIL_IDS 同一张表, 门禁 verify_replay_queue_art 对账)
const SIL_IDS := ["candy", "hunter", "space", "stone", "ghost", "rainbow", "hiding", "angel",
	"lightning", "ice", "crystal", "gambler", "fortune", "bamboo", "basic", "diamond"]
const SIL_PX := 18

## 卡框(源像素): 九宫格边距 左 上 右 下 = 4 19 4 4; 名牌带在 4~16 行; 路名一列 32; 槽 24、槽距 3、两路之间 4
const FRAME_MARGIN := [4, 19, 4, 4]
const CARD_H := 86
const LABEL_COL := 32
const SLOT := 24
const SLOT_GAP := 3
const CARD_GAP := 132.0            # 两张卡之间(放 VS)
## 对手空位: 扫描亮带 4 帧(每帧 StageCeremony.BURST_STEP 秒, 与晋级仪式光效逐帧同一个节拍), 剪影每 2 帧换一组
const SCAN_ROWS := [24, 39, 54, 69]

const TXT_TITLE := "闯关赛  第 %d 场"
const TXT_WIN_LEFT := "再赢 %d 场晋级决赛日"
const TXT_LOSS_LEFT := "再输 %d 场出局"
const TXT_LOCKED := "已锁定"
const TXT_TOP := "上路战场"
const TXT_BOTTOM := "下路战场"

const COL_CREAM := Color("#f6eed6")
const COL_SUB := Color("#96a8c0")
const COL_GOLD_HI := Color("#ffee92")
const COL_FOE_TXT := Color("#cebeec")
const COL_FOE_SUB := Color("#9684b6")
const COL_INK := Color("#070b16")
const COL_RED_LIP := Color("#62121a")

## 节点名
const N_BOX := "QueueBox"
const N_CELL := "QueueCell"            # 「正在寻找 X 胜 Y 负的对手」(对手空位的名牌带)
const N_WAITED := "QueueWaited"
const N_CANCEL := "QueueCancel"
const N_TITLE := "QueueTitle"
const N_WIN := "QueueWin_"             # + 下标
const N_LOSS := "QueueLoss_"
const N_MY_CARD := "QueueMyCard"
const N_MY_UNIT := "QueueMyUnit_"      # + 下标: 我锁定的阵容里的每一个单位(头像)
const N_LOCK := "QueueLock"
const N_FOE_CARD := "QueueFoeCard"
const N_FOE_SIL := "QueueFoeSil_"
const N_SCAN := "QueueScan"
const META_ON := "on"                  # 战绩格亮着(已胜 / 已负)

var frame: Control = null              # 设计框(与 content_root 同位置)
var cancel_btn: Button = null
var waited_lb: Label = null
var cell_lb: Label = null
var _bg: TextureRect = null
var _sils: Array = []                  # [TextureRect(AtlasTexture), 行, 列]
var _scan: TextureRect = null
var _tick := 0
var _card_w := 134                      # 卡宽(源像素), 按最多那一路的单位数算
var _title: Label = null
var _win_cells: Array = []
var _loss_cells: Array = []
var _h_win: Label = null
var _h_loss: Label = null
var _wins_in := 4
var _losses_out := 3
var _gwid := 0
var _glid := 0
var _x0 := 0.0
var _lx0 := 0.0
var _cell := Vector2i(-1, -1)


## lineup = 交上去的那份快照; cell = (gw, gl); wins_in / losses_out = 赛制(晋级 / 出局的场数)。
func build(lineup: Dictionary, cell: Vector2i, wins_in: int, losses_out: int) -> void:
	name = N_BOX
	mouse_filter = Control.MOUSE_FILTER_STOP            # 盖住下面那一屏(雷达环 / 左上「←」): 这一屏只留「取消」一个出口
	_bg = PixelKey.sprite(BG)
	add_child(_bg)
	frame = Control.new()
	frame.name = "QueueFrame"
	frame.size = Vector2(FW, FH)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var lanes := _lanes_of(lineup)
	var most := 3
	for ln in lanes:
		most = maxi(most, (ln as Array).size())
	_card_w = 4 + 6 + LABEL_COL + 4 + most * SLOT + (most - 1) * SLOT_GAP + 6 + 4
	_wins_in = wins_in
	_losses_out = losses_out
	var y := 90.0
	## 标题(像素标题字 36 号, 描边 12 = 每边一个源像素 §4.1-5)
	_title = _lbl("", 36, COL_CREAM)
	_title.name = N_TITLE
	UISkin.title_label(_title, 36)
	_title.add_theme_color_override("font_outline_color", COL_INK)
	_title.add_theme_constant_override("outline_size", 12)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size = Vector2(FW, 48)
	_title.position = Vector2(0, y)
	frame.add_child(_title)
	y += 48 + 9
	## 战绩格: 胜 wins_in 格(圆)+ 负 losses_out 格(菱形), 亮的格数 = 已胜 / 已负(set_record 里刷)
	var cw := 13 * S
	_gwid = wins_in * cw + (wins_in - 1) * 3 * S
	_glid = losses_out * cw + (losses_out - 1) * 3 * S
	_x0 = float(int((FW - (_gwid + 12 * S + _glid)) / 2.0 / S) * S)
	for i in range(wins_in):
		var c := PixelKey.sprite(CELL_WIN)
		c.name = N_WIN + str(i)
		c.position = Vector2(_x0 + i * (cw + 3 * S), y)
		frame.add_child(c)
		_win_cells.append(c)
	_lx0 = _x0 + _gwid + 12 * S
	for i in range(losses_out):
		var c := PixelKey.sprite(CELL_LOSS)
		c.name = N_LOSS + str(i)
		c.position = Vector2(_lx0 + i * (cw + 3 * S), y)
		frame.add_child(c)
		_loss_cells.append(c)
	y += cw + 9
	## 两句提示, 各自对齐在自己那一组格子下面
	_h_win = _lbl("", 20, COL_SUB)
	_h_loss = _lbl("", 20, COL_SUB)
	for h in [_h_win, _h_loss]:
		(h as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		(h as Label).position.y = y
		frame.add_child(h)
	set_record(cell)
	y += 28 + 24
	## 两张卡 + VS
	var card_px := float(_card_w * S)
	var cxl := float(int((FW - (card_px * 2.0 + CARD_GAP)) / 2.0 / S) * S)
	var cxr := cxl + card_px + CARD_GAP
	_build_my_card(lineup, lanes, Vector2(cxl, y))
	_build_foe_card(Vector2(cxr, y))
	var vs := _lbl("VS", 64, Color("#ffd65a"))
	vs.name = "QueueVs"
	vs.add_theme_color_override("font_outline_color", COL_INK)
	vs.add_theme_constant_override("outline_size", 16)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs.size = Vector2(CARD_GAP, CARD_H * S)
	vs.position = Vector2(cxl + card_px, y)
	frame.add_child(vs)
	y += CARD_H * S + 22
	## 已等待(正文; 文字由匹配屏每 0.25 秒刷)
	waited_lb = _lbl("", 26, Color("#c9d6e4"))
	waited_lb.name = N_WAITED
	waited_lb.add_theme_color_override("font_outline_color", COL_INK)
	waited_lb.add_theme_constant_override("outline_size", 6)
	waited_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waited_lb.size = Vector2(FW, 36)
	waited_lb.position = Vector2(0, y)
	frame.add_child(waited_lb)
	y += 36 + 14
	## 取消键: 红键底座九宫格拉宽 + 小 X + 字(正文)。看起来 54 高, 可点 84 高。
	var bt := PixelKey.HitButton.new()
	bt.name = N_CANCEL
	bt.pad = (PixelKey.HIT_PX - 18.0 * S) / 2.0
	PixelKey.skin(bt, KEY_RED, KEY_RED_DOWN, 18.0, 6.0)
	bt.icon = PixelKey.up(ICON_CANCEL_X)
	bt.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
	bt.add_theme_constant_override("h_separation", 10)
	bt.add_theme_font_size_override("font_size", 24)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		bt.add_theme_color_override(k, COL_CREAM)
	bt.add_theme_color_override("font_disabled_color", Color("#cdbfb4"))
	bt.add_theme_color_override("font_outline_color", COL_RED_LIP)
	bt.add_theme_constant_override("outline_size", 6)
	bt.position = Vector2(0, y)
	frame.add_child(bt)
	cancel_btn = bt
	## 动: 扫描亮带逐帧下移、剪影每 2 帧换一组
	var tk := Timer.new()
	tk.name = "QueueAnim"
	tk.wait_time = StageCeremony.BURST_STEP
	tk.autostart = true
	tk.timeout.connect(_step)
	add_child(tk)
	_step_to(0)


## 视口变了: 底纹底边对齐、水平居中(盖满任何比例); 设计框跟着匹配屏的 content_root 走。
func relayout(vp: Vector2, frame_pos: Vector2) -> void:
	position = Vector2.ZERO
	size = vp
	if _bg != null:
		_bg.position = Vector2(roundf((vp.x - _bg.size.x) / 2.0), vp.y - _bg.size.y)
	if frame != null:
		frame.position = frame_pos


## 取消键的字与灰态(排队中「取消匹配」/ 正在退出「正在退出排队」灰); 宽按字重算, 居中。
func set_cancel(t: String, disabled: bool) -> void:
	if cancel_btn == null:
		return
	if cancel_btn.text != t:
		cancel_btn.text = t
	cancel_btn.disabled = disabled
	var f := cancel_btn.get_theme_font("font")
	var tw: float = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, cancel_btn.get_theme_font_size("font_size")).x
	var w: float = ceilf((18.0 + 7.0 * S + 10.0 + tw + 18.0) / S) * S
	cancel_btn.size = Vector2(maxf(w, 44.0 * S), 18.0 * S)
	cancel_btn.custom_minimum_size = cancel_btn.size
	cancel_btn.position.x = float(int((FW - cancel_btn.size.x) / 2.0 / S) * S)


## 战绩(gw, gl): 标题第几场、亮几格、两句「再赢 / 再输」。服务端心跳里格子变了就再调一次。
func set_record(cell: Vector2i) -> void:
	_cell = cell
	if _title != null:
		_title.text = TXT_TITLE % (maxi(0, cell.x) + maxi(0, cell.y) + 1)
	for i in range(_win_cells.size()):
		var on := i < cell.x
		(_win_cells[i] as TextureRect).texture = load(CELL_WIN_ON if on else CELL_WIN)
		(_win_cells[i] as TextureRect).set_meta(META_ON, on)
	for i in range(_loss_cells.size()):
		var on := i < cell.y
		(_loss_cells[i] as TextureRect).texture = load(CELL_LOSS_ON if on else CELL_LOSS)
		(_loss_cells[i] as TextureRect).set_meta(META_ON, on)
	for pair in [[_h_win, TXT_WIN_LEFT % maxi(0, _wins_in - cell.x), _x0, _gwid],
			[_h_loss, TXT_LOSS_LEFT % maxi(0, _losses_out - cell.y), _lx0, _glid]]:
		var h: Label = pair[0]
		if h == null:
			continue
		h.text = str(pair[1])
		var hw: float = h.get_theme_font("font").get_string_size(h.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 4.0
		h.size = Vector2(hw, 28)                            # 框 = 字宽: 两句的框不叠
		h.position.x = roundf(float(pair[2]) + float(pair[3]) / 2.0 - hw / 2.0)


## 现在画的战绩(门禁对账: 亮的格数 = 胜 / 负场数)。
func record() -> Vector2i:
	return _cell


## 对手名牌带那一句(「正在寻找 X 胜 Y 负的对手」)。
func set_cell_text(t: String) -> void:
	if cell_lb != null and cell_lb.text != t:
		cell_lb.text = t


# ─────────────────────────────── 两张卡 ───────────────────────────────

## 快照里每一路的单位: [[{kind, id, rarity}...](上路), [...](下路)]。统领按 lane_assign, 小将按 minions 的个数。
static func _lanes_of(lineup: Dictionary) -> Array:
	var out: Array = []
	var la: Dictionary = lineup.get("lane_assign", {}) if lineup.get("lane_assign") is Dictionary else {}
	var mi: Dictionary = lineup.get("minions", {}) if lineup.get("minions") is Dictionary else {}
	for lane in ["top", "bottom"]:
		var row: Array = []
		for pid in (la.get(lane, []) if la.get(lane) is Array else []):
			var pet: Dictionary = DataRegistry.pet_by_id.get(str(pid), {})
			row.append({"kind": "leader", "id": str(pid), "rarity": str(pet.get("rarity", "C"))})
		for _m in (mi.get(lane, []) if mi.get(lane) is Array else []):
			row.append({"kind": "minion", "id": "", "rarity": "minion"})
		out.append(row)
	return out


## 快照里一共几个单位(门禁: 卡上画的头像数 = 这个数)。
static func unit_count(lineup: Dictionary) -> int:
	var n := 0
	for row in _lanes_of(lineup):
		n += (row as Array).size()
	return n


func _card(path: String, pos: Vector2, nm: String) -> NinePatchRect:
	var c := NinePatchRect.new()
	c.name = nm
	c.texture = PixelKey.up(path)
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.patch_margin_left = FRAME_MARGIN[0] * S
	c.patch_margin_top = FRAME_MARGIN[1] * S
	c.patch_margin_right = FRAME_MARGIN[2] * S
	c.patch_margin_bottom = FRAME_MARGIN[3] * S
	c.position = pos
	c.size = Vector2(_card_w * S, CARD_H * S)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(c)
	return c


## 第 row 路、第 col 格的槽左上角(卡内屏幕像素)。
func _slot_pos(row: int, col: int) -> Vector2:
	return Vector2((4 + 6 + LABEL_COL + 4 + col * (SLOT + SLOT_GAP)) * S, (19 + 5 + row * (SLOT + 4)) * S)


func _lane_label(card: Control, row: int, t: String, col: Color) -> void:
	var lb := _lbl(t, 20, col)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.size = Vector2(LABEL_COL * S, SLOT * S)
	lb.position = Vector2((4 + 6) * S, _slot_pos(row, 0).y)
	card.add_child(lb)


func _header_label(card: Control, t: String, col: Color, fs: int, x: float, w: float) -> Label:
	var lb := _lbl(t, fs, col)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.size = Vector2(w, 13 * S)
	lb.position = Vector2(x, 4 * S)
	lb.clip_text = true
	lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(lb)
	return lb


func _build_my_card(lineup: Dictionary, lanes: Array, pos: Vector2) -> void:
	var card := _card(FRAME_ME, pos, N_MY_CARD)
	var prof: Dictionary = lineup.get("profile", {}) if lineup.get("profile") is Dictionary else {}
	var cw := float(_card_w * S)
	var lock := PixelKey.sprite(LOCK)
	lock.name = N_LOCK
	lock.position = Vector2(cw - (4 + 11) * S, -4 * S)       # 压在卡框右上角、探出卡顶 4 源像素(像一枚封印)
	var lt := _lbl(TXT_LOCKED, 20, COL_GOLD_HI)
	lt.name = "QueueLockedText"
	card.add_child(lt)                                       # 先进树再量(§8-3)
	var ltw: float = lt.get_theme_font("font").get_string_size(TXT_LOCKED, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	lt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lt.size = Vector2(ltw + 4.0, 13 * S)
	lt.position = Vector2(lock.position.x - 8.0 - lt.size.x, 4 * S)
	## 名字 = 玩家昵称(快照里交上去的那个名字), 正文 32 号(拉丁 / 数字走 m6x11 原生 ×2)
	_header_label(card, str(prof.get("name", "")), COL_CREAM, 32, 10.0 * S, lt.position.x - 10.0 * S - 12.0)
	var k := 0
	for r in range(2):
		_lane_label(card, r, TXT_TOP if r == 0 else TXT_BOTTOM, COL_CREAM)
		var row: Array = lanes[r] if r < lanes.size() else []
		for c in range(row.size()):
			var u: Dictionary = row[c]
			var sp := _slot_pos(r, c)
			var rar := str(u["rarity"])
			if rar == "SSS":
				rar = "SS"                                    # 与游戏稀有度色同一档(SS / SSS 都是金)
			var sk := PixelKey.sprite(str(SOCKET.get(rar, SOCKET["C"])))
			sk.position = sp
			card.add_child(sk)
			var path: String = MINION_AVATAR if str(u["kind"]) == "minion" else "res://assets/sprites/avatars/%s.png" % str(u["id"])
			if not ResourceLoader.exists(path):
				path = "res://assets/sprites/pets/%s.png" % str(u["id"])      # 无头像退回全身图(与 dual_lane_flow 同)
			var av := TextureRect.new()
			av.name = N_MY_UNIT + str(k)
			av.texture = load(path) if ResourceLoader.exists(path) else null
			av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			av.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			av.mouse_filter = Control.MOUSE_FILTER_IGNORE
			av.position = sp + Vector2(3 * S, 3 * S)
			av.size = Vector2((SLOT - 6) * S, (SLOT - 6) * S)
			av.set_meta("unit", str(u["kind"]) + ":" + str(u["id"]))
			card.add_child(av)
			k += 1
	card.add_child(lock)                                    # 最后加: 压在卡框上面


func _build_foe_card(pos: Vector2) -> void:
	var card := _card(FRAME_FOE, pos, N_FOE_CARD)
	var q := PixelKey.sprite(QMARK)
	q.position = Vector2(10 * S, 4 * S + roundf((13 * S - q.size.y) / 2.0))
	card.add_child(q)
	var x := q.position.x + q.size.x + 12.0
	cell_lb = _header_label(card, "", COL_FOE_TXT, 20, x, _card_w * S - x - 10.0 * S)
	cell_lb.name = N_CELL
	var atlas := load(SIL_ATLAS) as Texture2D
	for r in range(2):
		_lane_label(card, r, TXT_TOP if r == 0 else TXT_BOTTOM, COL_FOE_SUB)
		for c in range(3):
			var sp := _slot_pos(r, c)
			var sk := PixelKey.sprite(SOCKET_FOE)
			sk.position = sp
			card.add_child(sk)
			var at := AtlasTexture.new()
			at.atlas = atlas
			var tr := TextureRect.new()
			tr.name = N_FOE_SIL + str(r * 3 + c)
			tr.texture = at
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.position = sp + Vector2(3 * S, 3 * S)
			tr.size = Vector2(SIL_PX * S, SIL_PX * S)
			card.add_child(tr)
			_sils.append([tr, r, c])
	## 扫描亮带: 两行「加亮」(BLEND_ADD, 光不描边 §4.3), 只在面板里(不碰边框)
	_scan = PixelKey.sprite(SCAN)
	_scan.name = N_SCAN
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_scan.material = mat
	_scan.position = Vector2(4 * S, SCAN_ROWS[0] * S)
	_scan.size = Vector2((_card_w - 8) * S, 2 * S)
	card.add_child(_scan)


# ─────────────────────────────── 动 ───────────────────────────────

func _step() -> void:
	_step_to(_tick + 1)


## 第 t 帧: 扫描亮带在第 t % 4 格; 剪影组 = t / 2(每 2 帧换一组, 一直换)。
func _step_to(t: int) -> void:
	_tick = t
	if _scan != null:
		_scan.position.y = SCAN_ROWS[t % SCAN_ROWS.size()] * S
	var g := t / 2
	for s in _sils:
		var tr: TextureRect = s[0]
		var idx: int = (g * 5 + int(s[1]) * 3 + int(s[2]) * 7) % SIL_IDS.size()
		(tr.texture as AtlasTexture).region = Rect2(idx * SIL_PX, 0, SIL_PX, SIL_PX)
		tr.set_meta("sil", SIL_IDS[idx])


## 现在这一帧 6 个剪影各是谁(门禁量「剪影在换」)。
func sil_ids() -> Array:
	var out: Array = []
	for s in _sils:
		out.append(str((s[0] as TextureRect).get_meta("sil", "")))
	return out


func _lbl(t: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
