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
##   ★护盾不再按最大生命算 —— 2026-08-03 用户改成【冲击波伤害的 20%】。
##   原写法「伤害 = maxHp/HP_MULT×pct，护盾 = maxHp×pct」差了整整 3 倍，
##   而文案写的是"等量" ⇒ 玩家看到的和实际拿到的对不上，且**看不出来**（刻度差，不是笔误）。
##   按伤害算之后文案与实装天然一致。

var battle

## 逐档：冲击波 = 自身最大生命的百分之几（真伤 + 自身护盾）
const WAVE_PCT := [0.04, 0.06, 0.08]
## 累计受到多少伤害放一次（用户 2026-08-03 定：400，固定值不随血量缩放）
const RAGE_THRESHOLD := 400.0
## 冲击波转护盾的比例（用户 2026-08-03 定：造成伤害的 20%）
const SHIELD_FROM_DMG := 0.20
## ★★2026-08-03 用户重定：**圣光护盾是一件【羁绊赠送的装备】**，不是档位上的被动。
##   · 3 档送 1 件、6 档送 2 件（`GameState.shield_grant_count`）
##   · 在背包里自由装配，**不占全队容量、也不占单只 3 件上限**（`GameState._cap_count` 跳过它）
##   · 属性 **+250 最大生命**
##   · **每 3 秒**为携带者生成 **55** 点圣光护盾值
##   · 圣光护盾存在时，**反击敌人的每段伤害造成 2 点真实伤害**
##   · **羁绊掉档就收回**（连装在龟身上的一起拿走）—— 它是羁绊的一部分，不是买来的
##   ⚠ 它**故意不给类型**：给"盾"就会「送盾 → 盾件数 +1 → 档位涨 → 再送盾」无限循环。
const HOLY_ITEM := "p2eq_095"
const HOLY_PERIOD := 3.0        # 每 3 秒
const HOLY_AMOUNT := 55.0       # 生成 55 点
const RIPOSTE_FLAT := 2.0       # 反击 2 点真伤（固定，不随件数放大）
## 9 档：盾在提供护盾/治疗时额外转成圣光护盾的比例 + 所有圣盾值加成
const T3_CONVERT := 0.20
const T3_SHIELD_BONUS := 0.20
## 收殓：敌方阵亡 → 最近的携带盾者获得该单位 N% 最大生命的护盾
const REAP_PCT := 0.30
## 收殓（敌亡给盾）从 6 档起（用户 2026-08-03：「6档时获得第二个圣光护盾且有敌人死亡给盾」）
const REAP_TIER := 2


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
	_riposte(u, src)          # ★反击的条件是"身上有圣光护盾【装备】且当前有护盾值", 与档位无关


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
	if not (t is Dictionary) or not (t as Dictionary).get("alive", false):
		return                    # ★没打出去就没有护盾 —— 护盾现在是【伤害的副产品】(见下)
	# ★除 HP_MULT: "自身 X% 最大生命 → 打给别人的伤害"(先例 equip_system.gd:428 哑铃)
	var dmg: int = maxi(1, int(float(u.get("maxHp", 0.0)) / battle.HP_MULT * pct))
	battle._damage._apply_damage_from(u, t, dmg, Color("#ffd93d"), 0.0, true)   # raw=true → 真实伤害
	# ★★2026-08-03 用户改: 护盾从「等量最大生命百分比」改成【冲击波伤害的 20%】。
	#   原写法 `maxHp × pct` 与伤害 `maxHp / HP_MULT × pct` 差了整整 HP_MULT(=3) 倍 ——
	#   文案说"等量"、实际护盾是伤害的 3 倍, 而玩家【完全看不出来】(刻度差造成的, 不是笔误)。
	#   改成按伤害算之后, 文案与实装天然一致, 也不再有那个隐形的 3 倍。
	#   ⚠ 取的是【算出来的伤害值】不是"实际扣掉的血": 目标带盾/免伤时实扣会更少,
	#     但那时护盾也跟着缩水会很难解释("我打满了却没盾")。按名义值走, 可预期。
	battle._damage._grant_shield(u, float(dmg) * SHIELD_FROM_DMG)


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
	if holy_count(u) <= 0:
		return                                      # 反击来自【圣光护盾装备】, 没装就没有
	if float(u.get("shield", 0.0)) <= 0.0:
		return                                      # 「圣光护盾存在时」—— 没盾不反击
	battle._damage._apply_damage_from(u, src, int(RIPOSTE_FLAT), Color("#ffe9a8"), 0.0, true)


## 身上装了几件【圣光护盾】装备
func holy_count(u: Dictionary) -> int:
	var n := 0
	for e in u.get("equips", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == HOLY_ITEM:
			n += 1
	return n


## 圣光护盾装备的周期护盾（每 3 秒 55 点 × 件数）。
## 9 档时所有圣盾值 +20%（用户 2026-08-03）。
var _t_holy := 0.0
func tick(delta: float) -> void:
	_t_holy += delta
	if _t_holy < HOLY_PERIOD:
		return
	_t_holy -= HOLY_PERIOD
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		var n: int = holy_count(u)
		if n <= 0:
			continue
		battle._damage._grant_shield(u, HOLY_AMOUNT * float(n) * holy_bonus(u))


## 9 档「圣盾值 +20%」
func holy_bonus(u: Dictionary) -> float:
	return 1.0 + (T3_SHIELD_BONUS if int(battle._synergy.tier_for(u, "盾")) >= 3 else 0.0)


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
