extends Node
## _probe_block_msgs.gd — 只读侦察: 把「点开打被拦住」的**全部**原文穷举出来,
## 逐条看它有没有告诉玩家【下一步在哪】。
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const _MENU := preload("res://scripts/scenes/MainMenuScene.gd")
func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	var m = _MENU.new()
	var anchor: int = _P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	var thu: int = anchor + 3 * 86400 + 12 * 3600
	var sat: int = anchor + 5 * 86400 + 12 * 3600
	var sun: int = anchor + 6 * 86400 + 12 * 3600
	var cases := [
		["周四·0命·未晋级",     thu, 0, 24, false, 0, 0],
		["周四·0命·已晋级",     thu, 0, 24, true,  0, 0],
		["周四·满命·配额满·未晋级", thu, 8, 24, false, 0, 0],
		["周四·满命·配额满·已晋级", thu, 8, 24, true,  0, 0],
		["周六·没资格",         sat, 8, 0,  false, 0, 0],
		["周六·已晋级·0-0",     sat, 8, 0,  true,  0, 0],
		["周六·4胜(进决赛日)",   sat, 8, 0,  true,  4, 1],
		["周六·3负(出局)",      sat, 8, 0,  true,  1, 3],
		["周六·配额6场打满",     sat, 8, 0,  true,  3, 3],
		["周日·没资格",         sun, 8, 0,  false, 0, 0],
		["周日·有资格没打进",    sun, 8, 0,  true,  2, 3],
		["周日·4胜进了决赛日",   sun, 8, 0,  true,  4, 0],
	]
	for c in cases:
		gs.hearts = int(c[2]); gs.ranked_used = int(c[3]); gs.promoted = bool(c[4])
		gs.gauntlet_wins = int(c[5]); gs.gauntlet_losses = int(c[6])
		var s: String = str(m._battle_block_msg(int(c[1])))
		var nxt := "有下一步"
		if s == "":
			nxt = "(放行)"
		elif s.find("下周一") < 0 and s.find("周六") < 0 and s.find("决赛日 →") < 0 \
				and s.find("看对阵图") < 0:
			nxt = "★★没说下一步"
		print("  %-24s → 「%s」   [%s]" % [str(c[0]), s, nxt])
	m.free()
	print("PROBE6 DONE")
	get_tree().quit(0)
