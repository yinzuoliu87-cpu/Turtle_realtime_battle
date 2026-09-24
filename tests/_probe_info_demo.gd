extends Node
## DEV 探针: `INFO_DEMO=1` 的「开场自动弹详情面板」还工作吗。
## ★不是门禁(下划线开头 ⇒ 不被自动发现)。
##
## 由来(2026-09-24): 那一处原本用 `get_tree().create_timer(1.6).timeout.connect(闭包)`,
## 是树级计时器 + 野捕获(场景没了它照样响 ⇒ "Lambda capture at index 0 was freed")。
## 改成了 Timer 子节点 + 具名方法。**而全仓没有任何门禁走这条路** ——
## 改坏了不会有人红, 所以这里手动验一次。
##
## 判据落在产品自己的状态 `battle._selected_unit`(面板打开时它才被写),
## 不是我插的标记; 并配一条分母: 不开 INFO_DEMO 时它必须是空的。
##
## 跑法: SHIP=1 INFO_DEMO=1 <godot> --headless --path . res://tests/_probe_info_demo.tscn --quit-after 4000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")


func _ready() -> void:
	await get_tree().process_frame
	var want := OS.has_environment("INFO_DEMO")
	print("=== INFO_DEMO 自动弹面板 探针 (INFO_DEMO=%s) ===" % want)
	var sc = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	get_tree().root.add_child(sc)

	## ★用**墙钟**等, 不用帧数 —— Timer 走的是真实时间, 无头帧率极高时
	##   几百帧可能连 0.1 秒都没过(CLAUDE.md §3.5)。
	var t0 := Time.get_ticks_msec()
	var opened := false
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		var su = sc.get("_selected_unit")
		if su != null and su is Dictionary and not (su as Dictionary).is_empty():
			opened = true
			break
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("  等了 %.2f 秒(墙钟)" % secs)
	print("  面板开了吗(battle._selected_unit 非空) = %s" % opened)
	if want:
		print("  ⇒ %s" % ("[PASS] 自动弹面板还在工作" if opened
			else "[FAIL] ★没弹出来 —— 那次改动把 DEV 工具弄坏了"))
	else:
		print("  ⇒ %s" % ("[FAIL] ★分母坏了: 没开 INFO_DEMO 也弹了" if opened
			else "[PASS] 分母: 不开 INFO_DEMO 就不弹"))
	get_tree().quit(0)
