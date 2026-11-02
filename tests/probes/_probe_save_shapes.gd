extends Node
## 探针: **能解析但字段是坏的**存档 —— 老版本档 / 类型不对 / 缺键。
## ★上一条(v0.19.463)修的是「解析不出来」那一类; 这一类是另一半:
##   JSON 合法, 但某个字段的**类型**不是代码假设的那个 ⇒ 后面 `.size()` / `int()` 会炸。
## ★下周测试拿新包覆盖旧档, 这条正好在路上。
const CASES := [
	["空字典", "{}"],
	["只有版本号", '{"onboarded": true}'],
	["数组字段给成字符串", '{"season_leaders": "basic", "left_team": "x"}'],
	["数字字段给成字符串", '{"season_total_battles": "十七", "hearts": "满"}'],
	["字典字段给成数组", '{"egg_hp": [1,2,3], "finals_match": [1]}'],
	["null 遍地", '{"season_leaders": null, "nickname": null, "hearts": null}'],
	["数字给成浮点", '{"season_total_battles": 17.9, "hearts": 2.5}'],
	["嵌套类型错", '{"match_history": {"a": 1}, "titles": 5}'],
]


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		get_tree().quit(1); return
	gs.test_mode = true
	print("=== 能解析但字段坏掉的存档: 读得进去吗 ===")
	for c in CASES:
		var name: String = str(c[0])
		var j := JSON.new()
		var okp: bool = j.parse(str(c[1])) == OK
		if not okp:
			print("  %-18s ⚠ 我自己这条用例的 JSON 就不合法" % name)
			continue
		## 不捕异常 —— GDScript 没有 try; 崩了就是整个进程没了, 那本身就是答案
		gs._apply_save_dict(j.data as Dictionary)
		print("  %-18s ✅ 没崩  场次=%s 命=%s 统领数=%s" % [
			name, str(gs.season_total_battles), str(gs.hearts),
			str((gs.season_leaders as Array).size()) if gs.season_leaders is Array else "非数组!"])
	print("")
	print("  ⇒ 全部走完 = 读档对坏字段是容忍的; 中途没打印 = 那一条把进程带走了")
	get_tree().quit(0)
