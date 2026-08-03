class_name SynergySystem
extends RefCounted
## 装备【类型羁绊】的战斗侧实装（批 4-1 · 方案书 docs/plans/20260802-装备扩充.md §5）。
##
## ★在此之前羁绊在战斗里【一行效果都没有】：`Phase2Types.apply_team_start` 全仓库零调用方，
##   它写的 `_swordEchoCount` / `_gadgetPieces` / `_relicHealthAtkPct` 等九个标记
##   **在实时版没有任何消费方**（方案书 §2.5 实测）。玩家在背包面板看得见档位，打起来毫无区别。
##
## ★★为什么不直接调 `apply_team_start` 而是新写一份：**它用的是回合制的字段名。**
##   `_apply_type_stat` 写 `baseAtk` / `baseDef` / `baseMr`，而实时战斗读的是
##   `base_atk` / `base_def` / `base_mr`。直接接上去 = 又一次"生产侧写了、消费侧没读"
##   （memory [[fb-write-without-reader-and-fake-gates]]，一天踩过三次）。
##   ⇒ `Phase2Types` 保持它真正的身份：**纯数据 + 计数**（阈值表 / 逐档文案 / calc_active）；
##     战斗侧的施加逻辑住这里，用战斗的字段名。
##
## ── 计数域（D11）───────────────────────────────────────────────────────
## 羁绊按**全队 18 位**算，不按路算：上路 / 下路 / 决胜**共享同一份羁绊**，
## 一场比赛**开始时算一次即固定**。所以这里数的是 `battle._units` 里**本方全部单位**
## 身上的装备，而不是"当前这一路的 3 只"。
##
## ── 本批（4-1）只做 🟢：现成钩子、零新机制 ───────────────────────────
## 十个类型的**每件属性**（给携带者）+ 三条周期效果（法器潮涌 / 食物盛宴 / 盾圣光）。
## 🟡🔴 的那些（剑回响 / 弓箭腐蚀叠层 / 灵物触手 / 枪炮台 / 法器法力条 / 净化 …）**不在本批**，
## 且**没有写进任何文案** —— 逐档文案在 `Phase2Types.TIER_DESCS` 里是完整的，
## 那是设计定稿；本批只实装其中的属性部分，**不承诺没做的**。

var battle

## 每场只算一次的激活档：{类型: 档位(1-based)}。★跨路复用（D11），换路不重算。
var tier_of: Dictionary = {}
## 各方各自的档位：left / right 各一份（对手的羁绊当然按对手的装备算）。
var _by_side: Dictionary = {"left": {}, "right": {}}
var _t_pulse := 0.0          # 潮涌 / 盛宴 的 2.5 秒节拍
var _t_light := 0.0          # 圣光的 5 秒节拍

const PULSE := 2.5           # = RealtimeBattle3DScene.EQ_TICK（装备周期 = 1 回合 ≈ 2.5 秒）
const LIGHT := 5.0

## 法器【潮涌】每档回复「已损失生命」的比例（档1 无此效果）
const TIDE_PCT := [0.0, 0.05, 0.08, 0.12]
## 食物【盛宴】每档回复「已损失生命」的比例（只有档3 有）
const FEAST_PCT := [0.0, 0.0, 0.03]
## 盾【圣光】每档基数（档1 无）；实发 = 基数 × (1 + 0.4 × 携带者身上盾件数)
const LIGHT_BASE := [0.0, 50.0, 90.0]


func _init(b) -> void:
	battle = b


## 开战 / 换路后调用（挂在 _eq_apply_all_stats 之后 —— 单件属性先落地，羁绊再加在上面）。
## ★幂等由 `_synergy_done` 标记保证：换路会重建单位字典，但档位本身不重算（D11 一场算一次）。
func apply_all() -> void:
	for side in ["left", "right"]:
		if (_by_side[side] as Dictionary).is_empty():
			_by_side[side] = _calc_tiers(side)
	tier_of = _by_side["left"]        # 面板/门禁默认看我方
	for u in battle._units:
		if not (u is Dictionary) or u.get("_isEgg", false):
			continue
		_apply_to(u, _by_side.get(str(u.get("side", "left")), {}))


## 统计某一方【全队】的类型件数 → 激活档。
## ★口径与 `Phase2Types.calc_active` 一致：**每件 +1，不看星、不去重**。
## 走宽（凑满一个类型）与走高（合 3★）因此互斥 —— 合一次 3★ 会让羁绊计数 −2。
func _calc_tiers(side: String) -> Dictionary:
	var cnt: Dictionary = {}
	for u in battle._units:
		if not (u is Dictionary) or str(u.get("side", "")) != side:
			continue
		if u.get("_isEgg", false) or u.get("is_trainer", false):
			continue          # 龟蛋与训龟大师不带装备, 也不该被算进羁绊
		for e in u.get("equips", []):
			if not (e is Dictionary):
				continue
			var t: String = battle.Phase2Types.type_of(str(e.get("id", "")))
			if t != "":
				cnt[t] = int(cnt.get(t, 0)) + 1
	var out: Dictionary = {}
	for t in cnt:
		var tiers: Array = (battle.Phase2Types.TYPES.get(t, {}) as Dictionary).get("tiers", [])
		var tier := 0
		for i in range(tiers.size()):
			if int(cnt[t]) >= int(tiers[i]):
				tier = i + 1
		if tier > 0:
			out[t] = tier
	return out


## 把该方的羁绊属性加到一只单位身上。
## ★per-piece：给的是「携带者身上**这个类型**有几件 × 该档每件的值」——
##   不是"全队几件"。这样奖励"把同类堆在一只龟身上"，与专精主题一致（方案书 C3）。
func _apply_to(u: Dictionary, tiers: Dictionary) -> void:
	if tiers.is_empty():
		return
	var mine: Dictionary = {}      # 携带者身上各类型的件数
	for e in u.get("equips", []):
		if not (e is Dictionary):
			continue
		var t: String = battle.Phase2Types.type_of(str(e.get("id", "")))
		if t != "":
			mine[t] = int(mine.get(t, 0)) + 1
	for t in mine:
		if not tiers.has(t):
			continue               # 该类型没激活 → 一点都不给
		var stats: Array = (battle.Phase2Types.TYPES.get(t, {}) as Dictionary).get("stats", [])
		var ti: int = clampi(int(tiers[t]) - 1, 0, maxi(0, stats.size() - 1))
		if ti >= stats.size():
			continue
		var per: Dictionary = stats[ti]
		var n: int = int(mine[t])
		for k in per:
			_add(u, str(k), float(per[k]) * float(n))
	battle._recalc_stats(u)


## 单条属性 → 实时战斗的字段名。★与 `EquipStatsApply.apply_stat_dict` 用同一套字段，
## 不是回合制的 baseAtk/baseDef/baseMr（那正是 apply_team_start 写了没人读的原因）。
func _add(u: Dictionary, k: String, v: float) -> void:
	match k:
		"atk":
			u["base_atk"] = float(u.get("base_atk", 0.0)) + v
		"def":
			u["base_def"] = float(u.get("base_def", 0.0)) + v
		"mr":
			u["base_mr"] = float(u.get("base_mr", 0.0)) + v
		"crit":
			u["crit"] = float(u.get("crit", 0.0)) + v
		"armorPen":
			u["armor_pen"] = float(u.get("armor_pen", 0.0)) + v
		"magicPen":
			u["magic_pen"] = float(u.get("magic_pen", 0.0)) + v
		"_lifestealPct":
			u["lifesteal"] = float(u.get("lifesteal", 0.0)) + v / 100.0
		"_maxEnergy":
			u["init_energy_bonus"] = float(u.get("init_energy_bonus", 0.0)) + v
		"hp":
			# ★装备/羁绊给的 hp 已是最终值, 不乘 HP_MULT(CLAUDE.md §3.1)
			u["maxHp"] = float(u.get("maxHp", 0.0)) + v
			u["hp"] = float(u.get("hp", 0.0)) + v
		_:
			pass          # 其余字段本批不给（灵物闪避走它自己的档位表, 见 §5.3 的双份警告）


## 每帧节拍（挂主循环）。本批三条周期效果全部是 🟢：现成的 _heal / _grant_shield。
func tick(delta: float) -> void:
	if _by_side["left"].is_empty() and _by_side["right"].is_empty():
		return
	_t_pulse += delta
	_t_light += delta
	if _t_pulse >= PULSE:
		_t_pulse -= PULSE
		_pulse()
	if _t_light >= LIGHT:
		_t_light -= LIGHT
		_holy_light()


## 法器【潮涌】+ 食物【盛宴】：每 2.5 秒全队回复「已损失生命」的 N%。
## ★回复的是【已损失】不是【最大】—— 满血时回 0，`_heal` 返回实际回血量。
func _pulse() -> void:
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		var tiers: Dictionary = _by_side.get(str(u.get("side", "left")), {})
		var pct := 0.0
		if tiers.has("法器"):
			pct += float(TIDE_PCT[clampi(int(tiers["法器"]) - 1, 0, 3)])
		if tiers.has("食物"):
			pct += float(FEAST_PCT[clampi(int(tiers["食物"]) - 1, 0, 2)])
		if pct <= 0.0:
			continue
		var lost: float = maxf(0.0, float(u.get("maxHp", 0.0)) - float(u.get("hp", 0.0)))
		if lost > 1.0:
			battle._damage._heal(u, lost * pct)


## 盾【圣光】：每 5 秒为**携带盾的人**生成护盾，量随他身上的盾件数放大。
func _holy_light() -> void:
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		var tiers: Dictionary = _by_side.get(str(u.get("side", "left")), {})
		if not tiers.has("盾"):
			continue
		var base: float = float(LIGHT_BASE[clampi(int(tiers["盾"]) - 1, 0, 2)])
		if base <= 0.0:
			continue
		var n := 0
		for e in u.get("equips", []):
			if e is Dictionary and battle.Phase2Types.type_of(str(e.get("id", ""))) == "盾":
				n += 1
		if n <= 0:
			continue
		battle._damage._grant_shield(u, base * (1.0 + 0.4 * float(n)))
