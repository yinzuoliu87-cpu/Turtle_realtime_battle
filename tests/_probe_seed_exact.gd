extends Node
## _probe_seed_exact.gd — 只读侦察: 两件事
##   ① `match_src_counts["exact"]`(= 用来回答「精确同场次命中率」那条未决点的数)
##      把内置 396 条 `seed_` 陪练也算成"同场次真人"。排行榜已经按 `seed_` 前缀
##      把陪练筛掉了(「陪练不上榜」), 匹配记账这一侧没有同样的维度。
##   ② `_status_row()` 调 `_gauntlet_status_line()` **不传时刻** —— 而同一文件里
##      `_battle_block_msg` / `_open_shop` 都走 `_now_ts()`(可注入)。
##      ⇒ 主菜单那一行的真实渲染只有**真的到了周六**才会被执行到。

const _BE := preload("res://scripts/net/backend.gd")
const _MENU := preload("res://scripts/scenes/MainMenuScene.gd")
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")

	print("=== ① 匹配来源记账 vs 陪练 ===")
	var pool: Dictionary = _BE.load_pool()
	var buckets: Dictionary = pool.get(_BE.POOL_KEY, {})
	var n_all := 0
	var n_seed := 0
	for b in buckets.keys():
		for g in buckets[b]:
			n_all += 1
			if str((g as Dictionary).get("ghost_id", "")).begins_with("seed_"):
				n_seed += 1
	print("  池子里快照 %d 条, 其中 seed_ 陪练 %d 条 (%.0f%%)  ← 分母" % [
		n_all, n_seed, 100.0 * float(n_seed) / float(maxi(1, n_all))])

	_BE.match_src_counts = {"exact": 0, "bot": 0, "gauntlet_label": 0, "gauntlet_bot": 0}
	var rng := RandomNumberGenerator.new(); rng.seed = 777
	var got_seed := 0
	var got_real := 0
	var N := 40
	for i in range(N):
		var g: Dictionary = _BE.find_opponent(i % 10, [], rng)
		var gid := str(g.get("ghost_id", ""))
		if gid.begins_with("seed_"):
			got_seed += 1
		elif gid != "":
			got_real += 1
	print("  %d 次抽对手: seed_ 陪练 %d / 非陪练快照 %d" % [N, got_seed, got_real])
	print("  match_src_counts = %s" % str(_BE.match_src_counts))
	print("  ⇒ exact=%d 里有 %d 次其实是陪练(排行榜那一侧会把它们筛掉)" % [
		int(_BE.match_src_counts.get("exact", 0)), got_seed])
	print("  排行榜的同维度筛子存在吗: leaderboard 里 seed_ 判据 = %s"
		% str(_BE.leaderboard(pool, "我", 0, 8, 0, 1 << 30).size() == 1))

	print("=== ② _status_row 有没有走可注入时钟 ===")
	var m = _MENU.new()
	var anchor: int = _P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	var sat: int = anchor + 5 * 86400 + 12 * 3600
	var sun: int = anchor + 6 * 86400 + 12 * 3600
	gs.promoted = true
	gs.gauntlet_wins = 2
	gs.gauntlet_losses = 1
	print("  今天(真实钟) iso_weekday = %d" % int(_P2C.iso_weekday_utc(int(Time.get_unix_time_from_system()))))
	print("  _gauntlet_status_line()      不传 = 「%s」  ← _status_row 用的就是这个"
		% str(m._gauntlet_status_line()))
	print("  _gauntlet_status_line(周六)  传   = 「%s」" % str(m._gauntlet_status_line(sat)))
	print("  _gauntlet_status_line(周日)  传   = 「%s」  ← 空 ⇒ 周日回落到积分赛那一行"
		% str(m._gauntlet_status_line(sun)))
	m.clock_override_ts = sat
	print("  设了 clock_override_ts=周六 之后, 不传参的那个调用 = 「%s」"
		% str(m._gauntlet_status_line()))
	print("  ⇒ 注入口对 _status_row 这条路无效(clock_override_ts 只被 _battle_block_msg/_open_shop 用)")
	print("=== ③ 周日那一行会显示什么(积分赛配额+命, 周日两者都不动) ===")
	gs.ranked_used = 7
	gs.hearts = 3
	print("  uses_ranked_quota(周日)=%s  (周日打的场不吃这 %d 场配额)" % [
		str(_P2C.phase_uses_ranked_quota(_P2C.PHASE_FINALS)), int(_P2C.RANKED_QUOTA)])
	print("  周日状态行 = 「第 %d 大轮 · Lv %d   ♥ %d/8   本周 %d/%d」 ← 两个数周日都冻着" % [
		int(gs.season_id), int(gs.season_level), int(gs.hearts),
		int(gs.ranked_used), int(_P2C.RANKED_QUOTA)])
	m.free()
	print("PROBE5 DONE")
	get_tree().quit(0)
