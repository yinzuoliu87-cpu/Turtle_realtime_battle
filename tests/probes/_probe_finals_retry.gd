extends Node
## _probe_finals_retry.gd — 只读侦察: 决赛日那一场「无 token ⇒ 静默不报」到底还漏在哪。
##
## 上游情报(另一个 agent 穷举 supabase.gd 12 条「请求没发出去」的分支):
##   `report_finals_async` 四条早退(含 `_token == ""`), 什么都不标、屏幕无话
##   ⇒ 「那一刻的结果永不上报且无重试」。
## 而 `_token` 只活在内存、从不落盘 ⇒ **每次冷启动都是空的**。
##
## 本探针不写任何判据, 只把**真实数值**打出来, 逐条回答:
##   ① 冷启动时 token 真是空的吗
##   ② 无 token 那一刻, `report_finals_if_any()` **有没有**写补报单(情报猜"只在失败那条路上写")
##   ③ 补报单进不进存档(能不能过夜)
##   ④ 补报时用的 seed / week 是从**补报单**取的, 还是又去读了一遍 GameState

const _BE := preload("res://scripts/net/backend.gd")
const _SB := preload("res://scripts/net/supabase.gd")


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true

	print("=== ① 冷启动时的 token ===")
	print("  _SB._token = 「%s」(长度 %d)   ← 只活在内存, 从不落盘"
		% [str(_SB._token), str(_SB._token).length()])
	print("  _SB.enabled() = %s   account_id = 「%s」" % [str(_SB.enabled()), str(gs.account_id)])

	print("=== ② 无 token 那一刻, 真入口 report_finals_if_any() 写不写补报单 ===")
	gs.week_anchor_ts = 1700000000
	gs.battle_seed = 4242
	gs.finals_report_pending = {}
	gs.finals_match = {"bucket": 2, "round": 3, "match": 1, "side": 0}
	_SB.finals_report_clear()
	_BE.report_finals_if_any(true)
	print("  finals_report_pending = %s" % str(gs.finals_report_pending))
	print("  finals_match(报完必清)  = %s" % str(gs.finals_match))
	print("  _SB.finals_reported(3,1) = %s   ← false = 一个字节都没发出去"
		% str(_SB.finals_reported(3, 1)))

	print("=== ③ 补报单进存档吗(能不能过夜) ===")
	var d: Dictionary = gs._save_dict()
	print("  _save_dict() 里有 finals_report_pending 吗 = %s" % str(d.has("finals_report_pending")))
	print("  它的值 = %s" % str(d.get("finals_report_pending", "(缺)")))
	print("  ⇒ `_settle_season` 尾部有一条无条件的 gs.save() ⇒ 单子过得了夜")

	print("=== ④ 补报时的 seed / week 从哪取 ===")
	print("  单子里存着 seed = %d" % int((gs.finals_report_pending as Dictionary).get("seed", -1)))
	## 把 GameState 上那个字段改成另一个值 —— 补报单里那份**没变**。
	## 如果补报读的是 GameState 而不是单子, 这两个数一分岔就报错了一个。
	gs.battle_seed = 999
	print("  现在 GameState.battle_seed = %d(换了一场对局就会是这样)" % int(gs.battle_seed))
	print("  全仓 grep `get(\"seed\"` 的读者里, **没有一个**读的是 finals_report_pending")
	print("  ⇒ retry_finals_report() → report_finals_result() 里那行 `int(GameState.battle_seed)`")
	print("     就是那个读者 —— 单子上的 seed **一个人都没读**")

	print("=== ⑤ 补报入口自己的行为 ===")
	_BE.retry_finals_report()
	print("  没报成 ⇒ 单子还在吗 = %s(该是 true: 下次开主菜单再补一次)"
		% str(not (gs.finals_report_pending as Dictionary).is_empty()))
	gs.finals_report_pending = {"bucket": 2, "round": 3, "match": 1, "side": -1, "seed": 7}
	_BE.retry_finals_report()
	print("  side = -1 的单子(report_finals_async 对它无条件早退)⇒ 单子还在吗 = %s"
		% str(not (gs.finals_report_pending as Dictionary).is_empty()))
	print("     ↑ true = 每次开主菜单都往那儿捶一下, 而且永远捶不成")
	print("PROBE_FINALS_RETRY DONE")
	get_tree().quit(0)
