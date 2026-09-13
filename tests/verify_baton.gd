extends Node
## verify_baton.gd — 027 电棍的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 「每 **3 秒**充能就绪, 下一次**普攻命中**时对该目标追加 **30/40/50 魔法伤害**
##   并使其**眩晕 2.5/2.5/3 秒**, 每次消耗 **1 层**电击
##   (装备时拥有 **3/4/5 层**, **层数为 0 时停止, 装备不消失**; 层数每场战斗重置)。」
##
## ⇒ 量五件事: 起手层数 / 每次只消耗 1 层 / 追加伤害是魔法伤 / 眩晕时长 / 层数归零后停但装备还在。
##
## ★这一件**原来没有台子也没有门禁** —— 从没被逐件体检过。
## ★它的结算是**同步的**(挂在普攻钩子上), 没有 024/025/026 那条「延时挂 tween」的病。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ET := preload("res://scripts/systems/equip/equip_tick_system.gd")

const CHARGES := [3, 4, 5]
const DMG := [30, 40, 50]
const STUN := [2.5, 2.5, 3.0]
const READY_SEC := 3.0

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


## ★用产品自己的造单位函数(手抄字段表必漏 —— 024 那轮抄两版漏两样)
func _mk(px: float, py: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, Vector2(px, py))
	u["hp"] = 90000.0
	u["maxHp"] = 90000.0
	u["atk"] = 100.0
	u["alive"] = true
	u["crit"] = 0.0          # 判据要对随机不敏感
	u["critDmg"] = 1.0
	u["atk_interval"] = 9999.0   # 关掉自动普攻这个噪声源
	u["atk_cd"] = 9999.0
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 027 电棍: 每 3 秒充能, 普攻命中追加魔法伤 + 眩晕, 消耗 1 层 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false
	var ets = _s._equip_tick_sys

	# ── ① ★★起手层数吃星级: 3/4/5 ────────────────────────────────
	## 层数由产品的 `equip_stats_apply` 给 —— 门禁自己喂就是恒真式
	for si in [0, 1, 2]:
		_s._units.clear()
		var u: Dictionary = _mk(500.0, 400.0, "left")
		u["equips"] = [{"id": "p2eq_027", "star": [1, 2, 3][si]}]
		u["eq_state"] = {}
		_s._units.append(u)
		_s._equip_sys._stats._eq_apply_one_stats(u, "p2eq_027", [1, 2, 3][si])
		var got: int = int(u["eq_state"].get("p2eq_027", {}).get("baton_charges", -1))
		_ok("① ★★★%d 星起手 %d 层(应 %d 层)" % [[1, 2, 3][si], got, CHARGES[si]],
			got == CHARGES[si], "层数由 equip_stats_apply 给, 不是门禁喂的")

	# ── ② ★★充能要 3 秒, 不到不就绪 ─────────────────────────────
	_s._units.clear()
	var c: Dictionary = _mk(500.0, 400.0, "left")
	c["equips"] = [{"id": "p2eq_027", "star": 3}]
	c["eq_state"] = {}
	_s._units.append(c)
	_s._equip_sys._stats._eq_apply_one_stats(c, "p2eq_027", 3)
	ets._tick_baton(c, READY_SEC - 0.2)
	_ok("② ★分母: 差 0.2 秒时**还没**就绪",
		not bool(c["eq_state"]["p2eq_027"].get("baton_ready", false)))
	ets._tick_baton(c, 0.3)
	_ok("② ★★满 %.0f 秒就绪" % READY_SEC,
		bool(c["eq_state"]["p2eq_027"].get("baton_ready", false)))

	# ── ③ ★★普攻命中: 追加伤害 + 眩晕 + 只消耗 1 层 ──────────────
	var foe: Dictionary = _mk(700.0, 400.0, "right")
	foe["mr"] = 0.0
	_s._units.append(foe)
	var ch0: int = int(c["eq_state"]["p2eq_027"]["baton_charges"])
	var hp0: float = float(foe["hp"])
	_s._equip_sys._eq_on_basic_attack(c, foe)
	var dealt: float = hp0 - float(foe["hp"])
	var ch1: int = int(c["eq_state"]["p2eq_027"]["baton_charges"])
	_ok("③ ★分母: 命中后目标掉血了(实得 %.0f)" % dealt, dealt > 0.0)
	_ok("③ ★★只消耗 1 层(%d → %d)" % [ch0, ch1], ch1 == ch0 - 1)
	_ok("③ ★★用掉之后回到【未就绪】(要再充 3 秒)",
		not bool(c["eq_state"]["p2eq_027"].get("baton_ready", false)))
	_ok("③ ★★★目标被眩晕(stun_until %.2f > 当前 %.2f)"
		% [float(foe.get("stun_until", 0.0)), _s._t],
		float(foe.get("stun_until", 0.0)) > _s._t,
		"文案写的是【眩晕】; 代码里 `_freeze` 内部走的就是 `_stun`")
	var stun_len: float = float(foe.get("stun_until", 0.0)) - _s._t
	_ok("③ ★★★3 星眩晕 %.1f 秒(应 %.1f)" % [stun_len, STUN[2]],
		absf(stun_len - STUN[2]) < 0.2)

	# ── ④ ★★没就绪时普攻**不**触发(否则等于没有充能这回事) ───────
	var foe2: Dictionary = _mk(760.0, 400.0, "right")
	foe2["mr"] = 0.0
	_s._units.append(foe2)
	var ch2: int = int(c["eq_state"]["p2eq_027"]["baton_charges"])
	var h2: float = float(foe2["hp"])
	_s._equip_sys._eq_on_basic_attack(c, foe2)
	_ok("④ ★★没就绪时不触发: 层数没变(%d) 且目标没被眩晕"
		% int(c["eq_state"]["p2eq_027"]["baton_charges"]),
		int(c["eq_state"]["p2eq_027"]["baton_charges"]) == ch2
			and float(foe2.get("stun_until", 0.0)) <= _s._t,
		"掉血 %.0f(追加伤害那一段不该有)" % (h2 - float(foe2["hp"])))

	# ── ⑤ ★★★层数耗尽后【停止, 但装备不消失】 ───────────────────
	var st: Dictionary = c["eq_state"]["p2eq_027"]
	st["baton_charges"] = 0
	st["baton_ready"] = false
	st["baton_cd"] = 0.0
	ets._tick_baton(c, 10.0)          # 充很久
	_ok("⑤ ★★层数为 0 时**不再就绪**(充多久都没用)",
		not bool(c["eq_state"]["p2eq_027"].get("baton_ready", false)))
	var has_eq := false
	for e in c["equips"]:
		if str(e.get("id", "")) == "p2eq_027":
			has_eq = true
	_ok("⑤ ★★★**装备不消失**(文案明写: 层数为 0 时停止, 装备不消失)", has_eq)

	# ── ⑥ 伤害口径: 是魔法伤害(吃魔抗) ──────────────────────────
	## ★不断言绝对数值: 携带者 id="basic" 走小龟·不屈(+20%), 那是产品本来的行为。
	_s._units.clear()
	var c6: Dictionary = _mk(500.0, 400.0, "left")
	c6["equips"] = [{"id": "p2eq_027", "star": 3}]
	c6["eq_state"] = {}
	_s._units.append(c6)
	_s._equip_sys._stats._eq_apply_one_stats(c6, "p2eq_027", 3)
	var soft: Dictionary = _mk(700.0, 400.0, "right")
	soft["mr"] = 0.0
	var hard: Dictionary = _mk(760.0, 400.0, "right")
	hard["mr"] = 500.0
	_s._units.append(soft)
	_s._units.append(hard)
	ets._tick_baton(c6, READY_SEC + 0.1)
	var hs: float = float(soft["hp"])
	_s._equip_sys._eq_on_basic_attack(c6, soft)
	var ds: float = hs - float(soft["hp"])
	ets._tick_baton(c6, READY_SEC + 0.1)
	var hh: float = float(hard["hp"])
	_s._equip_sys._eq_on_basic_attack(c6, hard)
	var dh: float = hh - float(hard["hp"])
	_ok("⑥ ★分母: 两边都掉血了(软 %.0f / 硬 %.0f)" % [ds, dh], ds > 0.0 and dh > 0.0)
	_ok("⑥ ★★魔抗 500 吃得明显少 ⇒ 是【魔法伤害】(软 %.0f vs 硬 %.0f)" % [ds, dh],
		dh < ds * 0.5)

	# ── ⑦ ★★★演出层: 电棍要**看得出是电**, 且贴住判定 ──────────────
	## 为什么这一节必须存在(memory [[fb-weld-visual-lessons-into-gate]]: 视觉教训焊进门禁,
	## 别指望我下次想得起来):
	##   原来两处演出都借 `electric-zap.png` —— 一张**对称放射星爆**, 而且
	##   **五帧里有两帧是暗的**(frame4 均色 R18 G25 B34、近白像素 0 个),
	##   偏偏就绪火花抽的是 `randi() % 5` ⇒ 40% 的火花在黑场里读成一团污渍。
	var VX = load("res://scripts/scenes/battle/battle_vfx.gd")
	var arc_tex: Texture2D = load(VX.BATON_ARC_TEX)
	var stk_tex: Texture2D = load(VX.BATON_STRIKE_TEX)
	_ok("⑦ ★分母: 两张素材都 import 得出来", arc_tex != null and stk_tex != null,
		"换了 png 不 --import 的话 load 返回 null, 游戏里直接看不见")
	if arc_tex != null and stk_tex != null:
		## a) 没有黑帧 —— 逐帧量【亮像素占不透明像素的比例】。
		##    ★★判据换过一版, 换的是**形状**不是阈值(memory [[fb-my-thresholds-degrade-good-assets]]):
		##      第一版量「不透明像素的平均亮度 ≥ 150」, 结果我给弧加了**深蓝描边**(像素画的正解,
		##      不加就在亮青色的龟身上看不见)之后平均亮度掉到 124 —— 判据要把好素材判红了。
		##      真正要卡的从来不是"平均多亮", 是「这一帧在黑场里**有没有看得见的东西**」。
		##    对照: electric-zap frame4 = 0/1037 = 0.00(整帧没有一个亮像素) ⇒ 抽到它等于什么都没画;
		##          它的 frame3 = 0.44, 本门禁的两张 = 0.22~0.40。
		var worst := 9.0
		var worst_i := -1
		for pair in [[arc_tex, VX.BATON_ARC_FRAMES], [stk_tex, VX.BATON_STRIKE_FRAMES]]:
			var img: Image = (pair[0] as Texture2D).get_image()
			var nfr: int = int(pair[1])
			var cw: int = int(img.get_width()) / nfr
			for f in range(nfr):
				var opaque := 0
				var bright := 0
				for x in range(f * cw, (f + 1) * cw):
					for y in range(img.get_height()):
						var cp: Color = img.get_pixel(x, y)
						if cp.a > 0.5:
							opaque += 1
							if maxf(cp.r, maxf(cp.g, cp.b)) >= 200.0 / 255.0:
								bright += 1
				if opaque > 0:
					var ratio: float = float(bright) / float(opaque)
					if ratio < worst:
						worst = ratio; worst_i = f
		_ok("⑦ ★★最差的一帧亮像素占比 %.2f(要 ≥ 0.15) —— 没有黑帧" % worst, worst >= 0.15,
			"第 %d 帧; electric-zap 的 frame4 是 0.00, 而就绪火花抽的是 randi()%%5" % worst_i)
		## b) 只有 4 色 + 零半透明像素 = 像素风(不是糊成一团的渐变球)
		var arc_img: Image = arc_tex.get_image()
		var cols := {}
		var semi := 0
		for x in range(arc_img.get_width()):
			for y in range(arc_img.get_height()):
				var c2: Color = arc_img.get_pixel(x, y)
				if c2.a > 0.5:
					cols[Color(c2.r, c2.g, c2.b).to_html(false)] = true
				elif c2.a > 0.0:
					semi += 1
		_ok("⑦ 跳弧只有 %d 色且半透明像素 %d 个(像素风: 硬边、不羽化)" % [cols.size(), semi],
			cols.size() <= 6 and semi == 0)

	## c) ★★★走真入口: 普攻触发那一下, 演出**真的被建出来**且**只罩被打中的那一个**
	##    (memory [[fb-zero-caller-is-a-whole-class]]: 门禁直接调函数 ≠ 游戏里走得到)
	_s._units.clear()
	_s._follow_vfx.clear()
	var c7: Dictionary = _mk(500.0, 400.0, "left")
	c7["equips"] = [{"id": "p2eq_027", "star": 3}]
	c7["eq_state"] = {}
	_s._units.append(c7)
	_s._equip_sys._stats._eq_apply_one_stats(c7, "p2eq_027", 3)
	var t7: Dictionary = _mk(700.0, 400.0, "right")
	var by7: Dictionary = _mk(760.0, 400.0, "right")     # 旁边站一个: 单体判定不该连它一起罩
	_s._units.append(t7)
	_s._units.append(by7)
	_ok("⑦ ★分母: 开打前跟随特效表是空的", _s._follow_vfx.is_empty(),
		"不空的话下面数出来的都是别人留下的")
	## ★按【真实帧步长】喂, 不要一口气喂 3.1 秒: 变就绪的那一 tick 走的是「还没就绪」那条分支,
	##   当帧不冒火花(下一帧才冒) —— 一次大步长喂进去数出来的 0 是**门禁自己的 0**。
	##   顺带这也验了它在 60fps 的真实步长下确实会冒(memory [[fb-axis-y-plus-rotation-cancels]]
	##   那条: 逐帧机制必须逐帧喂, 一次大 tick 会把取整误差抹掉 = 假绿灯)。
	for _f7 in range(200):                       # 200 × 1/60 = 3.33 秒 > 就绪 3.0 秒
		ets._tick_baton(c7, 1.0 / 60.0)
	var sparks: int = _s._follow_vfx.size()
	_ok("⑦ ★★就绪 tick 真的建出了跳弧(%d 个)" % sparks, sparks > 0,
		"一个都没有 ⇒ 就绪态在游戏里是**没有任何提示**的")
	_s._follow_vfx.clear()
	_s._equip_sys._eq_on_basic_attack(c7, t7)
	var strikes := 0
	var on_target := 0
	var wrong_filter := 0
	for f in _s._follow_vfx:
		var sp = f["spr"]
		if not is_instance_valid(sp):
			continue
		if sp.hframes == VX.BATON_STRIKE_FRAMES and str(sp.texture.resource_path) == VX.BATON_STRIKE_TEX:
			strikes += 1
			if is_same(f["unit"], t7):
				on_target += 1
			if sp.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
				wrong_filter += 1
	_ok("⑦ ★★★命中那一下落雷建出来了(%d 道)" % strikes, strikes == 1,
		"027 是**单体**判定 ⇒ 只该有一道; 0 道 = 演出根本没接上")
	_ok("⑦ ★★★落雷挂在【被打中的那一个】身上(%d/%d)" % [on_target, strikes],
		strikes > 0 and on_target == strikes,
		"挂错人 = 演出与判定对不上(用户原话: 演出得贴合实际伤害范围和判定)")
	_ok("⑦ ★★贴图过滤是 NEAREST(%d 个不是)" % wrong_filter, wrong_filter == 0,
		"Sprite3D 默认 texture_filter=3(LINEAR_WITH_MIPMAPS), 不显式写就糊")

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 23:
		print("  [FAIL] ★断言只有 %d 条(<23) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 027 电棍" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
