extends Node
## verify_heal_hot_readout.gd — 【持续回复】的演出与读数 (2026-09-14)
##
## 用户 2026-09-14 看 044 深海项链时连提两条:
##   ①「特效有做么, 就是这 6 秒的持续回复特效」
##   ②「信息栏最好是在这个 buff 触发后加一个倒计时条, 慢慢减到 0,
##      就一个横条在图标那里, **按照规则**」
##
## 原状(查过代码): 摊付结算在主场景 `_tick_unit` 里就两行 —— `if _t < eq_hot_until:
## _heal(rate*delta)`, **纯数字零演出、零读数**。`_heal_body_glow` 只是触发那一下
## 约 0.8 秒的脉动, 之后 5 秒多只有血条在悄悄涨。
##
## ★2026-09-14 用户「不要和地狱护盾共用了」⇒ 摊付从一个共享槽改成
##   `u["eq_hots"] = { 装备id: {rate, until, span} }`, **每件一条**, 各回各的。
## ★「规则」指 `equip_readouts.gd` 表头(用户 2026-08-08 定): 读数一律进装备图标框的
##   CHARGE / COUNT, 不许在演出层自造头顶条。所以判据落在 **CHARGE 表 + eq_state 里的
##   那个镜像字段**, 不是落在"我画了一根条"。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 期望值写死在门禁自己这儿, **不读被测常量**(读常量 = 恒真式)。
const EXP_NECK_SEC := 16.0        # 044 深海项链的摊付时长(用户 2026-09-14 两次上调: 6 → 8 → 16 秒)
const EXP_NECK_PCT := 1.30        # ★3 回复 130% 最大生命(用户 2026-09-14: 80 → 85 → 130%)
const EXP_BAR_FIELD := "hot_pct"  # 图标框那根条读的字段

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(px: float, py: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, Vector2(px, py))
	u["hp"] = 1000.0
	u["maxHp"] = 1000.0
	u["atk"] = 100.0
	u["alive"] = true
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	u["no_basic"] = true
	u["no_move"] = true
	return u


## 推游戏钟。★`_sim_step` 自己会推 `_t`, 但战斗判定结束(`_over`)后产品会把它冻住,
##   所以只在产品没推的时候补一步(无条件 `+=` 会双倍速)。
func _advance(sec: float) -> void:
	var steps: int = int(sec / _s.SIM_DT) + 1
	for _k in range(steps):
		var t0: float = _s._t
		_s._sim_step(_s.SIM_DT, false, false)
		if absf(_s._t - t0) < 1e-6:
			_s._t += _s.SIM_DT


## 逐帧互相关: 第 1 帧相对第 0 帧的最佳整数纵向位移(负 = 内容整体往上走)。
## ★对"稳态循环"的动画, 这是唯一量得出方向的尺子 —— 平均位置那种量法对它是瞎的。
func _best_shift(tex: Texture2D) -> int:
	var img: Image = tex.get_image()
	var n: int = 6
	var cell: int = int(img.get_width() / n)
	var h: int = img.get_height()
	var best_d: int = 0
	var best_s: int = -1
	for d in range(-9, 10):
		var sc: int = 0
		for y in range(h):
			var y2: int = y + d
			if y2 < 0 or y2 >= h:
				continue
			for x in range(cell):
				if img.get_pixel(x, y).a < 0.5:
					continue
				if img.get_pixel(cell + x, y2).a >= 0.5:
					sc += 1
		if sc > best_s:
			best_s = sc
			best_d = d
	return best_d

## 量一张精灵表里【亮点】的运动: mode="up" 返回 [首帧平均 y, 末帧平均 y];
## mode="in" 返回 [首帧平均半径, 末帧平均半径]。★量的是真图不是我写的注释。
func _motion(tex: Texture2D, mode: String) -> Array:
	var img: Image = tex.get_image()
	var n: int = 6
	var cell: int = int(img.get_width() / n)
	var cx: float = float(cell) / 2.0 - 0.5
	var out: Array = []
	for f in [0, n - 2]:                  # 末帧是循环回外圈那一帧, 取 n-2 才是一个周期内的终点
		var acc: float = 0.0
		var cnt: int = 0
		for y in range(img.get_height()):
			for x in range(cell):
				var c: Color = img.get_pixel(f * cell + x, y)
				if c.a < 0.78:
					continue
				if c.get_luminance() < 0.55:
					continue              # 只看亮点: 气泡的亮边 / 余烬的火星
				acc += float(y) if mode == "up" else sqrt(pow(float(x) - cx, 2.0) + pow((float(y) - cx) / 0.72, 2.0))
				cnt += 1
		out.append(acc / float(maxi(1, cnt)))
	return out

## 读某一件的摊付槽(新结构: 每件一条独立的 eq_hots[id])。
func _hot(u: Dictionary, iid: String, key: String) -> float:
	if not (u.get("eq_hots", null) is Dictionary):
		return 0.0
	return float((u["eq_hots"] as Dictionary).get(iid, {}).get(key, 0.0))

func _bar(u: Dictionary, iid: String) -> float:
	var st = u.get("eq_state", {})
	if not (st is Dictionary):
		return -999.0
	return float((st.get(iid, {}) as Dictionary).get(EXP_BAR_FIELD, -999.0))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 持续回复: 6 秒里有没有演出 + 图标框那根倒计时条 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false

	# ══════════════ ① 规则: 这件必须登记在【装备图标框】那张表里 ══════════════
	## ★这一条守的是"按照规则"本身 —— 读数不许自造头顶条, 只能走 CHARGE/COUNT。
	var ch = _s.PANEL_CHARGE
	_ok("① ★★★044 登记在 PANEL_CHARGE 里(条子在装备图标框, 不是自造的头顶条)",
		ch.has("p2eq_044") and str(ch["p2eq_044"][0]) == EXP_BAR_FIELD,
		"用户 2026-08-08 定的铁律, 写在 equip_readouts.gd 表头")
	_ok("① ★045 珍珠耳环同族, 也该有(它是 8 秒摊付)",
		ch.has("p2eq_045") and str(ch["p2eq_045"][0]) == EXP_BAR_FIELD)

	# ══════════════ ② 触发 → 条子满格 → 逐步减 → 到期抹零 ══════════════
	_s._units.clear()
	_s._pending_shots.clear()
	var c: Dictionary = _mk(500.0, 400.0, "left")
	c["equips"] = [{"id": "p2eq_044", "star": 3}]
	c["eq_state"] = {}
	_s._units.append(c)
	## ★★假人必须**打不动手**: 场上得有敌人在, `_check_end` 才不会把战斗判成结束、
	##   `_t` 才会走; 但它一还手, 携带者掉血又被 HOT 回上来 ⇒ 治疗账会**超过**上限空间
	##   (第一版量到 +1299 而上限只装得下 850, 判据当场红而产品是对的)。
	##   ⇒ 把噪声源直接掐掉(memory [[fb-make-the-noise-deterministic]]), 而不是去建模它。
	var dummy: Dictionary = _mk(900.0, 400.0, "right")
	dummy["stun_until"] = 1.0e9
	_s._units.append(dummy)
	_s._over = false
	_ok("② ★分母: 触发前条子字段还不存在(%.0f)" % _bar(c, "p2eq_044"),
		_bar(c, "p2eq_044") < -900.0, "一上来就有值的话下面那条证明不了是触发写的")

	## ★走**真实入口**: 把血压到线下, 由 `_eq_check_hp_threshold` 自己判定并触发,
	##   不直接调 `_eq_start_hot`(那样测的是我自己按了一下)。
	## ★压到 15% 而不是 40%: 回复量是 80% 最大生命, 从 40% 起算会**撞到生命上限被钳掉**
	##   ⇒ 实际只回 600 而不是 800, 而那是产品的正确行为、是我的判据没留够空间
	##   (第一版就这么红过一次)。15% + 80% = 95% < 100%, 装得下。
	## ★130% 回复量已经超过满血 ⇒ 无论从多低开始都必然撞上限。
	##   所以这一条改量**产品自己的治疗账**(`_st_heal`, 它明写"超过满血不计"),
	##   而判据也跟着改成"至少回满从当前血到满血这一段"。
	c["hp"] = float(c["maxHp"]) * 0.15
	_s._equip_sys._eq_check_hp_threshold(c)
	var hp_at_fire: float = float(c["hp"])
	var heal0: float = float(c.get("_st_heal", 0))
	_ok("② ★分母: 真实入口触发了(044 自己那条 until = %.2f)" % _hot(c, "p2eq_044", "until"),
		_hot(c, "p2eq_044", "until") > _s._t)
	_ok("② ★★★触发那一刻条子是满的(%.1f 应 100)" % _bar(c, "p2eq_044"),
		absf(_bar(c, "p2eq_044") - 100.0) < 0.5)

	_advance(EXP_NECK_SEC * 0.5)
	var mid: float = _bar(c, "p2eq_044")
	_ok("② ★★★推到一半时条子约在中间(%.1f 应 ≈50)" % mid, absf(mid - 50.0) < 12.0,
		"它是【倒计时】条: 从满格慢慢减到 0, 不是从 0 涨")

	_advance(EXP_NECK_SEC * 0.6)
	_ok("② ★★★到期后条子抹成 0(%.1f)" % _bar(c, "p2eq_044"),
		absf(_bar(c, "p2eq_044")) < 0.01,
		"★镜像必须**无条件**每帧写 —— 只在「还在回血」时写的话, 条子会停在最后一格不动")

	## 顺带确认摊付确实把血喂回来了(条子对了但没回血 = 读数骗人)。
	## ★★量的是产品自己的**治疗账** `_st_heal`(注释写着"实际回复, 超过满血不计"),
	##   **不是血量净变化** —— 第一版量净变化, 探针实测血从 150 涨到 906 之后
	##   又被场上那只假人打回 606, 判据于是读成"只回了 422", 而产品完全正确。
	##   memory [[fb-make-the-noise-deterministic]]: 别量世界净变化, 要量被测那件事的账。
	var healed: float = float(c.get("_st_heal", 0)) - heal0
	## 130% 会溢出满血, `_st_heal` 明写"超过满血不计" ⇒ 期望值取【请求量】与【能装下的量】的小者。
	var cap_room: float = float(c["maxHp"]) - hp_at_fire
	var want_heal: float = minf(float(c["maxHp"]) * EXP_NECK_PCT, cap_room)
	_ok("② ★分母: 这 %.0f 秒真的回了血(+%.0f, 应 ≈ %.0f; 请求 %.0f%% 最大生命, 上限只装得下 %.0f)"
		% [EXP_NECK_SEC, healed, want_heal, EXP_NECK_PCT * 100.0, cap_room],
		absf(healed - want_heal) < maxf(2.0, want_heal * 0.05),
		"★双向判据: 少算多算都红。2026-09-14 抓到的就是**少算** —— 累计写的是 int(hp-hb), "
		+ "而持续回复每帧只回 1.77 点 ⇒ int() 截成 1 ⇒ 结算面板的治疗列少算 43.5%(850 记成 480)")

	# ══════════════ ③ 6 秒里身上有没有演出 ══════════════
	_s._units.clear()
	_s._pending_shots.clear()
	var c2: Dictionary = _mk(500.0, 400.0, "left")
	c2["equips"] = [{"id": "p2eq_044", "star": 3}]
	c2["eq_state"] = {}
	_s._units.append(c2)
	_s._units.append(_mk(900.0, 400.0, "right"))
	_s._over = false
	c2["hp"] = float(c2["maxHp"]) * 0.4
	_s._equip_sys._eq_check_hp_threshold(c2)
	var before: int = _s._world.get_child_count()
	## ★走**真入口** `_render._tick_heal_hot()` —— 它就是游戏里每帧扫的那一个,
	##   不是我另写一个创建函数再断言"函数存在"(memory fb-verify-must-run-the-real-path)。
	_s._render._tick_heal_hot()
	_ok("③ ★★★摊付期间身上真的挂出了演出(`_world` 新增 %d 个节点)"
		% (_s._world.get_child_count() - before),
		_s._world.get_child_count() > before,
		"原来这 6 秒是纯数字零演出")
	_ok("③ ★分母: 演出句柄记在单位身上(续时间靠 eq_hot_until, 不另起第二条钟)",
		is_instance_valid(c2.get("_heal_hot_spr_p2eq_044", null)))
	var once: int = _s._world.get_child_count()
	_s._render._tick_heal_hot()
	_ok("③ ★★再扫一遍不许重复创建(%d → %d)" % [once, _s._world.get_child_count()],
		_s._world.get_child_count() == once,
		"每帧扫一次的机制, 不去重就会每帧堆一个精灵")

	## ★★到期自销走的是 `_follow_vfx` 的 `until_key` 分支 —— 那条也要验,
	##   否则气泡会一直挂在身上(「写了没人清」的镜像)。
	c2["eq_hots"] = {}
	c2["eq_hot_until_p2eq_044"] = 0.0
	_s._render._tick_follow_vfx()
	await get_tree().process_frame
	_ok("③ ★★★到期后气泡自己收掉(句柄已清)",
		not is_instance_valid(c2.get("_heal_hot_spr_p2eq_044", null)),
		"until_key 到点自销, 不用谁去手动删")

	# ══════════════ ④ 044 与 045 的持续演出不许重复 ══════════════
	## 用户 2026-09-14:「045 也需要做个回复 buff 持续特效, **不要和之前上一个重复**」。
	## ★★判据落在**真的不一样**上, 不是"我换了个文件名":
	##   ① 两件解析到的贴图必须是不同的资源;
	##   ② 逐帧量亮点的运动方向 —— 044 气泡**向上**(y 递减), 045 余烬**向内**(半径递减)。
	##   只比文件名的话, 把 045 指向 044 那张照样绿。
	var pb: String = str(_s._vfx.HHOT_TEX)
	var pe: String = str(_s._vfx.HHOT_BY_OWNER.get("p2eq_045", ""))
	_ok("④ ★分母: 045 在按持有者换素材的表里登记了(%s)" % pe, pe != "" and pe != pb)
	var tb = load(pb)
	var te = load(pe) if pe != "" else null
	_ok("④ ★分母: 两张贴图都载得进来", tb != null and te != null)
	if tb != null and te != null:
		## ★★气泡是**稳态循环**(升到顶破掉、底下补新的), 所以"所有亮点的平均 y"几乎不动 ——
		##   第一版就是这么量的, 读出 28.9 → 28.4 当场红, 而图是对的。
		##   换成**逐帧互相关**: 第 f+1 帧跟第 f 帧【往上平移多少】最吻合。
		var dy: int = _best_shift(tb)
		var me: Array = _motion(te, "in")
		_ok("④ ★★★044 的气泡逐帧**往上**走(最佳匹配位移 dy=%d, 负=向上)" % dy, dy < 0,
			"气泡从脚下升到头顶破掉 —— 这是「水」那一套")
		_ok("④ ★★★045 的亮点逐帧**向内**收(六帧平均半径 %.1f → %.1f)" % [float(me[0]), float(me[1])],
			float(me[1]) < float(me[0]) - 1.5,
			"余烬从四周收进身体 —— 这是「火/吸收」那一套, 与 044 的方向正交")

	# ══════════════ ⑤ 同时带 044 + 045: 两条摊付各走各的, 不许互相吞掉 ══════════════
	## 用户 2026-09-14:「不要和地狱护盾共用了」。
	## ★原来两件共用一个槽, 而 `_eq_start_hot` 的注释白纸黑字写着
	##   「两件同时触发时**取总量更大的那一段**」⇒ 按新数值 044(1.30×maxHp) 会把
	##   045(1.00×maxHp) **整个吞掉, 一声不响**。这条判据就是钉住它不许再发生。
	_s._units.clear()
	_s._pending_shots.clear()
	var c3: Dictionary = _mk(500.0, 400.0, "left")
	c3["equips"] = [{"id": "p2eq_044", "star": 3}, {"id": "p2eq_045", "star": 3}]
	c3["eq_state"] = {}
	_s._units.append(c3)
	var d3: Dictionary = _mk(900.0, 400.0, "right")
	d3["stun_until"] = 1.0e9
	_s._units.append(d3)
	_s._over = false
	c3["hp"] = float(c3["maxHp"]) * 0.15
	_s._equip_sys._eq_check_hp_threshold(c3)
	var n44: float = _hot(c3, "p2eq_044", "rate")
	var n45: float = _hot(c3, "p2eq_045", "rate")
	_ok("⑤ ★★★两件各自有一条摊付(044 速率 %.1f/秒 · 045 速率 %.1f/秒)" % [n44, n45],
		n44 > 0.0 and n45 > 0.0,
		"共用一个槽时, 总量小的那件会被**静默丢掉**")
	_ok("⑤ ★★两条的时长不同 ⇒ 确实是两条(044 %.0f 秒 / 045 %.0f 秒)"
		% [_hot(c3, "p2eq_044", "span"), _hot(c3, "p2eq_045", "span")],
		absf(_hot(c3, "p2eq_044", "span") - _hot(c3, "p2eq_045", "span")) > 1.0)
	_ok("⑤ ★★★两件各有自己的倒计时条(044 %.0f%% · 045 %.0f%%)"
		% [_bar(c3, "p2eq_044"), _bar(c3, "p2eq_045")],
		absf(_bar(c3, "p2eq_044") - 100.0) < 0.5 and absf(_bar(c3, "p2eq_045") - 100.0) < 0.5)
	var sp0: int = _s._world.get_child_count()
	_s._render._tick_heal_hot()
	_ok("⑤ ★★两件各挂各的演出(新增 %d 个节点, 应 ≥2)" % (_s._world.get_child_count() - sp0),
		_s._world.get_child_count() - sp0 >= 2,
		"一件气泡一件余烬, 各演各的")

	print("---- %d 条, 失败 %d ----" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS — 持续回复的演出与读数")
	else:
		print("有 %d 条 FAIL" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
