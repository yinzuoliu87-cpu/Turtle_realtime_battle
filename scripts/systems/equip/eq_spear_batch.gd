class_name EqSpearBatch
extends RefCounted
## eq_spear_batch.gd —— 长矛羁绊 10 件新装备的效果本体(2026-11-26 · 方案书 docs/plans/20261126-长矛羁绊.md §4)
##   137 竹矛 · 138 鱼叉 · 139 标枪 · 140 骑枪 · 141 长戟 · 142 盾矛 · 143 方天画戟 · 144 投矛器 · 145 永恒之枪 · 146 圣枪
## 每件单独生效(不靠羁绊档位; 同一件带多件 = 每件各自独立, 用户 11-13)。
## ★11-26 夜用户改了 137~144 的机制(原话见方案书第 1 节), 145 / 146 待重新设计(现在仍是第一版)。
## 接口 = 批④统一口(b4_owner.gd → `_b4`); 另加静态 `shield_block`(142 举盾时每段伤害减固定值并存进能量条, _apply_damage_from 里调)。
## 会动的东西一律按速度走、每步判定碰撞(竹刺浪 / 冲击波 / 鱼叉 / 标枪 / 落矛; memory fb-projectiles-have-speed / fb-moving-hits-collide-per-step)。
var battle
var vfx = null

const COL_PHYS := Color("#ff9a4a")
const COL_MAGIC := Color("#4dabf7")
# ── 137 竹矛: 每第 3 次攻击, 朝最远的敌人方向从地里刺出一道竹刺浪 ──
const BAMBOO_EVERY := 3
const BAMBOO_PCT := [0.60, 0.80, 1.20]
const BAMBOO_LEN := 450.0         # 浪走多远
const BAMBOO_SPD := 700.0         # 浪头推进速度
const BAMBOO_W := 40.0            # 判定半宽(加敌人体型一半)
const BAMBOO_SPIKE_EVERY := 45.0  # 每推进这么远冒一丛竹刺(只管画面)
# ── 138 鱼叉: 每 10/8/6 秒朝本场造成伤害最多的敌人射一叉 ──
const HARPOON_IV := [10.0, 8.0, 6.0]
const HARPOON_DMG := [40.0, 70.0, 120.0]
const HARPOON_STUN := 1.5
const HARPOON_PULL_IV := 0.5
const HARPOON_PULL := 40.0        # 每次往携带者拉近
const HARPOON_KEEP := 60.0        # 拉到离携带者这么近就不再拉
const HARPOON_SPD := 1100.0
# ── 139 标枪: 每 6 秒朝最远的敌人掷标枪 ──
const JAV_IV := 6.0
const JAV_PCT := [1.5, 2.2, 3.5]
const JAV_BLEED_PCT := [0.5, 0.7, 1.0]   # 流血层数 = 攻击力 ×
const JAV_SPD := 900.0
# ── 140 骑枪: 移动攒冲势, 攒满后下一次攻击耗尽 ──
const LANCE_NEED := 400.0         # 移动这么远攒满
const LANCE_PCT := [1.2, 1.8, 2.8]
const LANCE_STUN := [0.8, 1.0, 1.25]
const LANCE_EN := [15.0, 20.0, 30.0]
# ── 141 长戟: 每隔一次攻击间隔朝最近的敌人横扫前方扇形(迷你版 010 激光长刃) ──
const HALB_ARC := 0.5             # cos(60°): 前方 120° 扇形
const HALB_PCT := [0.35, 0.50, 0.80]
const HALB_MELEE_BONUS := 100.0   # 近战携带者半径额外加这么多(010 是 250)
# ── 142 盾矛: 每 8 秒举盾 4 秒 ──
const SHSP_IV := 8.0
const SHSP_SEC := 4.0
const SHSP_FLAT := [15.0, 25.0, 40.0]          # 举盾时每段伤害降低固定值
const SHSP_SHIELD_PCT := [0.30, 0.45, 0.70]    # 放盾: 存下伤害 × ⇒ 护盾
const SHSP_SHIELD_SEC := 6.0
const SHSP_WAVE_PCT := [0.50, 0.80, 1.20]      # 放盾: 存下伤害 × ⇒ 冲击波魔法伤害(路径上的敌人分摊)
const SHSP_WAVE_LEN := 300.0
const SHSP_WAVE_SPD := 600.0
const SHSP_WAVE_ARC := 0.7071                  # cos(45°): 前方 90° 扇形
# ── 143 方天画戟: 挨打攒战意 → 蓄力 → 跃起砸地; 之后 4 秒每次攻击绕身横扫 ──
const FTJ_NEED_PCT := 0.30        # 累计受到最大生命值 × 这么多伤害就攒满
const FTJ_WIND := 0.5             # 原地蓄力
const FTJ_AIR := 0.5              # 跃起到落地(演出按这个摆, 结算在落地那一步)
const FTJ_SLAM_R := 260.0
const FTJ_SLAM_PCT := [1.0, 1.5, 2.5]
const FTJ_SLAM_VY := 9.0          # 击飞上抛初速(滞空 = 2 × 9 / 22 ≈ 0.8 秒)
const FTJ_BUFF_SEC := 4.0
const FTJ_R := 170.0
const FTJ_PCT := [0.30, 0.45, 0.80]
const FTJ_HEAL := [30.0, 50.0, 90.0]
# ── 144 投矛器: 每 10 秒朝敌人最密集的位置落一圈矛雨 ──
const ATL_IV := 10.0
const ATL_N := [8, 12, 18]
const ATL_PCT := [0.35, 0.50, 0.80]
const ATL_R := 130.0              # 落点散在这一圈里(第一根落在目标本人身上)
const ATL_HIT_R := 65.0           # 每根矛落地判定半径(加敌人体型一半)
const ATL_SPREAD_SEC := 0.6       # 一批矛在这段时间里陆续出手
const ATL_FALL_H := 600.0         # 从多高落下(按速度飞, 落地才结算)
const ATL_FALL_SPD := 1400.0
# ── 145 永恒之枪(待重新设计) ──
## 145 永恒之枪(11-26 用户设计重做 · 方案书 20261126 附录 E)
const ETERNAL_NEED := 100.0                    # 进度条满
const ETERNAL_PS := 4.0                        # 每秒 +
const ETERNAL_PER_DMG := 3.0                   # 每造成 / 受到 100 点伤害 +
const ETERNAL_SPD := 700.0                     # 飞行速度(用户嫌飞刀飞镖快, 同手雷)
const ETERNAL_FROM := Vector2(900.0, 520.0)    # 从目标的「我方一侧上方」这么远处飞来(场外)
const ETERNAL_HIT_ATK := [1.2, 1.8, 3.0]       # 插中: 攻击力 ×
const ETERNAL_HIT_HP := [0.04, 0.06, 0.10]     # 插中: + 目标最大生命值 ×
const ETERNAL_SLIDE := 250.0                   # 击倒后往后滑行距离
const ETERNAL_SLIDE_SEC := 0.5
const ETERNAL_STUN := 1.0                      # 击倒 + 滑行期间眩晕
const ETERNAL_SLIDE_ATK := [0.4, 0.6, 1.0]     # 滑行期间共: 攻击力 ×(按每一步滑过的距离分摊)
const ETERNAL_SLIDE_HP := [0.02, 0.03, 0.05]   # 滑行期间共: + 目标最大生命值 ×
const ETERNAL_PASS_W := 50.0                   # 滑行路径上撞到其他敌人的判定半宽(加敌人体型一半)
const ETERNAL_PASS_ATK := [0.8, 1.2, 2.0]      # 路径上的其他敌人各: 攻击力 ×
const ETERNAL_PASS_HP := [0.03, 0.04, 0.06]    # 路径上的其他敌人各: + 其最大生命值 ×
const ETERNAL_IMM_ATK := [1.0, 1.5, 2.5]       # 目标免疫控制 ⇒ 不倒不滑, 转而追加: 攻击力 ×
const ETERNAL_IMM_HP := [0.04, 0.05, 0.08]     # 转而追加: + 目标最大生命值 ×
const ETERNAL_TEMP := [0.2, 0.3, 0.5]          # 命中时携带者临时生命值 = 自身最大生命值 ×(可叠加)
const ETERNAL_TEMP_SEC := 6.0
const ETERNAL_BURN_R := 250.0                  # 携带者身上灼烧圈半径(跟着携带者走)
const ETERNAL_BURN_SEC := 6.0
const ETERNAL_BURN_PCT := [0.02, 0.03, 0.05]   # 每秒: 圈内敌人各自最大生命值 × 的魔法伤害(多个圈各自生效)
# ── 146 圣枪(待重新设计) ──
## 146 圣枪(11-26 晚用户重做成坦克装 · 方案书 20261126c)
const HOLY_GUARD_AT := 0.5                     # 每一路首次生命值低于这个比例 ⇒ 圣枪护盾 + 双抗
const HOLY_GUARD_PCT := [0.40, 0.60, 1.00]     # 圣枪护盾合计 = 最大生命值 ×(不衰减, 换路随单位重建清掉)
const HOLY_GUARD_SEC := 10                     # 10 秒内每秒给一份(开头那一下给第 1 份, 共 10 份; 用户 11-26「数秒之内每秒提供」→「改为在十秒钟之内逐渐…给」)
const HOLY_RESIST := [30.0, 50.0, 100.0]       # 护甲 / 魔抗各 +, 持续到这一路结束
const HOLY_STORE_CAP := 1.0                    # 储能上限 = 最大生命值 ×
const HOLY_IV := 12.0                          # 每 12 秒开始引导
const HOLY_ORB_IV := 0.25                      # 引导中每 0.25 秒出一个光球
const HOLY_ORB_COST := [500.0, 400.0, 300.0]   # 每个光球消耗的储能; 不够一个就结束引导
const HOLY_ORB_SPD := 450.0                  # 用户 11-26「飞得太快了吧」(原 900); 画面上走弧线(演出层抬高度, 结算仍是飞到碰到才算)
const HOLY_ORB_HEAL := [150.0, 250.0, 400.0]   # 砸到友方: 临时等级 +1 并回复
const HOLY_ORB_DMG := [150.0, 250.0, 500.0]    # 砸到敌方: 魔法伤害
const HOLY_ORB_SHIELD := [60.0, 100.0, 200.0]  # 砸到敌方: 携带者护盾(照样存回储能条, 用户「不需要去限制」)

var stat := {"bamboo": 0, "bamboo_hit": 0, "harpoon": 0, "harpoon_hit": 0, "harpoon_pull": 0, "jav": 0, "jav_hit": 0,
	"lance": 0, "halb": 0, "halb_hit": 0, "shsp_raise": 0, "shsp_block": 0, "shsp_release": 0, "shsp_wave_hit": 0,
	"ftj": 0, "ftj_hit": 0, "ftj_spin": 0, "atl": 0, "atl_hit": 0, "eternal": 0, "eternal_hit": 0, "eternal_imm": 0, "eternal_pass": 0, "eternal_burn": 0, "holy_guard": 0, "holy_guard_part": 0, "holy_channel": 0, "holy_orb": 0, "holy_ally": 0, "holy_enemy": 0}
var _waves: Array = []    # 137 竹刺浪 {src, ck, o(起点), dir, r, si, hit, sp(下一丛竹刺的距离)}
var _pulls: Array = []    # 138 拉拽 {src, o, left, t_next}
var _swaves: Array = []   # 142 冲击波 {src, ck, o, dir, r, per, hit}
var _slams: Array = []    # 143 {u, ck, si, t, phase}
var _slides: Array = []   # 145 击倒滑行 {src, o, dir, gone, total, si, ck, hit}
var _burns: Array = []    # 145 灼烧圈(跟着携带者) {src, until, next, si, ck}
var _drops: Array = []    # 144 落矛 {src, ck, at, t_fire, t_land, si, fired}


func _init(b) -> void:
	battle = b


func _fx(method: String, args: Array = []) -> void:
	var v = battle._spear_syn.vfx if battle.get("_spear_syn") != null else null
	if v == null and battle.get("_spear_syn") != null:
		battle._spear_syn._fx("noop", [])
		v = battle._spear_syn.vfx
	if v != null and v.has_method(method):
		v.callv(method, args)


## 演出层(懒加载: 第一次用到之前是空的 ⇒ 要拿节点的地方先过这里, 不然第一叉 / 第一枪没有画面 —— 11-26 夜录像抓到鱼叉第一叉看不见)
func _vfx():
	if battle.get("_spear_syn") == null:
		return null
	if battle._spear_syn.vfx == null:
		battle._spear_syn._fx("noop", [])
	return battle._spear_syn.vfx


func _acc(u: Dictionary, key: String) -> float:
	var d: Dictionary = u.get("_spear_acc", {})
	return float(d.get(key, 0.0))


func _set_acc(u: Dictionary, key: String, v: float) -> void:
	var d: Dictionary = u.get("_spear_acc", {})
	d[key] = v
	u["_spear_acc"] = d


static func _si_of(e: Dictionary) -> int:   # 同一份实现只留在 EqMagicBatch(dup_primitive_audit)
	return EqMagicBatch._si_of(e)


func _phys(src: Dictionary, o: Dictionary, base: float) -> void:
	if not o.get("alive", false) or base <= 0.0:
		return
	var d: int = battle._phys_after_armor(src, base, o)
	battle._damage.set_dtype("physical", o, false, true)   # _phys_after_armor 只算护甲不声明类型 ⇒ 不声明就捡上一发的(飘字颜色 / 分行跟着错)
	battle._damage._apply_damage_from(src, o, d, COL_PHYS, 0.0, false, true)


func _magic(src: Dictionary, o: Dictionary, base: float) -> void:
	if not o.get("alive", false) or base <= 0.0:
		return
	battle._damage._apply_damage_from(src, o, battle._resolve_dmg(src, base, o, true, false), COL_MAGIC, 0.0, false, true)


func _enemies(u: Dictionary) -> Array:
	var out: Array = []
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false):
			out.append(o)
	return out


func _farthest(u: Dictionary):
	var far = null
	var bd := -1.0
	for o in _enemies(u):
		if battle._is_untargetable(o):
			continue
		var d: float = DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"]))
		if d > bd:
			bd = d
			far = o
	return far


func _dir_to(u: Dictionary, o: Dictionary) -> Vector2:
	var d: Vector2 = Vector2(o["pos"]) - Vector2(u["pos"])
	if DetMath.vlen(d) > 1.0:
		return DetMath.norm(d)
	return Vector2(1.0 if str(battle._eff_side(u)) == "left" else -1.0, 0.0)


## 142 盾矛举盾: 每段攻击 / 技能伤害降低固定值, 降之前的量存进这件的能量条(每件各自存) —— _apply_damage_from 减伤之后、护盾之前调
static func shield_block(u: Dictionary, d: float, t: float) -> float:
	var act: Dictionary = u.get("_shsp_act", {})
	if act.is_empty() or d <= 0.0:
		return d
	var flat := 0.0
	for ck in act:
		var a: Dictionary = act[ck]
		if t < float(a["until"]):
			flat += float(a["flat"])
			a["store"] = float(a["store"]) + d
	if flat <= 0.0:
		return d
	u["_shsp_blocked"] = int(u.get("_shsp_blocked", 0)) + 1
	return maxf(0.0, d - flat)


## 146 圣枪储能: 携带者获得任何护盾(普通 / 魔法 / 物理 / 溢出治疗转盾)都按到手的量存进每一件圣枪各自的储能条。
##   ★挂在全部「获盾记账」点上(_st_shield 的五个写点), 不是只挂 _grant_shield: 魔法 / 物理护盾是独立字段, 不走它。
##   静态: 登场护盾在圣枪自己的 on_spawn 之前就可能发, 不能等批系统登记; 份号直接从装备栏算(EquipCk.copies)。
static func holy_store(u: Dictionary, amt: float) -> void:
	if amt <= 0.0:
		return
	var cs: Array = EquipCk.copies(u, "p2eq_146")
	if cs.is_empty():
		return
	var hs: Dictionary = u.get("_holy_store", {})
	var cap: float = float(u.get("maxHp", 0.0)) * HOLY_STORE_CAP
	for c in cs:
		var k := str(c[0])
		hs[k] = minf(cap, float(hs.get(k, 0.0)) + amt)
	u["_holy_store"] = hs


static func holy_stored(u: Dictionary, ck: String) -> float:
	return float((u.get("_holy_store", {}) as Dictionary).get(ck, 0.0))


# ════════════════════════════════════════ 批④统一口 ════════════════════════════════════════

func on_spawn(u: Dictionary, eid: String, _si: int) -> void:
	if eid == "p2eq_140":
		u["_lance_from"] = Vector2(u["pos"])


func on_basic(u: Dictionary, tgt, eid: String, si: int) -> void:
	if not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
		return
	var t: Dictionary = tgt
	var ck: String = battle._equip_sys.key_of(u, eid)
	var atk: float = float(u.get("atk", 0.0))
	match eid:
		"p2eq_137":   # 竹矛: 第 3 下 ⇒ 竹刺浪
			var n := int(_acc(u, "bamboo:" + ck)) + 1
			if n < BAMBOO_EVERY:
				_set_acc(u, "bamboo:" + ck, float(n))
				return
			_set_acc(u, "bamboo:" + ck, 0.0)
			var far = _farthest(u)
			var dir: Vector2 = _dir_to(u, far if far is Dictionary else t)
			stat["bamboo"] += 1
			var w := {"src": u, "ck": ck, "o": Vector2(u["pos"]), "dir": dir, "r": 0.0, "si": si, "hit": [], "sp": 0.0}
			_waves.append(w)
			_fx("bamboo_wave", [u, dir])
		"p2eq_140":   # 骑枪: 攒满的冲势这一下耗尽
			if _acc(u, "lance:" + ck) >= LANCE_NEED:
				_set_acc(u, "lance:" + ck, 0.0)
				stat["lance"] += 1
				_phys(u, t, float(LANCE_PCT[si]) * atk)
				if t.get("alive", false):
					var sec: float = float(LANCE_STUN[si])
					battle._knock_up(t, Vector2(u["pos"]), sec * 22.0 / 2.0)   # 滞空 = 眩晕时长
					battle._damage._stun(t, sec, "lance")
				battle._equip_sys._eq_grant_energy(u, float(LANCE_EN[si]))
				_fx("lance_hit", [u, t])
				_fx("lance_ready", [u, false])


func on_hit(_src: Dictionary, _tgt: Dictionary, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 143 方天画戟: 受到伤害攒战意(攻击 / 技能 / 持续伤害都算; 蓄力 / 跃起期间和横扫状态里不攒)
func on_damaged(u: Dictionary, _src, dmg: float, eid: String, si: int) -> void:
	if eid == "p2eq_145" and dmg > 0.0:   # 145 永恒之枪: 受到伤害攒进度
		var ck5: String = battle._equip_sys.key_of(u, eid)
		_set_acc(u, "eter:" + ck5, minf(ETERNAL_NEED, _acc(u, "eter:" + ck5) + dmg * ETERNAL_PER_DMG / 100.0))
		return
	if eid != "p2eq_143" or dmg <= 0.0:
		return
	var ck: String = battle._equip_sys.key_of(u, eid)
	if _acc(u, "ftj_busy:" + ck) > 0.0 or float(battle._t) < _acc(u, "ftj_buff:" + ck):
		return
	var need: float = float(u.get("maxHp", 1.0)) * FTJ_NEED_PCT
	var a: float = _acc(u, "ftj:" + ck) + dmg
	if a < need:
		_set_acc(u, "ftj:" + ck, a)
		_fx("ftj_charge", [u, a / need])
		return
	_set_acc(u, "ftj:" + ck, 0.0)
	_set_acc(u, "ftj_busy:" + ck, 1.0)
	stat["ftj"] += 1
	battle._damage.channel(u, FTJ_WIND + FTJ_AIR)
	_slams.append({"u": u, "ck": ck, "si": si, "t": 0.0, "phase": 0})
	_fx("ftj_wind", [u, FTJ_WIND, FTJ_AIR])


func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_death(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


func on_mana_full(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


func on_kill(_k: Dictionary, _v: Dictionary, _eid: String, _si: int) -> void:
	pass


## 143 横扫状态: 任何一次普攻都绕身扫一圈(每件各自)
func on_any_basic(u: Dictionary, _tgt) -> void:
	if not u.has("_spear_acc"):
		return
	var t := float(battle._t)
	var es = battle._equip_sys
	var ckp: Array = es.ck_save()
	for e in u.get("equips", []):
		if not (e is Dictionary) or str((e as Dictionary).get("id", "")) != "p2eq_143":
			continue
		es.ck_set(u, e)
		var ck: String = es.key_of(u, "p2eq_143")
		if t >= _acc(u, "ftj_buff:" + ck):
			continue
		var si := _si_of(e)
		var tl: Array = es.tally.push(u, ck)
		stat["ftj_spin"] += 1
		for o in _enemies(u):
			if DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"])) <= FTJ_R + float(o.get("col_size", 22.0)) * 0.5:
				_phys(u, o, float(FTJ_PCT[si]) * float(u.get("atk", 0.0)))
		battle._damage._heal(u, float(FTJ_HEAL[si]))
		_fx("ftj_spin", [u])
		es.tally.pop(tl)
	es.ck_restore(ckp)


# ════════════════════════════════════════ 帧推进 ════════════════════════════════════════

func tick(delta: float) -> void:
	_tick_waves(delta)
	_tick_pulls()
	_tick_swaves(delta)
	_tick_slams(delta)
	_tick_drops()
	_tick_slides(delta)
	_tick_burns()


## 137 竹刺浪: 浪头按速度往前推, 每一步扫过的那一段里碰到的敌人各吃一次
func _tick_waves(delta: float) -> void:
	var keep: Array = []
	for w in _waves:
		var u: Dictionary = w["src"]
		var r0: float = float(w["r"])
		var r1: float = minf(BAMBOO_LEN, r0 + BAMBOO_SPD * delta)
		w["r"] = r1
		var org: Vector2 = w["o"]
		var dir: Vector2 = w["dir"]
		var tl: Array = battle._equip_sys.tally.push(u, str(w["ck"]))
		for o in _enemies(u):
			if _in_list(w["hit"], o):
				continue
			var rel: Vector2 = Vector2(o["pos"]) - org
			var along: float = DetMath.dot(rel, dir)
			var half: float = float(o.get("col_size", 22.0)) * 0.5
			if along < r0 - half or along > r1 + half:
				continue
			if absf(DetMath.dot(rel, Vector2(-dir.y, dir.x))) > BAMBOO_W + half:
				continue
			(w["hit"] as Array).append(o)
			stat["bamboo_hit"] += 1
			_phys(u, o, float(BAMBOO_PCT[int(w["si"])]) * float(u.get("atk", 0.0)))
		battle._equip_sys.tally.pop(tl)
		while float(w["sp"]) <= r1:
			_fx("bamboo_spike", [org + dir * float(w["sp"]), dir])
			w["sp"] = float(w["sp"]) + BAMBOO_SPIKE_EVERY
		if r1 < BAMBOO_LEN and u.get("alive", false):
			keep.append(w)
	_waves = keep


static func _in_list(arr: Array, o: Dictionary) -> bool:
	for x in arr:
		if is_same(x, o):
			return true
	return false


## 138 鱼叉: 眩晕期间每 0.5 秒往携带者拉近一段
func _tick_pulls() -> void:
	var t := float(battle._t)
	var keep: Array = []
	for p in _pulls:
		var src: Dictionary = p["src"]
		var o: Dictionary = p["o"]
		if not o.get("alive", false) or not src.get("alive", false) or int(p["left"]) <= 0:
			_fx("harpoon_release", [src, o])
			continue
		if t >= float(p["t_next"]):
			p["t_next"] = float(p["t_next"]) + HARPOON_PULL_IV
			p["left"] = int(p["left"]) - 1
			var to_src: Vector2 = Vector2(src["pos"]) - Vector2(o["pos"])
			var dist: float = DetMath.vlen(to_src)
			var step: float = minf(HARPOON_PULL, maxf(0.0, dist - HARPOON_KEEP))
			if step > 0.5:
				o["pos"] = ArenaShape.clamp_in(Vector2(o["pos"]) + DetMath.norm(to_src) * step, battle.ARENA, 40.0)
				stat["harpoon_pull"] += 1
				_fx("harpoon_pull", [src, o])
		keep.append(p)
	_pulls = keep


## 142 冲击波: 扇形往外推, 浪头扫到的敌人各吃一份(总伤害按出手时扇形全程里的敌人数平分)
func _tick_swaves(delta: float) -> void:
	var keep: Array = []
	for w in _swaves:
		var u: Dictionary = w["src"]
		var r0: float = float(w["r"])
		var r1: float = minf(SHSP_WAVE_LEN, r0 + SHSP_WAVE_SPD * delta)
		w["r"] = r1
		var tl: Array = battle._equip_sys.tally.push(u, str(w["ck"]))
		for o in _enemies(u):
			if _in_list(w["hit"], o):
				continue
			var rel: Vector2 = Vector2(o["pos"]) - Vector2(w["o"])
			var d: float = DetMath.vlen(rel)
			var half: float = float(o.get("col_size", 22.0)) * 0.5
			if d < r0 - half or d > r1 + half:
				continue
			if d > 1.0 and DetMath.dot(DetMath.norm(rel), Vector2(w["dir"])) < SHSP_WAVE_ARC:
				continue
			(w["hit"] as Array).append(o)
			stat["shsp_wave_hit"] += 1
			_magic(u, o, float(w["per"]))
		battle._equip_sys.tally.pop(tl)
		if r1 < SHSP_WAVE_LEN and u.get("alive", false):
			keep.append(w)
	_swaves = keep


## 143 蓄力 → 跃起 → 落地砸下(结算在落地那一步) → 进横扫状态
func _tick_slams(delta: float) -> void:
	var keep: Array = []
	for s in _slams:
		var u: Dictionary = s["u"]
		var ck: String = s["ck"]
		if not u.get("alive", false):
			_set_acc(u, "ftj_busy:" + ck, 0.0)
			continue
		s["t"] = float(s["t"]) + delta
		if int(s["phase"]) == 0 and float(s["t"]) >= FTJ_WIND:
			s["phase"] = 1
			_fx("ftj_leap", [u, FTJ_AIR])
		if int(s["phase"]) == 1 and float(s["t"]) >= FTJ_WIND + FTJ_AIR:
			var si := int(s["si"])
			var tl: Array = battle._equip_sys.tally.push(u, ck)
			for o in _enemies(u):
				if DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"])) <= FTJ_SLAM_R + float(o.get("col_size", 22.0)) * 0.5:
					stat["ftj_hit"] += 1
					_phys(u, o, float(FTJ_SLAM_PCT[si]) * float(u.get("atk", 0.0)))
					if o.get("alive", false):
						battle._knock_up(o, Vector2(u["pos"]), FTJ_SLAM_VY)
			battle._equip_sys.tally.pop(tl)
			_set_acc(u, "ftj_busy:" + ck, 0.0)
			_set_acc(u, "ftj_buff:" + ck, float(battle._t) + FTJ_BUFF_SEC)
			_fx("ftj_slam", [u, FTJ_SLAM_R, FTJ_BUFF_SEC])
			continue
		keep.append(s)
	_slams = keep


## 144 落矛: 到出手时刻才冒出来(从高处按速度落), 落地那一步判定落点附近的敌人
func _tick_drops() -> void:
	var t := float(battle._t)
	var keep: Array = []
	for d in _drops:
		var u: Dictionary = d["src"]
		if not bool(d["fired"]) and t >= float(d["t_fire"]):
			d["fired"] = true
			_fx("atl_drop", [d])
		if t < float(d["t_land"]):
			keep.append(d)
			continue
		var at: Vector2 = d["at"]
		var tl: Array = battle._equip_sys.tally.push(u, str(d["ck"]))
		var n_hit := 0
		for o in _enemies(u):
			if DetMath.dist(Vector2(o["pos"]), at) <= ATL_HIT_R + float(o.get("col_size", 22.0)) * 0.5:
				n_hit += 1
				stat["atl_hit"] += 1
				_phys(u, o, float(ATL_PCT[int(d["si"])]) * float(u.get("atk", 0.0)))
		battle._equip_sys.tally.pop(tl)
		_fx("atl_land", [d, n_hit > 0])
	_drops = keep


## 信息面板「本局」要显示的状态, 每帧镜像进 eq_state[装备键](面板 info_panel.eq_live_lines 只读它; eq_state 随直播下发 ⇒ 观战一致)。
##   只供显示、不参与结算(不改对局结果)。只放整数(倒计时按整秒), 免得每帧都变把直播数据撑大。
##   11-26 用户「物理护盾条呢…你这我随便一问，你这个就没做到啊？」⇒ 30 件新装备的显示逐件补齐。
func _live_put(u: Dictionary, ck: String, d: Dictionary) -> void:
	var est: Dictionary = u.get("eq_state", {})
	var cur = est.get(ck, {})
	if not (cur is Dictionary):
		cur = {}
	for k in d:
		(cur as Dictionary)[k] = d[k]
	est[ck] = cur
	u["eq_state"] = est


func _live_mirror(u: Dictionary) -> void:
	var es = battle._equip_sys
	var t := float(battle._t)
	for e in u.get("equips", []):
		if not (e is Dictionary):
			continue
		var eid := str(e.get("id", ""))
		if not ["p2eq_140", "p2eq_142", "p2eq_143", "p2eq_145", "p2eq_146"].has(eid):
			continue
		es.ck_set(u, e)
		var ck: String = es.key_of(u, eid)
		match eid:
			"p2eq_140":
				_live_put(u, ck, {"lance": int(_acc(u, "lance:" + ck)), "need": int(LANCE_NEED)})
			"p2eq_142":
				var act: Dictionary = u.get("_shsp_act", {})
				if act.has(ck):
					var a: Dictionary = act[ck]
					_live_put(u, ck, {"raise": true, "store": int(float(a["store"])), "left": int(ceil(float(a["until"]) - t))})
				else:
					_live_put(u, ck, {"raise": false, "next": int(ceil(SHSP_IV - _acc(u, "shsp:" + ck)))})
			"p2eq_143":
				var bu: float = _acc(u, "ftj_buff:" + ck)
				if t < bu:
					_live_put(u, ck, {"buff": int(ceil(bu - t)), "pct": 0})
				else:
					var need: float = maxf(1.0, float(u.get("maxHp", 1.0)) * FTJ_NEED_PCT)
					_live_put(u, ck, {"buff": 0, "pct": int(floor(_acc(u, "ftj:" + ck) / need * 100.0))})
			"p2eq_145":
				_live_put(u, ck, {"pct": int(floor(_acc(u, "eter:" + ck) / ETERNAL_NEED * 100.0))})
			"p2eq_146":
				_live_put(u, ck, {"store": int(holy_stored(u, ck)), "cap": int(float(u.get("maxHp", 0.0)) * HOLY_STORE_CAP),
					"channel": _acc(u, "holy_ch:" + ck) > 0.0, "next": int(ceil(HOLY_IV - _acc(u, "holy_t:" + ck)))})


func tick_unit(u: Dictionary, delta: float) -> void:
	if not u.get("alive", false):
		return
	var es = battle._equip_sys
	var ckp: Array = es.ck_save()
	_live_mirror(u)
	for e in u.get("equips", []):
		if not (e is Dictionary):
			continue
		var eid := str(e.get("id", ""))
		if not ["p2eq_138", "p2eq_139", "p2eq_140", "p2eq_141", "p2eq_142", "p2eq_144", "p2eq_145", "p2eq_146"].has(eid):
			continue
		var si := _si_of(e)
		es.ck_set(u, e)
		var ck: String = es.key_of(u, eid)
		var tl: Array = es.tally.push(u, ck)
		match eid:
			"p2eq_138":
				var a0 := _acc(u, "harp:" + ck) + delta
				if a0 >= float(HARPOON_IV[si]) and _harpoon(u, si, ck):
					a0 = 0.0
				_set_acc(u, "harp:" + ck, minf(a0, float(HARPOON_IV[si])))
			"p2eq_139":
				var a := _acc(u, "jav:" + ck) + delta
				if a >= JAV_IV:
					a -= JAV_IV
					_javelin(u, si, ck)
				_set_acc(u, "jav:" + ck, a)
			"p2eq_140":   # 骑枪: 移动攒冲势(攒满就停, 等下一次攻击用掉)
				var from: Vector2 = u.get("_lance_from", Vector2(u["pos"]))
				var mv: float = DetMath.dist(from, Vector2(u["pos"]))
				u["_lance_from"] = Vector2(u["pos"])
				var cur: float = _acc(u, "lance:" + ck)
				if cur < LANCE_NEED and mv > 0.0:
					var nv: float = minf(LANCE_NEED, cur + mv)
					_set_acc(u, "lance:" + ck, nv)
					if nv >= LANCE_NEED:
						_fx("lance_ready", [u, true])
			"p2eq_141":   # 长戟: 每隔一次攻击间隔扫一次(被控住时不扫, 同 010)
				var a1 := _acc(u, "halb:" + ck) + delta
				if a1 >= maxf(0.3, float(u.get("atk_interval", 1.0))) and not battle._equip_tick_sys.ctl_hold(u):
					var tg = battle._targeting._nearest_enemy(u)
					if tg is Dictionary:
						a1 = 0.0
						_halberd(u, tg, si)
				_set_acc(u, "halb:" + ck, a1)
			"p2eq_142":
				_tick_shield_spear(u, si, ck, delta)
			"p2eq_144":
				var a3 := _acc(u, "atl:" + ck) + delta
				if a3 >= ATL_IV:
					a3 -= ATL_IV
					_atlatl(u, si, ck)
				_set_acc(u, "atl:" + ck, a3)
			"p2eq_145":   # 进度: 每秒 + / 造成伤害(看 dmg_dealt 的增量) + / 受到伤害(on_damaged) +; 满了出手
				var dd: float = float(u.get("dmg_dealt", 0.0))
				var dd0: float = _acc(u, "eter_dd:" + ck)
				_set_acc(u, "eter_dd:" + ck, dd)
				var a4 := minf(ETERNAL_NEED, _acc(u, "eter:" + ck) + ETERNAL_PS * delta + maxf(0.0, dd - dd0) * ETERNAL_PER_DMG / 100.0)
				if a4 >= ETERNAL_NEED and _eternal(u, si, ck):
					a4 = 0.0
				_set_acc(u, "eter:" + ck, a4)
			"p2eq_146":
				_tick_holy(u, si, ck, delta)
		es.tally.pop(tl)
	es.ck_restore(ckp)


## 138 鱼叉: 本场造成伤害最多的敌人; 叉按速度追着飞, 到了才结算。没有能射的 ⇒ 返回 false(下一帧再试)
func _harpoon(u: Dictionary, si: int, ck: String) -> bool:
	var best = null
	var bd := -1.0
	for o in _enemies(u):
		if battle._is_untargetable(o):
			continue
		var dealt: float = float(o.get("_st_dealt", 0))
		if dealt > bd:
			bd = dealt
			best = o
	if not (best is Dictionary):
		return false
	stat["harpoon"] += 1
	var me: Dictionary = u
	var tg: Dictionary = best
	var node = null
	var vx = _vfx()
	if vx != null and vx.has_method("harpoon_fly"):
		node = vx.harpoon_fly(u, tg)
	var tp: Array = battle._equip_sys.tally.push(u, ck)
	battle._ballistics.launch_flight(u, Vector2(u["pos"]), tg, HARPOON_SPD,
		func(hit: bool) -> void:
			_fx("harpoon_end", [node, hit, me, tg])
			if not hit or not tg.get("alive", false) or not me.get("alive", false):
				return
			stat["harpoon_hit"] += 1
			_magic(me, tg, float(HARPOON_DMG[si]))
			if tg.get("alive", false):
				battle._damage._stun(tg, HARPOON_STUN, "harpoon")
				## 11-27 自查(黄色筹码录像): 眩晕被免掉(免控 / 训龟大师)时原来照样「眩晕期间」往回拽 ⇒ 只有真晕上了才拽; 没晕上就当场收绳
				if float(tg.get("stun_until", 0.0)) > float(battle._t):
					_pulls.append({"src": me, "o": tg, "left": int(round(HARPOON_STUN / HARPOON_PULL_IV)), "t_next": float(battle._t) + HARPOON_PULL_IV})
				else:
					_fx("harpoon_release", [me, tg]),
		func(_k: float, p2: Vector2, to2: Vector2) -> void:
			_fx("harpoon_step", [node, p2, to2]))
	battle._equip_sys.tally.pop(tp)
	return true


## 139 标枪: 最远的敌人; 按速度追着飞, 到了才结算: 物理伤害 + 流血
func _javelin(u: Dictionary, si: int, ck: String) -> void:
	var far = _farthest(u)
	if not (far is Dictionary):
		return
	stat["jav"] += 1
	var me: Dictionary = u
	var tg: Dictionary = far
	var base: float = float(JAV_PCT[si]) * float(u.get("atk", 0.0))
	var node = null
	var vx = _vfx()
	if vx != null and vx.has_method("javelin_fly"):
		node = vx.javelin_fly(u, tg)
	var tp: Array = battle._equip_sys.tally.push(u, ck)
	battle._ballistics.launch_flight(u, Vector2(u["pos"]), tg, JAV_SPD,
		func(hit: bool) -> void:
			_fx("javelin_end", [node, hit])
			if not hit or not tg.get("alive", false):
				return
			stat["jav_hit"] += 1
			_phys(me, tg, base)
			if tg.get("alive", false):
				battle._damage._apply_dot_stacks(tg, "bleed", maxi(1, roundi(float(me.get("atk", 0.0)) * float(JAV_BLEED_PCT[si]))), me)
				_fx("javelin_bleed", [tg]),
		func(_k: float, p2: Vector2, to2: Vector2) -> void:
			_fx("javelin_step", [node, p2, to2]))
	battle._equip_sys.tally.pop(tp)


## 141 长戟: 朝最近的敌人横扫前方 120° 扇形, 半径 = 攻击射程(近战再加)
func _halberd(u: Dictionary, tg: Dictionary, si: int) -> void:
	var fdir: Vector2 = _dir_to(u, tg)
	var rng: float = battle._eff_range(u) + (HALB_MELEE_BONUS if bool(u.get("melee", false)) else 0.0)
	stat["halb"] += 1
	for o in _enemies(u):
		var rel: Vector2 = Vector2(o["pos"]) - Vector2(u["pos"])
		var dd: float = DetMath.vlen(rel)
		if dd > rng + float(o.get("col_size", 22.0)) * 0.5:
			continue
		if dd > 1.0 and DetMath.dot(DetMath.norm(rel), fdir) < HALB_ARC:
			continue
		stat["halb_hit"] += 1
		_phys(u, o, float(HALB_PCT[si]) * float(u.get("atk", 0.0)))
	_fx("halb_sweep", [u, fdir, rng])


## 142 盾矛: 每 8 秒举盾 4 秒; 放盾 ⇒ 存下伤害的一部分转护盾 + 朝前方推冲击波
func _tick_shield_spear(u: Dictionary, si: int, ck: String, delta: float) -> void:
	var act: Dictionary = u.get("_shsp_act", {})
	var t := float(battle._t)
	if act.has(ck):
		var a: Dictionary = act[ck]
		if t < float(a["until"]):
			return
		act.erase(ck)
		u["_shsp_act"] = act
		var store: float = float(a["store"])
		stat["shsp_release"] += 1
		var sh: float = store * float(SHSP_SHIELD_PCT[si])
		if sh > 0.0:
			battle._damage._grant_shield(u, sh, SHSP_SHIELD_SEC)
		var tg = battle._targeting._nearest_enemy(u)
		var dir: Vector2 = _dir_to(u, tg) if tg is Dictionary else _dir_to(u, u)
		var total: float = store * float(SHSP_WAVE_PCT[si])
		var n := 0
		for o in _enemies(u):
			var rel: Vector2 = Vector2(o["pos"]) - Vector2(u["pos"])
			var d: float = DetMath.vlen(rel)
			if d <= SHSP_WAVE_LEN + float(o.get("col_size", 22.0)) * 0.5 and (d <= 1.0 or DetMath.dot(DetMath.norm(rel), dir) >= SHSP_WAVE_ARC):
				n += 1
		if total > 0.0:
			_swaves.append({"src": u, "ck": ck, "o": Vector2(u["pos"]), "dir": dir, "r": 0.0, "per": total / float(maxi(1, n)), "hit": []})
		_fx("shsp_release", [u, dir, sh, store])
		_set_acc(u, "shsp:" + ck, 0.0)
		return
	var a2 := _acc(u, "shsp:" + ck) + delta
	if a2 >= SHSP_IV:
		a2 = 0.0
		stat["shsp_raise"] += 1
		act[ck] = {"until": t + SHSP_SEC, "flat": float(SHSP_FLAT[si]), "store": 0.0}
		u["_shsp_act"] = act
		_fx("shsp_raise", [u, SHSP_SEC])
	_set_acc(u, "shsp:" + ck, a2)


## 144 投矛器: 敌人最密集的那一个周围一圈, 一批矛在 0.6 秒里陆续从高处落下(落点用对局随机数)
func _atlatl(u: Dictionary, si: int, ck: String) -> void:
	if _enemies(u).is_empty():
		return
	stat["atl"] += 1
	var c: Vector2 = battle._densest_enemy_point(u, 200.0)
	var n: int = int(ATL_N[si])
	var t := float(battle._t)
	var fall: float = ATL_FALL_H / ATL_FALL_SPD
	_fx("atl_cast", [u, c, ATL_R])
	for i in range(n):
		var ang: float = battle._battle_rng.randf() * TAU
		var rr: float = 0.0 if i == 0 else sqrt(battle._battle_rng.randf()) * ATL_R   # 第一根正落在目标身上(随机数照常取, 个数不变)
		var at: Vector2 = ArenaShape.clamp_in(c + Vector2(DetMath.dcos(ang), DetMath.dsin(ang)) * rr, battle.ARENA, 20.0)
		var tf: float = t + ATL_SPREAD_SEC * float(i) / float(maxi(1, n - 1))
		_drops.append({"src": u, "ck": ck, "at": at, "t_fire": tf, "t_land": tf + fall, "si": si, "fired": false})


## 145 永恒之枪(待重新设计): 生命值最高的敌人; 按速度飞到才结算: 钉住 1.5 秒 + 目标最大生命值 % 物理伤害
## 145 永恒之枪: 进度满 ⇒ 一支枪从场外(携带者那一方的上方)按速度飞向生命值最高的敌人, 碰到才结算。返回 false = 没有能打的(进度留着下一帧再试)
func _eternal(u: Dictionary, si: int, ck: String) -> bool:
	var best = null
	var bh := -1.0
	for o in _enemies(u):
		if battle._is_untargetable(o):
			continue
		if float(o.get("hp", 0.0)) > bh:
			bh = float(o.get("hp", 0.0))
			best = o
	if not (best is Dictionary):
		return false
	stat["eternal"] += 1
	var me: Dictionary = u
	var tg: Dictionary = best
	var sx: float = -1.0 if str(battle._eff_side(u)) == "left" else 1.0   # 左边队伍 ⇒ 从左上方飞来(从我方身后掷过去)
	var from := Vector2(tg["pos"]) + Vector2(sx * ETERNAL_FROM.x, -ETERNAL_FROM.y)
	var node = null
	var vx = _vfx()
	if vx != null and vx.has_method("eternal_fly"):
		node = vx.eternal_fly(from, tg)
	var tp: Array = battle._equip_sys.tally.push(u, ck)
	battle._ballistics.launch_flight(u, from, tg, ETERNAL_SPD,
		func(hit: bool) -> void:
			_fx("eternal_end", [node, hit, tg])
			if not hit or not tg.get("alive", false):
				return
			_eternal_hit(me, tg, si, ck, from),
		func(_k: float, p2: Vector2, to2: Vector2) -> void:
			_fx("eternal_step", [node, p2, to2]))
	battle._equip_sys.tally.pop(tp)
	return true


## 145 自己打出的伤害不算「造成伤害」的进度(否则按最大生命值算的大伤害自己喂自己, 一枪接一枪; 11-26 录像量到 3 秒就满第二枪):
##   每次 145 出伤害前后看 dmg_dealt 的差, 把进度基线一起往前挪
func _eter_self(me: Dictionary, ck: String, dd0: float) -> void:
	_set_acc(me, "eter_dd:" + ck, _acc(me, "eter_dd:" + ck) + maxf(0.0, float(me.get("dmg_dealt", 0.0)) - dd0))


func _eternal_hit(me: Dictionary, tg: Dictionary, si: int, ck: String, from: Vector2) -> void:
	stat["eternal_hit"] += 1
	var dd0: float = float(me.get("dmg_dealt", 0.0))
	var atk: float = float(me.get("atk", 0.0))
	var at := Vector2(tg["pos"])
	var dir: Vector2 = DetMath.norm(at - from) if DetMath.vlen(at - from) > 1.0 else Vector2(1.0, 0.0)
	_phys(me, tg, float(ETERNAL_HIT_ATK[si]) * atk + float(ETERNAL_HIT_HP[si]) * float(tg.get("maxHp", 0.0)))
	if tg.get("alive", false):
		if battle._damage.knock_blocked(tg):   # 免疫控制(或免击飞): 不倒不滑, 转而追加一段
			stat["eternal_imm"] += 1
			_phys(me, tg, float(ETERNAL_IMM_ATK[si]) * atk + float(ETERNAL_IMM_HP[si]) * float(tg.get("maxHp", 0.0)))
			_fx("eternal_immune", [tg])
		else:
			battle._damage._stun(tg, ETERNAL_STUN, "eternal_pin")
			tg["_kd_t0"] = float(battle._t)                      # 插倒(方案 A): 渲染按它把立绘往后倒、滑完躺一下再弹起
			tg["_kd_dir"] = 1.0 if dir.x >= 0.0 else -1.0         # 往滑行方向倒(背离来枪)
			var total: float = float(ETERNAL_SLIDE_ATK[si]) * atk + float(ETERNAL_SLIDE_HP[si]) * float(tg.get("maxHp", 0.0))
			_slides.append({"src": me, "o": tg, "dir": dir, "gone": 0.0, "total": total, "si": si, "ck": ck, "hit": [tg]})
			_fx("eternal_slide", [tg, dir, ETERNAL_SLIDE_SEC])
	_eter_self(me, ck, dd0)
	## 携带者临时生命值(到期按比例削回; 多次各自独立 = 叠加)
	if me.get("alive", false):
		var tmp: float = float(me.get("maxHp", 0.0)) * float(ETERNAL_TEMP[si])
		battle._trainer_sys._apply_temp_maxhp(me, tmp, ETERNAL_TEMP_SEC)
		_fx("eternal_temp", [me, int(tmp)])
	## 携带者身上的灼烧圈, 跟着携带者走(用户 11-26 晚「145 火圈应该是在携带者身上的」; 每个圈各自生效)
	if me.get("alive", false):
		_burns.append({"src": me, "until": float(battle._t) + ETERNAL_BURN_SEC, "next": float(battle._t) + 1.0, "si": si, "ck": ck})
		_fx("eternal_burn", [me, ETERNAL_BURN_R, ETERNAL_BURN_SEC])


## 145 击倒滑行: 目标按每一步往后滑(总距离 / 总时长), 这一步滑过的那一段里撞到的其他敌人各吃一次; 滑行伤害按这一步滑的距离分摊
func _tick_slides(delta: float) -> void:
	var keep: Array = []
	var step_len: float = ETERNAL_SLIDE / ETERNAL_SLIDE_SEC * delta
	for s in _slides:
		var o: Dictionary = s["o"]
		var src: Dictionary = s["src"]
		if not o.get("alive", false) or float(s["gone"]) >= ETERNAL_SLIDE - 0.01:
			_fx("eternal_slide_sum", [o, int(s.get("shown", 0))])   # 滑行伤害一路静默扣, 滑到头只跳一个总数(每步飘字会糊成一串, 11-26 录像)
			continue
		var a: Vector2 = Vector2(o["pos"])
		var mv: float = minf(step_len, ETERNAL_SLIDE - float(s["gone"]))
		var b: Vector2 = ArenaShape.clamp_in(a + Vector2(s["dir"]) * mv, battle.ARENA, 40.0)
		var real: float = DetMath.dist(a, b)
		o["pos"] = b
		s["gone"] = float(s["gone"]) + mv
		var tp: Array = battle._equip_sys.tally.push(src, str(s["ck"]))
		var sdd0: float = float(src.get("dmg_dealt", 0.0))
		if real > 0.0 and o.get("alive", false):
			var sd: int = battle._phys_after_armor(src, float(s["total"]) * real / ETERNAL_SLIDE, o)
			battle._damage.set_dtype("physical", o, false, true)
			battle._damage._apply_damage_from(src, o, sd, COL_PHYS, 0.0, false, true, false, false, true)
			s["shown"] = int(s.get("shown", 0)) + sd
		var si: int = int(s["si"])
		for e in _enemies(src):
			if _arr_has(s["hit"], e) or battle._is_untargetable(e):
				continue
			var q: Vector2 = DetMath.seg_closest(Vector2(e["pos"]), a, b)
			if DetMath.dist(q, Vector2(e["pos"])) <= ETERNAL_PASS_W + float(e.get("col_size", 22.0)) * 0.5:
				(s["hit"] as Array).append(e)
				stat["eternal_pass"] += 1
				_phys(src, e, float(ETERNAL_PASS_ATK[si]) * float(src.get("atk", 0.0)) + float(ETERNAL_PASS_HP[si]) * float(e.get("maxHp", 0.0)))
				_fx("eternal_pass", [e])
		_eter_self(src, str(s["ck"]), sdd0)
		battle._equip_sys.tally.pop(tp)
		if real < mv * 0.5:   # 撞到场地边缘: 停
			s["gone"] = ETERNAL_SLIDE
		keep.append(s)
	_slides = keep


## 145 灼烧圈: 每秒对圈内敌人各自最大生命值 × ETERNAL_BURN_PCT 的魔法伤害
func _tick_burns() -> void:
	var t := float(battle._t)
	var keep: Array = []
	for z in _burns:
		var src: Dictionary = z["src"]
		if t >= float(z["until"]) or not src.get("alive", false):
			continue
		if t >= float(z["next"]):
			z["next"] = float(z["next"]) + 1.0
			var tp: Array = battle._equip_sys.tally.push(src, str(z["ck"]))
			var bdd0: float = float(src.get("dmg_dealt", 0.0))
			_fx("eternal_burn_tick", [src, ETERNAL_BURN_R])
			for e in _enemies(src):
				if DetMath.dist(Vector2(e["pos"]), Vector2(src["pos"])) <= ETERNAL_BURN_R + float(e.get("col_size", 22.0)) * 0.5:
					stat["eternal_burn"] += 1
					_magic(src, e, float(e.get("maxHp", 0.0)) * float(ETERNAL_BURN_PCT[int(z["si"])]))
					_fx("eternal_burn_lick", [e])
			_eter_self(src, str(z["ck"]), bdd0)
			battle._equip_sys.tally.pop(tp)
		keep.append(z)
	_burns = keep


static func _arr_has(arr: Array, x) -> bool:
	for y in arr:
		if is_same(y, x):
			return true
	return false


## 146 圣枪每帧: ① 每一路首次低于 50% 生命 ⇒ 圣枪护盾 + 双抗; ② 每 12 秒开始引导, 引导中每 0.25 秒耗储能出一个光球, 不够就结束。
##   引导期间照常移动攻击(用户没说要定身); 引导中拿到的护盾照样存进来(存的口在 holy_store, 不分是否引导)。
func _tick_holy(u: Dictionary, si: int, ck: String, delta: float) -> void:
	if _acc(u, "holy_g:" + ck) <= 0.0 and float(u.get("hp", 0.0)) < float(u.get("maxHp", 0.0)) * HOLY_GUARD_AT:
		_set_acc(u, "holy_g:" + ck, 1.0)
		stat["holy_guard"] += 1
		battle._damage._buff(u, "def", float(HOLY_RESIST[si]), false, 99999.0)   # 到这一路结束(换路单位重建, buff 随之清)
		battle._damage._buff(u, "mr", float(HOLY_RESIST[si]), false, 99999.0)
		_fx("holy_guard", [u, int(HOLY_RESIST[si])])
		## 每份 = 触发那一刻的最大生命 × 合计比例 ÷ 份数(之后临时等级涨了最大生命也不改这一份)
		_set_acc(u, "holy_gper:" + ck, float(u.get("maxHp", 0.0)) * float(HOLY_GUARD_PCT[si]) / float(HOLY_GUARD_SEC))
		_set_acc(u, "holy_gn:" + ck, 0.0)
		_set_acc(u, "holy_ga:" + ck, 1.0)   # 触发这一步就给第 1 份
	var gn := int(_acc(u, "holy_gn:" + ck))
	if _acc(u, "holy_g:" + ck) > 0.0 and gn < HOLY_GUARD_SEC:
		var ga := _acc(u, "holy_ga:" + ck) + (0.0 if gn == 0 else delta)
		if ga >= 1.0:
			ga -= 1.0
			_holy_guard_part(u, _acc(u, "holy_gper:" + ck))
			_set_acc(u, "holy_gn:" + ck, float(gn + 1))
		_set_acc(u, "holy_ga:" + ck, ga)
	var a := _acc(u, "holy_t:" + ck) + delta
	if a >= HOLY_IV:
		a -= HOLY_IV
		if _acc(u, "holy_ch:" + ck) <= 0.0:
			_set_acc(u, "holy_ch:" + ck, 1.0)
			_set_acc(u, "holy_oi:" + ck, 0.0)   # 开始引导的这一步就出第一个
			stat["holy_channel"] += 1
			_fx("holy_channel", [u, true])
	_set_acc(u, "holy_t:" + ck, a)
	if _acc(u, "holy_ch:" + ck) <= 0.0:
		return
	var oi := _acc(u, "holy_oi:" + ck) - delta
	var cost: float = float(HOLY_ORB_COST[si])
	while oi <= 0.0:
		var hs: Dictionary = u.get("_holy_store", {})
		var have: float = float(hs.get(ck, 0.0))
		if have < cost:
			_set_acc(u, "holy_ch:" + ck, 0.0)
			_fx("holy_channel", [u, false])
			oi = 0.0
			break
		hs[ck] = have - cost
		u["_holy_store"] = hs
		_holy_orb(u, si, ck)
		oi += HOLY_ORB_IV
	_set_acc(u, "holy_oi:" + ck, oi)


## 圣枪护盾的一份: 进护盾池, 另记标记 _spearShieldVal(血条画金色段 / 面板单列); 不弹通用得盾罩、不跳通用「+N 盾」, 演出自己画
func _holy_guard_part(u: Dictionary, amt: float) -> void:
	if amt <= 0.0 or not u.get("alive", false):
		return
	var sb: float = float(u.get("shield", 0.0))
	u["_own_grant_vfx"] = true
	u["_own_grant_txt"] = true
	battle._damage._grant_shield(u, amt)   # shield-perm-ok: 146 圣枪护盾「不会衰减」(用户 11-26 晚: 特殊护盾; 文案写明)
	var got: float = maxf(0.0, float(u.get("shield", 0.0)) - sb)
	u["_spearShieldVal"] = minf(float(u.get("_spearShieldVal", 0.0)) + got, float(u.get("shield", 0.0)))
	stat["holy_guard_part"] += 1
	_fx("holy_guard_tick", [u, int(got)])


## 光球候选: 友方只有统领与小将(含携带者自己; 不含召唤物 / 龟蛋 / 训龟大师), 敌方是全部可选中的单位(含召唤物)。
func holy_pool(u: Dictionary) -> Array:
	var out: Array = []
	for o in battle._targeting._allies_of(u, true):
		if o.get("alive", false) and not bool(o.get("is_summon", false)) and not bool(o.get("_isEgg", false)):
			out.append(o)
	for o in battle._targeting._targetable_enemies(u):
		out.append(o)
	return out


func _holy_orb(u: Dictionary, si: int, ck: String) -> void:
	var pool: Array = holy_pool(u)
	if pool.is_empty():
		return
	var tg: Dictionary = pool[battle._battle_rng.randi() % pool.size()]
	var ally: bool = is_same(tg, u) or battle._is_ally(u, tg)   # ★_is_ally(u, u) 是 false: 砸到自己要按友方算(用户「光球也可以给到携带者自己」)
	stat["holy_orb"] += 1
	var me: Dictionary = u
	var node = null
	var vx = _vfx()
	if vx != null and vx.has_method("holy_orb_fly"):
		node = vx.holy_orb_fly(u, tg, ally)
	var tp: Array = battle._equip_sys.tally.push(u, ck)
	battle._ballistics.launch_flight(u, Vector2(u["pos"]), tg, HOLY_ORB_SPD,
		func(hit: bool) -> void:
			_fx("holy_orb_end", [node, hit, tg, ally])
			if not hit or not tg.get("alive", false):
				return
			if ally:
				stat["holy_ally"] += 1
				battle._equip_tick_sys.holy_level_up(tg)
				battle._damage._heal(tg, float(HOLY_ORB_HEAL[si]))
			else:
				stat["holy_enemy"] += 1
				_magic(me, tg, float(HOLY_ORB_DMG[si]))
				if me.get("alive", false):
					me["_own_grant_vfx"] = true   # 不弹通用得盾罩: 一次引导几十个光球, 每个都弹会把携带者整个盖住(11-26 录像); 演出是光点飞回携带者
					battle._damage._grant_shield(me, float(HOLY_ORB_SHIELD[si]), BattleDamage.COMMON_SHIELD_SEC)   # 文案没写时长 ⇒ 通用护盾 4 秒(封板)
					_fx("holy_shield_back", [tg, me]),
		func(_k: float, p2: Vector2, to2: Vector2) -> void:
			_fx("holy_orb_step", [node, p2, to2]))
	battle._equip_sys.tally.pop(tp)


func clear_all() -> void:
	_slides.clear()
	_burns.clear()
	_waves.clear()
	_pulls.clear()
	_swaves.clear()
	_slams.clear()
	_drops.clear()


func reset_match() -> void:
	pass
