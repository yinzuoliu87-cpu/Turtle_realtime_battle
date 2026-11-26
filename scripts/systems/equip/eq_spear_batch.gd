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
const ETERNAL_IV := 8.0
const ETERNAL_PIN := 1.5
const ETERNAL_PCT := [0.08, 0.12, 0.20]
const ETERNAL_SPD := 1100.0
# ── 146 圣枪(待重新设计) ──
const HOLY_STACKS := 3
const HOLY_DMG := [150.0, 250.0, 500.0]
const HOLY_HEAL := [0.05, 0.08, 0.12]

var stat := {"bamboo": 0, "bamboo_hit": 0, "harpoon": 0, "harpoon_hit": 0, "harpoon_pull": 0, "jav": 0, "jav_hit": 0,
	"lance": 0, "halb": 0, "halb_hit": 0, "shsp_raise": 0, "shsp_block": 0, "shsp_release": 0, "shsp_wave_hit": 0,
	"ftj": 0, "ftj_hit": 0, "ftj_spin": 0, "atl": 0, "atl_hit": 0, "eternal": 0, "eternal_hit": 0, "holy": 0}
var _waves: Array = []    # 137 竹刺浪 {src, ck, o(起点), dir, r, si, hit, sp(下一丛竹刺的距离)}
var _pulls: Array = []    # 138 拉拽 {src, o, left, t_next}
var _swaves: Array = []   # 142 冲击波 {src, ck, o, dir, r, per, hit}
var _slams: Array = []    # 143 {u, ck, si, t, phase}
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


static func _si_of(e: Dictionary) -> int:
	return clampi(int(e.get("star", 1)), 1, 3) - 1


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
		"p2eq_146":   # 圣枪: 圣痕 3 层引爆(待重新设计)
			var key := "holy:" + ck
			var marks: Dictionary = t.get("_holy_marks", {})
			var uid := str(u.get("_spear_uid", ""))
			if uid == "":
				_uid_n += 1
				uid = "s%d" % _uid_n
				u["_spear_uid"] = uid
			var mk: String = uid + key
			var nm := int(marks.get(mk, 0)) + 1
			if nm >= HOLY_STACKS:
				marks.erase(mk)
				stat["holy"] += 1
				var dmg: int = battle._resolve_dmg(u, float(HOLY_DMG[si]), t, true, false)
				battle._damage._apply_damage_from(u, t, dmg, COL_MAGIC, 0.0, false, true)
				battle._damage._heal(u, float(u.get("maxHp", 0.0)) * float(HOLY_HEAL[si]))
				_fx("holy_burst", [u, t])
			else:
				marks[mk] = nm
				_fx("holy_stigma", [t, nm])   # 不叫 holy_mark: 魔法书演出层(父类)有同名的 122 治愈圣典标记, 会画成别人的招牌
			t["_holy_marks"] = marks


static var _uid_n := 0


func on_hit(_src: Dictionary, _tgt: Dictionary, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 143 方天画戟: 受到伤害攒战意(攻击 / 技能 / 持续伤害都算; 蓄力 / 跃起期间和横扫状态里不攒)
func on_damaged(u: Dictionary, _src, dmg: float, eid: String, si: int) -> void:
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
			var along: float = rel.dot(dir)
			var half: float = float(o.get("col_size", 22.0)) * 0.5
			if along < r0 - half or along > r1 + half:
				continue
			if absf(rel.dot(Vector2(-dir.y, dir.x))) > BAMBOO_W + half:
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
			if d > 1.0 and DetMath.norm(rel).dot(Vector2(w["dir"])) < SHSP_WAVE_ARC:
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
		if not ["p2eq_140", "p2eq_142", "p2eq_143"].has(eid):
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
		if not ["p2eq_138", "p2eq_139", "p2eq_140", "p2eq_141", "p2eq_142", "p2eq_144", "p2eq_145"].has(eid):
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
			"p2eq_145":
				var a4 := _acc(u, "eter:" + ck) + delta
				if a4 >= ETERNAL_IV:
					a4 -= ETERNAL_IV
					_eternal(u, si, ck)
				_set_acc(u, "eter:" + ck, a4)
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
				_pulls.append({"src": me, "o": tg, "left": int(round(HARPOON_STUN / HARPOON_PULL_IV)), "t_next": float(battle._t) + HARPOON_PULL_IV}),
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
		if dd > 1.0 and DetMath.norm(rel).dot(fdir) < HALB_ARC:
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
			if d <= SHSP_WAVE_LEN + float(o.get("col_size", 22.0)) * 0.5 and (d <= 1.0 or DetMath.norm(rel).dot(dir) >= SHSP_WAVE_ARC):
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
		var at: Vector2 = ArenaShape.clamp_in(c + Vector2(cos(ang), sin(ang)) * rr, battle.ARENA, 20.0)
		var tf: float = t + ATL_SPREAD_SEC * float(i) / float(maxi(1, n - 1))
		_drops.append({"src": u, "ck": ck, "at": at, "t_fire": tf, "t_land": tf + fall, "si": si, "fired": false})


## 145 永恒之枪(待重新设计): 生命值最高的敌人; 按速度飞到才结算: 钉住 1.5 秒 + 目标最大生命值 % 物理伤害
func _eternal(u: Dictionary, si: int, ck: String) -> void:
	var best = null
	var bh := -1.0
	for o in _enemies(u):
		if battle._is_untargetable(o):
			continue
		if float(o.get("hp", 0.0)) > bh:
			bh = float(o.get("hp", 0.0))
			best = o
	if not (best is Dictionary):
		return
	stat["eternal"] += 1
	var me: Dictionary = u
	var tg: Dictionary = best
	var pct: float = float(ETERNAL_PCT[si])
	var node = null
	var vx = _vfx()
	if vx != null and vx.has_method("eternal_fly"):
		node = vx.eternal_fly(u, tg)
	var tp: Array = battle._equip_sys.tally.push(u, ck)
	battle._ballistics.launch_flight(u, Vector2(u["pos"]), tg, ETERNAL_SPD,
		func(hit: bool) -> void:
			_fx("eternal_end", [node, hit, tg])
			if not hit or not tg.get("alive", false):
				return
			stat["eternal_hit"] += 1
			_phys(me, tg, float(tg.get("maxHp", 0.0)) * pct)
			if tg.get("alive", false):
				battle._damage._stun(tg, ETERNAL_PIN, "eternal_pin"),
		func(_k: float, p2: Vector2, to2: Vector2) -> void:
			_fx("eternal_step", [node, p2, to2]))
	battle._equip_sys.tally.pop(tp)


func clear_all() -> void:
	_waves.clear()
	_pulls.clear()
	_swaves.clear()
	_slams.clear()
	_drops.clear()


func reset_match() -> void:
	pass
