extends Node
## _probe_eq_tally_coverage.gd — ④ 装备统计覆盖表: 全部装备逐件上场, 看每件的本局账记到了没有(2026-10-04)
##
## 只读探针: 不进门禁(文件名以 _ 开头, run-tests 不发现)。产出方案书 §8 ④ 的覆盖表。
##
## 每件: 干净小场 —— 携带者(3★, 半血, 会普攻、开局满龟能) + 一个半血队友 + 3 个高血敌人(低攻, 会还手)
##   + 1 个脆皮敌人(给击杀/敌亡类装备一个触发口)。推 25 游戏秒, 然后处决携带者再推 6 秒(给阵亡类装备)。
##   同种子再跑一遍【不带装备】的对照, 打印 Δ(我方造成 / 我方回血 / 我方获盾) 帮助判断「0 是真没有, 还是归因漏了」。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/_probe_eq_tally_coverage.tscn --quit-after 2000000
##   EQ_ONLY=p2eq_001,p2eq_002 只跑这几件

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EQS := preload("res://scripts/gamedata/equip_stats.gd")
const DT := 1.0 / 60.0

var s = null
var names: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	RB.DEBUG_EDIT = true
	s = RB.new()
	add_child(s)
	for _i in range(10):
		await get_tree().process_frame
	s._deterministic = true
	s.set_process(false)   # ★不让场景自己的 _process 插进来(调试场模式会把 _edit_mode 拨回去 ⇒ 单位不 tick, 第一版覆盖表因此大片假 0)
	var f := FileAccess.open("res://data/phase2-equipment.json", FileAccess.READ)
	for e in JSON.parse_string(f.get_as_text()):
		names[str(e["id"])] = str(e.get("name", ""))
	var ids: Array = EQS.STATS.keys()
	ids.sort()
	var only: String = OS.get_environment("EQ_ONLY")
	if only != "":
		ids = Array(only.split(","))
	print("[COV] 件数 %d" % ids.size())
	print("[COV] id|名|phy|mag|tru|heal|shield|Δ造成|Δ回血|Δ获盾")
	for iid in ids:
		## ★每件一个全新的战斗场: 前一件留下的全局状态(时停/在途协程/被释放的演出节点)会把后面的件
		##   静默弄成「不触发」—— 同一件单跑记得到数, 排在全量里就是 0(实测 018/042/048)。
		s.queue_free()
		await get_tree().process_frame
		s = RB.new()
		add_child(s)
		for _j in range(6):
			await get_tree().process_frame
		s._deterministic = true
		s.set_process(false)
		var ctl: Array = await _run("")
		var got: Array = await _run(str(iid))
		var t: Dictionary = got[0]
		var r: Dictionary = t.get(iid, {})
		print("[COV] %s|%s|%d|%d|%d|%d|%d|%d|%d|%d" % [iid, names.get(iid, "?"),
			int(r.get("phy", 0)), int(r.get("mag", 0)), int(r.get("tru", 0)),
			int(r.get("heal", 0)), int(r.get("shield", 0)),
			int(got[1] - ctl[1]), int(got[2] - ctl[2]), int(got[3] - ctl[3])])
		var other: Array = []
		for k in t.keys():
			if str(k) != str(iid):
				other.append(str(k))
		if not other.is_empty():
			print("[COV]   ⚠ %s 场上还记到了别的件: %s" % [iid, str(other)])
	print("[COV] DONE")
	get_tree().quit(0)


func _mk(id: String, side: String, pos: Vector2) -> Dictionary:
	return s._spawn._make_unit(id, side, pos)


## 返回 [携带者的 _st_eq(含召唤物/队友身上意外记到的合并), 我方造成合计, 我方回血合计, 我方获盾合计]
func _run(iid: String) -> Array:
	s._battle_rng.seed = 20261004
	s._dl_sys._dl_clear_units()
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = _mk("basic", "left", c + Vector2(-60, 0))
	u["maxHp"] = 6000.0; u["hp"] = 3000.0; u["atk"] = 120.0; u["no_move"] = true
	u["energy"] = 100.0
	var al: Dictionary = _mk("basic", "left", c + Vector2(-120, 30))
	al["maxHp"] = 6000.0; al["hp"] = 3000.0; al["no_basic"] = true; al["no_move"] = true
	var es: Array = []
	for i in range(3):
		var e: Dictionary = _mk("basic", "right", c + Vector2(10.0 + 50.0 * float(i), -20.0 + 20.0 * float(i)))
		e["maxHp"] = 1.0e6; e["hp"] = 1.0e6; e["atk"] = 25.0; e["no_move"] = true
		es.append(e)
	var fod: Dictionary = _mk("basic", "right", c + Vector2(30, 40))
	fod["maxHp"] = 400.0; fod["hp"] = 400.0; fod["atk"] = 1.0; fod["no_move"] = true
	s._units.clear()
	for x in [u, al, fod]:
		s._units.append(x)
	s._units.append_array(es)
	s._edit_mode = false
	s._over = false
	u["equips"] = [] if iid == "" else [{"id": iid, "star": 3}]
	u["eq_state"] = {} if iid == "" else {iid: {}}
	s._equip_sys._stats._eq_apply_all_stats()
	for k in range(1500):
		s._sim_step(DT, false, false)
		if k % 4 == 0:
			await get_tree().process_frame
	if u.get("alive", false):
		u["hp"] = 1.0
		s._kill(u, es[0])
	for k in range(360):
		s._sim_step(DT, false, false)
		if k % 4 == 0:
			await get_tree().process_frame
	var dealt := 0.0
	var heal := 0.0
	var sh := 0.0
	var tally: Dictionary = {}
	for x in s._units:
		if str(s._eff_side(x)) == "left":
			dealt += float(x.get("_st_dealt", 0))
			heal += float(x.get("_st_heal", 0))
			sh += float(x.get("_st_shield", 0))
		var t = x.get("_st_eq", null)
		if t is Dictionary:
			for k2 in (t as Dictionary).keys():
				var r: Dictionary = tally.get(k2, {})
				for kk in (t[k2] as Dictionary).keys():
					r[kk] = float(r.get(kk, 0.0)) + float(t[k2][kk])
				tally[k2] = r
	s._over = true
	return [tally, dealt, heal, sh]
