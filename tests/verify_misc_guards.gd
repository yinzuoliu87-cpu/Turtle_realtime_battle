extends Node
## verify_misc_guards.gd — 补守 T4 盘点出的"裸奔"机制（改坏了不报错、只会悄悄出问题的那些）
##
## 覆盖：BGM 音量公式 / 立绘朝向例外表 / 眩晕唯一入口 / 结算跨战场快照
## 这几项的共同特点：出问题时【编译过、测试过、压测也不报错】，只有玩家能察觉。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame

	# ── A. BGM 音量: apply_bgm_volume 必须与 play_bgm 用同一条公式 ──
	# 起因(2026-07-19): 我修音量滑条时只补了调用、没统一公式 —— apply 直接用 bgm_volume,
	# 丢掉了每场景各异的 base_vol → 拖一下滑条战斗音乐会突然响 29%。
	var au = get_node_or_null("/root/Audio")
	if au != null:
		var src := FileAccess.open("res://autoload/Audio.gd", FileAccess.READ)
		var txt := src.get_as_text() if src != null else ""
		if src != null: src.close()
		_ok("Audio 有 _current_base_vol 字段(记住场景基准)", txt.contains("_current_base_vol"))
		_ok("★apply_bgm_volume 用 base_vol×(bgm_volume/0.45) 同一公式",
			txt.contains("_current_base_vol * (bgm_volume / 0.45)"),
			"若失败=又退回只用 bgm_volume 的旧公式")
		_ok("play_bgm 会记下 base_vol", txt.contains("_current_base_vol = base_vol"))
	else:
		_ok("Audio autoload 存在", false, "取不到 /root/Audio")

	# ── B. 立绘朝向: 例外表必须对【召唤物】也生效 ──
	# 起因: 召唤物 id 是 "_summon_<kind>", 永远匹配不上按龟 id 写的 ART_FACES_RIGHT
	# → 用户 2026-07-19 报「机甲建模也反了」。
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame
	_ok("★机甲(召唤物·kind=mech) 判定为需翻转",
		s._art_faces_right({"id": "_summon_mech", "is_summon": true, "summon_kind": "mech"}),
		"若失败=例外表又对召唤物失效了")
	_ok("玩偶熊(kind=bear) 不翻转", not s._art_faces_right({"id": "_summon_bear", "is_summon": true, "summon_kind": "bear"}))
	_ok("缩头龟(按龟 id) 仍然翻转", s._art_faces_right({"id": "hiding"}))
	_ok("普通龟不翻转", not s._art_faces_right({"id": "basic"}))

	# ── C. 眩晕唯一入口: 全项目只有 _stun 能写 stun_until ──
	# 起因: 原先 17 处各写各的 maxf(...), 查不出是谁上的控; 收口后韧性/来源记录/将来的规则都只在一处。
	var f := FileAccess.open("res://scripts/scenes/RealtimeBattle3DScene.gd", FileAccess.READ)
	var writes := 0
	var ln := 0
	while f != null and not f.eof_reached():
		var line := f.get_line()
		ln += 1
		var t := line.strip_edges()
		if t.begins_with("#") or t.begins_with("##"):
			continue
		if line.contains("[\"stun_until\"] = maxf"):
			writes += 1
	if f != null: f.close()
	_ok("★stun_until 只有 1 处写入(=_stun 内部)", writes == 1, "实际 %d 处" % writes)

	# ── D. 结算统计: 跨战场快照函数在 ──
	# 起因: 结算页原本只显当前战场; 快照存的是纯标量(不能存单位字典, 会成环)
	_ok("有跨战场快照 _st_snapshot_lane", s.has_method("_st_snapshot_lane"))
	_ok("有合计归并 _st_merge_all", s.has_method("_st_merge_all"))
	var row: Dictionary = s._st_row({"name": "测试龟", "hp": 50.0, "maxHp": 100.0, "_st_dealt": 7})
	_ok("★快照行是纯标量(无单位字典引用, 防成环)",
		not row.values().any(func(v): return v is Dictionary or v is Array),
		"字段=%s" % [row.keys()])

	print("ALL PASS — 杂项守卫" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
