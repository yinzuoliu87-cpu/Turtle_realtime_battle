extends Node
## 探针: **一个全新玩家**在一周七天里, 每天打不打得开对局? 被挡时屏幕说的话有用吗?
##
## ★为什么问这个: 下周 10 人测试要走一整周, 而本仓「判据挂在星期几上」已经栽过五次。
## ★判据只有 `_battle_block_msg(now)` 一处, 而主菜单有可注入时钟 `clock_override_ts`
##   ⇒ 七天可以逐个问, 不用等一周。
const MM := preload("res://scripts/scenes/MainMenuScene.gd")

## 2026-09-20 周日 00:00 UTC(与 verify_bracket_map 的 SUN_AM 同一个锚)
const SUN0 := 1789862400
const DAYNAME := ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		## 全新玩家: 0 场、0 胜、满命、没绑邮箱之外的一切都按初始
		gs.season_total_battles = 0
		gs.season_wins = 0
		gs.ranked_used = 0
		gs.account_email = "t@x.co"     ## 已绑(否则被墙挡在前面, 那一步已有门禁)
	await get_tree().process_frame
	var mm = MM.new()
	add_child(mm)
	for _i in range(8):
		await get_tree().process_frame
	print("=== 全新玩家 × 一周七天 × 三个时刻 ===")
	for d in range(7):
		var line := "%s  " % DAYNAME[d]
		for h in [3, 12, 21]:
			mm.clock_override_ts = SUN0 + d * 86400 + h * 3600
			var msg: String = str(mm._battle_block_msg(mm._now_ts()))
			line += "%02d:00 → %s   " % [h, ("【可打】" if msg == "" else msg.substr(0, 26))]
		print("  " + line)
	## ── 追问: 配额打满的人, 一周七天还能不能打 ──
	print("")
	print("=== 配额打满(ranked_used = 全额) × 一周七天 ===")
	if gs != null:
		gs.ranked_used = 999
		gs.season_total_battles = 24
		gs.season_wins = 3
	for d2 in range(7):
		var l2 := "%s  " % DAYNAME[d2]
		mm.clock_override_ts = SUN0 + d2 * 86400 + 12 * 3600
		var ph: String = str(mm._P2C.phase_at_utc(mm._now_ts()))
		var uses: bool = bool(mm._P2C.phase_uses_ranked_quota(ph))
		var m2: String = str(mm._battle_block_msg(mm._now_ts()))
		l2 += "phase=%-9s 吃配额=%-5s → %s" % [ph, str(uses), ("【可打】" if m2 == "" else m2.substr(0, 24))]
		print("  " + l2)
	## ── 0 命(大轮淘汰)的人, 周六周日能不能打? ──
	## ★U9(2026-09-16)用户原话:「0 命的话就只能等到周 6 周日观赛了, 不再打表演赛」
	## ★而 `_battle_block_msg` 把**周六那支排在 `is_eliminated()` 之前** ⇒ 顺序决定答案。
	print("")
	print("=== 0 命 + 已晋级 × 七天 ===")
	if gs != null:
		gs.hearts = 0
		gs.promoted = true
		gs.ranked_used = 0
		gs.gauntlet_wins = 1
		gs.gauntlet_losses = 1
	for d3 in range(7):
		mm.clock_override_ts = SUN0 + d3 * 86400 + 12 * 3600
		var m3: String = str(mm._battle_block_msg(mm._now_ts()))
		print("  %s  %s" % [DAYNAME[d3], ("【可打】★ 0命还能打" if m3 == "" else m3.substr(0, 30))])
	get_tree().quit(0)
