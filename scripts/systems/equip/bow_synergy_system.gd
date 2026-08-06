class_name BowSynergySystem
extends RefCounted
## 弓箭羁绊的三条机制：【处决】【腐蚀·穿透】【腐蚀叠层】（2026-08-03）
##
## ★弓箭的属性档是全表最弱的（顶档带 3 件只有 DPS ×1.33）——
##   因为用户拍板**不给暴伤**，而 DPS 倍率 = 1 + 暴击 × (暴伤 − 1)，暴伤基础只有 1.5，
##   所以 +66% 暴击只等于 +33% 伤害。**弓箭的强度全压在这三条机制上**，不在属性上。
##
## ── 来源 ─────────────────────────────────────────────────────────────
## · **处决** ← 类型原生（`docs/specs/类型效果-实装规格.md:96-105`）
## · **腐蚀·穿透 / 腐蚀叠层** ← 学派「深渊议会·腐蚀」（`docs/archive/学派效果-实装规格.md:33-37`）
##
## ── 三条的作用域【各不相同】，这点最容易看错 ──────────────────────
## | 处决       | **全队**（用户 2026-08-03 改；原规格是"携带弓箭的宠物"）|
## | 腐蚀·穿透  | **全队**（不带弓箭的队友也吃）                          |
## | 腐蚀叠层   | 打**全场敌人**（无差别 debuff）                         |
##
## ⚠ **处决改全队的代价**：6 只龟每次攻击都在查斩杀线，残血单位基本活不过一秒。
##   不带弓箭的队友暴击率通常是 0 ⇒ 他们的斩杀线就是基数 4/7/10%；
##   带弓箭的因为 `+ 暴击率 × 0.1` 会更高（顶档带 3 件 ≈ 16.6%）。
##   ⇒ **斩杀线仍然是"各自算各自的"**，只是"谁有这个能力"从携带者扩大到全队。

var battle

## 处决斩杀线基数（逐档）。实际线 = 基数 + 该单位暴击率 × CRIT_TO_LINE
const EXEC_BASE := [0.04, 0.07, 0.10]
const CRIT_TO_LINE := 0.1
## ★★2026-08-03 用户定稿：**三条腐蚀效果【每一档都有】，只是数值随档位涨**。
##   这是回到学派原设计的形状 —— 我之前把它拆成"档2 才有穿透、档3 才有叠层"，
##   那是我按「每档解锁一条新机制」的梯度原则**自己加的框架**，不是原设计。
##   原设计三条从首档就一直在（`docs/archive/学派效果-实装规格.md:33-37`）。
## 腐蚀·穿透：全队攻击无视目标多少百分比的护甲与魔抗
const PEN_PCT := [0.04, 0.10, 0.22]
## 腐蚀叠层：每 2.5 秒给全场敌人 +1 层，最多 5 层
const CORRODE_PERIOD := 2.5
const CORRODE_MAX := 5
## 每层让目标受到的伤害 +N%（逐档）
const CORRODE_PER_STACK := [0.02, 0.03, 0.04]
## 满 5 层后，受到的伤害有多少转成真实伤害（逐档，无视护甲/护盾）
const CORRODE_TRUE_PCT := [0.10, 0.20, 0.35]

var _t_corrode := 0.0


func _init(b) -> void:
	battle = b


## 开战 / 换路后：把【腐蚀·穿透】写进休眠通道。
## ★这是全表最划算的一条：`armor_pen_pct` / `magic_pen_pct` 是**已被消费、零写入**的通道
##   （消费点 `battle_damage.gd:505,507` 与 `RealtimeBattle3DScene.gd:4221,4224,4243`）——
##   **只需要往里写，消费侧一行都不用改。**
func apply_all() -> void:
	for u in battle._units:
		if not (u is Dictionary):
			continue
		var tier: int = int(battle._synergy.tier_for(u, "弓箭"))
		if tier <= 0:
			continue
		var pen: float = PEN_PCT[clampi(tier - 1, 0, 2)]
		if pen <= 0.0:
			continue
		# ★用"加"不是"设": 别的来源(装备 038 的魔抗穿透等)也写这个字段, 直接赋值会把它们抹掉。
		u["armor_pen_pct"] = float(u.get("armor_pen_pct", 0.0)) + pen
		u["magic_pen_pct"] = float(u.get("magic_pen_pct", 0.0)) + pen


## 每次【攻击命中】后调（挂 `_apply_damage_from` 的 on-hit 处，与装备 on-hit 同一个位置）。
## ★只挂普攻/技能那条路径，不挂 DoT —— 原规格写的是"攻击时"。
func on_hit(src, tgt) -> void:
	if not (src is Dictionary) or not (tgt is Dictionary):
		return
	if not (tgt as Dictionary).get("alive", false):
		return
	var tier: int = int(battle._synergy.tier_for(src, "弓箭"))
	if tier <= 0:
		return
	# ★2026-08-03 用户改：处决给【全队】，不再要求身上带弓箭。
	#   斩杀线仍按各自的暴击率算 —— 不带弓箭的队友暴击通常是 0，线就是基数。
	var line: float = EXEC_BASE[clampi(tier - 1, 0, 2)] + float(src.get("crit", 0.0)) * CRIT_TO_LINE
	if tgt.get("eq_exec_immune", false):
		return                       # 免疫处决(龟蛋/大师等)
	if float(tgt.get("maxHp", 0.0)) <= 0.0:
		return
	if float(tgt["hp"]) >= float(tgt["maxHp"]) * line:
		return
	# 处决表现照 004 暴君之牙的既有做法：固定跳 -999999 真伤大字（实际伤害 = 剩余血）
	battle._vfx._float_text(tgt["pos"], "-999999",
		battle._VC.color_of(battle._VC.cls_for("damage", "true", true)), true, "damage", "true")
	tgt["hp"] = 0.0
	battle._kill(tgt, src)


## 每帧节拍（挂 `_sim_step`）：**首档起**每 2.5 秒给全场敌人叠一层腐蚀。
## ★这是全表唯一一条**无差别铺全场**的 debuff —— 它对敌方阵容规模不敏感，人越多收益越大。
func tick(delta: float) -> void:
	_t_corrode += delta
	if _t_corrode < CORRODE_PERIOD:
		return
	_t_corrode -= CORRODE_PERIOD
	# 每个阵营各自的弓箭档位（0 = 未激活）
	var side_tier: Dictionary = {}
	for u in battle._units:
		if not (u is Dictionary):
			continue
		var sd: String = str(u.get("side", ""))
		var tv: int = int(battle._synergy.tier_for(u, "弓箭"))
		if tv > int(side_tier.get(sd, 0)):
			side_tier[sd] = tv
	if side_tier.is_empty():
		return
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		var side: String = str(u.get("side", ""))
		# 对面的弓箭档位（多方混战时取最高的那个）
		var foe_tier := 0
		for sd2 in side_tier:
			if str(sd2) != side and int(side_tier[sd2]) > foe_tier:
				foe_tier = int(side_tier[sd2])
		if foe_tier <= 0:
			continue
		u["corrode_stacks"] = mini(CORRODE_MAX, int(u.get("corrode_stacks", 0)) + 1)
		# ★演出(批 B3): 腐蚀叠层现状【零显示】。叠到满 5 层是**规则级切换** ——
		#   此后它受到的伤害有 10/20/35% 转成真实伤害(无视护甲与护盾)。
		#   只在【刚满】那一次放(tier_advance 挡住之后每 2.5 秒的重复喂)。
		#   ⚠ 逐层的显示做不到 —— 那该是头顶徽章, 而 HEAD_ROW_CAP=4 已满(方案书 U5 未拍板)。
		if int(u["corrode_stacks"]) >= CORRODE_MAX and battle._vfx != null and battle._vfx._syn != null:
			var sv = battle._vfx._syn
			if sv.tier_advance(u, "_corrode_vfx", 1):
				sv.bow_corrode_full(Vector2(u.get("pos", Vector2.ZERO)))
		# ★把【施加方的档位】记在目标身上 —— 每层增伤与满层转真伤都随档位变,
		#   而受伤结算那一刻只拿得到目标自己的字典(_mitigate_incoming(u, …)),
		#   拿不到"谁给它上的腐蚀"。不记的话就只能写死一个档位的数。
		u["corrode_tier"] = foe_tier


## 受伤时的增伤倍率（挂 `_mitigate_incoming`）。每层 +2/3/4%（按【施加方】的档位）。
static func vuln_mult(u: Dictionary) -> float:
	var n: int = int(u.get("corrode_stacks", 0))
	if n <= 0:
		return 1.0
	var ti: int = clampi(int(u.get("corrode_tier", 1)) - 1, 0, 2)
	return 1.0 + float(n) * CORRODE_PER_STACK[ti]


## 满 5 层时，受到的伤害有多少比例转成真实伤害（10/20/35%，按【施加方】的档位）。
## ⚠ **两条伤害路径都要用**（CLAUDE.md §3.3：`_apply_damage` 与 `_apply_damage_from` 各自扣血）。
static func true_share(u: Dictionary) -> float:
	if int(u.get("corrode_stacks", 0)) < CORRODE_MAX:
		return 0.0
	return CORRODE_TRUE_PCT[clampi(int(u.get("corrode_tier", 1)) - 1, 0, 2)]


## 换路 / 重开：层数清零（单位字典会重建，但显式清一次更稳）。
func clear() -> void:
	_t_corrode = 0.0
	for u in battle._units:
		if u is Dictionary:
			u["corrode_stacks"] = 0
			u["corrode_tier"] = 0
			# ★演出侧的"放过了没"标记也要跟着清 —— 不清的话下一路重新叠满 5 层时
			#   tier_advance 认为"还在同一档"而不放, 那条演出就永远只出现一次。
			u["_corrode_vfx"] = 0
