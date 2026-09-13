extends Node
## verify_ice_vial.gd — 028 冰霜冻露瓶的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 「每 IceSystem.VIAL_IV 秒短暂蓄力, 抛出一个冰瓶砸向**最近的**敌人,
##   命中造成 **40/60/100 魔法伤害**并**将其击退**,
##   同时施加冰寒 IceSystem.VIAL_CHILL_SEC 秒(移动速度 -20%、攻击速度 -10%)。」
##
## ★★这一件**原来既没有台子也没有门禁**, 而且**两层延时都挂在 tween 上**:
##   ① `_eq_ice_throw` 的 0.32 秒前摇 `tween_interval`
##   ② `_ice_throw_go` 的 0.6 秒飞行 `tween_method` + 末尾 `tween_callback(_ice_bottle_hit)`
##   tween 走**未钳制的真实 delta, 无头下推不动**(CLAUDE.md §3.5)
##   ⇒ **瓶子根本不出手, 伤害/冰寒/击退一个都不落**。
##   与 024/025/026/029 同一条病, 现在统一走共享原语 `EquipTickSystem.schedule`。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ICE := preload("res://scripts/systems/skills/ice_system.gd")

const DMG := [40, 60, 100]

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
	u["atk_interval"] = 9999.0   # 关掉普攻这个噪声源
	u["atk_cd"] = 9999.0
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 028 冰霜冻露瓶: 每 %.0f 秒抛冰瓶 ===" % ICE.VIAL_IV)
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	## DEBUG_EDIT ⇒ _edit_mode 置真 ⇒ _fight_on 把整组 tick 门住(024 那轮栽过)
	_s._edit_mode = false
	var ets = _s._equip_tick_sys

	# ── ① ★分母: 文案里那几个数在代码里是这些 ──────────────────────
	_ok("① ★分母: 周期 %.0f 秒 / 冰寒 %.0f 秒 / 移速 -%.0f%% / 攻速 -%.0f%%"
		% [ICE.VIAL_IV, ICE.VIAL_CHILL_SEC, ICE.VIAL_MOVE_DOWN * 100.0, ICE.VIAL_ASPD_DOWN * 100.0],
		ICE.VIAL_IV > 0.0 and ICE.VIAL_CHILL_SEC > 0.0
			and absf(ICE.VIAL_MOVE_DOWN - 0.20) < 0.001 and absf(ICE.VIAL_ASPD_DOWN - 0.10) < 0.001)

	# ── ② ★★★走真入口: 推 sim 之后瓶子**真的砸到人** ────────────────
	## 这一条就是这次要修的那件事。改之前它恒为 0。
	_s._units.clear()
	ets._bolt_q.clear()
	var c: Dictionary = _mk(500.0, 400.0, "left")
	var foe: Dictionary = _mk(700.0, 400.0, "right")
	foe["mr"] = 0.0
	_s._units.append(c)
	_s._units.append(foe)
	var hp0: float = float(foe["hp"])
	_s._equip_sys._eq_ice_throw(c, 2)
	_ok("② ★分母: 刚放完还没结算(掉血 %.0f 应为 0)" % (hp0 - float(foe["hp"])),
		absf(hp0 - float(foe["hp"])) < 0.01,
		"前摇 %.2f + 飞行 %.2f 秒都还没走完" % [ICE.VIAL_WINDUP, ICE.VIAL_FLY_SEC])
	## 推够 前摇 + 飞行 + 余量; 用 _sim_step 确定性推, 不看帧率脸色
	for _k in range(150):        # 150 / 60 = 2.5 游戏秒 > 0.32 + 0.6
		_s._sim_step(_s.SIM_DT, false, false)
	var dealt: float = hp0 - float(foe["hp"])
	_ok("② ★★★推 sim 之后目标**确实掉血了**(实得 %.0f)" % dealt, dealt > 0.0,
		"若为 0: 前摇与飞行都埋在 tween 里而 tween 无头下推不动 —— 就是 §3.5 那条老病")
	_ok("② 共享延时队列已排空(没有漏结算的项)", ets._bolt_q.is_empty(),
		"剩 %d 项" % ets._bolt_q.size())

	# ── ③ ★★冰寒: 移速 ×0.8 / 攻速 ×0.9 / 持续 5 秒 ──────────────────
	_ok("③ ★★移速倍率 %.2f(应 %.2f)" % [float(foe.get("spd_move_mult", -1.0)), ICE.VIAL_MOVE_MULT],
		absf(float(foe.get("spd_move_mult", -1.0)) - ICE.VIAL_MOVE_MULT) < 0.001)
	_ok("③ ★★攻速倍率 %.2f(应 %.2f)" % [float(foe.get("spd_aspd_mult", -1.0)), ICE.VIAL_ASPD_MULT],
		absf(float(foe.get("spd_aspd_mult", -1.0)) - ICE.VIAL_ASPD_MULT) < 0.001)
	var left: float = float(foe.get("spd_dbf_until", 0.0)) - _s._t
	_ok("③ ★★冰寒还剩 %.2f 秒(应 ≤ %.0f 且 > 0)" % [left, ICE.VIAL_CHILL_SEC],
		left > 0.0 and left <= ICE.VIAL_CHILL_SEC + 0.01)

	# ── ④ ★★★击退: 文案写了「将其击退」, 代码必须真的把人推开 ─────────
	## ★不断言绝对位移: `_knockback` 会把目标抛起来(airborne), 落点由物理推。
	##   判据落在**对细节不敏感**的形状: 它被抛起来了 / 或离携带者更远了。
	_s._units.clear()
	ets._bolt_q.clear()
	var c4: Dictionary = _mk(500.0, 400.0, "left")
	var f4: Dictionary = _mk(700.0, 400.0, "right")
	f4["mr"] = 0.0
	_s._units.append(c4)
	_s._units.append(f4)
	var d0: float = (f4["pos"] as Vector2).distance_to(c4["pos"] as Vector2)
	_s._ice_sys._ice_bottle_hit(null, c4, f4, 2)
	var d1: float = (f4["pos"] as Vector2).distance_to(c4["pos"] as Vector2)
	_ok("④ ★★★被击退了(离携带者 %.1f → %.1f 码, 或被抛起 airborne=%s)"
		% [d0, d1, str(f4.get("airborne", false))],
		d1 > d0 + 0.5 or bool(f4.get("airborne", false)),
		"文案明写「并将其击退」")

	# ── ⑤ 伤害吃星级, 且是魔法伤害(吃魔抗) ───────────────────────────
	## ★不断言绝对数值: 携带者 id="basic" 走小龟·不屈(+20%), 那是产品本来的行为。
	_s._units.clear()
	ets._bolt_q.clear()
	var c5: Dictionary = _mk(500.0, 400.0, "left")
	_s._units.append(c5)
	var got: Array = []
	for si in [0, 1, 2]:
		var o: Dictionary = _mk(700.0 + 60.0 * si, 400.0, "right")
		o["mr"] = 0.0
		o["_knock_immune"] = true        # 免击飞: 位移会干扰后面的距离判据, 这一节只量伤害
		_s._units.append(o)
		var h: float = float(o["hp"])
		_s._ice_sys._ice_bottle_hit(null, c5, o, si)
		got.append(h - float(o["hp"]))
	_ok("⑤ ★分母: 三个星级都掉血了(%.0f / %.0f / %.0f)" % [got[0], got[1], got[2]],
		got[0] > 0.0 and got[1] > 0.0 and got[2] > 0.0)
	_ok("⑤ ★★伤害吃星级且比例对得上 40:60:100(实测 %.0f:%.0f:%.0f)"
		% [got[0], got[1], got[2]],
		absf(float(got[1]) / float(got[0]) - float(DMG[1]) / float(DMG[0])) < 0.05
			and absf(float(got[2]) / float(got[0]) - float(DMG[2]) / float(DMG[0])) < 0.05)
	var hard: Dictionary = _mk(900.0, 400.0, "right")
	hard["mr"] = 500.0
	hard["_knock_immune"] = true
	_s._units.append(hard)
	var hh: float = float(hard["hp"])
	_s._ice_sys._ice_bottle_hit(null, c5, hard, 2)
	var dh: float = hh - float(hard["hp"])
	_ok("⑤ ★★魔抗 500 吃得明显少 ⇒ 是【魔法伤害】(软 %.0f vs 硬 %.0f)" % [got[2], dh],
		dh < float(got[2]) * 0.5)

	# ── ⑥ ★★选靶是【最近的】敌人, 不是随便一个 ───────────────────────
	_s._units.clear()
	ets._bolt_q.clear()
	var c6: Dictionary = _mk(500.0, 400.0, "left")
	var near: Dictionary = _mk(600.0, 400.0, "right")
	var far: Dictionary = _mk(1100.0, 400.0, "right")
	near["mr"] = 0.0
	far["mr"] = 0.0
	_s._units.append(c6)
	_s._units.append(near)
	_s._units.append(far)
	var hn: float = float(near["hp"])
	var hf: float = float(far["hp"])
	_s._equip_sys._eq_ice_throw(c6, 2)
	for _k in range(150):
		_s._sim_step(_s.SIM_DT, false, false)
	var dn: float = hn - float(near["hp"])
	var df: float = hf - float(far["hp"])
	_ok("⑥ ★★砸的是【最近的】那个(近 %.0f / 远 %.0f)" % [dn, df], dn > 0.0 and df <= 0.0,
		"文案明写「砸向最近的敌人」")

	# ── ⑦ ★★★演出层: 霜要看得出是霜, 冰寒要看得出还在生效 ────────────
	## 为什么这一节必须存在(memory [[fb-weld-visual-lessons-into-gate]]):
	##   ① `_frost_puff` 原来用 `VfxTex._make_fire_glow_tex()`(程序生成光球),
	##      实拍量出来是一团 **144×100 屏幕像素、亮度中位 41** 的暗斑, 而龟才 45 像素高
	##      ⇒ 3.2 个龟宽的一坨暗色油污糊在地上, 读不出"霜"。
	##   ② 文案写的「冰寒 5 秒」是个**持续状态**, 而画面上从砸中到结束**零提示**。
	var VX = load("res://scripts/scenes/battle/battle_vfx.gd")
	var IC = load("res://scripts/systems/skills/ice_system.gd")
	var mist_tex: Texture2D = load(IC.FROST_MIST_TEX)
	var chill_tex: Texture2D = load(VX.CHILL_TEX)
	_ok("⑦ ★分母: 两张霜素材都 import 得出来", mist_tex != null and chill_tex != null,
		"换了 png 不 --import 的话 load 返回 null, 游戏里直接看不见")
	if mist_tex != null and chill_tex != null:
		## a) 逐帧量【亮像素占不透明像素的比例】—— 卡死"这一帧在黑场里看不见"那条老病
		var worst := 9.0
		for pair in [[mist_tex, IC.FROST_MIST_FRAMES], [chill_tex, VX.CHILL_FRAMES]]:
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
					worst = minf(worst, float(bright) / float(opaque))
		_ok("⑦ ★★最差的一帧亮像素占比 %.2f(要 ≥ 0.15) —— 没有黑帧" % worst, worst >= 0.15)

	## b) ★★★走真入口: 砸中之后**真的**挂上霜雾, 而且它是【帧表】不是程序生成的球
	_s._units.clear()
	_s._anim_fx.clear()
	var c7: Dictionary = _mk(500.0, 400.0, "left")
	var t7: Dictionary = _mk(700.0, 400.0, "right")
	_s._units.append(c7)
	_s._units.append(t7)
	_ok("⑦ ★分母: 砸中之前定格特效表是空的", _s._anim_fx.is_empty())
	_s._ice_sys._ice_bottle_hit(null, c7, t7, 2)
	var mists := 0
	var bad_filter := 0
	for f in _s._anim_fx:
		var sp = f["spr"]
		if not is_instance_valid(sp):
			continue
		if str(sp.texture.resource_path) == IC.FROST_MIST_TEX:
			mists += 1
			if sp.hframes != IC.FROST_MIST_FRAMES:
				bad_filter += 1
			if sp.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
				bad_filter += 1
	_ok("⑦ ★★★砸中之后霜雾真的建出来了(%d 团)" % mists, mists == 1,
		"0 团 = 演出没接上; 它必须是 frost-mist.png 这张【帧表】, 不是程序生成的光球")
	_ok("⑦ ★★霜雾是 %d 帧的帧表且 NEAREST(违规 %d 处)" % [IC.FROST_MIST_FRAMES, bad_filter],
		bad_filter == 0,
		"Sprite3D 默认 texture_filter=3(LINEAR_WITH_MIPMAPS), 不显式写就糊")

	## c) ★★★冰寒【持续期】身上真的有标记, 且它是状态的函数(不是 028 自己接的线)
	_s._follow_vfx.clear()
	t7.erase("_chill_spr")
	_ok("⑦ ★分母: 清表之后跟随特效是空的", _s._follow_vfx.is_empty())
	## ★★★走**真入口** `_render_step` —— 不是直调 `_tick_chill_mark()`。
	##   反向验证当场抓到: 直调的话, 把那一行从渲染 tick 群里**整行删掉**门禁照样绿
	##   ⇒ 守的是"函数存在"而不是"游戏里走得到"(memory [[fb-verify-must-run-the-real-path]])。
	_s._render._render_step(1.0 / 60.0, false, false)
	var marks := 0
	var on_chilled := 0
	for f in _s._follow_vfx:
		var sp2 = f["spr"]
		if not is_instance_valid(sp2):
			continue
		if str(sp2.texture.resource_path) == VX.CHILL_TEX:
			marks += 1
			if is_same(f["unit"], t7):
				on_chilled += 1
	_ok("⑦ ★★★冰寒期间身上挂了霜标记(%d 个, 其中 %d 个在被冻的那个身上)" % [marks, on_chilled],
		marks == 1 and on_chilled == 1,
		"文案写的「冰寒 5 秒」是个持续状态, 画面上必须读得出来")
	## ★不是「028 调了一下」而是「状态的函数」: 手写一个 spd_dbf_until 到【没被瓶子砸过】的人身上,
	##   它也必须自动带标记 —— 这一条守住的是"以后任何减速来源都自动有提示"。
	_s._follow_vfx.clear()
	var third: Dictionary = _mk(860.0, 400.0, "right")
	_s._units.append(third)
	third["spd_dbf_until"] = _s._t + 3.0
	_s._render._render_step(1.0 / 60.0, false, false)
	var third_marked := false
	for f in _s._follow_vfx:
		if is_same(f["unit"], third):
			third_marked = true
	_ok("⑦ ★★★换个来源写 spd_dbf_until 也自动带标记(不是 028 自己接的线)", third_marked,
		"判据挂在【状态字段】上 ⇒ 以后任何减速来源都自动有提示")

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 19:
		print("  [FAIL] ★断言只有 %d 条(<19) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 028 冰霜冻露瓶" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
