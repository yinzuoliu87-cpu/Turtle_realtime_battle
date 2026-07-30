extends Node
## verify_tile_texture.gd — 地面地砖细节贴图 (用户 2026-07-30 需求4·P1)
##
## 需求原文:「地图再度需要提升，思考办法」→ 拍板 U7 顺序 P1→P2→P4→P3, P1 = 地面上纹理。
## 方案书: docs/plans/20260730b-局内HUD改造+大师审核+地图提升.md §4.4
##
## ★方案书里我写的"tile 是纯色方块，没有贴图"是【错的】—— 我读的是程序化 fallback 分支,
##   而 arena.json 存在, 实际走的是数据驱动分支, 那条一直在传 _tile_material(ti):
##   水有滚动波纹 shader, 其余三种是 锁死调色板 × VfxTex._make_tile_texture()(32×32 程序斜网格)。
##   所以 P1 的真实内容是"把程序生成的斜网格换成真正的像素地砖纹理", 不是从无到有。
##
## 查四组:
##   ① 四张贴图在磁盘上, 且【真的是灰度】(r==g==b)
##   ② ★最亮像素必须是 255 —— 即"最亮处 = 纯调色板色, 贴图只做减法"。
##      这条是【锁死配色没被偷偷改掉】的判据: 管线是 albedo_color × 贴图,
##      贴图里任何 >1.0 的值 8-bit 都存不下(旧程序贴图写的 1.18 其实也被钳成 1.0),
##      所以只要 max=255 就保证了地面最亮处仍是 TILE_COLS 的原色。
##   ③ 贴图【真的有结构】(标准差下限) —— 我第一版给淤泥挑的图 sd=0.023, 屏幕上完全隐形,
##      合成预览才看出来。光"文件在位"是假判据。
##   ④ 接线: 四种 type 都拿到新贴图(不是退回程序斜网格) + 调色板没动 + 水的 shader 收到 detail_tex
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_tile_texture.tscn

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const VfxTex := preload("res://scripts/util/vfx_textures.gd")

## 每种 type 的最低结构标准差。★不是拍脑袋: 淤泥用 t1(sd 0.023)时屏幕上隐形,
##   换成 t3(sd 0.055)才读得出。0.040 卡在两者之间, 再退化就红。
const MIN_SD := 0.040

var _fail := 0
var _n := 0


func _ready() -> void:
	print("=== 地面地砖细节贴图 (需求4·P1) ===")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)
	s.set_physics_process(false)

	_files_and_gray(s)
	_wiring(s)

	print("  ★分母: 本门禁共 %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 地面地砖细节贴图")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


## ①②③ 四张图在位 + 是灰度 + 最亮=255 + 有结构
func _files_and_gray(s) -> void:
	print("  ── ①②③ 四张贴图: 在位 / 灰度 / 最亮=255 / 有结构 ──")
	var tex_map: Dictionary = RTScene.TILE_TEX
	_chk("★分母: TILE_TEX 登记了 4 种 type", tex_map.size() == 4, "%d 种" % tex_map.size())
	for ti in [0, 1, 2, 3]:
		var p: String = str(tex_map.get(ti, ""))
		_chk("① type %d 有登记路径" % ti, p != "")
		_chk("① type %d 贴图文件在磁盘上: %s" % [ti, p.get_file()],
			FileAccess.file_exists(p), p)
		if not FileAccess.file_exists(p):
			continue
		var tex: Texture2D = load(p)
		_chk("① type %d 能 load 成 Texture2D" % ti, tex != null)
		if tex == null:
			continue
		var img: Image = tex.get_image()
		_chk("① type %d 能取到 Image" % ti, img != null)
		if img == null:
			continue
		var w := img.get_width()
		var h := img.get_height()
		_chk("① type %d 尺寸 64×64" % ti, w == 64 and h == 64, "%d×%d" % [w, h])
		# 扫全图: 灰度 / 最亮 / 标准差
		var mx := 0.0
		var sum := 0.0
		var sum2 := 0.0
		var not_gray := 0
		var n := 0
		for y in range(h):
			for x in range(w):
				var c := img.get_pixel(x, y)
				if absf(c.r - c.g) > 0.004 or absf(c.g - c.b) > 0.004:
					not_gray += 1
				mx = maxf(mx, c.r)
				sum += c.r
				sum2 += c.r * c.r
				n += 1
		var mean: float = sum / float(n)
		var sd: float = sqrt(maxf(0.0, sum2 / float(n) - mean * mean))
		_chk("① ★type %d 是灰度(r==g==b·彩色图会和锁死调色板相乘变一团黑)" % ti,
			not_gray == 0, "非灰度像素 %d 个" % not_gray)
		_chk("② ★type %d 最亮像素=255(保证地面最亮处仍是 TILE_COLS 原色)" % ti,
			mx >= 0.996, "最亮 %.3f" % mx)
		_chk("③ ★type %d 真的有结构 sd≥%.3f(第一版淤泥 sd=0.023 屏幕上隐形)" % [ti, MIN_SD],
			sd >= MIN_SD, "sd=%.4f mean=%.3f" % [sd, mean])


## ④ 接线: 材质真的拿到新贴图, 调色板没动, 水的 shader 收到 detail_tex
func _wiring(s) -> void:
	print("  ── ④ 接线: 拿到新贴图 / 调色板未动 / 水 shader 收到 detail ──")
	var fallback: Texture2D = VfxTex._make_tile_texture()
	_chk("④ ★分母: 程序斜网格 fallback 能取到(用于对比)", fallback != null)
	for ti in [0, 2, 3]:
		var m = s._tile_material(ti)
		_chk("④ type %d 是 StandardMaterial3D" % ti, m is StandardMaterial3D)
		if not (m is StandardMaterial3D):
			continue
		var sm := m as StandardMaterial3D
		_chk("④ ★type %d 拿到了贴图(不是 null)" % ti, sm.albedo_texture != null)
		# ★不是退回程序斜网格 —— 缺图时 _tile_detail_tex 会 fallback, 那种情况必须红
		_chk("④ ★type %d 不是退回程序斜网格(缺图会静默退化)" % ti,
			sm.albedo_texture != fallback)
		_chk("④ type %d 用 NEAREST 过滤(像素画不许插值成糊)" % ti,
			sm.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)
		# 调色板没动: albedo_color 必须仍等于 TILE_COLS 里锁死的值
		var want: Color = RTScene.TILE_COLS.get(ti, Color.BLACK)
		_chk("④ ★type %d 调色板未动(TILE_COLS 是锁死的·场景地图方案.md§4)" % ti,
			sm.albedo_color.is_equal_approx(want),
			"%s vs 期望 %s" % [str(sm.albedo_color), str(want)])
	# 水: 保留滚动波纹 shader, 且把新水纹作为 detail 乘进去
	var wm = s._tile_material(1)
	_chk("④ 水仍是 ShaderMaterial(静态贴图给不了滚动波纹)", wm is ShaderMaterial)
	if wm is ShaderMaterial:
		var shm := wm as ShaderMaterial
		var dt = shm.get_shader_parameter("detail_tex")
		_chk("④ ★水的 shader 收到了 detail_tex", dt != null)
		_chk("④ ★水的 detail 不是退回程序斜网格", dt != fallback)
		var code: String = shm.shader.code if shm.shader != null else ""
		_chk("④ 水 shader 里真的用了 detail(不是设了参数不采样)",
			code.contains("texture(detail_tex, UV)") and code.contains("detail_amt"))
		_chk("④ 水 shader 仍保留滚动波纹(TIME 驱动)", code.contains("TIME"))
	# 数据驱动那条路径真的把材质传下去了(arena.json 存在 → 走的是它)
	var src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_chk("④ ★_tilemap_from_data 把 _tile_material(ti) 传给 _tilemap_add",
		src.contains("_tile_material(ti))"))
	_chk("④ 缺图时会 push_warning(不做静默兜底·同 TRAINER_SPRITE 的规矩)",
		src.contains("地砖细节贴图缺失"))


func _chk(name: String, ok: bool, detail: String = "") -> void:
	_n += 1
	if ok:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])
