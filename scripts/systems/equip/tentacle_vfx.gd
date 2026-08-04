class_name TentacleVfx
extends RefCounted
## 灵物【触手】演出 —— **常驻实体 + 状态机**（2026-08-04）
##
## ══════════════════════════════════════════════════════════════════════
##  ★这一版改的是【它是什么】，不是【它长什么样】
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-04：「我为什么让你参考？」
##
## 我前两版把「参考俄洛伊」当成**照着画一条触手**在用（拿配色、拿形状、拿纹路），
## 做出来的是「每 5 秒凭空冒一条出来拍一下就没了」。**那是技能特效，不是一个存在。**
##
## 俄洛伊触手真正的设计是 —— 它**长在地上、一直在那儿**：
##   · 出土要 **2 秒**且期间不可选中 → 那 2 秒不是动画，是**给对手的预告**
##   · 有**待机态**（蛰伏）与**唤醒态**，攻击只是它的一个动作
##   · 所以玩家会**数**：这片区域有几根 = 这里有多危险
##
## ⇒ 本版：**每根触手一个常驻节点**，从出土活到换路，由状态机驱动。
##   文案写的是「N 个无敌触手**登场**」——"登场"意味着它在场上，
##   不常驻的话这四个字玩家永远读不到，后面画得再好也是给错的东西上妆。
##
## ── 时间节点（★取自 Riot 官方数值，不是我编的）──────────────────────
## | 出土 | **2 秒**（`wiki:Illaoi` "Tentacles fully spawn after a 2 second delay"）|
## | 唤醒/立起 | **0.25 秒**（"The Tentacle awakens over 0.25 seconds"）|
## | 一次攻击 | **0.5 秒**出手 + **0.5 秒**锁定（大招态原文）|
## | 连续攻击间隔 | 上次攻击后 **0.25 秒** |
##
## ⚠ 我们的触手是**每 5 秒拍一次的常驻 AOE**，不是"生成后被英雄唤醒"的实体。
##   照搬 2 秒出土会占掉 40% 周期 ⇒ **2 秒出土只在【登场】用一次**，
##   之后每次拍击走 `0.25 立起 + 0.5 出手`。
##
## ── 外观（★逐像素看过参考图，`docs/plans/ref-tentacle-illaoi.png`）──────
## 翠绿半透明发光带（`#20c050` 主体 / `#5effc8` 亮边）· 扁带状截面 · S 形 ·
## 梢端向内打卷成钩 · 表面方折回纹 · **没有吸盘**。
## （我凭记忆说的"紫色/实体/有吸盘/圆管/收尖"六条**全错**，看图后逐条推翻。）
##
## ── 技术路线 ────────────────────────────────────────────────────────
## 程序化 `ArrayMesh`（`SurfaceTool` 现算），不导 `.glb`：实跑核实本仓库
## **0 个模型文件 / 0 个 Skeleton3D / 0 个 AnimationPlayer**；而地图那三处
## （礁石/墙/穹顶）本来就是现算网格（`battle_world_builder.gd:710,742`）。
## 另一个好处：**程序化不产出图片，不吃「素材不许复用」那条铁律**。
##
## ⚠ 朝向坑：`Sprite3D.axis = AXIS_Y` 本身就是平铺，再 `rotation.x = -90` 会掰成竖环。
##   本文件不用 Sprite3D，直接建 `ArrayMesh` 顶点（世界坐标），没有那层歧义。

const VfxTex := preload("res://scripts/util/vfx_textures.gd")

var battle

# ── 状态 ──────────────────────────────────────────────────────────
enum { ST_EMERGE, ST_IDLE, ST_REAR, ST_SLAM, ST_RECOVER, ST_RETRACT }

## 各态时长（秒）。EMERGE / REAR / SLAM 三个取自官方数值，见文件头。
const T_EMERGE := 2.0
const T_REAR := 0.25
const T_SLAM := 0.5
const T_RECOVER := 0.35
const T_RETRACT := 0.6
## 闪避追击用的短促点刺（不立起、不预告）
const T_JAB := 0.30

# ── 形状 ──────────────────────────────────────────────────────────
##
## ★★2026-08-04【自截图看出来的第三次认错】：
##   我从参考图里读出"扁带状截面"，做出来是**一条挂着的缎带**，拍击时变成
##   **横躺过去的香蕉**。原因是 —— **参考图是 2D 插画，我看到的是【侧面轮廓】，
##   而真实结构是【锥体】。** 同一个错误我犯了三次（配色/形状/截面），
##   全都是"把 2D 呈现当成 3D 结构"。
##
## ★★第二个根本错误：拍击被我做成了**沿地面伸长**（`reach` 把它拉向目标）。
##   真触手**根部不动、总长固定**，形态只靠**弯曲角度**变 —— 像鞭子/手臂。
##   ⇒ 改成【固定弧长 + 沿切角积分】：
##      p(0) = 根部；逐段 p += (cos θ·前 + sin θ·上) · ds
##      θ(u) 由状态机给：待机前倾下垂、蓄势竖直后仰、砸下整条前倒。
##      这样长度天然守恒，看起来才像一根真的触手在动。
const SEG := 36
const RING := 8                      # 锥体截面的边数（不是扁带了）
const R_BASE := 0.42                 # 根部半径（世界米）
const R_TIP := 0.055                 # 梢端半径
## ★总弧长固定 —— 不随目标距离变。这是"它是一根实体"的关键。
const ARC_LEN := 9.0
## 各态的切角（度）：[根部角, 梢端角]。90° = 竖直向上，0° = 水平向前，负 = 朝下
const ANG_IDLE := [80.0, 26.0]       # 待机: 立着、梢端前倾
const ANG_REAR := [104.0, 76.0]      # 蓄势: 整条更直立 + 后仰
## ★砸下：根部保持较立（58°）、梢端扎到地里（−80°）——
##   【自截图看出来的】根部倒到 30° 时整条【平躺】在地上，像一条海带，
##   而参考里是"根立着、梢抽下来"的一道弧。差别就在根部这个角。
const ANG_SLAM := [58.0, -80.0]
const ANG_EMERGE := [88.0, 62.0]     # 出土: 竖着顶出来
## 梢端打卷：最后这一段额外多转的角度（度）
## ★★【探针算出来的 bug】: 原来 CURL_EXTRA 是恒定 210°，于是砸下时
##   梢端 = −78° − 210° = **−288° ≡ +72°**，又转回朝上 —— 卷曲和砸下互相抵消，
##   12 帧自截图看下来姿态几乎没变。
##   ⇒ 卷曲量改成**随状态变**：待机卷紧(蓄势)、砸下时【松开甩直】。
##     这也符合参考：俄洛伊触手蛰伏时卷着，砸下去是抽直的。
const CURL_FROM := 0.66
const CURL_IDLE := 170.0             # 待机/蓄势: 卷成钩
const CURL_SLAM := 15.0              # 砸下: 几乎抽直
## 待机摇曳的横向摆幅（度）
const S_AMP := 9.0
## 梢端相位滞后（鞭子感 —— 整条一起动就是根棍子）
const LAG := 0.26
## 待机摇曳
const SWAY_SPEED := 1.15
const SWAY_AMP := 0.30

# ── 配色（★参考图逐像素统计，不是我挑的）────────────────────────────
const C_CORE := Color(0.125, 0.75, 0.31)     # #20c050 主体
const C_EDGE := Color(0.37, 1.0, 0.78)       # #5effc8 亮边
const C_GLYPH := Color(0.62, 1.0, 0.85)      # 回纹（比主体亮）

## 回纹：1 = 亮刻痕。BAND 列 × 8 行一循环，沿长度平铺。
## ★方折的阶梯/迷宫纹（参考图上那种直角折线纹样），不是随便的亮条。
const GLYPH := [
	[0, 1, 1, 1, 0],
	[0, 1, 0, 0, 0],
	[0, 1, 0, 1, 1],
	[0, 1, 0, 1, 0],
	[0, 0, 0, 1, 0],
	[1, 1, 0, 1, 0],
	[0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0],
]

## 待机态的重算节流：摇曳很慢，不必每帧重建网格（4 根 × 320 面是每帧开销）
const IDLE_REBUILD_HZ := 12.0

## 常驻触手：key = "side|idx" → 状态字典
var _tents: Dictionary = {}
## 表皮贴图（只生成一次，全部触手共用同一张 —— 这是【同一个东西的同一张皮】，不是复用别的素材）
static var _skin_tex: ImageTexture = null


static func _skin() -> ImageTexture:
	if _skin_tex == null:
		_skin_tex = VfxTex._make_tentacle_skin()
	return _skin_tex


func _init(b) -> void:
	battle = b


func _key(side: String, idx: int) -> String:
	return "%s|%d" % [side, idx]


## 让某方场上恰好有 n 根触手（多了撤场、少了出土）。每帧由 spirit 系统调。
## ★这是"登场"那一段 —— 不调它，触手永远不存在。
func ensure(side: String, n: int) -> void:
	for idx in range(4):
		var k: String = _key(side, idx)
		var has: bool = _tents.has(k)
		if idx < n and not has:
			_spawn(side, idx)
		elif idx >= n and has:
			var t: Dictionary = _tents[k]
			if int(t["state"]) != ST_RETRACT:
				t["state"] = ST_RETRACT
				t["ts"] = 0.0


func _spawn(side: String, idx: int) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Tentacle_%s_%d" % [side, idx]
	mi.mesh = ArrayMesh.new()
	var mat := StandardMaterial3D.new()
	# ★unshaded + 加色 + 半透明 —— 参考图上触手是【能看到背后城镇的发光能量体】。
	#   开光照会有连续明暗渐变，跟限色像素立绘立刻打架。
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# ★★不能用 BLEND_MODE_ADD ——【自截图实测】：加色混合叠在本作那片【亮青色】战场上
	#   直接爆成白色，画面上看到的是一条白影，一点绿都没有。
	#   参考图上触手之所以是绿的，是因为它【本体接近不透明】、只有边缘发光；
	#   叠加混合只适合暗背景。⇒ 用普通 alpha 混合，亮边靠顶点色做。
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	# ★★回纹用【贴图】不用顶点色 ——【自截图实测】36×8 的网格上，一个格子在屏幕上才几像素，
	#   顶点色插值出来是一片糊，参考图上最有辨识度的方折回纹**一点都看不见**。
	#   贴图是逐像素画的（`VfxTex._make_tentacle_skin`），不复用任何现成图。
	mat.albedo_texture = _skin()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素风：不做双线性
	mat.uv1_scale = Vector3(1.0, 3.0, 1.0)                       # 沿长度平铺 3 遍
	mat.albedo_color = Color(1, 1, 1, 0.93)
	mi.material_override = mat
	battle._world.add_child(mi)
	_tents[_key(side, idx)] = {
		"mi": mi, "side": side, "idx": idx,
		"state": ST_EMERGE, "ts": 0.0,
		"aim": Vector2.ZERO, "share": 1.0,
		"phase": float(idx) * 1.7,          # 相位错开 → 两根不同步摇
		"acc": 0.0,
	}


## 请求一次拍击：进入蓄势(REAR) → 拍击(SLAM) → 回位。
## `share` 只影响幅度（正常 1.0，闪避追击 0.25 → 走短促点刺）。
## ★伤害【不在这里结算】—— 逻辑侧早就结完了。
##   CLAUDE.md §3.5：一个测数值的用例不该依赖任何动画跑完。
func strike(side: String, idx: int, aim2: Vector2, share: float = 1.0) -> void:
	var k: String = _key(side, idx)
	if not _tents.has(k):
		return
	var t: Dictionary = _tents[k]
	var s: int = int(t["state"])
	if s == ST_EMERGE or s == ST_RETRACT:
		return                                  # 还没站稳 / 正在撤 → 不接指令
	t["aim"] = aim2
	t["share"] = share
	# ★追击走【点刺】（不立起、不预告），正常拍击走【蓄势】——
	#   只有触手常驻，玩家才看得出"是它反应了一下"，所以追击不该复用整套拍击。
	t["state"] = ST_SLAM if share < 0.9 else ST_REAR
	t["ts"] = 0.0
	t["hit"] = false


func tick(delta: float) -> void:
	for k in _tents.keys():
		var t: Dictionary = _tents[k]
		t["ts"] = float(t["ts"]) + delta
		var st: int = int(t["state"])
		var ts: float = float(t["ts"])
		# ── 状态转移 ──────────────────────────────────
		match st:
			ST_EMERGE:
				if ts >= T_EMERGE:
					t["state"] = ST_IDLE; t["ts"] = 0.0
			ST_REAR:
				if ts >= T_REAR:
					t["state"] = ST_SLAM; t["ts"] = 0.0
			ST_SLAM:
				var dur: float = T_JAB if float(t["share"]) < 0.9 else T_SLAM
				# ★落地冲击放在【触地那一刻】(动作走完 60%)，不是动画末尾 ——
				#   末尾放的话观感是"砸完了才响"。60% 是缓动曲线上梢端接触地面的点。
				if not bool(t.get("hit", true)) and ts >= dur * 0.6:
					t["hit"] = true
					_impact(t)
				if ts >= dur:
					t["state"] = ST_RECOVER; t["ts"] = 0.0
			ST_RECOVER:
				if ts >= T_RECOVER:
					t["state"] = ST_IDLE; t["ts"] = 0.0
			ST_RETRACT:
				if ts >= T_RETRACT:
					var n = t["mi"]
					if is_instance_valid(n):
						n.queue_free()
					_tents.erase(k)
					continue
		# ── 重建网格（待机降频）────────────────────────
		t["acc"] = float(t["acc"]) + delta
		if int(t["state"]) == ST_IDLE and float(t["acc"]) < 1.0 / IDLE_REBUILD_HZ:
			continue
		t["acc"] = 0.0
		_rebuild(t)


## 落地冲击：贴地冲击环 + 一撮碎屑。
## ★只是演出 —— 伤害早就在逻辑侧结完了（CLAUDE.md §3.5：测数值的用例不该依赖动画）。
func _impact(t: Dictionary) -> void:
	var from2: Vector2 = root_pos(str(t["side"]), int(t["idx"]))
	var to2: Vector2 = t["aim"]
	if to2 == Vector2.ZERO:
		return
	var d: Vector2 = to2 - from2
	if d.length() < 1.0:
		return
	# 落点：朝目标方向、触手弧长够得到的地方（总长固定，够不着就落在最远处）
	var hit2: Vector2 = from2 + d.normalized() * minf(d.length(), 520.0)
	var big: bool = float(t["share"]) >= 0.9
	battle._skill_ring(hit2, Color(0.36, 1.0, 0.72, 0.62), 70.0 if big else 34.0)
	battle._vfx._impact_particles(hit2, 0.0)


## 触手的根部坐标（场边固定位，idx 0/1 分上下）。
## ★与 `spirit_synergy_system.tentacle_pos` 必须同一套 —— 那边算伤害用的就是这个原点。
func root_pos(side: String, idx: int) -> Vector2:
	var a: Rect2 = battle.ARENA
	var y: float = a.position.y + a.size.y * (0.35 if idx == 0 else 0.65)
	var x: float = a.position.x + a.size.x * 0.18
	if side != "left":
		x = a.position.x + a.size.x * 0.82
	return Vector2(x, y)


## 当前这根触手的「动作进度」→ [露出比例 emerge, 根部切角(度), 梢端切角(度), 卷曲量(度)]
## ★不再返回"高度/前伸" —— 那套做出来是"沿地面伸长"，不是砸下。见形状常量那节。
func _phase(t: Dictionary) -> Array:
	var st: int = int(t["state"])
	var ts: float = float(t["ts"])
	match st:
		ST_EMERGE:
			var e: float = clampf(ts / T_EMERGE, 0.0, 1.0)
			var k: float = smoothstep(0.0, 1.0, e)
			return [e, lerpf(ANG_EMERGE[0], ANG_IDLE[0], k), lerpf(ANG_EMERGE[1], ANG_IDLE[1], k), CURL_IDLE * k]
		ST_IDLE:
			return [1.0, ANG_IDLE[0], ANG_IDLE[1], CURL_IDLE]
		ST_REAR:
			var r: float = smoothstep(0.0, 1.0, clampf(ts / T_REAR, 0.0, 1.0))
			return [1.0, lerpf(ANG_IDLE[0], ANG_REAR[0], r), lerpf(ANG_IDLE[1], ANG_REAR[1], r), CURL_IDLE]
		ST_SLAM:
			var dur: float = T_JAB if float(t["share"]) < 0.9 else T_SLAM
			# ★砸下用【前快后慢】的缓动：0.3 秒内甩到底，剩下的时间压在地上
			var s2: float = clampf(ts / dur, 0.0, 1.0)
			var e2: float = 1.0 - pow(1.0 - s2, 3.0)
			return [1.0, lerpf(ANG_REAR[0], ANG_SLAM[0], e2), lerpf(ANG_REAR[1], ANG_SLAM[1], e2), lerpf(CURL_IDLE, CURL_SLAM, e2)]
		ST_RECOVER:
			var c: float = smoothstep(0.0, 1.0, clampf(ts / T_RECOVER, 0.0, 1.0))
			return [1.0, lerpf(ANG_SLAM[0], ANG_IDLE[0], c), lerpf(ANG_SLAM[1], ANG_IDLE[1], c), lerpf(CURL_SLAM, CURL_IDLE, c)]
		ST_RETRACT:
			var q: float = clampf(ts / T_RETRACT, 0.0, 1.0)
			return [1.0 - q, ANG_IDLE[0], ANG_IDLE[1], CURL_IDLE]
	return [1.0, ANG_IDLE[0], ANG_IDLE[1], CURL_IDLE]


func _rebuild(t: Dictionary) -> void:
	var mi: MeshInstance3D = t["mi"]
	if not is_instance_valid(mi):
		return
	var mesh: ArrayMesh = mi.mesh
	mesh.clear_surfaces()
	var side: String = str(t["side"])
	var from2: Vector2 = root_pos(side, int(t["idx"]))
	var to2: Vector2 = t["aim"]
	if to2 == Vector2.ZERO:
		to2 = from2 + Vector2(1.0 if side == "left" else -1.0, 0.0) * 400.0
	var ph: Array = _phase(t)
	var emerge: float = float(ph[0])
	var a0: float = float(ph[1])       # 根部切角(度)
	var a1: float = float(ph[2])       # 梢端切角(度)
	var curl: float = float(ph[3])     # 卷曲量(度) —— 随状态变, 砸下时松开

	# 世界系的"前"与"上"
	var d2: Vector2 = to2 - from2
	if d2.length() < 1.0:
		d2 = Vector2.RIGHT
	var dir2: Vector2 = d2.normalized()
	var nrm2 := Vector2(-dir2.y, dir2.x)
	var root3: Vector3 = battle._world_pos(from2, battle.GROUND_LIFT)
	var wa: Vector3 = battle._world_pos(from2 + dir2 * 100.0, battle.GROUND_LIFT)
	var fwd: Vector3 = (wa - root3).normalized()
	var wn: Vector3 = battle._world_pos(from2 + nrm2 * 100.0, battle.GROUND_LIFT)
	var lat: Vector3 = (wn - root3).normalized()
	var up := Vector3.UP

	var swayt: float = battle._t * SWAY_SPEED + float(t["phase"])
	var ds: float = ARC_LEN * emerge / float(SEG)     # 出土 = 露出的弧长在长

	var stool := SurfaceTool.new()
	stool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pos: Vector3 = root3
	var prev: Array = []
	var prev_cols: Array = []
	var prev_uvs: Array = []
	var any := false
	for sidx in range(SEG + 1):
		var u: float = float(sidx) / float(SEG)
		# ★切角沿长度插值；梢端那一段额外多转 → 卷成钩
		var ang: float = lerpf(a0, a1, smoothstep(0.0, 1.0, u))
		if u > CURL_FROM:
			var cu: float = (u - CURL_FROM) / (1.0 - CURL_FROM)
			ang -= curl * cu * cu
		# 横向摆（待机摇曳 + S 形）
		var yaw: float = deg_to_rad(S_AMP * sin(u * TAU * 0.6 + swayt))
		var ar: float = deg_to_rad(ang)
		var tan: Vector3 = (fwd * cos(ar) * cos(yaw) + lat * sin(yaw) * cos(ar) + up * sin(ar)).normalized()
		# 截面
		var sidev: Vector3 = tan.cross(up)
		if sidev.length() < 0.001:
			sidev = lat
		sidev = sidev.normalized()
		var up2: Vector3 = sidev.cross(tan).normalized()
		var r: float = lerpf(R_BASE, R_TIP, pow(u, 0.72))
		if int(t["state"]) == ST_SLAM:
			r *= 1.15
		var ring: Array = []
		var cols: Array = []
		var uvs: Array = []
		for k in range(RING):
			var aa: float = TAU * float(k) / float(RING)
			ring.append(pos + (sidev * cos(aa) + up2 * sin(aa)) * r)
			uvs.append(Vector2(float(k) / float(RING), u))
			# 朝向镜头那一侧亮（伪边缘光）+ 回纹
			var lit: float = 0.5 + 0.5 * sin(aa)
			# 顶点色只做【整体调制】—— 回纹交给贴图（见材质那段的说明）
			var col: Color = Color(1, 1, 1).lerp(Color(0.72, 1.0, 0.86), lit * 0.30)
			if int(t["state"]) == ST_REAR:
				col = col.lerp(C_EDGE, 0.4 * clampf(float(t["ts"]) / T_REAR, 0.0, 1.0))
			cols.append(col.lerp(Color(0.80, 1.0, 0.92), u * 0.25))
		if not prev.is_empty():
			any = true
			for k2 in range(RING):
				var k3: int = (k2 + 1) % RING
				var u3a: Vector2 = prev_uvs[k2]
				var u3b: Vector2 = Vector2(1.0, prev_uvs[k3].y) if k3 == 0 else prev_uvs[k3]
				var u3c: Vector2 = uvs[k2]
				var u3d: Vector2 = Vector2(1.0, uvs[k3].y) if k3 == 0 else uvs[k3]
				stool.set_color(prev_cols[k2]); stool.set_uv(u3a); stool.add_vertex(prev[k2])
				stool.set_color(prev_cols[k3]); stool.set_uv(u3b); stool.add_vertex(prev[k3])
				stool.set_color(cols[k2]);      stool.set_uv(u3c); stool.add_vertex(ring[k2])
				stool.set_color(prev_cols[k3]); stool.set_uv(u3b); stool.add_vertex(prev[k3])
				stool.set_color(cols[k3]);      stool.set_uv(u3d); stool.add_vertex(ring[k3])
				stool.set_color(cols[k2]);      stool.set_uv(u3c); stool.add_vertex(ring[k2])
		prev = ring
		prev_cols = cols
		prev_uvs = uvs
		# ★沿切向走一步 —— 弧长天然守恒，这就是"长度固定"的来源
		pos += tan * ds
		if pos.y < root3.y - 0.4:
			pos.y = root3.y - 0.4                 # 别扎穿地板太多
	if any:
		stool.generate_normals()
		stool.commit(mesh)


## 场上现有几根（给门禁与调试用）
func count(side: String = "") -> int:
	if side == "":
		return _tents.size()
	var n := 0
	for k in _tents:
		if str((_tents[k] as Dictionary)["side"]) == side:
			n += 1
	return n


func state_of(side: String, idx: int) -> int:
	var k: String = _key(side, idx)
	return int((_tents[k] as Dictionary)["state"]) if _tents.has(k) else -1


## 换路 / 战斗结束：立刻撤干净（不走 RETRACT 动画 —— 场景要清空了）
func clear() -> void:
	for k in _tents:
		var n = (_tents[k] as Dictionary)["mi"]
		if is_instance_valid(n):
			n.queue_free()
	_tents.clear()
