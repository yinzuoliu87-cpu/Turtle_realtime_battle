class_name ShieldSynergySystem
extends RefCounted
## 盾羁绊的三条主动：【怒气冲击波】【反击】【收殓】（2026-08-03）
##
## ★盾这条羁绊是**两个来源拼起来的**，看数值时要分清：
##   · **怒气冲击波** ← 类型原生（`docs/specs/类型效果-实装规格.md:63`）
##   · **圣光 / 反击 / 收殓** ← 学派「圣甲议会·圣盾」（`docs/archive/学派效果-实装规格.md:15-19`）
##   圣光在 `synergy_system.gd` 里（它是纯周期效果，和潮涌/盛宴同一个节拍），这里是另外三条。
##
## ══════════════════════════════════════════════════════════════════════
##  怒气冲击波（用户 2026-08-03 改了两处）
## ══════════════════════════════════════════════════════════════════════
## 原设计：「携带盾者**每次受伤**攒（身上盾件数）点怒气，满 10 释放」
## 改成：**全队每个单位**，**累计受到 400 点伤害**释放一次冲击波。
##
## ★两处改动各自解决一个问题：
##   · **按伤害值不按次数**：按次数会让"被小刀连捅"比"被大招砸一下"攒得快，
##     而且多段攻击（龟壳双段 / 双生匕首追刀 / 剑士追打）会刷出畸形攒速。
##   · **全队而不只是携带者**：让后排脆皮也能参与，盾不再只是"前排自嗨"。
##
## ⚠ **门槛是固定 400，不随血量缩放** —— 这是用户明确的选择，代价要写清楚：
##   冲击波伤害是「**自身**最大生命的 4/6/8%」，所以**血越厚收益越高**。
##   基础龟（944 血）挨 400 → 打 25 真伤；不沉之锚 3★（+4000 血）挨 400 → 打 132 真伤。
##   ⇒ 这条效果**天然偏向肉龟**，与盾的主题一致，但它不是"人人平等"的。
##
## ★冲击波伤害口径：`maxHp / HP_MULT × pct`（**要除 HP_MULT**）。
##   先例是哑铃 `equip_system.gd:428`，也是 CLAUDE.md §3.1 说的"装备百分比回收"。
##   ⚠ 护盾**不除** —— 护盾和生命在同一个刻度上，除了就只有名义值的三分之一。
##   （所以"造成 X% 真伤并获得等量护盾"这句话里的"等量"，在代码里**不是同一个数**。
##     这是刻度差造成的，不是笔误；照字面写一样的表达式反而会错。）

var battle

## 逐档：冲击波 = 自身最大生命的百分之几（真伤 + 自身护盾）
const WAVE_PCT := [0.04, 0.06, 0.08]
## 累计受到多少伤害放一次（用户 2026-08-03 定：400，固定值不随血量缩放）
const RAGE_THRESHOLD := 400.0
## 反击：圣光护盾存在时，受到每段伤害对来源造成 `BASE × (1 + PER × 身上盾件数)` 真伤
const RIPOSTE_BASE := 3.0
const RIPOSTE_PER := 0.5
## 收殓：敌方阵亡 → 最近的携带盾者获得该单位 N% 最大生命的护盾
const REAP_PCT := 0.30
## 反击/收殓只在顶档（档 3）生效
const RIPOSTE_TIER := 3
const REAP_TIER := 3


func _init(b) -> void:
	battle = b


## 受到伤害时调（挂 `_eq_on_target` 那条承伤钩之后）。
## src 可能为 null（DoT / 环境伤害），那时没有反击对象但怒气照常攒。
func on_damaged(u: Dictionary, src, dmg: int) -> void:
	if dmg <= 0 or not u.get("alive", false):
		return
	var tier: int = int(battle._synergy.tier_for(u, "盾"))
	if tier <= 0:
		return
	_rage(u, tier, float(dmg))
	if tier >= RIPOSTE_TIER:
		_riposte(u, src)


## 怒气：累计伤害到阈值 → 冲击波。
## ★用 while 不用 if：一次挨 1200 伤害该放三次，而不是攒着等下次。
##   （靶向器那种大额单次伤害真的会出现，用 if 会静默吞掉两次。）
func _rage(u: Dictionary, tier: int, dmg: float) -> void:
	var acc: float = float(u.get("_shield_rage", 0.0)) + dmg
	var fired := 0
	while acc >= RAGE_THRESHOLD and fired < 5:      # 上限 5：防一次超大伤害刷出一串
		acc -= RAGE_THRESHOLD
		fired += 1
	u["_shield_rage"] = acc
	for _i in range(fired):
		_shockwave(u, tier)


func _shockwave(u: Dictionary, tier: int) -> void:
	var pct: float = WAVE_PCT[clampi(tier - 1, 0, 2)]
	# ★选最近的敌人 —— 确定性选取, 不用随机。
	#   同 §5.7 炮台/§5.8 猎物的规矩: 确定性利于门禁与确定性回放, 也避免"目标闪来闪去"的观感。
	var t = battle._targeting._nearest_enemy(u)
	if t is Dictionary and (t as Dictionary).get("alive", false):
		# ★除 HP_MULT: "自身 X% 最大生命 → 打给别人的伤害"(先例 equip_system.gd:428 哑铃)
		var dmg: int = maxi(1, int(float(u.get("maxHp", 0.0)) / battle.HP_MULT * pct))
		battle._damage._apply_damage_from(u, t, dmg, Color("#ffd93d"), 0.0, true)   # raw=true → 真实伤害
	# ★护盾【不除】HP_MULT: 护盾与生命同刻度
	battle._damage._grant_shield(u, float(u.get("maxHp", 0.0)) * pct)


## 反击：圣光护盾存在时，对伤害来源打真伤。
## ⚠⚠ **必须防"发两次"** —— `p2eq_015 荆棘海胆` 就栽在这上面：
##   通用反伤钩 + 它自己的专属分支同时触发, 实发是名义值的 **2.00×**（探针实测，
##   `equip_stats_apply.gd:50-61` 有整段血泪注释）。
##   本函数与 015 的关系：015 走 `u["reflect"]` 那条通用反伤路径（在 `_apply_damage_from` 里结算），
##   反击走这里的 `_eq_on_target` 路径 —— **两条是不同的路，不会互相重复**，
##   但同一只龟同时带 015 和顶档盾羁绊时**两者都会生效**（那是叠加，不是 bug）。
func _riposte(u: Dictionary, src) -> void:
	if not (src is Dictionary) or not (src as Dictionary).get("alive", false):
		return
	if float(u.get("shield", 0.0)) <= 0.0:
		return                                      # 「圣光护盾存在时」—— 没盾不反击
	var n := 0
	for e in u.get("equips", []):
		if e is Dictionary and battle.Phase2Types.type_of(str(e.get("id", ""))) == "盾":
			n += 1
	var dmg: int = maxi(1, int(RIPOSTE_BASE * (1.0 + RIPOSTE_PER * float(n))))
	battle._damage._apply_damage_from(u, src, dmg, Color("#ffe9a8"), 0.0, true)


## 收殓：敌方单位阵亡 → 最近的携带盾者获得该单位 30% 最大生命的护盾。
## 挂在击杀钩上（`_eq_on_kill` 已存在且带 victim）。
func on_enemy_died(victim: Dictionary) -> void:
	if not (victim is Dictionary):
		return
	var vside: String = str(victim.get("side", ""))
	var best = null
	var best_d: float = 1e18
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		if str(u.get("side", "")) == vside:
			continue                                 # 只给敌人的对面（即死者的敌方）
		if int(battle._synergy.tier_for(u, "盾")) < REAP_TIER:
			continue
		var carries := false
		for e in u.get("equips", []):
			if e is Dictionary and battle.Phase2Types.type_of(str(e.get("id", ""))) == "盾":
				carries = true
				break
		if not carries:
			continue                                 # 「最近的**携带盾者**」
		var d: float = Vector2(u.get("pos", Vector2.ZERO)).distance_squared_to(
			Vector2(victim.get("pos", Vector2.ZERO)))
		if d < best_d:
			best_d = d
			best = u
	if best is Dictionary:
		battle._damage._grant_shield(best, float(victim.get("maxHp", 0.0)) * REAP_PCT)


## 换路 / 重开：怒气累计器归零（单位字典会被整个重建，但显式清一次更稳）。
func clear() -> void:
	for u in battle._units:
		if u is Dictionary:
			u["_shield_rage"] = 0.0
