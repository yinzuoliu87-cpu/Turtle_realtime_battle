extends Node
## _probe_poolguard.gd — 证明 save_pool 的 test_mode 守卫【真在起作用, 且不是恒真】
##
## 起因: _probe_autoplay 跑完玩家真实 ghost_pool.json 的 md5 没变, 但那三把全输 →
## upload_ghost 在 `if won:` 里根本没被调到 → 「md5 没变」是【空证据】。
## 本探针不靠打赢, 直接调 upload_ghost/save_pool, 两个方向各验一次:
##   A. 默认路径(user://ghost_pool.json) + test_mode → 必须【不写】(文件 md5 不变)
##   B. 显式路径(自举仿真要用的) + test_mode → 必须【照写】(文件真出现)
## 只有 A 和 B 同时成立, 才说明守卫在"discriminate"而不是"什么都不写"或"什么都写"。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/_probe_poolguard.tscn

const Backend := preload("res://scripts/net/backend.gd")

const REAL := "user://ghost_pool.json"
const TMP := "user://_probe_guard_tmp.json"

var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _md5(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "(不存在)"
	return FileAccess.get_md5(path)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 没有 GameState"); get_tree().quit(1); return

	# 清掉上次残留, 保证 B 的"文件出现"是本次写的
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))

	var before := _md5(REAL)
	_ok("分母: 玩家真实池存在(否则整个验证是空的)", before != "(不存在)", "md5=%s" % before.substr(0, 12))

	print("  test_mode = %s (headless 应自动为 true)" % str(gs.test_mode))
	_ok("headless 下 test_mode 自动为 true", bool(gs.test_mode))

	# ── A: 默认路径必须不写 ──
	var snap := {"schema_ver": 1, "ghost_id": "probe_guard_should_never_land", "is_bot": true,
		"bracket": 3, "profile": {"name": "守卫探针", "avatar": "basic", "id": "PRB"},
		"leaders": ["basic"], "lane_assign": {"top": ["basic"], "bottom": []},
		"minions": {}, "loadouts": {}, "equipped": {}, "pet_levels": {"basic": 1},
		"season_total_battles": 8, "season_eggs_killed": 0}
	# 直接调 save_pool(默认路径) —— 绕开 upload_ghost 里的 load_pool, 只测守卫本身
	Backend.save_pool({"brackets": {"3": [snap]}})
	var after := _md5(REAL)
	_ok("★A 默认路径 + test_mode → 玩家真实池【没被写】", after == before,
		"before=%s after=%s" % [before.substr(0, 12), after.substr(0, 12)])

	# ── B: 显式路径必须照写(证明守卫不是"什么都不写"的恒真) ──
	Backend.save_pool({"brackets": {"3": [snap]}}, TMP)
	var tmp_exists := FileAccess.file_exists(TMP)
	_ok("★B 显式路径 + test_mode → 照写不误(守卫非恒真·自举仿真能产池)", tmp_exists,
		"写出=%s" % str(tmp_exists))
	if tmp_exists:
		var f := FileAccess.open(TMP, FileAccess.READ)
		var txt := f.get_as_text(); f.close()
		_ok("★B 写出的内容真是我给的那支队", txt.find("probe_guard_should_never_land") >= 0)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))

	# ── C: upload_ghost 整条链(load_pool→pool_add→save_pool)也不许碰真实池 ──
	#     load_pool 内部 _ensure_seeded 也会 save_pool(backend.gd:211) → 这条链是最隐蔽的写盘路径
	Backend.upload_ghost(snap)
	var after2 := _md5(REAL)
	_ok("★C upload_ghost 整条链(含 _ensure_seeded 落盘) → 真实池仍没被写", after2 == before,
		"after2=%s" % after2.substr(0, 12))

	print("ALL PASS — save_pool 守卫两个方向都成立" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
