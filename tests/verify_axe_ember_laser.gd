extends Node
## verify_axe_ember_laser.gd — 096 余烬之斧【处决】天降轨道激光 (2026-09-15)
##
## 用户 2026-09-15:「9/9处决没余烬的专属特效啊，还是这个特效不明显？我需要你参考lol比较新版本的
##   无限火力里击杀敌人时一道激光从天击中敌人的那种处决」
##
## ★判据全部落在真实对象上:
##   ① 素材 png 的真像素(帧数 / 帧尺寸 / 分段: 击杀闪光是青的、穹顶只在灼烧段有、收尾只剩细线)
##   ② 从【斧头真的普攻命中】`AxeSystem.on_hit` 走进处决结算, 量它建出来的节点(不直接调演出函数)
##   ③ 光柱与穹顶的【最底一行实心像素】换算到世界坐标 = 地面(真节点位置 × 真 pixel_size × 真像素行)
##   ④ 三层同一帧; 20fps 逐帧不丢最后一帧; tween 真的把帧推到头并收掉节点
## ★每条关键断言配分母。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AF := preload("res://scripts/gamedata/axe_final_stats.gd")
const AEV := preload("res://scripts/scenes/battle/axe_ember_vfx.gd")

const BEAM_FW := 80
const BEAM_FH := 626
const DOME_FH := 200
const GROUND_FW := 80

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true          # ★绝不写玩家存档
	print("=== 096 余烬处决: 天降轨道激光 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_t_assets()
	await _t_real_path()
	if _n < 30:
		print("  [FAIL] ★分母: 断言只有 %d 条(<30) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 余烬处决激光(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
#  像素工具: 读 png 源文件(不是导入后的纹理, 无头 dummy 渲染器取不到纹理像素)
# ─────────────────────────────────────────────────────────────
func _img(path: String) -> Image:
	var im := Image.load_from_file(path)
	return im


func _opaque(im: Image, fx: int, fw: int, fh: int) -> int:
	var n := 0
	for y in range(fh):
		for x in range(fw):
			if im.get_pixel(fx * fw + x, y).a > 0.5:
				n += 1
	return n


## 该帧最底下一行实心像素的行号(0 = 顶); 没有实心像素返回 -1。
func _bottom_row(im: Image, fx: int, fw: int, fh: int) -> int:
	for y in range(fh - 1, -1, -1):
		for x in range(fw):
			if im.get_pixel(fx * fw + x, y).a > 0.5:
				return y
	return -1


## 该帧第 `y` 行实心像素的横向跨度(最右 − 最左 + 1)。
func _row_span(im: Image, fx: int, fw: int, y: int) -> int:
	var lo := -1
	var hi := -1
	for x in range(fw):
		if im.get_pixel(fx * fw + x, y).a > 0.5:
			if lo < 0:
				lo = x
			hi = x
	return 0 if lo < 0 else hi - lo + 1


func _cyan_share(im: Image, fx: int, fw: int, fh: int) -> float:
	var n := 0
	var c := 0
	for y in range(fh):
		for x in range(fw):
			var p: Color = im.get_pixel(fx * fw + x, y)
			if p.a > 0.5:
				n += 1
				if p.b > p.r:
					c += 1
	return float(c) / float(maxi(1, n))


# ══════════════════════════════════════════════════════════════
#  ① 素材: 帧数 / 尺寸 / 分段读得出来
# ══════════════════════════════════════════════════════════════
func _t_assets() -> void:
	print("--- ① 素材 ---")
	var beam: Image = _img(AEV.TEX_BEAM)
	var dome: Image = _img(AEV.TEX_DOME)
	var ground: Image = _img(AEV.TEX_GROUND)
	_ok("★分母: 三张帧表都读得到", beam != null and dome != null and ground != null)
	if beam == null or dome == null or ground == null:
		return
	_ok("光柱帧表 = %d 帧 × %d×%d(实测 %d×%d)" % [AEV.N_FRAMES, BEAM_FW, BEAM_FH, beam.get_width(), beam.get_height()],
		beam.get_width() == AEV.N_FRAMES * BEAM_FW and beam.get_height() == BEAM_FH)
	_ok("穹顶帧表 = %d 帧 × %d×%d(实测 %d×%d)" % [AEV.N_FRAMES, BEAM_FW, DOME_FH, dome.get_width(), dome.get_height()],
		dome.get_width() == AEV.N_FRAMES * BEAM_FW and dome.get_height() == DOME_FH)
	_ok("地光帧表 = %d 帧 × %d×%d(实测 %d×%d)" % [AEV.N_FRAMES, GROUND_FW, GROUND_FW, ground.get_width(), ground.get_height()],
		ground.get_width() == AEV.N_FRAMES * GROUND_FW and ground.get_height() == GROUND_FW)
	_ok("时长 = 帧数 / 帧率(%.2f 秒)" % AEV.DUR, is_equal_approx(AEV.DUR, float(AEV.N_FRAMES) / AEV.FPS))

	## 分段(见 tools/blender_ember_laser.py 头注): 帧 0 击杀闪光是【青】的, 帧 12 灼烧段是暖色
	var cy0: float = _cyan_share(beam, 0, BEAM_FW, BEAM_FH)
	var cy12: float = _cyan_share(beam, 12, BEAM_FW, BEAM_FH)
	_ok("★帧 0 击杀闪光以青色为主(青占比 %.2f > 0.6)" % cy0, cy0 > 0.6)
	_ok("★帧 12 灼烧段以暖色为主(青占比 %.2f < 0.1)" % cy12, cy12 < 0.1)
	## 光柱主体宽度: 设计 = 含外晕约 0.7 × 龟高; 卡在 [0.5, 1.0] × 龟高, 太细看不见、太粗盖住半个战场
	## 量帧 8(两次脉冲之间、没有火团)离地 3 米那一行 —— 火团和碎石都在 2 米以下, 不会混进宽度
	var span_row: int = BEAM_FH - 1 - int(round((AEV.UPRIGHT_GROUND_ABOVE_BOTTOM + 3.0) / AEV.TEXEL_M))
	var span: int = _row_span(beam, 8, BEAM_FW, span_row)
	var span_m: float = float(span) * AEV.TEXEL_M
	_ok("★帧 8 离地 3 米处光柱宽 %d 像素 = %.2f 米 ∈ [0.5, 1.0] × 龟高 %.1f 米" % [span, span_m, RB.TARGET_BODY_H],
		span_m >= 0.5 * RB.TARGET_BODY_H and span_m <= 1.0 * RB.TARGET_BODY_H)
	## 收尾只剩细线: 帧 26 实心像素不到帧 12 的 15%
	var o12: int = _opaque(beam, 12, BEAM_FW, BEAM_FH)
	var o26: int = _opaque(beam, 26, BEAM_FW, BEAM_FH)
	_ok("★收尾细线: 帧 26 实心 %d < 帧 12 的 15%%(%d)" % [o26, o12], o12 > 0 and o26 > 0 and o26 < int(o12 * 0.15))
	## 穹顶只在灼烧段出现(帧 7 ~ 22), 开头和结尾都没有
	var dome_pre: int = 0
	for j in range(0, 7):
		dome_pre += _opaque(dome, j, BEAM_FW, DOME_FH)
	var dome_post: int = 0
	for j in range(23, AEV.N_FRAMES):
		dome_post += _opaque(dome, j, BEAM_FW, DOME_FH)
	var dome_mid: int = _opaque(dome, 12, BEAM_FW, DOME_FH)
	_ok("★穹顶只在灼烧段: 帧 0~6 实心 %d / 帧 12 实心 %d / 帧 23~31 实心 %d" % [dome_pre, dome_mid, dome_post],
		dome_pre == 0 and dome_mid > 0 and dome_post == 0)
	## 地光: 脉冲砸到底那一帧(12)比两次脉冲之间(14)大
	var g12: int = _opaque(ground, 12, GROUND_FW, GROUND_FW)
	var g14: int = _opaque(ground, 14, GROUND_FW, GROUND_FW)
	var g0: int = _opaque(ground, 0, GROUND_FW, GROUND_FW)
	_ok("★地光随脉冲鼓起: 帧 12 实心 %d > 帧 14 实心 %d; 帧 0 还没有(%d)" % [g12, g14, g0],
		g12 > g14 and g14 > 0 and g0 == 0)
	## ★不贴边: 地光每一帧的实心像素离四条格边 ≥ 2 像素。
	##   第一版脉冲帧包围盒满格 (0,0)-(127,127) —— 光芒撞到方形面片的边被切成方角(2026-09-15 逐帧量出来的)。
	var touch := -1
	var g_frames := 0
	for j in range(AEV.N_FRAMES):
		var m: int = _edge_margin(ground, j, GROUND_FW, GROUND_FW)
		if m < 999:
			g_frames += 1
		if m < 2 and touch < 0:
			touch = j
	_ok("★地光不贴格边(有内容的 %d 帧全部 ≥ 2 像素; 第一个贴边的帧 %d)" % [g_frames, touch],
		g_frames >= 20 and touch == -1)
	## ★别盖到邻居: 脉冲帧地光直径 ≤ 3.0 米。台子里相邻两只龟中心距 ≈ 2.9 米(enemy_gap 120 码 × 0.024 米/码),
	##   第一版 4.8 米, 台子录像 18.9 秒一炸把左右两只龟都盖住(2026-09-15)。
	var gd: int = _row_span(ground, 12, GROUND_FW, GROUND_FW / 2)
	var gd_m: float = float(gd) * AEV.TEXEL_M
	_ok("★地光脉冲帧直径 %d 像素 = %.2f 米: ≤ 3.0 米(不盖到相邻的龟)且 ≥ 1.0 米(看得见)" % [gd, gd_m],
		gd_m <= 3.0 and gd_m >= 1.0)


## 该帧实心像素离四条格边的最小距离(像素); 空帧返回 999。
func _edge_margin(im: Image, fx: int, fw: int, fh: int) -> int:
	var m := 999
	for y in range(fh):
		for x in range(fw):
			if im.get_pixel(fx * fw + x, y).a > 0.5:
				m = mini(m, mini(mini(x, y), mini(fw - 1 - x, fh - 1 - y)))
	return m


# ══════════════════════════════════════════════════════════════
#  ② 真入口: 斧头普攻命中 → 处决 → 激光
# ══════════════════════════════════════════════════════════════
func _mk_axe() -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var ax: Dictionary = _s._spawn._make_unit("basic", "left", c)
	_s._units.append(ax)
	ax["_eq_axe"] = true
	ax["_axe_pv"] = 0                 # 只看造物 on-hit: 不让被动 3/4/5 的额外伤害先把目标打死
	ax["_axe_final"] = "ember"
	ax["id"] = "__axe_probe__"
	ax["crit"] = 0.0
	ax["atk"] = 100.0
	ax["maxHp"] = 10000.0
	ax["hp"] = 10000.0
	ax["energy"] = 0.0
	ax["maxEnergy"] = 1000.0
	return ax


func _mk_foe(off: Vector2) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", "right", c + off)
	_s._units.append(u)
	u["id"] = "__foe_probe__"
	u["maxHp"] = 10000.0
	u["hp"] = 10000.0 * 0.19          # 40 层 = 20% 处决线, 19% 在线下
	u["_ember_seeds"] = 39
	u["shield"] = 0.0
	return u


func _lasers() -> Array:
	var out: Array = []
	for c in _s._world.get_children():
		if c is Node3D and c.has_meta("ember_laser"):
			out.append(c)
	return out


func _t_real_path() -> void:
	print("--- ② 真入口: AxeSystem.on_hit → 处决 → 激光 ---")
	## ★到了处决线但被护盾吸住没死 ⇒ 不许放激光。处决伤害走 _apply_damage(tru), 护盾照吸、免死锁血照挡;
	##   第一版不管死没死都放, 台子里锁血假人每一拳劈一道(2026-09-15 录像 18.9~26 秒)。
	var fin = _s._equip_sys._axe._fin
	var sax: Dictionary = _mk_axe()
	var sfoe: Dictionary = _mk_foe(Vector2(90, -60))
	sfoe["shield"] = 100000.0
	var rs: Dictionary = fin.ember_on_hit(sax, sfoe)
	_ok("★分母: 护盾目标这一下判了处决(executed=%s)、被护盾吸住没死(alive=%s 血 %.0f 盾 %.0f)"
		% [str(rs.get("executed", false)), str(sfoe.get("alive", false)), float(sfoe.get("hp", -1.0)), float(sfoe.get("shield", -1.0))],
		bool(rs.get("executed", false)) and sfoe.get("alive", false))
	_ok("★★没处决掉就不放激光(实测 %d 道)" % _lasers().size(), _lasers().size() == 0)
	sfoe["alive"] = false
	sax["alive"] = false
	var ax: Dictionary = _mk_axe()
	var foe: Dictionary = _mk_foe(Vector2(90, 40))
	var before: int = _lasers().size()
	_ok("★分母: 命中前场上没有激光(实测 %d)" % before, before == 0)
	_s._equip_sys._axe.on_hit(ax, foe, true)
	_ok("★分母: 这一下真的处决了(目标 alive=%s 血 %.0f)" % [str(foe.get("alive", true)), float(foe.get("hp", -1.0))],
		not foe.get("alive", true))
	var ls: Array = _lasers()
	_ok("★★处决那一刻(同一个调用里, 不等帧)建出 1 道激光(实测 %d)" % ls.size(), ls.size() == 1)
	if ls.size() != 1:
		return
	var root: Node3D = ls[0]
	var want: Vector3 = _s._world_pos(foe.get("pos", Vector2.ZERO), 0.0)
	_ok("★激光落在被处决者脚下(差 %.3f 米)" % Vector2(root.position.x - want.x, root.position.z - want.z).length(),
		Vector2(root.position.x - want.x, root.position.z - want.z).length() < 0.01 and absf(root.position.y) < 0.001)
	var beam: Sprite3D = root.get_node_or_null("Beam") as Sprite3D
	var dome: Sprite3D = root.get_node_or_null("Dome") as Sprite3D
	var ground: Sprite3D = root.get_node_or_null("Ground") as Sprite3D
	_ok("★分母: 三层都在(光柱/穹顶/地光)", beam != null and dome != null and ground != null)
	if beam == null or dome == null or ground == null:
		return
	for s in [beam, dome, ground]:
		var sp: Sprite3D = s
		_ok("%s: NEAREST 过滤 / %d 帧 / 像素尺寸 %.4f" % [sp.name, AEV.N_FRAMES, sp.pixel_size],
			sp.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and sp.hframes == AEV.N_FRAMES
			and is_equal_approx(sp.pixel_size, AEV.TEXEL_M) and sp.texture != null)
	_ok("★光柱永远直立(FIXED_Y, 全轴公告板会随相机俯仰倒下)", beam.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y)
	## ★不只比常量(改常量两边一起变 = 恒真): 还要真的半透明, 不透明的穹顶会把被处决者整个盖成红块
	_ok("★穹顶直立 + 半透明(实测 a=%.2f · 设计 %.2f · 须在 0.2~0.6)" % [dome.modulate.a, AEV.DOME_ALPHA],
		dome.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y and is_equal_approx(dome.modulate.a, AEV.DOME_ALPHA)
		and dome.modulate.a >= 0.2 and dome.modulate.a <= 0.6)
	_ok("★地光贴地(axis=Y · 不公告板 · 离地 %.2f 米)" % ground.position.y,
		ground.axis == Vector3.AXIS_Y and ground.billboard == BaseMaterial3D.BILLBOARD_DISABLED
		and ground.position.y > 0.0 and ground.position.y < 0.1)
	## ★地光测深度: 站在被处决者前面的龟要挡住地上的光(第一版不测深度, 台子录像里整圈地光画在邻居身上)
	_ok("★地光开深度测试(no_depth_test=%s), 光柱仍画在最上层(no_depth_test=%s)" % [str(ground.no_depth_test), str(beam.no_depth_test)],
		not ground.no_depth_test and beam.no_depth_test)
	## ★场上地光的真直径 = 素材脉冲帧跨度 × 【节点】像素尺寸(量真节点: 有人把地光节点放大也会红)
	var gim: Image = _img(AEV.TEX_GROUND)
	if gim != null:
		var gpx: int = _row_span(gim, 12, GROUND_FW, GROUND_FW / 2)
		var gm: float = float(gpx) * ground.pixel_size
		_ok("★★场上地光直径 %.2f 米(节点像素尺寸 %.4f × %d 像素) ≤ 3.0 米, 不盖到相邻的龟" % [gm, ground.pixel_size, gpx],
			gpx > 0 and gm <= 3.0)
	_ok("光柱画在穹顶上面(render_priority %d > %d)" % [beam.render_priority, dome.render_priority],
		beam.render_priority > dome.render_priority)

	## ★★地面线: 真节点的中心高度 + 真 pixel_size + 素材里最底一行实心像素 ⇒ 世界高度应 = 地面 0
	var bim: Image = _img(AEV.TEX_BEAM)
	var dim: Image = _img(AEV.TEX_DOME)
	if bim != null and dim != null:
		var fh: float = float(BEAM_FH)
		var dfh: float = float(DOME_FH)
		var rb: int = _bottom_row(bim, 8, BEAM_FW, BEAM_FH)
		var yb: float = root.position.y + beam.position.y + (fh * 0.5 - float(rb) - 1.0) * beam.pixel_size
		_ok("★★光柱底边落在地面(帧 8 最底实心行 %d → 世界高 %.3f 米, 容差 2 像素)" % [rb, yb],
			rb > 0 and absf(yb) <= 2.0 * beam.pixel_size)
		var rd: int = _bottom_row(dim, 12, BEAM_FW, DOME_FH)
		var yd: float = root.position.y + dome.position.y + (dfh * 0.5 - float(rd) - 1.0) * dome.pixel_size
		_ok("★★穹顶底边落在地面(帧 12 最底实心行 %d → 世界高 %.3f 米)" % [rd, yd],
			rd > 0 and absf(yd) <= 2.0 * dome.pixel_size)
		## ★「从天而降」量的是【战斗镜头里光柱顶端出不出屏幕上沿】, 不是我拍的"几倍龟高"——
		##   帧顶是一刀平切, 顶端落在屏幕里就读成一根悬空的柱子。
		##   (第一版写「≥ 4 × 龟高」, 实测 7.9 米 vs 8.0 红了: 那个 4 是我拍的数, 与读不读得出来无关。)
		var top_m: float = root.position.y + beam.position.y + fh * 0.5 * beam.pixel_size
		## ★量产品自己的战斗镜头 `_s._cam`: 测试场景里视口取不到当前相机(第一版 get_viewport().get_camera_3d() 拿到 null)
		var cam: Camera3D = _s._cam if is_instance_valid(_s._cam) else get_viewport().get_camera_3d()
		_ok("★分母: 战斗镜头在场", cam != null)
		if cam != null:
			var top_w: Vector3 = root.global_position + Vector3(0.0, top_m, 0.0)
			var foot_w: Vector3 = root.global_position
			var sp_top: Vector2 = cam.unproject_position(top_w)
			var sp_foot: Vector2 = cam.unproject_position(foot_w)
			var vh: float = get_viewport().get_visible_rect().size.y
			_ok("★★光柱顶端(离地 %.1f 米)投影在屏幕上沿之外(y=%.0f / 屏高 %.0f), 脚在屏内(y=%.0f)"
				% [top_m, sp_top.y, vh, sp_foot.y],
				not cam.is_position_behind(top_w) and sp_top.y < 0.0 and sp_foot.y > 0.0 and sp_foot.y < vh)

	## ── 三层同一帧 / 20fps 逐帧 / 不丢最后一帧 ──
	_ok("frame_at: 0 秒 → 0 · 0.35 秒 → 7 · 1.599 秒 → 31 · 9 秒 → 31(停在末帧)",
		AEV.frame_at(0.0) == 0 and AEV.frame_at(0.35) == 7 and AEV.frame_at(1.599) == 31 and AEV.frame_at(9.0) == 31)
	var seen := {}
	var desync := 0
	var samples := 0
	var t := 0.0
	while t < AEV.DUR:
		AEV.apply_frame(root, t)
		samples += 1
		seen[beam.frame] = true
		if beam.frame != dome.frame or dome.frame != ground.frame or beam.frame != AEV.frame_at(t):
			desync += 1
		t += 1.0 / 80.0
	_ok("★★三层同一帧(采样 %d 次, 错帧 %d 次)" % [samples, desync], samples >= 100 and desync == 0)
	_ok("★32 帧一帧不丢(实测走到 %d 个不同帧, 含末帧 31)" % seen.size(), seen.size() == AEV.N_FRAMES and seen.has(31))

	## ── tween 真的把帧推到头并收掉节点(墙钟上限 6 秒) ──
	var rid: int = root.get_instance_id()
	var t0: int = Time.get_ticks_msec()
	var max_frame := 0
	while is_instance_valid(instance_from_id(rid)) and Time.get_ticks_msec() - t0 < 6000:
		var b = instance_from_id(rid)
		if is_instance_valid(b):
			var bb: Sprite3D = (b as Node).get_node_or_null("Beam") as Sprite3D
			if bb != null:
				max_frame = maxi(max_frame, bb.frame)
		await get_tree().process_frame
	var el: float = float(Time.get_ticks_msec() - t0) / 1000.0
	_ok("★★播完收掉节点(用了 %.2f 秒墙钟, 演出 %.1f 秒)" % [el, AEV.DUR],
		not is_instance_valid(instance_from_id(rid)) and el >= AEV.DUR * 0.6)
	_ok("★分母: 收掉之前 tween 真的把帧推到了尾段(最大帧 %d ≥ 25)" % max_frame, max_frame >= 25)
	_ok("收掉后场上不留激光(实测 %d)" % _lasers().size(), _lasers().size() == 0)
