extends Node
## verify_replay_queue_art.gd — 回放操作条 + 闯关排队等待屏的专用像素素材门禁(2026-10-27, 用户看了风格稿回「行吧」)
##
## 图: tools/build_replay_queue_ui.py 生成, 存 1 倍源图(assets/sprites/ui/replay_bar/、queue_wait/);
##   运行时 PixelKey 最近邻 ×3(scripts/util/pixel_key.gd); 回放条 replay_controls.gd、等待屏 queue_wait_view.gd。
##   ① 表对账: 两个目录里的每一张 png 都被代码按完整路径引用(没有孤儿), 代码里引用的每一张都在盘上、能加载
##   ② 1 倍源图、真像素画: alpha 只有 0 / 255(硬边、零半透明)、每张 ≤ 64 色(tools/pixel_art_audit.py 的判据)
##   ③ 剪影图集: 格序表 QueueWaitView.SIL_IDS == 生成脚本 SIL_IDS, 图集宽 = 18 × 只数
##   ④ PixelKey.up 逐像素 = 源图 ×3 最近邻(整数倍、不糊)
##   ⑤ 真建等待屏(快照 = RefereeWatch.my_snapshot(), 与进队交上去的同一个构造):
##      阵容卡头像数 = 快照单位数(另起一份独立数法)、亮的战绩格 = 胜 / 负场数(换一组战绩再量)、剪影隔帧在换、
##      取消键皮 = 红键底座 ×3、贴图件尺寸都是源图 ×3
##   ⑥ 两个视口(1560×720 手机 / 1280×960 iPad)里: 标题 / 战绩格 / 两张卡 / VS / 已等待 / 取消键 互不相交、都在屏内,
##      底纹盖满整屏
##   ⑦ 尺子自检: 硬边判据对一张带半透明像素的图要判「不是硬边」; 计数法对「少画一个单位」要数出差
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_replay_queue_art.tscn --quit-after 3000

const GEN := "res://tools/build_replay_queue_ui.py"
const DIRS := ["res://assets/sprites/ui/replay_bar/", "res://assets/sprites/ui/queue_wait/"]
const CODE := ["res://scripts/scenes/battle/replay_controls.gd", "res://scripts/scenes/queue_wait_view.gd"]
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

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
	print("=== 回放条 + 排队等待屏 专用像素素材 ===")
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true                                  # 不许写真存档
	_t_table()
	_t_hard_edges()
	_t_sil_table()
	_t_upscale()
	await _t_view(gs)
	_t_ruler()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 回放条 / 排队等待屏素材" if _fail == 0 and _n >= 20 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _pngs() -> Array:
	var out: Array = []
	for d in DIRS:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.ends_with(".png"):
				out.append(d + f)
	out.sort()
	return out


# ① 表对账
func _t_table() -> void:
	var files := _pngs()
	var code := ""
	for c in CODE:
		code += FileAccess.get_file_as_string(c)
	var orphan: Array = []
	for f in files:
		if code.find(str(f)) < 0:
			orphan.append(str(f).get_file())
	_ok("① 分母: 两个目录里 %d 张 png" % files.size(), files.size() >= 30)
	_ok("① ★每一张都被代码按完整路径引用(没有孤儿素材)", orphan.is_empty(), str(orphan))
	var rx := RegEx.create_from_string("res://assets/sprites/ui/(?:replay_bar|queue_wait)/[A-Za-z0-9_\\-]+\\.png")
	var refs: Array = []
	for m in rx.search_all(code):
		if not refs.has(m.get_string()):
			refs.append(m.get_string())
	var missing: Array = []
	for r in refs:
		if not ResourceLoader.exists(str(r)) or load(str(r)) == null:
			missing.append(str(r).get_file())
	_ok("① 代码里引用的 %d 张都在盘上、能加载" % refs.size(), refs.size() >= 30 and missing.is_empty(), str(missing))


## 一张图的 (alpha 的取值集合, 不透明像素的颜色数)。
func _profile(img: Image) -> Array:
	var a := {}
	var cols := {}
	var im := img.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	for y in range(im.get_height()):
		for x in range(im.get_width()):
			var c := im.get_pixel(x, y)
			var ai := int(round(c.a * 255.0))
			a[ai] = true
			if ai > 0:
				cols[c.to_html(false)] = true
	return [a.keys(), cols.size()]


# ② 1 倍源图、真像素画
func _t_hard_edges() -> void:
	var soft: Array = []
	var many: Array = []
	var n := 0
	for f in _pngs():
		var img := (load(str(f)) as Texture2D).get_image()
		var pr := _profile(img)
		n += 1
		for av in pr[0]:
			if int(av) != 0 and int(av) != 255:
				soft.append(str(f).get_file())
				break
		if int(pr[1]) > 64:
			many.append("%s %d 色" % [str(f).get_file(), int(pr[1])])
	_ok("② ★硬边: alpha 只有 0 / 255(%d 张)" % n, n >= 30 and soft.is_empty(), str(soft))
	_ok("② 每张 ≤ 64 色(pixel_art_audit 的判据)", many.is_empty(), str(many))
	var key := (load("res://assets/sprites/ui/replay_bar/key-red.png") as Texture2D)
	_ok("② 存的是 1 倍源图(键底座 20×20, 没把 ×3 后的图存进来再放大一次)", key != null and key.get_size() == Vector2(20, 20))


# ③ 剪影图集
func _t_sil_table() -> void:
	var src := FileAccess.get_file_as_string(GEN)
	var i := src.find("SIL_IDS = [")
	var j := src.find("]", i)
	var ids: Array = []
	if i >= 0 and j > i:
		for part in src.substr(i + 11, j - i - 11).split(","):
			var t := part.strip_edges().replace("\"", "").replace("\n", "").strip_edges()
			if t != "":
				ids.append(t)
	_ok("③ ★剪影格序表 QueueWaitView.SIL_IDS == 生成脚本 SIL_IDS(%d 只)" % ids.size(), ids.size() >= 8 and ids == Array(QueueWaitView.SIL_IDS),
		"%s / %s" % [str(ids), str(QueueWaitView.SIL_IDS)])
	var at := load(QueueWaitView.SIL_ATLAS) as Texture2D
	_ok("③ 剪影图集宽 = %d × %d 只" % [QueueWaitView.SIL_PX, QueueWaitView.SIL_IDS.size()], at != null
		and at.get_size() == Vector2(QueueWaitView.SIL_PX * QueueWaitView.SIL_IDS.size(), QueueWaitView.SIL_PX))
	var miss: Array = []
	for pid in QueueWaitView.SIL_IDS:
		if not ResourceLoader.exists("res://assets/sprites/avatars/%s.png" % str(pid)):
			miss.append(pid)
	_ok("③ 剪影的来源(龟头像)每只都在", miss.is_empty(), str(miss))


## t 是不是 path 那张 1 倍源图按 ×k 最近邻放大(逐字节)。
func _is_up(t: Texture2D, path: String, k: int) -> bool:
	if t == null:
		return false
	var a := ((load(path) as Texture2D).get_image().duplicate()) as Image
	a.convert(Image.FORMAT_RGBA8)
	a.resize(a.get_width() * k, a.get_height() * k, Image.INTERPOLATE_NEAREST)
	var b := (t.get_image().duplicate()) as Image
	b.convert(Image.FORMAT_RGBA8)
	return a.get_size() == b.get_size() and a.get_data() == b.get_data()


# ④ PixelKey.up
func _t_upscale() -> void:
	var bad: Array = []
	var n := 0
	for f in ["res://assets/sprites/ui/replay_bar/key-neutral.png", "res://assets/sprites/ui/replay_bar/icon-play.png",
			"res://assets/sprites/ui/queue_wait/frame-me.png", "res://assets/sprites/ui/queue_wait/lock.png"]:
		n += 1
		var t := PixelKey.up(f)
		## 独立算一遍: 逐像素按 floor(x/3) 取源像素(不用 Image.resize, 不拿被测的同一把尺子)
		var src := (load(f) as Texture2D).get_image().duplicate() as Image
		src.convert(Image.FORMAT_RGBA8)
		var img := t.get_image().duplicate() as Image if t != null else null
		if img == null or img.get_size() != src.get_size() * 3:
			bad.append(f.get_file())
			continue
		img.convert(Image.FORMAT_RGBA8)
		var ok := true
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				if img.get_pixel(x, y) != src.get_pixel(x / 3, y / 3):
					ok = false
					break
			if not ok:
				break
		if not ok:
			bad.append(f.get_file())
	_ok("④ ★PixelKey.up 逐像素 = 源图 ×3 最近邻(%d 张, 独立按 floor(x/3) 取像素比)" % n, n == 4 and bad.is_empty(), str(bad))


func _snapshot(gs) -> Dictionary:
	gs.season_leaders = ["phoenix", "pirate", "ninja"]
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "phoenix", "equips": []}, {"kind": "leader", "slot": 1, "id": "pirate", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 2, "id": "ninja", "equips": []}, {"kind": "minion", "role": "front", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	return RW.my_snapshot()


## 独立数法: 快照里每一路的统领 + 小将个数(不调 QueueWaitView.unit_count)。
func _count_units(snap: Dictionary) -> int:
	var n := 0
	for lane in ["top", "bottom"]:
		n += ((snap.get("lane_assign", {}) as Dictionary).get(lane, []) as Array).size()
		n += ((snap.get("minions", {}) as Dictionary).get(lane, []) as Array).size()
	return n


func _lit(v: Node, prefix: String) -> Vector2i:
	var on := 0
	var all := 0
	for c in v.find_children(prefix + "*", "TextureRect", true, false):
		all += 1
		on += 1 if bool((c as TextureRect).get_meta(QueueWaitView.META_ON, false)) else 0
	return Vector2i(on, all)


# ⑤ ⑥ 真建等待屏
func _t_view(gs) -> void:
	var bak := {"leaders": (gs.season_leaders as Array).duplicate(), "dl": (gs.dual_lineup as Dictionary).duplicate(true)}
	var snap := _snapshot(gs)
	var want := _count_units(snap)
	for vp in [Vector2i(1560, 720), Vector2i(1280, 960)]:
		get_tree().root.size = vp
		await get_tree().process_frame
		await get_tree().process_frame
		var vsz := Vector2(get_viewport().get_visible_rect().size)
		var tag := "%dx%d" % [int(vsz.x), int(vsz.y)]
		var host := Control.new()
		host.size = vsz
		add_child(host)
		var v: QueueWaitView = QueueWaitView.new()
		host.add_child(v)
		v.build(snap, Vector2i(2, 1), int(P2C.GAUNTLET_WINS_IN), int(P2C.GAUNTLET_LOSSES_OUT))
		v.set_cell_text(RW.queue_cell_text(2, 1))
		v.set_cancel(RW.TXT_QUEUE_CANCEL, false)
		v.waited_lb.text = RW.queue_waited_text(64)
		var frame_pos := ((vsz - Vector2(QueueWaitView.FW, QueueWaitView.FH)) / 2.0).round()
		v.relayout(vsz, frame_pos)
		await get_tree().process_frame
		## ⑤ 阵容卡
		var avs: Array = []
		for c in v.find_children(QueueWaitView.N_MY_UNIT + "*", "TextureRect", true, false):
			if (c as TextureRect).texture != null:
				avs.append(str((c as TextureRect).get_meta("unit", "")))
		_ok("⑤ %s ★阵容卡头像 %d 个 = 快照单位数 %d(独立数法; 分母 > 0)、每个都有图" % [tag, avs.size(), want],
			want == 6 and avs.size() == want and QueueWaitView.unit_count(snap) == want, str(avs))
		var lw := _lit(v, QueueWaitView.N_WIN)
		var ll := _lit(v, QueueWaitView.N_LOSS)
		_ok("⑤ %s ★战绩格 2 胜 1 负: 胜 %d/%d 亮、负 %d/%d 亮" % [tag, lw.x, lw.y, ll.x, ll.y], lw == Vector2i(2, 4) and ll == Vector2i(1, 3))
		v.set_record(Vector2i(3, 2))
		lw = _lit(v, QueueWaitView.N_WIN)
		ll = _lit(v, QueueWaitView.N_LOSS)
		var tl := v.find_child(QueueWaitView.N_TITLE, true, false) as Label
		_ok("⑤ %s 换成 3 胜 2 负再量: 胜亮 %d、负亮 %d、标题「%s」" % [tag, lw.x, ll.x, tl.text if tl != null else "?"],
			lw.x == 3 and ll.x == 2 and tl != null and tl.text == QueueWaitView.TXT_TITLE % 6)
		v.set_record(Vector2i(2, 1))
		var s0 := v.sil_ids()
		v._step()
		var s1 := v.sil_ids()
		v._step()
		var s2 := v.sil_ids()
		_ok("⑤ %s ★剪影每 2 帧换一组(第 0→1 帧不换、第 1→2 帧换; 6 个)" % tag, s0.size() == 6 and s0 == s1 and s2 != s1, "%s / %s" % [str(s1), str(s2)])
		var bsb := v.cancel_btn.get_theme_stylebox("normal")
		_ok("⑤ %s ★取消键皮 = 回放条红键底座 ×3(同一套键)" % tag, bsb is StyleBoxTexture
			and _is_up((bsb as StyleBoxTexture).texture, QueueWaitView.KEY_RED, 3))
		var not3: Array = []
		for c in v.find_children("*", "TextureRect", true, false):
			var tr := c as TextureRect
			if tr.texture == null or str(tr.get_meta("unit", "")) != "" or tr.texture is AtlasTexture:
				continue
			if str(tr.name) == QueueWaitView.N_SCAN:
				continue                                      # 扫描亮带横向拉满面板(1×2 的光), 只量高
			if tr.size != tr.texture.get_size() * 3.0:
				not3.append("%s %s/%s" % [tr.name, str(tr.size), str(tr.texture.get_size())])
		_ok("⑤ %s 贴图件都按源图 ×3 画(整数倍)" % tag, not3.is_empty(), str(not3.slice(0, 6)))
		## ⑥ 摆位
		var parts := {}
		for nm in [QueueWaitView.N_TITLE, QueueWaitView.N_MY_CARD, QueueWaitView.N_FOE_CARD, "QueueVs", QueueWaitView.N_WAITED,
				QueueWaitView.N_CANCEL]:
			var c := v.find_child(nm, true, false) as Control
			if c != null:
				parts[nm] = c.get_global_rect()
		var cells := Rect2()
		for c in v.find_children("QueueWin_*", "TextureRect", true, false) + v.find_children("QueueLoss_*", "TextureRect", true, false):
			cells = (c as Control).get_global_rect() if cells.size == Vector2.ZERO else cells.merge((c as Control).get_global_rect())
		parts["cells"] = cells
		## 已等待那一行框是整个设计框宽: 按字宽量(字居中)
		var wl := v.waited_lb
		var ww: float = wl.get_theme_font("font").get_string_size(wl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, wl.get_theme_font_size("font_size")).x
		var wr: Rect2 = wl.get_global_rect()
		parts[QueueWaitView.N_WAITED] = Rect2(wr.position.x + (wr.size.x - ww) / 2.0, wr.position.y, ww, wr.size.y)
		var tlr: Rect2 = parts.get(QueueWaitView.N_TITLE, Rect2())
		var tw: float = tl.get_theme_font("font").get_string_size(tl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tl.get_theme_font_size("font_size")).x
		parts[QueueWaitView.N_TITLE] = Rect2(tlr.position.x + (tlr.size.x - tw) / 2.0, tlr.position.y, tw, tlr.size.y)
		var vr := Rect2(Vector2.ZERO, vsz)
		var hits: Array = []
		var outs: Array = []
		var keys: Array = parts.keys()
		for i in range(keys.size()):
			var ri: Rect2 = parts[keys[i]]
			if not vr.encloses(ri):
				outs.append(str(keys[i]))
			for j in range(i + 1, keys.size()):
				if ri.intersects(parts[keys[j]]):
					hits.append("%s × %s" % [keys[i], keys[j]])
		_ok("⑥ %s ★标题 / 战绩格 / 两张卡 / VS / 已等待 / 取消键 互不相交(%d 件两两比)" % [tag, keys.size()], keys.size() == 7 and hits.is_empty(), str(hits))
		_ok("⑥ %s 都在屏内" % tag, outs.is_empty(), str(outs))
		var bg := v.get_child(0) as TextureRect
		var bgr: Rect2 = bg.get_global_rect() if bg != null else Rect2()
		_ok("⑥ %s 底纹盖满整屏(%s ⊇ 视口)" % [tag, str(bgr)], bg != null and bgr.encloses(vr))
		var lk := v.find_child(QueueWaitView.N_LOCK, true, false) as Control
		var mc: Rect2 = parts.get(QueueWaitView.N_MY_CARD, Rect2())
		_ok("⑥ %s 锁徽记压在阵容卡右上角(与卡相交、探出卡顶)" % tag, lk != null and lk.get_global_rect().intersects(mc)
			and lk.get_global_rect().position.y < mc.position.y)
		host.queue_free()
		await get_tree().process_frame
	gs.season_leaders = bak["leaders"]
	gs.dual_lineup = bak["dl"]


# ⑦ 尺子自检
func _t_ruler() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))
	img.set_pixel(1, 1, Color(1, 0, 0, 0.5))
	var pr := _profile(img)
	var soft := false
	for av in pr[0]:
		if int(av) != 0 and int(av) != 255:
			soft = true
	_ok("⑦ 尺子自检: 带一颗半透明像素的图判「不是硬边」", soft)
	var snap := {"lane_assign": {"top": ["a", "b"], "bottom": ["c"]}, "minions": {"top": [{}], "bottom": [{}, {}]}}
	var short := snap.duplicate(true)
	(short["minions"]["bottom"] as Array).pop_back()
	_ok("⑦ 尺子自检: 计数法数得出「少一个单位」(6 vs 5)", _count_units(snap) == 6 and _count_units(short) == 5
		and QueueWaitView.unit_count(snap) == 6)
