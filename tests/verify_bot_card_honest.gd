extends Node
## verify_bot_card_honest.gd — 机器人对手的匹配卡不许冒充真人 (2026-10-03 周六实操台账 S14)
## 原现象: 「海域守卫 ID #451562」—— 机器人拿到一个编出来的 6 位玩家号。方案书 R2 要求 UI 说实话。
## ★走真函数: Backend.make_bot → MatchmakingScene._opponent_from_ghost → 卡片同一个三元式取 ID 那行文字。

const MM := preload("res://scripts/scenes/MatchmakingScene.gd")
const BE := preload("res://scripts/net/backend.gd")

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _id_line(prof: Dictionary) -> String:
	return MM.card_id_text(prof)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 机器人匹配卡不冒充真人 ===")
	var mm = MM.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bot: Dictionary = BE.make_bot(20, rng)
	_ok("★分母: make_bot 产出的是机器人", bool(bot.get("is_bot", false)), str(bot.get("ghost_id", "")))
	var pb: Dictionary = mm._opponent_from_ghost(bot)
	var line_b := _id_line(pb)
	_ok("★★机器人卡写明「陪练机器人」, 不印编出来的玩家号", line_b == MM.BOT_TAG and line_b.find("#") < 0, line_b)
	var human := {"is_bot": false, "profile": {"name": "龟主-abc", "id": "#123456"}, "leaders": ["basic"]}
	var ph: Dictionary = mm._opponent_from_ghost(human)
	_ok("★分母: 真人卡照旧印 ID", _id_line(ph) == "ID #123456", _id_line(ph))
	mm.free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 机器人卡说实话" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
