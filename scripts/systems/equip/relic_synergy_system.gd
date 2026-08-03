class_name RelicSynergySystem
extends RefCounted
## 遗物羁绊【生死界 / 远古之力 / 龟蛋加固 / 觉醒】（2026-08-03）
##
## 来源：学派「古物商会」（`docs/archive/学派效果-实装规格.md`）。
## 类型原生属性是 `_lifestealPct`（每件 +3/5/8/10% 生命偷取）。
##
## ── 四条的作用域 ─────────────────────────────────────────────────────
## | 生死界     | **携带者**（>50% 加攻 / <50% 吸血翻倍，按本体血量）|
## | 远古之力   | **全队**（每 2.5 秒全队永久涨攻，本场累积）        |
## | 龟蛋加固   | **本方龟蛋**                                      |
## | 觉醒       | **全队**（顶档，开打满 20 秒后远古之力提速）       |
##
## ══════════════════════════════════════════════════════════════════════
##  ★两处我按事实改了原文，必须先说清楚
## ══════════════════════════════════════════════════════════════════════
## ① **「<50% 时吸血翻倍(→10%/20%/40%/64%)」括号里的数对不上。**
##    每件给 3/5/8/10%，"翻倍"就是 ×2；而括号写的 10/20/40/64 相对 3/5/8/10
##    是 ×3.33 / ×4 / ×5 / ×6.4 —— 四个档四种倍率，既不是翻倍也没有规律，
##    像是按"顶配件数"倒推出来的估值被当成了倍率写进括号。
##    ⇒ 实装取**字面的"翻倍"（×2）**，文案里把那串括号数删掉，只写"翻倍"。
##
## ② **「软上限」没有定义。** 原文写"本场累积，软上限 +150"，但没说软在哪
##    （超过后衰减？还是只是个建议值？）。⇒ 实装成**硬上限**：到顶就不再涨，
##    文案改写成"上限"。含糊的词留在文案里就是将来对不上的种子。
##
## ★【觉醒】必须自己存 t0 —— `battle._t` 是**跨路累加、永不重置**的全局时钟
##   （CLAUDE.md §3.4）。直接拿 `_t >= 20` 判，下路一开场就已经"觉醒"了。

var battle

const PERIOD := 2.5
## 【生死界】血量 >50% 时的攻击力加成（逐档）
const HP_GATE := 0.5
const ATK_BONUS := [0.03, 0.05, 0.08, 0.12]
## <50% 时生命偷取的倍率（原文"翻倍"）
const LIFESTEAL_MULT := 2.0
## 【远古之力】每 2.5 秒全队永久 +N 攻击力（档1 无）
const ANCIENT_PER_TICK := [0.0, 4.0, 7.0, 11.0]
## 累积上限（原文"软上限"，实装成硬上限，见文件头）
const ANCIENT_CAP := [0.0, 150.0, 250.0, 350.0]
## 【龟蛋加固】本方龟蛋 +N 最大生命（档1 无）
const EGG_HP := [0.0, 500.0, 900.0, 1500.0]
## 【觉醒】顶档：本路开打满 N 秒后，已累积的远古之力 +50%，之后每跳翻倍
const AWAKEN_TIER := 4
const AWAKEN_SEC := 20.0
const AWAKEN_BOOST := 0.50
const AWAKEN_RATE := 2.0

var _t_acc := 0.0
## ★本路的 t0。`battle._t` 跨路累加永不重置（CLAUDE.md §3.4），
##   拿它直接判"开打满 20 秒"会让下路一开场就觉醒。
var _t0 := 0.0
var _t0_set := false
var _awakened := {"left": false, "right": false}


func _init(b) -> void:
	battle = b


func _side_tier(side: String) -> int:
	var t := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			t = maxi(t, int(battle._synergy.tier_for(u, "遗物")))
	return t


## 开战 / 换路后：写【生死界】的系数 + 给龟蛋加血。
func apply_all() -> void:
	_t0 = battle._t
	_t0_set = true
	for u in battle._units:
		if not (u is Dictionary):
			continue
		u["_relic_atk_bonus"] = 0.0
		var ti: int = int(battle._synergy.tier_for(u, "遗物"))
		if ti <= 0:
			continue
		# 生死界的系数写到单位上, 实际按血量分支在 _recalc_stats 里算(那里拿得到实时血量)
		u["_relic_atk_bonus"] = ATK_BONUS[clampi(ti - 1, 0, 3)]
		# 记下【遗物这个类型给了这只多少吸血】—— 生死界的"翻倍"只翻这一份。
		var mine := 0
		for e in u.get("equips", []):
			if e is Dictionary and battle.Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == "遗物":
				mine += 1
		var rs: Array = (battle.Phase2Types.TYPES.get("遗物", {}) as Dictionary).get("stats", [])
		var per: float = float((rs[clampi(ti - 1, 0, rs.size() - 1)] as Dictionary).get("_lifestealPct", 0.0))
		u["_relic_ls"] = per * float(mine) / 100.0
		# 龟蛋加固: 只加一次
		if u.get("_isEgg", false) and not u.get("_relic_egg_done", false):
			var add: float = EGG_HP[clampi(ti - 1, 0, 3)]
			if add > 0.0:
				u["_relic_egg_done"] = true
				u["maxHp"] = float(u.get("maxHp", 0.0)) + add
				u["hp"] = float(u.get("hp", 0.0)) + add
		battle._recalc_stats(u)


## 【生死界】攻击力倍率（挂 `_recalc_stats`）。
## ★与血祭同一个乘区（都乘在 base_atk 上），不是独立乘区 —— 避免 R8 那种"多个乘区连乘"。
static func atk_mult(u: Dictionary) -> float:
	var b: float = float(u.get("_relic_atk_bonus", 0.0))
	if b <= 0.0:
		return 1.0
	var mx: float = float(u.get("maxHp", 0.0))
	if mx <= 0.0:
		return 1.0
	if float(u.get("hp", 0.0)) / mx <= HP_GATE:
		return 1.0                    # <50%: 不加攻, 改成吸血翻倍(见下)
	return 1.0 + b


## 【生死界】血量 <50% 时额外补的生命偷取（挂 `_recalc_stats` 的 `ls_bonus` 写入点）。
##
## ★为什么是"补一份"而不是"整体 ×2"：
##   实际吸血 = `src.lifesteal + src.ls_bonus`（`battle_damage.gd:226`）。
##   羁绊给的吸血进的是 **`lifesteal`**（`synergy_system._add` 的 `_lifestealPct` 分支），
##   而 `_recalc_stats` 只算得出 **`ls_bonus`**（那是 buff 累加出来的）。
##   ⇒ 拿倍率去乘 `ls_bonus` 等于乘了个不相干的数（实测两边都是 0，门禁当场红）。
##   改成"把遗物那一份的量再补一份到 ls_bonus 上" —— 结果正好是【遗物提供的生命偷取翻倍】，
##   而且**不会波及别的吸血来源**（技能吸血/装备吸血照旧），这正是原文的意思。
static func lifesteal_bonus(u: Dictionary) -> float:
	var base: float = float(u.get("_relic_ls", 0.0))
	if base <= 0.0:
		return 0.0
	var mx: float = float(u.get("maxHp", 0.0))
	if mx <= 0.0:
		return 0.0
	return base * (LIFESTEAL_MULT - 1.0) if float(u.get("hp", 0.0)) / mx <= HP_GATE else 0.0


func tick(delta: float) -> void:
	# ★"有没有设过"必须用【独立的 bool】，不能拿 `_t0 < 0` 当哨兵 ——
	#   `_t0` 是从 `battle._t` 拷来的时刻，本身就可以是 0 甚至(在测试里)是负数，
	#   拿数值当哨兵会把一个【合法的 t0】判成"没设过"然后覆盖掉，觉醒永远不触发。
	if not _t0_set:
		_t0 = battle._t
		_t0_set = true
	_t_acc += delta
	if _t_acc < PERIOD:
		return
	_t_acc -= PERIOD
	for side in ["left", "right"]:
		var s: String = str(side)
		var ti: int = _side_tier(s)
		if ti < 2:
			continue
		var per: float = ANCIENT_PER_TICK[clampi(ti - 1, 0, 3)]
		var cap: float = ANCIENT_CAP[clampi(ti - 1, 0, 3)]
		if per <= 0.0:
			continue
		# ── 觉醒(顶档): 本路开打满 20 秒 → 已累积的 +50%, 之后每跳翻倍 ──
		var awake := false
		if ti >= AWAKEN_TIER and (battle._t - _t0) >= AWAKEN_SEC:
			awake = true
			if not bool(_awakened.get(s, false)):
				_awakened[s] = true
				_bump_all(s, AWAKEN_BOOST, cap)     # 一次性: 已累积的 +50%
		if awake:
			per *= AWAKEN_RATE
		for u in battle._units:
			if not (u is Dictionary) or str(u.get("side", "")) != s:
				continue
			var cur: float = float(u.get("_ancient", 0.0))
			if cur >= cap:
				continue
			var add: float = minf(per, cap - cur)
			u["_ancient"] = cur + add
			u["base_atk"] = float(u.get("base_atk", 0.0)) + add
			battle._recalc_stats(u)


## 觉醒的一次性提升：把【已累积的】远古之力 ×(1+pct)，仍受上限约束。
func _bump_all(side: String, pct: float, cap: float) -> void:
	for u in battle._units:
		if not (u is Dictionary) or str(u.get("side", "")) != side:
			continue
		var cur: float = float(u.get("_ancient", 0.0))
		if cur <= 0.0:
			continue
		var add: float = minf(cur * pct, maxf(0.0, cap - cur))
		if add <= 0.0:
			continue
		u["_ancient"] = cur + add
		u["base_atk"] = float(u.get("base_atk", 0.0)) + add
		battle._recalc_stats(u)


## 换路：重置本路的 t0 与觉醒态。
## ⚠ `_ancient`（已累积的攻击力）**不清** —— 规格是"本场累积"，而一场 = 上路+下路+决胜。
func clear() -> void:
	_t_acc = 0.0
	_t0 = battle._t
	_t0_set = true
	_awakened = {"left": false, "right": false}
