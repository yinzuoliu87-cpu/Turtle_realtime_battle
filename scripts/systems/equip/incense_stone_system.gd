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
##    ✅ **用户 2026-08-06 拍板确认**:「那确实是 90/45, 定下来吧」
##       ⇒ 满 300 刻痕时携带者 **+90% 增伤 / +45% 减伤**, 其余友军 +30% / +15%。
##       (我最早给用户的量级表写的是携带者 +60%/+30% —— 只算了装备那一份、漏了羁绊那份
##        也落在携带者身上。那个数是错的, 别按它去做平衡。)
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
## 【共享充能条】按阵营一条(用户 2026-08-13:「对局内两个火石也是一起叠充能, 共享充能条」)。
## ★这里【曾经】记在每个携带者自己的 `eq_state.chg` 里 ⇒ 两块石头 = 两条独立的条,
##   与"共用同一条充能条与刻痕池"对不上。现在系统级一条, 各石头的图标条镜像它。
var _chg: Dictionary = {"left": 0, "right": 0}
## 已经施加给某单位的本件贡献 —— 撤回时要按这个减, 不能凭空减(同 038 信号放大器 signal_amp 的做法)
## 已发放登记表 —— **按侧分开**。
## ★★★2026-08-14 探针实测的真 bug: 这里【曾经是一张全局表】, 而 `_reapply(side)`
##   开头的 `_revoke()` 会把**两侧的加成全撤掉**, 然后只重发自己这一侧。
##   ⇒ 敌我双方同时有香火时, **后跑的那一侧把先跑那一侧的加成整个抹掉**。
##   实测: 左边 10 道刻痕 + 右边 2 道 ⇒ 左边两只携带者 `damage_amp` 都是 **0.0000**,
##   而 `_given.size() == 1`(只剩右边那一只)。
##   ⇒ 改成 {side: [{u, amp, dr}]}, 撤销与发放都只动自己这一侧。
var _given: Dictionary = {"left": [], "right": []}


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
	## 充能条: 从【羁绊池】带进来(用户 2026-08-13:「羁绊里有多少刻痕和充能都是重新激活
	## 状态…就接着激活啊」)。★这里【曾经】读装备实例的 `chg` ⇒ 卖掉再买充能归零、
	## 刻痕却还在, 同一条香火线两半各走各的。现在与刻痕同一个池子。
	if side == "left" and GameState != null:
		_chg["left"] = clampi(int(GameState.incense_charge), 0, PER_MARK)
	stt["chg"] = int(_chg.get(side, 0))   # eq_state 里那份只是**显示镜像**(装备格的充能条读它)
	# ★伤害计数用现成的 `_st_dealt`(两条伤害路径都在记, battle_damage.gd:52/185/211) 做【增量】基准。
	#   不另起一套计数: 另起一套就要在两条路各插一次, 那是 §3.3 的十次机会漏一次。
	stt["dealt0"] = int(u.get("_st_dealt", 0))
	stt["emp_t"] = 0.0
	stt["emp"] = 0
	# 登场就把刻痕数镜像进来 —— 装备格的层数徽章第一帧就要显示存量, 不能等第一次刻痕
	# (⚠ 消费侧尚未接线, 见 tick_unit 里同名字段旁边那段说明)
	stt["marks"] = int(_marks.get(side, 0))
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
			_chg[side] = int(_chg.get(side, 0)) + d      # ★灌进【共享】条: 两块石头一起攒
			# ★★2026-08-09【一帧多道要合成一次】。实拍探针: 携带者一次斩击打出 2 万伤害
			#   ⇒ 这个 while 在 **同一帧** 转了 5 圈(t=13.58 连打 marks=1,2,3,4,5)。
			#   原来每圈都调一次 `_on_mark_scored` ⇒ 同一个点上叠 5 道一模一样的刻痕、
			#   5 条互相盖住的飘字("香火 1".."香火 5" 完全重合 = 谁都读不出来),
			#   而 `_reapply` 也白跑 5 遍(每遍都要 revoke + 遍历全场重发)。
			#   ⇒ 先把这一帧刻了几道数出来, 循环结束后**只结算/只演出一次**。
			var gained := 0
			while int(_chg.get(side, 0)) >= PER_MARK and int(_marks.get(side, 0)) < MARK_CAP:
				_chg[side] = int(_chg.get(side, 0)) - PER_MARK
				_marks[side] = int(_marks.get(side, 0)) + 1
				gained += 1
			# ★★钳一次: 上面这个 while 可能是【在循环中途撞到 300 上限】退出的,
			#   那时 chg 还剩一大截(实测灌 500 道的量时是 816000)。不钳就会显示成
			#   "充能条 816000/4000" —— 而且一旦上限以后被调高, 这堆存量会瞬间全变成刻痕。
			if int(_marks.get(side, 0)) >= MARK_CAP:
				_chg[side] = PER_MARK
			if gained > 0:
				_on_mark_scored(u, side, gained)
		else:
			# ★进 tick 时就已经满 300: 不再消耗充能, 条冻结显示满(方案书 R4 的定论)
			_chg[side] = PER_MARK
	stt["chg"] = int(_chg.get(side, 0))   # ★共享条 → 显示镜像(每块石头的图标条都显示同一个值)
	# 刻痕数镜像进 eq_state: 头像下装备格的层数徽章(PANEL_COUNT)只会读 eq_state,
	# 而刻痕本身是【按阵营】存的池子, 单位身上没有。无条件写(不只在刻痕时写),
	# 否则登场那一刻的存量刻痕在格子里显示成 0。
	#
	# ⚠⚠【消费侧还没接上, 现在这行是死写】—— 诚实记录, 别当成"已经做完了"。
	#   093 目前**不在** `RealtimeBattle3DScene.PANEL_COUNT / PANEL_CHARGE` 里,
	#   所以这一件的两个核心读数(充能条 0~4000 / 刻痕数 0~300)在局内**没有任何 UI 出口**
	#   —— VFXLAB 开着 ui=true 实拍过, 装备格里是空的。
	#   接线只要两行(在主场景那两张常量表里各加一条, 归主会话改):
	#     PANEL_COUNT  : "p2eq_093": "marks"
	#     PANEL_CHARGE : "p2eq_093": ["chg", 4000.0, "#ffd27a"]
	#   这两行一加, 本行与 `stt["chg"]` 就是它们的数据源, 不用再动别处。
	stt["marks"] = int(_marks.get(side, 0))

	# ② 主动: 每 12 秒强化下 4 次普攻。★自管累加器, 不读 battle._t(它跨路累加永不重置·§3.4)
	stt["emp_t"] = float(stt.get("emp_t", 0.0)) + delta
	if float(stt["emp_t"]) >= EMP_IV:
		stt["emp_t"] = float(stt["emp_t"]) - EMP_IV
		if int(stt.get("emp", 0)) <= 0:
			stt["emp"] = EMP_SHOTS
			_set_emp_haste(u, true)
			if battle._incense_vfx != null:
				battle._incense_vfx.empower_burst(u)


## 刻成痕: 重算全队加成、写回存档、放演出。
## `gained` = **这一帧一共刻了几道**(见 tick_unit 的批量注释), 演出要拿它决定摆几道凿痕、飘字写 +几。
func _on_mark_scored(u: Dictionary, side: String, gained: int) -> void:
	if side == "left" and GameState != null:
		GameState.incense_marks = int(_marks["left"])
	_persist_chg(u)
	_reapply(side)
	if battle._incense_vfx != null:
		battle._incense_vfx.mark_carved(u, int(_marks.get(side, 0)), gained)


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
	_revoke(side)          # ★只撤这一侧 —— 撤两侧会抹掉对面已发的(见 _given 的注释)
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
		(_given[side] as Array).append({"u": o, "amp": amp, "dr": dr})


## 撤销【某一侧】已发的加成。side 传空串 = 两侧都撤(换路/换场用)。
## ★参数不是可选的装饰: `_reapply(side)` 必须只撤自己这一侧, 否则就是上面注释里那个 bug。
func _revoke(side: String = "") -> void:
	for sd in (["left", "right"] if side == "" else [side]):
		for g in (_given.get(sd, []) as Array):
			var o = g["u"]
			if o is Dictionary:
				o["damage_amp"] = maxf(0.0, float(o.get("damage_amp", 0.0)) - float(g["amp"]))
				o["damage_reduction"] = maxf(0.0, float(o.get("damage_reduction", 0.0)) - float(g["dr"]))
		_given[sd] = []


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
	var chg: int = clampi(int(_chg.get(_side_of(u), 0)), 0, PER_MARK)
	## ★写回【羁绊池】—— 与刻痕同一条线(2026-08-13)。下面写装备实例那份保留着,
	##   是为了老存档里已经攒下的 `chg` 不至于凭空丢(读的时候已经不看它了)。
	GameState.incense_charge = chg
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
## 系统级每帧: 只做一件事 —— 【阵容变了就重发】。
## ★★用户 2026-08-14 追问「全队共享你确定」时挖出来的真 bug:
##   `_reapply` 原本只在两个时机跑 —— 刻了新痕 / 带石头的龟登场。
##   ⇒ 战斗**中途**才出现的单位(召唤物 / 机甲 / 大熊 / 海螺虫)在下一道刻痕之前
##     **完全吃不到**香火的全队增伤与减伤。实测: 场上 8 道刻痕, 中途加入的友军增伤 0.0000。
##   后期一道刻痕要 4000 伤害, 这个空窗可以长到一整场。
## ★为什么用"人数"当触发条件而不是每帧无条件 reapply:
##   `_reapply` 会 `_revoke()` 再遍历全场重发, 每帧跑是纯浪费;
##   而阵容只在生成/死亡时变 —— 人数变了就够了(死亡也要重发: `_revoke` 靠 `_given` 记账,
##   死人留在表里会让下次 revoke 去减一个已经不在场的单位)。
var _roster_n: Dictionary = {"left": -1, "right": -1}
## 本场是否已经从存档加载过(刻痕 + 充能)。★换路/换场由 `clear_all()` 复位。
var _loaded: Dictionary = {"left": false, "right": false}
func tick(_delta: float) -> void:
	## ★★★用户 2026-08-14 实测:「攒了 20 刀也是 0, 为什么上半有下半没有」。
	##   根因: `_marks["left"]` **只在 `on_spawn` 里从存档读**, 而 `on_spawn` 只对
	##   【带石头的龟】触发。石头装在只打上路的龟身上 ⇒ 下路一个携带者都没有
	##   ⇒ 刻痕根本没被读进来(探针实测: 存档 20 道, 局内 `_marks["left"] = 0`)
	##   ⇒ 下路全队增伤减伤都是 0, 攒多少道都没用。
	## ★为什么这是错的: 香火是【羁绊】。按 v0.19.138 羁绊按**全阵容**算、三个战场共享,
	##   所以"这一路有没有人带着石头"根本不该决定全队吃不吃得到。
	## ★单调采纳(只往上取)而不是无条件覆盖: 局内刻下的新痕会先写存档再回来,
	##   无条件覆盖在时序上没问题, 但只往上取更稳 —— 任何情况下都不会把局内进度抹掉。
	## ★充能条不能用"只往上取": 它在刻痕时要 **减** PER_MARK, 单调采纳会把刚扣掉的又灌回来
	##   ⇒ 无限刻痕。所以用【每场只加载一次】的闸, 由 `clear_all()`(换路/换场)重置。
	##   用户 2026-08-14 举的例子:「在上路战场应该从 200 充能开始而不是 0」。
	if GameState != null and not bool(_loaded.get("left", false)):
		_loaded["left"] = true
		_marks["left"] = maxi(int(_marks.get("left", 0)), clampi(int(GameState.incense_marks), 0, MARK_CAP))
		_chg["left"] = maxi(int(_chg.get("left", 0)), clampi(int(GameState.incense_charge), 0, PER_MARK))
		_roster_n["left"] = -1            # 逼下面那段重发一次
	for side in ["left", "right"]:
		if int(_marks.get(side, 0)) <= 0:
			continue
		var n := 0
		for o in battle._units:
			if o is Dictionary and o.get("alive", false) and str(o.get("side", "")) == side:
				n += 1
		if n != int(_roster_n.get(side, -1)):
			_roster_n[side] = n
			_reapply(str(side))


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
##
## ══════════════════════════════════════════════════════════════════
##  ★★★2026-09-05 实测: 本函数**全仓零调用者**, 而且不调它【没有任何功能后果】
## ══════════════════════════════════════════════════════════════════
## `dual_lane_flow.gd:513` 明确写了「香火石 `_incense` 故意不在换路清场里」,
## 所以这是**有意**不调, 不是漏接线。但那条注释给的理由（「清了就把玩家的进度抹了」）
## 与本函数的代码事实对不上 —— 它干的第一件事就是 `_persist_chg` **把余额写回存档**。
## 为免下一个人（和我自己）再查一遍, 把三条逐个量过的结论钉在这里:
##
##   ① `_incense_vfx.clear()` 不跑 ⇒ 香台会不会残留到下一路?  **不会**(探针实测)
##      分母①换路前香台=1 · 分母②换路后携带者已不在 `_units` · 换路+5 秒后 `_altars`=0。
##      下面那句「靠节点被 `_world` 一起 free 兜底是**别人的**生命周期」担心的事没发生
##      —— 兜底确实生效。是架构洁癖层面的顾虑, 不是功能缺陷。
##   ② `_revoke()` 不跑 ⇒ 增伤/减伤会不会带进下一路?  **不会**。
##      buff 写在**单位字典自己**的 `damage_amp`/`damage_reduction` 上, 而换路后
##      那批字典整体离场, 下一路是 `_spawn_lane_side` 新建的单位。
##   ③ `_persist_chg` 不跑 ⇒ 本路进度会不会丢?  **不会**。
##      它另有一个活调用点在本文件 `:200`（刻痕产生的当时就写回), 不依赖本函数。
##
## ★这条为什么没被 `zero_caller_audit.py` 抓到: `clear_all` 这个名字被 **16 个类**定义,
##   而它的主判据是「名字在全仓出现过就算有人调」⇒ **同名方法互相掩护, 必然全绿**。
##   已把这个盲区写进那个审计器的头注, 并加了一道"同名掩护"第二道网。
# zero-caller-ok: 有意不调(dual_lane_flow.gd:513); 三条后果已逐个实测为无影响, 见上
func clear_all() -> void:
	for o in battle._units:
		if o is Dictionary and _has_stone(o):
			_persist_chg(o)
	_revoke()
	## ★复位加载闸 —— 下一路要重新从存档把刻痕与充能读进来。
	##   (上面 `_persist_chg` 已经先把本路的余额写回存档, 所以读到的是最新值。)
	_loaded = {"left": false, "right": false}
	_roster_n = {"left": -1, "right": -1}
	# ★演出也要撤。香台是**常驻节点**(挂在 `_world` 上、由 emp 驱动), 换路时那批单位字典
	#   会被换掉 —— 不显式拔掉的话它就靠"节点被 _world 一起 free"兜底, 而那是**别人的**
	#   生命周期, 不是本层保证的。本层自己建的东西本层自己收。
	if battle._incense_vfx != null:
		battle._incense_vfx.clear()
