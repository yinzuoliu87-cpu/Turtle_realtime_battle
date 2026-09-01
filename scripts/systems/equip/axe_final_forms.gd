class_name AxeFinalForms
extends RefCounted
## 四个最终造物的行为 (2026-09-01·方案书六期)
##
## ★数值**全部**取自 `AxeFinalStats`，这里一个裸数字都不许有。
##
## ★★结算与演出分开（CLAUDE.md §3.5）：本文件里每个 `*_settle` / `*_tick` 都是
##   **纯结算**，门禁直接调它们喂数验；演出（环、回旋镖、法阵、处决闪光）在末尾调它们。
##   无头 CI 推不动 tween 链，把数值埋进演出末尾 = 本地永远复现不出来的红。
##
## ★★**不做死亡动画**（用户 2026-08-31 与 09-01 两次点名）。亡灵之斧的「死后重生」
##   靠状态机 + 特效表现，不加 death 动作帧；`verify_summon_art` 焊死了这条。
const AF := preload("res://scripts/gamedata/axe_final_stats.gd")
const AFV := preload("res://scripts/scenes/battle/axe_final_vfx.gd")

var battle = null
var vfx = null                            # 演出(axe_final_vfx.gd) —— **只画, 不结算**


func _init(b) -> void:
	battle = b
	vfx = AFV.new(b)


## 这只斧头的最终造物 key（""=还没选）。
## ★钉在召唤物身上而不是每次问 GameState —— 一路打到一半玩家在别处选了造物，
##   场上这只不该中途变身（它的血/攻是登场那一刻算的）。
func _fk(ax: Dictionary) -> String:
	return str(ax.get("_axe_final", ""))


# ══════════════════════════════════════════════════════════════
#  登场：把造物的属性折进召唤物
# ══════════════════════════════════════════════════════════════
## ★在 `_recalc_stats` **之前**调 —— 它改的是 base_*，要让重算把它们折进去。
func apply_stats(ax: Dictionary, final_key: String) -> void:
	if final_key == "" or not AF.STATS.has(final_key):
		return
	ax["_axe_final"] = final_key
	ax["maxHp"] = float(ax.get("maxHp", 0.0)) + AF.stat(final_key, "hp")
	ax["atk"] = float(ax.get("atk", 0.0)) + AF.stat(final_key, "atk")
	ax["base_def"] = float(ax.get("base_def", 0.0)) + AF.stat(final_key, "def")
	ax["base_mr"] = float(ax.get("base_mr", 0.0)) + AF.stat(final_key, "mr")
	var rng_add: float = AF.stat(final_key, "range")
	if rng_add > 0.0:
		## 炽天使「300码射程」—— 是**设成**300 不是加 300（近战 120 加 300 会变成 420）
		ax["atk_range"] = rng_add
		ax["melee"] = false
	var aspd: float = AF.stat(final_key, "aspd_pct")
	if aspd > 0.0:
		ax["aspd_perm"] = float(ax.get("aspd_perm", 1.0)) * (1.0 + aspd)
	var mv: float = AF.stat(final_key, "move_pct")
	if mv > 0.0:
		ax["move_perm"] = float(ax.get("move_perm", 1.0)) * (1.0 + mv)


# ══════════════════════════════════════════════════════════════
#  ① 亡灵之斧：300 码环 + 吸血 + 重生
# ══════════════════════════════════════════════════════════════
## 环这一跳的**纯结算**：环内每个敌人掉 1% 最大生命【魔法】，自己按人头回血。
## 返回环内敌人数（门禁拿它当分母）。
func undead_ring_tick(ax: Dictionary) -> int:
	if _fk(ax) != "undead" or not ax.get("alive", false):
		return 0
	var org: Vector2 = ax.get("pos", Vector2.ZERO)
	var hit: Array = []
	for o in battle._targeting._targetable_enemies(ax):
		if (o.get("pos", Vector2.ZERO) as Vector2).distance_to(org) <= AF.UNDEAD_RING_R:
			hit.append(o)
	for o in hit:
		var d: float = AF.undead_tick_dmg(float(o.get("maxHp", 0.0)))
		## ★★需求写的是**魔法伤害** ⇒ 必须吃魔抗，不逐件商量
		##   (memory [[fb-damage-type-is-wiring-not-color]]；权威 §7.5 已焊死)。
		##   ⚠ 但**光把 bucket 写成 "mag" 不够** —— `_apply_damage` 这条路
		##   根本不算抗性(护甲/魔抗只在 `_resolve_dmg` / `_phys_after_armor` /
		##   `_dot_after_resist` 里算)。门禁当场抓到: 0 魔抗和 200 魔抗都掉 1000。
		##   ⇒ 先过 `_dot_after_resist(magic=true)` 把数削好，再交给 `_apply_damage`。
		##   这也是本作 DoT 的标准做法(灼烧/中毒吃魔抗、流血吃护甲)。
		var after: int = battle._damage._dot_after_resist(o, d, true, ax)
		battle._damage._apply_damage(o, maxi(1, after), Color("#7ee081"), ax, "mag", false)
	if not hit.is_empty():
		battle._damage._heal(ax, AF.undead_leech(float(ax.get("maxHp", 0.0)), hit.size()))
		## ★演出**接在结算之后**(§3.5): 上面那行数值已经落定, 演出掉了也不影响正确性。
		for o2 in hit:
			vfx.undead_leech_line(o2.get("pos", Vector2.ZERO), ax.get("pos", Vector2.ZERO))
	return hit.size()


## 召唤物倒下时调。返回是否安排了重生。
## ★**不播死亡动画**（用户两次点名）——只记一个"什么时候站起来"的时刻。
func undead_on_death(ax: Dictionary) -> bool:
	if _fk(ax) != "undead":
		return false
	if bool(ax.get("_axe_revived", false)):
		return false                      # 一次战斗只重生一次
	ax["_axe_revive_at"] = float(battle._t) + AF.UNDEAD_REVIVE_DELAY
	return true


## 每帧推进重生。返回是否**在这一帧**站起来了。
func undead_tick_revive(ax: Dictionary) -> bool:
	if not ax.has("_axe_revive_at"):
		return false
	if float(battle._t) < float(ax["_axe_revive_at"]):
		return false
	ax.erase("_axe_revive_at")
	ax["_axe_revived"] = true
	ax["alive"] = true
	ax["hp"] = float(ax.get("maxHp", 0.0)) * AF.UNDEAD_REVIVE_HP_PCT
	ax["shield"] = 0.0
	ax["stun_until"] = 0.0
	vfx.undead_revive(ax.get("pos", Vector2.ZERO), 0.9)   # 亡魂聚拢再立起(不是死亡动画)
	return true


# ══════════════════════════════════════════════════════════════
#  ② 炽天使：普攻 8 层灼烧 + 主动 10 把回旋镖
# ══════════════════════════════════════════════════════════════
func seraph_on_hit(ax: Dictionary, tgt: Dictionary) -> int:
	if _fk(ax) != "seraph" or not (tgt is Dictionary) or not tgt.get("alive", false):
		return 0
	battle._damage._apply_dot_stacks(tgt, "burn", AF.SERAPH_BURN_ON_HIT, ax)
	return AF.SERAPH_BURN_ON_HIT


## 一把回旋镖的**纯结算**：沿 `dir` 直线飞过，半宽 300 码内的敌人各吃 1×ATK 魔法 + 8 层灼烧。
## 返回命中数。★门禁直接调它 —— 不等任何飞行 tween（§3.5 海盗钩索那条教训）。
func seraph_boomerang_settle(ax: Dictionary, dir: Vector2) -> int:
	if _fk(ax) != "seraph":
		return 0
	var d: Vector2 = dir.normalized()
	if d == Vector2.ZERO:
		return 0
	var org: Vector2 = ax.get("pos", Vector2.ZERO)
	var dmg: int = maxi(1, int(round(float(ax.get("atk", 0.0)) * AF.SERAPH_BOOM_ATK)))
	var n := 0
	for o in battle._targeting._targetable_enemies(ax):
		var rel: Vector2 = (o.get("pos", Vector2.ZERO) as Vector2) - org
		if rel.dot(d) < 0.0:
			continue                       # 只打身前那一侧（"直直飞过"是单向的）
		## 到飞行中线的横向距离 ——「半径大小为300码」当作这条线的作用半宽
		if absf(rel.dot(Vector2(-d.y, d.x))) > AF.SERAPH_BOOM_R:
			continue
		battle._damage._apply_damage(o, dmg, Color("#ffb347"), ax, "mag", false)
		if o.get("alive", false):
			battle._damage._apply_dot_stacks(o, "burn", AF.SERAPH_BOOM_BURN, ax)
		n += 1
	vfx.seraph_boomerang(org, d, AF.SERAPH_BOOM_R * 2.5, 0.45)   # 演出: 一把飞过去
	return n


# ══════════════════════════════════════════════════════════════
#  ③ 全息斧：普攻给最低血友军盾+龟能 / 插地法阵
# ══════════════════════════════════════════════════════════════
## 返回被照顾到的那个友军（null = 没有）。
func holo_on_hit(ax: Dictionary):
	if _fk(ax) != "holo":
		return null
	var best = null
	var best_r := 2.0
	for a in battle._targeting._allies_of(ax, true):
		if not a.get("alive", false):
			continue
		var mh: float = float(a.get("maxHp", 1.0))
		var r: float = float(a.get("hp", 0.0)) / maxf(1.0, mh)
		if r < best_r:
			best_r = r
			best = a
	if best == null:
		return null
	battle._damage._grant_shield(best, AF.HOLO_ONHIT_SHIELD)
	best["energy"] = minf(float(best.get("maxEnergy", 999999.0)),
		float(best.get("energy", 0.0)) + AF.HOLO_ONHIT_ENERGY)
	return best


## 法阵这一跳的**纯结算**：600 码内友军回血 + 给龟能 + 挂攻速。返回受益人数。
func holo_aura_tick(ax: Dictionary) -> int:
	if _fk(ax) != "holo":
		return 0
	var org: Vector2 = ax.get("pos", Vector2.ZERO)
	var n := 0
	for a in battle._targeting._allies_of(ax, true):
		if not a.get("alive", false):
			continue
		if (a.get("pos", Vector2.ZERO) as Vector2).distance_to(org) > AF.HOLO_AURA_R:
			continue                       # ★范围外的一律不许吃到（门禁专门量这条）
		battle._damage._heal(a, AF.HOLO_AURA_HEAL)
		a["energy"] = minf(float(a.get("maxEnergy", 999999.0)),
			float(a.get("energy", 0.0)) + AF.HOLO_AURA_ENERGY)
		## 攻速走既有的 haste 通道，到期自己失效（比自己再造一条通道稳）
		a["haste_mult"] = 1.0 + AF.HOLO_AURA_ASPD
		a["haste_until"] = float(battle._t) + AF.HOLO_AURA_TICK * 1.5
		n += 1
	return n


# ══════════════════════════════════════════════════════════════
#  ④ 余烬：种子层 + 处决 + 可叠加的余烬之光
# ══════════════════════════════════════════════════════════════
## 命中挂一层种子；顺带判处决。返回 {"stacks": 层数, "executed": 有没有处决掉}。
func ember_on_hit(ax: Dictionary, tgt: Dictionary) -> Dictionary:
	if _fk(ax) != "ember" or not (tgt is Dictionary) or not tgt.get("alive", false):
		return {"stacks": 0, "executed": false}
	var n: int = int(tgt.get("_ember_seeds", 0)) + AF.EMBER_SEED_PER_HIT
	tgt["_ember_seeds"] = n                # ★无上限（需求「无限叠加」）
	vfx.ember_seed(tgt, n)                 # 演出: 脚下火星, 浓度随层数(视觉 30 层封顶)
	var done := false
	if not tgt.get("eq_exec_immune", false) and AF.ember_should_execute(
			float(tgt.get("hp", 0.0)), float(tgt.get("maxHp", 0.0)), n):
		battle._damage._apply_damage(tgt, maxi(1, int(ceil(float(tgt.get("hp", 1.0))))),
			Color("#ff7043"), ax, "tru", false)
		done = true
		vfx.ember_execute(tgt.get("pos", Vector2.ZERO))
		if not tgt.get("alive", true):
			## 「处决一个单位会使召唤物获得150点龟能」
			ax["energy"] = minf(float(ax.get("maxEnergy", 999999.0)),
				float(ax.get("energy", 0.0)) + AF.EMBER_EXEC_ENERGY)
	return {"stacks": n, "executed": done}


## 放一次余烬之光。★★需求原话:「再次释放会提供一个新的余烬之光，**不会打扰到当前的buff**，
## 独立的4秒」⇒ 存的是**一串到期时刻**，不是一个"刷新"的字段。
## 只要串里还有没到期的，buff 就在。返回当前叠了几层。
func ember_light_cast(ax: Dictionary) -> int:
	if _fk(ax) != "ember":
		return 0
	var arr: Array = ax.get("_ember_lights", [])
	arr = arr.duplicate()
	arr.append(float(battle._t) + AF.EMBER_LIGHT_TIME)
	ax["_ember_lights"] = arr
	_ember_apply(ax)
	return ember_light_stacks(ax)


## 当前还在生效的余烬之光有几层（过期的自己掉）。
func ember_light_stacks(ax: Dictionary) -> int:
	var arr = ax.get("_ember_lights", null)
	if not (arr is Array):
		return 0
	var n := 0
	for t in (arr as Array):
		if float(t) > float(battle._t):
			n += 1
	return n


## 每帧：清掉过期的，并把 buff 状态同步到单位上。
func ember_light_tick(ax: Dictionary) -> void:
	var arr = ax.get("_ember_lights", null)
	if not (arr is Array) or (arr as Array).is_empty():
		return
	var keep: Array = []
	for t in (arr as Array):
		if float(t) > float(battle._t):
			keep.append(t)
	ax["_ember_lights"] = keep
	_ember_apply(ax)


## 把"有没有余烬之光"翻译成单位身上的实际字段。
## ★**不叠乘**：需求说的是"再来一个独立的 4 秒"，不是"效果翻倍" ——
##   多层只延长在线时间，不加强数值。这条最容易做反，门禁专门验。
func _ember_apply(ax: Dictionary) -> void:
	var on: bool = ember_light_stacks(ax) > 0
	ax["lifesteal"] = AF.EMBER_LIGHT_LIFESTEAL if on else 0.0
	ax["damage_reduction"] = AF.EMBER_LIGHT_DR if on else 0.0
	ax["haste_mult"] = (1.0 + AF.EMBER_LIGHT_ASPD) if on else 1.0
	ax["haste_until"] = (float(battle._t) + 0.2) if on else 0.0
	ax["cc_immune"] = on                   # 「免疫控制」
	if on:
		ax["stun_until"] = 0.0
