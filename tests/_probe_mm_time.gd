extends Node
## _probe_mm_time.gd — 探针(不是门禁): 时间缝开完之后, 到底量得到什么、量不到什么。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/_probe_mm_time.tscn --quit-after 600

const BE := preload("res://scripts/net/backend.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

const MON0 := 1789344000        # 2026-09-14 周一 00:00:00 UTC


func _ghost(id: String, battles: int) -> Dictionary:
	return {
		"schema_ver": BE.SCHEMA_VER,
		"ghost_id": id,
		"is_bot": false,
		"origin": BE.ORIGIN_REMOTE,
		"profile": {"name": "对手%s" % id},
		"leaders": ["basic", "ninja", "stone"],
		"season_total_battles": battles,
	}


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	print("── ① 缝的默认透明度 ──")
	var sys0: int = int(Time.get_unix_time_from_system())
	print("  now_override_ts=%d  now_utc()=%d  system=%d  diff=%d"
		% [P2.now_override_ts, P2.now_utc(), sys0, P2.now_utc() - sys0])

	print("── ② 钉住 ──")
	P2.now_override_ts = MON0 + 3 * 86400 + 9 * 3600
	print("  钉后 now_utc()=%d  phase=%s  iso_wd=%d"
		% [P2.now_utc(), P2.phase_at_utc(P2.now_utc()), P2.iso_weekday_utc(P2.now_utc())])
	P2.now_override_ts = 0
	print("  还原后 now_utc()-system=%d" % (P2.now_utc() - int(Time.get_unix_time_from_system())))

	print("── ③ 七天 × 相位 / 周锚点 ──")
	for d in range(7):
		P2.now_override_ts = MON0 + d * 86400 + 12 * 3600
		var n: int = P2.now_utc()
		print("  d=%d wd=%d phase=%-8s anchor_ok=%s quota=%s live=%s can_start=%s"
			% [d, P2.iso_weekday_utc(n), P2.phase_at_utc(n),
				str(P2.week_anchor_utc(n) == MON0),
				str(P2.phase_uses_ranked_quota(P2.phase_at_utc(n))),
				str(P2.phase_mode_live(P2.phase_at_utc(n))),
				str(P2.can_start_match_utc(n))])

	print("── ④ 封盘: 7 天 × 24 小时 × {:00, :40, :50} 全扫, 只打【封住】的 ──")
	var blocked: Array = []
	var total := 0
	for d in range(7):
		for h in range(24):
			for m in [0, 40, 50]:
				var ts: int = MON0 + d * 86400 + h * 3600 + m * 60
				P2.now_override_ts = ts
				total += 1
				if not P2.can_start_match_utc(ts):
					blocked.append("wd%d %02d:%02d(left=%d)"
						% [P2.iso_weekday_utc(ts), h, m, P2.close_left_sec(ts)])
	print("  扫了 %d 个时刻, 封住 %d 个:" % [total, blocked.size()])
	for b in blocked:
		print("    ", b)

	print("── ④b 收盘之后那一小时(周五 23:00~24:00 / 周六 23:00~24:00) ──")
	for spec in [[4, 23, 0], [4, 23, 30], [4, 23, 59], [5, 23, 0], [5, 23, 30], [5, 23, 59]]:
		var ts2: int = MON0 + int(spec[0]) * 86400 + int(spec[1]) * 3600 + int(spec[2]) * 60
		print("  wd=%d %02d:%02d  phase=%s  left=%d  can_start=%s"
			% [P2.iso_weekday_utc(ts2), int(spec[1]), int(spec[2]),
				P2.phase_at_utc(ts2), P2.close_left_sec(ts2),
				str(P2.can_start_match_utc(ts2))])

	print("── ⑤ find_opponent 在七天里给的答案 ──")
	var pool := {}
	for i in range(8):
		BE.pool_add(pool, _ghost("p_%d" % i, 12))
	BE.pool_override = pool
	print("  池子形状: %s   12 那格 %d 条"
		% [str(pool.keys()), ((pool.get(BE.POOL_KEY, {}) as Dictionary).get("12", []) as Array).size()])
	for d in range(7):
		P2.now_override_ts = MON0 + d * 86400 + 12 * 3600
		var rng := RandomNumberGenerator.new()
		rng.seed = 424242
		var g: Dictionary = BE.find_opponent(12, [], rng)
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 424242
		var g2: Dictionary = BE.find_opponent(999, [], rng2)
		print("  d=%d phase=%-8s exact=%s(%d场)  空格 999 ⇒ is_bot=%s(%d场)"
			% [d, P2.phase_at_utc(P2.now_utc()),
				str(g.get("ghost_id", "?")), int(g.get("season_total_battles", -1)),
				str(g2.get("is_bot", false)), int(g2.get("season_total_battles", -1))])

	print("── ⑥ gauntlet_pool_find 在七天里给的答案(它自己读真系统时钟) ──")
	var gpool := {}
	for i in range(4):
		BE.pool_add(gpool, {
			"ghost_id": "gl_a%d" % i, "name": "同标签%d" % i, "avatar": "basic",
			"origin": BE.ORIGIN_REMOTE, "gl_w": 3, "gl_l": 1,
			"gl_ts": int(Time.get_unix_time_from_system()) - 60,
		})
	BE.pool_add(gpool, {
		"ghost_id": "gl_other", "name": "别的标签", "avatar": "basic",
		"origin": BE.ORIGIN_REMOTE, "gl_w": 3, "gl_l": 2,
		"gl_ts": int(Time.get_unix_time_from_system()) - 60,
	})
	for d in range(7):
		P2.now_override_ts = MON0 + d * 86400 + 12 * 3600
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = 7
		var picked := {}
		for _i in range(20):
			var g3 = BE.gauntlet_pool_find(gpool, 3, 1, [], rng3)
			picked[str(g3.get("ghost_id", "?")) if g3 != null else "<null>"] = true
		var ks: Array = picked.keys()
		ks.sort()
		print("  d=%d phase=%-8s 20 次抽到 %s" % [d, P2.phase_at_utc(P2.now_utc()), str(ks)])

	BE.pool_override = {}
	P2.now_override_ts = 0
	print("PROBE DONE")
	get_tree().quit(0)
