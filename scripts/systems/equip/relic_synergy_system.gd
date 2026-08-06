class_name RelicSynergySystem
extends RefCounted
## 遗物羁绊【生死界 / 远古之力 / 龟蛋加固 / 觉醒】（2026-08-03）
##
## 来源：学派「古物商会」（`docs/archive/学派效果-实装规格.md`）。
## 类型原生属性是 `_lifestealPct`（每件 +3/5/8/10% 生命偷取）。
##
## ── 四条的作用域 ─────────────────────────────────────────────────────
## | 生死界     | **携带者**（>50% 加攻 / <50% 吸血翻倍，按本体血量）|
## | 远古之力   | **全队**（每 2.5 秒全队永久涨【增伤%】，本路累积）  |
## | 龟蛋加固   | **本方龟蛋**（加血 + 让蛋自己也能攻击）           |
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
## 【远古之力】每 2.5 秒全队永久 +N% **增伤**（档1 无）。
## ★用户 2026-08-04：「远古之力改为获得增伤」—— 原来是 +4/7/11 **攻击力**。
##   换掉的理由本身也成立：龟基础攻击力中位只有 40，+350 是 ×9.75，
##   一条羁绊把平A打成主伤害来源；而 `damage_amp` 是**乘在所有伤害上**的通道
##   （`battle_damage.gd:546` 与 `RealtimeBattle3DScene.gd:4243` 两处消费点，
##   平A/技能/DoT 全吃），量小得多但覆盖全，正是"古老力量缓慢渗透"该有的形状。
const ANCIENT_PER_TICK := [0.0, 0.01, 0.015, 0.02]
## 累积上限（原文"软上限"没定义 ⇒ 硬上限，见文件头）
const ANCIENT_CAP := [0.0, 0.15, 0.25, 0.35]
## 【龟蛋加固】本方龟蛋 +N 最大生命（档1 无）。
## ★用户 2026-08-04：「龟蛋加固要加强」—— 原 500/900/1500 → **1200/2200/3600**。
##   蛋的原始满血是 `3000 + 300×大轮等级`，顶档 +3600 ≈ 让蛋多扛一倍。
const EGG_HP := [0.0, 1200.0, 2200.0, 3600.0]
## 【龟蛋反击】用户 2026-08-04：「并使龟蛋也开始释放攻击」。
## 蛋原本是**纯血包**（`atk/range = 0`、`no_basic = true`，见 `battle_spawn.gd:283`），
## 遗物激活后给它攻击力与射程，让它自己也打。
const EGG_ATK := [0.0, 40.0, 80.0, 140.0]
## ⚠ 字段名【必须是 `atk_range` / `atk_interval`】——
##   `range` 和 `atk_cd` 都存在但意思不同: `atk_cd` 是"距下次普攻还剩多久"的倒计时
##   (每帧被覆写), `range` 压根不是单位字段。写错这两个 = 蛋照样一动不动,
##   而门禁如果只读自己写进去的键就会是恒真式、全绿。
##   真消费点: `_eff_range()` 读 `atk_range`(RealtimeBattle3DScene.gd:7579)。
const EGG_RANGE := 420.0
const EGG_ATK_INTERVAL := 2.0
## 【觉醒】顶档：本路开打满 N 秒后，已累积的远古之力 +50%。
## ★用户 2026-08-04：「觉醒10档有每跳翻倍这个吗，去掉吧」⇒ **每跳翻倍已删**，
##   只保留一次性的 +50%。（原来那条是"之后每跳也翻倍"，两条叠着涨得太快。）
const AWAKEN_TIER := 4
const AWAKEN_SEC := 20.0
const AWAKEN_BOOST := 0.50

## ── 以下三个常量【只喂演出, 一点数值都不改】(批 B3·2026-08-06) ──────────────
## 【远古之力】跨阈值提示的档位, 写成【上限的比例】而不是绝对值 ——
## 上限本身逐档不同(15/25/35%), 写绝对值就得为每一档各配一组。
## ⚠ 这三个数是我定的: 方案书未决点 U4「静默滚雪球用什么节奏提示」用户尚未拍板,
##   我取的是它的建议 A(跨阈值才放)+C(常驻环) 里的 A 那半; 要调就调这一行。
const ANCIENT_VFX_STEPS := [0.34, 0.67, 1.0]
## 【生死界】演出侧的滞回带(±2 个百分点)。
## ★只影响"要不要放特效", **不影响** `atk_mult` / `lifesteal_bonus` 的 50% 判定 ——
##   血量正好在 50% 附近抖动时(吸血 + 挨打交替)会来回跨线, 没有滞回就是每帧闪一下。
const GATE_DEADBAND := 0.02

var _t_acc := 0.0
## ★本路的 t0。`battle._t` 跨路累加永不重置（CLAUDE.md §3.4），
##   拿它直接判"开打满 20 秒"会让下路一开场就觉醒。
var _t0 := 0.0
var _t0_set := false
var _awakened := {"left": false, "right": false}
## 本场累计的远古之力增伤（各方一份）。存系统对象上, 理由同药水战利品:
## 换路会重建单位字典, 只写字典的话每路打回原形(用户 2026-08-04 定"以场重置")。
var _ancient_total := {"left": 0.0, "right": 0.0}


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
		# 龟蛋加固 + 龟蛋反击: 只加一次
		if u.get("_isEgg", false) and not u.get("_relic_egg_done", false):
			var add: float = EGG_HP[clampi(ti - 1, 0, 3)]
			if add > 0.0:
				u["_relic_egg_done"] = true
				u["maxHp"] = float(u.get("maxHp", 0.0)) + add
				u["hp"] = float(u.get("hp", 0.0)) + add
			var eatk: float = EGG_ATK[clampi(ti - 1, 0, 3)]
			if eatk > 0.0:
				# ★三个字段【缺一不可】: 蛋出厂是 atk=0 / range=0 / no_basic=true
				#   （`battle_spawn.gd:283,456`）。只给攻击力它照样不打 —— 射程 0 选不到人、
				#   no_basic 直接把 AI 普攻整条关掉。这正是"写了没人读"最容易犯的地方。
				u["no_basic"] = false
				u["base_atk"] = float(u.get("base_atk", 0.0)) + eatk
				u["atk_range"] = maxf(float(u.get("atk_range", 0.0)), EGG_RANGE)
				u["atk_interval"] = EGG_ATK_INTERVAL
				u["melee"] = false
				battle._recalc_stats(u)
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
	# ── 092【剧毒飞行物】的每帧驱动(2026-08-05·E 路) ───────────────────────────
	# ★为什么挂这里: 它需要一个【每帧只跑一次、且携带者死后照样跑】的入口 ——
	#   `_tick_eq_intervals` 是逐单位的, 携带者一死那条路就不跑了, 而已经落地的毒雾
	#   必须继续活满 4 秒; 主场景 `_sim_step` 是别人的地盘。遗物羁绊的 tick 正好两条都满足,
	#   而 092 本来就是遗物。★放在下面那些提前 return 之【前】——
	#   挪到后面它就变成每 2.5 秒才动一帧(memory [[fb-write-without-reader-and-fake-gates]])。
	if battle != null and battle._equip_sys != null and battle._equip_sys._venom != null:
		battle._equip_sys._venom.tick(delta)
	# ★"有没有设过"必须用【独立的 bool】，不能拿 `_t0 < 0` 当哨兵 ——
	#   `_t0` 是从 `battle._t` 拷来的时刻，本身就可以是 0 甚至(在测试里)是负数，
	#   拿数值当哨兵会把一个【合法的 t0】判成"没设过"然后覆盖掉，觉醒永远不触发。
	if not _t0_set:
		_t0 = battle._t
		_t0_set = true
	# ★【生死界】的跨线检查必须【每帧】跑 —— 血量是连续变化的, 挂在下面 2.5 秒的节拍上
	#   就会漏掉"2.5 秒内掉下去又被奶回来"的那一次(而那正是玩家最需要知道的一次)。
	#   ⇒ 和 092 同一条规矩: 放在提前 return 之【前】。
	_gate_tick()
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
		# ── 觉醒(顶档): 本路开打满 20 秒 → 已累积的 +50%【一次性】 ──
		# ★"之后每跳翻倍"已按用户 2026-08-04 删掉。
		if ti >= AWAKEN_TIER and (battle._t - _t0) >= AWAKEN_SEC 				and not bool(_awakened.get(s, false)):
			_awakened[s] = true
			_bump_all(s, AWAKEN_BOOST, cap)
			# ★演出(批 B3): 觉醒是【一次性 + 全场级】的, 方案书判定"值得最重的一个"。
			#   数值上面 _bump_all 已经结算完了, 下面这行只画不算。
			_awaken_vfx(s)
		for u in battle._units:
			if not (u is Dictionary) or str(u.get("side", "")) != s:
				continue
			var cur: float = float(u.get("_ancient", 0.0))
			if cur >= cap:
				continue
			var add: float = minf(per, cap - cur)
			u["_ancient"] = cur + add
			# ★演出(批 B3): 每 2.5 秒 +1~2% 是【静默滚雪球】—— 每跳都跳字 = 每 2.5 秒 6 个字。
			#   ⇒ 只在跨阈值时放一次。阈值由【本文件】算好传进去, 演出层一个数字都不烘。
			_ancient_step_vfx(u, cap)
			# ★写 `damage_amp` 不写 `base_atk` —— 增伤是【乘在所有伤害上】的通道,
			#   两处消费点(battle_damage.gd:546 / RealtimeBattle3DScene.gd:4243)已在用,
			#   信息面板也早就显示"增伤 N%"。消费侧零改动。
			u["damage_amp"] = float(u.get("damage_amp", 0.0)) + add
			_ancient_total[s] = float(u["_ancient"])   # 跨路存档(全队同量, 记一个数就够)


# ══════════════════════════════════════════════════════════════════════════
#  §演出侧 (批 B3·2026-08-06) —— 三个函数【一点数值都不改】
#  ★每个都能被门禁单独调用(CLAUDE.md §3.5: 数值测试不许依赖 tween 跑完)。
# ══════════════════════════════════════════════════════════════════════════

## 【觉醒】那一下: 该方全队同时一道金柱 + 脚下八边古纹环 + 中震。
func _awaken_vfx(side: String) -> int:
	if battle == null or battle._vfx == null or battle._vfx._syn == null:
		return 0
	var lit: Array = []
	for u in battle._units:
		if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) == side:
			lit.append(Vector2(u.get("pos", Vector2.ZERO)))
	if lit.is_empty():
		return 0
	return int(battle._vfx._syn.relic_awaken(lit))


## 【远古之力】跨阈值才放一次。阈值 = 上限 × ANCIENT_VFX_STEPS(见常量处的说明)。
func _ancient_step_vfx(u: Dictionary, cap: float) -> void:
	if cap <= 0.0 or battle == null or battle._vfx == null or battle._vfx._syn == null:
		return
	var sv = battle._vfx._syn
	var th: Array = []
	for fr in ANCIENT_VFX_STEPS:
		th.append(cap * float(fr))
	var step: int = sv.tier_of(float(u.get("_ancient", 0.0)), th)
	# tier_advance: 同档反复喂返回 false ⇒ 每 2.5 秒调一次也只在跨档那一次放。
	if sv.tier_advance(u, "_ancient_vfx", step):
		sv.relic_ancient_step(Vector2(u.get("pos", Vector2.ZERO)), step)


## 【生死界】每帧看有没有跨 50% 线。★带滞回, 且**第一次观测只记状态不放特效**
##   —— 否则开局(或换路重建单位)那一帧全队都会闪一下, 而那时什么都没发生。
func _gate_tick() -> void:
	if battle == null or battle._vfx == null or battle._vfx._syn == null:
		return
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		if float(u.get("_relic_atk_bonus", 0.0)) <= 0.0:
			continue                      # 没吃到遗物羁绊的不看(生死界只给携带者)
		var mx: float = float(u.get("maxHp", 0.0))
		if mx <= 0.0:
			continue
		var r: float = float(u.get("hp", 0.0)) / mx
		var prev: int = int(u.get("_relic_gate_vfx", 0))     # 0=还没观测过 1=线上 2=线下
		var now: int = prev
		if r <= HP_GATE - GATE_DEADBAND:
			now = 2
		elif r >= HP_GATE + GATE_DEADBAND:
			now = 1
		if now == 0 or now == prev:
			continue
		u["_relic_gate_vfx"] = now
		if prev == 0:
			continue                      # 第一次只记状态
		battle._vfx._syn.relic_gate(Vector2(u.get("pos", Vector2.ZERO)), now == 2)


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
		u["damage_amp"] = float(u.get("damage_amp", 0.0)) + add


## 换路重建单位【之后】调：把本场已累计的远古之力重放到新的一批单位上。
func restore() -> void:
	for u in battle._units:
		if not (u is Dictionary) or u.get("_ancient_restored", false):
			continue
		var had: float = float(_ancient_total.get(str(u.get("side", "")), 0.0))
		if had <= 0.0:
			continue
		u["_ancient_restored"] = true
		u["_ancient"] = had
		u["damage_amp"] = float(u.get("damage_amp", 0.0)) + had


## 整场结束（不是换路）：远古之力归零，下一场重新开始。
func reset_match() -> void:
	_ancient_total = {"left": 0.0, "right": 0.0}
	_awakened = {"left": false, "right": false}


## 换路：重置本路的 t0 与觉醒态。
## ⚠ `_ancient`（已累积的攻击力）**不清** —— 规格是"本场累积"，而一场 = 上路+下路+决胜。
func clear() -> void:
	_t_acc = 0.0
	_t0 = battle._t
	_t0_set = true
	_awakened = {"left": false, "right": false}
	# 092【剧毒飞行物】: 换路把飞行物 + 所有毒雾 + 所有单位身上的剧毒缓速层一次清干净。
	# ★这就是它的换路【真入口】(dual_lane_flow.gd:467 调的就是本函数)。
	if battle != null and battle._equip_sys != null and battle._equip_sys._venom != null:
		battle._equip_sys._venom.clear_all()
