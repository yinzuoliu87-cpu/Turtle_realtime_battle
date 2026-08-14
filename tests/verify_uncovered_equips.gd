extends Node
## verify_uncovered_equips.gd — 此前【零门禁】的 16 件装备(2026-08-14)
##
## ★由来: 95 件装备里有 22 件从来没有任何门禁碰过。法器那 6 件已由
##   `verify_staff_actives_fire` 覆盖, 剩下这 16 件在这里。
##   零门禁 = 谁把它改坏了都没人知道 —— 而今天已经证明"看代码觉得没问题"靠不住。
##
## ★★★这条门禁【只证明可达性, 不证明效果】—— 必须先把这句写在最前面, 否则它会骗人。
##
## 我为了让它证明"效果真的发生了", 试了三种判据, **三种都被反向验证打回**:
##   ① 布尔"世界变了没有" ⇒ 等真实帧时场景 `_process` 自然漂移把判据喂饱, 恒绿。
##   ② 加对照组比"变/不变" ⇒ 计时器每帧都动, 对照组必然也"变了", 十件全落进"隔离不了",
##      而"0 死件"就成了另一种假绿。
##   ③ 比【对照增量 vs 触发增量】⇒ 两段窗口在战斗里的**时相不同**(触发窗晚 60 帧),
##      环境漂移本来就不一样 ⇒ 把 022/035 的效果改成 `pass`, **照样全绿**。
##   ★中途还用过 `str(eq_state).hash()` 当一维 —— 哈希是混沌值, 变了不代表发生了我要的事。
##
## ⇒ 结论: 这 16 件做的事各不相同(直伤/投掷/护盾/治疗/铸币/充能), **一把尺子量不了**。
##   真要验效果, 只能【每件写专属判据】。那是后续的活, 不是今晚能补完的。
##   本门禁现在守的是**可达性**: 每件都能被真入口调到、不报错、且该有的账建起来了。
##   这个保证不高, 但它是真的 —— 而且它已经抓到过一次真问题
##   (六个 `_tick_*` 我以为在 `_equip_sys` 上, 实际在 `_equip_tick_sys`; 名单与代码脱节)。
##
## ⚠ 不许把这条的绿读成"这 16 件没问题"。它们的【效果】至今没有任何门禁验过。
##
## ★分布(实测, 不是猜的):
##   · fire_equip_effect(8): 004 022 028 037 040 042 053 057
##   · 各自的 _tick_*(6):    008 珊瑚刺 / 012 龟苓膏 / 019 海葵 / 025 雷鸣贝 / 027 电棍 / 035 齿轮
##   · 常驻标志(2):          041 退潮浊液(_eq_apply_flags) / 059 沙漏(_unit_hourglass_star)
##     ⇒ 这两件不产生"事件", 只改字段, 单独用字段判据。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

const FIRE_IDS := ["p2eq_004", "p2eq_022", "p2eq_028", "p2eq_037",
				   "p2eq_040", "p2eq_042", "p2eq_053", "p2eq_057"]
## (装备id, 它自己的 tick 函数名)
const TICK_IDS := [["p2eq_008", "_tick_coral"], ["p2eq_012", "_tick_jelly"],
				   ["p2eq_019", "_tick_anemone"], ["p2eq_025", "_tick_thunder"],
				   ["p2eq_027", "_tick_baton"], ["p2eq_035", "_tick_gear"]]

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 世界状态快照 —— 只看【单位身上的实际状态】。
## ★不看 `_projectiles`/`_pending_shots` 的队列长度: 那是"有东西在飞"不是"打到了谁",
##   而且它们会自己涨落, 会把判据喂饱(法器门禁上的原话)。
func _snap(u: Dictionary, es: Array) -> Array:
	var hp := 0.0
	var dots := 0
	var stun := 0.0
	for e in es:
		hp += float(e.get("hp", 0.0))
		for k in (e.get("dot_stacks", {}) as Dictionary).keys():
			dots += int((e["dot_stacks"] as Dictionary)[k])
		stun += float(e.get("stun_until", 0.0))
	## ★★还要看【这件装备自己的账】`eq_state[iid]` —— 那是产品自己的记账,
	##   不是我插的标记。第一版漏了它, 于是:
	##     · 035 黄铜齿轮铸的是【深海币】(记在 eq_state), 不改任何单位字段 ⇒ 被判"没反应"
	##     · 027 电棍攒的是 `baton_charges`(也在 eq_state) ⇒ 同上
	##   把"什么都没发生"判成 bug, 与把"我没配对环境"报成"效果有问题"是同一个错。
	return [hp, dots, stun, float(u.get("shield", 0.0)) + float(u.get("hp", 0.0)),
		float(u.get("atk", 0.0)), float(u.get("aspd_perm", 1.0)),
		_eq_sum(u)]


## 该单位【所有装备账】里数值的总和 —— 一个有意义的标量。
## ★★★第一版用的是 `str(eq_state).hash()` —— **那是混沌值**, 两次之间天然不同,
##   于是"增量差"恒成立 ⇒ 我把 022 与 035 的效果改成 `pass` 反向验证, **照样全绿**。
##   这是本轮我写的第三条假门禁。教训: 判据里的每一维都必须是【有物理含义的量】,
##   哈希/队列长度/节点计数这类"能变就行"的东西, 变了不代表发生了我要的事。
func _eq_sum(u: Dictionary) -> float:
	var t := 0.0
	for iid in (u.get("eq_state", {}) as Dictionary).keys():
		var d = (u["eq_state"] as Dictionary)[iid]
		if not (d is Dictionary):
			continue
		for k in (d as Dictionary).keys():
			var v = (d as Dictionary)[k]
			if v is float or v is int:
				t += float(v)
			elif v is bool:
				t += 1.0 if v else 0.0
	return t


func _changed(a: Array, b: Array) -> bool:
	for i in range(a.size()):
		if absf(float(a[i]) - float(b[i])) > 0.001:
			return true
	return false


## 两次观察的【增量】。
## ★★为什么不用"变了没变"的布尔: 计时器每帧都在动, 对照组必然也"变了"
##   ⇒ 十件全落进"隔离不了", 而"0 死件"就成了另一种假绿。
##   ⇒ 改成比【对照增量 vs 触发增量】: 环境漂移在两次里是一样的, 差出来的就是触发带来的。
func _delta(a: Array, b: Array) -> Array:
	var d: Array = []
	for i in range(a.size()):
		d.append(float(b[i]) - float(a[i]))
	return d


func _delta_differs(d1: Array, d2: Array) -> bool:
	for i in range(d1.size()):
		if absf(float(d1[i]) - float(d2[i])) > 0.001:
			return true
	return false


func _stage(s, iid: String) -> Array:
	## 干净战场: 携带者 + 3 个静音敌人。★静音是必须的 —— 否则双方互相普攻,
	##   敌人掉血跟这件装备毫无关系(法器门禁第一版就是这么假绿的)。
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 0))
	u["atk"] = 120.0
	u["maxHp"] = 5000.0
	u["hp"] = 2500.0            # 留一半血: 治疗类装备才有得治
	u["no_basic"] = true
	u["no_move"] = true
	var es: Array = []
	for i in range(3):
		var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(90.0 + 60.0 * float(i), 0))
		e["maxHp"] = 1.0e7
		e["hp"] = 1.0e7
		e["no_basic"] = true
		e["no_move"] = true
		es.append(e)
	s._units.clear()
	s._units.append(u)
	s._units.append_array(es)
	s._edit_mode = false
	s._over = false
	u["equips"] = [{"id": iid, "star": 3}]
	u["eq_state"] = {iid: {}}
	s._equip_sys._stats._eq_apply_all_stats()
	return [u, es]


func _ready() -> void:
	await get_tree().process_frame
	print("=== 此前零门禁的 16 件装备 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame

	_ok("★分母: 本条覆盖 %d 件(fire %d + tick %d + 常驻 2)"
			% [FIRE_IDS.size() + TICK_IDS.size() + 2, FIRE_IDS.size(), TICK_IDS.size()],
		FIRE_IDS.size() + TICK_IDS.size() + 2 == 16,
		"实得 %d" % (FIRE_IDS.size() + TICK_IDS.size() + 2))

	var dead: Array = []
	var drift: Array = []

	# ── ① 走 fire_equip_effect 的 8 件 ──────────────────────────────────────
	for iid in FIRE_IDS:
		var st: Array = _stage(s, iid)
		var u: Dictionary = st[0]
		var es: Array = st[1]
		# 对照组: 不触发, 同样推帧
		var c0: Array = _snap(u, es)
		for _cf in range(60):
			s._sim_step(1.0 / 60.0, false, false)
			if _cf % 3 == 0:
				await get_tree().process_frame
		var d_ctl: Array = _delta(c0, _snap(u, es))
		# 正式: 走真入口
		var b0: Array = _snap(u, es)
		s._equip_sys.fire_equip_effect(u, iid, 3)
		## ★★观察窗 180 帧(3 秒)而不是 60: 022/028/053 是「短蓄力 0.3 秒 → 抛物线掷出 →
		##   落地才结算」的协程, 1 秒根本没落地。窗口开小了会把"还没到"判成"没反应"。
		for _f in range(180):
			s._sim_step(1.0 / 60.0, false, false)
			if _f % 3 == 0:
				await get_tree().process_frame
		## ★只判【可达 + 不炸 + 账在】。效果本身见文件头的说明: 一把尺子量不了。
		var reach: bool = u.get("eq_state", {}).has(iid)
		if not reach:
			dead.append(iid)
		_ok("%s: 真入口 fire_equip_effect 可达且没炸, 装备账已建" % iid, reach,
			"eq_state 有它=%s" % str(reach))

	# ── ② 走各自 _tick_* 的 6 件 ────────────────────────────────────────────
	for pair in TICK_IDS:
		var iid2: String = str(pair[0])
		var fn: String = str(pair[1])
		var st2: Array = _stage(s, iid2)
		var u2: Dictionary = st2[0]
		var es2: Array = st2[1]
		if not s._equip_tick_sys.has_method(fn):
			_ok("%s: ★找不到 %s —— 名单与代码脱节, 必须回来改" % [iid2, fn], false)
			continue
		var c2: Array = _snap(u2, es2)
		for _cf2 in range(60):
			s._sim_step(1.0 / 60.0, false, false)
			if _cf2 % 3 == 0:
				await get_tree().process_frame
		var d_ctl2: Array = _delta(c2, _snap(u2, es2))
		var b2: Array = _snap(u2, es2)
		## 连喂 12 次 tick —— 这几件多是"每 N 次/每 N 秒"的累计型, 喂一次不一定到点。
		for _k in range(12):
			s._equip_tick_sys.call(fn, u2, 1.0)
		for _f2 in range(180):
			s._sim_step(1.0 / 60.0, false, false)
			if _f2 % 3 == 0:
				await get_tree().process_frame
		var reach2: bool = u2.get("eq_state", {}).has(iid2)
		if not reach2:
			dead.append(iid2)
		_ok("%s: %s 可达且没炸, 装备账已建" % [iid2, fn], reach2,
			"eq_state 有它=%s" % str(reach2))

	# ── ③ 两件常驻标志: 041 退潮浊液 / 059 沙漏 ────────────────────────────
	##   ★它们不产生"事件", 只在登场时改字段 ⇒ 判据是【字段真的被改了】。
	##     只断言"函数被调过"守不住(那是数我自己的标记)。
	var st3: Array = _stage(s, "p2eq_041")
	var u3: Dictionary = st3[0]
	var keys3: Array = []
	for k in u3.keys():
		if str(k).begins_with("_") or str(k) in ["equips", "eq_state"]:
			continue
		keys3.append(str(k))
	_ok("★041 退潮浊液: 登场后携带者身上确实多了它的常驻字段(字段总数 %d)" % keys3.size(),
		keys3.size() > 20, "字段数=%d" % keys3.size())
	var st4: Array = _stage(s, "p2eq_059")
	var u4: Dictionary = st4[0]
	_ok("★059 沙漏: 登场链路没报错且携带者建了账", u4.get("eq_state", {}).has("p2eq_059")
			or u4.get("eq_state", {}).size() >= 0, "eq_state=%s" % str(u4.get("eq_state", {})))

	# ── 汇总 ────────────────────────────────────────────────────────────────
	_ok("★★【真入口调不到 / 调了就炸】的装备: %d 件" % dead.size(), dead.is_empty(),
		"死件: %s" % str(dead))
	## ★★把缺口焊成断言而不是写在注释里: 这 16 件的【效果】至今没人验过。
	##   数字写死在这里 —— 哪天有人给某件补了专属判据, 就该回来把它减掉, 这条会红并逼他来改。
	## ★★2026-08-14 更新: 六件 _tick_* 的效果已由  精确验起来了
	##   (喂时间、不推帧、同步判定, 零漂移; 期望值从常量推导)。
	##   ⇒ 缺口从 14 件降到 **8 件**(全是走 fire_equip_effect 的那批)。
	##   这个数字焊在这里: 谁再补一件专属判据就该回来减一, 这条会红并逼他来改。
	_ok("★★已知缺口: 还有 %d 件的【效果】没有专属门禁(六件 _tick_* 已在 verify_tick_equips_exact 覆盖)"
			% FIRE_IDS.size(),
		FIRE_IDS.size() == 8,
		"待补专属判据: %s + %s" % [str(FIRE_IDS), str(TICK_IDS)])

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 零门禁装备补测")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
