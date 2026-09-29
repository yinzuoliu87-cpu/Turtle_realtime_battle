extends Node
## _probe_canary_home.gd — 探子 Label 挂进 Settings 之后**落在谁名下、看不看得见** (2026-09-29)
##
## 由来: `verify_no_emoji_icons` 的「分母 Settings: 探子逮不到」在**后端配着**时红。
## 假设: 登录墙一立, `_maybe_login_wall` 把 self 下所有 Control 藏掉(含 `DesignFrame`),
##       而 `UIFrame._process` 的孤儿收编会把后挂进来的探子搬进 `DesignFrame`
##       ⇒ 探子跟着变不可见 ⇒ 扫描器数不到它。
## 跑法: <godot> --headless --path . res://tests/_probe_canary_home.tscn --quit-after 900
const SB := preload("res://scripts/net/supabase.gd")


func _wf(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _one(label: String, backend: String) -> void:
	OS.set_environment("TURTLE_SUPABASE", backend)
	SB._reset_auth_for_test()
	GameState.account_email = ""
	GameState.account_id = "uid-canary"
	var inst = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	add_child(inst)
	await _wf(24)
	print("=== %s  (SB.enabled=%s  墙=%s) ===" % [label, str(SB.enabled()),
		str(inst._email_layer != null)])
	var probe := Label.new()
	probe.name = "EmojiCanary"
	probe.text = "🐢"
	inst.add_child(probe)
	print("  刚挂上去: 父 = %s  visible_in_tree = %s" % [str(probe.get_parent().name),
		str(probe.is_visible_in_tree())])
	for k in [1, 2, 3, 8]:
		await _wf(1)
		print("  等 %d 帧后: 父 = %-14s visible_in_tree = %-5s  visible = %s" % [k,
			str(probe.get_parent().name), str(probe.is_visible_in_tree()), str(probe.visible)])
	inst.queue_free()
	await _wf(3)


func _ready() -> void:
	await _wf(2)
	GameState.test_mode = true
	await _one("后端没配(门禁默认) ⇒ 不立墙", " ")
	await _one("后端配了 ⇒ 立墙", "http://127.0.0.1:9")
	OS.set_environment("TURTLE_SUPABASE", " ")
	SB._reset_auth_for_test()
	print("PROBE DONE")
	get_tree().quit(0)
