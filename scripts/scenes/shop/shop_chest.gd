class_name ShopChest
extends RefCounted
## 商店左半【店主 + 宝箱】(2026-10-18 整页重做·第三版)。
##
## 用户 10-18:「整个页面就应该重做啊，没有任何游戏搞的这种浏览器网页感」→ 商店改成货铺场景;
##   接着「我并不觉得左边的阵容可以放在商店里吧」→ 选「店主 + 宝箱」:
##   商店只管买 / 卖 / 看; 买下的东西进宝箱(= 背包), 装到龟身上回背包页做。
## ⇒ 左半: 店主站在地毯上(待机轻晃) + 左下角宝箱(背景图里本来就有) 旁边一排已有装备。
##   只有点按, 没有拖拽(用户 10-18「为什么要拖入宝箱去购买？」): 点货架 → 说明卡 → 购买;
##   点宝箱里一件 → 详情 / 卖出。
## ★卖走背包页同一套 `InvOps`(私人池退张、羁绊赠送件不可卖、存盘都在里面)。
## ★触控尺寸(verify_ui_consistency「热区不足」): 宝箱格 81、按钮 81 高。
## ★照 CLAUDE.md §5 拆分模板: RefCounted + 构造注入宿主(ShopScene)。

## ── 店主 ──
const KEEPER_TEX = preload("res://assets/sprites/shop/shopkeeper.png")
const KEEPER_POS := Vector2(150.0, 236.0)
const KEEPER_SIZE := Vector2(352.0, 352.0)   # 原生 128 × 2.75
## ── 宝箱(背包) ──
const BENCH_X := 168.0        # 背景左下角宝箱(屏幕 0..160)右边的沙地上
const BENCH_Y := 590.0
const BENCH_CELL := 81.0       # = 44pt 触控下限
const BENCH_STEP := 89.0
const BENCH_PER_ROW := 6       # 6 × 89 = 534: 168..702

var host = null
static var _ell_cache: Dictionary = {}


func _init(h) -> void:
	host = h


## 像素椭圆(白色, 用 modulate 上色)。w×h 是原生像素, 显示时按 size 放大 —— 边缘是像素台阶, 不是矢量圆角
##   (verify_ui_consistency「圆角盒」= 网页味)。
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


# ══════════════════════════════════════════════════════════════
#  店主
# ══════════════════════════════════════════════════════════════

func build_keeper(parent: Control) -> void:
	var sh := ellipse(150.0, 22.0, 30, 5, Color(0.1, 0.05, 0.02, 0.45)); sh.name = "KeeperShadow"
	sh.position = KEEPER_POS + Vector2(KEEPER_SIZE.x * 0.5 - 75.0, KEEPER_SIZE.y - 30.0)
	parent.add_child(sh)
	var k := TextureRect.new(); k.name = "Shopkeeper"
	k.texture = KEEPER_TEX
	k.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	k.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	k.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	k.position = KEEPER_POS; k.size = KEEPER_SIZE
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(k)
	## 待机: 上下轻晃(呼吸感), 两帧之间整像素跳 —— 像素角色不做亚像素平滑位移
	var tw := TweenKit.loop_bound(host, k)
	tw.tween_property(k, "position:y", KEEPER_POS.y - 4.0, UIPalette.T_SET).set_trans(Tween.TRANS_SINE)
	tw.tween_property(k, "position:y", KEEPER_POS.y, UIPalette.T_SET).set_trans(Tween.TRANS_SINE)


# ══════════════════════════════════════════════════════════════
#  宝箱(背包)
# ══════════════════════════════════════════════════════════════

func build_bench(parent: Control) -> void:
	var bench: Array = GameState.persistent_bench
	var hd := Label.new(); hd.name = "BenchHeader"
	hd.text = ("背包 %d 件" % bench.size()) if bench.size() > 0 else "背包 · 空"
	hd.add_theme_font_size_override("font_size", 15); hd.add_theme_color_override("font_color", Color("#ffe3a3"))
	hd.add_theme_color_override("font_outline_color", Color("#1a0e05")); hd.add_theme_constant_override("outline_size", 5)
	hd.position = Vector2(40, BENCH_Y - 2); hd.size = Vector2(120, 22); hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hd)
	var overflow: bool = bench.size() > BENCH_PER_ROW
	var shown: int = (BENCH_PER_ROW - 1) if overflow else bench.size()
	for j in range(shown):
		var it: Dictionary = bench[j]
		var ed: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {})
		var sel: bool = j == int(host._sel_bench)
		var cell := Panel.new(); cell.name = "BenchCell%d" % j
		## 木格: 不透明深木底 + 费用色边(选中 = 金边); 冷青色金属槽框跟暖色货铺不搭
		var csb := StyleBoxFlat.new(); csb.bg_color = Color("#2a1a0e")
		csb.border_color = Color("#ffd93d") if sel else host._cost_color(int(ed.get("cost", 1)))
		csb.set_border_width_all(4 if sel else 3); csb.set_corner_radius_all(0)
		cell.add_theme_stylebox_override("panel", csb)
		cell.position = Vector2(BENCH_X + j * BENCH_STEP, BENCH_Y + 22.0); cell.size = Vector2(BENCH_CELL, BENCH_CELL)
		if sel:
			cell.position.y -= 8.0       # 拿起来了: 抬高一截, 槽框是金色
		parent.add_child(cell)
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
	## 选中一件: 「详情 / 卖出」两颗无框图标钮排在宝箱这一排的末尾(浮在上方会压到商人的袍子)
	var bi: int = int(host._sel_bench)
	if bi >= 0 and bi < shown:
		var it2: Dictionary = bench[bi]
		var acts: Array = [["LineupAct0", host.DETAIL_ICON, "详情", Callable(self, "_detail_bench")]]
		if not GameState.is_synergy_grant(it2):
			acts.append(["LineupAct1", host.SELL_ICON, "卖出 +%d" % int(host._inv_ops._sell_value(it2)), Callable(self, "_sell_bench")])
		var aw := 96.0
		var x0: float = minf(BENCH_X + shown * BENCH_STEP + 4.0, 704.0 - aw * acts.size())
		for k in range(acts.size()):
			var ab: Button = host._icon_button(acts[k][0], acts[k][1], acts[k][2],
				Vector2(x0 + k * aw, BENCH_Y + 4.0), Vector2(aw, 96))
			ab.z_index = 3
			ab.pressed.connect(acts[k][3])
			parent.add_child(ab)
	if overflow:
		var mb := Button.new(); mb.name = "BenchMore"
		mb.text = "+%d" % (bench.size() - shown)
		mb.add_theme_font_size_override("font_size", 22)
		mb.position = Vector2(BENCH_X + shown * BENCH_STEP, BENCH_Y + 22.0); mb.size = Vector2(BENCH_CELL, BENCH_CELL)
		mb.pressed.connect(func(): host._go_inventory())
		## 与宝箱格同一种木格(不用金木框按钮)
		for st in [["normal", "#2a1a0e"], ["hover", "#3a2414"], ["pressed", "#1e1209"], ["focus", "#2a1a0e"]]:
			var sb := StyleBoxFlat.new(); sb.bg_color = Color(st[1]); sb.border_color = Color("#8a5a32")
			sb.set_border_width_all(3); sb.set_corner_radius_all(0)
			mb.add_theme_stylebox_override(st[0], sb)
		mb.add_theme_color_override("font_color", Color("#ffe3a3"))
		parent.add_child(mb)


func _on_bench(j: int) -> void:
	host._sel_bench = -1 if int(host._sel_bench) == j else j
	host._sel = -1
	host._sel_own = ""
	host._rebuild()


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
