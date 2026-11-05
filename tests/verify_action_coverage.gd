extends Node
## 28 只龟 × 全部能力的动作覆盖门禁(方案书 docs/plans/20261105b-龟美术统一与动作补全.md §2.4 / §6「缺一格就红」, 2026-11-05)。
##
## 每只龟(data/pets.json 全部)逐格查「游戏里真有一张帧条会被播」:
##   待机(pets.json img + sprite) / 走路 / 普攻 / 受击 / 阵亡 —— 主场景 ACTION_* 表 → TurtleActions(生成) 两处任一有、且贴图加载得到;
##   三个技能(skillPool[1..3]) —— TurtleActions.CAST / CastSheets.CAST 任一有、且贴图加载得到;
##   方案书点名的形态 / 持续状态 / 复活 / 觉醒 —— TurtleActions.FORM / STATE、CastSheets.STATE。
## 不走通用表、由该龟自己的系统播的格子写在 BESPOKE, 每条都带「去哪查」, 本门禁照着去查那张图真在(不是只信注释)。
## 已知缺口写在 KNOWN_GAPS(带原因与谁定), 数目断言死 —— 新冒出的缺口一定红, 补上一个也红(提醒把表删掉一行)。

const PETS := "res://data/pets.json"
const TH_DIR := "res://assets/sprites/pets/animations/two_head/"

## 自管动作的格子: 键 = 龟:格子, 值 = [由谁播, 要在的贴图(res 路径, 全部要加载得到)]
const BESPOKE := {
	"ninja:ninjaBackstab": ["ninja_system 背刺播 backstab-rt.png(action = backstab)", ["res://assets/sprites/pets/animations/ninja/backstab-rt.png"]],
	"two_head:idle": ["TwoHeadArt ranged_idle / melee_idle(pets.json 的 img 是单张立绘, 战斗里待机由 TwoHeadArt 播)", [TH_DIR + "ranged_idle.png", TH_DIR + "melee_idle.png"]],
	"two_head:attack": ["TwoHeadArt ranged_attack / melee_attack", [TH_DIR + "ranged_attack.png", TH_DIR + "melee_attack.png"]],
	"two_head:death": ["TwoHeadArt.attach 装进 _act_rows", [TH_DIR + "ranged_death.png", TH_DIR + "melee_death.png"]],
	"two_head:run": ["TwoHeadArt ranged_walk / melee_walk", [TH_DIR + "ranged_walk.png", TH_DIR + "melee_walk.png"]],
	"two_head:twoHeadStrike": ["TwoHeadArt ranged_strike / melee_strike", [TH_DIR + "ranged_strike.png", TH_DIR + "melee_strike.png"]],
	"two_head:twoHeadDisrupt": ["TwoHeadArt ranged_disrupt / melee_absorb", [TH_DIR + "ranged_disrupt.png", TH_DIR + "melee_absorb.png"]],
	"two_head:twoHeadFusion": ["TwoHeadArt fusion_cast", [TH_DIR + "fusion_cast.png"]],
	"ghost:ghostPhase": ["虚化 = 持续状态循环(CastSheets.STATE.ghost)", ["res://assets/sprites/pets/animations/ghost/state_ghostPhase.png"]],
}
## 已知缺口: 键 = 龟:格子, 值 = 原因(现在没有)
const KNOWN_GAPS := {}
## 设计上不要的格子(不是缺口): 键 = 龟:格子, 值 = 原因(出处)
const NOT_NEEDED := {
	"shell:run": "龟壳没有腿, 移动 = 待机原样滑行(tools/assetgen/build_spine_actions.py 走路表注释「龟壳没有腿不做」)",
}
## 方案书 §2.4「形态 / 状态」列点名要有的(键 = 表名:动画键:名字)
const REQUIRED_EXTRA := [
	"FORM:lava:transform", "FORM:lava:revert", "STATE:lava_volcano:volcano",
	"FORM:angel:revive", "FORM:phoenix:revive", "FORM:shell:awaken",
	"STATE:diamond:diamondRoll", "STATE:hiding:hidingShrink", "CS_STATE:ghost:ghostPhase",
]

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _tex_ok(rel: String) -> bool:
	var p := rel if rel.begins_with("res://") else "res://assets/sprites/" + rel
	return ResourceLoader.exists(p) and load(p) != null


func _row(tbl: Dictionary, id: String) -> String:
	var r = tbl.get(id, [])
	return str((r as Array)[0]) if r is Array and (r as Array).size() >= 1 else ""


func _ready() -> void:
	await get_tree().process_frame
	print("=== 28 只龟 × 全部能力动作覆盖 ===")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(PETS))
	var pets: Array = raw.get("pets", []) if raw is Dictionary else raw
	var rb = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var cs: Dictionary = rb.get_script_constant_map()
	var main_tbl := {"attack": cs.get("ACTION_ATTACK", {}), "death": cs.get("ACTION_DEATH", {}), "run": cs.get("ACTION_RUN", {})}
	var ta_tbl := {"attack": TurtleActions.ATTACK, "death": TurtleActions.DEATH, "run": TurtleActions.RUN}
	_ok("★分母: pets.json 28 只", pets.size() == 28, "%d 只" % pets.size())
	var cells := 0
	var gaps_seen: Array = []
	var nn_seen: Array = []
	for p in pets:
		var id := str(p.get("id", ""))
		## 待机
		cells += 1
		if BESPOKE.has(id + ":idle"):
			_check_bespoke(id + ":idle")
		else:
			_ok("%s 待机帧条在" % id, _tex_ok(str(p.get("img", ""))) and not (p.get("sprite", {}) as Dictionary).is_empty())
		## 走路 / 普攻 / 受击 / 阵亡
		for kind in ["run", "attack", "death"]:   # 不含受击: 全游戏不要受击动作(用户 07-11 / 11-05, 参考云顶)
			cells += 1
			var key := "%s:%s" % [id, kind]
			var path := _row(main_tbl[kind], id)
			if path == "":
				path = _row(ta_tbl[kind], id)
			if path != "":
				_ok("%s %s 有帧条且加载得到" % [id, kind], _tex_ok(path), path)
			elif BESPOKE.has(key):
				_check_bespoke(key)
			elif KNOWN_GAPS.has(key):
				gaps_seen.append(key)
				print("  [GAP ] %s  %s" % [key, KNOWN_GAPS[key]])
			elif NOT_NEEDED.has(key):
				nn_seen.append(key)
				print("  [不要] %s  %s" % [key, NOT_NEEDED[key]])
			else:
				_ok("★%s %s 有动作(主场景表 / TurtleActions / BESPOKE 都没有)" % [id, kind], false)
		## 三个技能
		var pool: Array = p.get("skillPool", [])
		for i in range(1, mini(4, pool.size())):
			var st := str((pool[i] as Dictionary).get("type", ""))
			cells += 1
			var key := "%s:%s" % [id, st]
			var ent: Array = (TurtleActions.CAST.get(id, {}) as Dictionary).get(st, (CastSheets.CAST.get(id, {}) as Dictionary).get(st, []))
			if not ent.is_empty():
				_ok("%s 技能 %s 有释放动作且加载得到" % [id, st], _tex_ok(str(ent[0])), str(ent[0]))
			elif BESPOKE.has(key):
				_check_bespoke(key)
			elif KNOWN_GAPS.has(key):
				gaps_seen.append(key)
				print("  [GAP ] %s  %s" % [key, KNOWN_GAPS[key]])
			else:
				_ok("★%s 技能 %s(%s)有释放动作" % [id, st, str((pool[i] as Dictionary).get("name", ""))], false)
	## 形态 / 状态 / 复活 / 觉醒
	for spec in REQUIRED_EXTRA:
		var parts: PackedStringArray = str(spec).split(":")
		var path := ""
		match parts[0]:
			"FORM":
				var f: Array = (TurtleActions.FORM.get(parts[1], {}) as Dictionary).get(parts[2], [])
				path = str(f[0]) if not f.is_empty() else ""
			"STATE", "CS_STATE":
				var rows: Array = (TurtleActions.STATE if parts[0] == "STATE" else CastSheets.STATE).get(parts[1], [])
				for r in rows:
					if str((r as Array)[0]) == parts[2]:
						path = str((r as Array)[1])
		cells += 1
		_ok("%s 有帧条且加载得到" % spec, path != "" and _tex_ok(path), path)
	_ok("★分母: 查了 ≥ 28 × 7 格", cells >= 28 * 7, "%d 格" % cells)
	## 受击不许回来: 主场景受击表为空、生成表没有 HURT、盘上没有任何单位的 hurt.png
	var hurt_files: Array = []
	var dd := DirAccess.open("res://assets/sprites/pets/animations")
	if dd != null:
		for sub in dd.get_directories():
			if FileAccess.file_exists("res://assets/sprites/pets/animations/%s/hurt.png" % sub):
				hurt_files.append(sub)
	_ok("★没有受击动作: ACTION_HURT 空、TurtleActions 没有 HURT 表、没有 hurt.png", (cs.get("ACTION_HURT", {}) as Dictionary).is_empty()
		and not (load("res://scripts/gamedata/turtle_actions.gd") as Script).get_script_constant_map().has("HURT") and hurt_files.is_empty() and dd != null, str(hurt_files))
	_ok("★已知缺口数 == 登记数(补上一个要把 KNOWN_GAPS 删一行; 新缺口不许混进来)", gaps_seen.size() == KNOWN_GAPS.size(), "%d / %d %s" % [gaps_seen.size(), KNOWN_GAPS.size(), str(gaps_seen)])
	_ok("★设计上不要的格子数 == 登记数", nn_seen.size() == NOT_NEEDED.size(), "%d / %d %s" % [nn_seen.size(), NOT_NEEDED.size(), str(nn_seen)])
	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 28 只龟全部能力都有动作(已知缺口 %d 处已登记)" % gaps_seen.size() if _fail == 0 else "FAIL")
	get_tree().quit(0 if _fail == 0 else 1)


func _check_bespoke(key: String) -> void:
	var b: Array = BESPOKE[key]
	var all_ok := true
	for pth in (b[1] as Array):
		all_ok = all_ok and _tex_ok(str(pth))
	_ok("%s 自管动作在(%s)" % [key, str(b[0])], all_ok and (b[1] as Array).size() > 0)
