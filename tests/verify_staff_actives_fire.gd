extends Node
## verify_staff_actives_fire.gd — 十件法器的主动【真的会响吗】(2026-08-13)
##
## ★由来: 2026-08-12/13 我们把这批法器的触发口全改成"法力条满"(v0.19.127~133),
##   改完**一个门禁都没有**。95 件装备里 22 件零门禁, 其中 6 件正是这批刚改过的法器。
##   这与凤凰那个洞是同一类风险: **改了触发口, 没人验消费者**。
##
## ★判据是【产品状态变了没有】, 不是我插的标记:
##   ① 法力条真的走到满并清零(`stt["mana"]` 回 0) —— 证明 `_fire` 跑到了
##   ② 世界真的发生了变化(敌人掉血 / 排了弹道 / 中了控 / 叠了 DoT / 自己得了盾)
##   ★★只验 ① 守不住 —— 清零发生在调 `fire_equip_effect` 之【前】,
##     那件装备的分支哪怕是空的, 条也照样清零。必须两条都验。
##
## 跑法: <godot> --headless --path . res://tests/verify_staff_actives_fire.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const StaffSyn := preload("res://scripts/systems/equip/staff_synergy_system.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

## 效果埋在 `_reg_tween()` 链里的法器 —— 无头下 tween 不推进(CLAUDE.md §3.5),
## 本门禁只能验到"法力条走到满并清零", 验不到效果本身。
## ★登记在这里而不是注释里, 是为了让【名单变化】能把门禁弄红(见文件末那条断言)。
## ★根治办法是把结算从演出里抽出来(同 3.5 里海盗钩索那次): 留给后续。
## ★★2026-08-14 解掉: 031 的主动已由 `verify_staff_active_isolated` 用【同窗隔离】验起来
##   (同一场战斗两组都带 031, 只一组灌满法力 ⇒ 差值就是主动; 反向验证打瘸后归零)。
##   这里保留空名单 + 断言, 是为了【名单一旦回涨就红】—— 谁再把某件的伤害埋回 tween,
##   这条会逼他回来看。空名单不是"没这回事", 是"这条缺口已经关上了"。
const TWEEN_BURIED := ["p2eq_031"]

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 世界状态快照 —— 用来判"这件法器到底有没有做出任何事"。
## ★宽口径是故意的: 十件法器做的事各不相同(直伤/控/盾/DoT/弹道), 用一把尺子量不了;
##   但"什么都没发生"是可以统一判的, 而那正是我们要抓的失败形态。
func _snap(s, u: Dictionary, es: Array) -> Array:
	var hp := 0.0
	var dots := 0
	var stun := 0.0
	for e in es:
		hp += float(e.get("hp", 0.0))
		for k in (e.get("dot_stacks", {}) as Dictionary).keys():
			dots += int((e["dot_stacks"] as Dictionary)[k])
		stun += float(e.get("stun_until", 0.0))
	## ★★判据【只看单位身上的实际状态】, 不看 `_projectiles` / `_pending_shots` 的队列长度。
	##   2026-08-14: 我一度把这两个队列长度也算进"世界变了" —— 而等真实帧之后场景自己的
	##   `_process` 会让队列自然涨落 ⇒ 023 把主动改成 `pass` 反向验证**照样绿**。
	##   队列长度是"有东西在飞", 不是"打到了谁"。判据要落在被打的人身上。
	return [hp, dots, stun, float(u.get("shield", 0.0)) + float(u.get("hp", 0.0))]


func _changed(a: Array, b: Array) -> bool:
	for i in range(a.size()):
		if absf(float(a[i]) - float(b[i])) > 0.001:
			return true
	return false


func _ready() -> void:
	await get_tree().process_frame
	print("=== 法器主动: 法力满 → 真的响了吗 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5

	# 全表法器 —— 从类型表取, 不手抄名单(手抄的副本必然落后)
	## ★名单从 `data/p2eq-types.json` 现读 —— 手抄的副本必然落后。
	##   ⚠ 不要用 `Phase2Types.TYPES`(那是【羁绊档位阈值表】不是装备→类型映射),
	##     我第一版拿错了表, 取到 0 件 —— 而"全部通过"在 0 件时照样绿, 靠分母断言才抓到。
	var staffs: Array = []
	var _mf := FileAccess.open("res://data/p2eq-types.json", FileAccess.READ)
	var _mp = JSON.parse_string(_mf.get_as_text()) if _mf != null else null
	if _mp is Dictionary:
		for iid in (_mp as Dictionary).keys():
			var v = (_mp as Dictionary)[iid]
			var vs: Array = v if v is Array else [v]
			for t in vs:
				if str(t) == "法器":
					staffs.append(str(iid))
					break
	staffs.sort()
	_ok("★分母: 从类型表取到法器 %d 件(不是手抄名单)" % staffs.size(), staffs.size() >= 10,
		"实得 %d 件: %s" % [staffs.size(), str(staffs)])

	var dead: Array = []
	for iid in staffs:
		var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 0))
		u["atk"] = 120.0
		u["maxHp"] = 5000.0
		u["hp"] = 5000.0
		var es: Array = []
		for i in range(3):
			var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(100.0 + 70.0 * float(i), 0))
			e["maxHp"] = 1.0e7
			e["hp"] = 1.0e7
			es.append(e)
		## ★★把【普通战斗静音】—— 否则那 90 帧里双方本来就在互相普攻,
		##   敌人掉血跟法器毫无关系, 判据被战斗本身喂饱 ⇒ 门禁恒绿。
		##   实测: 第一版没静音, 我把 011/029 的主动改成 `pass` 反向验证, **照样全绿**。
		##   这正是"假门禁"的样子 —— 只有反向验证能发现。
		u["no_basic"] = true
		u["no_move"] = true
		for e0 in es:
			(e0 as Dictionary)["no_basic"] = true
			(e0 as Dictionary)["no_move"] = true
		s._units.clear()
		s._units.append(u)
		s._units.append_array(es)
		s._edit_mode = false
		s._over = false
		u["equips"] = [{"id": iid, "star": 3}]
		u["eq_state"] = {iid: {}}
		s._equip_sys._stats._eq_apply_all_stats()

		var full: float = s._staff_syn.mana_full_for(u, iid, 3)
		## ★★【对照组】先不灌法力, 同样推 90 帧, 量一遍"什么都不做时世界会自己变多少"。
		##   2026-08-14 血泪: 等真实帧之后场景自己的 `_process` 会让状态漂移
		##   ⇒ 023 把主动改成 `pass` 反向验证**照样绿**(两次都判"变了")。
		##   有了对照组, 判据就变成"灌满法力带来的变化 ≠ 什么都不做时的变化" —— 这才是隔离。
		##   ⚠ 对照期必须【冻住法力】: 自然增长是每 2.5 秒 +MANA_PER_TICK, 90 帧里
		##     它自己就能把条攒满并触发(实测 6 件在对照期 `条余 0.0` = 真的放了)。
		##     用产品自己的防连放闸 `_staff_busy` —— `add_mana` 开头就 return, 不另造机关。
		u["_staff_busy"] = true
		var ctl0: Array = _snap(s, u, es)
		for _cf in range(90):
			s._sim_step(1.0 / 60.0, false, false)
			if _cf % 3 == 0:
				await get_tree().process_frame
		var ctl_moved: bool = _changed(ctl0, _snap(s, u, es))
		u["_staff_busy"] = false
		var before: Array = _snap(s, u, es)
		## ★走【真入口】add_mana —— 不直接调 fire_equip_effect。
		##   直接调等于绕过"法力条满才触发"这条链, 而那条链正是这次要验的东西。
		s._staff_syn.add_mana(u, full + 1.0)
		## 推进时间让延后结算落地。★★必须【等真实帧】而不是纯同步调 `_sim_step`:
		##   023 灼热火珊瑚走的是 `await battle._wait_sim(0.4)` + `await process_frame`
		##   的**协程**, 同步循环里真实帧一帧都没过 ⇒ 协程永远不恢复 ⇒ 我一度把它误判成
		##   "效果埋在 tween 里量不到"。分类错了, 判据自然也就错了。
		for _f in range(90):
			s._sim_step(1.0 / 60.0, false, false)
			if _f % 3 == 0:
				await get_tree().process_frame
		var after: Array = _snap(s, u, es)
		var mana_left: float = float((u["eq_state"].get(iid, {}) as Dictionary).get("mana", -1.0))
		var fired: bool = mana_left >= 0.0 and mana_left < full
		var did: bool = _changed(before, after)
		if iid in TWEEN_BURIED:
			## ★这几件的伤害埋在 `_reg_tween()` 链的末尾(026 见 RealtimeBattle3DScene:8312,
			##   030/031 见 _eq_crystal_line/_eq_crystal_sweep) —— **tween 在无头下推不动**
			##   (CLAUDE.md §3.5), 所以本门禁量不到它们的效果。
			##   ⚠ 这是【测试侧量不到】, 不是"装备是死件" —— 两者结论完全相反, 不许混为一谈。
			##   只验"条走到满并清零"(= `_fire` 真的被调到了), 效果本身留作已知缺口。
			_ok("%s: 法力满→条清零(效果埋在 tween 里, 无头量不到 —— 已知缺口)" % iid, fired,
				"条余 %.1f/%.1f" % [mana_left, full])
			continue
		## ★对照组也在变 ⇒ 这一件身上有【持续性被动】(023 灼烧场 / 029 冰封 /
		##   088·089·090 的常驻物), 宽判据分不开"主动放了"与"被动一直在跑"。
		##   ⇒ 只能验到"条走到满并清零"(= `_fire` 真被调到)。**诚实登记成缺口**,
		##     不许静默当通过 —— 023 一度就是这么假绿的(主动改成 pass 照样绿)。
		##   ★根治要给这几件各写一条**专属判据**(量它主动特有的产物), 留作后续。
		## ★★"对照组也在漂移"这条出口 2026-08-14 起【只是降级说明】, 不再是缺口 ——
		##   023/029/089/090 的主动已由 `verify_staff_active_isolated` 用同窗隔离单独验过。
		##   这里保留是因为本条的宽判据确实分不开, 但那 4 件在另一条门禁里是有真断言的。
		if ctl_moved:
			_ok("%s: 法力满→条清零(★有持续被动, 宽判据隔离不了主动 —— 已知缺口)" % iid, fired,
				"条余 %.1f/%.1f" % [mana_left, full])
			continue
		if not (fired and did):
			dead.append("%s(条清了=%s 世界变了=%s)" % [iid, str(fired), str(did)])
		_ok("%s: 法力满→条清零 且【世界真的变了】(对照组不动)" % iid, fired and did,
			"条余 %.1f/%.1f · 变化=%s" % [mana_left, full, str(did)])

	_ok("★★可同步验的法器【全部】都能被法力条触发出实际效果(死件 %d 件)" % dead.size(),
		dead.is_empty(), "死件: %s" % str(dead))
	## ★★把缺口【焊成断言】而不是写在注释里: 名单一旦变化(有人把某件改成 tween 埋伤害,
	##   或者把某件从 tween 里抽出来了)这条就红, 逼人回来看。静默的缺口 = 假的覆盖率。
	var still: Array = []
	for iid2 in staffs:
		if iid2 in TWEEN_BURIED:
			still.append(iid2)
	_ok("★★【本条】量不到的仍是 %d 件(031 的主动已由 verify_staff_active_isolated 同窗隔离验过)"
			% TWEEN_BURIED.size(),
		still == TWEEN_BURIED,
		"实得 %s / 登记 %s" % [str(still), str(TWEEN_BURIED)])

	# 反面: 法力【没满】就不该触发 —— 否则上面全绿也可能只是"什么都会响"
	var u2: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 0))
	u2["atk"] = 120.0
	var e2: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(150, 0))
	e2["maxHp"] = 1.0e7
	e2["hp"] = 1.0e7
	s._units.clear()
	s._units.append_array([u2, e2])
	u2["equips"] = [{"id": "p2eq_026", "star": 3}]
	u2["eq_state"] = {"p2eq_026": {}}
	var full2: float = s._staff_syn.mana_full_for(u2, "p2eq_026", 3)
	var b2: Array = _snap(s, u2, [e2])
	s._staff_syn.add_mana(u2, full2 * 0.5)      # 只灌一半
	## ★反面判定【不推帧】—— 推帧本身就会让世界变化(单位移动/普攻),
	##   而且法器自然增长(每 2.5 秒 +MANA_PER_TICK)会把条从半满继续往上推。
	##   我第一版推了 60 帧, 两条反面同时假红(条 100 → 115)。
	##   "半满不触发"本来就是**同步**的事实, 灌完立刻判即可。
	_ok("★反面: 法力只到一半 ⇒ 什么都不该发生", not _changed(b2, _snap(s, u2, [e2])))
	_ok("★反面: 条也不该清零(还在攒)",
		absf(float((u2["eq_state"]["p2eq_026"] as Dictionary).get("mana", -1.0)) - full2 * 0.5) < 0.01,
		"条余 %.1f(应 %.1f)" % [float((u2["eq_state"]["p2eq_026"] as Dictionary).get("mana", -1.0)), full2 * 0.5])

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 法器主动全部会响")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
