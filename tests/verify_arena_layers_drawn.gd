extends Node
## verify_arena_layers_drawn.gd — 主题的九层**真的画出来了**(不只是配置齐)
##
## ★由来: 方案书 `docs/plans/20261003-四版完整地图.md` §4.4 第 4 条 ——
##   `verify_arena_themes` 只证明**配置**齐, 而周边环/前景/灯具/粒子/障碍/中景那几层「配置在、渲染不在」。
##   本条量的是**产品真的建出来的节点**, 按具名容器逐层点名。
## ★★两条建场路径都要量: 调试场/门禁走 `_build_tilemap_decor`, **真对局(双路)还会再跑 `_build_map_props`** ——
##   2026-10-04 实拍发现主题在后一条路上漏了 4 道水面光柱 + 满场气泡 + 原礁石障碍 + 第二遍主题环,
##   而原有门禁全只建调试场, 一条都没抓到。⇒ 这里建完调试场后**再调一次真对局用的同一个函数**。
## ★只验 `ArenaTheme.DRAWN` 里的版(用户拍板先做暗林一版到位); base 只验「这条判据看得见光柱」(分母)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")
const R_MAX := 1.22        # 同 verify_decor_grounded: 超出 = 摆到岛外黑海面上, 读作悬空

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 主题各层真的画出来了 ===")
	var keep: String = AT.active
	RB.DEBUG_EDIT = true
	_ok("★分母: 至少有一版标成「已画出来」", AT.DRAWN.size() >= 1, str(AT.DRAWN))

	## ── base: 证明「找光柱」这件事本身找得到(否则下面「主题 0 道」恒真) ──
	AT.active = AT.V0_BASE
	var sb = RB.new()
	add_child(sb)
	await get_tree().process_frame
	await get_tree().process_frame
	sb._world_builder._build_map_props()
	var base_shafts: int = _count_meta(sb._world, "light_shaft")
	_ok("[base] ★分母: 真对局那条路在 base 下画 4 道水面光柱(看得见才能断言主题里没有)", base_shafts == 4, "%d 道" % base_shafts)
	sb.queue_free()
	await get_tree().process_frame

	for th in AT.DRAWN:
		AT.active = str(th)
		var cfg: Dictionary = AT.cfg()
		var s = RB.new()
		add_child(s)
		await get_tree().process_frame
		await get_tree().process_frame
		s._world_builder._build_map_props()          # ★真对局(dual_lane_flow)调的同一个函数
		await get_tree().process_frame
		var A: Rect2 = RB.ARENA
		var c3: Vector3 = s._world_pos(A.position + A.size * 0.5, 0.0)
		var e3: Vector3 = s._world_pos(A.end, 0.0)
		var hx: float = absf(e3.x - c3.x)
		var hz: float = absf(e3.z - c3.z)

		## ① 顶上光柱 / 满场气泡: 一道一颗都不许有
		_ok("[%s] ★★真对局路径: 水面光柱 0 道(用户「还有顶上那4个光柱？」)" % th,
			_count_meta(s._world, "light_shaft") == 0, "%d 道" % _count_meta(s._world, "light_shaft"))

		## ② 主题环只建一遍(两条路各建一遍 = 同位置叠两层)
		var rings: Array = _all_named(s._world, "ThemeRing")
		_ok("[%s] ★★主题环只有一个(真对局那条路不许再建第二遍)" % th, rings.size() == 1, "%d 个" % rings.size())

		## ③ 前景框边: 挂在相机上的那条剪影带
		var fg: String = str(cfg.get("fg_band", ""))
		var fg_n := 0
		for ch in s._cam.get_children():
			if ch is Sprite3D and str(ch.get_meta("fg_band", "")) == fg and (ch as Sprite3D).texture != null:
				fg_n += 1
		_ok("[%s] ★前景框边真的挂在相机上(%s)" % [th, fg], fg_n >= 1, "%d 张" % fg_n)

		## ④ 挡路障碍: 换成主题外观, 而且看起来多宽就挡多宽
		var props: Node = s._world.find_child("MapProps", true, false)
		_ok("[%s] ★分母: 找得到障碍容器 MapProps" % th, props != null)
		var reef := 0
		for sp in _all_sprites(props):
			var tx: Texture2D = (sp as Sprite3D).texture
			if tx != null and tx.resource_path.get_file().begins_with("reef_"):
				reef += 1
		_ok("[%s] ★★障碍里没有默认画面的珊瑚礁(reef_*)" % th, reef == 0, "%d 件" % reef)
		var tobs: Array = _with_meta(props, "vis_w")   # ★同名兄弟会被引擎改名(@Node3D@N), 按元数据认
		_ok("[%s] ★分母: 主题障碍件数 == 玩法障碍数" % th, tobs.size() == s._obstacles.size() and tobs.size() > 0,
			"%d / %d" % [tobs.size(), s._obstacles.size()])
		var bad_w: Array = []
		var k := 0
		for ob in s._obstacles:
			if k >= tobs.size():
				break
			var spr: Sprite3D = tobs[k]
			k += 1
			if spr == null or spr.texture == null:
				bad_w.append("第%d件没精灵" % k)
				continue
			## 视觉半宽(游戏 px) = 图宽 × pixel_size ÷ WS ÷ 2 ; 与碰撞 rx 比
			var half_px: float = float(spr.texture.get_width()) * spr.pixel_size / RB.WS * 0.5
			var rx: float = float(ob["rx"])
			if absf(half_px - rx) / rx > 0.2:
				bad_w.append("%s 视觉半宽 %.1f vs rx %.1f" % [spr.texture.resource_path.get_file(), half_px, rx])
		_ok("[%s] ★★每件障碍的视觉半宽与碰撞 rx 差 ≤20%%(用户 2026-07-21「生效范围比看起来的大」)" % th,
			bad_w.is_empty(), str(bad_w))

		## ④b 布局物件不许压在障碍上(2026-10-04: 布局表一格物件堆正落在下墙碰撞椭圆中心, 两图叠成一坨读作怪)
		##   只验开了 layout_clear_obstacles 的版(暗林没开: 布局表四版共用, 改它会动已认可的暗林)。
		if bool(cfg.get("layout_clear_obstacles", false)):
			var lp: Node = s._world.find_child("LayoutProps", true, false)
			var lps: Array = []
			for sp in _all_sprites(lp):
				if not (sp as Node).is_queued_for_deletion():
					lps.append(sp)
			_ok("[%s] ★分母: 布局物件 LayoutProps ≥ 10 件" % th, lps.size() >= 10, "%d 件" % lps.size())
			var on_ob: Array = []
			for sp in lps:
				var p: Vector3 = (sp as Node3D).global_position
				for ob in s._obstacles:
					var o3: Vector3 = s._world_pos(ob["c"], 0.0)
					var dx: float = (p.x - o3.x) / (float(ob["rx"]) * RB.WS * 1.3)
					var dz: float = (p.z - o3.z) / (float(ob["ry"]) * RB.WS * 2.5)   # 纵深放大: 站在墙身后 2 个 ry 内的立图会被墙压住下半截(屏幕上叠成一坨)
					if dx * dx + dz * dz < 1.0:
						on_ob.append("%s 压在 %s 上" % [(sp as Sprite3D).texture.resource_path.get_file(), str(ob["img"])])
			_ok("[%s] ★★没有布局物件和障碍在屏幕上叠成一坨(碰撞椭圆横×1.3 纵深×2.5)(两图叠成一坨读作怪)" % th, on_ob.is_empty(), str(on_ob))

		## ⑤ 中景: 有, 站在平台边沿以内, 只在上半圈
		var mid: Node = s._world.find_child("ThemeMid", true, false)
		var mids: Array = _all_sprites(mid)
		_ok("[%s] ★分母: 中景容器 ThemeMid 至少 4 件" % th, mids.size() >= 4, "%d 件" % mids.size())
		var bad_mid: Array = []
		for sp in mids:
			var p: Vector3 = (sp as Node3D).global_position
			var r: float = Vector2((p.x - c3.x) / hx, (p.z - c3.z) / hz).length()
			if r > R_MAX or p.z > c3.z:
				bad_mid.append("r=%.2f z%s中心" % [r, ">" if p.z > c3.z else "<"])
		_ok("[%s] ★★中景都站在边沿以内(r≤%.2f)且只在上半圈(下半圈的大件会挡龟)" % [th, R_MAX],
			bad_mid.is_empty(), str(bad_mid))

		## ⑥ 吊灯: 每盏的支架底板必须压在宿主树干的树皮上(不许悬空)
		var hang: Node = s._world.find_child("ThemeHangLamps", true, false)
		var lamps: Array = []
		for sp in _all_sprites(hang):
			if (sp as Node).has_meta("plate_px"):   # 灯本体(光晕也挂 host, 但没有底板)
				lamps.append(sp)
		_ok("[%s] ★分母: 吊灯至少 3 盏" % th, lamps.size() >= 3, "%d 盏" % lamps.size())
		var bad_hang: Array = []
		for L in lamps:
			var host: Sprite3D = (L as Sprite3D).get_meta("host", null)
			if host == null or not is_instance_valid(host):
				bad_hang.append("无宿主")
				continue
			var pl: Vector2 = (L as Sprite3D).get_meta("plate_px", Vector2(-1, -1))
			## ★独立重算(不调产品的 sprite_px_world): 底板像素 → 世界 → 宿主贴图像素, 查那格是不是不透明
			var w: Vector3 = _px_world(s, L, pl.x, pl.y)
			var hp: Vector2 = _world_px(s, host, w)
			var im: Image = host.texture.get_image()
			if im.is_compressed():
				im.decompress()
			var ix: int = int(floor(hp.x))
			var iy: int = int(floor(hp.y))
			var inside: bool = ix >= 0 and iy >= 0 and ix < im.get_width() and iy < im.get_height() and im.get_pixel(ix, iy).a > 0.5
			if not inside:
				bad_hang.append("底板落在宿主像素 (%.1f,%.1f) = 空" % [hp.x, hp.y])
			## 灯本身吊在半空(公告板的「上」朝后倾, 投到地面会往后跑), 落地的是宿主树干 ⇒ 量宿主的脚
			var hpos: Vector3 = host.global_position
			var r: float = Vector2((hpos.x - c3.x) / hx, (hpos.z - c3.z) / hz).length()
			if r > R_MAX:
				bad_hang.append("宿主 r=%.2f 超出边沿" % r)
		_ok("[%s] ★★每盏吊灯的支架底板都压在宿主树干的不透明像素上(用户「装饰物乱飞到上面」)" % th,
			bad_hang.is_empty() and not lamps.is_empty(), str(bad_hang))
		var n_light := 0
		for ch in (hang.get_children() if hang != null else []):
			if ch is OmniLight3D:
				n_light += 1
		_ok("[%s] ★吊灯是真光源(每盏一个 OmniLight3D)" % th, n_light == lamps.size() and n_light > 0, "%d 光 / %d 灯" % [n_light, lamps.size()])

		s.queue_free()
		await get_tree().process_frame
	AT.active = keep
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 主题各层真的画出来了" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 公告板精灵像素 → 世界(独立实现: 本地 y = offset.y + h/2 - py, 轴 = 相机右/上)
func _px_world(s, sp: Sprite3D, px: float, py: float) -> Vector3:
	var b: Basis = s._cam.global_transform.basis
	var lx: float = sp.offset.x + px - float(sp.texture.get_width()) * 0.5
	var ly: float = sp.offset.y + float(sp.texture.get_height()) * 0.5 - py
	return sp.global_position + (b.x * lx * sp.scale.x + b.y * ly * sp.scale.y) * sp.pixel_size


## 世界点 → 精灵贴图像素(上式的逆; 把点投到精灵平面上)
func _world_px(s, sp: Sprite3D, w: Vector3) -> Vector2:
	var b: Basis = s._cam.global_transform.basis
	var d: Vector3 = w - sp.global_position
	var lx: float = d.dot(b.x) / (sp.pixel_size * sp.scale.x)
	var ly: float = d.dot(b.y) / (sp.pixel_size * sp.scale.y)
	return Vector2(lx - sp.offset.x + float(sp.texture.get_width()) * 0.5,
		sp.offset.y + float(sp.texture.get_height()) * 0.5 - ly)


func _count_meta(root: Node, key: String) -> int:
	return _with_meta(root, key).size()


func _with_meta(root: Node, key: String) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if c.has_meta(key):
			out.append(c)
		out.append_array(_with_meta(c, key))
	return out


func _count_named(root: Node, prefix: String) -> int:
	return _all_named(root, prefix).size()


func _all_named(root: Node, prefix: String) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if prefix in str(c.name):   # ★同名兄弟会被引擎改成 @Name@N, 用「包含」不用「开头」
			out.append(c)
		out.append_array(_all_named(c, prefix))
	return out


func _all_sprites(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if c is Sprite3D:
			out.append(c)
		out.append_array(_all_sprites(c))
	return out
