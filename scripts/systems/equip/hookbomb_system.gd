class_name HookBombSystem
extends RefCounted
## 靶向器 p2eq_055 ·【钩索炸弹】(用户 2026-08-01 整条重做)
##
## 用户原文:「携带者在首次造成了400点伤害后，会向最近的1/1/2名敌人发射钩索炸弹，
##   炸弹会附在敌人身上并每秒对该敌人造成1/2/2%物理伤害，持续到敌人死亡时，
##   如果敌人带有炸弹的时候死亡，则会朝所有敌方单位发射钩索，眩晕0.5秒后把他们拉向自己，
##   聚在一起后产生一次爆炸造成200/400/500+10%最大生命值物理伤害。
##   记得排出训龟大师和龟蛋还有免控单位」
##
## ★旧效果(命中标记 +20% 受伤 5 秒)已整条删除, 不是叠加。
##
## ═══ 为什么把结算全做成纯函数 ═══
## CLAUDE.md §3.5 的血泪: `verify_pirate_hook` 连红三次(帧数→游戏时钟→墙钟), 根因是
## 【场景树 create_tween() 在无头 CI 下推进不稳】—— 伤害结算埋在"甩钩→拉回→callback"两层
## tween 链的最末尾, CI 上那条链跑不完, 等多久都是 0, 而本地永远复现不出来。
## 所以本文件的规矩是:
##   · `_hb_pull_dest(...)`   纯几何 —— 验落点, 不等 tween 跑到
##   · `_hb_detonate(...)`    纯结算 —— 演出末尾调它、门禁也直接调它
##   · `_hb_targets(...)`     纯筛选 —— 免控/大师/龟蛋的排除单独可验
## 一个测"数值对不对"的用例, 不该依赖任何动画 tween 跑完。
##
## ═══ 数值口径(已在方案书记录, 用户未逐条指定基数时的取法) ═══
##   · 每秒 1/2/2% 物理伤害 → 按【宿主自身 maxHp】的百分比。与骷髅爆炸(032)同口径:
##     那条也是"200码内敌各受【其自身】%最大生命"。
##   · 爆炸 200/400/500 + 10% 最大生命值 → 同样按【被炸目标自身 maxHp】。
##   · 两者都是【物理伤害】= 走 raw=false 的常规路径, 吃护甲。

var battle

const TRIGGER_DMG := 400                      # 首次累计造成这么多伤害后触发(用户原文"首次造成了400点伤害")
const BOMB_COUNT := [1, 1, 2]                 # 挂弹敌人数(1/1/2)
const BOMB_DPS_PCT := [0.01, 0.02, 0.02]      # 每秒对宿主造成其 maxHp 的 1/2/2%
const BOMB_TICK := 1.0                        # "每秒"
const BLAST_FLAT := [200.0, 400.0, 500.0]     # 聚爆固定段
const BLAST_MAXHP_PCT := 0.10                 # 聚爆额外 10% 最大生命
const PULL_STUN := 0.5                        # 拉之前先眩晕 0.5 秒
const PULL_GATHER_R := 60.0                   # 聚拢半径: 拉到携带者周围这个圈上(不重叠成一个点)


func _init(b) -> void:
	battle = b


## 能不能被这套钩索【拉/晕】。用户点名排除: 训龟大师 / 龟蛋 / 免控单位。
## ★免控用的是通用窗口 cc_immune_until(battle_damage._stun 的唯一闸门), 不是自己再发明一个判据 ——
##   发明新判据 = 下一个加免控来源的人不会知道要同步这里。
func _hb_can_grab(o: Dictionary) -> bool:
	if not (o is Dictionary) or not o.get("alive", false):
		return false
	if o.get("is_trainer", false):
		return false
	if o.get("_isEgg", false) or o.get("egg", false) or o.get("_eggImmune", false):
		return false
	if battle._t < float(o.get("cc_immune_until", 0.0)):
		return false
	return true


## 可挂弹的敌人(排除同上): 挂到蛋/大师身上等于把整条效果喂给一个永远不死或不该被拉的目标。
func _hb_targets(u: Dictionary, n: int) -> Array:
	var cand: Array = []
	for o in battle._targeting._enemies_of(u):
		if not _hb_can_grab(o):
			continue
		if float(o.get("hookbomb_pct", 0.0)) > 0.0:
			continue                                   # 已经挂着弹, 不重复挂
		cand.append(o)
	cand.sort_custom(func(a, b): return (a["pos"] - u["pos"]).length_squared() < (b["pos"] - u["pos"]).length_squared())
	return cand.slice(0, maxi(0, n))


## 挂弹。★不拿单位字典当 Dictionary 的键(CLAUDE.md §3.2 会递归哈希成环→卡死);
##   这里是把【引用】存进字段, 与 summon_owner 同一做法, 合法。
func _hb_attach(u: Dictionary, o: Dictionary, si: int) -> void:
	o["hookbomb_pct"] = BOMB_DPS_PCT[si]
	o["hookbomb_src"] = u
	o["hookbomb_si"] = si
	o["hookbomb_t"] = 0.0
	battle._mark_vfx(o, 9999.0, Color("#ff7a3c"))     # 持续到死 → 用超长时长而不是另造一套标记
	battle._skill_ring(o["pos"], Color(1.0, 0.48, 0.24, 0.7), 44.0)


## 宿主身上的每秒跳伤。由 _tick_unit 每帧喂 delta。
func _hb_tick(o: Dictionary, delta: float) -> void:
	var pct: float = float(o.get("hookbomb_pct", 0.0))
	if pct <= 0.0 or not o.get("alive", false):
		return
	var src = o.get("hookbomb_src", null)
	if not (src is Dictionary):
		return
	o["hookbomb_t"] = float(o.get("hookbomb_t", 0.0)) + delta
	if float(o["hookbomb_t"]) < BOMB_TICK:
		return
	o["hookbomb_t"] = float(o["hookbomb_t"]) - BOMB_TICK
	var dmg: int = maxi(1, int(round(float(o["maxHp"]) * pct)))
	battle._damage._apply_damage_from(src, o, dmg, Color("#ff8a3c"), 0.0, false, true)


## 聚拢落点(纯几何 —— 门禁验这个, 不等拉拽 tween 跑完)。
## 均匀铺在携带者周围半径 PULL_GATHER_R 的圈上: 全拉到同一点会被分离力当场弹开,
## 看起来像"拉了个寂寞", 而且 ARENA 外的合成单位会被钳到同一处(memory 里那条 500帧红/1500帧绿的坑)。
func _hb_pull_dest(carrier: Dictionary, idx: int, total: int) -> Vector2:
	var a: float = TAU * float(idx) / maxf(1.0, float(total))
	return (carrier["pos"] as Vector2) + Vector2(cos(a), sin(a)) * PULL_GATHER_R


## ★★核心结算: 宿主带弹死亡 → 朝所有敌方单位发钩 → 眩晕 0.5s → 拉向携带者 → 聚拢后一次爆炸。
## 纯函数: 演出末尾调它, 门禁也直接调它。返回被卷入的单位数(供门禁当分母, N=0 是空检查不是通过)。
func _hb_detonate(carrier: Dictionary, si: int) -> int:
	if not (carrier is Dictionary) or not carrier.get("alive", false):
		return 0
	var list: Array = []
	for o in battle._targeting._enemies_of(carrier):
		if _hb_can_grab(o):
			list.append(o)
	if list.is_empty():
		return 0
	var n: int = list.size()
	for i in range(n):
		var o: Dictionary = list[i]
		battle._damage._stun(o, PULL_STUN, "hookbomb")
		var dest: Vector2 = _hb_pull_dest(carrier, i, n)
		o["pos"] = dest
		o["_home_pos"] = dest        # ★位移技能必须写回 _home_pos, 否则归位逻辑当场把人拽回去(memory: fb-review-dummy-homing)
		var dmg: int = maxi(1, int(round(BLAST_FLAT[si] + float(o["maxHp"]) * BLAST_MAXHP_PCT)))
		battle._damage._apply_damage_from(carrier, o, dmg, Color("#ff5a2a"), 0.0, false, true)
	battle._skill_ring(carrier["pos"], Color(1.0, 0.45, 0.2, 0.85), 150.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	return n


## 宿主死亡钩子。由 battle._kill 调。★把"带弹"的判据放在这里而不是 _kill 里散着写,
## 是为了让"谁在触发引爆"只有一个答案。
func _hb_on_death(o: Dictionary) -> void:
	if float(o.get("hookbomb_pct", 0.0)) <= 0.0:
		return
	var src = o.get("hookbomb_src", null)
	var si: int = int(o.get("hookbomb_si", 0))
	o["hookbomb_pct"] = 0.0
	o["hookbomb_src"] = null
	if src is Dictionary:
		_hb_detonate(src as Dictionary, si)
