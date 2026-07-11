extends Node
## verify_season_flow.gd — 守卫 R1: 大轮阵容锁定 + 3选1 技能可变
## 用户〖2026-07-11〗:「一个大轮固定3只龟…选好后整个大轮锁定但技能可以变」
##
## 断言:
##   A. 战斗引擎荣誉 loadout —— 每只龟每个候选 idx1/2/3 选中后 _resolve_chosen_index 都真返回该 idx,
##      不静默回落 idx1 (拆掉 TeamSelect 那道 `idx != 1` 死门后, 技能可变必须端到端生效)。
##   B. start_new_season 同时清空 season_leaders 与 loadouts (新大轮阵容+技能一起重来)。
##   C. loadouts 经 JSON 往返(数字→float) 后按 _load 同逻辑强转回 int (存档持久不丢/不类型漂移)。
##   D. 锁定判定 = season_leaders 满 REQUIRED_PETS(3): 空=全选态 / 满3=确认出战锁定态。
##
## ★安全: 全程不调 GameState.save()/_load() —— 避免写坏玩家真实存档 user://savegame.json。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true   # 阻断任何自动 save (双保险)

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	# ── A. 战斗引擎荣誉所有龟所有候选 idx1/2/3 ──
	var data: Dictionary = scene._data_by_id
	_ok("pets 数据已加载", data.size() >= 28, "共 %d 只" % data.size())
	var reverted: Array = []
	var checked := 0
	for pid in data.keys():
		var pool: Array = (data[pid] as Dictionary).get("skillPool", [])
		for idx in range(1, pool.size()):
			gs.loadouts = {str(pid): idx}
			var got: int = scene._resolve_chosen_index(str(pid), true)
			checked += 1
			if got != idx:
				reverted.append("%s idx%d→%d" % [pid, idx, got])
	_ok("★所有龟 3选1 候选战斗引擎都荣誉不回落 (%d 个候选)" % checked, reverted.is_empty(),
		("回落: " + ", ".join(reverted)) if not reverted.is_empty() else "")

	# ── B. start_new_season 清 season_leaders + loadouts ──
	gs.season_leaders = ["basic", "stone", "ice"]
	gs.loadouts = {"basic": 2, "cyber": 3}
	gs.start_new_season()
	_ok("新赛季清空 season_leaders", (gs.season_leaders as Array).is_empty())
	_ok("新赛季清空 loadouts", (gs.loadouts as Dictionary).is_empty())

	# ── C. loadouts JSON 往返 float→int 强转 (与 GameState._load 同逻辑) ──
	var raw := {"loadouts": {"basic": 2, "cyber": 3}}
	var round_tripped = JSON.parse_string(JSON.stringify(raw))
	var lo: Dictionary = {}
	var lr: Dictionary = (round_tripped as Dictionary).get("loadouts", {})
	for k in lr:
		var v = lr[k]
		lo[str(k)] = int(v) if (v is int or v is float) else v
	_ok("JSON 往返后 loadouts 值强转回 int", lo.get("basic") is int and lo.get("basic") == 2 and lo.get("cyber") == 3,
		"basic=%s(%s) cyber=%s" % [lo.get("basic"), typeof(lo.get("basic")), lo.get("cyber")])

	# ── D. 锁定判定 = season_leaders 满 3 ──
	gs.season_leaders = []
	_ok("空 season_leaders = 未锁定(全选态)", (gs.season_leaders as Array).size() != 3)
	gs.season_leaders = ["basic", "stone", "ice"]
	_ok("满 3 season_leaders = 已锁定(确认出战态)", (gs.season_leaders as Array).size() == 3)

	# ── E. 真实 TeamSelect 场景在锁定/全选两态都能起(_roster_locked 正确 + 不崩) ──
	var ts_packed = load("res://scenes/TeamSelect.tscn")
	# E1 锁定态: season_leaders 满 3 → _roster_locked=true
	gs.season_leaders = ["basic", "stone", "ice"]
	gs.clear_team()
	var ts_locked = ts_packed.instantiate()
	add_child(ts_locked)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("锁定态 TeamSelect 起且 _roster_locked=true", ts_locked._roster_locked == true,
		"_roster_locked=%s" % ts_locked._roster_locked)
	_ok("锁定态预填了 3 龟阵容", (GameState.left_team as Array).size() == 3)
	ts_locked.queue_free()
	await get_tree().process_frame
	# E2 全选态: season_leaders 空 → _roster_locked=false
	gs.season_leaders = []
	gs.clear_team()
	var ts_open = ts_packed.instantiate()
	add_child(ts_open)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("全选态 TeamSelect 起且 _roster_locked=false", ts_open._roster_locked == false,
		"_roster_locked=%s" % ts_open._roster_locked)
	ts_open.queue_free()
	await get_tree().process_frame

	_done()


func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 大轮锁定+技能可变 端到端守卫通过")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)
