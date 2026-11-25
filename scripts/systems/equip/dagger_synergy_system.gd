class_name DaggerSynergySystem
extends RefCounted
## 匕首羁绊【刺杀】(2026-11-25 · 方案书 docs/plans/20261125-匕首羁绊.md §4.1)
##
## 用户 11-25:「战斗开始时，我方所有友方单位打出了第一次攻击，并暴击…除必定暴击之外，这一击还会获得百分之二十五、
##   百分之五十五、百分之八十的暴击伤害，与百分之二十的生命偷取，然后如果升到二档的话…这个效果会在第十秒后再触发一次…
##   如果到了三档的话，就是相当于再过十秒之后又有这个效果」
##
## ── 规则 ─────────────────────────────────────────────────────────────
## · 每一路(上路 / 下路 / 决胜)各自计时: `battle._sd_t0` 是这一路开打那一刻(`_t` 跨路累加, CLAUDE.md §4.4)。
## · 触发 = 给这一方【所有存活友方单位】挂上「下一次普攻强化」(`_assassin_ready` = 额外暴伤);
##   一档开打时触发一次, 二档另在第 TRIGGER_GAP 秒, 三档再另在第 2×TRIGGER_GAP 秒(档位 = 触发次数)。
## · 强化的那一击(只算普攻, 方案书 §4.1 口径): 必定暴击, 暴击伤害另加 EXTRA_CRIT_DMG[档], 额外生命偷取 LIFESTEAL。
##   上一次没打出去时再触发 ⇒ 不叠加(仍只强化下一击, 额外暴伤按当前档)。
## · 消费点: 主场景 `_basic_attack` 把 ready 移成 now(这一下普攻范围内有效) → `_resolve_dmg` 强制暴击 + 加暴伤
##   → `_emit_basic` / 弹道命中带上额外吸血; 普攻结束清掉 now。
## · 龟蛋 / 训龟大师不挂。属性: 每件匕首给携带者暴击伤害(Phase2Types.TYPES["匕首"], 逐档)。
const TRIGGER_GAP := 10.0
const EXTRA_CRIT_DMG := [0.25, 0.55, 0.80]
const LIFESTEAL := 0.20

var battle
var _lane_t0 := -1.0
## 本路每方已触发到第几次(0 = 还没触发)
var _fired := {"left": 0, "right": 0}
## 门禁量: 本进程挂过几次「下一击强化」、打出过几次
var armed := 0
var struck := 0


func _init(b) -> void:
	battle = b


func side_tier(side: String) -> int:
	var t := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			t = maxi(t, int(battle._synergy.tier_for(u, "匕首")))
	return t


func tick(_dt: float) -> void:
	var t0 := float(battle._sd_t0)
	if t0 != _lane_t0:
		_lane_t0 = t0
		_fired = {"left": 0, "right": 0}
	if bool(battle.get("_over")):
		return
	var el := float(battle._t) - t0
	for side in ["left", "right"]:
		var tier := side_tier(side)
		if tier <= 0:
			continue
		var n := int(_fired[side])
		if n >= tier or el < TRIGGER_GAP * float(n):
			continue
		_fired[side] = n + 1
		_arm(side, tier)


## 给这一方所有存活友方单位挂「下一次普攻强化」
func _arm(side: String, tier: int) -> void:
	var extra: float = float(EXTRA_CRIT_DMG[clampi(tier, 1, 3) - 1])
	var who: Array = []
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false) or str(u.get("side", "")) != side:
			continue
		if bool(u.get("_isEgg", false)) or battle._is_untouchable(u):
			continue
		u["_assassin_ready"] = extra
		armed += 1
		who.append(u)
	var v = _vfx()
	if v != null and v.has_method("assassin_arm"):
		v.assassin_arm(who)


## 主场景 `_basic_attack` 开头调: ready → now(只在这一下普攻里有效)
static func begin_basic(u: Dictionary) -> void:
	var r: float = float(u.get("_assassin_ready", 0.0))
	if r > 0.0:
		u["_assassin_now"] = r
		u.erase("_assassin_ready")


## 主场景 `_basic_attack` 末尾调(所有提前返回也经过这里, 见主场景包装)
func end_basic(u: Dictionary, tgt) -> void:
	if u.has("_assassin_now"):
		u.erase("_assassin_now")
		struck += 1
		var v = _vfx()
		if v != null and v.has_method("assassin_strike") and tgt is Dictionary:
			v.assassin_strike(u, tgt)


## `_resolve_dmg` 里调: 这一下是不是强化击; 是 ⇒ 返回额外暴伤(> 0)
static func extra_crit(u: Dictionary) -> float:
	return float(u.get("_assassin_now", 0.0))


## 普攻 / 弹道的额外吸血
static func extra_ls(u) -> float:
	return LIFESTEAL if (u is Dictionary and float((u as Dictionary).get("_assassin_now", 0.0)) > 0.0) else 0.0


func reset_match() -> void:
	_lane_t0 = -1.0
	_fired = {"left": 0, "right": 0}


func _vfx():
	var es = battle.get("_equip_sys")
	return es._dagger_sys.vfx if es != null and es.get("_dagger_sys") != null else null
