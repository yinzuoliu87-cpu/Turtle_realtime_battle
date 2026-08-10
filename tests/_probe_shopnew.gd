extends Node
## _probe_shopnew.gd — 探针(只读·不进门禁): 商店【真的】掷得出新装备吗?
##
## 用户 2026-08-10 实机反馈「为啥我手机上没看到新装备」「真的能在商店里拿到新装备吗」。
## 推理和读代码都不算数 —— 这里**走真实掷货路径** `Phase2Equip.roll_shop`,
## 用真实的私人池, 按每个大轮等级各掷几百轮, 数新批(060~095)到底出不出得来。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/_probe_shopnew.tscn --quit-after 600

const Phase2Equip := preload("res://scripts/gamedata/phase2_equip.gd")
const EquipPool := preload("res://scripts/gamedata/equip_pool.gd")

const ROLLS_PER_LEVEL := 300
const SLOTS := 10


func _ready() -> void:
	await get_tree().process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260810

	# 真实私人池(走 GameState 的那条路, 不是自己造一个)
	GameState.equip_pool = {}
	GameState.ensure_equip_pool()
	var pool: Array = EquipPool.available(GameState.equip_pool, DataRegistry.phase2_equipment)

	var total_new := 0
	var total_old := 0
	var seen_new := {}
	print("── 每个等级掷 %d 轮 × %d 格 ──" % [ROLLS_PER_LEVEL, SLOTS])
	for lv in range(1, 11):
		var n_new := 0
		var n_all := 0
		for _r in range(ROLLS_PER_LEVEL):
			for it in Phase2Equip.roll_shop(pool, lv, SLOTS, rng):
				if not (it is Dictionary):
					continue
				n_all += 1
				var eid: String = str((it as Dictionary).get("id", ""))
				if _is_new(eid):
					n_new += 1
					seen_new[eid] = int(seen_new.get(eid, 0)) + 1
		total_new += n_new
		total_old += (n_all - n_new)
		print("  等级 %2d: 掷出 %5d 格, 其中新批(060~095) %5d 格 = %.1f%%"
			% [lv, n_all, n_new, 100.0 * float(n_new) / maxf(1.0, float(n_all))])

	# 新批里【一次都没掷出来】的是谁 —— 这才是真正要看的
	var never: Array = []
	for e in DataRegistry.phase2_equipment:
		if not (e is Dictionary):
			continue
		var eid2: String = str((e as Dictionary).get("id", ""))
		if _is_new(eid2) and not seen_new.has(eid2):
			never.append("%s(cost %d, shop %d)" % [eid2,
				int((e as Dictionary).get("cost", 0)),
				int((e as Dictionary).get("shopAvailable", 0))])
	print("")
	print("合计: 新批 %d 格 / 旧批 %d 格" % [total_new, total_old])
	print("新批里掷出过的不同装备: %d 种" % seen_new.size())
	print("★一次都没掷出来的: %d 件" % never.size())
	for s in never:
		print("    " + s)
	get_tree().quit(0)


func _is_new(eid: String) -> bool:
	if not eid.begins_with("p2eq_"):
		return false
	return int(eid.substr(5)) >= 60
