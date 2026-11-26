"""eternal_vfx_1126.py —— 145 永恒之枪演出层(方案书 20261126 附录 E 分段表; 参考 薇恩 E; 素材 pack_holy_spear_art.py)
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


VF = "scripts/scenes/battle/spear_eq_vfx.gd"
OLD = """func eternal_fly(from: Vector2, tg: Dictionary):   # 11-26 起从场外飞来(sim 给出发点)
	return _proj("spear-gungnir.png", from, Vector2(tg["pos"]) - from, 2.0)


func eternal_step(node, p2: Vector2, to2: Vector2) -> void:
	javelin_step(node, p2, to2)


func eternal_end(node, hit: bool, tg: Dictionary) -> void:
	_free(node)
	if hit and tg.get("alive", false):
		_ring(Vector2(tg["pos"]), 70.0, Color(0.85, 0.95, 1.0, 0.95), 0.4)
"""
NEW = """## ── 145 永恒之枪(11-26 用户设计重做 · 方案书 20261126 附录 E · 参考 docs/studies/20261126-参考-薇恩E恶魔审判.md) ──
##   ① 飞来: 枪从场外斜着砸下来(高度 6 米 → 1 米, 按 sim 的飞行进度), 身后一串金色残影拖尾(薇恩 E: 快速飞行物画成长拖尾)
##   ② 插中: eternal-impact 一格白金十字最亮 → 变金缩小外散(薇恩 E 撞墙那一下的方法)
##   ③ 滑行: 枪插在目标身上跟着走(眩晕期间), 一路身后扬尘
##   ⑤ 路径撞人: 火星; ⑥ 临时生命值: 金色飘字; ⑦ 灼烧圈: eternal-burn 平铺在命中处 6 秒
const ETER_H0 := 6.0          # 出发高度(米, 从场外上方砸下)
const ETER_LEN_M := 2.6       # 枪长(米)
const ETER_GHOST_GAP := 28.0   # 拖尾残影间隔(飞过的码数)
const ETER_GHOST_LIFE := 0.28
const ETER_IMPACT_M := 3.2
const ETER_BURN_FILL := 1.09  # 灼烧圈在 98 像素帧里约占 90 像素 ⇒ 帧宽 = 直径 × 1.09
var _eter_ghosts: Array = []  # {node, t}
var _eter_pins: Array = []    # 插在目标身上的枪 {node, o, dir, until}
var _eter_dust: Array = []    # 滑行扬尘 {o, until, next}


func eternal_fly(from: Vector2, tg: Dictionary):   # 11-26 起从场外飞来(sim 给出发点)
	var n := _proj("spear-gungnir.png", from, Vector2(tg["pos"]) - from, ETER_LEN_M)
	if n != null:
		n.set_meta("from", from)
		n.set_meta("gd", 0.0)
		n.position = battle._world_pos(from, ETER_H0)
	return n


func eternal_step(node, p2: Vector2, to2: Vector2) -> void:
	if node == null or not is_instance_valid(node):
		return
	var from: Vector2 = (node as Node).get_meta("from", p2)
	var gone: float = from.distance_to(p2)
	var left: float = p2.distance_to(to2)
	var k: float = gone / maxf(1.0, gone + left)
	var here: Vector3 = battle._world_pos(p2, lerpf(ETER_H0, 1.0, k))
	var ahead: Vector3 = battle._world_pos(to2, 1.0)
	(node as Sprite3D).position = here
	if ahead.distance_to(here) > 0.001:
		_orient_screen(node, ahead - here)
	## 残影拖尾: 每隔一小段留一个金色半透明的枪影, 很快淡掉
	var gd: float = float((node as Node).get_meta("gd", 0.0))
	if gone - gd >= ETER_GHOST_GAP:
		(node as Node).set_meta("gd", gone)
		var g := (node as Sprite3D).duplicate() as Sprite3D
		if g != null:
			g.modulate = Color(1.0, 0.85, 0.4, 0.55)
			g.render_priority = 8
			battle._world.add_child(g)
			_eter_ghosts.append({"node": g, "t": 0.0})


func eternal_end(node, hit: bool, tg: Dictionary) -> void:
	var dir := Vector2(1.0, 0.0)
	if node != null and is_instance_valid(node):
		var from: Vector2 = (node as Node).get_meta("from", Vector2(tg["pos"]))
		dir = (Vector2(tg["pos"]) - from).normalized()
	_free(node)
	if not hit or not tg.get("alive", false):
		return
	_strip(SV + "eternal-impact.png", 9, battle._world_pos(Vector2(tg["pos"]), 1.0 - ETER_IMPACT_M * 0.5), ETER_IMPACT_M, 18.0, false, 9.0 / 18.0, false, null, 0.0)
	## 枪插在目标身上(斜着, 枪尾朝来的方向), 眩晕期间跟着目标走
	var pin := _proj("spear-gungnir.png", Vector2(tg["pos"]), dir, ETER_LEN_M * 0.9)
	if pin != null:
		_eter_pins.append({"node": pin, "o": tg, "dir": dir, "until": float(EqSpearBatch.ETERNAL_STUN) + 0.1, "t": 0.0})


func eternal_slide(tg: Dictionary, _dir: Vector2, sec: float) -> void:
	_eter_dust.append({"o": tg, "t": 0.0, "until": sec, "next": 0.0})


func eternal_immune(_tg: Dictionary) -> void:
	pass   # 免控: 插中那一下照样有(eternal_end), 不倒不滑 ⇒ 没有滑行演出


func eternal_pass(e: Dictionary) -> void:
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(e["pos"]), 0.6), 1.8, 20.0, false, 6.0 / 20.0, false, null, 0.0)


func eternal_temp(me: Dictionary, amt: int) -> void:
	if amt > 0:
		battle._vfx._float_text(me["pos"] + Vector2(0, -60), Lang.t("+%d 临时生命值") % amt, Color("#ffc43a"))


func eternal_burn(at: Vector2, r: float, sec: float) -> void:
	_strip(SV + "eternal-burn.png", 12, battle._world_pos(at, 0.03), r * 2.0 * float(battle.WS) * ETER_BURN_FILL, 12.0, true, sec, true, null, 0.03)


func _tick_eternal(delta: float) -> void:
	var keep: Array = []
	for g in _eter_ghosts:
		var n = g["node"]
		if n == null or not is_instance_valid(n):
			continue
		g["t"] = float(g["t"]) + delta
		var k: float = float(g["t"]) / ETER_GHOST_LIFE
		if k >= 1.0:
			_free(n)
			continue
		(n as Sprite3D).modulate.a = 0.55 * (1.0 - k)
		keep.append(g)
	_eter_ghosts = keep
	keep = []
	for p in _eter_pins:
		var n = p["node"]
		var o: Dictionary = p["o"]
		p["t"] = float(p["t"]) + delta
		if n == null or not is_instance_valid(n) or not o.get("alive", false) or float(p["t"]) >= float(p["until"]):
			_free(n)
			continue
		var d: Vector2 = Vector2(p["dir"])
		(n as Sprite3D).position = battle._world_pos(Vector2(o["pos"]) - d * 26.0, 1.1)   # 枪身往来的方向退一截 = 枪尖扎在身上
		keep.append(p)
	_eter_pins = keep
	keep = []
	for s in _eter_dust:
		var o: Dictionary = s["o"]
		s["t"] = float(s["t"]) + delta
		if not o.get("alive", false) or float(s["t"]) >= float(s["until"]):
			continue
		if float(s["t"]) >= float(s["next"]):
			s["next"] = float(s["next"]) + 0.1
			_strip(SV + "spear-cav-dustbow.png", 6, battle._world_pos(Vector2(o["pos"]), 0.0), 1.6, 18.0, false, 6.0 / 18.0, false, null, 0.0)
		keep.append(s)
	_eter_dust = keep
"""
patch(VF, [
    (OLD, NEW, 1),
    ("""	_tick_holy_back(delta)
""", """	_tick_holy_back(delta)
	_tick_eternal(delta)
""", 1),
    ("""	_holy_spears.clear()
""", """	_holy_spears.clear()
	for g in _eter_ghosts:
		_free(g["node"])
	_eter_ghosts.clear()
	for p in _eter_pins:
		_free(p["node"])
	_eter_pins.clear()
	_eter_dust.clear()
""", 1),
])
patch("scripts/systems/equip/eq_spear_batch.gd", [
    ("""		battle._trainer_sys._apply_temp_maxhp(me, float(me.get("maxHp", 0.0)) * float(ETERNAL_TEMP[si]), ETERNAL_TEMP_SEC)
		_fx("eternal_temp", [me])
""", """		var tmp: float = float(me.get("maxHp", 0.0)) * float(ETERNAL_TEMP[si])
		battle._trainer_sys._apply_temp_maxhp(me, tmp, ETERNAL_TEMP_SEC)
		_fx("eternal_temp", [me, int(tmp)])
""", 1),
])
p = os.path.join(ROOT, "locale/en.po")
raw = open(p, "rb").read()
nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
a = 'msgid "等级 +1"\nmsgstr "Level +1"\n'
assert s.count(a) == 1
s = s.replace(a, a + '\nmsgid "+%d 临时生命值"\nmsgstr "+%d Temporary Health"\n')
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
