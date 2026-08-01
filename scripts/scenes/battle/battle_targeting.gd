class_name BattleTargeting
extends RefCounted
## 目标选择/敌我查询(最近敌/获取目标/敌方/友方/可选目标·纯确定性查询无RNG)
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _nearest_enemy_for_trainer(u: Dictionary):
	var best = null
	var best_d = battle.TRAINER_RANGE * battle.TRAINER_RANGE
	for o in battle._units:
		if not o.get("alive", false) or not battle._is_hostile(u, o):
			continue
		if o.get("is_trainer", false):
			continue   # 训龟大师之间不互殴(都是场外监视者)
		if battle._t < float(o.get("untargetable_until", 0.0)):
			continue
		var dd: float = (o["pos"] - u["pos"]).length_squared()
		if dd < best_d:
			best_d = dd; best = o
	return best


## 播扔石头动作(一次性, 播完自动回 idle/run — 走 anim_action 白名单)
# --- 索敌: 被嘲讽则强制打嘲讽来源, 否则最近敌 (跳过 untargetable / 缩头护身随从) ---
func _acquire_target(u: Dictionary):
	# ★嘲讽分支必须再过一遍 battle._is_hostile: 它原先绕过一切阵营判定, 于是
	#   "侵入前嘲讽过赛博方的单位, 被侵入后赛博方仍死锁着它" / "归队瞬间还锁着新队友"
	#   都会出现同阵营互殴(伤害层没有友伤闸)。见 §HOSTILE
	if battle._t < u["taunt_until"] and u["taunt_by"] != null and u["taunt_by"]["alive"] and battle._is_hostile(u, u["taunt_by"]):
		return u["taunt_by"]
	return _nearest_enemy(u)

# ----------------------------------------------------------------------------
#  §HOSTILE — 统一敌我判定原语 (2026-07-22)
#
#  ★为什么必须有这个函数: 在它之前, 全工程【零个敌我原语】, 敌我判断散在 20 处、
#    清一色只写 `o["side"] != u["side"]`。赛博龟侵入需要【不对称敌我】——
#    被侵入者对所有人都是敌人, 但它自己只打原队友 —— 用 side 一个字段表达不了,
#    所以旧实现只能去【改写 side】, 结果把它变成了赛博方的"真友军"(赛博全队打不到它,
#    还会给它加治疗), 与权威文档 28龟技能设计-权威.md:1467「不算友军·会被打」相反。
#
#  ★口径(用户 2026-07-22 拍板, 已用他的例子验算):
#      我方=赛博+2友军, 敌方仅 1 个被侵入单位 →
#        赛博/友军1/友军2 → 都打被侵入者 ✅
#        被侵入者 → 无目标 = 站着发呆 ✅   (它只打原队友, 而原队友已没了)
#      治疗/护盾: 被侵入者对谁都不是友军 = 孤军
#
#  ★side 全程不动。这样"死亡不归队 / 跨路串阵营 / 单路瞬间判胜 / 召唤物串队"
#    这四类问题根本不会发生 —— 它们全都源于改写 side。
#
#  ★注意: 全工程另有 29 处 `side == "left"` 是在判【是不是玩家方】(UI 配色/技能选择/
#    局外数据), 不是敌我逻辑, 一律不要改成 battle._is_hostile。
# ----------------------------------------------------------------------------

## a 会不会攻击 b。★不对称: battle._is_hostile(a,b) 与 battle._is_hostile(b,a) 可以不同。
func _nearest_enemy(u: Dictionary):
	var best = null
	var best_d = INF
	for o in battle._units:
		if not battle._is_hostile(u, o) or not o["alive"]:   # ★原为 o["side"] == u["side"], 见 §HOSTILE
			continue
		if battle._t < o["untargetable_until"]:   # 黑洞 → 不可被选
			continue
		if o.get("_egg_fence", false):   # 龟蛋围栏未破 → 不可被主动索敌(但AoE/增益穿栏, 走_enemies_of不受此限)
			continue
		if o.get("is_trainer", false):   # 训龟大师: 不被【主动索敌】(用户2026-07-22)
			# ★只挡这一条路 —— AoE 走 _enemies_of, 那里【故意不跳过】它, 所以照样吃到范围伤害。
			#   两条路天然分离, 正好对上"不会被主动索敌但会吃到aoe伤害"。
			continue
		var dd: float = (o["pos"] - u["pos"]).length_squared()
		if dd < best_d:
			best_d = dd; best = o
	return best

# 每单位每帧: DoT 落血 / buff 到期清理 / 层数DoT结算 / 召唤体周期特殊技 / 周期被动 (1:1 2D _tick_effects)
func _enemies_of(u: Dictionary) -> Array:
	var out: Array = []
	for o in battle._units:
		if battle._is_hostile(u, o) and o["alive"]:   # ★原为 o["side"] != u["side"], 见 §HOSTILE
			if o.get("_egg_fence", false): continue   # 围栏未破的蛋: 单体+AoE都不锁(用户2026-07-12: 珊瑚刺等别锁蛋)
			out.append(o)
	return out

## §PICK-TARGET 集中"可被定向选取"的敌人闸门(用户2026-07-23 点4)。
## = _enemies_of 再排除【训龟大师(场外监视者: 只吃 AOE 波及、不被单体/定向锁)】+【不可选中(含机甲 5 秒组装期 untargetable_until/_assembling)】。
## ★用法铁律: 凡"随机挑一个 / 最近一个 / 单体指向"的技能选目标都走【这个】;
##   真 AOE(龟派气波、激光竖劈 _equip_sys._eq_laser_chop、扇形波及等"范围扫到谁算谁")仍用 _enemies_of —— 那才是"大师只吃 AOE 溅射"的语义。
## ★非伤害效果(处决/击飞/位移/驱散)也必须走这个 —— 光挡伤害不够(大师"伤害降为1"挡不住处决/击飞)。
## 机甲死亡激光那类"选一个敌人朝它拉一条线"的定向技: 用这个选目标(不选大师), 但线扫过大师仍在 _apply_damage 里结算(吃1)。
func _pick_enemies_of(u: Dictionary) -> Array:
	var out: Array = []
	for o in _enemies_of(u):
		if o.get("is_trainer", false):
			continue
		if battle._is_untargetable(o):
			continue
		out.append(o)
	return out

## 均分型护盾/团队份额的受益名单: 排除【训龟大师】与【龟蛋】——
##   两者都是"占着人头却把盾摊薄"的非战斗单位: 大师是场外监视者、龟蛋不动不攻击且已自带围栏 200 双抗。
## ★只给【均分/按人头分摊】的效果用(铁壁盾 016、温泉蛋孵化盾 036); "给全队罩个盾"之类无所谓不用换。
## 用户 2026-07-23 点4 先排了大师; 2026-08-01 补排龟蛋(原话:「铁壁盾分摊不应该包括龟蛋和训龟大师，温泉蛋也是」)。
## ★改名自 _allies_no_trainer: 名字得说实话 —— 现在排的不只大师, 叫 no_trainer 会误导下一个改它的人。
func _allies_share_pool(u: Dictionary) -> Array:
	var out: Array = []
	for o in _allies_of(u):
		if o.get("is_trainer", false):
			continue
		if o.get("_isEgg", false):
			continue
		out.append(o)
	return out

func _targetable_enemies(u: Dictionary) -> Array:
	var out: Array = []
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if o.get("_egg_fence", false): continue
		if battle._t < float(o.get("untargetable_until", 0.0)): continue
		if o.get("is_trainer", false): continue   # ★大师不可主动锁(用户2026-07-23 点4: 只吃AOE波及)
		out.append(o)
	return out

## 当前【输出最高】的友军 —— 输出以 攻击力 ÷ 攻击间隔 (=每秒攻击力) 排, 不是裸攻击力:
## 攻速差在本项目里最大到 0.60 vs 0.85(近1.4倍), 只比攻击力会把慢攻速的坦克误判成输出位。
## 召唤物/小将也算(它们可能就是当前真输出), 但排除不会普攻的(no_basic: 海盗船/水晶球那类)。
## 用户 2026-07-28: 天使祝福从「最低血友军」改投这里 —— 原设定在实测里几乎总是把盾和攻速
## 加成给了没有技能的陪跑小将, 等于浪费。
func _top_dps_ally(u: Dictionary, include_self: bool = true):
	var best = null
	var bv := -1.0
	for o in _allies_of(u, include_self):
		if not o.get("alive", false) or bool(o.get("no_basic", false)):
			continue
		var iv: float = maxf(0.05, float(o.get("atk_interval", 1.0)))
		var dps: float = float(o.get("atk", 0.0)) / iv
		if dps > bv:
			bv = dps
			best = o
	return best

func _allies_of(u: Dictionary, include_self: bool = true) -> Array:
	var out: Array = []
	for o in battle._units:
		# ★原为 o["side"] == u["side"]。改用 battle._is_ally(双向都不敌对) → 被侵入者是孤军:
		#   赛博方不会给它加治疗/护盾, 它也不给赛博方加。见 §HOSTILE
		if not o["alive"]:
			continue
		if is_same(o, u):          # is_same: 单位字典互引成环, ==/!= 会深比较→卡死(同053教训)
			if include_self:
				out.append(o)
			continue
		if battle._is_ally(u, o):
			out.append(o)
	return out

# ============================================================================
#  被动系统: 登场被动 / on-hit / 周期被动 (1:1 搬自 2D 版)
# ============================================================================
# 召唤体永远主动平A不放技能; 选被动的龟(暂无)也不放. demo 默认全选主动.
