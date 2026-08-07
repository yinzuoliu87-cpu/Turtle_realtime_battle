class_name GoldenShotVfx
extends RefCounted
## golden_shot_vfx.gd — 枪羁绊【金弹】的可辨演出层　(2026-08-07)
##
## ══════════════════════════════════════════════════════════════════════
##  ★为什么整件事只在【一处】做
## ══════════════════════════════════════════════════════════════════════
## 金弹 = 每把枪射满 4/3/2 发额外射一发 + 60/80/100% 真实伤害。
## 它的**唯一出口**是 `RealtimeBattle3DScene._queue_shots(n, gap, fn, src, gun_id)` ——
## 五把老枪(048/050/051/052/057)与四把新枪(077~080)全从那里出去,
## 金弹那一发复用同一个 `fn`, 期间 `src["_golden_pct"] > 0`。
## ⇒ **演出也只在那一处挂**。往九件装备里各写一份 = 抄一次永远落后一次
##   (memory [[fb-hand-rolled-copies-drift]]: 手抄的副本必然落后)。
##
## ══════════════════════════════════════════════════════════════════════
##  ★怎么知道"这一发打中了谁" —— 不加伤害管线钩子, 用快照差分
## ══════════════════════════════════════════════════════════════════════
## `_queue_shots` 只知道**射手**, 不知道目标(目标是 `fn` 内部各自选的)。
## 要在**被打中的那个人身上**画金弹命中, 通常的做法是往 `battle_damage` 里加钩子 ——
## 那是本项目最热的共用管线, 而且同时有别的 agent 在动它。
##
## ⇒ 改用**差分**: 调 `fn` 之前 `arm()` 把全场每个单位的 `hp + shield` 记一份,
##   `fn` 返回后 `resolve()` 比一遍, **掉了的就是这一发打中的**。
##   · 不碰任何共用管线, 全部逻辑在本文件 + `_queue_shots` 那 3 行里;
##   · 对 AOE(078 左管霰弹锥 / 080 炸弹)天然正确 —— 锥内每个人都会被标上;
##   · 治疗(079 炮台奶友军)天然不会被误标 —— 血是涨的。
##   · 单位表最多几十个, 一发金弹约 1 秒一次 ⇒ 开销可忽略。
##
## ══════════════════════════════════════════════════════════════════════
##  ★可辨的判据是【剑silhouette】, 不是颜色
## ══════════════════════════════════════════════════════════════════════
## 场上已有的射击演出全是**直条**(弹迹 `_band`)、**圆环**(`_hit_spark` / `_skill_ring`)、
## **圆形光斑**(`_make_glow_texture` / `_make_fire_glow_tex`)。
## 只把子弹调成金色 ⇒ 遮住颜色就分不出来了(用户 2026-08-07:「撞形状比撞色更要命」)。
## ⇒ 金弹的三样东西**一个圆、一条直条都不用**, 全部是**菱形族**:
##   ① 枪口: 双人字箭簇「»」(两道 V, 尖指射向)
##   ② 弹迹: 一串**菱形弹珠**(点状链, 不是连续直条)
##   ③ 命中: **菱形外框**炸开 + 中心实心菱
## 三样凑起来是"一发不一样的子弹从枪口出去、串成珠、在目标身上炸成菱"。
##
## ★亮度/尺寸 ≡ 该档金弹的真伤比例(60/80/100%) —— **一个数两处用, 不另设表**。
##   与 `GunEqVfx.gold_glow` 是同一条恒等式, 门禁焊死两者逐档相等。
##
## ══════════════════════════════════════════════════════════════════════
##  ★零素材 / 不用 tween
## ══════════════════════════════════════════════════════════════════════
## · 贴图全部本文件逐像素**现算**并静态缓存(程序化生成不产出可复用的图,
##   与用户铁律「新内容一律新素材」不冲突 —— 它没有借用任何一张现成图)。
## · 生命周期由 `tick(delta)` 自己推进, **不用 `create_tween()`**(CLAUDE.md §3.5:
##   无头 CI 下 tween 推进不稳, 埋在 tween 链末尾的东西永远等不到)。
##   ⇒ 门禁可以同步喂 delta 把整段演出跑完。

## 金弹的两个色: 外金 / 内白热
const GOLD := Color(1.0, 0.78, 0.16)
const CORE := Color(1.0, 0.98, 0.86)

## 枪口箭簇的尺寸(码)与存活(秒)
const MUZZLE_PX := 62.0
const MUZZLE_SEC := 0.26
## 弹迹菱珠: 只画贴近目标的最后这么长一段(码) —— 见文件头, 射手不一定就是 `src` 的位置
## (080 直升机的 `src` 是携带者, 真正开火的是空中的机体), 只保证**入射方向**与命中点对。
const TRAIL_LEN := 150.0
## 菱珠个数与单颗尺寸(码)
const TRAIL_BEADS := 5
const BEAD_PX := 26.0
const TRAIL_SEC := 0.22
## 命中菱框: 从这么大扩到这么大(码)
const HIT_R0 := 26.0
const HIT_R1 := 104.0
const HIT_SEC := 0.34
## 演出离地高度(米) —— 与胸口同高, 不贴地(贴地会被龟身压住, 那正是 093 的病)
const BODY_Y := 0.95

## 节点身份标记(程序生成贴图 `resource_path` 是空串, 按路径数会全数成 0)
const META_KEY := "golden_shot_vfx"
## 最后一道闸: 同时在场的本层节点上限
const OWNED_CAP := 192

## 静态贴图缓存(整个进程建一次)
static var _tex_bead: ImageTexture = null
static var _tex_frame: ImageTexture = null
static var _tex_chevron: ImageTexture = null

var battle
## 正在播的特效 [{node, t, life, kind, …}]
var _fx: Array = []
## `arm()` 拍下的快照: [[单位字典, hp+shield], …]
## ★单位字典只当**值**存, 绝不当 Dictionary 的键(CLAUDE.md §3.2: 递归哈希会卡死)
var _snap: Array = []
var _armed_src = null
## 本发的**真实出膛点**(场地码)。null = 没给 ⇒ 退回 src["pos"]。
var _armed_from = null
## 累计画过几发金弹(门禁分母)
var _shots_marked := 0


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and battle._world != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等演出
# ══════════════════════════════════════════════════════════════════

## 金弹辉光强度 ≡ 该档金弹的真伤比例(1/2/3 档 = 0.60/0.80/1.00)。
## ★与 `GunEqVfx.gold_glow` 是**同一条恒等式** —— 门禁验两者逐档相等。
static func glow(pct: float) -> float:
	return clampf(pct, 0.0, 1.0)


## 第 i 颗菱珠在 a→b 上的位置。★只铺**贴近 b** 的最后 TRAIL_LEN 码:
## 距离短于 TRAIL_LEN 时退化成"整条都铺", 不会越过 a。
static func bead_pos(a: Vector2, b: Vector2, i: int, n: int, seg_len: float = TRAIL_LEN) -> Vector2:
	var d: Vector2 = b - a
	var l: float = d.length()
	if l < 0.001 or n <= 1:
		return b
	var back: float = minf(seg_len, l)
	var start: Vector2 = b - d / l * back
	return start.lerp(b, float(i) / float(n - 1))


## 命中菱框在 q∈[0,1] 时的半径(码)。线性外扩 —— 与 088 潮涌环同族(匀速),
## 与 090 猛砸的 Sedov t^0.4 明确不同, 免得两件在同一帧里被读混。
static func hit_radius(q: float, pct: float) -> float:
	var g: float = glow(pct)
	return lerpf(HIT_R0, HIT_R1 * (0.7 + 0.3 * g), clampf(q, 0.0, 1.0))


# ══════════════════════════════════════════════════════════════════
#  §程序化贴图 —— 菱形族, 一张圆的都没有
# ══════════════════════════════════════════════════════════════════

## |x/a| + |y/b| ≤ 1 的实心菱(带白热芯)。★这条判据本身就是"菱形"的定义,
## 门禁拿它反过来验: 四个角必须是空的、四条边中点必须是实的。
static func bead_tex() -> ImageTexture:
	if _tex_bead != null:
		return _tex_bead
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var dx: float = absf(float(x) - c) / c
			var dy: float = absf(float(y) - c) / c
			var m: float = dx + dy                      # 菱形度量: 1.0 = 边界
			if m > 1.0:
				continue
			var a: float = clampf((1.0 - m) * 3.2, 0.0, 1.0)
			var core: float = clampf((0.45 - m) * 3.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(
				lerpf(GOLD.r, CORE.r, core), lerpf(GOLD.g, CORE.g, core),
				lerpf(GOLD.b, CORE.b, core), a))
	_tex_bead = ImageTexture.create_from_image(img)
	return _tex_bead


## 菱形【外框】(空心)。命中时炸开的就是它 —— 空心菱 vs 场上一切圆环, 剪影一眼分得开。
static func frame_tex() -> ImageTexture:
	if _tex_frame != null:
		return _tex_frame
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var m: float = absf(float(x) - c) / c + absf(float(y) - c) / c
			var band: float = 1.0 - absf(m - 0.86) / 0.14   # 只留 m≈0.86 附近一圈
			if band <= 0.0:
				continue
			img.set_pixel(x, y, Color(GOLD.r, GOLD.g, GOLD.b, clampf(band, 0.0, 1.0)))
	_tex_frame = ImageTexture.create_from_image(img)
	return _tex_frame


## 双人字箭簇「»」: 两道 V 形折线, 尖指 +X。枪口用。
static func chevron_tex() -> ImageTexture:
	if _tex_chevron != null:
		return _tex_chevron
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var ny: float = (float(y) - c) / c            # −1..1
			var nx: float = (float(x) - c) / c
			if absf(ny) > 0.92:
				continue
			var best := 2.0
			for tipx in [0.18, 0.78]:                     # 两道人字的尖各在这里
				var want: float = float(tipx) - absf(ny) * 0.72
				best = minf(best, absf(nx - want))
			if best > 0.13:
				continue
			var a: float = clampf((0.13 - best) / 0.13, 0.0, 1.0)
			img.set_pixel(x, y, Color(CORE.r, CORE.g, CORE.b, a * 0.95))
	_tex_chevron = ImageTexture.create_from_image(img)
	return _tex_chevron


# ══════════════════════════════════════════════════════════════════
#  §建节点
# ══════════════════════════════════════════════════════════════════

func _adopt(n: Node3D, life: float, kind: String, extra: Dictionary = {}) -> Node3D:
	n.set_meta(META_KEY, kind)
	battle._world.add_child(n)
	if _fx.size() >= OWNED_CAP:
		var old: Dictionary = _fx.pop_front()
		var x = old.get("node", null)
		if x is Node3D and is_instance_valid(x):
			x.queue_free()
	var d: Dictionary = {"node": n, "t": 0.0, "life": maxf(0.01, life), "kind": kind}
	for k in extra:
		d[k] = extra[k]
	_fx.append(d)
	return n


## 面向相机的公告板。★`no_depth_test` 保证不被龟身/地板吞掉(093 的病就是被压住)。
func _board(tex: Texture2D, pos2: Vector2, y_m: float, size_px: float, col: Color,
		roll: float = 0.0) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 20
	s.modulate = col
	s.position = battle._world_pos(pos2, y_m)
	s.pixel_size = (size_px * float(battle.WS)) / maxf(1.0, float(tex.get_width()))
	if roll != 0.0:
		s.rotation.z = roll
	return s


## 一块**沿 a2→b2 摊平**的带贴图四边形(贴图 +X 指向 b2)。
## ★为什么不用 `Sprite3D` + `rotation.z`: `BILLBOARD_ENABLED` 会**吃掉 roll**
##   (本仓库 001 飞斩踩过的坑, 见 `_spawn_eq_bolt` 的注释「billboard会吃掉roll」) ——
##   箭簇就会永远指着同一个方向而且不报错。用世界坐标顶点直接建, 朝向由几何决定。
func _quad_along(a2: Vector2, b2: Vector2, half_w: float, y_m: float,
		tex: Texture2D, col: Color) -> MeshInstance3D:
	var dir: Vector2 = b2 - a2
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	var p: Vector2 = Vector2(-dir.y, dir.x).normalized() * half_w
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v: Array = [battle._world_pos(a2 + p, y_m), battle._world_pos(b2 + p, y_m),
					battle._world_pos(b2 - p, y_m), battle._world_pos(a2 - p, y_m)]
	var uv: Array = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[idx])
		st.add_vertex(v[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 20
	mat.albedo_texture = tex
	mat.albedo_color = col
	mi.material_override = mat
	return mi


## 给"任何一种"节点写 alpha —— Sprite3D 走 modulate, 网格走 material_override。
static func _set_a(n, a: float) -> void:
	if n is Sprite3D:
		(n as Sprite3D).modulate.a = clampf(a, 0.0, 1.0)
	elif n is MeshInstance3D:
		var m = (n as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			var c: Color = (m as StandardMaterial3D).albedo_color
			(m as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))


# ══════════════════════════════════════════════════════════════════
#  §对外三个入口
# ══════════════════════════════════════════════════════════════════

## ① 枪口: 射手身上炸一簇金色箭簇「»」, 尖指射向。
func muzzle(src, aim: Vector2, pct: float, from_override = null) -> Node3D:
	if not _has_world() or not (src is Dictionary):
		return null
	var g: float = glow(pct)
	# ★枪口闪也画在**真正的出膛点**上, 不是携带者身上(同上)
	var p: Vector2 = from_override if from_override is Vector2 else Vector2((src as Dictionary)["pos"])
	var dir: Vector2 = (aim if aim.length() > 0.01 else Vector2.RIGHT).normalized()
	var len_px: float = MUZZLE_PX * (0.8 + 0.35 * g)
	var mi := _quad_along(p + dir * 8.0, p + dir * (8.0 + len_px), len_px * 0.5, BODY_Y,
		chevron_tex(), Color(CORE.r, CORE.g, CORE.b, 0.95))
	return _adopt(mi, MUZZLE_SEC, "muzzle", {"a0": 0.95})


## ② 弹迹: 一串菱形弹珠, 铺在**贴近目标**的最后一段上。返回铺了几颗(门禁分母)。
func trail(from2: Vector2, to2: Vector2, pct: float) -> int:
	if not _has_world():
		return 0
	var g: float = glow(pct)
	for i in range(TRAIL_BEADS):
		var p: Vector2 = bead_pos(from2, to2, i, TRAIL_BEADS)
		var f: float = float(i) / float(maxi(1, TRAIL_BEADS - 1))
		var s := _board(bead_tex(), p, BODY_Y,
			BEAD_PX * (0.55 + 0.65 * f) * (0.8 + 0.3 * g),
			Color(1.0, 1.0, 1.0, 0.55 + 0.45 * f))
		_adopt(s, TRAIL_SEC * (0.6 + 0.5 * f), "bead", {"a0": 0.55 + 0.45 * f, "ps0": s.pixel_size})
	return TRAIL_BEADS


## ③ 命中: 目标身上一个菱形外框炸开 + 中心一颗实心菱。
func hit(tgt, pct: float) -> Node3D:
	if not _has_world() or not (tgt is Dictionary):
		return null
	var g: float = glow(pct)
	var p: Vector2 = (tgt as Dictionary)["pos"]
	var y: float = BODY_Y + float((tgt as Dictionary).get("height", 0.0))
	var core := _board(bead_tex(), p, y, BEAD_PX * (1.1 + 0.5 * g),
		Color(1.0, 1.0, 1.0, 0.95))
	_adopt(core, HIT_SEC * 0.6, "beadcore", {"a0": 0.95, "ps0": core.pixel_size})
	var fr := _board(frame_tex(), p, y, hit_radius(0.0, pct) * 2.0,
		Color(GOLD.r, GOLD.g, GOLD.b, 0.5 + 0.45 * g))
	return _adopt(fr, HIT_SEC, "frame", {"a0": 0.5 + 0.45 * g, "pct": pct})


# ══════════════════════════════════════════════════════════════════
#  §快照差分 —— `_queue_shots` 的金弹分支调这两个
# ══════════════════════════════════════════════════════════════════

## 开火【前】: 把全场每个单位的 `hp + shield` 记一份。
## ★★2026-08-08【金弹从错的地方射出去】—— 用户实测指出的:
##   起点原来一律取 `src["pos"]`, 而 `src` 是 **`_queue_shots` 的伤害归属方 = 携带者**。
##   于是凡是"实际开火的不是携带者本人"的装备(**九把枪里的 077 小手枪 / 079 珊瑚塔 /
##   080 直升机 / 086 浮游炮**), 金弹都是**从地上那只龟身上射出去的**,
##   而真正的枪/炮/机在别处 —— 同一发子弹画了两条起点完全不同的弹道。
##   根因: `src` 一个参数扛了两个语义(结算归属 / 出膛点), 必然有一边错。
##   ⇒ `from_override` 把"出膛点"独立出来; 不传时才退回 src["pos"](携带者自己开的枪)。
func arm(src, from_override = null) -> void:
	_snap.clear()
	_armed_src = src if src is Dictionary else null
	_armed_from = from_override if from_override is Vector2 else null
	if battle == null:
		return
	for u in battle._units:
		if u is Dictionary and u.get("alive", false):
			_snap.append([u, float(u.get("hp", 0.0)) + float(u.get("shield", 0.0))])


## 开火【后】: 比一遍快照, 掉血/掉盾的就是这一发打中的 ⇒ 在他身上画金弹命中 + 入射弹迹。
## 返回标了几个人(门禁数它: 0 = 这一发空放, 也是有意义的信息)。
func resolve(pct: float) -> int:
	var n := 0
	var from2: Vector2 = Vector2.ZERO
	if _armed_from is Vector2:
		from2 = _armed_from                      # ★真正开火那个东西的出膛点
	elif _armed_src is Dictionary:
		from2 = Vector2((_armed_src as Dictionary)["pos"])
	var aim: Vector2 = Vector2.RIGHT
	for e in _snap:
		var u = e[0]
		if not (u is Dictionary):
			continue
		var now: float = float(u.get("hp", 0.0)) + float(u.get("shield", 0.0))
		if now >= float(e[1]) - 0.001:
			continue
		var p: Vector2 = u["pos"]
		if n == 0:
			aim = p - from2
		trail(from2, p, pct)
		hit(u, pct)
		n += 1
	if _armed_src is Dictionary:
		muzzle(_armed_src, aim, pct, from2)
	_snap.clear()
	_armed_src = null
	_armed_from = null
	_shots_marked += 1
	return n


func shots_marked() -> int:
	return _shots_marked


# ══════════════════════════════════════════════════════════════════
#  §每帧推进(不用 tween) + 撤场
# ══════════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	if delta <= 0.0 or _fx.is_empty():
		return
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		var n = f.get("node", null)
		if not (n is Node3D) or not is_instance_valid(n):
			_fx.remove_at(i)
			continue
		f["t"] = float(f["t"]) + delta
		var q: float = clampf(float(f["t"]) / float(f["life"]), 0.0, 1.0)
		var a0: float = float(f.get("a0", 1.0))
		match str(f.get("kind", "")):
			"frame":
				var s: Sprite3D = n
				var r: float = hit_radius(q, float(f.get("pct", 1.0)))
				s.pixel_size = (r * 2.0 * float(battle.WS)) / maxf(1.0, float(s.texture.get_width()))
				_set_a(n, a0 * (1.0 - q * q))
			"muzzle":
				_set_a(n, a0 * (1.0 - q))
			_:
				_set_a(n, a0 * (1.0 - q * q))
		if q >= 1.0:
			(n as Node).queue_free()
			_fx.remove_at(i)


## 撤场: 拔掉一切自己建的节点。返回拔了几个(门禁验"真的清干净了")。
func clear() -> int:
	var n := 0
	for f in _fx:
		var x = f.get("node", null)
		if x is Node3D and is_instance_valid(x):
			x.queue_free()
			n += 1
	_fx.clear()
	_snap.clear()
	_armed_src = null
	return n


## 现存节点数(可按 kind 过滤) —— 门禁量真实对象用。
func alive_count(kind: String = "") -> int:
	var n := 0
	for f in _fx:
		var x = f.get("node", null)
		if not (x is Node3D) or not is_instance_valid(x):
			continue
		if kind != "" and str((x as Node).get_meta(META_KEY, "")) != kind:
			continue
		n += 1
	return n
