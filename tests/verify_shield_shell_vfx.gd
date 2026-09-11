extends Node
## verify_shield_shell_vfx.gd — 「获得护盾」的演出必须罩在**单位身上** (2026-09-11)
##
## ════════════════════════════════════════════════════════════════════════
##  ★由来
## ════════════════════════════════════════════════════════════════════════
## 用户看 012 的护盾演出:
##     「**我不明白lol里获得护盾都是你这样在地上搞一下的吗**」
## 上一轮(2026-08-09)看 095 时否的是同一个东西:
##     「又是程序生成的环？哪个商业游戏是你这么做啊」
##
## 被否的是 `battle_damage._grant_shield` 末尾那行 `_skill_ring(...)` ——
## 在**地上**画一个金圈, 而它封着全游戏 44 个给盾点。
##
## ════════════════════════════════════════════════════════════════════════
##  ★判据怎么定的
## ════════════════════════════════════════════════════════════════════════
## 用户的话是「**在地上**搞一下」⇒ 判据必须直接量【地上有没有多出东西】和
## 【单位身上有没有多出东西】, 而不是"函数存在"或"常量等于常量"
## ([[fb-gate-must-measure-requirement-not-my-hook]])。
##
## 「贴地环」在这个引擎里有一个**结构性签名**(见 `_skill_ring`):
##     `billboard = DISABLED` + `axis = AXIS_Y`(躺平) + `position.y ≈ 0.05`
## 「罩在身上」的签名正相反: `billboard = ENABLED` + y 抬到龟身高度。
## ⇒ ①数地上新增了几个贴地环(必须 0) ②数身上新增了几个公告板(必须 ≥1)。
##
## ★每条都配分母: 先证明"这一刻确实给了盾", 否则 0 个环也可能只是因为根本没触发。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BV := preload("res://scripts/scenes/battle/battle_vfx.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(side: String, off: Vector2) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("green", side, c + off)
	u["maxHp"] = 5000.0
	u["hp"] = 5000.0
	u["shield"] = 0.0
	u["shield_amp"] = 0.0
	u["no_basic"] = true
	u["no_move"] = true
	u["eq_state"] = {}
	return u


## 把 _world 里当前的特效节点分成两类点名数: (贴地环, 罩在身上的公告板)
## 贴地环签名照抄 `_skill_ring`: 不公告板 + axis=AXIS_Y(躺平) + 贴着地面。
func _census() -> Array:
	var ground := 0
	var on_unit := 0
	for ch in _s._world.get_children():
		if not (ch is Sprite3D):
			continue
		var sp: Sprite3D = ch
		if sp.billboard == BaseMaterial3D.BILLBOARD_DISABLED \
				and sp.axis == Vector3.AXIS_Y and sp.position.y < 0.20:
			ground += 1
		elif sp.billboard == BaseMaterial3D.BILLBOARD_ENABLED and sp.position.y > 0.40:
			on_unit += 1
	return [ground, on_unit]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 获得护盾的演出: 罩在单位身上, 不是地上画圈 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s._edit_mode = false
	_s._over = false

	_g1_not_on_the_ground()
	_g2_asset_is_pixel_art()
	_g3_frames_advance_and_free()
	_g4_own_vfx_opt_out()
	_g5_kelp_012()

	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 18:
		print("  [FAIL] ★分母: 断言只有 %d 条(<18) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 护盾演出在单位身上" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ── ① 给盾这一下: 地上不许多出环, 身上必须多出罩 ─────────────────────────
func _g1_not_on_the_ground() -> void:
	print("--- ① 给盾 → 罩在身上 ---")
	var u: Dictionary = _mk("left", Vector2(-140, 0))
	_s._units.clear()
	_s._units.append(u)
	var before: Array = _census()
	var fv0: int = _s._follow_vfx.size()
	_s._damage._grant_shield(u, 120.0, 4.0)
	var after: Array = _census()
	_ok("① ★分母: 这一刻确实给了盾(没给盾的话下面数 0 个环毫无意义)",
		float(u["shield"]) > 1.0, "盾 %.0f" % float(u["shield"]))
	_ok("① ★★地上**没有**多出贴地环(用户:「在地上搞一下」否的就是这个)",
		int(after[0]) - int(before[0]) == 0,
		"贴地环 %d → %d" % [int(before[0]), int(after[0])])
	_ok("① ★★单位身上多出了罩子(公告板 + 抬到身高)",
		int(after[1]) - int(before[1]) >= 1,
		"身上罩 %d → %d" % [int(before[1]), int(after[1])])
	_ok("① ★罩子登记进了跟随表(会跟着龟走, 不是钉在给盾那一刻的坐标)",
		_s._follow_vfx.size() > fv0, "跟随表 %d → %d" % [fv0, _s._follow_vfx.size()])

	## 真的跟着走: 把龟挪开, 跑**真的**跟随 tick, 看罩子的水平坐标有没有跟上
	var spr: Sprite3D = null
	for f in _s._follow_vfx:
		if f.get("unit", null) != null and is_same(f["unit"], u):
			spr = f["spr"]
	_ok("① ★分母: 找得到这只龟身上的那个罩子节点", spr != null and is_instance_valid(spr))
	if spr == null or not is_instance_valid(spr):
		return
	var p0: Vector3 = spr.position
	u["pos"] = u["pos"] + Vector2(180.0, 0.0)
	_s._render._tick_follow_vfx()
	var moved: float = Vector2(spr.position.x - p0.x, spr.position.z - p0.z).length()
	_ok("① ★★龟走了 180 码, 罩子跟着走了(不是钉在原地)", moved > 180.0 * _s.WS * 0.8,
		"罩子水平位移 %.3f 米(应 ≈ %.3f)" % [moved, 180.0 * _s.WS])
	_ok("① ★罩子挂在龟身上的高度(不是贴地)", spr.position.y > 0.40,
		"y = %.2f 米" % spr.position.y)


# ── ② 素材本身必须是真像素画 ───────────────────────────────────────────
func _g2_asset_is_pixel_art() -> void:
	print("--- ② 素材: 真像素画 + 镂空 ---")
	var tex: Texture2D = load(BV.SHELL_TEX)
	_ok("② ★分母: 素材 import 得进来(null = 没 --import, 游戏里根本看不见)", tex != null)
	if tex == null:
		return
	var img: Image = tex.get_image()
	var w: int = img.get_width()
	var h: int = img.get_height()
	_ok("② 8 帧横排, 每帧是方的(%d×%d)" % [w, h],
		w == h * BV.SHELL_FRAMES, "实得 %d×%d" % [w, h])
	var cols := {}
	var semi := 0
	var opaque := 0
	for y in range(h):
		for x in range(w):
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.001:
				continue
			if c.a < 0.999:
				semi += 1
			else:
				opaque += 1
				cols[Vector3i(int(c.r8), int(c.g8), int(c.b8))] = true
	_ok("② ★色数 ≤ 8(像素画判据·实得 %d)" % cols.size(), cols.size() <= 8)
	## ★判据换过形状(2026-09-11): 原来是「半透明像素必须是 0」。
	##   那条规矩是**我自己定的**(pixelize_sheet.py:171「像素画不要羽化」), 用户从没定过;
	##   它把两件不同的事混成一条 —— **羽化的边缘**(该禁) 与 **刻意的半透填充**(护盾罩
	##   能"罩住但不遮住"的唯一手段)。混在一起的后果: 罩子只能做成空心格线,
	##   而空心格线正是用户说「完全不够商业游戏」的那个东西。
	## ⇒ 改成卡【alpha 只能有少数几档】: 硬阶梯放行, 连续羽化照红 —— **收得更准, 不是放松**。
	var alphas := {}
	for y in range(h):
		for x in range(w):
			var ca: float = img.get_pixel(x, y).a
			if ca > 0.001:
				alphas[int(round(ca * 255.0))] = true
	_ok("② ★alpha 只能是硬阶梯(档数 %d, 需 ≤ 16); 连续羽化会几十上百档" % alphas.size(),
		alphas.size() <= 16, "实得 %d 档" % alphas.size())
	_ok("② ★分母: 确实用了半透明(全不透明 = 又变回遮住龟的那种·实得 %d 个)" % semi,
		semi > 200, "半透像素 %d" % semi)
	_ok("② ★分母: 真的画了东西(不透明 %d 个)" % opaque, opaque > 1000)
	## 纯灰度: 罩子的颜色由调用点 modulate 决定, 素材带色相会串到全部 44 处
	var tinted := 0
	for k in cols.keys():
		if (k as Vector3i).x != (k as Vector3i).y or (k as Vector3i).y != (k as Vector3i).z:
			tinted += 1
	_ok("② ★必须纯灰 R=G=B(带色相的 %d 种, 须 0)" % tinted, tinted == 0)
	## ★需求是【看得见里面的龟】, 不是【中心必须是空的】。
	##   v1 靠镂空满足它, v2 靠半透满足它 —— 判据要卡**需求**不是卡某一种实现。
	##   卡实现的判据会把正确的做法也判成错的。
	var core_block := 0
	var core_total := 0
	var cx: int = int(h / 2)
	var cy: int = int(h / 2)
	for y in range(cy - 8, cy + 9):
		for x in range(cx - 8, cx + 9):
			core_total += 1
			## 取满格帧(第 2 帧) —— 数第 0 帧等于放水
			if img.get_pixel(x + 2 * h, y).a > 0.62:
				core_block += 1
	_ok("③ ★★罩中心看得见里面的龟: 满格帧中心 17×17 里不该有不透明像素(实得 %d/%d)"
		% [core_block, core_total], core_block == 0)


# ── ③ 帧动画真的在推进, 且放完自销 ─────────────────────────────────────
func _g3_frames_advance_and_free() -> void:
	print("--- ③ 8 帧真的在推进 ---")
	var u: Dictionary = _mk("left", Vector2(-140, 60))
	_s._units.clear()
	_s._units.append(u)
	_s._damage._grant_shield(u, 100.0, 4.0)
	var spr: Sprite3D = null
	var ent: Dictionary = {}
	for f in _s._follow_vfx:
		if f.get("unit", null) != null and is_same(f["unit"], u) and f.has("anim_fps"):
			spr = f["spr"]
			ent = f
	_ok("③ ★分母: 罩子带着帧动画参数(没有 anim_fps = 它是张死图)",
		spr != null and not ent.is_empty())
	if spr == null:
		return
	_ok("③ ★分母: hframes 与素材的帧数对得上", spr.hframes == BV.SHELL_FRAMES,
		"hframes=%d" % spr.hframes)
	## ★时刻用**绝对值**算, 不累加: 第一版写 `_t += 1.0/fps` 跑了一个[1,2,3,4,5,6,7,7]
	##   —— 八次 0.05 累加出来是 0.39999997, ×20 后 int() 掉回 7。那是**尺子**的 float 刀口
	##   (与 _wait_sim 那个同族), 不是产品的毛病 —— 不该把测试自己的误差算到被测头上。
	var t0: float = float(ent["anim_t0"])
	var seen: Array = []
	for step in range(BV.SHELL_FRAMES):
		if not is_instance_valid(spr):
			break
		_s._t = t0 + (float(step) + 0.5) / float(BV.SHELL_FPS)   # 落在每帧中间, 避开边界
		_s._render._tick_follow_vfx()
		if is_instance_valid(spr):
			seen.append(int(spr.frame))
	var rising := true
	for i in range(1, seen.size()):
		if int(seen[i]) <= int(seen[i - 1]):
			rising = false
	_ok("③ ★★帧号随游戏时钟单调上升(不是永远停在第 0 帧)",
		seen.size() == BV.SHELL_FRAMES and rising and int(seen[0]) == 0
			and int(seen[-1]) == BV.SHELL_FRAMES - 1,
		"帧序列 %s(应 0…%d)" % [str(seen), BV.SHELL_FRAMES - 1])
	## 再推过总时长: 必须从跟随表里摧销 + 节点排队销毁。
	## ★判 `is_instance_valid` 是错的: queue_free() 是**延到帧尾**才真删,
	##   同步跑的测试里它一直是 true —— 第一版就这么红的。真实的产品账是这两条。
	var fv_before: int = _s._follow_vfx.size()
	_s._t = t0 + float(BV.SHELL_FRAMES) / float(BV.SHELL_FPS) + 0.5
	_s._render._tick_follow_vfx()
	var still_listed := false
	for f in _s._follow_vfx:
		if f.get("spr", null) == spr:
			still_listed = true
	_ok("③ ★放完从跟随表里摧销(否则每帧白跑一遍)",
		not still_listed and _s._follow_vfx.size() < fv_before,
		"跟随表 %d → %d" % [fv_before, _s._follow_vfx.size()])
	_ok("③ ★放完节点排了销毁(不残留在场上)",
		(not is_instance_valid(spr)) or spr.is_queued_for_deletion())


# ── ④ 自绘方仍能跳过通用罩(095 那条路不许被压掉) ────────────────────────
func _g4_own_vfx_opt_out() -> void:
	print("--- ④ _own_grant_vfx: 自绘时跳过通用罩 ---")
	var u: Dictionary = _mk("left", Vector2(-140, 120))
	_s._units.clear()
	_s._units.append(u)
	var b: Array = _census()
	u["_own_grant_vfx"] = true
	_s._damage._grant_shield(u, 100.0, 4.0)
	var a: Array = _census()
	_ok("④ ★分母: 盾还是给了(闸住的是演出, 不是效果)", float(u["shield"]) > 1.0,
		"盾 %.0f" % float(u["shield"]))
	_ok("④ 置了 _own_grant_vfx ⇒ **不**再叠通用罩", int(a[1]) - int(b[1]) == 0,
		"身上罩 %d → %d" % [int(b[1]), int(a[1])])
	_ok("④ 用完即清(不许粘住让这只龟以后永远没有护盾演出)",
		not u.has("_own_grant_vfx"))


# ── ⑤ 012 海藻: 脚下长出一丛海藻(来源标识) ─────────────────────────────
func _g5_kelp_012() -> void:
	print("--- ⑤ 012 海藻: 脚下长海藻 ---")
	var u: Dictionary = _mk("left", Vector2(-140, 180))
	u["equips"] = [{"id": "p2eq_012", "star": 3}]
	u["eq_state"] = {"p2eq_012": {}}
	_s._units.clear()
	_s._units.append(u)
	var fv0: int = _s._follow_vfx.size()
	_s._equip_tick_sys._tick_jelly(u, 4.1)
	_ok("⑤ ★分母: 到点真的给盾了(没触发的话下面数海藻没意义)",
		float(u["shield"]) > 1.0, "盾 %.0f" % float(u["shield"]))
	var kelps: Array = []
	for i in range(fv0, _s._follow_vfx.size()):
		var f: Dictionary = _s._follow_vfx[i]
		if f.has("orbit_r") and f.has("anim_fps"):
			kelps.append(f)
	_ok("⑤ ★★长出了 %d 丛海藻" % BV.KELP_N, kelps.size() == BV.KELP_N,
		"实得 %d 丛" % kelps.size())
	if kelps.size() < 2:
		return
	## 错开起跳: 全一样 = 一个印章盖下去
	var t0s: Array = []
	for f in kelps:
		t0s.append(float(f["anim_t0"]))
	var spread: float = float(t0s.max()) - float(t0s.min())
	_ok("⑤ ★四丛**错开**起跳(全同时 = 一个印章盖下去)", spread > 0.01,
		"起跳时刻跨度 %.3f 秒" % spread)
	## 绕身分布: 角度各不相同, 不是四丛叠在同一个点
	var angs := {}
	for f in kelps:
		angs[int(round(float(f["orbit_a"]) * 100.0))] = true
	_ok("⑤ ★四丛分布在不同角度(不是叠在一起)", angs.size() == kelps.size(),
		"不同角度 %d 个" % angs.size())
	## ★012 不自绘 ⇒ 通用六棱罩照样罩上(两层各司其职, 不是二选一)
	var shells := 0
	for i in range(fv0, _s._follow_vfx.size()):
		var f: Dictionary = _s._follow_vfx[i]
		if f.has("anim_fps") and not f.has("orbit_r"):
			shells += 1
	_ok("⑤ ★★海藻之外**还有**通用六棱罩(它是全游戏【我有盾了】的统一语言)",
		shells >= 1, "罩子 %d 个" % shells)
