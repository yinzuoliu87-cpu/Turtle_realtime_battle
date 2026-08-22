extends Node
## 让场上打满各种伤害, 收哨兵报告
func _ready() -> void:
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	## ★分母保证: 默认队未必带灵物 ⇒ 触手可能一根都不存在, 那样账本全是 0 而我会
	##   误读成"没问题"。这里给双方每只龟塞 5 件灵物装备并重算羁绊, 强制两边都有触手。
	##   (memory [[fb-gate-subject-never-constructed]]: 判据没错但被测对象不在场。)
	for u in scn._units:
		if u is Dictionary:
			u["equips"] = [{"id": "p2eq_032", "star": 1}, {"id": "p2eq_025", "star": 1},
				{"id": "p2eq_014", "star": 1}, {"id": "p2eq_045", "star": 1},
				{"id": "p2eq_051", "star": 1}]
	scn._synergy.clear()
	scn._synergy.apply_all()
	print("  ★分母自证: 灵物档位 左=%d 右=%d (为 0 就没有触手, 下面的账本不算数)" % [
		scn._spirit_syn._side_tier("left"), scn._spirit_syn._side_tier("right")])
	var secs: float = float(OS.get_environment("SENT_SECS")) if OS.has_environment("SENT_SECS") else 60.0
	var t0: float = float(Time.get_ticks_msec()) / 1000.0
	while float(Time.get_ticks_msec()) / 1000.0 - t0 < secs:
		await get_tree().process_frame
	## 触手拍击账本(用户 2026-08-22:「有的时候触手打中没任何伤害」)
	var pk: Dictionary = scn._spirit_syn._pk
	print("★触手拍击账本: 排队 %d / 被闸门丢掉 %d / 真结算 %d / 结算了但零命中 %d" % [
		int(pk.get("queued", 0)), int(pk.get("dropped", 0)),
		int(pk.get("resolved", 0)), int(pk.get("zero_hit", 0))])
	print("  队列丢弃: 回调失效 %d / 换路清空 %d / 结束时仍在队列 %d" % [
		int(scn._ballistics._ps_drop_invalid), int(scn._ballistics._ps_drop_cleared),
		scn._pending_shots.size()])
	var rep: Dictionary = scn._damage.sentinel_report()
	var rows: Array = []
	var tot := 0
	for k in rep:
		rows.append([int(rep[k]), str(k)])
		tot += int(rep[k])
	rows.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	print("★哨兵报告: 共 %d 发伤害是【捡来的类型】(颜色看运气), 涉及 %d 种来源" % [tot, rows.size()])
	for r in rows.slice(0, 26):
		print("   %6d 次   %s" % [int(r[0]), str(r[1])])
	get_tree().quit(0)
