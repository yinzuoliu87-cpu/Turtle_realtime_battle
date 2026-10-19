extends Node
## verify_stream_coverage.gd — 逐帧直播: 录流覆盖扫描(方案书 docs/plans/20261019-服务器逐帧直播.md 风险 R3 / 验收清单「镜像全覆盖」)。
##
## 问题: 「特效漏录有多少」—— det 15 场景 + 2 局裁判局只是样本, 28 龟 × 全部装备 × 12 羁绊没跑全。
## 做法: 每个对象单独上场打一局短局, 全程开录流(与裁判机同一个挂点形状 pre_step → _sim_step → post_step),
##   每局记四样东西, 都按「创建处」(节点 add_child 时的调用栈, 跳过 tests/ 自己的帧)归类:
##   ① 白名单外属性变化报警(录流器 keyframe / 删节点时的全量核对)          键 alarm|类.属性|出处
##   ② 占位定义(程序贴图 / 程序网格 / 其它无路径资源 / 内联 shader)          键 ph|种类:类名|出处
##      —— 手机拿到的只有类名和宽高 / 面数, 画不出来(S3 的出处键还没做)
##   ③ 第三条钟: 在 sim 步与渲染步之外改了镜像节点(SceneTree tween / 计时器 …) 键 ext|属性|出处、extdel|出处
##      以及在 sim 步之外往 _world 加节点                                     键 extadd|出处
##   ④ 分母: 这一局确实触发了这只龟的技能 / 这件装备的效果 / 这个羁绊到了顶档(见 _den())
##
## 出处键 = 「文件:函数」(不含行号: 别的改动挪了行号不该让门禁红); 报告里另记带行号的样例。
##
## 对象(全量 = 28 龟 × 3 个可选主动技 + 全部商店装备 + 12 羁绊顶档 + 小将三种 + 训龟大师六技):
##   · 龟: 左队主角(满龟能, 回充 ×4) + 半血队友; 右队两只会打会走的普通龟 + 一只远处高血假人。
##         第 PH_LOW 步把主角压到 25% 血(低血被动), 第 PH_KILL 步处决主角(死亡 / 复活被动)。
##   · 装备: 携带者 basic 3★ 单件, 其余同上(被击中 / 低血 / 阵亡类装备都有触发口)。
##   · 羁绊: 左队 4 只按类型把该类全部装备(去重)分着带, 达到顶档。
##
## 模式(环境变量):
##   默认(门禁): 跑本分片(SHARD / SHARDS)的对象; 断言 ① 每个对象分母 > 0、节点层建过节点
##                ② 观测到的键 ⊆ tests/golden/stream_coverage_known.json(已知清单 = S3 待补; 补一项删一项, 最终清零)。
##   COV_ALL=1          全量(忽略分片)
##   COV_ONLY=a,b       只跑这几个对象(对象名见 _objects())
##   COV_OUT=<绝对路径>  把逐对象结果写成 JSON(报告由它生成)
##   COV_WRITE_KNOWN=1  用本次观测到的键重写已知清单(只在全量时用)

const SIM_DT := 1.0 / 60.0
const KNOWN_PATH := "res://tests/golden/stream_coverage_known.json"
const P2T := preload("res://scripts/gamedata/phase2_types.gd")
const SEED := "424242"

## 分片: 门禁按对象序号 % SHARDS == SHARD 取。本文件 = 第 1 片; verify_stream_coverage_2/3/4 是其余三片(只覆盖这两个数)。
##   全量约 4 分钟, 单进程跑会成为门禁最长的杆 ⇒ 拆四片并行, 每片约 1 分钟。
var SHARD := 0
var SHARDS := 4

## 局长(步)。装备里最长的周期 ~10 秒(059 第 10 秒开时停), 所以装备局 1300 步。
const T_FRAMES := 900
const T_LOW := 480
const T_KILL := 700
const E_FRAMES := 1300
const E_LOW := 720
const E_KILL := 1000

var _fail := 0
var _n := 0

## ── 当前这一局 ──
var _bt: Node = null
var _rec = null
var _sites := {}          # 节点 iid → [键, 带行号样例, 标签]
var _cur := {}            # 当前对象的记录
var _subject = null       # 主角 / 携带者单位字典
var _eid := ""            # 装备局: 装备 id
var _lo0 := {}            # 开跑前的 GameState.loadouts(每局建场后还原)

## ── 全部对象 ──
var _all_keys := {}       # 键 → {n: 次数, objs: {对象: 次数}, ex: {样例: true}}
var _results: Array = []


class CovRec extends StreamRecorder:
	var host = null
	var ctx = null

	func _samp(t: StreamRecorder.TN, cont: bool) -> void:
		ctx = t
		super._samp(t, cont)
		ctx = null

	func _node_new(t: StreamRecorder.TN) -> void:
		ctx = t
		super._node_new(t)
		ctx = null

	func _alarm_node(t: StreamRecorder.TN) -> void:
		ctx = t
		super._alarm_node(t)
		ctx = null

	func _alarm_hit(key: String) -> void:
		super._alarm_hit(key)
		host._on_alarm(key, ctx)

	func _ensure(rid: int) -> void:
		if rid > 0 and not _res_sent.has(rid):
			var o = (_res_ref[rid] as WeakRef).get_ref()
			## 种类按资源此刻的样子重算(先见到、后挂出处键的, 录流器在 _ensure 里才升级种类)
			host._on_res(rid, StreamRecorder._kind_of(o) if o != null else int(_res_kind[rid]), o, ctx)
		super._ensure(rid)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var lo0: Dictionary = (gs.loadouts as Dictionary).duplicate(true)
	_lo0 = lo0.duplicate(true)
	var pe0 = gs.persistent_equipped
	gs.persistent_equipped = {}      # 羁绊按全阵容名单算; 名单空 ⇒ 退回「场上单位」口径(本扫描要的就是场上)
	var t_start := Time.get_ticks_msec()
	get_tree().node_added.connect(_on_added)

	var objs: Array = _objects()
	var only := OS.get_environment("COV_ONLY")
	var all_mode := OS.get_environment("COV_ALL") != "" or OS.get_environment("COV_WRITE_KNOWN") != ""
	var pick: Array = []
	for i in range(objs.size()):
		var o: Dictionary = objs[i]
		if only != "":
			if not (str(o["obj"]) in Array(only.split(","))):
				continue
		elif not all_mode and (i % SHARDS) != SHARD:
			continue
		pick.append(o)
	print("=== 录流覆盖扫描: %d / %d 个对象(分片 %d/%d%s) ===" % [pick.size(), objs.size(), SHARD, SHARDS,
		" 全量" if all_mode else ""])
	for o in pick:
		var t0 := Time.get_ticks_msec()
		await _run_obj(o)
		_cur["ms"] = Time.get_ticks_msec() - t0
		_results.append(_cur)
		print("  [量] %-22s 分母 %s=%d  节点 %d 核对 %d  报警 %d 占位 %d 第三钟 %d  %d ms" % [str(o["obj"]), str(_cur["den_kind"]),
			int(_cur["den"]), int(_cur["nodes_new"]), int(_cur["alarm_checked"]), int(_cur["alarm"]), int(_cur["ph"]),
			int(_cur["ext"]), int(_cur["ms"])])
		gs.loadouts = lo0.duplicate(true)
	get_tree().node_added.disconnect(_on_added)
	gs.persistent_equipped = pe0
	gs.loadouts = lo0
	(load("res://scripts/scenes/RealtimeBattle3DScene.gd")).DEBUG_EDIT = false
	OS.set_environment("TURTLE_SEED", "")
	var wall := Time.get_ticks_msec() - t_start
	print("  [量] 共 %d 个对象, 墙钟 %.1f 秒" % [pick.size(), wall / 1000.0])

	var outp := OS.get_environment("COV_OUT")
	if outp != "":
		var f := FileAccess.open(outp, FileAccess.WRITE)
		f.store_string(JSON.stringify({"objects": _results, "keys": _all_keys, "wall_ms": wall,
			"n_objects_total": objs.size()}, "\t"))
		f.close()
		print("  [量] 结果写到 ", outp)
	if OS.get_environment("COV_WRITE_KNOWN") != "":
		_write_known()

	_judge(pick)
	_finish()


# ═══════════════════════════════════════════════════════════════════════
#  对象表
# ═══════════════════════════════════════════════════════════════════════
func _objects() -> Array:
	var out: Array = []
	var pets = JSON.parse_string(FileAccess.get_file_as_string("res://data/pets.json"))
	for p in pets:
		var pid := str((p as Dictionary)["id"])
		var pool: Array = (p as Dictionary).get("skillPool", [])
		for k in range(1, pool.size()):
			out.append({"group": "龟", "obj": "%s#%d" % [pid, k], "id": pid, "skill": k, "skill_name": str(pool[k])})
	var eqs = JSON.parse_string(FileAccess.get_file_as_string("res://data/phase2-equipment.json"))
	for e in eqs:
		if int((e as Dictionary).get("shopAvailable", 0)) != 1:
			continue
		out.append({"group": "装备", "obj": str((e as Dictionary)["id"]), "name": str((e as Dictionary).get("name", ""))})
	var types = JSON.parse_string(FileAccess.get_file_as_string("res://data/p2eq-types.json"))
	var by_type := {}
	for eid in (types as Dictionary):
		var tv = (types as Dictionary)[eid]
		var tl: Array = tv if tv is Array else [tv]
		for ty in tl:
			if not by_type.has(str(ty)):
				by_type[str(ty)] = []
			## 只收商店里有的件(095 圣光护盾不出售, 羁绊件数也不算它)
			(by_type[str(ty)] as Array).append(str(eid))
	var shop := {}
	for e in eqs:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop[str((e as Dictionary)["id"])] = true
	var tnames: Array = P2T.TYPES.keys()
	tnames.sort()
	for ty in tnames:
		var ids: Array = []
		for eid in by_type.get(str(ty), []):
			if shop.has(eid) and not (eid in ids):
				ids.append(eid)
		ids.sort()
		out.append({"group": "羁绊", "obj": "羁绊:" + str(ty), "type": str(ty), "equips": ids})
	for r in ["front", "back", "elite"]:
		out.append({"group": "小将", "obj": "小将:" + r, "role": r})
	var tk: Array = (load("res://scripts/scenes/RealtimeBattle3DScene.gd")).TRAINER_SKILLS.keys()
	for k2 in tk:
		out.append({"group": "大师", "obj": "大师:" + str(k2), "tskill": str(k2)})
	return out


# ═══════════════════════════════════════════════════════════════════════
#  一局
# ═══════════════════════════════════════════════════════════════════════
func _run_obj(o: Dictionary) -> void:
	_cur = {"obj": str(o["obj"]), "group": str(o["group"]), "label": str(o.get("name", o.get("skill_name", ""))),
		"keys": {}, "alarm": 0, "ph": 0, "ext": 0, "nodes_new": 0, "alarm_checked": 0,
		"den": 0, "den_kind": "", "ev": {}}
	_sites.clear()
	_subject = null
	_eid = ""
	OS.set_environment("TURTLE_SEED", SEED)
	var gs = get_node_or_null("/root/GameState")
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	## ★调试场开场会恢复上一次「开始」时存的摆位 + loadouts(user://debug_setup.json, _edit_load_setup)
	##   ⇒ 上一局的选技会漏进下一局(实测: 同一件装备排在全量里与单跑, 节点数 269 vs 433)。删档 + 建场后还原 loadouts。
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://debug_setup.json"))
	var s = RB.new()
	_bt = s
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)
	gs.loadouts = _lo0.duplicate(true)
	s._debug._edit_clear()
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	var grp := str(o["group"])
	var frames := T_FRAMES
	var low_at := T_LOW
	var kill_at := T_KILL
	var lefts: Array = []
	if grp == "龟":
		gs.loadouts[str(o["id"])] = int(o["skill"])
		_subject = s._debug._edit_place_unit(str(o["id"]), "left", Vector2(360, 320))
		lefts.append(_subject)
	elif grp == "装备":
		frames = E_FRAMES
		low_at = E_LOW
		kill_at = E_KILL
		_eid = str(o["obj"])
		_subject = s._debug._edit_place_unit("basic", "left", Vector2(360, 320))
		_subject["_edit_equips"] = [{"id": _eid, "star": 3}]
		lefts.append(_subject)
	elif grp == "羁绊":
		frames = E_FRAMES
		low_at = -1
		kill_at = -1
		var ids: Array = o["equips"]
		var who := ["basic", "stone", "hunter", "bamboo"]
		for i in range(4):
			var part: Array = []
			for j in range(i * 3, mini(i * 3 + 3, ids.size())):
				part.append({"id": str(ids[j]), "star": 3})
			if part.is_empty():
				continue
			var u: Dictionary = s._debug._edit_place_unit(who[i], "left", Vector2(360, 200 + 110 * i))
			u["_edit_equips"] = part
			lefts.append(u)
		_subject = lefts[0]
	elif grp == "小将":
		s._edit_minion_role = str(o["role"])
		_subject = s._debug._edit_place_unit("__minion__", "left", Vector2(360, 320))
		lefts.append(_subject)
	elif grp == "大师":
		s._edit_trainer_active = str(o["tskill"])
		_subject = s._debug._edit_place_unit(s.TRAINER_ID, "left", Vector2(140, 360))
		low_at = -1
		kill_at = -1
	## 队友(半血: 给治疗友军类效果一个对象)
	var al: Dictionary = s._debug._edit_place_unit("basic", "left", Vector2(300, 470))
	## 右队: 两只会打会走的普通龟(给受击 / 击杀类效果触发口) + 一只远处高血假人(让后半局一直有目标)
	var foes: Array = []
	for k in range(2):
		var f: Dictionary = s._debug._edit_place_unit("basic", "right", Vector2(760, 260 + 140 * k))
		foes.append(f)
	var dm: Dictionary = s._debug._edit_place_unit("basic", "right", Vector2(980, 360))
	## 龟壳【复制】要从敌人身上抄技能: 敌人带上真实主动技(否则可抄池为 0, 技能放不出来)
	if grp == "龟" and str(o["id"]) == "shell":
		for f2 in foes:
			(f2 as Dictionary)["active_skills"] = s._resolve_active_skills("stone", false)
	s._debug._edit_start_battle()
	s.set_process(false)
	for f3 in foes:
		var fd: Dictionary = f3
		fd["no_basic"] = false
		fd["no_move"] = false
		fd["maxHp"] = 5000.0
		fd["hp"] = 5000.0
	al["hp"] = float(al.get("maxHp", 1000.0)) * 0.5
	## 062 螳螂虾钳要先闪避才蓄力: 给携带者 40% 闪避(同 _probe_eq_tally_coverage 的补法)
	if _eid == "p2eq_062":
		(_subject["buffs"] as Array).append({"stat": "dodge", "amount": 0.4, "pct": false, "until": 1.0e9, "src_eq": "cov"})
		s._recalc_stats(_subject)
	if grp == "羁绊":
		var tier := int((s._synergy._by_side.get("left", {}) as Dictionary).get(str(o["type"]), 0))
		var top: int = (P2T.TYPES[str(o["type"])]["tiers"] as Array).size()
		_cur["tier"] = tier
		_cur["tier_top"] = top
	## 录流
	var rec := CovRec.new(s, {})
	rec.host = self
	_rec = rec
	rec.start()
	## ★开录前先记一遍基线: 满龟能 ⇒ 第 1 步就放技, 基线不先记就会漏掉第一发
	var cd_last := {}
	var casts := 0
	var actcd_last := -1.0
	var ts_steps := 0
	var eqst_ch := 0
	var eqst_last := ""
	if _eid != "" and _subject is Dictionary:
		eqst_last = _fp_state((_subject.get("eq_state", {}) as Dictionary).get(_eid))
	if _subject is Dictionary:
		var cds0 = _subject.get("skill_cd", {})
		if cds0 is Dictionary:
			for sk0 in (cds0 as Dictionary):
				cd_last[sk0] = float((cds0 as Dictionary)[sk0])
		actcd_last = float(_subject.get("_active_cd", 0.0))
	for i in range(frames):
		if i % 60 == 0:
			await _third_clock_frame()
		rec.pre_step()
		if i == low_at and _subject is Dictionary and bool(_subject.get("alive", false)):
			_subject["hp"] = maxf(1.0, float(_subject.get("maxHp", 100.0)) * 0.25)
		if i == kill_at and _subject is Dictionary and bool(_subject.get("alive", false)):
			_subject["hp"] = 1.0
			s._kill(_subject, foes[0])
		s._sim_step(SIM_DT, float(s._hitstop) > 0.0, not (s._timestop._ts_active as Array).is_empty())
		rec.post_step()
		if not (s._timestop._ts_active as Array).is_empty():
			ts_steps += 1
		if _eid != "" and _subject is Dictionary:
			var es := _fp_state((_subject.get("eq_state", {}) as Dictionary).get(_eid))
			if es != eqst_last:
				eqst_ch += 1
				eqst_last = es
			if bool(_subject.get("_ebb_on", false)):
				_cur["ebb_on"] = int(_cur.get("ebb_on", 0)) + 1
		## 分母: 主角放技(产品自己写的 skill_cd 抬头, 与 verify_determinism_b cast_probe 同口径) / 大师 `_active_cd` 抬头
		if _subject is Dictionary:
			var cds = _subject.get("skill_cd", {})
			if cds is Dictionary:
				for sk in (cds as Dictionary):
					var cv := float((cds as Dictionary)[sk])
					if cd_last.has(sk) and cv > float(cd_last[sk]) + 0.001:
						casts += 1
					cd_last[sk] = cv
			var ac := float(_subject.get("_active_cd", 0.0))
			if actcd_last >= 0.0 and ac > actcd_last + 0.001:
				casts += 1
			actcd_last = ac
	var m: Dictionary = rec.finish()
	_rec = null
	_cur["nodes_new"] = int(m.get("nodes_new", 0))
	_cur["alarm_checked"] = int(m.get("alarm_checked", 0))
	_cur["alarm_meta"] = int(m.get("alarm", 0))
	_cur["ev"] = m.get("events", {})
	_cur["casts"] = casts
	_cur["ts_steps"] = ts_steps
	_cur["eqst_ch"] = eqst_ch
	if _eid != "" and _subject is Dictionary:
		_cur["hammer_pct"] = float(_subject.get("hammer_pct", 0.0))
	## 装备产出(产品自己的装备统计 EquipTally: 伤害 / 治疗 / 护盾)
	if _eid != "":
		var tot := 0.0
		for u in s._units:
			var st = (u as Dictionary).get("_st_eq", null)
			if st is Dictionary and (st as Dictionary).has(_eid):
				for kk in ((st as Dictionary)[_eid] as Dictionary):
					tot += float((st as Dictionary)[_eid][kk])
		_cur["eq_out"] = int(tot)
	_den(o)
	OS.set_environment("TURTLE_SEED", "")
	_bt = null
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## eq_state 的浅指纹: 只取标量值(★不能 var_to_str 整份 —— 里面挂着单位字典, 互相引用成环 ⇒ Max recursion, CLAUDE.md §3.2)。
func _fp_state(st) -> String:
	if not (st is Dictionary):
		return str(typeof(st))
	var parts := PackedStringArray()
	for k in (st as Dictionary):
		var v = (st as Dictionary)[k]
		var t := typeof(v)
		if t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL or t == TYPE_STRING:
			parts.append("%s=%s" % [str(k), str(v)])
	return ",".join(parts)


## 分母: 这一局「确实触发了」该对象。按组取产品自己的账, 取不到的明确写出用了哪一种证据。
func _den(o: Dictionary) -> void:
	var grp := str(o["group"])
	var c: Dictionary = _cur
	if grp == "龟" or grp == "小将":
		c["den_kind"] = "放技次数"
		c["den"] = int(c["casts"])
		if grp == "小将":
			## 小将没有主动技: 用「小将技能文件(rocket / hiding / elite)建过的节点」作证
			c["den_kind"] = "小将技能建节点"
			c["den"] = int(c.get("tag_minion", 0))
	elif grp == "大师":
		c["den_kind"] = "大师施法次数"
		c["den"] = int(c["casts"])
	elif grp == "装备":
		## 装备效果的证据(任一 > 0 即算): 装备统计有产出 / 装备上下文里建过节点
		var ctxn := int((c.get("ctx_nodes", {}) as Dictionary).get(_eid, 0))
		c["ctx_n"] = ctxn
		c["den_kind"] = "统计产出+上下文建节点"
		c["den"] = int(c.get("eq_out", 0)) + ctxn
		## 059 沙漏的效果就是时停本身(不产出伤害 / 治疗 / 护盾, 也不开装备统计上下文) ⇒ 证据 = 时停开着的步数(产品自己的 _ts_active)
		if _eid == "p2eq_059":
			c["den_kind"] = "时停步数"
			c["den"] = int(c.get("ts_steps", 0))
		## 强证据都是 0 时退一级(报告里单列, 不混进强证据):
		##   047 重击锤是纯属性(攻击力随最大生命), 没有演出 ⇒ 证据 = 属性真的加上了(hammer_pct)
		##   其余 = 这件装备自己的 eq_state 在局中变过(硬化层数 / 涨潮计时 / 油层 …)—— 说明效果代码跑到了, 但不保证有画面
		if int(c["den"]) <= 0:
			if _eid == "p2eq_047":
				c["den_kind"] = "纯属性(hammer_pct)"
				c["den"] = 1 if float(c.get("hammer_pct", 0.0)) > 0.0 else 0
			elif _eid == "p2eq_041":
				c["den_kind"] = "涨潮步数(_ebb_on)"
				c["den"] = int(c.get("ebb_on", 0))
			else:
				c["den_kind"] = "弱:eq_state变化次数"
				c["den"] = int(c.get("eqst_ch", 0))
	elif grp == "羁绊":
		c["den_kind"] = "顶档"
		c["den"] = 1 if int(c.get("tier", 0)) == int(c.get("tier_top", -1)) and int(c.get("tier_top", -1)) > 0 else 0


# ═══════════════════════════════════════════════════════════════════════
#  采集
# ═══════════════════════════════════════════════════════════════════════
func _phase() -> int:
	if _rec == null:
		return -1                     # 开录之前(摆位 / 建场)
	return int(_rec._ph)


func _on_added(n: Node) -> void:
	if _bt == null or not is_instance_valid(_bt):
		return
	var w = _bt.get("_world")
	if w == null or not is_instance_valid(w) or not (w as Node).is_ancestor_of(n):
		return
	var st := _site()
	_sites[n.get_instance_id()] = st
	var ph := _phase()
	if ph == StreamRecorder.PH_SIM:
		var tl = _bt._equip_sys.tally
		var ci := str(tl._iid)
		if ci != "":
			var cn: Dictionary = _cur.get("ctx_nodes", {})
			cn[ci] = int(cn.get(ci, 0)) + 1
			_cur["ctx_nodes"] = cn
		var tags: Dictionary = st[2]
		for tg in tags:
			_cur["tag_" + str(tg)] = int(_cur.get("tag_" + str(tg), 0)) + 1
	elif ph == StreamRecorder.PH_OUT and _rec != null and int(_rec._step_n) > 0:
		_hit("extadd|" + str(st[0]), str(st[1]))


## 调用栈 → [出处键「文件:函数」, 带行号样例「文件:行 <- 文件:行」, 标签]。跳过 tests/ 自己的帧。
func _site() -> Array:
	var stk: Array = get_stack()
	var picked: Array = []
	var tags := {}
	for f in stk:
		var src := str((f as Dictionary).get("source", ""))
		if src.begins_with("res://tests/"):
			continue
		if src.find("systems/skills/") >= 0:
			if src.find("rocket_system") >= 0 or src.find("hiding_system") >= 0 or src.find("elite_system") >= 0:
				tags["minion"] = true
			tags["skill"] = true
		if src.find("systems/trainer/") >= 0:
			tags["trainer"] = true
		if src.find("synergy") >= 0:
			tags["synergy"] = true
		if picked.size() < 2:
			picked.append(f)
	if picked.is_empty():
		return ["(测试代码)", "(测试代码)", tags]
	var f0: Dictionary = picked[0]
	var p0 := str(f0.get("source", "")).replace("res://", "")
	var key := "%s:%s" % [p0, str(f0.get("function", "?"))]
	var full := "%s:%d" % [p0, int(f0.get("line", 0))]
	if picked.size() > 1:
		var f1: Dictionary = picked[1]
		full += " <- %s:%d" % [str(f1.get("source", "")).replace("res://", ""), int(f1.get("line", 0))]
	return [key, full, tags]


func _site_of(t) -> Array:
	if t == null:
		return ["(无节点上下文)", "(无节点上下文)"]
	var s = _sites.get(int(t.iid))
	if s == null:
		return ["(未登记节点)", "(未登记节点)"]
	return s


func _hit(key: String, ex: String) -> void:
	var ks: Dictionary = _cur["keys"]
	ks[key] = int(ks.get(key, 0)) + 1
	var a: Dictionary = _all_keys.get(key, {"n": 0, "objs": {}, "ex": {}})
	a["n"] = int(a["n"]) + 1
	var ob: Dictionary = a["objs"]
	ob[_cur["obj"]] = int(ob.get(_cur["obj"], 0)) + 1
	var exd: Dictionary = a["ex"]
	if exd.size() < 6:
		exd[ex] = true
	_all_keys[key] = a
	if key.begins_with("alarm|"):
		_cur["alarm"] = int(_cur["alarm"]) + 1
	elif key.begins_with("ph|"):
		_cur["ph"] = int(_cur["ph"]) + 1
	else:
		_cur["ext"] = int(_cur["ext"]) + 1


func _on_alarm(prop_key: String, t) -> void:
	var s := _site_of(t)
	_hit("alarm|%s|%s" % [prop_key, str(s[0])], str(s[1]))


## 手机画不出来的几种(带出处键的 RES_GEN 能现生成、内联 shader 带源码能编 ⇒ 都不算; S3 起内联 shader 不再列, 2026-10-19)
const RES_NAMES := {2: "程序贴图", 3: "程序网格", 5: "其它无路径资源"}
func _on_res(_rid: int, kind: int, o, t) -> void:
	if not RES_NAMES.has(kind):
		return
	var cls := (o as Object).get_class() if o != null else "已释放"
	if o == null:
		kind = 5
	var s := _site_of(t)
	_hit("ph|%s:%s|%s" % [str(RES_NAMES[kind]), cls, str(s[0])], str(s[1]))


## 第三条钟: 一个引擎帧(SceneTree tween / Timer / 节点自己的 _process 在这里跑)前后, 比镜像节点的属性。
##   sim 步和渲染步都不在这一帧里跑(战斗场 _process 已关), 所以这里看到的变化录流器都看不见(要等下一次采样才补上, 或永远补不上)。
func _third_clock_frame() -> void:
	if _rec == null:
		await get_tree().process_frame
		return
	var snap: Array = []
	for t in _rec._tn:
		var n = t.n
		if not is_instance_valid(n) or (n as Node).is_queued_for_deletion() or not (n as Node).is_inside_tree():
			continue
		if _anc_queued(n):
			continue
		snap.append([t, n, _props(n)])
	await get_tree().process_frame
	for e in snap:
		var t = e[0]
		var n = e[1]
		if not is_instance_valid(n):
			var s0 := _site_of(t)
			_hit("extdel|" + str(s0[0]), str(s0[1]))
			continue
		var now: Dictionary = _props(n)
		var old: Dictionary = e[2]
		for k in old:
			var a = old[k]
			var b = now.get(k)
			if typeof(a) != typeof(b) or a != b:
				var s1 := _site_of(t)
				_hit("ext|%s|%s" % [str(k), str(s1[0])], str(s1[1]))


func _anc_queued(n: Node) -> bool:
	var w: Node = _bt.get("_world")
	var a: Node = n.get_parent()
	while a != null and a != w:
		if a.is_queued_for_deletion():
			return true
		a = a.get_parent()
	return false


## 第三条钟比的属性(录流器跟踪的那些 + 材质颜色; GPUParticles3D.emitting 不比 —— 引擎粒子自己放完, 手机端也是自己放)。
func _props(n: Node) -> Dictionary:
	var d := {}
	if n is Node3D:
		d["transform"] = (n as Node3D).transform
		d["visible"] = (n as Node3D).visible
	if n is Sprite3D:
		var sp: Sprite3D = n
		d["modulate"] = sp.modulate
		d["frame"] = sp.frame
		d["texture"] = sp.texture
		d["pixel_size"] = sp.pixel_size
	elif n is Label3D:
		d["modulate"] = (n as Label3D).modulate
		d["text"] = (n as Label3D).text
	elif n is MeshInstance3D:
		d["mesh"] = (n as MeshInstance3D).mesh
	if n is GeometryInstance3D:
		var mo = (n as GeometryInstance3D).material_override
		if mo is StandardMaterial3D:
			d["material.albedo_color"] = (mo as StandardMaterial3D).albedo_color
		d["transparency"] = (n as GeometryInstance3D).transparency
	return d


# ═══════════════════════════════════════════════════════════════════════
#  判
# ═══════════════════════════════════════════════════════════════════════
func _load_known() -> Dictionary:
	if not FileAccess.file_exists(KNOWN_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(KNOWN_PATH))
	return d if d is Dictionary else {}


func _write_known() -> void:
	var ks: Array = _all_keys.keys()
	ks.sort()
	var items: Array = []
	for k in ks:
		var a: Dictionary = _all_keys[k]
		var ob: Array = (a["objs"] as Dictionary).keys()
		ob.sort()
		items.append({"key": k, "n": int(a["n"]), "objs": ob.size(), "ex": (a["ex"] as Dictionary).keys()})
	var zero: Array = []
	for r in _results:
		if int((r as Dictionary)["den"]) <= 0:
			zero.append(str((r as Dictionary)["obj"]))
	var d := {"_说明": "录流覆盖扫描的已知清单(S3 待补)。门禁 verify_stream_coverage: 观测到的键必须 ⊆ known; 新出处即红。S3 每补一项就删一项, 最终清零。由 COV_WRITE_KNOWN=1 全量扫描生成(2026-10-19)。",
		"known": items, "zero_den": zero}
	var f := FileAccess.open(ProjectSettings.globalize_path(KNOWN_PATH), FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t") + "\n")
	f.close()
	print("  [量] 已知清单写回 %d 项, 分母为 0 的对象 %d 个" % [items.size(), zero.size()])


func _judge(pick: Array) -> void:
	var known := _load_known()
	var kset := {}
	for it in known.get("known", []):
		kset[str((it as Dictionary)["key"])] = true
	var zero_ok := {}
	for z in known.get("zero_den", []):
		zero_ok[str(z)] = true
	## S3 起已知清单清零(2026-10-19): 判「读到了」看文件解析出 known 数组, 不再要求非空(空 = 全部补完)
	_ok("分母 · 已知清单读到了(%d 项; 0 = S3 已清零)" % kset.size(), known.get("known") is Array)
	_ok("分母 · 跑了 %d 个对象" % pick.size(), pick.size() > 0 and _results.size() == pick.size())
	var no_den: Array = []
	var no_nodes: Array = []
	for r in _results:
		var rd: Dictionary = r
		if int(rd["den"]) <= 0 and not zero_ok.has(str(rd["obj"])):
			no_den.append(str(rd["obj"]))
		if int(rd["nodes_new"]) <= 0:
			no_nodes.append(str(rd["obj"]))
	_ok("★分母 · 每个对象都真的触发了(技能放过 / 装备有产出或建过节点 / 羁绊到顶档)", no_den.is_empty(), str(no_den))
	_ok("分母 · 每局节点层都建过节点", no_nodes.is_empty(), str(no_nodes))
	var fresh: Array = []
	for k in _all_keys:
		if not kset.has(str(k)):
			fresh.append("%s  ← %s" % [str(k), str((_all_keys[k]["objs"] as Dictionary).keys())])
	fresh.sort()
	for x in fresh:
		print("    新出处: ", x)
	_ok("★★报警 / 占位 / 第三条钟的出处 ⊆ 已知清单(新出处即红; S3 补一项删一项)", fresh.is_empty(), "%d 个新出处" % fresh.size())
	var seen := {}
	for k in _all_keys:
		seen[str(k)] = true
	var gone := 0
	for k in kset:
		if not seen.has(k):
			gone += 1
	print("  [量] 本分片观测到 %d 个出处键; 已知清单里本分片没碰到的 %d 个(可能已修好或只在别的分片出现)" % [seen.size(), gone])


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 录流覆盖: 分母全 > 0, 无新出处 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
