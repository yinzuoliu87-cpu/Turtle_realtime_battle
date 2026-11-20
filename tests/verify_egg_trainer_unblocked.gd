extends Node
## verify_egg_trainer_unblocked.gd — 四张图上, 场景装饰不许挡住两端的龟蛋与训龟大师。
##
## ★由来(用户 2026-11-20):「龟蛋和训练大师这个基本上都被啊都被一个东西遮住了，都被挡住了，看都看不到。」
##   真对局实拍(docs/plans/img-20261120c-地图优化/现状-龟蛋与训龟大师被挡.png, 暗林 1560×720):
##   左边训龟大师只露头顶(身子被边草丛 + 横木挡), 右边整只看不见; 蛋罩被大树干切一块、前面压草。
##   根因: 边草沿场地椭圆边 0.86 ~ 0.99 半径随机撒, 蛋在 0.91、大师在 0.95 —— 正好站在装饰圈里。
##
## 判据(四张图 × 两个机位 × 左右两头):
##   机位 = 默认取景 / 拉近(2.0)推到那一头(玩家想看蛋时就是这么看的)。
##   把每件装饰(下面 DECOR_ROOTS 里的精灵 / 网格)投到屏幕, **离镜头比目标近**(挡在前面)的才算,
##   与目标(真生成的龟蛋立绘 / 训龟大师立绘)屏幕框的重叠面积累加 ÷ 目标框面积 ≤ MAX_COVER。
##   ★分母: 每张图每个目标都真建出来了(立绘有贴图、框面积 > 0), 每张图参与比较的装饰件数 > 0。
## 反向验证(2026-11-20, 逐字节还原): 不跑 `_clear_base_sightlines` ⇒ 36 条红(藏 0 件 + 四张图全挡);
##   前后只比 z(不按视线深度) ⇒ 赤林左边训龟大师被树上吊灯挡 83% 红; 广告牌改回立方体包围盒 ⇒ 不红 ——
##   立方体包住真四边形, 只会多藏(每图多 5 ~ 9 件)不会漏挡, 是安全方向的近等价变异; 多藏由 MAX_HIDDEN 拦大头。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")
const DECOR_ROOTS := ["EdgeTufts", "LayoutProps", "TileDecor", "Detritus", "FieldLamps", "RimLights", "MapProps"]
const MAX_COVER := 0.05
const MAX_HIDDEN := 60           # 两头加起来最多藏这么多件(实测 36 ~ 45; 边草一圈约 170 丛); 超了说明判据宽到在清场
const EGG_INSET := 70.0          # 与 dual_lane_flow.gd 生成龟蛋那一行同一个数(verify_cam_egg_reach 核对源码)
var _fail := 0
var _n := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "   ", d)


## 贴图里真有颜色的那块(像素), 按贴图缓存。单帧精灵才用(多帧序列的整张图不代表当前帧)。
static var _used_cache: Dictionary = {}


## ★无头渲染器下 `Texture2D.get_image()` 拿不到像素(返回空) ⇒ 直接读源 PNG。
static func _image_of(tex: Texture2D) -> Image:
	var key: String = tex.resource_path
	if _used_cache.has("img:" + key):
		return _used_cache["img:" + key]
	var img: Image = null
	if key != "" and FileAccess.file_exists(key):
		img = Image.load_from_file(ProjectSettings.globalize_path(key))
	if img == null:
		img = tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	_used_cache["img:" + key] = img
	return img


## 当前这一帧里真有颜色的那块(帧内像素坐标) + 这一帧的大小。
static func _frame_used(sp: Sprite3D) -> Array:
	var tw: int = sp.texture.get_width()
	var th: int = sp.texture.get_height()
	var fr := Rect2i(0, 0, tw, th)
	if sp.region_enabled:
		fr = Rect2i(sp.region_rect)
	elif sp.hframes * sp.vframes > 1:
		var fw: int = tw / sp.hframes
		var fh: int = th / sp.vframes
		fr = Rect2i((sp.frame % sp.hframes) * fw, (sp.frame / sp.hframes) * fh, fw, fh)
	var key: String = "%s#%s" % [sp.texture.resource_path, str(fr)]
	if not _used_cache.has(key):
		var img: Image = _image_of(sp.texture)
		var ur := Rect2i(Vector2i.ZERO, fr.size)
		if img != null and fr.size.x > 0 and fr.size.y > 0:
			ur = img.get_region(fr).get_used_rect()
		_used_cache[key] = [ur, fr.size]
	return _used_cache[key]


## 精灵这一帧的四边形(本地 2D, 米, y 向上)收紧到「有颜色的区域」。
## ★四边形用 `BattleWorldBuilder.sprite_quad`(帧大小 × pixel_size + centered + offset), 不用 `get_aabb()`:
##   广告牌的包围盒是立方体、看不出 offset —— 第一版拿它量, 把脚底贴地的蛋当成一半埋在地下, 前面的草全算成挡住(假红)。
static func local_quad(sp: Sprite3D) -> Rect2:
	var q: Rect2 = BattleWorldBuilder.sprite_quad(sp)
	if sp.texture == null:
		return q
	var fu: Array = _frame_used(sp)
	var ur: Rect2i = fu[0]
	var fs: Vector2i = fu[1]
	if ur.size.x <= 0 or ur.size.y <= 0 or fs.x <= 0 or fs.y <= 0:
		return q
	var u0: float = float(ur.position.x) / float(fs.x)
	var u1: float = float(ur.end.x) / float(fs.x)
	if sp.flip_h:
		var t0: float = 1.0 - u1
		u1 = 1.0 - u0
		u0 = t0
	var v0: float = float(ur.position.y) / float(fs.y)   # 帧顶 → 四边形顶
	var v1: float = float(ur.end.y) / float(fs.y)
	var x0: float = q.position.x + u0 * q.size.x
	var x1: float = q.position.x + u1 * q.size.x
	var y1: float = q.end.y - v0 * q.size.y
	var y0: float = q.end.y - v1 * q.size.y
	return Rect2(x0, y0, x1 - x0, y1 - y0)


## 平贴在地上的东西(全局包围盒高度 < 5 厘米: 地面光斑 / 贴花)画在立着的人物下面, 挡不住。
static func is_flat(gi: GeometryInstance3D) -> bool:
	if gi is SpriteBase3D:
		var bb: bool = (gi as SpriteBase3D).billboard != BaseMaterial3D.BILLBOARD_DISABLED
		var mo = gi.material_override
		if mo is BaseMaterial3D and (mo as BaseMaterial3D).billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
			bb = true
		if bb:
			return false
	var g: AABB = gi.global_transform * gi.get_aabb()
	return g.size.y < 0.05


## 精灵 / 网格在屏幕上的框(像素)。精灵按这一帧的四边形(广告牌正对镜头立起来), 其余按全局包围盒 8 角。
static func screen_rect(cam: Camera3D, gi: GeometryInstance3D) -> Rect2:
	var pts: Array = []
	if gi is Sprite3D:
		var q: Rect2 = local_quad(gi as Sprite3D)
		var gp: Vector3 = gi.global_position
		if BattleWorldBuilder._is_billboard(gi):
			var sc: Vector3 = gi.global_transform.basis.get_scale()
			var r: Vector3 = cam.global_transform.basis.x.normalized()
			var u: Vector3 = cam.global_transform.basis.y.normalized()
			for xx in [q.position.x, q.end.x]:
				for yy in [q.position.y, q.end.y]:
					pts.append(gp + r * (float(xx) * absf(sc.x)) + u * (float(yy) * absf(sc.y)))
		else:
			for xx in [q.position.x, q.end.x]:
				for yy in [q.position.y, q.end.y]:
					pts.append(gi.global_transform * Vector3(float(xx), float(yy), 0.0))
	else:
		var xf: Transform3D = gi.global_transform
		var ab: AABB = gi.get_aabb()
		for i in range(8):
			pts.append(xf * ab.get_endpoint(i))
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in pts:
		if cam.is_position_behind(p):
			continue
		var s: Vector2 = cam.unproject_position(p)
		mn = Vector2(minf(mn.x, s.x), minf(mn.y, s.y))
		mx = Vector2(maxf(mx.x, s.x), maxf(mx.y, s.y))
	if mn.x == INF:
		return Rect2()
	return Rect2(mn, mx - mn)


## 离镜头多远(沿视线)。
static func depth(cam: Camera3D, p: Vector3) -> float:
	return -(cam.global_transform.affine_inverse() * p).z


func _decor(s) -> Array:
	var out: Array = []
	for rn in DECOR_ROOTS:
		var r: Node = s._world.find_child(rn, true, false)
		if r == null:
			continue
		for n in r.find_children("*", "GeometryInstance3D", true, false):
			var gi := n as GeometryInstance3D
			if gi == null or not gi.is_visible_in_tree():
				continue
			if gi in (s._base_domes as Dictionary).values():
				continue                      # 蛋罩是蛋自己的围栏, 不算挡
			if gi is MultiMeshInstance3D or is_flat(gi):
				continue                      # 贴地的地砖 / 草皮层 / 地面光斑
			out.append([rn, gi])
	return out


func _push(s, zoom: float, dir: float) -> void:
	s._shake_amp = 0.0
	s._cam_zoom = zoom
	s._cam_pan = Vector3.ZERO
	s._apply_cam_zoom()
	for _k in range(60 if dir != 0.0 else 0):
		s._cam_pan_by(-dir * 80.0, 0.0)
	s._cam.position = s._cam_zoom_base


func _ready() -> void:
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	print("=== 龟蛋 / 训龟大师不被场景装饰挡住 ===")
	var keep: String = AT.active
	var keep_forced: String = AT.forced
	AT.forced = ""
	get_tree().root.size = Vector2i(1560, 720)
	for th in AT.MATCH_POOL:
		AT.active = str(th)
		var s = RB.new()
		add_child(s)
		for _i in range(4):
			await get_tree().process_frame
		s._world_builder._build_map_props()          # 真对局(双路)建障碍 + 蛋罩 + 主题环的同一个函数
		var cy: float = RB.ARENA.position.y + RB.ARENA.size.y * 0.5
		var tg: Array = []
		for side in ["left", "right"]:
			var ex: float = RB.ARENA.position.x + EGG_INSET if side == "left" else RB.ARENA.end.x - EGG_INSET
			var tx: float = RB.ARENA.position.x + BattleSpawn.TRAINER_INSET if side == "left" else RB.ARENA.end.x - BattleSpawn.TRAINER_INSET
			var egg: Dictionary = s._spawn._make_unit("__egg__", side, Vector2(ex, cy), {"egg": true, "egg_side": side, "hp": 100.0, "hp_max": 100.0})
			var trn: Dictionary = s._spawn._make_unit(s.TRAINER_ID, side, Vector2(tx, cy - 150.0), {"trainer": true})
			tg.append(["龟蛋", side, egg])
			tg.append(["训龟大师", side, trn])
		for _i in range(3):
			await get_tree().process_frame
		var dec: Array = _decor(s)
		_ok("[%s] ★分母: 参与比较的装饰件数 > 0" % th, dec.size() > 0, "%d 件" % dec.size())
		## 建场那一趟(`BattleWorldBuilder._clear_base_sightlines`)真的藏了东西, 又没把一整圈清空
		var n_hid := 0
		for rn in DECOR_ROOTS:
			var r: Node = s._world.find_child(rn, true, false)
			if r != null:
				for n in r.find_children("*", "Node3D", true, false):
					if n.has_meta("base_sightline"):
						n_hid += 1
		_ok("[%s] ★藏掉挡视线的装饰 0 < n ≤ %d(不是一整圈清空)" % [th, MAX_HIDDEN], n_hid > 0 and n_hid <= MAX_HIDDEN, "%d 件" % n_hid)
		CamFit.apply(s)
		for view in [["默认", 1.0, 0.0], ["拉近推左", 2.0, -1.0], ["拉近推右", 2.0, 1.0]]:
			_push(s, float(view[1]), float(view[2]))
			await get_tree().process_frame
			var cam: Camera3D = s._cam
			for t in tg:
				var sd: String = str(t[1])
				if float(view[2]) != 0.0 and (sd == "left") != (float(view[2]) < 0.0):
					continue                  # 推到左头只看左边那两个
				var spr = (t[2] as Dictionary).get("sprite", null)
				var ok_spr: bool = spr is GeometryInstance3D and is_instance_valid(spr) and (spr as Sprite3D).texture != null
				var tr: Rect2 = screen_rect(cam, spr) if ok_spr else Rect2()
				_ok("[%s] ★分母: %s %s %s 立绘真建出来了" % [th, view[0], sd, t[0]], ok_spr and tr.get_area() > 4.0, str(tr))
				if not ok_spr or tr.get_area() <= 4.0:
					continue
				var td: float = depth(cam, (spr as Node3D).global_position)
				var cov := 0.0
				var who: Dictionary = {}
				for d in dec:
					var gi: GeometryInstance3D = d[1]
					if depth(cam, gi.global_position) >= td:
						continue              # 在目标后面, 画不到它前面
					var ir: Rect2 = screen_rect(cam, gi).intersection(tr)
					if ir.get_area() > 0.0:
						cov += ir.get_area()
						who[d[0]] = int(who.get(d[0], 0)) + 1
				var frac: float = cov / tr.get_area()
				_ok("[%s] %s: %s%s 被挡 ≤ %d%%" % [th, view[0], "左" if sd == "left" else "右", t[0], int(MAX_COVER * 100)],
					frac <= MAX_COVER, "挡了 %.0f%% · 挡它的 %s" % [frac * 100.0, str(who)])
		s.queue_free()
		await get_tree().process_frame
	AT.active = keep
	AT.forced = keep_forced
	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
