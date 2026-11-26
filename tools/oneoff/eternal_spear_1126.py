"""eternal_spear_1126.py —— 145 永恒之枪按用户 11-26 设计重做(数值 = 我 11-26 晚给的稿, 用户确认: 打生命值最高的敌人 /
伤害 = 攻击力 + 目标最大生命值两部分 / 临时生命值叠加; 用户 11-26 晚「145 特效去哪了」⇒ 直接做)
一次性; 原行尾二进制读写, 每处替换次数核对。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b, n in pairs:
        assert s.count(a) == n, (rel, a[:70], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


SP = "scripts/systems/equip/eq_spear_batch.gd"

OLD_CONST = """const ETERNAL_IV := 8.0
const ETERNAL_PIN := 1.5
const ETERNAL_PCT := [0.08, 0.12, 0.20]
const ETERNAL_SPD := 1100.0
"""
NEW_CONST = """## 145 永恒之枪(11-26 用户设计重做 · 方案书 20261126 附录 E)
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
const ETERNAL_BURN_R := 250.0                  # 命中处灼烧圈半径
const ETERNAL_BURN_SEC := 6.0
const ETERNAL_BURN_PCT := [0.02, 0.03, 0.05]   # 每秒: 圈内敌人各自最大生命值 × 的魔法伤害(多个圈各自生效)
"""

OLD_ETERNAL_FN = """func _eternal(u: Dictionary, si: int, ck: String) -> void:
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
"""
NEW_ETERNAL_FN = """## 145 永恒之枪: 进度满 ⇒ 一支枪从场外(携带者那一方的上方)按速度飞向生命值最高的敌人, 碰到才结算。返回 false = 没有能打的(进度留着下一帧再试)
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


func _eternal_hit(me: Dictionary, tg: Dictionary, si: int, ck: String, from: Vector2) -> void:
	stat["eternal_hit"] += 1
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
			var total: float = float(ETERNAL_SLIDE_ATK[si]) * atk + float(ETERNAL_SLIDE_HP[si]) * float(tg.get("maxHp", 0.0))
			_slides.append({"src": me, "o": tg, "dir": dir, "gone": 0.0, "total": total, "si": si, "ck": ck, "hit": [tg]})
			_fx("eternal_slide", [tg, dir, ETERNAL_SLIDE_SEC])
	## 携带者临时生命值(到期按比例削回; 多次各自独立 = 叠加)
	if me.get("alive", false):
		battle._trainer_sys._apply_temp_maxhp(me, float(me.get("maxHp", 0.0)) * float(ETERNAL_TEMP[si]), ETERNAL_TEMP_SEC)
		_fx("eternal_temp", [me])
	## 命中处灼烧圈(每个圈各自生效)
	_burns.append({"src": me, "at": at, "until": float(battle._t) + ETERNAL_BURN_SEC, "next": float(battle._t) + 1.0, "si": si, "ck": ck})
	_fx("eternal_burn", [at, ETERNAL_BURN_R, ETERNAL_BURN_SEC])


## 145 击倒滑行: 目标按每一步往后滑(总距离 / 总时长), 这一步滑过的那一段里撞到的其他敌人各吃一次; 滑行伤害按这一步滑的距离分摊
func _tick_slides(delta: float) -> void:
	var keep: Array = []
	var step_len: float = ETERNAL_SLIDE / ETERNAL_SLIDE_SEC * delta
	for s in _slides:
		var o: Dictionary = s["o"]
		var src: Dictionary = s["src"]
		if not o.get("alive", false) or float(s["gone"]) >= ETERNAL_SLIDE - 0.01:
			continue
		var a: Vector2 = Vector2(o["pos"])
		var mv: float = minf(step_len, ETERNAL_SLIDE - float(s["gone"]))
		var b: Vector2 = ArenaShape.clamp_in(a + Vector2(s["dir"]) * mv, battle.ARENA, 40.0)
		var real: float = DetMath.dist(a, b)
		o["pos"] = b
		s["gone"] = float(s["gone"]) + mv
		var tp: Array = battle._equip_sys.tally.push(src, str(s["ck"]))
		if real > 0.0:
			_phys(src, o, float(s["total"]) * real / ETERNAL_SLIDE)
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
		if t >= float(z["until"]):
			continue
		if t >= float(z["next"]):
			z["next"] = float(z["next"]) + 1.0
			var tp: Array = battle._equip_sys.tally.push(src, str(z["ck"]))
			for e in _enemies(src):
				if DetMath.dist(Vector2(e["pos"]), Vector2(z["at"])) <= ETERNAL_BURN_R + float(e.get("col_size", 22.0)) * 0.5:
					stat["eternal_burn"] += 1
					_magic(src, e, float(e.get("maxHp", 0.0)) * float(ETERNAL_BURN_PCT[int(z["si"])]))
			battle._equip_sys.tally.pop(tp)
		keep.append(z)
	_burns = keep


static func _arr_has(arr: Array, x) -> bool:
	for y in arr:
		if is_same(y, x):
			return true
	return false
"""

patch(SP, [
    (OLD_CONST, NEW_CONST, 1),
    (OLD_ETERNAL_FN, NEW_ETERNAL_FN, 1),
    ('"eternal": 0, "eternal_hit": 0,', '"eternal": 0, "eternal_hit": 0, "eternal_imm": 0, "eternal_pass": 0, "eternal_burn": 0,', 1),
    ("var _drops: Array = []", "var _slides: Array = []   # 145 击倒滑行 {src, o, dir, gone, total, si, ck, hit}\nvar _burns: Array = []    # 145 灼烧圈 {src, at, until, next, si, ck}\nvar _drops: Array = []", 1),
    ("""	_tick_slams(delta)
	_tick_drops()
""", """	_tick_slams(delta)
	_tick_drops()
	_tick_slides(delta)
	_tick_burns()
""", 1),
    ("""			"p2eq_145":
				var a4 := _acc(u, "eter:" + ck) + delta
				if a4 >= ETERNAL_IV:
					a4 -= ETERNAL_IV
					_eternal(u, si, ck)
				_set_acc(u, "eter:" + ck, a4)
""", """			"p2eq_145":   # 进度: 每秒 + / 造成伤害(看 dmg_dealt 的增量) + / 受到伤害(on_damaged) +; 满了出手
				var dd: float = float(u.get("dmg_dealt", 0.0))
				var dd0: float = _acc(u, "eter_dd:" + ck)
				_set_acc(u, "eter_dd:" + ck, dd)
				var a4 := minf(ETERNAL_NEED, _acc(u, "eter:" + ck) + ETERNAL_PS * delta + maxf(0.0, dd - dd0) * ETERNAL_PER_DMG / 100.0)
				if a4 >= ETERNAL_NEED and _eternal(u, si, ck):
					a4 = 0.0
				_set_acc(u, "eter:" + ck, a4)
""", 1),
    ("""func on_damaged(u: Dictionary, _src, dmg: float, eid: String, si: int) -> void:
	if eid != "p2eq_143" or dmg <= 0.0:
		return
""", """func on_damaged(u: Dictionary, _src, dmg: float, eid: String, si: int) -> void:
	if eid == "p2eq_145" and dmg > 0.0:   # 145 永恒之枪: 受到伤害攒进度
		var ck5: String = battle._equip_sys.key_of(u, eid)
		_set_acc(u, "eter:" + ck5, minf(ETERNAL_NEED, _acc(u, "eter:" + ck5) + dmg * ETERNAL_PER_DMG / 100.0))
		return
	if eid != "p2eq_143" or dmg <= 0.0:
		return
""", 1),
    ("""func clear_all() -> void:
	_waves.clear()
""", """func clear_all() -> void:
	_slides.clear()
	_burns.clear()
	_waves.clear()
""", 1),
    ('		if not ["p2eq_140", "p2eq_142", "p2eq_143", "p2eq_146"].has(eid):',
     '		if not ["p2eq_140", "p2eq_142", "p2eq_143", "p2eq_145", "p2eq_146"].has(eid):', 1),
    ("""			"p2eq_146":
				_live_put(u, ck, {"store\"""", """			"p2eq_145":
				_live_put(u, ck, {"pct": int(floor(_acc(u, "eter:" + ck) / ETERNAL_NEED * 100.0))})
			"p2eq_146":
				_live_put(u, ck, {"store\"""", 1),
])

patch("scripts/gamedata/eq_stat_labels.gd", [
    ('	"p2eq_146": "holy_spear",', '	"p2eq_145": "eternal_spear",  # 永恒之枪: 积攒进度(11-26 重做)\n	"p2eq_146": "holy_spear",', 1),
])
patch("scripts/scenes/battle/info_panel.gd", [
    ('		"holy_spear":\n', '		"eternal_spear":\n			out.append(Lang.t("积攒进度 %d%%") % mini(100, int(st.get("pct", 0))))\n		"holy_spear":\n', 1),
])

D = ("战斗中积攒进度：每秒获得 {C:EqSpearBatch.ETERNAL_PS} 点，每造成或受到 100 点伤害获得 {C:EqSpearBatch.ETERNAL_PER_DMG} 点。"
     "进度达到 {C:EqSpearBatch.ETERNAL_NEED} 时，一支永恒之枪从场外飞向生命值最高的敌人，造成 {C:EqSpearBatch.ETERNAL_HIT_ATK%}% 攻击力 + 目标 {C:EqSpearBatch.ETERNAL_HIT_HP%}% 最大生命值的物理伤害，"
     "将其击倒并向后滑行，滑行期间共造成 {C:EqSpearBatch.ETERNAL_SLIDE_ATK%}% 攻击力 + 目标 {C:EqSpearBatch.ETERNAL_SLIDE_HP%}% 最大生命值的物理伤害，眩晕 {C:EqSpearBatch.ETERNAL_STUN} 秒。"
     "滑行路径上的其他敌人受到 {C:EqSpearBatch.ETERNAL_PASS_ATK%}% 攻击力 + 其 {C:EqSpearBatch.ETERNAL_PASS_HP%}% 最大生命值的物理伤害。"
     "目标免疫控制时，转而额外受到 {C:EqSpearBatch.ETERNAL_IMM_ATK%}% 攻击力 + 目标 {C:EqSpearBatch.ETERNAL_IMM_HP%}% 最大生命值的物理伤害。\\n"
     "命中时，自身获得 {C:EqSpearBatch.ETERNAL_TEMP%}% 最大生命值的临时生命值，持续 {C:EqSpearBatch.ETERNAL_TEMP_SEC} 秒。"
     "命中处留下灼烧圈，持续 {C:EqSpearBatch.ETERNAL_BURN_SEC} 秒，每秒对圈内敌人造成其 {C:EqSpearBatch.ETERNAL_BURN_PCT%}% 最大生命值的魔法伤害。临时生命值与灼烧圈均可叠加。")
OLD_D = "每 {C:EqSpearBatch.ETERNAL_IV} 秒向生命值最高的敌人掷出永恒之枪，造成目标 {C:EqSpearBatch.ETERNAL_PCT%}% 最大生命值的物理伤害，并将其钉在原地 {C:EqSpearBatch.ETERNAL_PIN} 秒。"
p = os.path.join(ROOT, "data/phase2-equipment.json")
raw = open(p, "rb").read()
s = raw.decode("utf-8")
assert s.count(OLD_D) == 1
s = s.replace(OLD_D, D)
i = s.index('"id": "p2eq_145"')
j = s.index('"effectBrief": "', i)
k = s.index('"', j + len('"effectBrief": "'))
s = s[:j] + '"effectBrief": "积攒进度满后，永恒之枪从场外飞向生命值最高的敌人，将其击倒拖行，并获得临时生命值、留下灼烧圈。' + s[k:]
open(p, "wb").write(s.encode("utf-8"))

patch("scripts/gamedata/equip_tier_labels.gd", [
    ('	"p2eq_145": ["伤害 #% 最大生命值"],',
     '	"p2eq_145": ["命中伤害 #% 攻击力", "命中伤害 #% 最大生命值", "滑行伤害 #% 攻击力", "滑行伤害 #% 最大生命值", "路径伤害 #% 攻击力", "路径伤害 #% 最大生命值", '
     '"免控追加 #% 攻击力", "免控追加 #% 最大生命值", "临时生命值 #% 最大生命值", "灼烧 #% 最大生命值"],', 1),
])
print("ok")
