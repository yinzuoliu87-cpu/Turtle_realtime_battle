extends Node
## verify_ring_team_rim.gd — 地面环敌我描边(2026-11-04 · 方案书 docs/plans/20261104b-特效对标商业做法.md P4)
## 学的是 Supercell《荒野乱斗》「每个特效都要表明阵营」: 放技能那一刻生成的地面环外面套一圈阵营色(左蓝右红)。
##   ① 真入口 _cast_skill: 左方 / 右方各放一次带地面环的技能 ⇒ 环都带描边, 颜色分别是 RING_RIM_LEFT / RING_RIM_RIGHT, 且两边不同
##   ② 施放结束后 _ring_side 清空(之后的环不许乱描)
##   ③ ★真打一局(双路自动战 · 固定种子 · 每帧恰一步): 逐帧扫场上新出现的地面环, 有描边的占比 ≥ 90%
##   ④ 同一局地面环每分钟 ≤ 80 个(改前 249: 冰霜每根冰锥一个预警环 + 一个落地环)
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_ring_team_rim.tscn --quit-after 9000

const RTScene := preload("res://scenes/RealtimeBattle3D.tscn")
const COVER_MIN := 0.9          # 11-04 实测 40/40 = 100%(冰锥两环去掉 + 6 处异步环补施法方之后)
const RINGS_PER_MIN_MAX := 80.0 # 11-04 改前 249 个/分(冰霜每根冰锥两个环占 97%), 改后 40
const FIGHT_SECONDS := 60.0

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _rings(s) -> Array:
	var out: Array = []
	if s._world == null:
		return out
	for c in s._world.get_children():
		if c is Sprite3D and (c as Sprite3D).has_meta("ring_target_ps"):
			out.append(c)
	return out


func _ready() -> void:
	for kv in [["SHIP", "1"], ["DUALLANE", "1"], ["DL_AUTOFIGHT", "1"], ["TURTLE_SEED", "20261104"]]:
		OS.set_environment(str(kv[0]), str(kv[1]))
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var s = RTScene.instantiate()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame

	## ① 真入口: 竹叶龟「竹刺阵」(bambooSpikes) 施放时同步铺蓄力预警圈 —— 左右各放一次
	var cols := {}
	for side in ["left", "right"]:
		var foe_side := "right" if side == "left" else "left"
		var b: Dictionary = s._spawn._make_unit("bamboo", side, Vector2(600, 400))
		var f: Dictionary = s._spawn._make_unit("basic", foe_side, Vector2(700, 400))
		s._units.append(b)
		s._units.append(f)
		var before: Array = _rings(s)
		s._cast_skill(b, f, "bambooSpikes")
		var fresh: Array = []
		for r in _rings(s):
			if not before.has(r):
				fresh.append(r)
		var with_rim := 0
		var c := Color(0, 0, 0, 0)
		for r in fresh:
			if (r as Sprite3D).has_meta("ring_rim"):
				with_rim += 1
				c = ((r as Sprite3D).get_meta("ring_rim") as Sprite3D).modulate
		cols[side] = c
		var want: Color = s.RING_RIM_LEFT if side == "left" else s.RING_RIM_RIGHT
		_ok("① %s 方放「竹刺阵」: 新地面环 %d 个都带描边, 颜色 = 该方阵营色" % [side, fresh.size()],
			fresh.size() >= 1 and with_rim == fresh.size() and is_equal_approx(c.r, want.r) and is_equal_approx(c.b, want.b),
			"带描边 %d/%d · 颜色 %s" % [with_rim, fresh.size(), str(c)])
		s._units.erase(b)
		s._units.erase(f)
	_ok("① 两方描边颜色不同", not cols["left"].is_equal_approx(cols["right"]), "%s vs %s" % [str(cols["left"]), str(cols["right"])])
	_ok("② 施放结束后施法方已清空(之后的环不乱描)", str(s._ring_side) == "", "_ring_side=%s" % str(s._ring_side))

	## ③ 真打一局: 覆盖率
	s._deterministic = true
	var seen := {}
	var n_rim := 0
	var n_all := 0
	var t0 := -1.0
	var frames := 0
	while frames < 8500:
		await get_tree().process_frame
		frames += 1
		if not is_instance_valid(s):
			break
		if str(s._dl_state) != "fight":
			continue
		if t0 < 0.0:
			t0 = float(s._t)
		for r in _rings(s):
			var id: int = (r as Object).get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			n_all += 1
			if (r as Sprite3D).has_meta("ring_rim"):
				n_rim += 1
		if float(s._t) - t0 >= FIGHT_SECONDS:
			break
	var cover: float = float(n_rim) / maxf(1.0, float(n_all))
	print("  [覆盖] 战斗 %.0f 秒 · 地面环 %d 个 · 带描边 %d 个(%.0f%%)" % [float(s._t) - t0, n_all, n_rim, cover * 100.0])
	_ok("③ 分母: 一局里真出现了地面环(≥ 10 个)", n_all >= 10, "%d 个" % n_all)
	_ok("③★带敌我描边的地面环占比 ≥ %.0f%%" % (COVER_MIN * 100.0), cover >= COVER_MIN, "%.0f%%" % (cover * 100.0))
	var per_min: float = float(n_all) / maxf(1.0, float(s._t) - t0) * 60.0
	_ok("④★地面环每分钟 ≤ %.0f 个(不许每根冰锥都配环那种刷屏)" % RINGS_PER_MIN_MAX, per_min <= RINGS_PER_MIN_MAX, "%.0f 个/分" % per_min)

	print("分母: %d 项" % _n)
	if _fail == 0:
		print("ALL PASS — 地面环敌我描边")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
