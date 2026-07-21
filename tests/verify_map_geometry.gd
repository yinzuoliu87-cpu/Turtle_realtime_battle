extends Node
## verify_map_geometry.gd — 守卫「贴地特效不被地砖埋」+「障碍判定贴合视觉」
##
## 两件都是用户 2026-07-21 亲眼看出来的问题, 且都属于【改坏了不报错、只是悄悄不对】,
## 只能靠测试守。
##
## A. 地砖埋特效:
##    BoxMesh 以 transform 为几何中心, 砖厚 TILE_THICK。若砖心放在 y=0, 上表面就在 +厚/2,
##    于是所有 y < 厚/2 的贴地特效(技能环 0.05 / 影子 0.02 / 队色环 0.015 …)全被埋进砖里。
##    修法是建砖时统一下沉 TILE_SINK, 让上表面落在 y=0。
##    → 断言 TILE_SINK == TILE_THICK/2, 且源码里两条建砖路径都真的减了它。
##
## B. 障碍判定 vs 视觉:
##    _map_billboard 按【图高】把立绘归一到 h 米, 宽度按图比例被动决定。
##    所以视觉半宽是【算得出来的】: 图宽 × (h/图高) / WS / 2。
##    rx 必须贴合这个值 —— 旧值是它的 2.5~3.0 倍, 单位离礁石老远就拐弯。
##    → 逐个障碍算出视觉半宽, 断言 rx 落在合理区间(不小于视觉、不超过视觉的 1.35 倍)。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SRC := "res://scripts/scenes/RealtimeBattle3DScene.gd"

var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_test_tile_sink()
	_test_obstacle_vs_visual()
	print("ALL PASS — 地图几何(特效不被埋 + 障碍贴合视觉)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## A. 地砖下沉, 上表面归零
func _test_tile_sink() -> void:
	_ok("TILE_SINK == 砖厚的一半(上表面落在 y=0)",
		is_equal_approx(RTScene.TILE_SINK, RTScene.TILE_THICK * 0.5),
		"厚=%.3f 沉=%.3f" % [RTScene.TILE_THICK, RTScene.TILE_SINK])

	var src := _src()
	# 两条建砖路径(json 路径 + fallback 程序化路径)都必须减 TILE_SINK
	var n_sink := src.count("- TILE_SINK")
	_ok("★两条建砖路径都下沉了(json + fallback)", n_sink >= 2,
		"源码里 `- TILE_SINK` 出现 %d 次(应 >=2)" % n_sink)
	# 砖厚不许再写死 0.15 魔数(否则改了常量而漏改这里 → 上表面又不在 y=0)
	var magic := src.contains("0.15, tw_m * 0.94")
	_ok("砖厚用常量而非魔数 0.15", not magic,
		"仍有写死的 0.15 砖厚" if magic else "")

	# ★贴地特效的基准: 上表面 y=0, 所以任何 y>0 的贴地 VFX 都该露出来
	var top_y: float = RTScene.TILE_THICK * 0.5 - RTScene.TILE_SINK
	_ok("★地砖上表面 y==0(贴地特效的基准面)", is_equal_approx(top_y, 0.0), "上表面 y=%.4f" % top_y)


## B. 障碍 rx 贴合视觉半宽
func _test_obstacle_vs_visual() -> void:
	var scene = RTScene.new()
	add_child(scene)
	# 触发 _build_map_props 才有 _obstacles; 直接读它的常量口径自己算更稳
	var obs: Array = _parse_obstacles()
	_ok("解析到障碍定义", obs.size() >= 3, "%d 个" % obs.size())

	var checked := 0
	var bad: Array = []
	for ob in obs:
		var img: String = str(ob["img"])
		var path := "res://assets/sprites/map/%s.png" % img
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		if tex == null:
			continue
		var tw: float = float(tex.get_width())
		var th: float = float(tex.get_height())
		if th <= 0.0:
			continue
		# _map_billboard: pixel_size = h/图高 → 视觉宽(米) = 图宽 × pixel_size
		var vis_w_m: float = tw * (float(ob["h"]) / th)
		var vis_half_px: float = (vis_w_m / RTScene.WS) * 0.5
		var rx: float = float(ob["rx"])
		checked += 1
		# rx 应在 [视觉半宽×0.9, 视觉半宽×1.35] —— 不能远小于(挡不住), 更不能远大于(老远就拐弯)
		if rx < vis_half_px * 0.9 or rx > vis_half_px * 1.35:
			bad.append("%s: rx=%.0f 视觉半宽=%.0f (%.2f倍)" % [img, rx, vis_half_px, rx / maxf(1.0, vis_half_px)])
	_ok("★障碍 rx 贴合视觉半宽(不再是 2.5~3 倍)", bad.is_empty(),
		"核了 %d 个; 超标: %s" % [checked, "; ".join(PackedStringArray(bad)) if not bad.is_empty() else "无"])
	_ok("★核对分母非空(防空检查)", checked >= 3, "checked=%d" % checked)

	# 两处外扩余量必须同源(历史上 navmesh 用 +28、放置 clamp 用 +26, 没人说得清为什么差 2)。
	# ★只查这两个落点本身, 不要全文搜 "+ 26.0" —— 文件里别处有无关的 +26.0(移动步长),
	#   搜全文会误报(我第一版就这么错了)。
	var src := _src()
	var nav_line := ""
	for line in src.split("\n"):
		if line.contains("add_obstruction_outline"):
			nav_line = line
			break
	_ok("★navmesh 障碍外扩用 OBSTACLE_MARGIN", nav_line.contains("OBSTACLE_MARGIN"),
		nav_line.strip_edges().substr(0, 100))
	var clamp_idx := src.find("func _dl_clamp_place")
	var clamp_body := src.substr(clamp_idx, 700) if clamp_idx >= 0 else ""
	_ok("★放置 clamp 障碍外扩用同一个 OBSTACLE_MARGIN",
		clamp_body.contains("OBSTACLE_MARGIN") and not clamp_body.contains("+ 26.0"),
		"_dl_clamp_place 里仍有独立数值" if not clamp_body.contains("OBSTACLE_MARGIN") else "")

	scene.queue_free()


## 从源码里解析 _obstacles 的字面量定义(不跑场景, 避免建整个战斗场)
func _parse_obstacles() -> Array:
	var src := _src()
	var out: Array = []
	var re := RegEx.new()
	re.compile("\"rx\":\\s*([0-9.]+),\\s*\"ry\":\\s*([0-9.]+),\\s*\"img\":\\s*\"([a-z_]+)\",\\s*\"h\":\\s*([0-9.]+)")
	for m in re.search_all(src):
		out.append({
			"rx": float(m.get_string(1)), "ry": float(m.get_string(2)),
			"img": m.get_string(3), "h": float(m.get_string(4)),
		})
	return out


func _src() -> String:
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s
