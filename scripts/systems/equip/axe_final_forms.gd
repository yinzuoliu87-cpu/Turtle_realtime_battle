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
const ASV := preload("res://scripts/scenes/battle/axe_seraph_vfx.gd")

var battle = null
var vfx = null                            # 演出(axe_final_vfx.gd) —— **只画, 不结算**
var seraph_vfx = null                     # 炽天使回旋镖演出(axe_seraph_vfx.gd) —— 同样只画
## 在途回旋镖(炽天使主动)。每条是一个记录字典, 见 `seraph_boomerang_launch`。
## ★记录里的 src / cands / hits 装的是单位字典: 只当【值】存, 比较一律 is_same / _arr_has_unit(CLAUDE.md §3.2)。
var _booms: Array = []


func _init(b) -> void:
	battle = b
	vfx = AFV.new(b)
	seraph_vfx = ASV.new(b)


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
	## ★★全息斧「**50%龟能充能速率**」—— 数值表里躺了一天、**零消费者**,
	##   2026-09-01 逐条对用户原话时抓到。引擎里充能速率的字段是 `echarge_perm`
	##   (主场景龟能 tick: `cds[k] -= delta * _ecm * echarge_perm * _ts_echarge`)。
	var er: float = AF.stat(final_key, "energy_rate_pct")
	if er > 0.0:
		ax["echarge_perm"] = float(ax.get("echarge_perm", 1.0)) * (1.0 + er)
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
	## ★环的**视觉**要跟着斧头走。它是常驻场, 但斧头在移动 ⇒ 每跳重建一次最省事
	##   (每秒一次, 开销可忽略), 比自己维护一个跟随节点少一整类"没跟上/没释放"的 bug。
	##   ⚠ 之前 `undead_ring` 是**零调用者** —— 环写好了但场上根本看不见, 是
	##   tools/zero_caller_audit.py 抓到的。
	var _rn = vfx.undead_ring(ax, AF.UNDEAD_RING_R)
	if _rn != null:
		vfx.fade_and_free(_rn, AF.UNDEAD_RING_TICK)
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
	## ★★把 `_kill` 做过的事撤回来(第十批 E3) —— 只改 alive 会得到一把【看不见、打不死】的斧头:
	##   · `_dead_done` 是 `_kill` 的防重入守卫, 不清掉的话再挨到 0 血 `_kill` 第一行就 return;
	##   · `_kill` 把立绘淡到 0 再 hide, 影子 / 环 / 接触影 hide, 血条 visible = false。
	##   影子透明度由渲染每帧按 SHADOW_BASE_A 重设, 环与接触影本来就是 0 透明 ⇒ 这里只负责重新显示。
	ax.erase("_dead_done")
	for _k in ["sprite", "shadow", "ring", "contact"]:
		var _nd = ax.get(_k, null)
		if is_instance_valid(_nd):
			_nd.visible = true
	var _spr = ax.get("sprite", null)
	if is_instance_valid(_spr):
		_spr.modulate.a = 1.0
	if is_instance_valid(ax.get("bar_root", null)):
		ax["bar_root"].visible = true
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


## ── 回旋镖(2026-09-15 重做: 飞出去 → 折返 → 飞回斧头, 经过时结算) ──────────────
## 用户:「7/9的回旋镖同样是在敷衍我啊，回旋镖是什么？以及特效和实际伤害范围完全不一样啊，也没有命中特效」
## ★原来的 `seraph_boomerang_settle` 在【出手当帧】把身前半宽 300 码、不限长的带里所有敌人一次打完,
##   演出是一根小方块直线飞 0.45 秒不回来 —— 伤害与演出脱节。现在拆成两半:
##   · `seraph_boomerang_launch`(出手): 只登记在途, 定下【命中名单】与【飞出距离】, **不结算**;
##   · `tick_boomerangs`(每个模拟步, 挂 EquipSystem.tick_global): 推进路径, 用「上一步中心 → 这一步中心」
##     这段折线扫, 敌人中心到线段 ≤ SERAPH_BOOM_R 就命中。
## ★数值与目标集合一个不动:
##   · 名单 = 出手时在【身前】那一侧的可选中敌人(rel·dir ≥ 0, 相对出手点) —— 镖是圆的,
##     不许因此把身后 300 码内的也打了(保持原「单向」的目标集合);
##   · 飞出距离 = max(SERAPH_BOOM_MIN_OUT, 身前判定带里最远那个的纵深) ⇒ 原来打得到的, 现在镖真的飞到
##     (第十批 E10 那条「1300 码外挨打却看不到镖」在这里从根上没了: 不再有"演出长度"与"判定长度"两个数);
##   · 每把每个敌人只吃一次(去程或回程先碰到的那次) —— 回程再打一遍 = 伤害翻倍 = 擅自改数值;
##   · 伤害 = 出手时 1×ATK 魔法(先过魔抗再 `_apply_damage`, 同亡灵环) + 8 层灼烧, 与原来完全一样。
## ★源头离场(换路 / 战斗结束, 斧头从 `battle._units` 里消失) ⇒ 整条作废并收掉节点(照 eq_bow_batch._alive_here);
##   斧头只是死了不作废, 回程飞回出手点。

## 出手: 登记一把在途回旋镖。返回在途记录(没甩出去 = 空字典)。
## 记录字段: src 斧头 / org 出手点 / dir 方向 / out 飞出距离 / dmg 出手时的伤害 / cands 身前名单 / hits 已命中 /
##   pos 当前中心 / flown 去程已飞 / back 在回程 / done 已飞回 / t 已飞秒数 / node 镖身节点。
## ★不结算 —— 门禁专门量「出手当帧敌人不掉血」。
func seraph_boomerang_launch(ax: Dictionary, dir: Vector2) -> Dictionary:
	if _fk(ax) != "seraph":
		return {}
	var d: Vector2 = dir.normalized()
	if d == Vector2.ZERO:
		return {}
	var org: Vector2 = ax.get("pos", Vector2.ZERO)
	var cands: Array = []
	var out: float = AF.SERAPH_BOOM_MIN_OUT
	for o in battle._targeting._targetable_enemies(ax):
		var rel: Vector2 = (o.get("pos", Vector2.ZERO) as Vector2) - org
		if rel.dot(d) < 0.0:
			continue                       # 只打身前那一侧(单向的目标集合)
		cands.append(o)
		## 到飞行中线的横向距离 ≤ 半宽 = 原判定带覆盖到的那个 ⇒ 镖至少要飞到它的纵深
		if absf(rel.dot(Vector2(-d.y, d.x))) <= AF.SERAPH_BOOM_R:
			out = maxf(out, rel.dot(d))
	var rec := {
		"src": ax, "org": org, "dir": d, "out": out,
		"dmg": maxi(1, int(round(float(ax.get("atk", 0.0)) * AF.SERAPH_BOOM_ATK))),
		"cands": cands, "hits": [],
		"pos": org, "flown": 0.0, "back": false, "done": false, "t": 0.0,
		"node": seraph_vfx.boom_spawn(org),
	}
	_booms.append(rec)
	## ★斧头本体的【甩】动作帧 —— 每把一次(4 秒 10 把 ⇒ 每 0.4 秒), fps 就是按这个定的。
	##   在此之前斧头是站着不动把 10 把镖变出来的(当时的人形素材 eq-axe-throw.png 零调用者; 2026-09-15 起换成悬空 3D 斧, 按形态取 eq096-axe-<形态>-throw.png, 见 AxeArt)。
	_play(ax, "axe_throw")
	return rec


## 每个模拟步推进全部在途回旋镖(EquipSystem.tick_global → AxeSystem.tick_global → 这里)。
## 返回这一步新命中的人次(门禁拿它当分母)。
## ★挂 tick_global 而不是每携带者的 `AxeSystem.tick`: 后者在斧头死后第一行就 return, 而镖要飞回出手点;
##   时停期间 tick_global 整块不跑 ⇒ 在途镖与火花天然冻住。
func tick_boomerangs(delta: float) -> int:
	seraph_vfx.tick(delta)
	if _booms.is_empty():
		return 0
	var dt: float = maxf(0.0, delta)
	var n := 0
	var keep: Array = []
	## ★先把表摘下来再遍历: 结算里可能打死人 → 死亡链上的钩子万一又甩出新镖, 不许改正在遍历的数组
	var cur: Array = _booms
	_booms = []
	for rec in cur:
		if not battle._arr_has_unit(battle._units, rec["src"]):
			seraph_vfx.boom_free(rec.get("node", null))   # 源头离场: 整条作废, 不许打到新一路的单位
			continue
		var pts: Array = _boom_advance(rec, AF.SERAPH_BOOM_SPEED * dt)
		n += _boom_sweep(rec, pts)
		rec["t"] = float(rec["t"]) + dt
		seraph_vfx.boom_step(rec.get("node", null), rec["pos"], float(rec["t"]))
		if bool(rec["done"]):
			seraph_vfx.boom_free(rec.get("node", null))   # 飞回斧头: 收掉
			continue
		keep.append(rec)
	keep.append_array(_booms)
	_booms = keep
	return n


## 沿「出手点 → 最远处 → 斧头」前进 `step` 码。返回这一步走过的折线顶点(第一个 = 上一步的中心)。
## ★折返点落在这一步中间时, 顶点里带上折返点 —— 否则扫的是一条抄近路的弦, 最远处那个人会被漏掉。
## ★回程终点每步现读: 斧头活着 = 它【当前】的位置(它在走), 死了 = 出手点。
func _boom_advance(rec: Dictionary, step: float) -> Array:
	var pts: Array = [rec["pos"]]
	var left: float = step
	if not bool(rec["back"]):
		var remain: float = float(rec["out"]) - float(rec["flown"])
		if left < remain:
			rec["flown"] = float(rec["flown"]) + left
			rec["pos"] = (rec["org"] as Vector2) + (rec["dir"] as Vector2) * float(rec["flown"])
			pts.append(rec["pos"])
			return pts
		rec["flown"] = float(rec["out"])
		rec["pos"] = (rec["org"] as Vector2) + (rec["dir"] as Vector2) * float(rec["out"])
		rec["back"] = true
		pts.append(rec["pos"])
		left -= remain
	var src: Dictionary = rec["src"]
	var home: Vector2 = rec["org"]
	if src.get("alive", false):
		home = src.get("pos", home)
	var to_home: Vector2 = home - (rec["pos"] as Vector2)
	if to_home.length() <= left:
		rec["pos"] = home
		rec["done"] = true
	else:
		rec["pos"] = (rec["pos"] as Vector2) + to_home.normalized() * left
	pts.append(rec["pos"])
	return pts


## 扫这一步走过的折线: 名单里还没吃过这把的敌人, 中心到任一段 ≤ 半宽 ⇒ 结算。返回命中数。
func _boom_sweep(rec: Dictionary, pts: Array) -> int:
	if pts.size() < 2:
		return 0
	var src: Dictionary = rec["src"]
	var n := 0
	for o in battle._targeting._targetable_enemies(src):
		if not battle._arr_has_unit(rec["cands"], o) or battle._arr_has_unit(rec["hits"], o):
			continue                       # 不在出手时的身前名单 / 这把已经打过它(每把每敌一次)
		var p: Vector2 = o.get("pos", Vector2.ZERO)
		var near := false
		for i in range(pts.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) <= AF.SERAPH_BOOM_R:
				near = true
				break
		if not near:
			continue
		(rec["hits"] as Array).append(o)
		## ★★「1ATK**魔法**伤害」必须吃魔抗(memory: 伤害类型是接线不是颜色, 没有例外)。
		##   `_apply_damage` 这条路**不算抗性** —— 先过 `_dot_after_resist(magic=true)` 再交给它(同亡灵环;
		##   2026-09-01 回旋镖漏过一次: 全仓 4 个 "mag" 调用点里唯一没预削的那个)。
		var after: int = battle._damage._dot_after_resist(o, float(rec["dmg"]), true, src)
		battle._damage._apply_damage(o, maxi(1, after), Color("#ffb347"), src, "mag", false)
		if o.get("alive", false):
			battle._damage._apply_dot_stacks(o, "burn", AF.SERAPH_BOOM_BURN, src)
		seraph_vfx.hit_spark(o)            # 命中火花: 接在结算之后(§3.5), 演出掉了不影响数值
		n += 1
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
	## ★友军名单排除训龟大师与龟蛋(第十批 E11 —— 原来普攻护盾给了大师, 法阵奶了大师和龟蛋)
	for a in battle._targeting._allies_share_pool(ax):
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
	_give_energy(best, AF.HOLO_ONHIT_ENERGY)
	return best


## ★★给一个单位加龟能 —— **分两条路**, 2026-09-01 补。
##   由来: 全息斧的「普攻给友军 5 龟能」和「法阵每 0.5 秒 5 龟能」原来都写成
##   `u["energy"] += 5`。而**引擎里没有任何一处读龟的 `energy`** ——
##   实时版的龟能 = 技能冷却充能, 正确入口是 `EquipSystem._eq_grant_energy`(龟能银行)。
##   (`eq_bow_batch.gd:440` 与 `angel_system.gd:52` 都白纸黑字警告过, 我还是踩了。)
##   ⇒ 龟走冷却充能; 斧头召唤物没有技能冷却表, 走它自己那条充能条。
func _give_energy(u: Dictionary, amount: float) -> void:
	if not (u is Dictionary) or amount <= 0.0:
		return
	if u.get("_eq_axe", false):
		u["energy"] = minf(float(u.get("maxEnergy", 999999.0)),
			float(u.get("energy", 0.0)) + amount)
		return
	battle._equip_sys._eq_grant_energy(u, amount)


## 法阵这一跳的**纯结算**：600 码内友军回血 + 给龟能 + 挂攻速。返回受益人数。
func holo_aura_tick(ax: Dictionary) -> int:
	if _fk(ax) != "holo":
		return 0
	var org: Vector2 = ax.get("pos", Vector2.ZERO)
	var n := 0
	## ★友军名单排除训龟大师与龟蛋(第十批 E11 —— 原来普攻护盾给了大师, 法阵奶了大师和龟蛋)
	for a in battle._targeting._allies_share_pool(ax):
		if not a.get("alive", false):
			continue
		if (a.get("pos", Vector2.ZERO) as Vector2).distance_to(org) > AF.HOLO_AURA_R:
			continue                       # ★范围外的一律不许吃到（门禁专门量这条）
		battle._damage._heal(a, AF.HOLO_AURA_HEAL)
		_give_energy(a, AF.HOLO_AURA_ENERGY)
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
		_play(ax, "axe_execute")       # 斧头本体的处决动作(素材早在盘上, 之前零调用者)
		if not tgt.get("alive", true):
			## 「处决一个单位会使召唤物获得150点龟能」
			_give_energy(ax, AF.EMBER_EXEC_ENERGY)
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
	## ★★按差量加减, 到期还原施放前的值(第十批 E9)。原来在线写常量、到期直接写 0 ——
	##   施放前就有的减伤 / 吸血 / 免控被抹掉(探针: 施放前 0.10 减伤 → 到期 0.00)。
	##   口径与蓄力 / 插地一致: 在线期间取大(不叠加), 记下【实际抬了多少】, 到期只减这么多。
	var was: bool = ax.has("_ember_dr_add")
	if on and not was:
		ax["_ember_dr_add"] = maxf(0.0, AF.EMBER_LIGHT_DR - float(ax.get("damage_reduction", 0.0)))
		ax["_ember_ls_add"] = maxf(0.0, AF.EMBER_LIGHT_LIFESTEAL - float(ax.get("lifesteal", 0.0)))
		ax["damage_reduction"] = float(ax.get("damage_reduction", 0.0)) + float(ax["_ember_dr_add"])
		ax["lifesteal"] = float(ax.get("lifesteal", 0.0)) + float(ax["_ember_ls_add"])
	elif was and not on:
		ax["damage_reduction"] = maxf(0.0, float(ax.get("damage_reduction", 0.0)) - float(ax["_ember_dr_add"]))
		ax["lifesteal"] = maxf(0.0, float(ax.get("lifesteal", 0.0)) - float(ax.get("_ember_ls_add", 0.0)))
		ax.erase("_ember_dr_add")
		ax.erase("_ember_ls_add")
	## 攻速走单格的 haste 通道: 在线时取大并续 0.2 秒; 到期【不写】, 让它自己过期(原来写 1.0 / 0 会顺手抹掉别人给的加速)。
	if on:
		var _h_on: bool = float(battle._t) < float(ax.get("haste_until", 0.0))
		ax["haste_mult"] = maxf(float(ax.get("haste_mult", 1.0)) if _h_on else 1.0, 1.0 + AF.EMBER_LIGHT_ASPD)
		ax["haste_until"] = maxf(float(ax.get("haste_until", 0.0)), float(battle._t) + 0.2)
	## ★★「免疫控制」的字段名**我原来写错了**: 我写的是 `cc_immune`(布尔), 而引擎读的是
	##   `cc_immune_until`(时间戳, 见 battle_damage._is_cc_immune / _stun)。
	##   `cc_immune` 全仓**没有任何代码读它** ⇒ 余烬之光的免控**根本不生效**。
	##   2026-09-01 逐条对用户原话时抓到 —— 这是"读了没人写"的镜像:"写了没人读"。
	var _lights: Array = ax.get("_ember_lights", [])
	var _last: float = 0.0
	for _x in _lights:
		_last = maxf(_last, float(_x))
	## 免控: 在线时取大(不缩短别人给的更长免控), 并记下施放前的值与本效果写入的值;
	##   到期时若仍是本效果写的那个值 ⇒ 还原施放前的值(原来直接写 0 会抹掉施放前就有的免控),
	##   若期间被别人改过 ⇒ 不动。★不能「到期不写」: 光效提前全部失效而时间戳还在未来时, 会留下一段假免控
	##   (verify_axe_finals「全部过期后减伤/免控还原」当场抓到)。
	if on:
		if not ax.has("_ember_cc_bak"):
			ax["_ember_cc_bak"] = float(ax.get("cc_immune_until", 0.0))
		ax["cc_immune_until"] = maxf(float(ax.get("cc_immune_until", 0.0)), _last)
		ax["_ember_cc_set"] = float(ax["cc_immune_until"])
	elif ax.has("_ember_cc_bak"):
		if is_equal_approx(float(ax.get("cc_immune_until", 0.0)), float(ax.get("_ember_cc_set", -1.0))):
			ax["cc_immune_until"] = float(ax["_ember_cc_bak"])
		ax.erase("_ember_cc_bak")
		ax.erase("_ember_cc_set")
	## ★★这里原来还写了一个 `ax["cc_immune"] = on`。**删掉** ——
	##   引擎一处都不读它, 而门禁读了 5 次: 那 5 条断言量的是**我自己插的标记**,
	##   不是"免控真的生效了"(memory: 门禁要量需求不是量我的钩子)。
	##   判据已改成读引擎真的会看的 `cc_immune_until`。
	## ★★需求原话:「**这期间不会锁龟能**」—— 2026-09-01 对原话逐条核对时抓到我完全没做。
	##   本作的"锁龟能"是 `energy_lock_until`(主场景龟能 tick 开头那道闸)。
	##   余烬之光期间要**主动清掉**它: 否则被眩晕/击飞/风暴挂上锁之后, 免控让斧头动得了、
	##   龟能却还在锁着 —— 那正是"免疫控制"该解决而没解决的另一半。
	if on:
		ax["energy_lock_until"] = 0.0
	## ★余烬之光的**视觉**(之前 `ember_light` 也是零调用者)。多层不叠强度,
	##   所以视觉也只画一圈 —— 与结算口径一致。
	if on and not ax.has("_ember_light_node"):
		ax["_ember_light_node"] = vfx.ember_light(ax)
	elif not on and ax.has("_ember_light_node"):
		vfx.fade_and_free(ax.get("_ember_light_node", null), 0.3)
		ax.erase("_ember_light_node")
	if on:
		ax["stun_until"] = 0.0


# ══════════════════════════════════════════════════════════════
#  ★★主动技能的【替换】—— 2026-09-01 补
#
#  由来: 零调用者扫描抓到 —— `undead_on_death` / `seraph_boomerang_settle` /
#  `holo_aura_tick` / `ember_light_cast` **产品代码里一个调用者都没有**。
#  也就是说四个造物的主动**一个都放不出来**, 而门禁全绿 ——
#  因为门禁直接调这些函数, 从没证明"游戏里真的会走到它们"。
#  (memory [[fb-verify-must-run-the-real-path]]: 断言函数存在 ≠ 还有没有人调)
#
#  需求原文里的替换规则:
#    · 炽天使「主动效果4秒里的猛砸将被替换为4秒内投掷10把斧头回旋镖，**不再获得减伤**」
#    · 全息斧「主动4秒内的猛砸将被替换为将斧头插入地下4秒，转而获得30%减伤，期间释放全息法阵」
#    · 余烬  「主动技能的4秒猛砸将被替换为余烬之光」(不是蓄力, 是立刻起 4 秒 buff)
#    · 亡灵之斧**没说替换** ⇒ 保持被动6的梯形蓄力猛砸
# ══════════════════════════════════════════════════════════════

## 主动触发时按造物分派。返回走了哪条路(""=没有造物, 交给被动6的猛砸)。
## ★纯状态机, 不建节点也不结算伤害 —— 门禁直接调它验分派对不对。

## 播斧头本体的一张招式帧。**只是转调** `axe_system.play_action` ——
## 造物这边不另起一套播放逻辑(memory [[fb-hand-rolled-copies-drift]]:
## 手抄的副本必然落后)。拿不到 axe_system 就静默跳过(无头测试里正常)。
func _play(ax: Dictionary, key: String, loop: bool = false) -> bool:
	var es = battle.get("_equip_sys") if battle != null else null
	if es == null:
		return false
	var axs = es.get("_axe")
	if axs == null:
		return false
	return bool(axs.play_action(ax, key, loop))


func begin_active(ax: Dictionary) -> String:
	var fk: String = _fk(ax)
	match fk:
		"seraph":
			ax["_seraph_until"] = float(battle._t) + AF.SERAPH_CAST_TIME
			ax["_seraph_left"] = AF.SERAPH_BOOMERANGS
			ax["_seraph_next"] = float(battle._t)
			## ★「不再获得减伤」—— 需求明确取消, 所以这里**什么都不做**(不是漏写)
			return "seraph"
		"holo":
			ax["_holo_until"] = float(battle._t) + AF.HOLO_PLANT_TIME
			ax["_holo_next"] = float(battle._t)
			ax["_holo_dr_bak"] = float(ax.get("damage_reduction", 0.0))
			ax["damage_reduction"] = maxf(float(ax.get("damage_reduction", 0.0)), AF.HOLO_PLANT_DR)
			ax["_holo_root"] = vfx.holo_field(ax.get("pos", Vector2.ZERO),
				AF.HOLO_AURA_R, AF.HOLO_PLANT_TIME)
			_play(ax, "axe_plant", true)   # 插地是【持续 4 秒的状态】⇒ 循环帧表
			return "holo"
		"ember":
			ember_light_cast(ax)
			return "ember"
	return ""


## 每帧推进造物主动。返回这一帧做了几件事(门禁拿它当分母)。
func tick_active(ax: Dictionary, _delta: float) -> int:
	var n := 0
	# ── 炽天使: 4 秒内均匀甩 10 把 ──
	if ax.has("_seraph_until"):
		if float(battle._t) >= float(ax["_seraph_until"]) or int(ax.get("_seraph_left", 0)) <= 0:
			ax.erase("_seraph_until")
			ax.erase("_seraph_left")
			ax.erase("_seraph_next")
		elif float(battle._t) >= float(ax.get("_seraph_next", 0.0)):
			var t2 = battle._targeting._nearest_enemy(ax)
			var dir: Vector2 = Vector2.RIGHT
			if t2 is Dictionary:
				var rel: Vector2 = (t2.get("pos", Vector2.ZERO) as Vector2) - (ax.get("pos", Vector2.ZERO) as Vector2)
				if rel != Vector2.ZERO:
					dir = rel.normalized()
			seraph_boomerang_launch(ax, dir)   # 只登记在途; 伤害在 tick_boomerangs 里镖经过时结算
			ax["_seraph_left"] = int(ax.get("_seraph_left", 0)) - 1
			## ★间隔 = 4 秒 / 10 把, 与 AxeFinalVfx.boomerang_launch_t 同一个口径
			ax["_seraph_next"] = float(battle._t) + AF.SERAPH_CAST_TIME / float(AF.SERAPH_BOOMERANGS)
			n += 1
	# ── 全息斧: 插地 4 秒, 每 0.5 秒法阵一跳 ──
	if ax.has("_holo_until"):
		if float(battle._t) >= float(ax["_holo_until"]):
			ax.erase("_holo_until")
			ax.erase("_holo_next")
			## ★减伤**必须还原** —— 不还原就是个永久 30% 减伤的怪物(被动6踩过同一个坑)
			if ax.has("_holo_dr_bak"):
				ax["damage_reduction"] = float(ax["_holo_dr_bak"])
				ax.erase("_holo_dr_bak")
			ax.erase("_holo_root")
		elif float(battle._t) >= float(ax.get("_holo_next", 0.0)):
			holo_aura_tick(ax)
			vfx.holo_pulse(ax.get("_holo_root", null))
			ax["_holo_next"] = float(battle._t) + AF.HOLO_AURA_TICK
			n += 1
	return n


## 造物主动**正在进行中**吗（正在甩回旋镖 / 正在插地）。
## ★调用方据此决定"这一帧还要不要放新的主动" —— 不判的话龟能一满就重开, 永远做不完。
func active_busy(ax: Dictionary) -> bool:
	return ax.has("_seraph_until") or ax.has("_holo_until")


# zero-caller-ok: 自检用, 故意没人调
func zzz_exempt() -> int:
	return 1
