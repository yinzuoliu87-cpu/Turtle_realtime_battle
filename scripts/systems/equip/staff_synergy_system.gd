class_name StaffSynergySystem
extends RefCounted
## 法器羁绊【法力条 / 灵泉 / 余韵 / 共鸣】（2026-08-03）
##
## ★名字换过一轮：潮涌 / 退潮 / 大潮 是**学派「潮汐议会」**的叫法，
##   而这个类型现在叫【法器】—— 潮水主题跟它不搭。用户 2026-08-03 要求改成法器向的名字。
##
## ★作用域分工（用户 2026-08-03 明确要考虑的）：
##   · **法力条 = 携带者**（每件法器各自累计，是"带法器的人"的专属奖励）
##   · **灵泉 / 余韵 / 共鸣 = 全队**（法器是团队续航型；方案书 R19 记着"团队续航最早要凑到法器"）
##   ⇒ 两边不重叠：带法器的人多一条触发路径，整支队伍多一层续航。
##
## ── 来源 ─────────────────────────────────────────────────────────────
## · **法力条** ← 类型原生（`docs/specs/类型效果-实装规格.md:109-116`）
## · **灵泉 / 余韵 / 共鸣**（原名 潮涌 / 退潮 / 大潮）← 学派「潮汐议会」（`docs/archive/学派效果-实装规格.md:39-43`）
##
## ══════════════════════════════════════════════════════════════════════
##  法力条（原生规格逐字）
## ══════════════════════════════════════════════════════════════════════
## 「每件法器有**独立法力条**（多法器各自积累，互不共享）：每 2.5 秒 +15 法力（2026-08-13 削弱：原 25），
##   另按宠物**技能伤害 ×0.1** + **受伤 ×0.1** 积累；满值随档位(2026-08-12 削弱后 200/180/150/120/80) → 触发这件法器的效果，
##   然后清空该法力条重新积累。」
## 「规则：**法器效果本身造成的伤害不计入法力积累**（防连放）；仅宠物自身技能伤害与受伤计入。」
##
## ★"防连放"那条不是可选项 —— 法器效果打出的伤害如果也涨法力，
##   就是「满 → 放 → 伤害 → 又满 → 再放」的自激循环。用 `_staff_busy` 标记堵住。
##
## ★法力条【不是龟能】。项目里 `_energy` / `_maxEnergy` 是龟能（放技能用的），
##   法力条是每件法器各自的独立计数，存在 `u.eq_state[装备id].mana`。
##   `phase2_types.gd` 的老注释专门写过这条铁律，别把两者接到一起。
##
## ══════════════════════════════════════════════════════════════════════
##  净化（共鸣）
## ══════════════════════════════════════════════════════════════════════
## ⚠ 原文写「净化冰冻/灼烧/腐蚀/僵硬等」，但**冰冻在代码里就是眩晕** ——
##   `_freeze()` 只是 `_stun(u, sec, "_freeze")` 加一个特效环，共用同一个 `stun_until` 字段，
##   两者**分不开**。用户 2026-08-03 拍板：**就按眩晕算**（文案也写眩晕，不写冰冻）。
##   ⇒ 这样文案与实装一致，不会出现"说得到做不到"。

var battle

## 逐档：法力条满值
## 法力条满值 —— **下标 = 档位(0~4)**, 档 0 = 没激活法器羁绊。
## 用户 2026-08-12 实测后削弱(原「法器装备过于强势」):
##   未激活 200 / 2 件 180 / 5 件 150 / 8 件 120 / 10 件 80。
##   法器的档位阈值就是 [2,5,8,10](phase2_types.gd), 所以这五个数与"档 0~4"一一对应。
## ★这里【曾经】是 `[100, 80, 60, 50]` 按档位 1~4 索引, 档 0 靠 clamp 落到索引 0
##   ⇒ 未激活与首档同值 100。现在档 0 单列 200, 不再与首档同值。
const MANA_FULL_BY_TIER := [200.0, 180.0, 150.0, 120.0, 80.0]
const MANA_PER_TICK := 15.0        # 每 2.5 秒 +15 (用户 2026-08-13 削弱: 25 → 15)
const MANA_FROM_DMG := 0.1         # 技能伤害 ×0.1
const MANA_FROM_TAKEN := 0.1       # 受伤 ×0.1
## 灵泉（全队）：每 2.5 秒全队回复「已损失生命」的比例
const SPRING_PCT := [0.0, 0.05, 0.08, 0.12]
## 余韵（全队）：友军受到治疗时额外获得治疗量 N% 的护盾
const ECHO_PCT := [0.0, 0.0, 0.30, 0.50]
## 共鸣（全队）：每 7.5 秒全队回复最大生命的 N%，并净化 M 个减益（仅顶档）
const RESONANCE_PERIOD := 7.5
const RESONANCE_HEAL := 0.15
const RESONANCE_DISPEL := [0, 0, 0, 2]

var _t_reso := 0.0

## 净化的减益种类与清除顺序。★顺序固定 = 门禁可断言、回放可复现。
## ⚠ 冰冻不单列 —— 它在存储上就是眩晕（同一个 stun_until），见文件头。
const DISPEL_KINDS := ["眩晕", "减速", "灼烧", "中毒", "诅咒"]


func _init(b) -> void:
	battle = b


func tier_of(u: Dictionary) -> int:
	return int(battle._synergy.tier_for(u, "法器"))


## 【按件】的法力条满值倍率 —— 装备自己的负面/正面被动。★★这是"满值按件算"的唯一来源:
## 没登记的装备一律 1.0(= 老行为, 满值只看羁绊档位)。
## · 043 海浪护符: 上限 +50/25/0%(★1/★2/★3) —— 浪墙是敌我通吃的全场 AOE, 代价是低星攒得慢。
##   ⚠ 三元数组就近声明在这里而不是 `_eq_water_wave` 里: 它是**法力条**的属性(这个类的地盘),
##     不是浪墙本身的参数。tooltip_number_audit 的"远处命中"白名单里记了这一条。
## ★写成【百分比】而不是倍率: 文案逐字是"上限提升50/25/0%", 代码里放同一个三元组,
##   tooltip_number_audit 才对得上(它比的就是文案三元组 ↔ 代码三元数组)。
const MANA_FULL_PCT := {"p2eq_043": [50.0, 25.0, 0.0]}


## 某个【单位 × 某件法器】的法力条满值 = 档位满值 × (1 + 该件的上限提升%)。
func mana_full_for(u: Dictionary, iid: String, star: int) -> float:
	var m: Array = MANA_FULL_PCT.get(str(iid), [])
	if m.is_empty():
		return mana_full(u)
	return mana_full(u) * (1.0 + float(m[clampi(star, 1, 3) - 1]) * 0.01)


## 该单位身上第 idx 件法器的法力条满值。
## ★档 0(没激活羁绊)= 100, 与首档同值 —— clamp 把 -1 夹到 0 就是这个意思, 不是巧合:
##   规格里首档写的就是 100, 羁绊的收益是从二档起【降满值】(80/60/50), 一档只给属性与团队效果。
func mana_full(u: Dictionary) -> float:
	return MANA_FULL_BY_TIER[clampi(tier_of(u), 0, 4)]


## 给身上每件法器的法力条加 n 点；满了就触发那件法器的效果并清零。
## ★"每件独立"：循环的是携带者身上的每一件法器，各自记在 eq_state[id].mana。
func add_mana(u: Dictionary, n: float) -> void:
	if n <= 0.0 or not u.get("alive", false):
		return
	if u.get("_staff_busy", false):
		return                       # ★防连放：法器效果自己打出的伤害不涨法力
	## ★这里【曾经】有一道 `if tier_of(u) <= 0: return` —— 没激活法器羁绊就一点法力不涨。
	##   2026-08-12 用户拆掉:「我整个场上只装备符纸为啥不能触发主动? 激活法器羁绊只是
	##   加快法力条的充能但没激活时也有 100 法力值啊」。理由是硬的: 088/089/090 三件的
	##   **唯一**触发方式就是"该法器法力条集满时"(文案逐字), 有闸就等于单装一件=死件,
	##   文案承诺的主动永远兑现不了。⇒ 法力条是【每件法器自带】的, 满值 100;
	##   羁绊的作用是把满值降到 80/60/50(mana_full 的 clamp 本来就让档 0 = 100)。
	##   ⚠ 只拆法力条这一道 —— 灵泉/共鸣是**全队**收益, 照旧要档位。
	for e in u.get("equips", []):
		if not (e is Dictionary):
			continue
		var iid: String = str(e.get("id", ""))
		if battle.Phase2Types.type_of(iid) != "法器":
			continue
		## ★满值【按件算】: 档位满值 × 该件自己的倍率(043 的负面被动 +50/25/0%)。
		##   循环内取而不是循环外 —— 同一个单位身上两件法器的满值可以不一样。
		var full: float = mana_full_for(u, iid, int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		stt["mana"] = float(stt.get("mana", 0.0)) + n
		## ★★镜像一份【归一化百分比】给装备图标框的法力条(2026-08-10 补)。
		##   用户实测:「5 费装备有个法器吧, 那我压根没看到装备图标那里有法力条,
		##   在攒法力吗」—— 查证: 10 件法器**一件都不在 PANEL_CHARGE 里**, 局内零读数。
		##   ★为什么不直接拿 `mana`: 满值 `MANA_FULL_BY_TIER` 随档位变(200/180/150/120/80),
		##     而 PANEL_CHARGE 的分母只能是**常量** ⇒ 直接拿 mana 会让高档永远填不满。
		##     同 081 藤编圆盾那一行的做法(存 chg_pct), 这里存 mana_pct(0~100)。
		stt["mana_pct"] = clampf(float(stt["mana"]) / maxf(1.0, full) * 100.0, 0.0, 100.0)
		u["eq_state"][iid] = stt
		if float(stt["mana"]) < full:
			continue
		stt["mana"] = 0.0
		stt["mana_pct"] = 0.0
		_fire(u, iid, int(e.get("star", 1)))


## 触发某件法器的效果 —— 走它在 `_tick_eq_intervals` 里的同一个分支，
## 所以"触发这件法器的效果"是字面意义上的同一件事，不会出现两套行为。
func _fire(u: Dictionary, iid: String, star: int) -> void:
	u["_staff_busy"] = true         # 期间产生的伤害不再涨法力（防自激循环）
	battle._equip_sys.fire_equip_effect(u, iid, star)
	u["_staff_busy"] = false
	# ★演出(批 B3): 法力条【玩家没有任何途径看到进度】—— 只会突然看到某件装备效果放了。
	#   U3 用户未拍板 ⇒ 按方案书建议 C: 先只做"响了"这一下的闪光, 进度条另议。
	#   放在 fire 之【后】: 那件装备自己的演出先出, 这根柱子是"为什么它响了"的注脚。
	if battle._vfx != null and battle._vfx._syn != null:
		battle._vfx._syn.staff_mana_full(Vector2(u.get("pos", Vector2.ZERO)))


## 每帧节拍：法力自然增长（每 2.5 秒 +15）+ 灵泉（每 2.5 秒）+ 共鸣（每 7.5 秒）。
var _t_tick := 0.0
func tick(delta: float) -> void:
	_t_tick += delta
	if _t_tick >= battle.EQ_TICK:
		_t_tick -= battle.EQ_TICK
		for u in battle._units:
			if not (u is Dictionary) or not u.get("alive", false):
				continue
			var ti: int = tier_of(u)
			## ★自然增长(每 2.5 秒 +15)对【每个带法器的人】都跑, 不再要求档位 ≥1（同上）。
			##   下面的灵泉才是全队收益, 那个仍然要档位。
			add_mana(u, MANA_PER_TICK)
			if ti <= 0:
				continue
			var pct: float = SPRING_PCT[clampi(ti - 1, 0, 3)]
			if pct > 0.0:
				var lost: float = maxf(0.0, float(u.get("maxHp", 0.0)) - float(u.get("hp", 0.0)))
				if lost > 1.0:
					battle._damage._heal(u, lost * pct)
	_t_reso += delta
	if _t_reso >= RESONANCE_PERIOD:
		_t_reso -= RESONANCE_PERIOD
		_resonance()


## 共鸣：全队回 15% 最大生命 + 净化 N 个减益（仅顶档）
func _resonance() -> void:
	var lit: Array = []          # 这一次共鸣【谁被引动了】—— 只喂演出, 不参与任何结算
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		var ti: int = tier_of(u)
		if ti < 4:
			continue
		battle._damage._heal(u, float(u.get("maxHp", 0.0)) * RESONANCE_HEAL)
		dispel(u, RESONANCE_DISPEL[clampi(ti - 1, 0, 3)])
		lit.append(Vector2(u.get("pos", Vector2.ZERO)))
	# ★演出(批 B3): 7.5 秒才一次 ⇒ 方案书 §2.3 判定"可以做重的"。全队【同时】一道蓝紫光柱。
	#   现状只有 _heal 的绿字, 而"全队同时被引动"这件事只有同时性才表达得出来。
	if not lit.is_empty() and battle._vfx != null and battle._vfx._syn != null:
		battle._vfx._syn.staff_resonance(lit)


## 净化 n 种减益（按 DISPEL_KINDS 的固定顺序）。返回实际清掉几种。
## ★"净化 N 个" = N **种**不是 N **层** —— 一种清干净算一个。
func dispel(u: Dictionary, n: int) -> int:
	var done := 0
	for kind in DISPEL_KINDS:
		if done >= n:
			break
		if _remove_one(u, str(kind)):
			done += 1
	# ★演出(批 B3): 净化【清掉眩晕/减速/灼烧/中毒/诅咒, 零提示】—— 缺的正是"清掉了什么"。
	#   放在这里而不是 _resonance 里: dispel 是净化的唯一出口, 将来别的来源调它也一样有表现。
	#   ⚠ 只在【真的清掉了】时才放 —— done==0 时放特效就是"什么都没净化却闪了一下"。
	if done > 0 and battle._vfx != null and battle._vfx._syn != null:
		battle._vfx._syn.staff_dispel(Vector2(u.get("pos", Vector2.ZERO)), done)
	return done


func _remove_one(u: Dictionary, kind: String) -> bool:
	match kind:
		"眩晕":
			# ⚠ 冰冻共用这个字段（_freeze 就是 _stun 加特效），所以清眩晕连冰冻一起清。
			if float(u.get("stun_until", 0.0)) > battle._t:
				u["stun_until"] = 0.0
				return true
		"减速":
			if float(u.get("slow_until", 0.0)) > battle._t:
				u["slow_until"] = 0.0
				return true
		"灼烧", "中毒":
			var ds: Dictionary = u.get("dot_stacks", {})
			var key: String = "burn" if kind == "灼烧" else "poison"
			if int(ds.get(key, 0)) > 0:
				ds[key] = 0
				u["dot_stacks"] = ds
				return true
		"诅咒":
			# ⚠ 诅咒【不是】一个 until 字段 —— 它是 `dots` 数组里 tag=="curse" 的那一条
			#   （`battle_damage._add_curse`：同一目标只保留一条、重复施加累加时长）。
			#   我第一版写的 `curse_until` **全仓库没有第二处**，那就是个净化不掉任何东西的空动作。
			var ds2: Array = u.get("dots", [])
			for i in range(ds2.size() - 1, -1, -1):
				var d = ds2[i]
				if d is Dictionary and str((d as Dictionary).get("tag", "")) == "curse":
					ds2.remove_at(i)
					return true
	return false


## 余韵（全队）：友军受到治疗时额外获得治疗量 N% 的护盾（挂 `_heal` 之后）。
## ⚠ 防递归：余韵产的是**护盾**不是治疗，天然不成环；但仍留一道 `_ebb_busy`，
##   免得将来有人加"护盾转治疗"时炸掉。
var _ebb_busy := false
func on_healed(u: Dictionary, amount: float) -> void:
	if _ebb_busy or amount <= 0.0 or not (u is Dictionary):
		return
	var ti: int = tier_of(u)
	if ti <= 0:
		return
	var pct: float = ECHO_PCT[clampi(ti - 1, 0, 3)]
	if pct <= 0.0:
		return
	_ebb_busy = true
	battle._damage._grant_shield(u, amount * pct)
	_ebb_busy = false


func clear() -> void:
	_t_tick = 0.0
	_t_reso = 0.0
