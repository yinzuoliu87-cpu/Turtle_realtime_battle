extends Node
## verify_bot_card_honest.gd — 机器人对手的匹配卡与真人卡看不出区别 (用户 2026-10-04:「不能让玩家知道是机器人」)
## ⚠ 曾按方案书 R2 改成写「陪练机器人」(v0.19.518), 用户 2026-10-04 推翻, 以用户为准。
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
	print("=== 机器人匹配卡与真人卡看不出区别 ===")
	var mm = MM.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bot: Dictionary = BE.make_bot(20, rng)
	_ok("★分母: make_bot 产出的是机器人", bool(bot.get("is_bot", false)), str(bot.get("ghost_id", "")))
	var pb: Dictionary = mm._opponent_from_ghost(bot)
	var line_b := _id_line(pb)
	var human := {"is_bot": false, "profile": {"name": "龟主-abc", "id": "#123456"}, "leaders": ["basic"]}
	var ph: Dictionary = mm._opponent_from_ghost(human)
	var line_h := _id_line(ph)
	var fmt_ok := func(s: String) -> bool:
		return s.begins_with("ID #") and s.length() == len("ID #123456") and s.substr(4).is_valid_int()
	_ok("★★机器人卡的 ID 行与真人同一格式「ID #6位数」(用户 2026-10-04: 不能让玩家知道是机器人)", fmt_ok.call(line_b), line_b)
	_ok("★分母: 真人卡也是这个格式", fmt_ok.call(line_h), line_h)
	var bad := []
	for w in ["机器人", "陪练", "BOT", "bot", "Bot", "AI"]:
		if line_b.find(w) >= 0 or str(pb.get("name", "")).find(w) >= 0:
			bad.append(w)
	_ok("★★机器人卡的名字和 ID 里没有任何「机器人/陪练/BOT」字样", bad.is_empty(), str(bad) + " ← " + str(pb))
	_ok("★卡片字典里没有能被界面读出的 bot 标记", not pb.has("bot"), str(pb.keys()))
	## 两个机器人不许同名同号(原来全体「海域守卫」+ 同一个 #451562)
	var bot2: Dictionary = BE.make_bot(20, rng)
	var pb2: Dictionary = mm._opponent_from_ghost(bot2)
	_ok("★★两个机器人名字不同、号码不同(原 bug: 全体同名同号)", str(pb.get("name")) != str(pb2.get("name")) and str(pb.get("id")) != str(pb2.get("id")), "%s %s / %s %s" % [pb.get("name"), pb.get("id"), pb2.get("name"), pb2.get("id")])
	## 用户 2026-10-04:「龟主-32c6c这是真人会用的名字？」—— 兜底名一看就是没起名的号, 机器人不许用它
	## ★2026-10-04 起兜底名本身也换成了生成器里的名字 ⇒ 不能再从 nickname_fallback 现切前缀
	##   (切出来的是「石头统领-」这种永远匹配不上的串 = 恒真)。旧格式写死在这里。
	var fb_head: String = "龟主-"
	_ok("★★机器人不用「龟主-xxxxx」兜底名", str(pb.get("name")).find(fb_head) < 0 and str(pb2.get("name")).find(fb_head) < 0, "%s / %s" % [pb.get("name"), pb2.get("name")])
	var pool := {}
	for i in range(BE._P2.nickname_stems().size()):
		for j in range(BE._P2.NICK_HEADS.size()):
			pool[BE._P2.nickname_suggest_at(i, j)] = true
	_ok("★★机器人名字出自真人注册时的预填名生成器", pool.has(str(pb.get("name"))) and pool.has(str(pb2.get("name"))), "%s / %s (池 %d 个)" % [pb.get("name"), pb2.get("name"), pool.size()])
	mm.free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 机器人卡看不出区别" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
