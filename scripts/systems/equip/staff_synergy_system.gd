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
## 「每件法器有**独立法力条**（多法器各自积累，互不共享）：每回合 +25 法力，
##   另按宠物**技能伤害 ×0.1** + **受伤 ×0.1** 积累；满 100/80/60/50 → 触发这件法器的效果，
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
const MANA_FULL := [100.0, 80.0, 60.0, 50.0]
const MANA_PER_TICK := 25.0        # 每 2.5 秒 +25
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


## 该单位身上第 idx 件法器的法力条满值
func mana_full(u: Dictionary) -> float:
	return MANA_FULL[clampi(tier_of(u) - 1, 0, 3)]


## 给身上每件法器的法力条加 n 点；满了就触发那件法器的效果并清零。
## ★"每件独立"：循环的是携带者身上的每一件法器，各自记在 eq_state[id].mana。
func add_mana(u: Dictionary, n: float) -> void:
	if n <= 0.0 or not u.get("alive", false):
		return
	if u.get("_staff_busy", false):
		return                       # ★防连放：法器效果自己打出的伤害不涨法力
	if tier_of(u) <= 0:
		return
	var full: float = mana_full(u)
	for e in u.get("equips", []):
		if not (e is Dictionary):
			continue
		var iid: String = str(e.get("id", ""))
		if battle.Phase2Types.type_of(iid) != "法器":
			continue
		var stt: Dictionary = u["eq_state"].get(iid, {})
		stt["mana"] = float(stt.get("mana", 0.0)) + n
		u["eq_state"][iid] = stt
		if float(stt["mana"]) < full:
			continue
		stt["mana"] = 0.0
		_fire(u, iid, int(e.get("star", 1)))


## 触发某件法器的效果 —— 走它在 `_tick_eq_intervals` 里的同一个分支，
## 所以"触发这件法器的效果"是字面意义上的同一件事，不会出现两套行为。
func _fire(u: Dictionary, iid: String, star: int) -> void:
	u["_staff_busy"] = true         # 期间产生的伤害不再涨法力（防自激循环）
	battle._equip_sys.fire_equip_effect(u, iid, star)
	u["_staff_busy"] = false


## 每帧节拍：法力自然增长（每 2.5 秒 +25）+ 灵泉（每 2.5 秒）+ 共鸣（每 7.5 秒）。
var _t_tick := 0.0
func tick(delta: float) -> void:
	_t_tick += delta
	if _t_tick >= battle.EQ_TICK:
		_t_tick -= battle.EQ_TICK
		for u in battle._units:
			if not (u is Dictionary) or not u.get("alive", false):
				continue
			var ti: int = tier_of(u)
			if ti <= 0:
				continue
			add_mana(u, MANA_PER_TICK)
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
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		var ti: int = tier_of(u)
		if ti < 4:
			continue
		battle._damage._heal(u, float(u.get("maxHp", 0.0)) * RESONANCE_HEAL)
		dispel(u, RESONANCE_DISPEL[clampi(ti - 1, 0, 3)])


## 净化 n 种减益（按 DISPEL_KINDS 的固定顺序）。返回实际清掉几种。
## ★"净化 N 个" = N **种**不是 N **层** —— 一种清干净算一个。
func dispel(u: Dictionary, n: int) -> int:
	var done := 0
	for kind in DISPEL_KINDS:
		if done >= n:
			break
		if _remove_one(u, str(kind)):
			done += 1
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
