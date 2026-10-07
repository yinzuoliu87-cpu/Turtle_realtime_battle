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


## 一批名字里: [带汉字的个数, 带拉丁字母的个数, 带数字的个数]
func _mix(names: Array) -> Array:
	var r := [0, 0, 0]
	for nm in names:
		var s := str(nm)
		var c := false
		var l := false
		var d := false
		for i in range(s.length()):
			var u := s.unicode_at(i)
			if u >= 0x4E00 and u <= 0x9FFF:
				c = true
			elif (u >= 65 and u <= 90) or (u >= 97 and u <= 122):
				l = true
			elif u >= 48 and u <= 57:
				d = true
		r[0] += 1 if c else 0
		r[1] += 1 if l else 0
		r[2] += 1 if d else 0
	return r


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
	## 真人: 走产品自己的快照生成(带 `profile.tag` = 账号算的玩家 ID)。
	var _gid := BE.player_ghost_id(int(GameState.season_id), ["basic", "stone", "ice"], 20)
	var human: Dictionary = BE.build_ghost_snapshot(_gid, {"name": "石头统领", "avatar": "basic", "id": _gid})
	var ph: Dictionary = mm._opponent_from_ghost(human)
	var line_h := _id_line(ph)
	var fmt_ok := func(s: String) -> bool:
		## ★2026-10-04 起是玩家 ID 的形状(`#` + 6 位字母数字, `_P2.tag_valid`), 不再是 6 位数字。
		return s.begins_with("ID ") and BE._P2.tag_valid(s.substr(3))
	_ok("★★机器人卡的 ID 行与真人同一格式「ID #XXXXXX」(用户 2026-10-04: 不能让玩家知道是机器人)", fmt_ok.call(line_b), line_b)
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
	## ★★2026-10-07 生成器换成真人用户名的长相, 池子不能再穷举 ⇒ 改量「机器人名字与真人默认名**长得一样**」:
	##   同样 300 个, 比字形构成(中文 / 拉丁 / 带数字)的占比 —— 机器人要是走了另一套名字, 占比必然对不上
	##   (旧版「石头统领」那套: 拉丁 0%, 而真人默认名拉丁约一半)。
	var bots: Array = []
	var humans: Array = []
	var brng := RandomNumberGenerator.new()
	brng.seed = 77
	for i in range(300):
		var bb: Dictionary = BE.make_bot(int(brng.randi() % 25), brng)
		bots.append(str((bb.get("profile", {}) as Dictionary).get("name", "")))
		humans.append(str(BE._P2.nickname_fallback("acct-%d-%s" % [i, str(i * 7919).sha256_text().substr(0, 8)])))
	var hb := _mix(bots)
	var hh := _mix(humans)
	print("     机器人 中/拉丁/数字 = %s · 真人默认名 = %s" % [str(hb), str(hh)])
	var bad_b: Array = []
	for nm in bots:
		if not BE._P2.nickname_valid(nm) or BE._P2.nickname_blocked(nm):
			bad_b.append(nm)
	_ok("★★机器人名字每一个都合法、不撞屏蔽词(与真人同一道门)", bad_b.is_empty(), str(bad_b.slice(0, 5)))
	_ok("★分母: 两边各 300 个, 且真人那边中文/拉丁都有(否则占比比较没意义)",
		bots.size() == 300 and humans.size() == 300 and hh[0] > 30 and hh[1] > 30, str(hh))
	var near := true
	for k in range(3):
		if absi(int(hb[k]) - int(hh[k])) > 45:
			near = false
	_ok("★★★机器人名字与真人默认名**长得一样**(中文 / 拉丁 / 带数字 三项占比各差 ≤ 15 个百分点)", near,
		"机器人 %s vs 真人 %s (每 300 个)" % [str(hb), str(hh)])
	var bset := {}
	for nm in bots:
		bset[nm] = true
	_ok("★★300 个机器人里没有大批同名(≥ 240 种)", bset.size() >= 240, "%d 种" % bset.size())
	mm.free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 机器人卡看不出区别" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
