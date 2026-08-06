class_name IncenseStoneSystem
extends RefCounted
## incense_stone_system.gd — 093 香火石(遗物 · 2 费) 的效果本体　【主会话独占, agent 不要动】
##
## 规格 = `docs/plans/20260805-装备逐件重做.md` §0.5「★093 香火石」, 用户 2026-08-06 亲手设计。
##
## ══════════════════════════════════════════════════════════════════════
##  它是全表唯一【跨对局养成】的装备 —— 状态分两半, 存法完全不同
## ══════════════════════════════════════════════════════════════════════
## · **刻痕数** = 队伍级 + 赛季级。存 `GameState.incense_marks`, 随 `start_new_season()` 清零。
##   用户原话「如果卖掉了就丢失这 20」——**只有充能会丢**, 已投进羁绊的刻痕不退
##   ⇒ 它与某一件石头的存亡无关, 所以不能存在装备实例上。
## · **充能条**(0~4000) = 每件装备实例自己的。存在装备 dict 的 `chg` 字段里, 跨对局保留;
##   卖掉丢失; 升星时三件相加。收口在 `GameState.mk_eq` / `GameState.eq_chg`。
##
## ⚠ 装备 dict 在本项目里被【重建】的点一共 **10 处**(GameState 8 处 + 主场景注入 2 处),
##   每一处都写死 `{"id":…, "star":…}`、额外字段直接丢。**漏一处 = 充能静默清零, 不报错**。
##   全链路门禁 `tests/verify_incense_stone.gd` 把它焊死: 买→装→进战斗→攒→升星→存档→读档→卖。
##
## ══════════════════════════════════════════════════════════════════════
##  ★规格没写死、由我定的地方(交付要求: 选了哪一侧 / 为什么 / 另一侧是什么)
## ══════════════════════════════════════════════════════════════════════
## D1【携带者的增伤是 0.2% 还是 0.3% 每刻痕】→ **0.3%**(装备 0.2% + 羁绊 0.1%)。
##    用户原文:「每道痕使香火石这件装备额外提供 0.2% 增伤和 0.1% 减伤, **此外**独特羁绊使
##    **全队**获得 0.1% 增伤 + 0.05% 减伤」——「此外」+「全队」⇒ 携带者两份都吃。
##    另一侧是"携带者只吃 0.2%"(把羁绊那份排除携带者), 但那样"全队"二字就不成立。
##    ⚠ **量级提醒**: 按字面读, 满 300 刻痕时携带者是 **+90% 增伤 / +45% 减伤**, 全队 +30%/+15%。
##       我之前给用户的量级表写的是携带者 +60%/+30%(只算了装备那一份)—— 那个数偏低, 已在交付报告里更正。
##
## D2【同一只龟装 2 件香火石】→ 装备那一份 **只给一次**(不叠), 但**两件各自攒充能**。
##    另一侧是"装备那份也翻倍"。选前者: 与全表通用口径「多件同带取星级更高的那一件」一致
##    (082/084/071 都是这么定的); 而"各自攒充能"是用户明说的(「多个香火石…各自攒」)。
##    ⚠ 实现限制(诚实记录): `eq_state` 是按 **item id** 存的, 同一只龟上的两件共用一个槽
##    ⇒ 同龟两件实际上是**共用一条充能条**。要真正各攒需要把 eq_state 改成按槽位存,
##    那是全 95 件装备的公共结构改动, 不在本批范围。**不同龟各带一件是各攒各的**(常见情形)。
##
## D3【敌方(right)的刻痕】→ **每场从 0 开始**, 不读也不写存档。
##    另一侧是给 bot 也造一份赛季存档。选前者: bot 对手是即时生成的(见 `scripts/net/backend.gd`),
##    没有"这个 bot 上赛季带过这块石头"这回事; 硬给它一个数字只会变成凭空的难度旋钮。
##
## D4【充能写回存档的时机】→ **每刻成一道痕时** + **换路/撤场时**。
##    另一侧是每帧写回。选前者: 每帧写回要遍历 persistent_equipped 找那一件, 是热路径上的浪费;
##    崩溃时最多丢不到一道痕(<4000 伤害)的进度。
##
## D5【强化普攻的 +100% 攻速什么时候撤】→ **4 次用完立刻撤**, 不设时限。
##    规格原文「强化自己的下 4 次普攻, 使下四次普攻获得 100% 攻速」⇒ 是"这 4 次"的属性,
##    不是"一段时间"。另一侧是给个固定窗口(如 3 秒), 但那样打不完 4 次就白给。

## ★逐星三元数组【就近声明】在 "p2eq_093" 字面量旁边:
##   tooltip_number_audit 靠 id 字面量 ±2500 字符判"这个数组是不是这件的",
##   提到别处会被判【远处命中】直接红。
const EID := "p2eq_093"
## 刻一道痕需要的伤害(用户原文 4000) 与 刻痕上限(用户原文 300)
const PER_MARK := 4000
const MARK_CAP := 300
## 每道刻痕: 装备给携带者 +0.2% 增伤 / +0.1% 减伤; 独特羁绊给全队 +0.1% / +0.05%
const ITEM_AMP := 0.002
const ITEM_DR := 0.001
const TEAM_AMP := 0.001
const TEAM_DR := 0.0005
## 主动: 每 12 秒强化下 4 次普攻(用户原文)
const EMP_IV := 12.0
const EMP_SHOTS := 4
## 强化期间 +100% 攻速 与 10% 生命偷取(用户原文)
const EMP_ASPD := 1.0
const EMP_LS := 0.10

var battle
## 本场刻痕池(按 side)。left 与 GameState.incense_marks 同步, right 每场从 0 起(D3)。
var _marks: Dictionary = {"left": 0, "right": 0}
## 已经施加给某单位的本件贡献 —— 撤回时要按这个减, 不能凭空减(同 038 信号放大器 signal_amp 的做法)
var _given: Array = []   # [{u, amp, dr}]


func _init(b) -> void:
	battle = b


func _side_of(u: Dictionary) -> String:
	var sd := str(u.get("side", ""))
	return sd if (sd == "left" or sd == "right") else "left"


## 本方当前刻痕数。
func marks_of(side: String) -> int:
	return int(_marks.get(side, 0))


# ══════════════════════════════════════════════════════════════════
#  登场: 从存档把刻痕与充能读进来, 并施加刻痕带来的增伤/减伤
# ══════════════════════════════════════════════════════════════════
func on_spawn(u: Dictionary, eid: String, _si: int) -> void:
	if eid != EID:
		return
	var side := _side_of(u)
	if side == "left" and GameState != null:
		_marks["left"] = clampi(int(GameState.incense_marks), 0, MARK_CAP)
	var stt: Dictionary = u["eq_state"].get(EID, {})
	# 充能条: 从装备实例带进来的 `chg`(跨对局保留)。同龟多件共用一个槽, 见 D2。
	var chg := 0
	for e in u.get("equips", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == EID:
			chg = maxi(chg, int((e as Dictionary).get("chg", 0)))
	stt["chg"] = chg
	# ★伤害计数用现成的 `_st_dealt`(两条伤害路径都在记, battle_damage.gd:52/185/211) 做【增量】基准。
	#   不另起一套计数: 另起一套就要在两条路各插一次, 那是 §3.3 的十次机会漏一次。
	stt["dealt0"] = int(u.get("_st_dealt", 0))
	stt["emp_t"] = 0.0
	stt["emp"] = 0
	u["eq_state"][EID] = stt
	_reapply(side)


# ══════════════════════════════════════════════════════════════════
#  每帧: 攒充能 → 刻痕; 主动计时 → 强化下 4 次普攻
# ══════════════════════════════════════════════════════════════════
func tick_unit(u: Dictionary, delta: float) -> void:
	if not u.get("alive", false):
		return
	var stt = u.get("eq_state", {}).get(EID, null)
	if not (stt is Dictionary) or not stt.has("dealt0"):
		return
	var side := _side_of(u)

	# ① 攒香火: 携带者造成的伤害增量进充能条
	var now: int = int(u.get("_st_dealt", 0))
	var d: int = now - int(stt["dealt0"])
	if d > 0:
		stt["dealt0"] = now
		if int(_marks.get(side, 0)) < MARK_CAP:
			stt["chg"] = int(stt.get("chg", 0)) + d
			while int(stt["chg"]) >= PER_MARK and int(_marks.get(side, 0)) < MARK_CAP:
				stt["chg"] = int(stt["chg"]) - PER_MARK
				_marks[side] = int(_marks.get(side, 0)) + 1
				_on_mark_scored(u, side)
			# ★★钳一次: 上面这个 while 可能是【在循环中途撞到 300 上限】退出的,
			#   那时 chg 还剩一大截(实测灌 500 道的量时是 816000)。不钳就会显示成
			#   "充能条 816000/4000" —— 而且一旦上限以后被调高, 这堆存量会瞬间全变成刻痕。
			if int(_marks.get(side, 0)) >= MARK_CAP:
				stt["chg"] = PER_MARK
		else:
			# ★进 tick 时就已经满 300: 不再消耗充能, 条冻结显示满(方案书 R4 的定论)
			stt["chg"] = PER_MARK

	# ② 主动: 每 12 秒强化下 4 次普攻。★自管累加器, 不读 battle._t(它跨路累加永不重置·§3.4)
	stt["emp_t"] = float(stt.get("emp_t", 0.0)) + delta
	if float(stt["emp_t"]) >= EMP_IV:
		stt["emp_t"] = float(stt["emp_t"]) - EMP_IV
		if int(stt.get("emp", 0)) <= 0:
			stt["emp"] = EMP_SHOTS
			_set_emp_haste(u, true)
			if battle._incense_vfx != null:
				battle._incense_vfx.empower_burst(u)


## 刻成一道痕: 重算全队加成、写回存档、放演出。
func _on_mark_scored(u: Dictionary, side: String) -> void:
	if side == "left" and GameState != null:
		GameState.incense_marks = int(_marks["left"])
	_persist_chg(u)
	_reapply(side)
	if battle._incense_vfx != null:
		battle._incense_vfx.mark_carved(u, int(_marks.get(side, 0)))


# ══════════════════════════════════════════════════════════════════
#  普攻: 消耗一次强化 —— 附带伤害 + 生命偷取
# ══════════════════════════════════════════════════════════════════
func on_basic(u: Dictionary, tgt, eid: String, si: int) -> void:
	if eid != EID or tgt == null or not (tgt is Dictionary) or not tgt.get("alive", false):
		return
	var stt = u.get("eq_state", {}).get(EID, null)
	if not (stt is Dictionary) or int(stt.get("emp", 0)) <= 0:
		return
	stt["emp"] = int(stt["emp"]) - 1
	if int(stt["emp"]) <= 0:
		_set_emp_haste(u, false)   # D5: 4 次用完立刻撤, 不设时限
	# 附带 30/50/80 + 目标最大生命 1/1.5/2% 的【物理】伤害(用户 2026-08-06「可以分星」后的定稿)
	# ★这两行旁边必须有一个 "p2eq_093" 字面量: tooltip_number_audit 靠 id 字面量 ±2500 字符
	#   判"这个数组是不是这件的"。文件顶部那个 `const EID` 离这里 4000+ 字符, 够不着
	#   ⇒ 全套门禁实测把这两组判成【远处命中】。加这一行不是装饰, 是让审计器锚得到。
	var _anchor := "p2eq_093"
	var flat: float = [30.0, 50.0, 80.0][si]
	var pct: float = [0.01, 0.015, 0.02][si]
	assert(_anchor == EID)   # 顺手让这个锚点不是死变量(改了 EID 这里会立刻炸)
	var raw: float = flat + float(tgt.get("maxHp", 0.0)) * pct
	var dmg: int = battle._resolve_dmg(u, raw, tgt, false)
	# ★from_equip = true: 不回钩 on-hit(否则与剑士追打/冰封/僵硬连锁自激)
	battle._damage._apply_damage_from(u, tgt, dmg, Color("#ffd27a"), 0.0, false, true)
	# 10% 生命偷取只吃这 4 次(规格原文) —— 走实际造成的伤害, 不是 raw
	if u.get("alive", false):
		battle._damage._heal(u, float(dmg) * EMP_LS)
	u["_incense_emp_n"] = int(u.get("_incense_emp_n", 0)) + 1   # 同步触发证据(门禁数它)
	if battle._incense_vfx != null:
		battle._incense_vfx.empower_hit(u, tgt)


## 强化期间 +100% 攻速 —— 走 `aspd_perm`(本项目的永久攻速乘子, 主循环算 atk_cd 时除进去)。
## ★加/撤都走同一个常量, 不写死 2.0 —— 写死的话以后改 EMP_ASPD 会撤不干净(残留永久攻速)。
func _set_emp_haste(u: Dictionary, on: bool) -> void:
	var cur: float = float(u.get("aspd_perm", 1.0))
	u["aspd_perm"] = maxf(0.1, cur + (EMP_ASPD if on else -EMP_ASPD))


# ══════════════════════════════════════════════════════════════════
#  刻痕加成: 携带者 (0.2%+0.1%)/痕, 其余友军 0.1%/痕
#  ★用【差量】施加并记账 —— damage_amp / damage_reduction 是全项目共用的加法字段,
#    凭空减会把别人的贡献也减掉(038 信号放大器就是这么记账的)。
# ══════════════════════════════════════════════════════════════════
func _reapply(side: String) -> void:
	_revoke()
	var m: int = int(_marks.get(side, 0))
	if m <= 0:
		return
	for o in battle._units:
		if not (o is Dictionary) or not o.get("alive", true):
			continue
		if str(o.get("side", "")) != side:
			continue
		# ★"友军"一律排除龟蛋与训龟大师(用户 2026-08-06 定的全表通用口径)
		if o.get("_isEgg", false) or o.get("is_trainer", false):
			continue
		var amp: float = TEAM_AMP * m
		var dr: float = TEAM_DR * m
		if _has_stone(o):
			amp += ITEM_AMP * m     # D2: 装备那一份只给一次, 同龟两件不叠
			dr += ITEM_DR * m
		o["damage_amp"] = float(o.get("damage_amp", 0.0)) + amp
		o["damage_reduction"] = float(o.get("damage_reduction", 0.0)) + dr
		_given.append({"u": o, "amp": amp, "dr": dr})


func _revoke() -> void:
	for g in _given:
		var o = g["u"]
		if o is Dictionary:
			o["damage_amp"] = maxf(0.0, float(o.get("damage_amp", 0.0)) - float(g["amp"]))
			o["damage_reduction"] = maxf(0.0, float(o.get("damage_reduction", 0.0)) - float(g["dr"]))
	_given.clear()


func _has_stone(o: Dictionary) -> bool:
	for e in o.get("equips", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == EID:
			return true
	return false


# ══════════════════════════════════════════════════════════════════
#  充能写回存档(D4: 刻成一道痕时 + 撤场时)
#  ★只写回 left(玩家)。right 是即时生成的 bot, 没有存档(D3)。
# ══════════════════════════════════════════════════════════════════
func _persist_chg(u: Dictionary) -> void:
	if _side_of(u) != "left" or GameState == null:
		return
	var stt = u.get("eq_state", {}).get(EID, null)
	if not (stt is Dictionary):
		return
	var chg: int = clampi(int(stt.get("chg", 0)), 0, PER_MARK)
	var pet := str(u.get("id", ""))
	var pe = GameState.get("persistent_equipped")
	if pe is Dictionary and (pe as Dictionary).has(pet):
		for it in (pe as Dictionary)[pet]:
			if it is Dictionary and str((it as Dictionary).get("id", "")) == EID:
				(it as Dictionary)["chg"] = chg
				return
	# 小将走 dual_lineup(它们共用 id "__minion__", 只能按 lane+槽位找)
	var dl = GameState.get("dual_lineup")
	if dl is Dictionary:
		for lane in (dl as Dictionary):
			for mu in ((dl as Dictionary)[lane] as Array):
				if not (mu is Dictionary) or not ((mu as Dictionary).get("equips") is Array):
					continue
				for it2 in (mu as Dictionary)["equips"]:
					if it2 is Dictionary and str((it2 as Dictionary).get("id", "")) == EID:
						(it2 as Dictionary)["chg"] = chg
						return


# ══════════════════════════════════════════════════════════════════
#  未用到的统一钩子(接口由 EquipSystem 统一调, 见 docs/plans/20260806-实装契约-批④.md)
# ══════════════════════════════════════════════════════════════════
func tick(_delta: float) -> void:
	pass


func on_hit(_src: Dictionary, _tgt: Dictionary, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_damaged(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_death(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


func on_mana_full(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


## 换路撤场: 把充能写回存档、撤掉本件施加的全部增伤/减伤。
## ★不清 `_marks` —— 刻痕是赛季级的, 换路不重置(用户「一大轮重置」= 赛季)。
func clear_all() -> void:
	for o in battle._units:
		if o is Dictionary and _has_stone(o):
			_persist_chg(o)
	_revoke()
