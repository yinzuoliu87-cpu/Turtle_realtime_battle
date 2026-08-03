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
var _t_pulse := 0.0          # 盛宴 的 2.5 秒节拍
var _t_light := 0.0          # 圣光的 5 秒节拍

const PULSE := 2.5           # = RealtimeBattle3DScene.EQ_TICK（装备周期 = 1 回合 ≈ 2.5 秒）
const LIGHT := 5.0

## ★法器【潮涌】已于 2026-08-03 从这里【移走】—— 用户把潮水系的名字换成了法器向的
##   （潮涌→灵泉 / 退潮→余韵 / 大潮→共鸣），三条连同法力条一起归 staff_synergy_system.gd 管。
##   **一个类型的机制只能有一个主人**：留在两处就会两边各发一次（同一个 _heal 调两遍）。
## 食物【盛宴】每档回复「已损失生命」的比例（只有档3 有）
const FEAST_PCT := [0.0, 0.0, 0.03]
## 盾【圣光】每档基数（档1 无）；实发 = 基数 × (1 + 0.4 × 携带者身上盾件数)
const LIGHT_BASE := [0.0, 50.0, 90.0]
## 剑【血祭】: 本体每损失 1% 生命 → +N% 攻击力（用户 2026-08-03 定）。
## 全队每只都吃, 不要求身上带剑 —— 这是从血牙帮原样搬来的"全队"口径。
const BLOOD_RITE := [0.1, 0.3, 0.5]


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
##
## ★★口径（用户 2026-08-03 拍板）：**按装备 id 去重** ——
##   带两件一模一样的剑，只算 1 个羁绊数。⇒ 顶档 9 件 = **集齐这个类型的全部 9 种装备**，
##   这才是「顶档 == 件数」最自然的读法（方案书 D5）。
##   ★去重带来一个重要后果：**合成 3★ 不再扣羁绊数**。
##     去重前 3 件同款算 3、合成后剩 1 件算 1 ⇒ −2；去重后 3 件同款本来就算 1 ⇒ ±0。
##     这推翻了方案书 §4.5.2「走宽与走高互斥」的论点 —— 但那个设计等于"升星要罚你掉羁绊",
##     玩家会觉得憋屈。现在两条路可以同时走。
##   ⚠ 只有【阈值计数】去重；**每件属性（per-piece）不去重** ——
##     「每个剑装备额外提供 X 攻击力」说的是你身上带几件就吃几份，带 3 件同款照样吃 3 份。
##     两者口径不同是有意的：去重防的是"刷同一件凑档位", 不是"限制你堆属性"。
func _calc_tiers(side: String) -> Dictionary:
	var cnt: Dictionary = {}
	var seen: Dictionary = {}      # 该方已经数过的装备 id（去重用）
	for u in battle._units:
		if not (u is Dictionary) or str(u.get("side", "")) != side:
			continue
		if u.get("_isEgg", false) or u.get("is_trainer", false):
			continue          # 龟蛋与训龟大师不带装备, 也不该被算进羁绊
		for e in u.get("equips", []):
			if not (e is Dictionary):
				continue
			var eid: String = str(e.get("id", ""))
			if seen.has(eid):
				continue          # ★同一件装备只算一次（不看星、不看带了几份）
			seen[eid] = true
			var t: String = battle.Phase2Types.type_of(eid)
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
	# ── 剑【血祭】: 全队每一只都吃, 【不要求身上带剑】(用户 2026-08-03 定) ──
	#   数值是"每损失 1% 生命 → +N% 攻击力", 实际计算在 RealtimeBattle3DScene._recalc_stats
	#   (那里能拿到实时血量), 这里只负责把档位对应的系数写到单位上。
	if tiers.has("剑"):
		u["_blood_rite"] = BLOOD_RITE[clampi(int(tiers["剑"]) - 1, 0, 2)]
		u["_blood_rite_bucket"] = -999      # 强制下一次 _blood_rite_refresh 真的算一遍

	# ── 食物是全表【唯一】数"携带者身上全部装备"而不是"本类型件数"的效果 ──
	#   §5.10: 队伍每件装备为其携带者 +N 最大生命, 食物类装备【双倍】。
	#   ⇒ 它与"走宽"天然协同(装备位塞满就有血), 也是唯一一条随装备位线性增长的属性。
	if tiers.has("食物"):
		var fs: Array = (battle.Phase2Types.TYPES.get("食物", {}) as Dictionary).get("stats", [])
		var fi: int = clampi(int(tiers["食物"]) - 1, 0, maxi(0, fs.size() - 1))
		var per_eq: float = float((fs[fi] as Dictionary).get("_foodPerEquip", 0.0))
		if per_eq > 0.0:
			var add := 0.0
			for e in u.get("equips", []):
				if not (e is Dictionary):
					continue
				var et: String = battle.Phase2Types.type_of(str(e.get("id", "")))
				add += per_eq * (2.0 if et == "食物" else 1.0)
			if add > 0.0:
				u["maxHp"] = float(u.get("maxHp", 0.0)) + add
				u["hp"] = float(u.get("hp", 0.0)) + add

	for t in mine:
		if t == "食物":
			continue               # 上面单独处理过了, 别再按 per-piece 走一遍
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


## 某只单位所属阵营的某类型激活档（0 = 未激活）。给别的系统查档位用。
func tier_for(u: Dictionary, t: String) -> int:
	var tiers: Dictionary = _by_side.get(str(u.get("side", "left")), {})
	return int(tiers.get(t, 0))


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
		"healAmp":
			# 药水。★`heal_amp` 是【已被消费、羁绊侧零写入】的通道 ——
			#   消费点 `battle_damage._heal`(amt *= 1 + heal_amp), 信息面板也早就在显示"治疗强度"。
			#   ⇒ 只需要往里写, 消费侧一行都不用改(同弓箭的 armor_pen_pct)。
			u["heal_amp"] = float(u.get("heal_amp", 0.0)) + v / 100.0
		"shieldAmp":
			# 同上, 消费点 `battle_damage._grant_shield`(amt *= 1 + shield_amp)。
			u["shield_amp"] = float(u.get("shield_amp", 0.0)) + v / 100.0
		"hp":
			# ★装备/羁绊给的 hp 已是最终值, 不乘 HP_MULT(CLAUDE.md §3.1)
			u["maxHp"] = float(u.get("maxHp", 0.0)) + v
			u["hp"] = float(u.get("hp", 0.0)) + v
		"_aspdPct":
			# 枪。★aspd_perm 是【加算】通道(D16: 多件叠加统一用加) —— 与 038 信号放大器 /
			#   056 飞镖 同一个字段, 用乘会把那两件的口径也带偏。
			u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + v / 100.0
		"dodgePct":
			# 灵物。★上限【不在这里钳】—— DODGE_CAP(0.75) 钳在 _recalc_stats 的唯一写入点,
			#   两处各钳一次必然漂移(v0.18.9 修"带 2 件 3★ 幽灵墨鱼永远打不中"时定的规矩)。
			u["dodge"] = float(u.get("dodge", 0.0)) + v / 100.0
		_:
			pass


## 每帧节拍（挂主循环）。本批三条周期效果全部是 🟢：现成的 _heal / _grant_shield。
func tick(delta: float) -> void:
	if _by_side["left"].is_empty() and _by_side["right"].is_empty():
		return
	_t_pulse += delta
	_t_light += delta   # (保留计时器: 未来若有别的 5 秒周期效果可复用)
	if _t_pulse >= PULSE:
		_t_pulse -= PULSE
		_pulse()
	if _t_light >= LIGHT:
		_t_light -= LIGHT


## 食物【盛宴】：每 2.5 秒全队回复「已损失生命」的 N%。（法器灵泉已移出，见上）
## ★回复的是【已损失】不是【最大】—— 满血时回 0，`_heal` 返回实际回血量。
func _pulse() -> void:
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		var tiers: Dictionary = _by_side.get(str(u.get("side", "left")), {})
		var pct := 0.0
		if tiers.has("食物"):
			pct += float(FEAST_PCT[clampi(int(tiers["食物"]) - 1, 0, 2)])
		if pct <= 0.0:
			continue
		var lost: float = maxf(0.0, float(u.get("maxHp", 0.0)) - float(u.get("hp", 0.0)))
		if lost > 1.0:
			battle._damage._heal(u, lost * pct)


## ★盾【圣光】已于 2026-08-03 从这里【移走】—— 用户重定为一件【羁绊赠送的装备】
## （3 档送 1 件 / 6 档送 2 件，可自由装配、不占容量），实装在 shield_synergy_system.gd。
## 原来那版是"档位直接给携带盾者护盾"，是我实施方案书时简化掉的，与原设计不符。
