extends Node
## 斧头【演出】门禁 (2026-09-03)
##
## ══════════════════════════════════════════════════════════════════
##  ★这个文件要守住的是什么
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-03:「斧头特效要全部补齐且不能敷衍」
##
## 「不敷衍」没法靠我说了算, 所以判据落在**可量的东西**上:
##   ① 蓄力梯形的四个角**必须恰好在判定边界上** —— 演出即判定, 逐码对齐。
##      这条最重要: 它把"画个大概"和"画的就是判定区"分开了。
##   ② 八张招式帧**真的被换上去**(读产品自己的 `_axe_last_action`, 不是我插的计数)。
##   ③ 梯形在所有退出路径上都被收掉(蓄力中斧头死 = 最容易漏的那条)。
##
## ★★不做什么: 不断言"建了几个节点"。节点数是实现细节, 改个做法就红,
##   而且它证明不了"玩家看得见" —— memory [[fb-zero-caller-is-a-whole-class]]
##   里 64 条门禁全绿而环与光从没被创建, 就是断言挑错了对象。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const APV := preload("res://scripts/scenes/battle/axe_passive_vfx.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(msg: String, cond: bool, extra: String = "") -> void:
	_n += 1
	if cond:
		print("  [OK] %s" % msg)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [msg, extra])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true          # ★绝不写玩家存档
	print("=== 斧头演出: 梯形对齐 / 招式帧 / 收尾 ===")

	# ══════════════════════════════════════════════════════════════
	#  ① 纯几何: 梯形演出的角点 = 判定边界 (不建场, 直接算)
	# ══════════════════════════════════════════════════════════════
	print("── ① 演出即判定: 梯形四角逐码对齐 ──")
	var tested := 0
	for step in range(1, int(AE.CHARGE_TIME / AE.CHARGE_STEP) + 1):
		var h: float = float(step) * AE.CHARGE_H_PER_STEP
		var cs: Array = APV.field_corners(h)
		if cs.size() != 4:
			_ok("h=%.0f 有四个角" % h, false, "拿到 %d 个" % cs.size())
			continue
		tested += 1
		var org := Vector2(0, 0)
		var dir := Vector2(1, 0)
		## 角点稍稍**往里** ⇒ 判定必须说"在里面"; 稍稍**往外** ⇒ 必须说"不在"。
		## ★两侧各验一次 —— memory [[fb-judge-must-fit-the-shape]]: 只验一侧,
		##   宽一格和窄一格都发现不了。
		for c in cs:
			var p: Vector2 = c
			var inward: Vector2 = (Vector2(h * 0.5, 0.0) - p).normalized() * 2.0
			var pin: Vector2 = p + inward
			var pout: Vector2 = p - inward
			if not AE.in_trapezoid(org, dir, h, pin):
				_ok("h=%.0f 角(%.0f,%.0f) 往里 2 码应在判定内" % [h, p.x, p.y], false)
			if AE.in_trapezoid(org, dir, h, pout):
				_ok("h=%.0f 角(%.0f,%.0f) 往外 2 码应在判定外" % [h, p.x, p.y], false)
	_ok("★分母: 逐格验了 %d 种蓄力高度(应 = %d 格)" % [tested, int(AE.CHARGE_TIME / AE.CHARGE_STEP)],
		tested == int(AE.CHARGE_TIME / AE.CHARGE_STEP), "为 0 = 空检查")
	_ok("① 八格梯形的角点全部恰好卡在判定边界上(往里在内/往外在外)", _fail == 0,
		"已 FAIL %d 条" % _fail)

	## ★半宽必须按【满蓄高】插值而不是当前高 —— 这是判定那边注释点名的坑。
	## 反向说法: 若演出按当前高插值, 那么 h=100 时远边半宽会等于 900/2=450(满宽),
	## 而判定只给 lerp(300,900,100/800)/2 = 187.5。拿这两个数直接比。
	var w_far_at_100: float = APV.half_w_at(100.0)
	var wrong_if_by_h: float = AE.TRAPEZOID_FAR_W * 0.5
	_ok("② 半宽按满蓄高插值(h=100 时半宽 %.1f, 不是按当前高的 %.1f)"
		% [w_far_at_100, wrong_if_by_h], absf(w_far_at_100 - wrong_if_by_h) > 1.0,
		"两者相等 = 演出会比判定胖")
	_ok("★分母: h=100 的半宽是真算出来的(非 0)", w_far_at_100 > 0.0)

	# ══════════════════════════════════════════════════════════════
	#  ② 真建场: 招式帧真的换上去了
	# ══════════════════════════════════════════════════════════════
	print("── ② 招式帧: 读产品自己的 _axe_last_action ──")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var owner_u: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-200, 0))
	_s._units.append(owner_u)
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	foe["maxHp"] = 1.0e8
	foe["hp"] = 1.0e8
	_s._units.append(foe)

	var ax = _s._equip_sys._axe.summon(owner_u)
	_ok("★分母: 真召唤出斧头", ax is Dictionary and ax.get("alive", false))
	if not (ax is Dictionary):
		_done()
		return

	## 逐档验: 把 `_axe_pv` 直接钉在召唤物上(产品就是这么存的, 见 axe_system.summon),
	## 然后走**真入口** `on_hit` —— 不是直接调 play_action
	## (memory [[fb-verify-must-run-the-real-path]]: 目视确认过零调用者的死函数)。
	var cases := [
		{"pv": 3, "swing_parity": 1, "want": "axe_sweep", "name": "金斧·奇数拳 → 横扫"},
		{"pv": 3, "swing_parity": 0, "want": "axe_cleave", "name": "铁斧·偶数拳 → 竖劈"},
	]
	for cs2 in cases:
		ax["_axe_pv"] = int(cs2["pv"])
		ax["_axe_swing"] = (0 if int(cs2["swing_parity"]) == 1 else 1)   # 下一拳的奇偶
		ax["_axe_smash_ready"] = false                                    # 别让强化砸抢镜
		ax.erase("_axe_last_action")
		_s._equip_sys._axe.on_hit(ax, foe, true)
		_ok("③ %s (实测 %s)" % [str(cs2["name"]), str(ax.get("_axe_last_action", "(没播)"))],
			str(ax.get("_axe_last_action", "")) == str(cs2["want"]))

	## 强化猛砸【优先级】: 同一拳既满足竖劈又满足强化砸时, 必须播 smash。
	## ★这条是接线时想到的真实风险: 连着 _set_anim_sheet 两次, 后一张顶掉前一张,
	##   表现成"强化猛砸永远看不见"而伤害照常结算 —— 屏幕上分辨不出来。
	ax["_axe_pv"] = 4
	ax["_axe_swing"] = 1                 # 下一拳是第 2 拳 = 偶数 = 竖劈
	ax["_axe_smash_ready"] = true        # 同时强化砸也就绪
	ax.erase("_axe_last_action")
	_s._equip_sys._axe.on_hit(ax, foe, true)
	_ok("④ 强化砸与竖劈撞在同一拳 → 播稀有的那个(smash)",
		str(ax.get("_axe_last_action", "")) == "axe_smash",
		"实测 %s" % str(ax.get("_axe_last_action", "(没播)")))

	# ══════════════════════════════════════════════════════════════
	#  ②b 五张新素材: 存在 / 规格 / **真的被建成节点**
	# ══════════════════════════════════════════════════════════════
	## ★「素材在盘上」证明不了「玩家看得见」—— 斧头那 8 张动作帧就是躺了两天零调用者
	##   (memory [[fb-zero-caller-is-a-whole-class]])。所以三层都要验:
	##   ① 文件在  ② 是 9 帧的 sheet 不是单图  ③ 走真入口后 _world 里真多了节点。
	print("── ②b 五张特效素材 ──")
	var sheets := {
		"cleave": APV.TEX_CLEAVE, "sweep": APV.TEX_SWEEP, "smash": APV.TEX_SMASH,
		"slam": APV.TEX_SLAM, "heal": APV.TEX_HEAL,
	}
	for k in sheets:
		var path: String = str(sheets[k])
		var ex: bool = ResourceLoader.exists(path)
		_ok("素材在盘上: %s" % k, ex, path)
		if not ex:
			continue
		var tex: Texture2D = load(path)
		var fh: int = maxi(1, tex.get_height())
		var nf: int = int(tex.get_width() / fh)
		## ★用户 2026-08-29:「不要拿图片贴图敷衍我, 我要动画像素特效」⇒ 单帧不算数。
		_ok("%s 是多帧动画(%d 帧, 单帧=敷衍)" % [k, nf], nf >= 4, "%dx%d" % [tex.get_width(), fh])

	var pvfx = _s._equip_sys._axe._pas.vfx
	var before: int = _s._world.get_child_count()
	var made := {
		"cleave": pvfx.cleave(ax, foe),
		"sweep": pvfx.sweep(ax, Vector2.RIGHT),
		"smash": pvfx.smash(foe),
		"slam": pvfx.slam(ax, Vector2.RIGHT, 400.0),
		"heal": pvfx.heal(ax),
	}
	for k in made:
		_ok("④b %s 真的建出了节点并挂进 _world" % k,
			made[k] != null and is_instance_valid(made[k]) and (made[k] as Node).is_inside_tree(),
			"拿到 null / 没进树 = 玩家看不见")
	_ok("★分母: _world 子节点从 %d 涨到 %d(涨了 %d 个)"
		% [before, _s._world.get_child_count(), _s._world.get_child_count() - before],
		_s._world.get_child_count() > before, "没涨 = 上面五条是空检查")

	## ★横扫的直径必须 = 判定直径(atk_range × 2)。这条是"演出即判定"在横扫上的具体含义:
	##   画大了玩家以为扫得到却没伤害, 画小了反过来。拿 pixel_size × 单帧宽 反推真实码数。
	var sw_node = made["sweep"]
	if sw_node != null and is_instance_valid(sw_node):
		var sp := sw_node as Sprite3D
		var fh2: float = maxf(1.0, float(sp.texture.get_height()))
		var real_px: float = sp.pixel_size * fh2 / _s.WS       # 反推回场地码
		var want: float = float(ax.get("atk_range", 120.0)) * 2.0
		_ok("⑤b 横扫直径 %.0f 码 = 判定直径 %.0f 码(atk_range×2)" % [real_px, want],
			absf(real_px - want) < 1.0, "差 %.1f 码 = 演出与判定不等" % absf(real_px - want))

	# ══════════════════════════════════════════════════════════════
	#  ③ 梯形在所有退出路径上都收掉
	# ══════════════════════════════════════════════════════════════
	print("── ③ 收尾: 蓄力中斧头死掉, 地上不许留亮区 ──")
	ax["_axe_pv"] = 4
	ax["alive"] = true
	ax.erase("_axe_charge_t0")
	var began: bool = _s._equip_sys._axe._pas.begin_charge(ax)
	_ok("★分母: 真进了蓄力", began and ax.has("_axe_charge_t0"))
	_ok("⑤ 蓄力一开始就有梯形场", ax.get("_axe_field", null) != null)
	var fld = ax.get("_axe_field", null)
	## 模拟"蓄力中被打死": 产品走 tick_charge → not alive → _end_charge
	ax["alive"] = false
	_s._equip_sys._axe._pas.tick_charge(ax, 0.1)
	_ok("⑥ 斧头死在蓄力中 → 梯形被收掉(字段清空)", not ax.has("_axe_field"))
	## ★`queue_free()` 是**延迟**释放 —— 同一帧断言 is_instance_valid 必然还是 true,
	##   那是判据错不是产品错(第一版就这么红的)。等一帧再判。
	## ★这不会把判据放松成恒真: 如果根本没调 queue_free, 等多少帧它都还活着。
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("⑦ 梯形节点真的被 free 了(不是只清了字段)",
		fld == null or not is_instance_valid(fld),
		"节点还活着 = 地上留了一块永久亮区")

	_done()


func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
		get_tree().quit(0)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
		get_tree().quit(1)
