extends Node
## verify_eq_body_sprites.gd — 「白球家族」本体立绘门禁
##
## ══════════════════════════════════════════════════════════════════════════
##  守的是: 装备召唤出来的**东西本身有没有形状**
## ══════════════════════════════════════════════════════════════════════════
## 2026-08-07 干净台(VFXLAB)一拍才发现, 有一批装备的"本体"根本没画:
##   · 077 小手枪 → `_spawn_summon` 的**兜底队色发光球**(花名册直接打 `spr=✗`)
##   · 080 直升机 → 发光球缩成 1.4×0.9 + 一块横穿机身的几何旋翼
##     ⇒ 实拍读起来就是**一个灰长方形**(用户原话:「长方形也能算子弹」)
## 而**已有的 verify_eq_gun_batch 全绿** —— 它守的是"航线长 800 码对不对"
## 「覆盖敌人数是不是最大」「每命中 +4 龟能对不对」。**这些全对, 而它看起来什么都不是。**
## ⇒ 数值门禁**结构上守不住**「它有没有形状」, 得单开一份。
##
## ── 这份门禁的四条判据 ──
## ① 素材在位且真是**横排帧表**(宽是高的整数倍且 ≥2 帧) —— 单帧立绘会被当成"动画"却永远不动
## ② **首尾闭合**: 末帧与首帧的差异不得大于相邻帧差的 2 倍。
##    由来: PixelLab 出的 idle 末帧与首帧差 323/1600(手枪) 与 774/4096(直升机),
##    直接首尾相接**每轮跳一下**。两件都靠**乒乓排帧**(0..n 再 n-1..1)解决,
##    所以这条断言等价于「乒乓有没有被人改回单向」。
## ③ **朝向**: 两张表都统一成【朝右】。左队打向右, 表若朝左就是**背对敌人开枪**
##    (077 第一版真的这样上了场, 只有实拍抓得到)。
##    ★★这条的尺子换过一次, 教训值得写下来: 第一版判据是「重心必须偏右半」,
##      结果**手枪红了**(重心 18.8/40) —— 而实拍里它明明朝右。
##      因为**重心量的是重量分布, 不是朝向**: 手枪重在【握把】(在后)、枪管细;
##      直升机重在【座舱】(在前)、尾梁细。两件的重心方向天然相反。
##      ⇒ 判据改成「**有没有被镜像**」: 逐件写明它现在偏哪边(镜像会让这个符号翻转)。
##      这条抓得住"谁把表镜像回去了", 抓不住"一张全新的、朝向本来就错的表" ——
##      后者只有实拍能抓, 这里如实写明, 不假装它守得住。
## ④ 有立绘时**不许再叠几何占位**: 直升机的那块旋翼 mesh 必须不在树上。
##
## ⚠ 期望值一律写字面量, 不引用 gun_eq_vfx 里的常量 —— 引用就是拿代码跟它自己比。

const PISTOL := "res://assets/sprites/vfx/eq-pistol-idle.png"
const HELI := "res://assets/sprites/vfx/eq-heli-idle.png"
const CORAL := "res://assets/sprites/vfx/eq-coraltower-idle.png"
const DRONE := "res://assets/sprites/vfx/eq-orbdrone-idle.png"

var _n := 0
var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("=== 白球家族·本体立绘 ===")

	_check_strip("077 小手枪", PISTOL, 40, 16, -1)
	_check_strip("080 直升机", HELI, 64, 16, 1)
	_check_strip("079 珊瑚急救塔", CORAL, 64, 16, 0)
	# 086 浮游炮绕着龟转, **没有朝向**这回事; 这条纯粹守"表没被人镜像/换掉"。
	_check_strip("086 六分仪浮游炮", DRONE, 40, 16, -1)

	# ── 089 蚀月符纸: 单帧立绘(不是帧表), 判据是**它不是一张空白板**。
	#    由来: v0.19.37 之前它是 `talisman_tex_image()` 拼的几个矩形, 干净台一拍是
	#    **10.8×9.3 屏幕像素的纯白空白四边形** —— 无符文/无月/无边框。
	#    ⇒ 这条量的是"纸上有没有字": 不透明像素里, 与最亮色**明显不同**的那部分要够多。
	_check_talisman()

	# ── ④ 有立绘时不许再叠几何占位(直升机旋翼 mesh)
	var s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for i in range(20):
		await get_tree().process_frame
	var vfx = s._equip_sys._gun_sys.vfx if s._equip_sys != null else null
	_ok("★分母: 拿到了 080 的演出层", vfx != null)
	if vfx == null:
		_done(); return
	var owner_u: Dictionary = {"side": "left", "pos": Vector2(400, 400), "alive": true}
	var h: Dictionary = {"owner": owner_u, "pos": Vector2(400, 400), "rotor": 0.0, "energy": 0.0}
	vfx.heli_spawn(h)
	var root = h.get("node", null)
	_ok("★分母: 直升机节点建出来了", root is Node3D and is_instance_valid(root))
	if not (root is Node3D):
		_done(); return
	var n_mesh := 0
	var body: Sprite3D = null
	for c in (root as Node3D).get_children():
		if c is MeshInstance3D:
			n_mesh += 1
		elif c is Sprite3D and int((c as Sprite3D).hframes) > 1:
			body = c
	_ok("④ 机身走的是立绘(帧表), 不是发光球", body != null,
		"hframes=%d" % (int(body.hframes) if body != null else 0))
	_ok("④ 几何旋翼没有再叠上去", n_mesh == 0, "树上 MeshInstance3D = %d" % n_mesh)

	# 朝向: 左队不翻转(表本身朝右), 右队翻转
	_ok("③ 左队的直升机不翻转(表朝右, 左队正好打向右)", body != null and not body.flip_h)
	var h2: Dictionary = {"owner": {"side": "right", "pos": Vector2(400, 400), "alive": true},
		"pos": Vector2(400, 400), "rotor": 0.0, "energy": 0.0}
	vfx.heli_spawn(h2)
	var body2: Sprite3D = null
	for c in (h2["node"] as Node3D).get_children():
		if c is Sprite3D and int((c as Sprite3D).hframes) > 1:
			body2 = c
	_ok("③ 右队的直升机水平翻转(否则背对敌人)", body2 != null and body2.flip_h)

	_done()


## ①②③ 三条对一张帧表
## 089 符纸: 判"纸上真的有字", 不是判尺寸。
func _check_talisman() -> void:
	var path := "res://assets/sprites/vfx/eq-talisman.png"
	_ok("089 符纸 ★分母: 素材在位", ResourceLoader.exists(path), path)
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if tex == null:
		_ok("089 符纸 ★分母: 能载入", false)
		return
	var img: Image = tex.get_image()
	var lum: Array[float] = []
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.3:
				lum.append(c.r * 0.30 + c.g * 0.59 + c.b * 0.11)
	_ok("089 符纸 ★分母: 有不透明像素", lum.size() > 200, "%d 个" % lum.size())
	if lum.size() <= 200:
		return
	lum.sort()
	var hi: float = lum[int(float(lum.size()) * 0.9)]     # 纸的底色(占大多数)
	var dark := 0
	for v in lum:
		if v < hi - 0.18:                                  # 比底色暗一截 = 笔画
			dark += 1
	var frac: float = float(dark) / float(lum.size())
	# ★阈值 8%: 一张纯白板是 0%, 现在这张实测远高于它。写字面量不引用被测数据。
	_ok("089 符纸 ⑤ 纸上真的有笔画(暗于底色的像素 ≥ 8%)", frac >= 0.08,
		"底色亮度 %.2f / 笔画占比 %.1f%%" % [hi, frac * 100.0])


## `bias`: 1 = 重心该偏右 · -1 = 该偏左 · **0 = 左右对称**(塔这种没有朝向的东西)
func _check_strip(tag: String, path: String, frame_h: int, want_frames: int, bias: int) -> void:
	_ok("%s ★分母: 素材在位" % tag, ResourceLoader.exists(path), path)
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if tex == null:
		_ok("%s ★分母: 素材能载入" % tag, false)
		return
	var w: int = tex.get_width()
	var hgt: int = tex.get_height()
	_ok("%s ① 帧高 = %d" % [tag, frame_h], hgt == frame_h, "实际 %d" % hgt)
	var nf: int = w / maxi(1, hgt)
	_ok("%s ① 是横排帧表(宽是高的整数倍)" % tag, w % maxi(1, hgt) == 0, "%dx%d" % [w, hgt])
	_ok("%s ① 共 %d 帧" % [tag, want_frames], nf == want_frames, "实际 %d 帧" % nf)
	if nf < 2:
		return

	var img: Image = tex.get_image()
	# ② 首尾闭合(乒乓排帧的直接后果)
	var d_wrap: int = _frame_diff(img, hgt, nf - 1, 0)
	var adj: Array[int] = []
	for i in range(nf - 1):
		adj.append(_frame_diff(img, hgt, i, i + 1))
	# ★★这条判据换过两版, 两版都是**反向验证**逼出来的, 值得完整写下来:
	#   第①版「末→首 ≤ 最大相邻帧差 ×2」—— 变异"把乒乓改回单向"**没红**:
	#     单向排帧在接缝处必然留一个大跳变, 那个跳变自己把门槛抬高了 ⇒ 替 wrap 打掩护。
	#     **分母里只要含被测的那个缺陷, 门禁就自动失效。**
	#   第②版「≤ 中位数 ×2」—— 变异红了, 但**真表也红了**:
	#     手枪 wrap=841 而中位=329。查下来 wrap **正好等于 anim 帧 0→1 那一步** ——
	#     它本来就是这张表最大的一步(PixelLab 第一帧到第二帧动得最多)。
	#     也就是说这张表**是闭合的**, 是我的判据假设了"运动速率均匀", 而它不均匀。
	#   ⇒ 第③版改成断言**乒乓排帧的精确性质**, 不再猜阈值:
	#     乒乓 = [0,1,…,n, n-1,…,1] ⇒ 相邻帧差序列必然是 [g0,g1,…,g_{n-1}, g_{n-1},…,g1],
	#     即**去掉第一项后是回文**; 且 **末→首 恰好 == g0**(末帧是 anim1、首帧是 anim0)。
	#     两条都是乒乓的充分特征, 单向排帧一条都不满足, 而且**不含任何拍脑袋的容差**。
	#   ⚠ 比较带容差, 不能用 `==`: 门禁读的是 **Godot 导入后的纹理**(`tex.get_image()`),
	#     它可能是有损压缩的 ⇒ 同一对帧在 PNG 上差 509、在导入纹理上差 785, 且回文对不严格相等。
	#     (实测: 直升机那张严格回文成立、手枪那张不成立 —— 同一份代码, 差别只在导入设置。)
	#     容差取 `0.20×较大者 + 40`: 加性项 40 是为了小差值(11 vs 43)不被相对误差判死。
	var tail: Array[int] = adj.slice(1)
	var pal := true
	for i in range(tail.size() / 2):
		if not _close(tail[i], tail[tail.size() - 1 - i]):
			pal = false
	_ok("%s ② 乒乓排帧还在(相邻帧差去掉首项后成回文)" % tag, pal and tail.size() >= 2,
		"相邻帧差 %s" % str(adj))
	_ok("%s ② 首尾闭合(末→首 ≈ 第一步)" % tag, _close(d_wrap, adj[0]),
		"末→首 %d px / 第一步 %d px" % [d_wrap, adj[0]])
	var d_mx: int = 0
	for v in adj:
		d_mx = maxi(d_mx, v)
	_ok("%s ★分母: 帧之间真的在动(不是同一张复制 %d 遍)" % [tag, nf],
		d_mx > 0, "最大相邻帧差 %d px" % d_mx)

	# ③ 朝向: 不透明像素的 x 重心必须偏右
	var sum_x := 0.0
	var cnt := 0
	for y in range(hgt):
		for x in range(hgt):
			if img.get_pixel(x, y).a > 0.16:
				sum_x += float(x)
				cnt += 1
	_ok("%s ★分母: 首帧有不透明像素" % tag, cnt > 0, "%d 个" % cnt)
	if cnt > 0:
		var cx: float = sum_x / float(cnt)
		var mid: float = float(hgt) * 0.5
		if bias == 0:
			# ★对称件(塔): 判"朝向"没有意义, 改判**它确实是对称的** ——
			#   重心偏出中线 8% 帧宽就说明它有朝向了, 那就该改用 ±1 分支。
			_ok("%s ③ 左右对称(重心在中线 ±8% 内)" % tag, absf(cx - mid) <= float(hgt) * 0.08,
				"x 重心 %.1f / 中线 %.1f / 帧宽 %d" % [cx, mid, hgt])
		else:
			_ok("%s ③ 没有被镜像(重心应偏%s)" % [tag, "右" if bias > 0 else "左"],
				(cx > mid) == (bias > 0), "x 重心 %.1f / 帧宽 %d" % [cx, hgt])


## 两个帧差是否"同一个量" —— 容差见 ② 的注释(有损纹理导入)
func _close(a: int, b: int) -> bool:
	return absf(float(a) - float(b)) <= 0.20 * float(maxi(a, b)) + 40.0


## 两帧之间"差异明显"的像素个数
func _frame_diff(img: Image, fh: int, a: int, b: int) -> int:
	var n := 0
	for y in range(fh):
		for x in range(fh):
			var ca: Color = img.get_pixel(a * fh + x, y)
			var cb: Color = img.get_pixel(b * fh + x, y)
			var d: float = absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
			if d > 0.14:
				n += 1
	return n


func _ok(name: String, cond: bool, extra: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  — " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  — " + extra) if extra != "" else ""])


func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS (%d/%d)" % [_n, _n])
		get_tree().quit(0)
	else:
		print("FAIL x%d (共 %d 条)" % [_fail, _n])
		get_tree().quit(1)
