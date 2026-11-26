"""eternal_ring_vfx_1126.py —— 145 灼烧圈按美术分层重做(用户 11-26 晚「火圈应该是在携带者身上的，火圈特效不行，仔细以美术师的角度思考」)
方案书 20261126 附录 E ⑦: 地面暗底 + 淡热光 / 圈边手画火舌立体一圈(前矮后高, 慢转) / 余烬 / 每秒光波 + 挨烧的人身上舔火 / 叠加更高 / 结束缩下去
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
OLD = """func eternal_burn(me: Dictionary, r: float, sec: float) -> void:   # 跟着携带者走(11-26 晚用户)
	_strip(SV + "eternal-burn.png", 12, battle._world_pos(Vector2(me["pos"]), 0.03), r * 2.0 * float(battle.WS) * ETER_BURN_FILL, 12.0, true, sec, true, me, 0.03)
"""
NEW = """## ⑦ 灼烧圈(跟着携带者; 用户 11-26 晚「火圈应该是在携带者身上的，火圈特效不行，仔细以美术师的角度思考」) —— 分层:
##   地面层 eternal-ring-ground(暗褐焦痕环压对比 + 焦斑 + 淡热光呼吸 + 圈边琥珀细光, 平铺在脚下)
##   + 圈边一圈立起来的手画火舌 eternal-flame-tongue(Aseprite 逐笔画 8 帧; ETER_TONGUES 根, 后半圈高前半圈矮 = 立体, 帧错开, 整圈慢转)
##   + 余烬从圈边往上飘 + 每秒跳伤害: 光波 eternal-pulse 从携带者推到圈边, 挨烧的人身上舔一下小火舌; 叠加的圈火舌更高; 结束火舌缩回地里
const ETER_RING_FILL := 1.116   # 地面层 / 光波: 圈在 192 帧里半径 86 ⇒ 帧宽 = 直径 × 1.116
const ETER_TONGUES := 20
const ETER_TONGUE_BACK := 1.55  # 后半圈火舌高(米)
const ETER_TONGUE_FRONT := 0.85 # 前半圈火舌高(米)
const ETER_SPIN := 0.35         # 整圈转速(弧度 / 秒)
const ETER_GROW := 0.3          # 出现: 火舌从地里长出来
const ETER_SHRINK := 0.45       # 结束: 缩回地里
var _eter_rings: Array = []     # {me, tongues[_mfx 条], ground(_mfx 条), t, life, ang, hmul, ember}


func eternal_burn(me: Dictionary, r: float, sec: float) -> void:
	var at := Vector2(me["pos"])
	var d_m: float = r * 2.0 * float(battle.WS) * ETER_RING_FILL
	var g := _strip(SV + "eternal-ring-ground.png", 12, battle._world_pos(at, 0.02), d_m, 12.0, true, sec, true, me, 0.02)
	var stack := 0
	for rr in _eter_rings:
		if is_same(rr["me"], me):
			stack += 1
	var ring := {"me": me, "tongues": [], "t": 0.0, "life": sec, "ang": 0.0, "hmul": 1.0 + 0.15 * float(stack), "ember": 0.0, "en": 0, "r": r}
	for i in range(ETER_TONGUES):
		var s := _strip(SV + "eternal-flame-tongue.png", 8, battle._world_pos(at, 0.0), ETER_TONGUE_FRONT, 12.0, true, sec, false, null, 0.0)
		if s != null:
			var f: Dictionary = _mfx.back()
			f["t"] = float(i % 8) / 12.0 * 1.37   # 帧错开, 不齐刷刷一起跳
			s.render_priority = 8
			(ring["tongues"] as Array).append(f)
	_eter_rings.append(ring)


func eternal_burn_tick(me: Dictionary, r: float) -> void:
	_strip(SV + "eternal-pulse.png", 8, battle._world_pos(Vector2(me["pos"]), 0.03), r * 2.0 * float(battle.WS) * ETER_RING_FILL, 16.0, false, 0.5, true, me, 0.03)


func eternal_burn_lick(e: Dictionary) -> void:
	var s := _strip(SV + "eternal-flame-tongue.png", 8, battle._world_pos(Vector2(e["pos"]), 0.0), 0.9, 16.0, false, 0.5, false, e, 0.0)
	if s != null:
		s.render_priority = 9


func _tick_eter_rings(delta: float) -> void:
	var keep: Array = []
	for ring in _eter_rings:
		var me: Dictionary = ring["me"]
		ring["t"] = float(ring["t"]) + delta
		var t: float = float(ring["t"])
		var life: float = float(ring["life"])
		if t >= life or not me.get("alive", false):
			for f in ring["tongues"]:
				_free((f as Dictionary)["node"])
			continue
		ring["ang"] = float(ring["ang"]) + ETER_SPIN * delta
		var grow: float = clampf(t / ETER_GROW, 0.0, 1.0) * clampf((life - t) / ETER_SHRINK, 0.0, 1.0)
		var c := Vector2(me["pos"])
		var r: float = float(ring["r"])
		var tl: Array = ring["tongues"]
		for i in range(tl.size()):
			var n = (tl[i] as Dictionary)["node"]
			if n == null or not is_instance_valid(n):
				continue
			var a: float = float(ring["ang"]) + TAU * float(i) / float(tl.size())
			var off := Vector2(cos(a), sin(a)) * r
			var front: float = (sin(a) + 1.0) * 0.5          # 0 = 最远(画面上方), 1 = 最近
			var h: float = lerpf(ETER_TONGUE_BACK, ETER_TONGUE_FRONT, front) * float(ring["hmul"]) * grow
			var sp := n as Sprite3D
			sp.position = battle._world_pos(c + off, 0.0)
			sp.pixel_size = maxf(0.0001, h / float(sp.texture.get_height()))
			sp.modulate.a = clampf(grow * 1.4, 0.0, 1.0)
		## 余烬: 每 0.12 秒从圈边一处(黄金角轮转, 不用随机数)飘起一颗
		ring["ember"] = float(ring["ember"]) + delta
		while float(ring["ember"]) >= 0.12:
			ring["ember"] = float(ring["ember"]) - 0.12
			ring["en"] = int(ring["en"]) + 1
			var ea: float = float(ring["en"]) * 2.39996
			_eter_embers.append({"at": c + Vector2(cos(ea), sin(ea)) * r, "t": 0.0, "node": _ember_node(c + Vector2(cos(ea), sin(ea)) * r)})
		keep.append(ring)
	_eter_rings = keep
	var ke: Array = []
	for e in _eter_embers:
		var n = e["node"]
		if n == null or not is_instance_valid(n):
			continue
		e["t"] = float(e["t"]) + delta
		var k: float = float(e["t"]) / 0.7
		if k >= 1.0:
			_free(n)
			continue
		(n as Sprite3D).position = battle._world_pos(Vector2(e["at"]), 0.2 + 1.3 * k)
		(n as Sprite3D).modulate = Color(1.0, 0.65 + 0.3 * (1.0 - k), 0.25, 1.0 - k)
		ke.append(e)
	_eter_embers = ke


var _eter_embers: Array = []


func _ember_node(at: Vector2) -> Sprite3D:
	var path := "res://assets/sprites/vfx/cent_aegis/mote.png"   # 底层小元素(火星)可跨特效共用(§10 第 5 条)
	if not _ok() or not ResourceLoader.exists(path):
		return null
	var s := Sprite3D.new()
	s.texture = load(path)
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = 0.12 / float(maxi(1, s.texture.get_height()))
	s.position = battle._world_pos(at, 0.2)
	battle._world.add_child(s)
	return s
"""
patch(VF, [
    (OLD, NEW, 1),
    ("""	_tick_eternal(delta)
""", """	_tick_eternal(delta)
	_tick_eter_rings(delta)
""", 1),
    ("""	_eter_dust.clear()
""", """	_eter_dust.clear()
	for ring in _eter_rings:
		for f in ring["tongues"]:
			_free((f as Dictionary)["node"])
	_eter_rings.clear()
	for e in _eter_embers:
		_free(e["node"])
	_eter_embers.clear()
""", 1),
])
patch("scripts/systems/equip/eq_spear_batch.gd", [
    ("""			var bdd0: float = float(src.get("dmg_dealt", 0.0))
			for e in _enemies(src):""", """			var bdd0: float = float(src.get("dmg_dealt", 0.0))
			_fx("eternal_burn_tick", [src, ETERNAL_BURN_R])
			for e in _enemies(src):""", 1),
    ("""					_magic(src, e, float(e.get("maxHp", 0.0)) * float(ETERNAL_BURN_PCT[int(z["si"])]))
""", """					_magic(src, e, float(e.get("maxHp", 0.0)) * float(ETERNAL_BURN_PCT[int(z["si"])]))
					_fx("eternal_burn_lick", [e])
""", 1),
])
print("ok")
