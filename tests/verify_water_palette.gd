extends Node
## verify_water_palette.gd — 水面 shader 的颜色必须等于【硬锁调色板】里写的那两个值
##
## ★由来(2026-09-18): 硬锁表(docs/design/场景地图方案.md §4)写的是**两个**色:
##     水 water: #1fb8c4   →   高光: #3fe9e0
##   而实际代码里 `shallow_col` 长期是 (0.30,0.93,0.90) ≈ #4dede6 —— **几乎就是那个高光色**。
##   又因为潟湖只有 2~3 格宽 ⇒ 水深 `depth` 始终很低 ⇒ **整条水带被刷成高光色而不是水体色**。
##   实拍后果: 全屏亮部里 86% 是这条水带, 判据「亮部饱和度中位 ≤0.60」实测 0.696 红。
##   ★**漂了两个月没人发现, 因为没有任何一条门禁把 shader 的颜色和调色板对过账。**
##
## ⇒ 这条门禁就是那笔账。判据落在**产品真用的 shader 默认值**上,
##   不落在"文档里写了没有" —— 文档写了代码不照做, 正是上面那个病。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_water_palette.tscn --quit-after 600

const BWB := preload("res://scripts/scenes/battle/battle_world_builder.gd")

## ★硬锁调色板(docs/design/场景地图方案.md §4)。**照抄一份到这里是有意的**:
##   门禁就是要在"代码"与"拍板的值"之间做独立对账, 两边都从同一处读就成恒真式了。
##   改这里 == 改用户 2026-07-13 拍板的硬锁, 要用户点头。
const LOCK_WATER := Color8(0x1f, 0xb8, 0xc4)     # #1fb8c4 水体
const LOCK_CREST := Color8(0x3f, 0xe9, 0xe0)     # #3fe9e0 高光
const TOL := 0.012                                # 8-bit 量化 + sRGB 往返的余量

var _ok := 0
var _fail := 0

func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])

func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= TOL and absf(a.g - b.g) <= TOL and absf(a.b - b.b) <= TOL

func _hex(c: Color) -> String:
	return "#%02x%02x%02x" % [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]

## 从【已剥注释】的 shader 源码里抠出 `uniform vec4 <name> ... = vec4(a, b, c, ...)` 的前三个分量。
## 解析不出来返回 null —— **不做静默兜底**(兜底成默认色就等于这条门禁永远绿)。
func _parse_vec4(clean: String, uname: String) -> Variant:
	var key := "uniform vec4 " + uname
	var i: int = clean.find(key)
	if i < 0:
		return null
	var eq: int = clean.find("=", i)
	var semi: int = clean.find(";", i)
	if eq < 0 or semi < 0 or eq > semi:
		return null
	var lp: int = clean.find("(", eq)
	var rp: int = clean.find(")", lp)
	if lp < 0 or rp < 0 or rp > semi:
		return null
	var parts: PackedStringArray = clean.substr(lp + 1, rp - lp - 1).split(",")
	if parts.size() < 3:
		return null
	var v := []
	for j in range(3):
		var s: String = parts[j].strip_edges()
		if not s.is_valid_float():
			return null
		v.append(s.to_float())
	return Color(v[0], v[1], v[2])


func _ready() -> void:
	await get_tree().process_frame
	print("── 水面 shader 颜色 ↔ 硬锁调色板 ──")
	var sh: Shader = BWB.SH_WATER
	_chk("★分母: 水面 shader 加载得到", sh != null)
	if sh == null:
		_done(); return

	## ★读【shader 的默认值】而不是材质上的覆写 —— 产品侧 `tile_material` 并不覆写这两个,
	##   所以真正生效的就是默认值。用 RenderingServer 直接问引擎, 不去解析源码文本
	##   (解析文本是"看着像对"的假判据: 注释里写一个值、uniform 写另一个, 文本判据分不出来)。
	var names: Array = []
	for u in sh.get_shader_uniform_list():
		names.append(str(u.get("name", "")))
	_chk("★分母: shader 里解析到 %d 个 uniform" % names.size(), names.size() >= 5, str(names.size()))
	_chk("① uniform `shallow_col` 存在(改名了这条会红, 不会静默放过)", names.has("shallow_col"))
	_chk("① uniform `crest_col` 存在", names.has("crest_col"))
	if not (names.has("shallow_col") and names.has("crest_col")):
		_done(); return

	## ★★读值这一步换过一次实现, 记下来:
	##   第一版用 `RenderingServer.shader_get_parameter_default()` —— **无头下返回 null**
	##   (渲染器是 dummy, shader 没真编译)。★是上面那条【分母断言】当场把它抓出来的,
	##   否则 null 会被静默当成"取到了"然后一路绿 —— 这条门禁就成了摆设。
	##   ⇒ 改成解析 `.gdshader` 源码, 但做两件事避免"文本判据"的老毛病:
	##     ① **先剥掉注释再匹配**(否则注释里写的值会冒充真值 —— 这文件注释里就写着 #1fb8c4);
	##     ② 上面已经用【编译后的 shader】确认过 uniform 名字真的存在 ⇒
	##        改名/删 uniform 会先红在 ① 那条, 文本判据不会指着一个不存在的东西空转。
	var src_f := FileAccess.open(sh.resource_path, FileAccess.READ)
	_chk("★分母: 读得到 shader 源码 %s" % sh.resource_path, src_f != null)
	if src_f == null:
		_done(); return
	var src := src_f.get_as_text()
	src_f.close()
	var clean := ""
	for line in src.split("
"):
		var i: int = line.find("//")
		clean += (line.substr(0, i) if i >= 0 else line) + "
"
	var w = _parse_vec4(clean, "shallow_col")
	var k = _parse_vec4(clean, "crest_col")
	_chk("★分母: 两个 uniform 的默认值都解析得到(不是 null)", w != null and k != null)
	if w == null or k == null:
		_done(); return
	var wc: Color = w
	var kc: Color = k
	print("    实测 shallow_col=%s  crest_col=%s" % [_hex(wc), _hex(kc)])
	_chk("② ★水体色 == 硬锁 #1fb8c4(漂成高光色就是这条没人看着才发生的)",
		_near(wc, LOCK_WATER), "实测 %s · 应为 %s" % [_hex(wc), _hex(LOCK_WATER)])
	_chk("② ★高光色 == 硬锁 #3fe9e0",
		_near(kc, LOCK_CREST), "实测 %s · 应为 %s" % [_hex(kc), _hex(LOCK_CREST)])

	## ③ 水体必须【比高光暗】—— 这条是形状判据, 挡住"两个值被对调"这种改法
	var lw: float = 0.299 * wc.r + 0.587 * wc.g + 0.114 * wc.b
	var lk: float = 0.299 * kc.r + 0.587 * kc.g + 0.114 * kc.b
	_chk("③ ★水体明度 < 高光明度(对调了也会红)", lw < lk, "水体 %.3f < 高光 %.3f" % [lw, lk])

	## ④ 陆地那张调色板没被顺手动过
	var cols: Dictionary = BWB.TILE_COLS
	_chk("④ ★分母: TILE_COLS 有 4 种 type", cols.size() == 4, "%d 种" % cols.size())
	_chk("④ ★TILE_COLS[1](水)仍是硬锁 #1fb8c4",
		_near(cols.get(1, Color.BLACK), LOCK_WATER), _hex(cols.get(1, Color.BLACK)))
	_done()

func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 水面调色板 (%d/%d)" % [_ok, _ok])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok])
	get_tree().quit(1 if _fail > 0 else 0)
