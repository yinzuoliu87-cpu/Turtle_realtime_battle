class_name SwordsmanSystem
extends RefCounted
## 剑羁绊【剑士】追打（用户 2026-08-03 定，取代原设计里的「回响」）。
##
## 规格：**剑的携带者每次普攻后**，再以 `18% / 25% / 40% × 身上剑的件数` 的伤害
## 打出 **1 / 1 / 2** 次追打，追打**以 5 倍攻速节奏打出**并**触发 onhit 效果**。
##
## ══════════════════════════════════════════════════════════════════════
##  ★★三条规则（① ② 防无限递归 · ③ 是平衡决定）
## ══════════════════════════════════════════════════════════════════════
## **① 追打【不走 `_basic_attack`】，只走「伤害 + onhit」。**
##   走 `_basic_attack` 会同时点燃两条链：
##   · **自递归**：追打 → `_eq_on_basic_attack` → 又排 N 次追打 → 无限。
##   · **赌神龟连击**：`gambler` 的"多重打击"实现是【把下次普攻的冷却缩短】
##     （`gambler_system.gd:17` `_gambler_multi_cd`，40/60/80% 概率、连锁 ×0.8 递减、~6 倍攻速）。
##     它的每一发连击都是一次完整 `_basic_attack` ⇒ 若追打也走那条路，
##     赌神会为每一次追打【再掷一次连击骰】，两个"云顶剑士式连击"互相喂 ⇒ 组合爆炸。
##   ⇒ 追打直接调 `_apply_damage_from`，绕开 `_basic_attack` 与 `_eq_on_basic_attack`。
##     （on-hit 由 `_apply_damage_from` 内部回钩，**不要在外面再调一次** ——
##       2026-08-05 前这里多调了一次，导致每发追打把 on-hit 点了两次。详见 tick() 里的注释）
##
## **② 追打触发的 onhit【不再触发剑士】。**
##   `双生匕首(005)` 3★ 是「每段伤害命中后 **100%** 追加一刀」——
##   若那一刀又算作"普攻"去点剑士，就是第二条无限链。①已经堵住了这条
##   （追打不经过 `_eq_on_basic_attack`），这里再用 `_sw_busy` 标记做一道显式保险，
##   因为将来若有人把追打改成走普攻入口，①的保护会静默消失而这道不会。
##
## **③ 连击产生的普攻【不触发剑士】**（用户 2026-08-03 拍板）。
##   赌神龟自己就是"云顶剑士式连击"，两个连击机制相乘 ⇒ 实测赌神拿满剑 = 普通龟的 **2.1 倍**
##   （每秒伤害 576% vs 272%），剑这条羁绊会变成"赌神专属"。
##   ⇒ 只有**链的第一发**（正常节奏那一下）触发剑士，后续连击一律不触发。
##   ★注意这与 ①② 不同：①② 是防无限递归（不做会卡死），③ 是**平衡决定**（不做只是失衡）。
##
## ★为什么用「延迟队列」而不是当场连打完：规格写的是"以 5 倍攻速打出"，
##   即两次追打之间有 `攻击间隔 / 5` 的真实时间差。当场打完会让飘字与音效叠在同一帧，
##   看起来就是一次伤害翻倍，而不是"连斩"。

var battle

## 逐档：追打次数 / 每次伤害占普攻的比例（再乘携带者身上的剑件数）
const HITS := [1, 1, 2]
const PCT := [0.18, 0.25, 0.40]
const ASPD_MULT := 5.0        # 追打节奏 = 攻击间隔 / 5

## 待发的追打：[{"src":单位, "tgt":单位, "t":发射时刻, "pct":伤害比例}]
var _pending: Array = []


func _init(b) -> void:
	battle = b


## 每次普攻时调（挂 `_eq_on_basic_attack` —— 它在 `_basic_attack` 的【所有特殊龟 early return 之前】，
## 是唯一一个每只龟都会经过的普攻钩；挂函数末尾会漏掉闪电/龟壳/精英/宝箱/双头/幽灵/赛博/熔岩这一大票）。
func on_basic_attack(u: Dictionary, tgt) -> void:
	if not (tgt is Dictionary) or not (u is Dictionary):
		return
	if u.get("_sw_busy", false):
		return                                  # ★防爆规则②：追打自身产生的命中不再点燃剑士
	if u.get("_chained_atk", false):
		# ★防爆规则③（用户 2026-08-03 拍板）：**连击产生的普攻不触发剑士**。
		#   赌神龟(gambler)本身就是"云顶剑士式连击"(掷中→以 ~6 倍攻速再打一发, 链式 ×0.8 递减),
		#   它的每一发连击都是完整 _basic_attack ⇒ 若都触发剑士, 实测赌神拿满剑 = 普通龟的 2.1 倍
		#   (576% vs 272% 每秒伤害)。两个连击机制相乘, 剑这条羁绊会变成"赌神专属"。
		#   ⇒ 只放行【链的第一发】(正常节奏那一下), 后续连击一律不触发。
		#   标记写在 gambler_system._gambler_multi_cd —— 掷中时置 true, 链断时置 false。
		return
	var tier: int = int(battle._synergy.tier_for(u, "剑"))
	if tier <= 0:
		return
	var n_sword := 0
	for e in u.get("equips", []):
		if e is Dictionary and battle.Phase2Types.type_of(str(e.get("id", ""))) == "剑":
			n_sword += 1
	if n_sword <= 0:
		return                                  # 剑士只给【携带剑的人】，不是全队
	var ti: int = clampi(tier - 1, 0, 2)
	var pct: float = PCT[ti] * float(n_sword)
	var iv: float = float(u.get("atk_interval", 1.25)) / ASPD_MULT
	for k in range(HITS[ti]):
		_pending.append({"src": u, "tgt": tgt, "t": battle._t + iv * float(k + 1), "pct": pct})


## 每帧推进（挂 `_sim_step`）。★用战斗时钟 `battle._t` 不用墙钟 —— 顿帧/暂停时追打也该跟着停。
func tick(_delta: float) -> void:
	if _pending.is_empty():
		return
	var keep: Array = []
	for p in _pending:
		if battle._t < float(p["t"]):
			keep.append(p)
			continue
		var src: Dictionary = p["src"]
		var tgt: Dictionary = p["tgt"]
		if not src.get("alive", false) or not tgt.get("alive", false):
			continue                            # 谁死了就作废，不补刀
		src["_sw_busy"] = true                  # ★进入追打：期间产生的普攻钩一律不点燃剑士
		var dmg: int = battle._atk_dmg(src, float(p["pct"]), tgt)
		# ★追打【照常吃 on-hit】（用户明确要）：流血/溅射/连锁/标记这些都吃。
		#   ⚠ 但它【不】触发 _eq_on_basic_attack —— 那条是"每普攻一次"的计数钩
		#   （008 珊瑚刺每 5 次普攻、017 不沉之锚每普攻消耗充能），追打不该给它们刷次数。
		#   ⇒ 靠 `_sw_busy` 挡住, 不是靠绕开这条伤害路径。
		#
		# ★★2026-08-05 删掉了这行后面原本显式的 `_eq_on_hit(src, tgt, dmg)` ——
		#   它是**重复的**: `_apply_damage_from` 的 `from_equip` 默认 false,
		#   内部那段(battle_damage.gd:259) 已经调过 _eq_on_hit 了。
		#   ⇒ 一次追打把 on-hit 点了【两次】, 一次普攻 = 1 + 2x2 = **5 次 on-hit 事件**(应为 3)。
		#   影响的不止某一件装备, 是**所有 on-hit 装备**(流血叠层/005 双刃/各种充能计数)
		#   在剑阵容里全部按双倍速率跑。弓/药水/奇械/法器没这问题(它们只在内部那段挂了一次)。
		battle._damage._apply_damage_from(src, tgt, dmg, Color("#ffd27f"))
		src["_sw_busy"] = false
	_pending = keep


## 换路 / 重开时清空 —— 单位字典会被整个重建，留着旧引用就是悬空引用。
func clear() -> void:
	_pending.clear()
