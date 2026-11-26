"""centurion_big_1127.py —— 百夫长做大做壮 + 普攻 / 技能特效加强(用户 11-27「这个形象就太小了…肯定是要大一点的，要健壮一点…技能特效感觉都不明显。普攻也没有特效」)
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        n = s.count(a)
        if n != 1:
            sys.exit("%s: 命中 %d 次: %r" % (rel, n, a[:90]))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("ok", rel)


## 召唤物显示倍率(只放大画面, 不动碰撞): behavior.vis_mul
patch("scripts/scenes/battle/battle_spawn.gd", [
("""		spr.pixel_size = (battle.TARGET_BODY_H * (col_size / 56.0)) / float(maxi(1, fh))
		spr.offset = Vector2(0.0, fh * 0.5)""",
"""		spr.pixel_size = (battle.TARGET_BODY_H * (col_size / 56.0)) / float(maxi(1, fh)) * float(behavior.get("vis_mul", 1.0))   # vis_mul: 只放大画面(11-27 百夫长)
		spr.offset = Vector2(0.0, fh * 0.5)"""),
])

## 体型: 碰撞 60 → 72(更壮的身板), 画面再 ×1.2 ⇒ 人物约 2.8 米(龟 2 米)
patch("scripts/systems/equip/spear_synergy_system.gd", [
("""		{"label": "百夫长", "spr_id": "eq-centurion", "col_size": 60.0, "hp_w": 44.0, "atk_interval": 1.0, "atk_range": RANGE, "melee": true})""",
"""		{"label": "百夫长", "spr_id": "eq-centurion", "col_size": 72.0, "hp_w": 56.0, "vis_mul": 1.2, "atk_interval": 1.0, "atk_range": RANGE, "melee": true})   # 11-27 用户「形象就太小了…要大一点的，要健壮一点」: 重画成重甲巨汉 + 放大"""),
])

patch("scripts/scenes/RealtimeBattle3DScene.gd", [
(""""eq-centurion": ["vfx/eq-centurion-idle.png", 112],""",
""""eq-centurion": ["vfx/eq-centurion-idle.png", 128],"""),
])

patch("scripts/scenes/battle/spear_eq_vfx.gd", [
("""const CENT_FW := 112""", """const CENT_FW := 128"""),
("""func cent_thrust(_u: Dictionary, _t: Dictionary, _n: int) -> void:
	pass   # 刺的动作走普攻节奏(AttackRhythm 播 attack 帧条), 这里不重播
""",
"""## 普攻(11-27 用户「普攻也没有特效」): 刺出那一下(sim 结算同一步)从矛尖朝目标射出一道金白突刺气劲(逐帧: 矛尖闪 → 光尾拉长 → 碎成火星),
##   2 档起贯穿 ⇒ 气劲一路穿到目标身后(长度 = 结算的贯穿线); 目标身上迸火星
const CENT_TIP_H := 1.3     # 矛尖离地高(米, 新画的百夫长平端长矛的高度)


func cent_thrust(u: Dictionary, t: Dictionary, n: int) -> void:
	var a := Vector2(u["pos"])
	var b := Vector2(t["pos"])
	var d: Vector2 = b - a
	if d.length() < 1.0:
		d = _face(u)
	var dir := d.normalized()
	var ln: float = maxf(80.0, d.length()) + (SpearSynergySystem.LINE_LEN if n > 1 else 20.0)
	var mid: Vector2 = a + dir * (ln * 0.5)
	_dir_strip(SV + "spear-cent-thrust.png", 7, mid, dir, ln * float(battle.WS), 24.0, 7.0 / 24.0, CENT_TIP_H)
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(b, 0.6), 1.3, 20.0, false, 6.0 / 20.0, false, null, 0.0)
"""),
("""func cent_throw(u: Dictionary, s: Dictionary) -> void:
	_cent_play(u, "throw", 20.0)
	var n := _proj("spear-pilum.png", Vector2(s["pos"]), Vector2(s["dir"]), 1.9)""",
"""func cent_throw(u: Dictionary, s: Dictionary) -> void:
	_cent_play(u, "throw", 20.0)
	_dir_strip(SV + "spear-cent-thrust.png", 7, Vector2(s["pos"]) + Vector2(s["dir"]) * 90.0, Vector2(s["dir"]), 180.0 * float(battle.WS), 24.0, 7.0 / 24.0, CENT_TIP_H)   # 出手那一下的气劲
	var n := _proj("spear-pilum.png", Vector2(s["pos"]), Vector2(s["dir"]), 2.4)"""),
("""func cent_spear_hit(o: Dictionary) -> void:
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.35), 0.9, 20.0, false, 6.0 / 20.0, false, null, 0.0)""",
"""func cent_spear_hit(o: Dictionary) -> void:
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.5), 1.6, 20.0, false, 6.0 / 20.0, false, null, 0.0)
	_strip(LION_DUST, 7, battle._world_pos(Vector2(o["pos"]), 0.0), 1.0, 16.0, false, 7.0 / 16.0, false, null, 0.0)"""),
("""func cent_shield(u: Dictionary, sec: float) -> void:
	## 帧条 = 举盾 6 帧 + 撑盾 36 帧(打包脚本里拼好); 整条恰好播满举盾时长 ⇒ 0.4 秒举起, 之后一直撑着, 到点放下回待机
	var sd := _cent_sd("shield", 14.0)
	var nf: int = int(sd.get("frames", 42)) if not sd.is_empty() else 42
	_cent_play(u, "shield", float(nf) / maxf(0.5, sec))


func cent_shield_off(_u: Dictionary) -> void:
	pass


func cent_poke(_u: Dictionary) -> void:
	pass   # 刺击本身有动作帧, 不再加地上的程序圆圈
""",
"""## 龟甲阵(11-27 用户「技能特效感觉都不明显」): 举盾那一刻身前立起一面金色能量巨盾(逐帧: 光纹流过、边缘明暗、光点上飘),
##   跟着百夫长、朝最近的敌人那一侧, 半透明叠在盾前; 举盾结束收掉。落盾时扬尘 + 轻震屏
var _aegis: Array = []      # {u, node}
const AEGIS_FWD := 46.0     # 立在身前多远(码)
const AEGIS_H_M := 3.0      # 能量盾高(米)


func cent_shield(u: Dictionary, sec: float) -> void:
	## 帧条 = 举盾 6 帧 + 撑盾 36 帧(打包脚本里拼好); 整条恰好播满举盾时长 ⇒ 0.4 秒举起, 之后一直撑着, 到点放下回待机
	var sd := _cent_sd("shield", 14.0)
	var nf: int = int(sd.get("frames", 42)) if not sd.is_empty() else 42
	_cent_play(u, "shield", float(nf) / maxf(0.5, sec))
	cent_shield_off(u)
	var s := _strip(SV + "spear-cent-aegis.png", 6, battle._world_pos(Vector2(u["pos"]), 0.0), AEGIS_H_M, 10.0, true, sec, false, null, 0.0)
	if s != null:
		s.modulate = Color(1.0, 1.0, 1.0, 0.72)
		_aegis.append({"u": u, "node": s})
		_tick_aegis()
	_strip(LION_DUST, 7, battle._world_pos(Vector2(u["pos"]), 0.0), 1.6, 16.0, false, 7.0 / 16.0, false, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.5)


func cent_shield_off(u: Dictionary) -> void:
	for a in _aegis:
		if is_same(a["u"], u) and a["node"] != null and is_instance_valid(a["node"]):
			_fade_out(a["node"] as Sprite3D, 0.15)
	_aegis = _aegis.filter(func(a): return not is_same(a["u"], u))


func _tick_aegis() -> void:
	var keep: Array = []
	for a in _aegis:
		var n = a["node"]
		var u: Dictionary = a["u"]
		if n == null or not is_instance_valid(n) or not u.get("alive", false):
			_free(n)
			continue
		var tg = battle._targeting._nearest_enemy(u)
		var fx: float = (1.0 if Vector2(tg["pos"]).x >= Vector2(u["pos"]).x else -1.0) if tg is Dictionary else _face(u).x
		(n as Sprite3D).position = battle._world_pos(Vector2(u["pos"]) + Vector2(fx * AEGIS_FWD, 6.0), 0.0)
		(n as Sprite3D).flip_h = fx < 0.0
		keep.append(a)
	_aegis = keep


## 3 档举盾期间每 0.5 秒刺周围: 朝范围里每个敌人各一道短突刺气劲 + 火星(结算同一步, 范围 = POKE_R)
func cent_poke(u: Dictionary) -> void:
	var a := Vector2(u["pos"])
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false) or DetMath.dist(Vector2(o["pos"]), a) > SpearSynergySystem.POKE_R:
			continue
		var d: Vector2 = Vector2(o["pos"]) - a
		var dir: Vector2 = d.normalized() if d.length() > 1.0 else _face(u)
		var ln: float = maxf(60.0, d.length())
		_dir_strip(SV + "spear-cent-thrust.png", 7, a + dir * (ln * 0.5), dir, ln * float(battle.WS), 28.0, 7.0 / 28.0, CENT_TIP_H * 0.8)
		_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.5), 1.0, 20.0, false, 6.0 / 20.0, false, null, 0.0)
"""),
("""func cent_sweep(u: Dictionary) -> void:
	## 一圈金白横扫气刃贴地转开、往外甩土(spear-cent-sweep, 俯视画); 画里气刃外缘约占画布 0.8 ⇒ 按横扫半径 260 换算
	_strip(SV + "spear-cent-sweep.png", 9, battle._world_pos(Vector2(u["pos"]), 0.06), 260.0 * 2.0 * float(battle.WS) / 0.8, 20.0, false, 9.0 / 20.0, true, null, 0.0)""",
"""func cent_sweep(u: Dictionary) -> void:
	## 一圈金白横扫气刃贴地转开、往外甩土(spear-cent-sweep, 俯视画); 画里气刃外缘约占画布 0.8 ⇒ 按横扫半径 260 换算
	var sw := _strip(SV + "spear-cent-sweep.png", 9, battle._world_pos(Vector2(u["pos"]), 0.06), 260.0 * 2.0 * float(battle.WS) / 0.8, 16.0, false, 9.0 / 16.0, true, null, 0.0)
	if sw != null:
		sw.modulate = Color(1.35, 1.25, 1.0, 1.0)   # 11-27「技能特效感觉都不明显」: 提亮、放慢一点
	for o in battle._targeting._enemies_of(u):   # 扫到的每个敌人身上迸火星(结算同一步, 范围 = SWEEP_R)
		if o.get("alive", false) and DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"])) <= SpearSynergySystem.SWEEP_R:
			_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.5), 1.3, 20.0, false, 6.0 / 20.0, false, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.6)"""),
("""	_tick_hfx(delta)""" if False else """	_tick_fall(delta)
""",
"""	_tick_fall(delta)
	_tick_aegis()
"""),
("""	_cc_last.clear()
	_lance_on.clear()""",
"""	_cc_last.clear()
	_lance_on.clear()
	for a in _aegis:
		_free(a["node"])
	_aegis.clear()"""),
])
