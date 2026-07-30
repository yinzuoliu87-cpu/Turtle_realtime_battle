extends Node
## verify_midground.gd — 中景地标层 (用户 2026-07-30 需求4·P2)
##
## 需求原文:「地图再度需要提升，思考办法」→ 拍板 U7 顺序 P1→P2→P4→P3, P2 = 补中景。
## 方案书: docs/plans/20260730b-局内HUD改造+大师审核+地图提升.md §4.4 / §8.3
##
## ★为什么需要这一层: 原来只有【远景三层】(z≈-19 的水幕/远礁剪影/光柱)和
##   【边框装饰带】(ARENA 外 0~200px 的小水草珊瑚), 两者之间是空的 → 纵深断层。
##
## ★核心判据是【素材真的进了 _world】而不是"函数被调了"——
##   memory project-vfx-library-rich 那条教训: 美术断言要查素材真的显示进 _world,
##   不能只判定生效。所以本门禁真建一次战斗场景, 走一遍 _world 数精灵。
##
## 查四组:
##   ① 三个素材在磁盘 + 尺寸对 + 【与仓库已有素材都不相同】(不复用铁律·用户 2026-07-30 追问过)
##   ② 接线: _build_tilemap_decor 里调了 _build_midground; 且 MAPEDIT 下不建(同装饰带)
##   ③ 布局参数: 环带在装饰带【之外】、间距/件数在合理档、用【播种】RNG(护确定性)
##   ④ ★真建场景 → 中景精灵确实出现在 _world 里, 且数量与 MID_COUNT 一致
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_midground.tscn

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
## ★不能 preload 成 const 再调 get_script_constant_map() —— class_name 会让它解析成
##   【类型】而不是 Script 资源, 直接报 "Cannot call non-static function ... directly"。
##   要 load() 成 Script(同 verify_trainer_desc 的做法)。
const WB_PATH := "res://scripts/scenes/battle/battle_world_builder.gd"

const MID_FILES := ["mid_shipwreck", "mid_coral_pillar", "mid_stone_column"]
const DECOR_BAND := 200.0     # _build_tilemap_decor 里的 mg —— 中景必须在它之外

var _fail := 0
var _n := 0


func _ready() -> void:
	print("=== 中景地标层 (需求4·P2) ===")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	_assets()
	_wiring()
	_layout()
	await _in_world()

	print("  ★分母: 本门禁共 %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 中景地标层")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


## ① 素材在位 + 不与已有素材重复
func _assets() -> void:
	print("  ── ① 三个素材在磁盘 + 不复用 ──")
	_chk("★分母: 登记了 3 个中景素材", MID_FILES.size() == 3)
	# 把仓库 map/ 下【其它】素材的字节指纹收起来, 用于查重
	var others: Dictionary = {}
	var d := DirAccess.open("res://assets/sprites/map")
	var n_other := 0
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.ends_with(".png") and not (f.get_basename() in MID_FILES):
				# ★用 FileAccess.get_sha256 —— 别拿 get_file_as_bytes().get_string_from_ascii()
				#   去哈希: PNG 是二进制, ASCII 转换会在第一个 null 字节处截断, 所有文件塌成
				#   同一个短串 → 我第一版就是这样, 三个素材全报"撞上 tile-water.png"(假阳性)。
				var h0 := FileAccess.get_sha256("res://assets/sprites/map/" + f)
				if h0 != "":
					others[h0] = f
					n_other += 1
			f = d.get_next()
		d.list_dir_end()
	print("    对照池: map/ 下其它 png %d 个" % n_other)
	_chk("① ★分母: 对照池非空(空池等于没查重)", n_other >= 10, "%d 个" % n_other)
	for nm in MID_FILES:
		var p: String = "res://assets/sprites/map/%s.png" % nm
		_chk("① %s.png 在磁盘上" % nm, FileAccess.file_exists(p))
		if not FileAccess.file_exists(p):
			continue
		var tex: Texture2D = load(p)
		_chk("① %s 能 load 且有尺寸" % nm,
			tex != null and tex.get_width() >= 64 and tex.get_height() >= 96,
			"%dx%d" % [tex.get_width() if tex else 0, tex.get_height() if tex else 0])
		var h := FileAccess.get_sha256(p)
		_chk("① ★%s 与 map/ 下已有素材都不相同(不复用铁律)" % nm,
			not others.has(h), ("撞上 " + str(others.get(h, ""))) if others.has(h) else "")


## ② 接线
func _wiring() -> void:
	print("  ── ② 接线 ──")
	var src := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_world_builder.gd")
	_chk("② ★分母: 读到 world_builder 源码", src.length() > 20000)
	_chk("② _build_midground 函数存在", src.contains("func _build_midground("))
	_chk("② ★_build_tilemap_decor 里真的调了它", src.contains("_build_midground(root)"))
	# 装饰带在 MAPEDIT 下不建 → 中景挂在装饰带里, 自然也不建(免遮挡刷格)
	_chk("② MAPEDIT 下不建装饰(中景挂在装饰里·同步生效)",
		src.contains('if not OS.has_environment("MAPEDIT"): _build_tilemap_decor()'))
	for nm in MID_FILES:
		_chk("② MID_OBJS 里登记了 %s" % nm, src.contains('"%s"' % nm))


## ③ 布局参数
func _layout() -> void:
	print("  ── ③ 布局参数 ──")
	var _ws: Script = load(WB_PATH)
	var K: Dictionary = _ws.get_script_constant_map()
	_chk("③ ★分母: 读到 world_builder 常量表", not K.is_empty())
	_chk("③ ★环带内沿在边框装饰带【之外】(不重叠·别往已调稀的装饰带里加密度)",
		float(K.get("MID_BAND_IN", 0.0)) >= DECOR_BAND,
		"内沿 %.0f vs 装饰带 %.0f" % [float(K.get("MID_BAND_IN", 0.0)), DECOR_BAND])
	_chk("③ 环带外沿大于内沿", float(K.get("MID_BAND_OUT", 0.0)) > float(K.get("MID_BAND_IN", 0.0)),
		"%.0f~%.0f" % [float(K.get("MID_BAND_IN", 0.0)), float(K.get("MID_BAND_OUT", 0.0))])
	# 少而大 = 地标; 多了就变回"装饰刷屏"(2026-07-23 已因太密调稀过一轮)
	var cnt: int = int(K.get("MID_COUNT", 0))
	_chk("③ ★件数在【少而大】的档位(6~24)", cnt >= 6 and cnt <= 24, "%d 件" % cnt)
	_chk("③ 有最小间距防扎堆", float(K.get("MID_MIN_GAP", 0.0)) >= 150.0,
		"%.0f 码" % float(K.get("MID_MIN_GAP", 0.0)))
	_chk("③ ★三种物件都有(单一物件重复十几次=一模一样)", int(K.get("MID_OBJS", []).size()) == 3,
		"%d 种" % int(K.get("MID_OBJS", []).size()))
	# 确定性: 必须播种, 不许裸随机(rng_discipline 棘轮)
	var src := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_world_builder.gd")
	var body := _func_body(src, "_build_midground")
	_chk("③ ★分母: 取到 _build_midground 函数体", body.length() > 400, "%d 字符" % body.length())
	_chk("③ ★用【播种】RNG(裸随机会破确定性回放)",
		body.contains("RandomNumberGenerator.new()") and body.contains("rng.seed ="))
	_chk("③ 缺图会 push_warning(不静默兜底)", body.contains("中景素材缺失"))


## ④ ★真建场景 → 数 _world 里的中景精灵。这才是"素材真的显示出来"的判据。
func _in_world() -> void:
	print("  ── ④ 真建场景: 中景精灵确实进了 _world ──")
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)
	s.set_physics_process(false)
	_chk("④ ★分母: _world 建起来了", s._world != null)
	if s._world == null:
		return
	var want: Dictionary = {}
	for nm in MID_FILES:
		want["res://assets/sprites/map/%s.png" % nm] = 0
	var total := _count_sprites(s._world, want)
	print("    _world 下共 %d 个 Sprite3D; 中景命中分布 %s" % [total, str(want)])
	var _ws: Script = load(WB_PATH)
	var K: Dictionary = _ws.get_script_constant_map()
	var cnt: int = int(K.get("MID_COUNT", 0))
	var got := 0
	for k in want:
		got += int(want[k])
	_chk("④ ★中景精灵真的进了 _world(不是只调了函数)", got > 0, "命中 %d 个" % got)
	_chk("④ ★数量 = MID_COUNT(%d)" % cnt, got == cnt, "实际 %d 个" % got)
	# 三种都得出现 —— 若某个素材路径写错, 只会少那一种, 总数对不上但更要指名道姓
	for k in want:
		_chk("④ %s 至少出现 1 个" % String(k).get_file(), int(want[k]) >= 1,
			"%d 个" % int(want[k]))
	s.queue_free()
	await get_tree().process_frame


## 递归数 Sprite3D, 并按纹理资源路径统计命中
func _count_sprites(n: Node, want: Dictionary) -> int:
	var c := 0
	if n is Sprite3D:
		c += 1
		var t: Texture2D = (n as Sprite3D).texture
		if t != null:
			var rp := t.resource_path
			if want.has(rp):
				want[rp] = int(want[rp]) + 1
	for ch in n.get_children():
		c += _count_sprites(ch, want)
	return c


func _func_body(s: String, fname: String) -> String:
	var i := s.find("func %s(" % fname)
	if i < 0:
		return ""
	var j := s.find("\nfunc ", i + 1)
	return s.substr(i, (j - i) if j > i else (s.length() - i))


func _chk(name: String, ok: bool, detail: String = "") -> void:
	_n += 1
	if ok:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])
