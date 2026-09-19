extends Node
## verify_ground_palette — 地面调色板四项**逐个**钉住，且与文档 §4 那张表对账。
##
## ★★为什么有它（2026-09-20）：
##   所谓「调色板硬锁」（`docs/design/场景地图方案.md §4`、`场景地图方案.md §5 铁律`），
##   实际上**只有「水」那一项有门禁看着**（`verify_water_palette` ④）。
##   `TILE_COLS` 里的 grass / stone / sand 改了 **不会有任何门禁红** ——
##   跟当年「水体色漂成高光色、两个月没人发现」是**同一个形状的洞**，只是还没发作。
##   我 2026-09-20 换暖石台调色板时才撞见这件事，顺手把洞补上。
##
## ★★判据形状：**拿文档 §4 的表去对产品常量**，不是拿产品常量对自己。
##   `verify_tile_texture ④` 那条写的是「材质 base_col == TILE_COLS」——
##   那测的是**接线**（材质真的用了调色板），不是**取值**；两边同源，改 TILE_COLS 它不会红。
##   本门禁解析 §4 那张 Markdown 表里的 hex，与 `TILE_COLS` 逐项比。
##   ⇒ 改代码不改文档 → 红；改文档不改代码 → 红；两边一起改 → 绿（那才是**有意的**改动）。
##
## ★换暖石台的依据（153 帧真实游戏内画面实测，见
##   `docs/studies/20260920-咩咩启示录美术逐帧-配色与结构.md`）：
##   参考主色里**洋红-紫-暖橙占 54.0%、青 180–210 只占 3.2%**，本项目整个压在那 3.2% 上
##   （暖色只有 2.3%）。三套候选实拍量过：**A 暖石台 23.3%** / B 洋红紫 4.1% / C 橄榄绿 6.6%。
##   ★水色**不动** —— 参考自己也画水，只是水**比地面暗**（v0.19.413 已按此压暗）；
##     青水 + 暖石台 = **冷暖对比**而不是同色堆叠。

const BWB := preload("res://scripts/scenes/battle/battle_world_builder.gd")
const DOC := "res://docs/design/场景地图方案.md"

## type 下标 → 文档表里那一行的行首名字
const ROWS := [
	[0, "主地面 grass"],
	[1, "水 water"],
	[2, "石台 stone"],
	[3, "岸 sand"],
]

var _pass := 0
var _fail := 0


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [name, extra])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, extra])


## 从 §4 的表里取某一行的**第一个** hex（`#rrggbb`）。取不到返回 ""。
func _hex_of(doc: String, row_name: String) -> String:
	for line in doc.split("\n"):
		if not line.begins_with("|"):
			continue
		if not line.contains(row_name):
			continue
		var i := line.find("`#")
		if i < 0:
			continue
		var h := line.substr(i + 1, 7)
		if h.length() == 7:
			return h.to_lower()
	return ""


func _ready() -> void:
	await get_tree().process_frame

	var f := FileAccess.open(DOC, FileAccess.READ)
	_chk("① ★分母: 场景地图方案.md 打得开", f != null, DOC)
	if f == null:
		_done()
		return
	var doc := f.get_as_text()
	f.close()
	## ★分母：文档里真的有 §4 那节。节名改了就得有人发现，不能静默跳过。
	_chk("① ★分母: 文档里有【4. 调色板】这一节", doc.contains("## 4. 调色板"))

	var cols: Dictionary = BWB.TILE_COLS
	_chk("① ★分母: TILE_COLS 有 4 种 type", cols.size() == 4, "%d 种" % cols.size())

	var matched := 0
	for row in ROWS:
		var ti: int = int(row[0])
		var nm: String = str(row[1])
		var want_hex := _hex_of(doc, nm)
		## ★分母：这一行在文档里找得到。找不到 = 判据没作用在它身上，不是"通过"。
		_chk("② ★分母: §4 表里找得到「%s」这一行" % nm, want_hex != "", want_hex)
		if want_hex == "":
			continue
		var want := Color(want_hex)
		var got: Color = cols.get(ti, Color.BLACK)
		var same: bool = absf(got.r - want.r) < 0.004 and absf(got.g - want.g) < 0.004 \
			and absf(got.b - want.b) < 0.004
		if same:
			matched += 1
		_chk("③ ★type %d「%s」: TILE_COLS == §4 表里的 %s" % [ti, nm, want_hex], same,
			"实得 #%s" % got.to_html(false))

	## ★★分母：四项**全部**比对过。少比一项就等于那一项没人看着 —— 这正是本门禁要补的洞。
	_chk("④ ★★四项全部与文档对上(少一项就是又留了个没人看着的洞)", matched == 4,
		"对上 %d/4" % matched)

	## ★水那一项另有 `verify_water_palette` 在钉，这里再钉一次是**有意的重复** ——
	##   两条判据走的是不同的源（那条读 shader uniform，这条读 TILE_COLS），
	##   同时红才说明是真改了，只红一条说明两处漂开了。
	_chk("⑤ 水仍是 #1fb8c4(与 verify_water_palette 交叉验证)",
		_hex_of(doc, "水 water") == "#1fb8c4",
		_hex_of(doc, "水 water"))

	_done()


func _done() -> void:
	var total := _pass + _fail
	if _fail == 0:
		print("ALL PASS — 地面调色板对账 (%d/%d)" % [_pass, total])
	else:
		print("FAILED — 地面调色板对账 (%d/%d)" % [_pass, total])
	get_tree().quit(1 if _fail > 0 else 0)
