class_name EqMagicBatch
extends RefCounted
const _SummonEnergy := preload("res://scripts/gamedata/summon_energy.gd")
## eq_magic_batch.gd —— 魔法书羁绊 10 件新装备的效果本体(2026-11-25 · 方案书 docs/plans/20261125b-魔法书羁绊.md §4.2)
##   117 学徒笔记 · 118 羊皮咒卷 · 119 烈焰法典 · 120 霜语魔典 · 121 风暴之书 · 122 治愈圣典 · 123 亡者之书(召唤三种骷髅)
##   · 124 镜像魔典(再放一次) · 125 禁咒全书 · 126 浮空魔典(近战书页环绕 / 远程书页格挡)
##
## 接口 = 批④统一口(b4_owner.gd → `_b4`): on_spawn / on_basic / on_hit / on_damaged / on_magic_hurt / on_death / on_mana_full
##   / tick / tick_unit / clear_all; 另加:
##   · `on_unit_cast(u, tgt, stype, cost, echo)` —— 携带者每释放一次技能(MagicbookSynergySystem.after_cast 转来, 龟本体的两条施法路都走它)。
##     「这次技能消耗的龟能」= cost(= battle._skill_cost, 已扣掉 125 的最大龟能减少)。echo = 这一次是 124 镜像魔典的「再放一次」。
##   · `page_block(u, d)` —— 126 远程书页格挡(battle_damage._apply_damage_from 护盾前调; 持续伤害走另一条路, 不挡)。
##
## ── 地雷对照(CLAUDE.md §4) ────────────────────────────────────────
##   §4.1 「X% 最大生命」一律真实 maxHp。 §4.2 单位字典不当键: 在途表存字典本身, 比较 is_same。
##   §4.3 只发伤害、不改伤害流程: 魔法 `_resolve_dmg(magic=true)` + `_apply_damage_from(from_equip)`。
##   §4.4 `_t` 跨路累加: 到期时刻都存绝对 `_t`, 换路 clear_all 整表清。
##   随机: 121 挑 3 名、123 挑骷髅种类都走已播种的 `battle._battle_rng`。
##   会走的波(123 祭司亡灵浪潮): 每步线段碰撞, 命中名单防重复(memory fb-moving-hits-collide-per-step)。
##   飞行物(117 / 119 / 125 / 骷髅法师普攻): 一律按速度飞, 碰到身体才结算(memory fb-projectiles-have-speed-not-fixed-time)。
var battle
var vfx = null

# ── 117 学徒笔记 ──
const NOTE_EVERY := 3
const NOTE_FLAT := [20.0, 35.0, 60.0]
const NOTE_ATK := 0.3
const NOTE_SPD := 900.0
# ── 118 羊皮咒卷 ──
const SCROLL_SHIELD := [60.0, 110.0, 200.0]
const SCROLL_SEC := 4.0
# ── 119 烈焰法典 ──
const FIRE_FLAT := [50.0, 90.0, 150.0]
const FIRE_ATK := 0.6
const FIRE_BURN_PER_EN := [0.10, 0.15, 0.25]
const FIRE_SPD := 800.0
# ── 120 霜语魔典 ──
const FROST_R := 300.0
const FROST_FLAT := [30.0, 50.0, 90.0]
const FROST_ATK := 0.3
const FROST_SEC_PER_EN := [0.02, 0.025, 0.03]
const FROST_MOVE_DOWN := 0.20   # 冰寒: 移动速度 −20%(同 028 冰冻药剂)
const FROST_ASPD_DOWN := 0.10   # 攻击速度 −10%
# ── 121 风暴之书 ──
const STORM_IV := 6.0
const STORM_N := 3
const STORM_FLAT := [40.0, 70.0, 120.0]
const STORM_ATK := 0.4
# ── 122 治愈圣典 ──
const HOLY_FLAT := [20.0, 35.0, 60.0]
const HOLY_ATK := [0.10, 0.15, 0.20]
const HOLY_SEC_PER_EN := 0.1
# ── 123 亡者之书 ──
const SKEL_SEC_PER_EN := 0.15
const SKEL_EN_MAX := 80.0
const SKEL_KINDS := ["skel_warrior", "skel_mage", "skel_priest"]
const SKW_HP := [500.0, 1000.0, 2400.0]
const SKW_IV := 1.0       # 攻击间隔(秒)
const SKW_RANGE := 60.0
const SKM_IV := 1.3
const SKM_RANGE := 420.0
const SKP_IV := 1.2
const SKP_RANGE := 400.0
const SKW_ATK := [30.0, 60.0, 140.0]
const SKW_RES := [40.0, 70.0, 120.0]
const SKM_HP := [300.0, 600.0, 1400.0]
const SKM_ATK := [45.0, 90.0, 210.0]
const SKM_RES := [20.0, 35.0, 60.0]
const SKP_HP := [350.0, 700.0, 1600.0]
const SKP_ATK := [20.0, 40.0, 90.0]
const SKP_RES := [30.0, 50.0, 90.0]
## 技能前摇(秒) = 技能动作从起手到出招帧的时长(MagicEqVfx 按它定帧率, 出招帧落在结算那一刻)
const SKEL_WINDUP := {"skel_warrior": 0.35, "skel_mage": 0.4, "skel_priest": 0.35}
const SKW_RAGE_SEC := 4.0
const SKW_DR := 0.25
const SKW_EXTRA := 0.5
const SKW_LS := 0.25
const SKW_RAGE_TINT := Color(0.78, 1.2, 0.62)
const SKM_BLAST_R := 200.0
const SKM_BLAST_ATK := 2.0
const SKP_BASIC := 0.6   # 祭司普攻 60% 攻击力魔法(主场景 BASIC_ATK["_summon_skel_priest"] 读它)
const SKM_BASIC := 1.0   # 法师普攻 100% 攻击力魔法(BASIC_ATK["_summon_skel_mage"])
const WAVE_SPD := 300.0
const WAVE_LEN := 700.0
const WAVE_W := 60.0
const WAVE_DMG := [80.0, 160.0, 360.0]
const WAVE_HEAL := [80.0, 160.0, 360.0]
const WAVE_KNOCK_VY := 11.0   # 滞空 = 2 × 11 / 22 = 1 秒
const WAVE_STUN := 1.5
const WAVE_MR_SHRED := 0.25
const WAVE_MR_SEC := 4.0
# ── 124 镜像魔典 ──
const MIRROR_THR := [400.0, 300.0, 200.0]
const ECHO_DELAY := 0.35   # 「立刻再释放一次」: 隔一个短拍再放, 看得出是两次
# ── 125 禁咒全书 ──
const FORB_FLAT := [100.0, 200.0, 600.0]
const FORB_ATK := 0.8
const FORB_MAXHP := [0.04, 0.06, 0.10]
const FORB_SPLASH_R := 200.0
const FORB_SPLASH := 0.5
const FORB_CUT := [10.0, 15.0, 25.0]
const FORB_SPD := 1000.0
# ── 126 浮空魔典 ──
const PAGE_N := [3, 4, 6]
const PAGE_R := 120.0
const PAGE_W := 1.4          # 环绕角速度(弧度/秒; 11-25 用户「转速这么快吗？这太快了呀」3.0 → 1.4, 转一圈约 4.5 秒)
const PAGE_HIT_R := 45.0     # 书页碰到敌人的判定半径(书页半宽 + 余量; 再加敌人自己的碰撞半径)
const PAGE_FLAT := [10.0, 20.0, 50.0]
const PAGE_ATK := 0.1
const PAGE_SHIELD := [15.0, 30.0, 70.0]
const PAGE_SHIELD_SEC := 4.0
const PAGE_SHIELD_CAP := [200.0, 400.0, 1000.0]
const PAGE_REGEN := [4.0, 3.5, 3.0]
const PAGE_BLOCK_PCT := 0.06
const PAGE_BLOCK_MAX := [300.0, 600.0, 1500.0]
const TOME_HP := [300.0, 700.0, 2000.0]
const TOME_SEC_PER_EN := 0.06

const SEC_PER_ENERGY := 0.075
const COL_MAGIC := Color("#4dabf7")
const COL_PHYS := Color("#ff9a4a")

var _hots: Array = []      ## 122 持续回复 {tgt, per, until, acc, tl}
var _skels: Array = []     ## 123 骷髅 {u, owner, kind, si, en, until, rage_until}
var _waves: Array = []     ## 123 祭司亡灵浪潮 {src, pos, dir, left, si, hit:[]}
var _echo: Array = []      ## 124 再放一次 {u, tgt, stype, at, tl}
var _temphp: Array = []    ## 126 临时最大生命 {u, amt, until}
## 门禁量
var stat := {"note": 0, "scroll": 0, "fire": 0, "frost": 0, "storm": 0, "holy": 0, "holy_heal": 0.0, "skel": 0,
	"skel_cast": 0, "wave_hit": 0, "echo": 0, "forb": 0, "page_hit": 0, "page_block": 0, "page_absorb": 0.0, "temphp": 0}


func _init(b) -> void:
	battle = b
	vfx = MagicEqVfx.new(b)


func _fx(method: String, args: Array = []) -> void:
	if vfx != null and vfx.has_method(method):
		vfx.callv(method, args)


# ════════════════════════════════════════ 小工具 ════════════════════════════════════════

func _enemies_of(u: Dictionary) -> Array:
	var out: Array = []
	var side := str(battle._eff_side(u))
	for o in battle._units:
		if not (o is Dictionary) or not o.get("alive", false):
			continue
		if str(battle._eff_side(o)) == side or bool(o.get("_isEgg", false)) or battle._is_untouchable(o):
			continue
		out.append(o)
	return out


func _allies_of(u: Dictionary) -> Array:
	var out: Array = []
	var side := str(battle._eff_side(u))
	for o in battle._units:
		if o is Dictionary and o.get("alive", false) and str(battle._eff_side(o)) == side and not bool(o.get("_isEgg", false)) \
				and not battle._is_untouchable(o):
			out.append(o)
	return out


func _magic(src: Dictionary, tgt: Dictionary, base: float, can_crit: bool = true) -> void:
	if not tgt.get("alive", false) or base <= 0.0:
		return
	var dmg: int = battle._resolve_dmg(src, base, tgt, true, can_crit)
	battle._damage._apply_damage_from(src, tgt, dmg, COL_MAGIC, 0.0, false, true)


func _acc(u: Dictionary, key: String) -> float:
	var d: Dictionary = u.get("_magic_acc", {})
	return float(d.get(key, 0.0))


func _set_acc(u: Dictionary, key: String, v: float) -> void:
	var d: Dictionary = u.get("_magic_acc", {})
	d[key] = v
	u["_magic_acc"] = d


func _en_gain(u: Dictionary, delta: float) -> float:
	## 召唤物龟能: 和龟的技能充能同一套规矩(锁 / 加减速 / 时停), 见 summon_energy.gd(11-27 统一)
	return _SummonEnergy.gain(u, float(battle._t), delta)


func _nearest_enemy(u: Dictionary):
	var best = null
	var bd := INF
	for o in _enemies_of(u):
		var d: float = DetMath.dist(Vector2(u["pos"]), Vector2(o["pos"]))
		if d < bd:
			bd = d
			best = o
	return best


static func _si_of(e: Dictionary) -> int:
	return clampi(int(e.get("star", 1)), 1, 3) - 1


# ════════════════════════════════════════ 批④统一口 ════════════════════════════════════════

func on_spawn(u: Dictionary, eid: String, si: int) -> void:
	match eid:
		"p2eq_125":   # 禁咒全书②: 技能条的最大龟能减少(_skill_cost 读 energy_cut ⇒ 消耗与充能时间一起少; 多件相加)
			u["energy_cut"] = float(u.get("energy_cut", 0.0)) + float(FORB_CUT[si])
		"p2eq_126":   # 浮空魔典: 开打时按携带者近战 / 远程定一套, 一场不变
			var ck: String = battle._equip_sys.key_of(u, eid)
			var melee := bool(u.get("melee", false))
			u["_mb_pages"] = true
			_set_acc(u, "pmode:" + ck, 1.0 if melee else 2.0)
			_set_acc(u, "pages:" + ck, float(PAGE_N[si]))   # 远程: 现有书页(开打满)
			_fx("pages_spawn", [u, ck, int(PAGE_N[si]), melee])


func on_basic(u: Dictionary, tgt, eid: String, si: int) -> void:
	if not (tgt is Dictionary) or not tgt.get("alive", false):
		return
	var ck: String = battle._equip_sys.key_of(u, eid)
	match eid:
		"p2eq_117":   # 学徒笔记: 每第 3 次攻击额外射出一枚追踪魔法飞弹
			var n := int(_acc(u, "note:" + ck)) + 1
			if n < NOTE_EVERY:
				_set_acc(u, "note:" + ck, float(n))
				return
			_set_acc(u, "note:" + ck, 0.0)
			stat["note"] += 1
			var base: float = float(NOTE_FLAT[si]) + NOTE_ATK * float(u.get("atk", 0.0))
			var src: Dictionary = u
			var t: Dictionary = tgt
			var node = vfx.note_launch(u, t) if vfx != null else null
			var from2 := Vector2(u["pos"])
			battle._ballistics.launch_flight(u, from2, t, NOTE_SPD,
				func(hit: bool) -> void:
					_fx("note_land", [node, t, hit])
					if hit:
						_magic(src, t, base),
				func(k: float, p2: Vector2, to2: Vector2) -> void: _fx("bolt_step", [node, from2, p2, to2, k]))
		"p2eq_125":   # 禁咒全书①: 放过技能后的下一次攻击变成禁咒弹
			if _acc(u, "forb:" + ck) <= 0.0:
				return
			_set_acc(u, "forb:" + ck, 0.0)
			stat["forb"] += 1
			u["_basic_replaced"] = true   # 这一下攻击本身就是禁咒弹(主场景普攻本体看到这个标记就不再打原来的攻击)
			var src2: Dictionary = u
			var t2: Dictionary = tgt
			var base2: float = float(FORB_FLAT[si]) + FORB_ATK * float(u.get("atk", 0.0))
			var pct: float = float(FORB_MAXHP[si])
			var node2 = vfx.forb_launch(u, t2) if vfx != null else null
			var from3 := Vector2(u["pos"])
			_fx("forb_ready", [u, false])
			battle._ballistics.launch_flight(u, from3, t2, FORB_SPD,
				func(hit: bool) -> void:
					_fx("forb_land", [node2, t2])
					if hit:
						_forb_hit(src2, t2, base2, pct),
				func(k: float, p2: Vector2, to2: Vector2) -> void: _fx("bolt_step", [node2, from3, p2, to2, k]))


func _forb_hit(src: Dictionary, tgt: Dictionary, base: float, pct: float) -> void:
	var c := Vector2(tgt["pos"])
	var main: float = base + pct * float(tgt.get("maxHp", 0.0))
	_magic(src, tgt, main)
	for o in _enemies_of(src):
		if is_same(o, tgt) or DetMath.dist(Vector2(o["pos"]), c) > FORB_SPLASH_R:
			continue
		_magic(src, o, (base + pct * float(o.get("maxHp", 0.0))) * FORB_SPLASH)


func on_hit(_src: Dictionary, _tgt: Dictionary, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_damaged(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_death(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


func on_mana_full(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


## 任何单位普攻(EquipSystem._eq_on_basic_attack 最前面调): 骷髅战士【骸骨狂怒】期间的额外物理伤害
func on_any_basic(u: Dictionary, tgt) -> void:
	if str(u.get("id", "")) != "_summon_skel_warrior" or not (tgt is Dictionary) or not tgt.get("alive", false):
		return
	if float(battle._t) >= float(u.get("_skw_rage_until", 0.0)):
		return
	var dmg: int = battle._resolve_dmg(u, SKW_EXTRA * float(u.get("atk", 0.0)), tgt, false)
	battle._damage._apply_damage_from(u, tgt, dmg, COL_PHYS, 0.0, false, true)
	_fx("skw_rage_hit", [u, tgt])


# ════════════════════════════════════════ 释放技能(124 / 118 / 119 / 120 / 122 / 123 / 125 / 126) ════════════════════════════════════════

## 携带者释放了一次技能(cost = 这次消耗的龟能)。echo = 124 的「再放一次」(完整效果, 但不往充能条里存、不再触发再放)。
func on_unit_cast(u: Dictionary, tgt, stype: String, cost: float, echo: bool) -> void:
	if u.get("equips", []).is_empty() or not u.get("alive", false):
		return
	var es = battle._equip_sys
	var ckp: Array = es.ck_save()
	for e in u["equips"]:
		if not (e is Dictionary):
			continue
		var eid := str(e.get("id", ""))
		if not ["p2eq_118", "p2eq_119", "p2eq_120", "p2eq_122", "p2eq_123", "p2eq_124", "p2eq_125", "p2eq_126"].has(eid):
			continue
		var si := _si_of(e)
		es.ck_set(u, e)
		var ck: String = es.key_of(u, eid)
		var tl: Array = es.tally.push(u, ck)
		match eid:
			"p2eq_118": _scroll(u, si)
			"p2eq_119": _fireball(u, si, cost)
			"p2eq_120": _frost_nova(u, si, cost)
			"p2eq_122": _holy(u, si, cost)
			"p2eq_123": _summon_skeleton(u, si, cost)
			"p2eq_124":
				if not echo:
					_mirror(u, tgt, stype, cost, si, ck)
			"p2eq_125":
				_set_acc(u, "forb:" + ck, 1.0)
				_fx("forb_ready", [u, true])
			"p2eq_126": _tome_hp(u, si, cost)
		es.tally.pop(tl)
	es.ck_restore(ckp)


## 118 羊皮咒卷: 护盾 4 秒
func _scroll(u: Dictionary, si: int) -> void:
	stat["scroll"] += 1
	battle._damage._grant_shield(u, float(SCROLL_SHIELD[si]), SCROLL_SEC)
	_fx("scroll_shield", [u])


## 119 烈焰法典: 朝最近的敌人扔一颗火球, 命中魔法伤害 + 灼烧(层数随这次消耗的龟能)
func _fireball(u: Dictionary, si: int, cost: float) -> void:
	var tgt = _nearest_enemy(u)
	if not (tgt is Dictionary):
		return
	stat["fire"] += 1
	var t: Dictionary = tgt
	var src: Dictionary = u
	var base: float = float(FIRE_FLAT[si]) + FIRE_ATK * float(u.get("atk", 0.0))
	var stacks := int(floor(cost * float(FIRE_BURN_PER_EN[si])))
	var node = vfx.fire_launch(u, t) if vfx != null else null
	var from2 := Vector2(u["pos"])
	battle._ballistics.launch_flight(u, from2, t, FIRE_SPD,
		func(hit: bool) -> void:
			_fx("fire_land", [node, t])
			if hit:
				_magic(src, t, base)
				if t.get("alive", false) and stacks > 0:
					battle._damage._apply_dot_stacks(t, "burn", stacks, src),
		func(k: float, p2: Vector2, to2: Vector2) -> void: _fx("bolt_step", [node, from2, p2, to2, k]))


## 120 霜语魔典: 周围 300 码冰霜新星 + 冰寒(时长随这次消耗的龟能)
func _frost_nova(u: Dictionary, si: int, cost: float) -> void:
	stat["frost"] += 1
	var c := Vector2(u["pos"])
	var base: float = float(FROST_FLAT[si]) + FROST_ATK * float(u.get("atk", 0.0))
	var sec: float = cost * float(FROST_SEC_PER_EN[si])
	_fx("frost_nova", [c, FROST_R])
	for o in _enemies_of(u):
		if DetMath.dist(Vector2(o["pos"]), c) > FROST_R:
			continue
		_magic(u, o, base)
		if o.get("alive", false) and sec > 0.0:
			battle._damage.apply_chill(o, 1.0 - FROST_MOVE_DOWN, 1.0 - FROST_ASPD_DOWN, sec)


## 122 治愈圣典: 给生命比例最低的友军挂持续回复(每秒一跳, 时长随这次消耗的龟能)
func _holy(u: Dictionary, si: int, cost: float) -> void:
	var best = null
	var br := 9.0
	for o in _allies_of(u):
		var r := float(o["hp"]) / maxf(1.0, float(o.get("maxHp", 1.0)))
		if r < br:
			br = r
			best = o
	var sec: float = cost * HOLY_SEC_PER_EN
	if not (best is Dictionary) or sec <= 0.0:
		return
	stat["holy"] += 1
	var per: float = float(HOLY_FLAT[si]) + float(HOLY_ATK[si]) * float(u.get("atk", 0.0))
	_hots.append({"tgt": best, "per": per, "until": float(battle._t) + sec, "acc": 0.0, "tl": battle._equip_sys.tally.capture()})
	_fx("holy_mark", [best, sec])


func _tick_hots(delta: float) -> void:
	if _hots.is_empty():
		return
	var t := float(battle._t)
	var keep: Array = []
	var tl0: Array = battle._equip_sys.tally.capture()
	for h in _hots:
		var o: Dictionary = h["tgt"]
		if not o.get("alive", false):
			continue
		h["acc"] = float(h["acc"]) + delta
		if float(h["acc"]) >= 1.0:
			h["acc"] = float(h["acc"]) - 1.0
			battle._equip_sys.tally.use(h["tl"])
			stat["holy_heal"] += battle._damage._heal(o, float(h["per"]))
		if t < float(h["until"]):
			keep.append(h)
	battle._equip_sys.tally.pop(tl0)
	_hots = keep


## 126 浮空魔典通用: 释放技能后临时最大生命值(同时回复等量), 时长随这次消耗的龟能; 到期按比例削(同训龟大师口哨)
func _tome_hp(u: Dictionary, si: int, cost: float) -> void:
	var sec: float = cost * TOME_SEC_PER_EN
	if sec <= 0.0:
		return
	stat["temphp"] += 1
	var amt: float = float(TOME_HP[si])
	u["maxHp"] = float(u["maxHp"]) + amt
	u["hp"] = float(u["hp"]) + amt
	_temphp.append({"u": u, "amt": amt, "until": float(battle._t) + sec})
	_fx("tome_hp", [u, sec])


func _tick_temphp() -> void:
	if _temphp.is_empty():
		return
	var t := float(battle._t)
	var keep: Array = []
	for r in _temphp:
		if t < float(r["until"]):
			keep.append(r)
			continue
		var uu: Dictionary = r["u"]
		if not uu.get("alive", false):
			continue
		var old_max: float = float(uu["maxHp"])
		var new_max: float = maxf(1.0, old_max - float(r["amt"]))
		uu["hp"] = float(uu["hp"]) * (new_max / old_max)
		uu["maxHp"] = new_max
	_temphp = keep


# ════════════════════════════════════════ 124 镜像魔典 ════════════════════════════════════════

## 每一路首次释放技能 ⇒ 再放一次; 另把消耗的龟能存进充能条, 存满(400/300/200)清空, 下一次释放技能 ⇒ 再放一次。
## 单位每路重建 ⇒ 「本路首次」与充能条都自然清零。
func _mirror(u: Dictionary, tgt, stype: String, cost: float, si: int, ck: String) -> void:
	var go := false
	if _acc(u, "mfirst:" + ck) <= 0.0:
		_set_acc(u, "mfirst:" + ck, 1.0)
		go = true
	if _acc(u, "marmed:" + ck) > 0.0:
		_set_acc(u, "marmed:" + ck, 0.0)
		go = true
	var ch: float = _acc(u, "mcharge:" + ck) + cost
	if ch >= float(MIRROR_THR[si]):
		ch = 0.0
		_set_acc(u, "marmed:" + ck, 1.0)
	_set_acc(u, "mcharge:" + ck, ch)
	var st: Dictionary = u["eq_state"].get(ck, {})
	st["mirror_charge"] = ch   # 读数(装备格进度)
	st["mirror_armed"] = _acc(u, "marmed:" + ck) > 0.0
	u["eq_state"][ck] = st
	if go and stype != "":
		_echo.append({"u": u, "tgt": tgt, "stype": stype, "at": float(battle._t) + ECHO_DELAY, "tl": battle._equip_sys.tally.capture()})
		_fx("mirror_echo", [u, ECHO_DELAY])


func _tick_echo() -> void:
	if _echo.is_empty():
		return
	var t := float(battle._t)
	var keep: Array = []
	var due: Array = []
	for r in _echo:
		(due if t >= float(r["at"]) else keep).append(r)
	_echo = keep
	for r in due:
		var u: Dictionary = r["u"]
		if not u.get("alive", false) or battle._damage.is_controlled(u):
			continue   # 被控就作废(同双头延后施法)
		var tg = r["tgt"]
		if not (tg is Dictionary) or not (tg as Dictionary).get("alive", false):
			tg = battle._targeting._nearest_enemy(u)
		if not (tg is Dictionary):
			continue
		var stype: String = str(r["stype"])
		if not battle._cast_skill(u, tg, stype):
			continue
		stat["echo"] += 1
		var tl0: Array = battle._equip_sys.tally.capture()
		battle._equip_sys._eq_on_cast(u, tg)
		battle._equip_sys.tally.pop(tl0)
		battle._magic_syn.after_cast(u, tg, stype, true)


# ════════════════════════════════════════ 123 亡者之书: 三种骷髅 ════════════════════════════════════════

## kind 留空 = 随机(对局种子, 用户 11-25「随机不是轮流」); 门禁点名某一种时传进来
func _summon_skeleton(owner: Dictionary, si: int, cost: float, kind: String = "") -> Dictionary:
	var life: float = cost * SKEL_SEC_PER_EN
	if life <= 0.0:
		return {}
	if kind == "":
		kind = SKEL_KINDS[battle._battle_rng.randi() % SKEL_KINDS.size()]
	var hp: float
	var atk: float
	var res: float
	var p = null
	## 三个调用点各写字面量 label(verify_summon_label 逐个扫 `_spawn_summon(` 调用点要求带中文 label)
	match kind:
		"skel_warrior":
			hp = SKW_HP[si]; atk = SKW_ATK[si]; res = SKW_RES[si]
			p = battle._spawn._spawn_summon(owner, kind, hp, atk, {"label": "骷髅战士", "spr_id": "eq-skel-warrior", "col_size": 44.0, "hp_w": 32.0, "atk_interval": SKW_IV, "atk_range": SKW_RANGE, "melee": true})
		"skel_mage":
			hp = SKM_HP[si]; atk = SKM_ATK[si]; res = SKM_RES[si]
			p = battle._spawn._spawn_summon(owner, kind, hp, atk, {"label": "骷髅法师", "spr_id": "eq-skel-mage", "col_size": 42.0, "hp_w": 30.0, "atk_interval": SKM_IV, "atk_range": SKM_RANGE, "melee": false})
		_:
			hp = SKP_HP[si]; atk = SKP_ATK[si]; res = SKP_RES[si]
			p = battle._spawn._spawn_summon(owner, kind, hp, atk, {"label": "骷髅祭司", "spr_id": "eq-skel-priest", "col_size": 42.0, "hp_w": 30.0, "atk_interval": SKP_IV, "atk_range": SKP_RANGE, "melee": false})
	if p == null:
		return {}
	p["def"] = res; p["base_def"] = res
	p["mr"] = res; p["base_mr"] = res
	p["maxEnergy"] = SKEL_EN_MAX
	p["energy"] = 0.0
	p["_act_like_idle"] = true   # 动作帧沿用待机缩放(render 读; 不然一做动作就放大、脚底跳)
	stat["skel"] += 1
	var rec := {"u": p, "owner": owner, "kind": kind, "si": si, "en": 0.0, "until": float(battle._t) + life}
	_skels.append(rec)
	_fx("skel_rise", [p, kind])
	return rec


func _tick_skels(delta: float) -> void:
	if _skels.is_empty():
		return
	var t := float(battle._t)
	var keep: Array = []
	for s in _skels:
		var p: Dictionary = s["u"]
		if not p.get("alive", false):
			continue
		if t >= float(s["until"]):   # 时间到: 化灰
			if battle._damage.execute_saved(p):
				keep.append(s)
				continue
			p["hp"] = 0.0
			battle._kill(p)
			_fx("skel_crumble", [p])
			continue
		keep.append(s)
		if str(s["kind"]) == "skel_warrior" and t < float(p.get("_skw_rage_until", 0.0)):
			continue   # 狂怒 4 秒锁龟能
		if str(s["kind"]) == "skel_warrior" and float(p.get("_skw_rage_until", 0.0)) > 0.0:
			_skw_rage_end(p)
		if float(s.get("cast", -1.0)) >= 0.0:   # 技能前摇: 动作播到出招帧(= 前摇结束)才结算
			s["cast"] = float(s["cast"]) - delta
			if float(s["cast"]) <= 0.0:
				s["cast"] = -1.0
				_skel_resolve(s)
			continue
		s["en"] = minf(SKEL_EN_MAX, float(s["en"]) + _en_gain(p, delta))
		p["energy"] = float(s["en"])
		if float(s["en"]) < SKEL_EN_MAX:
			continue
		var tgt = battle._targeting._nearest_enemy(p)
		if not (tgt is Dictionary):
			continue
		s["en"] = 0.0
		p["energy"] = 0.0
		var wu: float = float(SKEL_WINDUP[str(s["kind"])])
		s["cast"] = wu
		s["cast_tgt"] = tgt
		battle._damage.channel(p, wu + 0.15)   # 前摇里站定不普攻
		p["face_right"] = Vector2(tgt["pos"]).x > Vector2(p["pos"]).x
		_fx("skel_cast", [p, str(s["kind"]), wu])
	_skels = keep


## 前摇结束: 按种类结算, 目标没了就就近重挑(战士不需要目标)
func _skel_resolve(s: Dictionary) -> void:
	var p: Dictionary = s["u"]
	var tgt = s.get("cast_tgt", null)
	s.erase("cast_tgt")
	if not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
		tgt = battle._targeting._nearest_enemy(p)
	if not (tgt is Dictionary) and str(s["kind"]) != "skel_warrior":
		return
	stat["skel_cast"] += 1
	match str(s["kind"]):
		"skel_warrior": _skw_rage(p)
		"skel_mage": _skm_blast(p, tgt)
		_: _skp_wave(p, tgt, int(s["si"]))
	battle._magic_syn.on_cast(p, SKEL_EN_MAX)   # 骷髅放技能也触发【飞弹】(用户 11-25「肯定是的」); 不再召骷髅(只有携带者放才召)


## 骷髅战士【骸骨狂怒】: 4 秒减伤 25% + 每次攻击额外 50% 攻击力物理(on_any_basic) + 25% 生命偷取; 期间锁龟能
func _skw_rage(p: Dictionary) -> void:
	p["_skw_rage_until"] = float(battle._t) + SKW_RAGE_SEC
	p["damage_reduction"] = float(p.get("damage_reduction", 0.0)) + SKW_DR
	p["lifesteal"] = float(p.get("lifesteal", 0.0)) + SKW_LS
	p["_body_tint"] = SKW_RAGE_TINT   # 狂怒 4 秒: 骨头泛绿(演出底色通道, battle_render 读, 直播录)
	_fx("skw_rage", [p, SKW_RAGE_SEC])


func _skw_rage_end(p: Dictionary) -> void:
	p["_skw_rage_until"] = 0.0
	p["damage_reduction"] = maxf(0.0, float(p.get("damage_reduction", 0.0)) - SKW_DR)
	p["lifesteal"] = maxf(0.0, float(p.get("lifesteal", 0.0)) - SKW_LS)
	p.erase("_body_tint")


## 骷髅法师【骨火爆裂】: 目标周围 200 码爆炸, 200% 攻击力魔法
func _skm_blast(p: Dictionary, tgt: Dictionary) -> void:
	var c := Vector2(tgt["pos"])
	_fx("skm_blast", [p, c, SKM_BLAST_R])
	for o in _enemies_of(p):
		if DetMath.dist(Vector2(o["pos"]), c) <= SKM_BLAST_R:
			_magic(p, o, SKM_BLAST_ATK * float(p.get("atk", 0.0)))


## 骷髅祭司【亡灵浪潮】: 从自身朝目标推出一道缓慢的浪潮(逐步碰撞, 每个单位只吃一次)
func _skp_wave(p: Dictionary, tgt: Dictionary, si: int) -> void:
	var d: Vector2 = Vector2(tgt["pos"]) - Vector2(p["pos"])
	d = DetMath.norm(d) if DetMath.vlen(d) > 1.0 else Vector2.RIGHT
	var w := {"src": p, "pos": Vector2(p["pos"]), "dir": d, "left": WAVE_LEN, "si": si, "hit": []}
	w["node"] = vfx.wave_launch(p, d) if vfx != null else null
	_waves.append(w)


func _tick_waves(delta: float) -> void:
	if _waves.is_empty():
		return
	var keep: Array = []
	for w in _waves:
		var src: Dictionary = w["src"]
		var step: float = minf(WAVE_SPD * delta, float(w["left"]))
		var a: Vector2 = w["pos"]
		var b: Vector2 = a + Vector2(w["dir"]) * step
		var side := str(battle._eff_side(src))
		for o in battle._units:
			if not (o is Dictionary) or not o.get("alive", false) or bool(o.get("_isEgg", false)) or battle._is_untouchable(o):
				continue
			if battle._arr_has_unit(w["hit"], o):
				continue
			var r: float = WAVE_W * 0.5 + float(o.get("col_r", 20.0))
			if DetMath.dist(DetMath.seg_closest(Vector2(o["pos"]), a, b), Vector2(o["pos"])) > r:
				continue
			(w["hit"] as Array).append(o)
			if str(battle._eff_side(o)) == side:
				battle._damage._heal(o, float(WAVE_HEAL[int(w["si"])]))
				_fx("wave_heal", [o])
			else:
				_wave_hit(src, o, int(w["si"]))
		w["pos"] = b
		w["left"] = float(w["left"]) - step
		_fx("wave_step", [w.get("node"), b, w["dir"]])
		if float(w["left"]) > 0.0:   # 祭司半路死了浪潮照样推完
			keep.append(w)
		else:
			_fx("wave_end", [w.get("node")])
	_waves = keep


## 浪潮打到敌人: 固定物理伤害 + 击飞 1 秒(同时开始眩晕 1.5 秒) + 4 秒魔抗 −25%
func _wave_hit(src: Dictionary, o: Dictionary, si: int) -> void:
	stat["wave_hit"] += 1
	var dmg: int = battle._resolve_dmg(src, float(WAVE_DMG[si]), o, false, false)
	battle._damage._apply_damage_from(src, o, dmg, COL_PHYS, 0.0, false, true)
	if not o.get("alive", false):
		return
	battle._knock_up(o, Vector2(o["pos"]) - Vector2(1, 0) * 10.0, WAVE_KNOCK_VY)
	battle._damage._stun(o, WAVE_STUN, "skel_wave")
	battle._damage._buff_refresh(o, "mr", -WAVE_MR_SHRED, true, "skel_wave_mr", WAVE_MR_SEC)
	_fx("wave_hit", [o])


# ════════════════════════════════════════ 126 浮空魔典: 书页 ════════════════════════════════════════

## 近战: 书页绕携带者转; ★每张书页各自判定碰撞(11-25 用户「你确定是每个书页碰到敌人的时候就触发效果吗？…没有的话就给我重做」):
##   每个 sim 步算每张书页此刻的位置, 某张书页「刚碰上」某个敌人(上一步没碰着、这一步碰着)就结算一次 ——
##   同一张书页一直贴着同一个敌人不重复打, 离开再碰上才再打; 不同书页各算各的。每碰一次给自己一点护盾(本件给的盾封顶)。
func _tick_pages_melee(u: Dictionary, si: int, ck: String, delta: float) -> void:
	var ang: float = fmod(_acc(u, "pang:" + ck) + PAGE_W * delta, TAU)
	_set_acc(u, "pang:" + ck, ang)
	var n: int = int(PAGE_N[si])
	var c := Vector2(u["pos"])
	var base: float = float(PAGE_FLAT[si]) + PAGE_ATK * float(u.get("atk", 0.0))
	for i in range(n):
		var th: float = ang + TAU * float(i) / float(n)
		var p: Vector2 = c + Vector2(DetMath.dcos(th), DetMath.dsin(th)) * PAGE_R
		for o in _enemies_of(u):
			var key: String = "ptouch:%s:%d:%s" % [ck, i, _uid(o)]
			var touching: bool = DetMath.dist(p, Vector2(o["pos"])) <= PAGE_HIT_R + float(o.get("col_r", 20.0))
			var was: bool = _acc(u, key) > 0.0
			if touching == was:
				continue
			_set_acc(u, key, 1.0 if touching else 0.0)
			if touching:
				_page_hit(u, o, si, ck, base)
	## 本件给的盾 4 秒到期 ⇒ 封顶额度跟着回来
	if _acc(u, "pshexp:" + ck) > 0.0 and float(battle._t) >= _acc(u, "pshexp:" + ck):
		_set_acc(u, "pshield:" + ck, 0.0)
		_set_acc(u, "pshexp:" + ck, 0.0)


func _page_hit(u: Dictionary, o: Dictionary, si: int, ck: String, base: float) -> void:
	stat["page_hit"] += 1
	_magic(u, o, base, false)
	_fx("page_cut", [o])
	var got: float = _acc(u, "pshield:" + ck)
	var add: float = minf(float(PAGE_SHIELD[si]), float(PAGE_SHIELD_CAP[si]) - got)
	if add > 0.0:
		_set_acc(u, "pshield:" + ck, got + add)
		battle._damage._grant_shield(u, add, PAGE_SHIELD_SEC)
		_set_acc(u, "pshexp:" + ck, float(battle._t) + PAGE_SHIELD_SEC)


static var _uid_next := 0
## 敌人的稳定编号(做「哪张书页碰着哪个敌人」的键; 单位字典不能当键, CLAUDE.md §4.2)
func _uid(o: Dictionary) -> String:
	if not o.has("_mb_uid"):
		_uid_next += 1
		o["_mb_uid"] = "m%d" % _uid_next
	return str(o["_mb_uid"])


## 远程: 每 4/3.5/3 秒长回一张书页(最多 3/4/6 张)
func _tick_pages_ranged(u: Dictionary, si: int, ck: String, delta: float) -> void:
	var n: float = _acc(u, "pages:" + ck)
	if n >= float(PAGE_N[si]):
		_set_acc(u, "pregen:" + ck, 0.0)
		return
	var a := _acc(u, "pregen:" + ck) + delta
	if a < float(PAGE_REGEN[si]):
		_set_acc(u, "pregen:" + ck, a)
		return
	_set_acc(u, "pregen:" + ck, a - float(PAGE_REGEN[si]))
	_set_acc(u, "pages:" + ck, n + 1.0)
	_fx("page_regen", [u, ck, int(n + 1.0)])


## 远程书页格挡(battle_damage._apply_damage_from 护盾前调): 单次伤害 ≥ 携带者最大生命值 6% 才挡,
##   一张书页最多吸收 300/600/1500, 超出部分照常受到。多件各自一叠书页, 按带的顺序先用第一件的。
func page_block(u: Dictionary, d: float) -> float:
	if d < PAGE_BLOCK_PCT * float(u.get("maxHp", 0.0)) or d <= 0.0:
		return d
	var es = battle._equip_sys
	for e in u.get("equips", []):
		if not (e is Dictionary) or str(e.get("id", "")) != "p2eq_126":
			continue
		var ckp: Array = es.ck_save()
		es.ck_set(u, e)
		var ck: String = es.key_of(u, "p2eq_126")
		es.ck_restore(ckp)
		if _acc(u, "pmode:" + ck) != 2.0 or _acc(u, "pages:" + ck) < 1.0:
			continue
		var si := _si_of(e)
		_set_acc(u, "pages:" + ck, _acc(u, "pages:" + ck) - 1.0)
		var ab: float = minf(d, float(PAGE_BLOCK_MAX[si]))
		stat["page_block"] += 1
		stat["page_absorb"] += ab
		var tl: Array = es.tally.push(u, ck)
		es.tally.credit(u, "p2eq_126", "block", ab)
		es.tally.pop(tl)
		_fx("page_block", [u, ck, ab])
		return d - ab
	return d


# ════════════════════════════════════════ 帧推进 ════════════════════════════════════════

func tick(delta: float) -> void:
	_tick_echo()
	_tick_hots(delta)
	_tick_temphp()
	_tick_skels(delta)
	_tick_waves(delta)
	if vfx != null:
		vfx.tick(delta)


func tick_unit(u: Dictionary, delta: float) -> void:
	if not u.get("alive", false):
		return
	var es = battle._equip_sys
	var ckp: Array = es.ck_save()
	for e in u.get("equips", []):
		if not (e is Dictionary):
			continue
		var eid := str(e.get("id", ""))
		if eid != "p2eq_121" and eid != "p2eq_126":
			continue
		var si := _si_of(e)
		es.ck_set(u, e)
		var ck: String = es.key_of(u, eid)
		var tl: Array = es.tally.push(u, ck)
		if eid == "p2eq_121":
			var a := _acc(u, "storm:" + ck) + delta
			if a >= STORM_IV:
				a -= STORM_IV
				_storm(u, si)
			_set_acc(u, "storm:" + ck, a)
		elif _acc(u, "pmode:" + ck) == 1.0:
			_tick_pages_melee(u, si, ck, delta)
		else:
			_tick_pages_ranged(u, si, ck, delta)
		es.tally.pop(tl)
	es.ck_restore(ckp)


## 121 风暴之书: 随机 3 名敌人(不重复)各落一道闪电
func _storm(u: Dictionary, si: int) -> void:
	var pool: Array = _enemies_of(u)
	if pool.is_empty():
		return
	stat["storm"] += 1
	var base: float = float(STORM_FLAT[si]) + STORM_ATK * float(u.get("atk", 0.0))
	for i in range(mini(STORM_N, pool.size())):
		var j: int = battle._battle_rng.randi() % pool.size()
		var o: Dictionary = pool[j]
		pool.remove_at(j)
		_fx("storm_bolt", [o])
		_magic(u, o, base)


func clear_all() -> void:
	_hots.clear(); _skels.clear(); _waves.clear(); _echo.clear(); _temphp.clear()
	if vfx != null:
		vfx.clear()


func reset_match() -> void:
	pass
