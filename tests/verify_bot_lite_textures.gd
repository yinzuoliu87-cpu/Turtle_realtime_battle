extends Node

## verify_bot_lite_textures.gd —— 无头陪练号省内存: 大贴图换成同尺寸、不含像素的占位(2026-10-27)
##
## 被测: scripts/systems/sim/lite_tex_loader.gd(加载器 + 开关) / autoload/persistent_bg.gd(接线) /
##       代码里从【载入的贴图】读像素的各处(占位贴图的 get_image() 是 null)。
##   ① 不设 SIM_DRIVER(= 本门禁进程; 与真人客户端、裁判机同一面): 真 autoload 没装加载器;
##      大贴图(龟全身动作表)是真贴图、有像素
##   ② 测试缝模拟「无头 + SIM_DRIVER=1」(调的是 persistent_bg._init 调的同一个函数): 同一张大贴图 ⇒ 同尺寸占位、
##      没有像素; 小贴图(< 256KB)仍是真贴图; 开关只认「无头 且 恰好 "1"」; 阈值边界两侧各一张;
##      注册前后各打一行 [LiteTex]
##   ③ 从载入的贴图读像素的 10 处(get_image; 视口截图那几处读的是画面不是载入的贴图, 不在此列),
##      在占位下不报错、不崩 —— 报错条数由挂在引擎上的 Logger 数(脚本报错不经过 GDScript, 只有它数得到)
##   ④ 尺子自检: 阈值改成 0 ⇒ 小贴图也变占位(证明 ②「小贴图是真贴图」那条量得出差别)
##   ⑤ 拆掉加载器后一切复原; 两处补了空值判断的函数在真贴图下照旧出图(补丁没伤到真人客户端那条路)

const LTL := preload("res://scripts/systems/sim/lite_tex_loader.gd")

const BIG := "res://assets/sprites/pets/shell.png"              # 龟全身动作表 4000×1500(解码 24MB)
const BIG2 := "res://assets/sprites/pets/headless.png"          # 另一张全身表: 走普通 load()(带缓存)那条路
const SMALL := "res://assets/sprites/ui/coin.png"               # 24×24(解码 2.3KB)
const EDGE_AT := "res://assets/sprites/skills/basic-attack.png" # 256×256×4 = 262144 恰好等于阈值 ⇒ 算大
const EDGE_BELOW := "res://assets/sprites/vfx/bear-walk.png"    # 672×96×4 = 258048 刚低于阈值 ⇒ 算小
const MENU_TILE := "res://assets/sprites/menu/menu-bg-tile.png" # 1946×1984: PreloadCache / PersistentBg 读它的像素
const FG_BAND := "res://assets/sprites/map/themes/fg_sea_band.png"   # 800×224: 前景剪影带分层增益读它的像素
const SKILL_RING := "res://assets/sprites/vfx/skill-ring.png"
const SHELL_GUARD := "res://assets/sprites/vfx/shell-guard.png"
const THEME_TEX := "res://assets/sprites/map/themes/%s.png"
## 源码里 `func _ready` 那一行(拆成两截拼: 整串字面量会被 coroutine_await_audit 当成对本文件协程 _ready 的裸调用)。
const READY_SIG := "func _ready" + "() -> void:"
const SITES_TOTAL := 10
const MIN_ASSERTS := 57

var _n := 0
var _fail := 0
var _tap: ErrTap = null
var _sites_hit := 0


## 数引擎 / 脚本报错与 print 的 Logger(Godot 4.5+)。★回调里不许 print / push_error(会递归回到自己)。
class ErrTap extends Logger:
	var errors := 0
	var warnings := 0
	var last := ""
	var lite_lines: Array = []
	var mx := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		mx.lock()
		if error_type == Logger.ERROR_TYPE_WARNING:
			warnings += 1
		else:
			errors += 1
			last = (rationale if rationale != "" else code).left(160)
		mx.unlock()

	func _log_message(message: String, _error: bool) -> void:
		if message.begins_with("[LiteTex]"):
			mx.lock()
			lite_lines.append(message.strip_edges())
			mx.unlock()

	func reset() -> void:
		mx.lock()
		errors = 0
		warnings = 0
		last = ""
		lite_lines.clear()
		mx.unlock()


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 不进缓存地载一次(CACHE_MODE_IGNORE): 每次都真的问一遍加载器, 不会被上一次的结果挡住。
func _fresh(path: String) -> Texture2D:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D


func _is_ph(t) -> bool:
	return t != null and t is PlaceholderTexture2D


## 真贴图 = 不是占位、拿得到像素、像素里有不透明的。
func _has_px(t: Texture2D) -> bool:
	if t == null or t is PlaceholderTexture2D:
		return false
	var im: Image = t.get_image()
	return im != null and not im.is_empty() and im.get_used_rect().size.x > 0


## 在 Logger 底下跑一处读像素的代码 ⇒ [返回值, 报错条数, 警告条数, 最后一条报错]。
func _measure(fn: Callable) -> Array:
	_tap.reset()
	var r = fn.call()
	return [r, _tap.errors, _tap.warnings, _tap.last]


func _ready() -> void:
	await get_tree().process_frame
	_tap = ErrTap.new()
	OS.add_logger(_tap)
	push_error("LITETEX_TAP_PROBE 门禁自检: 证明 Logger 数得到报错(这一条是故意的)")
	_ok("尺子: Logger 收得到报错(故意 push_error 一条 ⇒ 数到 ≥1)", _tap.errors >= 1, "errors=%d" % _tap.errors)
	var big_size := _part1()
	var ld: ResourceFormatLoader = _part2(big_size)
	if ld == null:
		_ok("② 加载器没装上, ③④ 无从量起", false)
	else:
		_part4(ld)
		_part3(ld)
		ResourceLoader.remove_resource_format_loader(ld)
	_part5()
	OS.remove_logger(_tap)
	print("--- 分母: 断言 %d 条(下限 %d) / 读像素 %d 处里真吃到占位或证明碰不到的 %d 处 ---" % [_n, MIN_ASSERTS, SITES_TOTAL, _sites_hit])
	if _fail == 0 and _n >= MIN_ASSERTS and _sites_hit == SITES_TOTAL:
		print("ALL PASS verify_bot_lite_textures (%d 条断言 / %d 处读像素)" % [_n, _sites_hit])
		get_tree().quit(0)
	else:
		print("FAILED verify_bot_lite_textures: fail=%d n=%d sites=%d/%d" % [_fail, _n, _sites_hit, SITES_TOTAL])
		get_tree().quit(1)


## ① 本进程 = 无头、不设 SIM_DRIVER ⇒ 真 autoload 没装加载器, 大贴图是真贴图。返回大贴图尺寸给 ② 比。
func _part1() -> Vector2:
	print("--- ① 不设 SIM_DRIVER: 不装, 大贴图有像素 ---")
	_ok("① 前提: 本进程无头、SIM_DRIVER 不是 \"1\"(门禁从不设它)",
		DisplayServer.get_name() == "headless" and OS.get_environment("SIM_DRIVER") != "1",
		"display=%s SIM_DRIVER='%s'" % [DisplayServer.get_name(), OS.get_environment("SIM_DRIVER")])
	var pbg := get_node_or_null("/root/PersistentBg")
	_ok("① 真 autoload PersistentBg 在场且没装加载器(lite_tex == null)",
		pbg != null and pbg.get("lite_tex") == null, "pbg=%s" % str(pbg))
	## 接线: persistent_bg._init 调的就是 ② 用测试缝调的那个函数, 输入就是这两样(不是别的环境变量 / 不是 strip 过的)
	var src := FileAccess.get_file_as_string("res://autoload/persistent_bg.gd")
	var i_init := src.find("func _init() -> void:")
	var i_call := src.find("LiteTexLoader.install_if_bot(DisplayServer.get_name() == \"headless\", OS.get_environment(\"SIM_DRIVER\"))")
	var i_ready := src.find(READY_SIG)
	_ok("① 接线: persistent_bg._init 里调 install_if_bot(无头?, SIM_DRIVER 原值)",
		i_init >= 0 and i_call > i_init and (i_ready < 0 or i_call < i_ready),
		"_init@%d call@%d _ready@%d" % [i_init, i_call, i_ready])
	var proj := FileAccess.get_file_as_string("res://project.godot")
	var i_al := proj.find("[autoload]")
	var first_al := proj.substr(i_al).split("\n", false)[1] if i_al >= 0 else ""
	_ok("① PersistentBg 是第一个 autoload(_init 早于其余 autoload 载入贴图)",
		first_al.begins_with("PersistentBg="), first_al)
	var t := _fresh(BIG)
	_ok("① 大贴图是真贴图(CompressedTexture2D, 不是占位)", t is CompressedTexture2D and not _is_ph(t), str(t))
	_ok("① 大贴图有像素(get_image 非空且有不透明像素)", _has_px(t))
	var sz: Vector2 = t.get_size() if t != null else Vector2.ZERO
	_ok("① 大贴图真是大的: 解码 ≥ 阈值(否则 ② 量不出东西)", sz.x * sz.y * 4.0 >= float(LTL.MIN_BYTES),
		"%dx%d" % [int(sz.x), int(sz.y)])
	return sz


## ② 测试缝模拟陪练号。返回装上的加载器(③④ 接着用), 装不上返回 null。
func _part2(big_size: Vector2) -> ResourceFormatLoader:
	print("--- ② 模拟「无头 + SIM_DRIVER=1」 ---")
	var cases := [
		[true, "1", true, "无头 + \"1\" ⇒ 装"],
		[false, "1", false, "有画面(真人客户端) + \"1\" ⇒ 不装"],
		[true, "", false, "无头 + 没设(门禁 / 裁判机) ⇒ 不装"],
		[true, "0", false, "无头 + \"0\" ⇒ 不装"],
		[true, "1 ", false, "无头 + \"1 \"(带空格, 不是恰好 \"1\") ⇒ 不装"],
		[true, "true", false, "无头 + \"true\" ⇒ 不装"],
		[false, "", false, "有画面 + 没设 ⇒ 不装"],
	]
	for c in cases:
		_ok("② 开关: " + str(c[3]), LTL.wanted(bool(c[0]), str(c[1])) == bool(c[2]))
	## 不该装的两种: 函数返回 null、不打日志、大贴图照旧是真的(行为上证明什么都没注册)
	for c in [[false, "1"], [true, ""]]:
		_tap.reset()
		var none := LTL.install_if_bot(bool(c[0]), str(c[1]))
		var after := _fresh(BIG)
		_ok("② install_if_bot(%s, '%s') ⇒ null、没打 [LiteTex]、大贴图仍有像素" % [str(c[0]), str(c[1])],
			none == null and _tap.lite_lines.is_empty() and _has_px(after), str(_tap.lite_lines))
	_tap.reset()
	var ld := LTL.install_if_bot(true, "1")
	var lines: Array = _tap.lite_lines.duplicate()
	_ok("② install_if_bot(true, \"1\") ⇒ 装上了加载器", ld != null)
	if ld == null:
		return null
	_ok("② 注册前后各打一行 [LiteTex](服务器上 grep 确认生效)",
		lines.size() == 2 and str(lines[0]).contains("注册") and str(lines[1]).contains("已注册"), str(lines))
	var t := _fresh(BIG)
	_ok("② 同一张大贴图 ⇒ 占位(PlaceholderTexture2D)", _is_ph(t), str(t))
	_ok("② 占位与真贴图同尺寸", t != null and t.get_size() == big_size,
		"%s vs %s" % [str(t.get_size() if t != null else null), str(big_size)])
	_ok("② 占位不含像素(get_image() == null)", t != null and t.get_image() == null)
	var s := _fresh(SMALL)
	_ok("② 小贴图(< 256KB)仍是真贴图、有像素", s is CompressedTexture2D and _has_px(s),
		"%s %s" % [str(s), str(s.get_size() if s != null else null)])
	var ea := _fresh(EDGE_AT)
	var eb := _fresh(EDGE_BELOW)
	_ok("② 边界: 256×256(恰好 = 阈值)算大 ⇒ 占位", _is_ph(ea) and ea.get_size() == Vector2(256, 256),
		str(ea.get_size() if ea != null else null))
	_ok("② 边界: 672×96(258048 < 阈值)算小 ⇒ 真贴图", _has_px(eb) and eb.get_size() == Vector2(672, 96),
		str(eb.get_size() if eb != null else null))
	## 普通 load()(带缓存, 产品代码走的就是这条): 第一次载就是占位, 缓存里存的也是占位
	_ok("② 前提: %s 还没进缓存" % BIG2, not ResourceLoader.has_cached(BIG2))
	var b2: Texture2D = load(BIG2)
	_ok("② 普通 load() 的大贴图 ⇒ 占位, 且缓存里那份就是它",
		_is_ph(b2) and ResourceLoader.has_cached(BIG2) and is_same(load(BIG2), b2), str(b2))
	_ok("② 占位带原路径(录流 / 出处键按路径认)", b2 != null and b2.resource_path == BIG2,
		b2.resource_path if b2 != null else "")
	b2 = null
	return ld


## ④ 尺子自检: 阈值改成 0 ⇒ 小贴图也变占位; 改回来又是真的。
func _part4(ld: ResourceFormatLoader) -> void:
	print("--- ④ 尺子自检: 阈值 0 ---")
	ld.set("min_bytes", 0)
	var s0 := _fresh(SMALL)
	_ok("④ 阈值 0 ⇒ 小贴图也变占位(②「小贴图是真贴图」那条量得出差别)", _is_ph(s0), str(s0))
	_ok("④ 阈值 0 下的小贴图占位仍同尺寸", s0 != null and s0.get_size() == Vector2(24, 24),
		str(s0.get_size() if s0 != null else null))
	ld.set("min_bytes", LTL.MIN_BYTES)
	var s1 := _fresh(SMALL)
	_ok("④ 阈值改回 %d ⇒ 小贴图又是真贴图" % LTL.MIN_BYTES, _has_px(s1), str(s1))


## ③ 读像素的 10 处。加载器在装着(默认阈值, 与服务器上一致)。
func _part3(ld: ResourceFormatLoader) -> void:
	print("--- ③ 读像素的 %d 处在占位下不报错、不崩 ---" % SITES_TOTAL)
	var ph_big: Texture2D = load(BIG)
	_ok("③ 前提: 喂给各处的龟全身表是占位", _is_ph(ph_big), str(ph_big))

	## S1 autoload/preload_cache.gd menu_bg_tile_tex: 读 menu-bg-tile(1946×1984, 大) 的像素再缩 512
	_ok("③ S1 前提: menu-bg-tile 没进缓存、PreloadCache 还没缩过(无头 _ready 直接返回)",
		not ResourceLoader.has_cached(MENU_TILE) and PreloadCache.get("_menu_bg_tex") == null)
	var ph0 := int(ld.get("n_ph"))
	var m1 := _measure(func(): return PreloadCache.menu_bg_tile_tex())
	var got_ph := int(ld.get("n_ph")) - ph0
	_ok("③ S1 PreloadCache.menu_bg_tile_tex: 真吃到占位(加载器这次换了 ≥1 张)", got_ph >= 1, "换了 %d 张" % got_ph)
	_ok("③ S1 PreloadCache.menu_bg_tile_tex: 0 报错, 返回 null(不铺花砖)", m1[1] == 0 and m1[0] == null,
		"errors=%d last=%s" % [m1[1], m1[3]])
	_site(m1[1] == 0 and got_ph >= 1)

	## S2 autoload/persistent_bg.gd _ready: 同一张 menu-bg-tile —— 但无头时在读像素之前就返回了, 而加载器只在无头装
	var src := FileAccess.get_file_as_string("res://autoload/persistent_bg.gd")
	var i_ready := src.find(READY_SIG)
	var i_guard := src.find("if DisplayServer.get_name() == \"headless\":", i_ready)
	var i_ret := src.find("return", i_guard)
	var i_px := src.find(".get_image()", i_ready)
	_ok("③ S2 PersistentBg._ready: 无头先 return、再往下才读像素(加载器只在无头装 ⇒ 这一处碰不到占位)",
		i_ready >= 0 and i_guard > i_ready and i_ret > i_guard and i_px > i_ret and LTL.wanted(false, "1") == false,
		"_ready@%d guard@%d return@%d get_image@%d" % [i_ready, i_guard, i_ret, i_px])
	var rerun := func() -> bool:
		get_node("/root/PersistentBg")._ready()
		return true
	var m2 := _measure(rerun)
	_ok("③ S2 PersistentBg._ready 在无头下再跑一遍: 0 报错", m2[1] == 0, "errors=%d last=%s" % [m2[1], m2[3]])
	_site(i_px > i_ret and m2[1] == 0)

	## S3 / S4 scripts/util/vfx_textures.gd: skill-ring 96×96 / shell-guard 76×42 —— 小图, 加载器放行
	for e in [[SKILL_RING, "S3 VfxTex._make_ring_texture", func(): return VfxTex._make_ring_texture(Color.WHITE)],
			[SHELL_GUARD, "S4 VfxTex._make_shellhalf_texture", func(): return VfxTex._make_shellhalf_texture()]]:
		var src_t := _fresh(str(e[0]))
		_ok("③ %s: 源图在加载器下仍是真贴图(< 阈值, 碰不到占位)" % e[1], _has_px(src_t),
			"%s %s" % [str(e[0]).get_file(), str(src_t.get_size() if src_t != null else null)])
		var m := _measure(e[2])
		_ok("③ %s: 0 报错、出了图" % e[1], m[1] == 0 and m[0] != null, "errors=%d last=%s" % [m[1], m[3]])
		_site(_has_px(src_t) and m[1] == 0)

	## S5 scripts/util/equip_icon.gd _trimmed: 任意贴图裁留边 —— 喂占位
	var m5 := _measure(func(): return EquipIcon._trimmed(ph_big))
	_ok("③ S5 EquipIcon._trimmed(占位): 0 报错, 原样返回", m5[1] == 0 and is_same(m5[0], ph_big),
		"errors=%d last=%s" % [m5[1], m5[3]])
	_site(m5[1] == 0)

	## S6 scripts/scenes/MainMenuScene.gd _currency_icon: 货币条的图标逐个染色 —— 小图, 加载器放行
	var mm_src := FileAccess.get_file_as_string("res://scripts/scenes/MainMenuScene.gd")
	var i_bar := mm_src.find("_currency_bar([")
	var bar_txt := mm_src.substr(i_bar, maxi(0, mm_src.find("])", i_bar) - i_bar)) if i_bar >= 0 else ""
	var re := RegEx.create_from_string("\"(res://[^\"]+\\.png)\"")
	var icons: Array = []
	for mt in re.search_all(bar_txt):
		icons.append(mt.get_string(1))
	_ok("③ S6 分母: 主菜单货币条的图标路径 ≥ 1 个(从源码里抠)", icons.size() >= 1, str(icons))
	var mm = load("res://scripts/scenes/MainMenuScene.gd").new()
	var s6_ok := icons.size() >= 1
	for p in icons:
		var it := _fresh(str(p))
		var m6 := _measure(func(): return mm._currency_icon(str(p), Color(0.122, 0.561, 0.247)))
		var tr: TextureRect = m6[0] as TextureRect
		var fine: bool = _has_px(it) and m6[1] == 0 and tr != null and tr.texture != null
		_ok("③ S6 MainMenu._currency_icon(%s): 源图仍是真贴图、0 报错、出了图" % str(p).get_file(), fine,
			"errors=%d last=%s" % [m6[1], m6[3]])
		s6_ok = s6_ok and fine
		if tr != null:
			tr.free()
	mm.free()
	_site(s6_ok)

	## S7 scripts/scenes/InventoryScene.gd _card_portrait: 背包龟卡立绘裁留边 —— 喂占位(全身表就是它的输入)
	var inv = load("res://scripts/scenes/InventoryScene.gd").new()
	var m7 := _measure(func(): return inv._card_portrait(ph_big, Rect2(0, 0, 250, 250), Rect2(0, 0, 120, 120)))
	var c7: Control = m7[0] as Control
	var s7_ok: bool = m7[1] == 0 and c7 != null
	_ok("③ S7 InventoryScene._card_portrait(占位): 0 报错、出了卡片立绘", s7_ok,
		"errors=%d last=%s" % [m7[1], m7[3]])
	if c7 != null:
		c7.free()
	inv.free()
	_site(s7_ok)

	## S8 scripts/scenes/battle/potion_eq_vfx.gd _white_silhouette: 药水光晕的白剪影 —— 喂占位(单位精灵就是全身表)
	var m8 := _measure(func(): return PotionEqVfx._white_silhouette(ph_big))
	var sil: Texture2D = m8[0] as Texture2D
	_ok("③ S8 PotionEqVfx._white_silhouette(占位): 0 报错、出了剪影", m8[1] == 0 and sil != null,
		"errors=%d last=%s" % [m8[1], m8[3]])
	_ok("③ S8 剪影与源图同尺寸(光晕片的帧切分不变)", sil != null and sil.get_size() == ph_big.get_size(),
		"%s vs %s" % [str(sil.get_size() if sil != null else null), str(ph_big.get_size())])
	_ok("③ S8 剪影照挂出处键(录流按路径重建)", sil != null and sil.has_meta(&"stream_gen")
		and str(sil.get_meta(&"stream_gen")).contains(BIG), str(sil.get_meta(&"stream_gen") if sil != null and sil.has_meta(&"stream_gen") else null))
	var m8b := _measure(func(): return PotionEqVfx.gen_white_silhouette(BIG))
	_ok("③ S8 按路径的入口 gen_white_silhouette: 0 报错", m8b[1] == 0 and m8b[0] != null,
		"errors=%d last=%s" % [m8b[1], m8b[3]])
	_site(m8[1] == 0 and m8b[1] == 0 and sil != null)

	## S9 scripts/scenes/battle/battle_world_builder.gd _fg_band_layer_lift: 前景剪影带(800×224, 大)分层增益
	var bwb := BattleWorldBuilder.new(null)
	var fg: Texture2D = load(FG_BAND)
	_ok("③ S9 前提: 前景剪影带在加载器下是占位(这一处在陪练号上真会碰到)", _is_ph(fg), str(fg))
	var m9 := _measure(func(): return bwb._fg_band_layer_lift(fg, [1.0, 1.2, 1.5]))
	var r9: Array = m9[0] if m9[0] is Array else []
	_ok("③ S9 _fg_band_layer_lift(占位): 0 报错, 原样退回 [贴图, 1.0]",
		m9[1] == 0 and r9.size() == 2 and is_same(r9[0], fg) and float(r9[1]) == 1.0,
		"errors=%d warnings=%d last=%s" % [m9[1], m9[2], m9[3]])
	_site(m9[1] == 0 and _is_ph(fg))

	## S10 同文件 _tex_img: 灯具 / 树干取像素。它自己判了空; 但挂灯那段(_build_hang_lamps)对灯图的 _tex_img 结果
	##   **没判空**就 get_width() ⇒ 灯图必须一直是小图。这里逐张钉住: 哪天换了张大灯图, 这里先红。
	var m10 := _measure(func(): return bwb._tex_img(ph_big))
	_ok("③ S10 _tex_img(占位): 0 报错, 返回 null(调用方按空跳过)", m10[1] == 0 and m10[0] == null,
		"errors=%d last=%s" % [m10[1], m10[3]])
	var lamps: Array = []
	for th in ArenaTheme.THEMES:
		var cfg: Dictionary = ArenaTheme.THEMES[th]
		for nm in cfg.get("hang_lamp_tex", []):
			if not lamps.has(str(nm)):
				lamps.append(str(nm))
	var lamp_bad: Array = []
	for nm in lamps:
		if not _has_px(_fresh(THEME_TEX % str(nm))):
			lamp_bad.append(nm)
	_ok("③ S10 挂灯用的灯图(没判空那一段的输入)在加载器下全是真贴图", lamps.size() >= 1 and lamp_bad.is_empty(),
		"灯图 %d 张, 变成占位的: %s" % [lamps.size(), str(lamp_bad)])
	_site(m10[1] == 0 and lamps.size() >= 1 and lamp_bad.is_empty())
	bwb = null
	ph_big = null
	fg = null


func _site(ok: bool) -> void:
	if ok:
		_sites_hit += 1


## ⑤ 拆掉加载器后复原; 补了空值判断的两处在真贴图下照旧出图。
func _part5() -> void:
	print("--- ⑤ 拆掉加载器 ⇒ 复原; 真贴图那条路不受补丁影响 ---")
	var t := _fresh(BIG)
	_ok("⑤ 拆掉后同一张大贴图又是真贴图、有像素", _has_px(t))
	t = null
	var m1 := _measure(func(): return PreloadCache.menu_bg_tile_tex())
	var tile: Texture2D = m1[0] as Texture2D
	_ok("⑤ PreloadCache.menu_bg_tile_tex(真贴图): 0 报错、出 512×512 平铺图",
		m1[1] == 0 and tile != null and tile.get_size() == Vector2(512, 512), "errors=%d %s" % [m1[1], str(tile)])
	var real: Texture2D = _fresh(EDGE_BELOW)
	var m8 := _measure(func(): return PotionEqVfx._white_silhouette(real))
	var sil: Texture2D = m8[0] as Texture2D
	var im: Image = sil.get_image() if sil != null else null
	var white := false
	if im != null:
		var ur := im.get_used_rect()
		if ur.size.x > 0:
			var c := Color(0, 0, 0, 0)
			for x in range(ur.position.x, ur.end.x):
				c = im.get_pixel(x, ur.position.y + ur.size.y / 2)
				if c.a > 0.5:
					break
			white = c.a > 0.5 and c.r > 0.99 and c.g > 0.99 and c.b > 0.99
	_ok("⑤ PotionEqVfx._white_silhouette(真贴图): 0 报错、同尺寸、不透明处是白的",
		m8[1] == 0 and sil != null and sil.get_size() == real.get_size() and white,
		"errors=%d size=%s white=%s" % [m8[1], str(sil.get_size() if sil != null else null), str(white)])
