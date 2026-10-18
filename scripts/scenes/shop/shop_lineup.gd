class_name ShopLineup
extends RefCounted
## 商店【场地 + 储物箱 + 操作区】—— 商店整页重做(2026-10-18 第二刀)。
##
## 用户 10-18:「商店不够，你怎么参考的」「整个页面就应该重做啊，没有任何游戏搞的这种浏览器网页感」。
## 第一刀把背包页的列表原样搬进了商店右侧 = 表单。参考(背包乱斗 / The Bazaar / 超级自动宠物 /
## Underlords)的共同点是: 队伍是画面中心而且画得大、商品是实物配价签、拖到哪就买到 / 装到哪。
## ⇒ 这一刀:
##   · 左半是场地: 上 / 下战场各 3 个单位, **龟本身的全身立绘 + 待机动画**, 脚下 3 个装备格
##   · 底部储物箱: 没装上的装备(一行 7 件 + 「+N」)
##   · 右下操作区: 此刻该做什么 + 卸下 / 详情 / 卖出
##   · 拖拽: 货架 → 单位 = 买下并装上; 货架 → 储物箱 = 买下; 储物箱 → 单位 = 装上; 储物箱 → 货架 = 卖出
##   · 点选同样能完成全部操作(点了再点), 拖拽是快捷方式
## ★装/卸/卖全走背包页同一套 `InvOps`(上限两条、自动合成、羁绊赠送件、存盘都在里面)。
## ★触控尺寸(verify_ui_consistency「热区不足」= 短边 < 81 且长边 < 200): 单位 190×190、储物格 81、按钮 81 高。
## ★照 CLAUDE.md §5 拆分模板: RefCounted + 构造注入宿主(ShopScene)。

## ── 场地 ──
const FIELD_X := 80.0          # 第一列单位的左沿(左边 20..74 是竖排的「上战场 / 下战场」牌)
const LANE_Y := [96.0, 304.0]  # 上 / 下战场单位格的顶(脚 ≈ +116, 踩在背景两级台面上: 后排 173..233 / 前排 380..440)
const UNIT_W := 190.0
const UNIT_H := 190.0
const UNIT_STEP := 205.0
const SPRITE_BOX := 112.0      # 立绘 contain-fit 的方框
const SLOT := 44.0             # 装备格(只显示; 点整格单位)
const SLOT_STEP := 50.0
## ── 储物箱 ──
const BENCH_X := 40.0
const BENCH_Y := 548.0
const BENCH_CELL := 81.0       # = 44pt 触控下限
const BENCH_STEP := 89.0
const BENCH_PER_ROW := 7       # 7 × 89 = 623 ≤ 场地宽 650
## ── 右下操作区 ──
const ACT_X := 730.0
const ACT_W := 520.0
const ACT_HINT_Y := 556.0
const ACT_BTN_Y := 596.0
const ACT_BTN_H := 81.0
## 单位格里龟名那一行(门禁 verify_shop_layout NAME_NOT_TRUNCATED 穷举 28 只龟名量它)
const NAME_W := 182.0
const NAME_FONT := 16
const Phase2Minion = preload("res://scripts/gamedata/phase2_minion.gd")

var host = null
static var _ell_cache: Dictionary = {}


## 像素椭圆(白色, 用 modulate 上色)。w×h 是原生像素, 显示时按 scale 放大 —— 边缘是像素台阶, 不是矢量圆角。
static func ellipse_tex(w: int, h: int) -> Texture2D:
	var key := "%dx%d" % [w, h]
	if _ell_cache.has(key):
		return _ell_cache[key]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in range(h):
		for x in range(w):
			var dx := (x - cx) / (w * 0.5)
			var dy := (y - cy) / (h * 0.5)
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	_ell_cache[key] = tex
	return tex


static func ellipse(w_px: float, h_px: float, native_w: int, native_h: int, col: Color) -> TextureRect:
	var r := TextureRect.new()
	r.texture = ellipse_tex(native_w, native_h)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = Vector2(w_px, h_px)
	r.modulate = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 选中的单位(不在「待装」时点一个单位): {lane, idx}。空 = 没选。
var pick_eq: Dictionary = {}
## 本次重建出来的单位格 / 储物箱区: 拖动时只改它们的高亮, 不整页重建(重建会释放拖动源)。
var unit_tiles: Array = []     # [{lane, idx, node, hl}]
var bench_zone: Control = null


func _init(h) -> void:
	host = h


# ══════════════════════════════════════════════════════════════
#  规则(全部委托 GameState / InvOps, 这里只判断能不能)
# ══════════════════════════════════════════════════════════════

## 这个单位能不能接下 item。返回 "" = 能; 否则是不能的原因(短语)。item 为空 = 用背包里选中的那件。
func refuse_reason(unit: Dictionary, item: Dictionary = {}) -> String:
	if str(unit.get("kind", "")) == "leader" and str(unit.get("id", "")) == "":
		return "未选龟"
	var it: Dictionary = item
	if it.is_empty():
		var bench: Array = GameState.persistent_bench
		var bi: int = int(host._sel_bench)
		if bi < 0 or bi >= bench.size():
			return "没选装备"
		it = bench[bi]
	if GameState.is_synergy_grant(it) or str(it.get("kind", "")) == "item":
		return ""
	if GameState._cap_count(unit_equips(unit)) >= int(host.P2.UNIT_EQUIP_CAP):
		return "已满 3 件"
	if not GameState.team_has_equip_room():
		return "全队已满"
	return ""


func unit_equips(unit: Dictionary) -> Array:
	if str(unit.get("kind", "")) == "leader":
		var pe = GameState.persistent_equipped.get(str(unit.get("id", "")), []) if GameState.persistent_equipped is Dictionary else []
		return pe if pe is Array else []
	return unit.get("equips", []) if unit.get("equips", null) is Array else []


func _unit_at(lineup: Dictionary, lane: String, idx: int) -> Dictionary:
	var arr: Array = lineup.get(lane, [])
	return arr[idx] if idx >= 0 and idx < arr.size() and arr[idx] is Dictionary else {}


func _unit_name(unit: Dictionary) -> String:
	var kind := str(unit.get("kind", ""))
	var pid := str(unit.get("id", ""))
	if kind == "leader":
		if pid == "":
			return "统领%d" % (int(unit.get("slot", 0)) + 1)
		return str(DataRegistry.pet_by_id.get(pid, {}).get("name", pid))
	return "精英小将" if bool(unit.get("elite", false)) else "小将"


## 把背包第 bi 件装到 (lane, idx)。返回是否装上。
func equip_bench_to(lane: String, idx: int, bi: int) -> bool:
	var unit: Dictionary = _unit_at(GameState.get_dual_lineup(), lane, idx)
	if unit.is_empty() or bi < 0 or bi >= GameState.persistent_bench.size():
		return false
	var why := refuse_reason(unit, GameState.persistent_bench[bi])
	if why != "":
		host._toast(why)
		return false
	var n0: int = int(GameState.team_equipped_count())
	var b0: int = GameState.persistent_bench.size()
	host._sel_bench = bi
	if str(unit.get("kind", "")) == "leader":
		host._inv_ops._equip_to(str(unit.get("id", "")), bi)
	else:
		host._inv_ops._equip_minion(lane, idx, bi)
	return int(GameState.team_equipped_count()) > n0 or GameState.persistent_bench.size() < b0


# ══════════════════════════════════════════════════════════════
#  场地
# ══════════════════════════════════════════════════════════════

func build_field(parent: Control) -> void:
	unit_tiles = []
	var lineup: Dictionary = GameState.get_dual_lineup()
	var lanes := ["top", "bottom"]
	for li in range(2):
		var lk: String = lanes[li]
		var ly: float = LANE_Y[li]
		## 竖排牌子「上战场 / 下战场」
		var sign := Label.new(); sign.name = "LaneSign_%s" % lk
		sign.text = "上\n战\n场" if lk == "top" else "下\n战\n场"
		sign.add_theme_font_size_override("font_size", 18)
		sign.add_theme_color_override("font_color", Color("#ffe3a3"))
		sign.add_theme_color_override("font_outline_color", Color("#2a1608"))
		sign.add_theme_constant_override("outline_size", 6)
		sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sign.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sign.position = Vector2(22, ly + 30.0); sign.size = Vector2(48, UNIT_H - 60.0)
		sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(sign)
		var arr: Array = lineup.get(lk, [])
		for i in range(arr.size()):
			if arr[i] is Dictionary:
				_unit_tile(parent, Vector2(FIELD_X + i * UNIT_STEP, ly), lk, i, arr[i])


func _unit_tile(parent: Control, pos: Vector2, lane: String, idx: int, unit: Dictionary) -> void:
	var kind := str(unit.get("kind", ""))
	var pid := str(unit.get("id", ""))
	var is_ph: bool = kind == "leader" and pid == ""
	var arming: bool = int(host._sel_bench) >= 0
	var why: String = refuse_reason(unit) if arming else ""
	var ok: bool = arming and why == ""
	var picked: bool = not arming and str(pick_eq.get("lane", "")) == lane and int(pick_eq.get("idx", -1)) == idx

	var tile := Control.new(); tile.name = "LineupRow_%s_%d" % [lane, idx]
	tile.position = pos; tile.size = Vector2(UNIT_W, UNIT_H)
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(tile)

	## 脚下的地台光圈: 平时淡, 能接 / 选中时亮金。拖动时由宿主改它(见 set_drag_highlight)。
	var hl := ellipse(120.0, 20.0, 30, 5, Color(0.1, 0.05, 0.02, 0.45)); hl.name = "Halo"
	hl.position = Vector2(UNIT_W * 0.5 - 60.0, 102)
	tile.add_child(hl)
	_style_halo(hl, ok or picked, false)
	unit_tiles.append({"lane": lane, "idx": idx, "node": tile, "hl": hl, "unit": unit})

	## 全身立绘(待机动画) / 小将立绘 / 未选龟的问号
	var cx: float = UNIT_W * 0.5
	var cy: float = 60.0
	if is_ph:
		var q := Label.new(); q.text = "?"
		q.add_theme_font_size_override("font_size", 56); q.add_theme_color_override("font_color", Color("#9fb2c8"))
		q.add_theme_color_override("font_outline_color", Color("#0b1620")); q.add_theme_constant_override("outline_size", 8)
		q.position = Vector2(0, 10); q.size = Vector2(UNIT_W, 100)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE; tile.add_child(q)
	elif kind == "leader":
		_pet_sprite(tile, Vector2(cx, cy), DataRegistry.pet_by_id.get(pid, {}), SPRITE_BOX)
	else:
		var img := "res://assets/sprites/%s" % Phase2Minion.minion_img(bool(unit.get("elite", false)), str(unit.get("role", "front")) == "back")
		if ResourceLoader.exists(img):
			var a := TextureRect.new(); a.texture = load(img)
			a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; a.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			a.position = Vector2(cx - 46, cy - 46); a.size = Vector2(92, 92); a.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.add_child(a)
	if arming and not ok:
		tile.modulate = Color(1, 1, 1, 0.5)

	## 名字(描边字, 直接写在场地上, 不加底框)
	var nl := Label.new(); nl.name = "UnitName"; nl.text = _unit_name(unit)
	nl.add_theme_font_size_override("font_size", NAME_FONT)
	nl.add_theme_color_override("font_color", Color("#fff4dc"))
	nl.add_theme_color_override("font_outline_color", Color("#1a0e05")); nl.add_theme_constant_override("outline_size", 6)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.position = Vector2((UNIT_W - NAME_W) * 0.5, 120); nl.size = Vector2(NAME_W, 22)
	nl.clip_text = true; nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE; tile.add_child(nl)
	if arming and not ok:
		var wl := Label.new(); wl.name = "Refuse"; wl.text = why
		wl.add_theme_font_size_override("font_size", 14)
		wl.add_theme_color_override("font_color", Color("#ffb454"))
		wl.add_theme_color_override("font_outline_color", Color("#1a0e05")); wl.add_theme_constant_override("outline_size", 5)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wl.position = Vector2(0, 2); wl.size = Vector2(UNIT_W, 20)
		wl.mouse_filter = Control.MOUSE_FILTER_IGNORE; tile.add_child(wl)

	## 3 个装备格
	var eqs: Array = unit_equips(unit)
	var sx: float = (UNIT_W - (3.0 * SLOT_STEP - (SLOT_STEP - SLOT))) * 0.5
	for ci in range(int(host.P2.UNIT_EQUIP_CAP)):
		var cell := Panel.new(); cell.name = "Slot%d" % ci
		var has_it: bool = ci < eqs.size() and eqs[ci] is Dictionary
		var ed: Dictionary = {}
		var csb := StyleBoxFlat.new(); csb.set_corner_radius_all(0); csb.bg_color = Color("#0e1a26")
		if has_it:
			ed = DataRegistry.phase2_equipment_by_id.get(str((eqs[ci] as Dictionary).get("id", "")), {})
			csb.border_color = host._cost_color(int(ed.get("cost", 1))); csb.set_border_width_all(2)
		else:
			csb.border_color = Color("#3a2a1a"); csb.set_border_width_all(1)
		## 不套金属槽框: 44px 的格子装不下那圈边带, 星级会压在边带上(verify_ui_consistency「文字压边带」)。
		##   不透明底 + 费用色细边 —— 不是「半透明底 + 边框」那种网页盒。
		cell.add_theme_stylebox_override("panel", csb)
		cell.position = Vector2(sx + ci * SLOT_STEP, 144); cell.size = Vector2(SLOT, SLOT)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(cell)
		if has_it:
			var ic := EquipIcon.make(ed, Vector2(32, 28))
			ic.position = Vector2(6, 3); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(ic)
			var st := Label.new(); st.text = "★".repeat(int((eqs[ci] as Dictionary).get("star", 1)))
			st.add_theme_font_size_override("font_size", 10); st.add_theme_color_override("font_color", Color("#ffd93d"))
			st.position = Vector2(0, 30); st.size = Vector2(SLOT, 13); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			st.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(st)

	host._wire_tap(tile, func(): _on_row(lane, idx))
	tile.set_drag_forwarding(Callable(),
		func(_at: Vector2, data: Variant) -> bool: return _can_drop_on_unit(data, lane, idx),
		func(_at: Vector2, data: Variant) -> void: _drop_on_unit(data, lane, idx))


func _style_halo(hl: Control, on: bool, dim: bool) -> void:
	## 能接 / 选中: 脚下一圈亮金; 平时: 一团暗影
	hl.modulate = Color(1.0, 0.86, 0.32, 0.85) if on else Color(0.1, 0.05, 0.02, 0.45 if not dim else 0.2)


## 龟的全身立绘 + 待机动画(与图鉴 CodexScene._add_pet_portrait 同算法: 按 sprite 元数据切帧, contain-fit)。
func _pet_sprite(tile: Control, center: Vector2, pet: Dictionary, box: float) -> void:
	var img := "res://assets/sprites/%s" % str(pet.get("img", ""))
	if str(pet.get("img", "")) == "" or not ResourceLoader.exists(img):
		var av := "res://assets/sprites/avatars/%s.png" % str(pet.get("id", ""))
		if ResourceLoader.exists(av):
			var a := TextureRect.new(); a.texture = load(av)
			a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; a.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			a.position = center - Vector2(box, box) * 0.5; a.size = Vector2(box, box)
			a.mouse_filter = Control.MOUSE_FILTER_IGNORE; tile.add_child(a)
		return
	var tex: Texture2D = load(img)
	var spr := Sprite2D.new(); spr.name = "PetSprite"
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = center
	var meta = pet.get("sprite", null)
	if meta is Dictionary and (meta as Dictionary).has("frameW"):
		var fw: int = maxi(1, int(meta.get("frameW", tex.get_width())))
		var fh: int = maxi(1, int(meta.get("frameH", tex.get_height())))
		var hf: int = maxi(1, int(floor(float(tex.get_width()) / float(fw))))
		var vf: int = maxi(1, int(floor(float(tex.get_height()) / float(fh))))
		spr.frame = 0
		spr.hframes = hf; spr.vframes = vf; spr.frame = 0
		var total: int = hf * vf
		var idle_n: int = maxi(1, mini(int(meta.get("frames", total)), total - 1))
		var sf: float = minf(box / float(fw), box / float(fh))
		spr.scale = Vector2(sf, sf)
		if idle_n > 1:
			var dur_ms: float = float(meta.get("duration", 800))
			var fps: float = maxf(4.0, roundf(float(idle_n) * 1000.0 / maxf(200.0, dur_ms)))
			var tw := TweenKit.loop_on(spr)
			tw.tween_method(func(fr: float) -> void:
				spr.frame = int(fr) % maxi(1, mini(idle_n, int(spr.hframes) * int(spr.vframes)))
			, 0.0, float(idle_n), float(idle_n) / fps)
	else:
		var sf2: float = minf(box / float(maxi(1, tex.get_width())), box / float(maxi(1, tex.get_height())))
		spr.scale = Vector2(sf2, sf2)
	tile.add_child(spr)


# ══════════════════════════════════════════════════════════════
#  拖拽
# ══════════════════════════════════════════════════════════════

func _can_drop_on_unit(data: Variant, lane: String, idx: int) -> bool:
	if not (data is Dictionary):
		return false
	var unit: Dictionary = _unit_at(GameState.get_dual_lineup(), lane, idx)
	if unit.is_empty():
		return false
	var it: Dictionary = host._drag_item(data)
	return not it.is_empty() and refuse_reason(unit, it) == ""


func _drop_on_unit(data: Variant, lane: String, idx: int) -> void:
	var src := str((data as Dictionary).get("src", ""))
	if src == "shop":
		host._buy_and_equip(int(data.get("idx", -1)), lane, idx)
	elif src == "bench":
		if equip_bench_to(lane, idx, int(data.get("idx", -1))):
			host._toast("已装上")


## 拖动开始 / 结束: 只改高亮, 不重建。data 为 null = 结束。
func set_drag_highlight(data: Variant) -> void:
	var it: Dictionary = host._drag_item(data) if data is Dictionary else {}
	for t in unit_tiles:
		if not is_instance_valid(t["node"]):
			continue
		var can: bool = not it.is_empty() and refuse_reason(t["unit"], it) == ""
		_style_halo(t["hl"], can, not it.is_empty() and not can)
		(t["node"] as Control).modulate = Color(1, 1, 1, 0.5) if (not it.is_empty() and not can) else Color(1, 1, 1, 1)
	if bench_zone != null and is_instance_valid(bench_zone):
		var from_shop: bool = data is Dictionary and str(data.get("src", "")) == "shop"
		(bench_zone.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color("#ffe27a") if from_shop else Color("#7a4e2a")


# ══════════════════════════════════════════════════════════════
#  点选
# ══════════════════════════════════════════════════════════════

func _on_row(lane: String, idx: int) -> void:
	var unit: Dictionary = _unit_at(GameState.get_dual_lineup(), lane, idx)
	if unit.is_empty():
		return
	if int(host._sel_bench) < 0:
		var same: bool = str(pick_eq.get("lane", "")) == lane and int(pick_eq.get("idx", -1)) == idx
		pick_eq = {} if same else {"lane": lane, "idx": idx}
		host._sel = -1
		host._sel_own = ""
		host._rebuild()
		return
	if equip_bench_to(lane, idx, int(host._sel_bench)):
		host._toast("已装上")


func _unequip_at(ci: int) -> void:
	var lane := str(pick_eq.get("lane", ""))
	var idx: int = int(pick_eq.get("idx", -1))
	var u: Dictionary = _unit_at(GameState.get_dual_lineup(), lane, idx)
	if u.is_empty():
		pick_eq = {}
		host._rebuild(); return
	if str(u.get("kind", "")) == "leader":
		host._inv_ops._unequip_at(str(u.get("id", "")), ci)
	else:
		host._inv_ops._unequip_minion_at(lane, idx, ci)
	host._toast("已放回背包")


func _detail_bench() -> void:
	var bench: Array = GameState.persistent_bench
	var bi: int = int(host._sel_bench)
	if bi < 0 or bi >= bench.size():
		return
	host._on_select_own(str(bench[bi].get("id", "")), int(bench[bi].get("star", 1)))


func _sell_bench() -> void:
	sell_bench_at(int(host._sel_bench))


func sell_bench_at(bi: int) -> void:
	var bench: Array = GameState.persistent_bench
	if bi < 0 or bi >= bench.size():
		return
	if GameState.is_synergy_grant(bench[bi]):
		host._toast("羁绊赠送装备不可出售")
		return
	var sv: int = int(host._inv_ops._sell_value(bench[bi]))
	host._sel_bench = bi
	host._inv_ops._sell_selected()
	host._toast("已卖出 +%d" % sv)


# ══════════════════════════════════════════════════════════════
#  右下操作区: 此刻该做什么 + 按钮
# ══════════════════════════════════════════════════════════════

func build_actions(parent: Control) -> void:
	var lineup: Dictionary = GameState.get_dual_lineup()
	var used: int = int(GameState.team_equipped_count())
	var cap: int = int(GameState.team_equip_cap())
	var bench: Array = GameState.persistent_bench
	var bi: int = int(host._sel_bench)
	var sel_item: Dictionary = bench[bi] if bi >= 0 and bi < bench.size() else {}
	var pu: Dictionary = _unit_at(lineup, str(pick_eq.get("lane", "")), int(pick_eq.get("idx", -1)))
	if pu.is_empty():
		pick_eq = {}

	var cnt := Label.new(); cnt.name = "TeamEquipCount"
	cnt.text = "装备 %d/%d" % [used, cap]
	cnt.add_theme_font_size_override("font_size", 20)
	cnt.add_theme_color_override("font_color", Color("#ffb454") if used >= cap else Color("#ffe3a3"))
	cnt.add_theme_color_override("font_outline_color", Color("#1a0e05")); cnt.add_theme_constant_override("outline_size", 6)
	cnt.position = Vector2(ACT_X, ACT_HINT_Y); cnt.size = Vector2(120, 30)
	parent.add_child(cnt)
	var hint := Label.new(); hint.name = "LineupHint"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_outline_color", Color("#1a0e05")); hint.add_theme_constant_override("outline_size", 5)
	hint.position = Vector2(ACT_X + 126, ACT_HINT_Y + 2); hint.size = Vector2(ACT_W - 126, 28)
	hint.clip_text = true; hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var acts: Array = []   # [文字, Callable]
	if not sel_item.is_empty():
		var ed: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(sel_item.get("id", "")), {})
		var _free: bool = GameState.is_synergy_grant(sel_item) or str(sel_item.get("kind", "")) == "item"
		if not _free and not GameState.team_has_equip_room():
			hint.text = "全队已满 · 升级或先卸下一件"
			hint.add_theme_color_override("font_color", Color("#ffb454"))
		else:
			hint.text = "点一只龟装上「%s」" % str(ed.get("name", "?"))
			hint.add_theme_color_override("font_color", Color("#ffd93d"))
		acts.append(["详情", Callable(self, "_detail_bench")])
		if not GameState.is_synergy_grant(sel_item):
			acts.append(["卖出 +%d" % int(host._inv_ops._sell_value(sel_item)), Callable(self, "_sell_bench")])
	elif not pu.is_empty():
		var es: Array = unit_equips(pu)
		hint.text = ("%s · 还没有装备" % _unit_name(pu)) if es.is_empty() else ("%s · 选一件卸下" % _unit_name(pu))
		hint.add_theme_color_override("font_color", Color("#ffd93d"))
		for ci in range(es.size()):
			if es[ci] is Dictionary:
				var ed2: Dictionary = DataRegistry.phase2_equipment_by_id.get(str((es[ci] as Dictionary).get("id", "")), {})
				acts.append(["卸下\n%s" % str(ed2.get("name", "?")), Callable(self, "_unequip_at").bind(ci)])
	else:
		hint.text = "全队已满 · 升级可多装" if used >= cap else "拖装备到龟身上 · 等级越高可装越多"
		hint.add_theme_color_override("font_color", Color("#cfe4f0"))
	parent.add_child(hint)
	if acts.is_empty():
		return
	var bw: float = (ACT_W - 10.0 * float(acts.size() - 1)) / float(acts.size())
	for k in range(acts.size()):
		var ab := Button.new(); ab.name = "LineupAct%d" % k
		ab.text = str(acts[k][0])
		ab.add_theme_font_size_override("font_size", 16)
		ab.position = Vector2(ACT_X + k * (bw + 10.0), ACT_BTN_Y); ab.size = Vector2(bw, ACT_BTN_H)
		ab.clip_text = true
		ab.pressed.connect(acts[k][1])
		host._skin_button(ab); parent.add_child(ab)


# ══════════════════════════════════════════════════════════════
#  储物箱
# ══════════════════════════════════════════════════════════════

func build_bench(parent: Control) -> void:
	var bench: Array = GameState.persistent_bench
	## 整条储物箱是一个落点(货架拖到这里 = 只买下)
	var zone := Panel.new(); zone.name = "BenchZone"
	var zsb := StyleBoxFlat.new()
	## 木托盘: 深木色底 + 浅木色边(像素风不用圆角)。
	zsb.bg_color = Color("#2a190d")
	zsb.border_color = Color("#7a4e2a"); zsb.set_border_width_all(4); zsb.set_corner_radius_all(0)
	zone.add_theme_stylebox_override("panel", zsb)
	zone.position = Vector2(BENCH_X - 10, BENCH_Y - 6)
	zone.size = Vector2(BENCH_PER_ROW * BENCH_STEP + 12, 26 + BENCH_CELL + 14)
	zone.mouse_filter = Control.MOUSE_FILTER_PASS
	zone.set_drag_forwarding(Callable(),
		func(_at: Vector2, d: Variant) -> bool: return d is Dictionary and str(d.get("src", "")) == "shop",
		func(_at: Vector2, d: Variant) -> void: host._buy_to_bench(int(d.get("idx", -1))))
	parent.add_child(zone)
	bench_zone = zone
	var hd := Label.new(); hd.name = "BenchHeader"
	hd.text = ("背包 %d 件" % bench.size()) if bench.size() > 0 else "背包 · 空"
	hd.add_theme_font_size_override("font_size", 15); hd.add_theme_color_override("font_color", Color("#ffe3a3"))
	hd.add_theme_color_override("font_outline_color", Color("#1a0e05")); hd.add_theme_constant_override("outline_size", 5)
	hd.position = Vector2(BENCH_X, BENCH_Y); hd.size = Vector2(300, 22); hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hd)
	var overflow: bool = bench.size() > BENCH_PER_ROW
	var shown: int = (BENCH_PER_ROW - 1) if overflow else bench.size()
	for j in range(shown):
		var it: Dictionary = bench[j]
		var ed: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {})
		var sel: bool = j == int(host._sel_bench)
		var cell := Panel.new(); cell.name = "BenchCell%d" % j
		var csb := StyleBoxFlat.new(); csb.bg_color = Color("#162230")
		csb.border_color = Color("#ffd93d") if sel else host._cost_color(int(ed.get("cost", 1)))
		csb.set_border_width_all(3 if sel else 2); csb.set_corner_radius_all(0)
		cell.add_theme_stylebox_override("panel", UISkin.slot(csb, UISkin.tint_of(csb.border_color)))
		cell.position = Vector2(BENCH_X + j * BENCH_STEP, BENCH_Y + 24.0); cell.size = Vector2(BENCH_CELL, BENCH_CELL)
		parent.add_child(cell)
		if sel:
			cell.position.y -= 8.0       # 拿起来了: 抬高一截, 槽框是金色
		var ic := EquipIcon.make(ed, Vector2(44, 38))
		ic.position = Vector2(18, 13); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(ic)
		var st := Label.new(); st.text = "★".repeat(int(it.get("star", 1)))
		st.add_theme_font_size_override("font_size", 12); st.add_theme_color_override("font_color", Color("#ffd93d"))
		st.position = Vector2(16, 51); st.size = Vector2(BENCH_CELL - 32.0, 16); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(st)
		cell.tooltip_text = "%s ★%d" % [str(ed.get("name", "?")), int(it.get("star", 1))]
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var _j := j
		host._wire_tap(cell, func(): _on_bench(_j))
		cell.set_drag_forwarding(
			func(_at: Vector2) -> Variant: return host._begin_drag({"src": "bench", "idx": _j}, ed),
			Callable(), Callable())
	if overflow:
		var mb := Button.new(); mb.name = "BenchMore"
		mb.text = "+%d" % (bench.size() - shown)
		mb.add_theme_font_size_override("font_size", 18)
		mb.position = Vector2(BENCH_X + shown * BENCH_STEP, BENCH_Y + 24.0); mb.size = Vector2(BENCH_CELL, BENCH_CELL)
		mb.pressed.connect(func(): host._go_inventory())
		host._skin_button(mb); parent.add_child(mb)


func _on_bench(j: int) -> void:
	host._sel_bench = -1 if int(host._sel_bench) == j else j
	pick_eq = {}
	host._sel = -1
	host._sel_own = ""
	host._rebuild()
