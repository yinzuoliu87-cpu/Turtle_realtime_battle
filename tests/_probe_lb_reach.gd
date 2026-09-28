extends Node
## _probe_lb_reach.gd — 只读侦察: 排行榜这一侧【拿不拿得到「问没问到」这个事实】。
##
## 起因: 屏上那句「榜上暂时只有你 —— 打完一场, 对手就会上来」在**离线**时是假话:
##   `pool_add` 的全部调用点里, 只有 `apply_pull_response` / `ingest_remote` 会带来别人,
##   而那两条是纯网络。断网时打一万场也不会有对手上来。
##
## 要修成「问不到 / 问到了榜上就你一个」两句话, 先得查实: 本屏够不到哪个事实。
## 本探针把所有**已有的公开取数口**逐个打出来, 不写任何判据。

const _BE := preload("res://scripts/net/backend.gd")
const _SB := preload("res://scripts/net/supabase.gd")
const _RP := preload("res://scripts/net/remote_pool.gd")


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	print("=== 池子与榜 ===")
	var pool: Dictionary = _BE.load_pool()
	var buckets: Dictionary = pool.get(_BE.POOL_KEY, {})
	var n_all := 0
	var n_seed := 0
	for b in buckets.keys():
		for g in buckets[b]:
			n_all += 1
			if str((g as Dictionary).get("ghost_id", "")).begins_with("seed_"):
				n_seed += 1
	var rows: Array = _BE.leaderboard(pool, "我", 0, 8, 0, 1 << 30)
	print("  池子 %d 条 (seed_ %d) ⇒ 榜上 rows = %d" % [n_all, n_seed, rows.size()])

	print("=== Supabase 层公开取数口(本屏 preload 就能读) ===")
	print("  enabled()          = %s   ← 配了 url+key 吗" % str(_SB.enabled()))
	print("  base_url()         = 「%s」" % str(_SB.base_url()))
	print("  pull_try_count()   = %d   ← 本进程【问过】几次对手" % int(_SB.pull_try_count()))
	print("  pull_ok_count()    = %d   ← 其中【问到了】几次" % int(_SB.pull_ok_count()))
	print("  last_pull_stats()  = %s" % str(_SB.last_pull_stats()))
	print("  service_state()    = %s   ← /service_status 那条独立的健康检查" % str(_SB.service_state()))
	print("  ask_count()        = %d" % int(_SB.ask_count()))
	print("=== 旧后端层(backend_url) ===")
	print("  RemotePool.enabled() = %s  ok_count=%d fail_count=%d"
		% [str(_RP.enabled()), int(_RP.ok_count), int(_RP.fail_count)])

	print("=== 喂一次【失败】回包 ⇒ 这两个数跟着动吗 ===")
	_SB.apply_pull_response(false, 0, "")
	print("  失败一次后: try=%d ok=%d" % [int(_SB.pull_try_count()), int(_SB.pull_ok_count())])
	print("=== 喂一次【成功但空数组】回包 ===")
	_SB.apply_pull_response(true, 200, "[]")
	print("  成功一次后: try=%d ok=%d" % [int(_SB.pull_try_count()), int(_SB.pull_ok_count())])

	print("PROBE_LB_REACH DONE")
	get_tree().quit(0)
