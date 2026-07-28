extends Node
## verify_turtle_roles.gd — 焊死【定位 = 权威事实源】(用户 2026-07-28)
##
## 背景: 定位以前只活在 turtle_stats.gd 的一行注释里, 没有字段承载 ——
## 结果攻速遵守了定位、移速完全没跟: 28 只龟只有 4 个移速值, 且【远程均移速 > 近战均移速】(关系是反的),
## 近战坦克结构性追不上远程、被风筝到死。定位化之后必须有门禁守着, 否则同样的漂移会再来一次。
##
## 查 6 条:
##   ① 每只龟都有 ROLE (新增龟漏填 → 红)
##   ② ROLE 里的档位都在 ROLE_SPEC 中 (拼错档名 → 红)
##   ③ STATS 的移速/攻速 == ROLE_SPEC 派生值 (手改 STATS 数值 → 红)
##   ④ ROLE 的近战/远程前缀 == STATS 的 melee 标记 (白名单 ROLE_MELEE_EXEMPT 除外)
##   ⑤ ★结构保证: 近战最慢档 > 远程最快档 (改档位数值把这条破坏掉 → 红)
##   ⑥ ROLE_SPEC 没有空档 (定义了却没龟用 = 死数据)
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_turtle_roles.tscn

const TS := preload("res://scripts/gamedata/turtle_stats.gd")

var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("=== 定位(ROLE) ↔ 属性(STATS) 一致性 ===")
	var roles: Dictionary = TS.ROLE
	var spec: Dictionary = TS.ROLE_SPEC
	var stats: Dictionary = TS.STATS
	var exempt: Array = TS.ROLE_MELEE_EXEMPT
	print("  %d 只龟 / %d 个定位档 / %d 只 melee 例外" % [stats.size(), spec.size(), exempt.size()])
	if stats.size() < 28:
		_bad("★龟数 %d < 28 —— 分母不对, 后面的检查没意义" % stats.size())

	# ① + ② + ③ + ④
	var n_chk := 0
	for id in stats.keys():
		var st: Array = stats[id]
		if not roles.has(id):
			_bad("① %s 没有 ROLE —— 新增龟必须填定位" % id); continue
		var r: String = str(roles[id])
		if not spec.has(r):
			_bad("② %s 的定位 %s 不在 ROLE_SPEC 里(档名拼错?)" % [id, r]); continue
		var sp: Array = spec[r]
		var want_spd: float = float(sp[0])
		var want_iv: float = 1.0 / float(sp[1])
		n_chk += 2
		if absf(float(st[1]) - want_spd) > 0.01:
			_bad("③ %s(%s) 移速 %.1f ≠ 档位值 %.1f" % [id, r, float(st[1]), want_spd])
		if absf(float(st[2]) - want_iv) > 0.001:
			_bad("③ %s(%s) 攻击间隔 %.4f ≠ 档位值 %.4f (攻速 %.2f)" % [id, r, float(st[2]), want_iv, float(sp[1])])
		n_chk += 1
		var role_melee: bool = r.begins_with("近战")
		if role_melee != bool(st[0]) and not (id in exempt):
			_bad("④ %s 定位是 %s 但 melee=%s —— 要么改定位, 要么进 ROLE_MELEE_EXEMPT 白名单" % [id, r, st[0]])
	print("  ①②③④ 共 %d 条断言" % n_chk)

	# ⑤ 结构保证: 近战最慢 > 远程最快
	var melee_min := 99999.0
	var ranged_max := -1.0
	for r in spec.keys():
		var v: float = float((spec[r] as Array)[0])
		if str(r).begins_with("近战"):
			melee_min = minf(melee_min, v)
		else:
			ranged_max = maxf(ranged_max, v)
	print("  ⑤ 近战最慢档 %.0f  vs  远程最快档 %.0f" % [melee_min, ranged_max])
	if melee_min <= ranged_max:
		_bad("⑤ 近战最慢(%.0f) ≤ 远程最快(%.0f) —— 近战追不上远程, 这次整改的目的就没了" % [melee_min, ranged_max])

	# ⑥ 空档 = 死数据
	var used := {}
	for id in roles.keys():
		used[str(roles[id])] = true
	for r in spec.keys():
		if not used.has(str(r)):
			_bad("⑥ 定位档 %s 定义了但没有龟使用 = 死数据, 删掉或给它龟" % r)

	# 汇总: 打印每档实际人数(分母可见)
	print("")
	var cnt := {}
	for id in roles.keys():
		var r2: String = str(roles[id])
		cnt[r2] = int(cnt.get(r2, 0)) + 1
	for r in spec.keys():
		var sp2: Array = spec[r]
		print("  %-10s 移速%5.0f 攻速%.2f  %d只" % [r, float(sp2[0]), float(sp2[1]), int(cnt.get(str(r), 0))])

	print("")
	print("  ALL PASS" if _fail == 0 else "  ★ %d 项 FAIL" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _bad(msg: String) -> void:
	_fail += 1
	print("  [FAIL] " + msg)
