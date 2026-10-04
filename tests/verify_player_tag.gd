extends Node
## verify_player_tag.gd — 玩家 ID(`#XXXXXX`): 名字可以重, ID 分得开 (用户 2026-10-04「行啊，做做看，别搞出ai味的就行」)
##
## 守六件事, 都走产品自己的函数, 不手抄算法:
##   ① 同一个账号 ⇒ 同一个 ID(换设备 / 重装 = 换安装号, ID 不变); 访客拿到账号后换成账号算的那个
##   ② 不同账号散得开: 1 万个随机账号量撞号数 + 每一位的字母分布
##   ③ 真人 / 机器人 / 陪练同一种长相, 而且机器人的号与它快照里看得见的任何东西都推不出关系
##   ④ 对手卡片 / 自己那张卡片显示的就是这串
##   ⑤ 设置页看得见自己的 ID(真入口实例化 Settings.tscn)
##   ⑥ 名字不当键: 两个同名的人在排行榜上是两行, 而且只有重名的那几行带号; 对阵图同理

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const BE := preload("res://scripts/net/backend.gd")
const SB := preload("res://scripts/net/supabase.gd")
const MM := preload("res://scripts/scenes/MatchmakingScene.gd")
const SETTINGS := preload("res://scenes/Settings.tscn")
const SETTINGS_SCRIPT := preload("res://scripts/scenes/SettingsScene.gd")

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 一个 uuid 形状的随机账号号(Supabase auth.users.id 的长相)。
func _rand_uuid(c: Crypto) -> String:
	var h := c.generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


func _ready() -> void:
	await get_tree().process_frame
	print("=== 玩家 ID: 名字可以重, ID 分得开 ===")
	OS.set_environment(SB.ENV_URL, " ")
	GameState.test_mode = true
	var acct0 := str(GameState.account_id)
	var uid0 := str(GameState.install_uid)
	var mail0 := str(GameState.account_email)

	## ── ① 同一个账号 ⇒ 同一个 ID ──
	var A := "7f3a9c12-5b6e-4d1a-9e2f-0c8b7a6d5e4f"
	GameState.account_id = A
	GameState.install_uid = "aaaaaaaaaaaa"
	var t_dev1 := BE.my_tag()
	GameState.install_uid = "bbbbbbbbbbbb"          # 换手机 / 重装 = 新安装号, 账号用邮箱取回
	var t_dev2 := BE.my_tag()
	_ok("★分母: 算出来的是合法 ID 形状", P2.tag_valid(t_dev1), t_dev1)
	_ok("★★同一个账号换设备(安装号变了) ⇒ ID 不变", t_dev1 == t_dev2, "%s / %s" % [t_dev1, t_dev2])
	_ok("★同一个输入算两遍一样(确定性)", P2.player_tag(A) == P2.player_tag(A) and P2.player_tag(A) == t_dev1)
	## 访客: 还没账号时用安装号; 拿到账号后换成账号算的那个(对阵图是拿 account_id 现算的, 必须对得上)
	GameState.account_id = ""
	GameState.install_uid = "cccccccccccc"
	var t_guest := BE.my_tag()
	_ok("访客(没账号)也有 ID, 由安装号算", P2.tag_valid(t_guest) and t_guest == P2.player_tag("cccccccccccc"), t_guest)
	GameState.account_id = A
	_ok("★访客拿到账号后 ID 换成账号算的那个(= 别人在对阵图上看到的)", BE.my_tag() == t_dev1 and t_guest != t_dev1,
		"%s → %s" % [t_guest, BE.my_tag()])
	## 对阵图那一侧: 回包里的 account_id 在**别人的机器上**现算 ⇒ 必须等于我自己设置页上那串
	var body := JSON.stringify({"ok": true, "n": 2, "round": 1, "entrants": [
		{"seed": 0, "name": "石头统领", "account_id": A},
		{"seed": 1, "name": "石头统领", "account_id": "11111111-2222-3333-4444-555555555555"}], "done": {}})
	var fv: Dictionary = SB.parse_finals(true, 200, body, "", 0)
	var ftags: Array = fv.get("tags", [])
	_ok("★★对阵图回包里算出来的号 = 那个人自己设置页上的号(两台机器同一个算法)",
		ftags.size() == 2 and str(ftags[0]) == t_dev1, str(ftags))
	_ok("★对阵图: 同名的两个人号不同", ftags.size() == 2 and str(ftags[0]) != str(ftags[1]), str(ftags))

	## ── ② 1 万个随机账号: 撞号数 + 分布 ──
	var c := Crypto.new()
	var seen := {}
	var coll := 0
	var N := 10000
	var L := P2.TAG_LEN
	var K := P2.TAG_ALPHABET.length()
	var cnt := []                    # cnt[位][字母下标]
	for i in range(L):
		var row := []
		row.resize(K)
		row.fill(0)
		cnt.append(row)
	var bad_fmt := 0
	for i in range(N):
		var t := P2.player_tag(_rand_uuid(c))
		if not P2.tag_valid(t):
			bad_fmt += 1
			continue
		if seen.has(t):
			coll += 1
		seen[t] = true
		for p in range(L):
			cnt[p][P2.TAG_ALPHABET.find(t[p + 1])] += 1
	var expect_pairs := float(N) * float(N - 1) / 2.0 / pow(float(K), float(L))
	print("    1 万个账号: 撞号 %d 次(生日碰撞期望 %.3f 对; 纯 6 位数字时期望 %.1f 对)" % [
		coll, expect_pairs, float(N) * float(N - 1) / 2.0 / 1e6])
	_ok("★分母: 1 万个都是合法形状", bad_fmt == 0, "%d 个不合法" % bad_fmt)
	_ok("★★1 万个随机账号撞号 ≤ 2 次(期望 0.10)", coll <= 2, "%d 次" % coll)
	var lo := 1 << 30
	var hi := 0
	for p in range(L):
		for k in range(K):
			lo = mini(lo, int(cnt[p][k]))
			hi = maxi(hi, int(cnt[p][k]))
	var exp_cell := float(N) / float(K)
	print("    每一位每个字母: 最少 %d / 最多 %d (期望 %.0f)" % [lo, hi, exp_cell])
	_ok("★★散得开: 6 位 × 28 个字母每一格都在期望的 ±25% 以内(没有偏到某几个号段)",
		float(lo) >= exp_cell * 0.75 and float(hi) <= exp_cell * 1.25, "%d~%d" % [lo, hi])
	## 字母表本身: 不含容易认错的 0 O 1 I L(小字号里分不清)
	var amb := []
	for ch in ["0", "O", "1", "I", "L", "A", "E", "U"]:
		if P2.TAG_ALPHABET.find(ch) >= 0:
			amb.append(ch)
	_ok("字母表里没有 0/O/1/I/L(认错) 也没有元音(拼出单词)", amb.is_empty() and K == 28, str(amb))

	## ── ③ 真人 / 机器人 / 陪练同一种长相, 且推不出关系 ──
	GameState.account_id = A
	GameState.install_uid = "dddddddddddd"
	var leaders: Array = []
	for p in DataRegistry.launch_pets:
		leaders.append(str((p as Dictionary)["id"]))
		if leaders.size() >= 3:
			break
	GameState.season_leaders = leaders
	var gid := BE.player_ghost_id(int(GameState.season_id), leaders, 5)
	var human: Dictionary = BE.build_ghost_snapshot(gid, {"name": "石头统领", "avatar": leaders[0], "id": gid})
	var h_tag := str((human.get("profile", {}) as Dictionary).get("tag", ""))
	_ok("★★真人快照带 profile.tag, 就是我设置页上那串", h_tag == BE.my_tag() and P2.tag_valid(h_tag), h_tag)
	var bad_bot := []
	var rel_bot := 0
	var bot_tags := {}
	for k in range(300):
		var r := RandomNumberGenerator.new()
		r.seed = 500 + k
		var b: Dictionary = BE.make_bot(k % 25, r)
		var pr: Dictionary = b.get("profile", {})
		var bt := str(pr.get("tag", ""))
		if not P2.tag_valid(bt):
			bad_bot.append(bt)
		bot_tags[bt] = true
		## 「号 = f(快照里看得见的 uid)」就是机器人独有的特征(真人的号由账号算) —— 不许有。
		var owner := BE.owner_tag_of_id(str(pr.get("id", "")))
		if owner != "" and P2.player_tag(owner.split("_")[1]) == bt:
			rel_bot += 1
	_ok("★★300 个机器人的 profile.tag 全是同一种形状", bad_bot.is_empty(), str(bad_bot.slice(0, 5)))
	_ok("★两两不同(不再是全体同号)", bot_tags.size() >= 299, "%d 种" % bot_tags.size())
	_ok("★★机器人的号与快照里的 uid 没有可验证的关系(真人的号由账号算, 两者本来就无关)", rel_bot == 0, "%d 个" % rel_bot)
	_ok("★真人的号同样与 uid 无关(对照组: 证明上一条量的是真人也满足的性质)",
		P2.player_tag(BE.owner_tag_of_id(gid).split("_")[1]) != h_tag)
	## 陪练: 同一个人各场次同一个号
	var raw = JSON.parse_string(FileAccess.get_file_as_string(BE.SEED_PATH))
	var by_person := {}
	var seed_n := 0
	var bad_seed := []
	var rel_seed := 0
	if raw is Dictionary and (raw as Dictionary).get(BE.POOL_KEY) is Dictionary:
		for bk in (raw[BE.POOL_KEY] as Dictionary).keys():
			for g in (raw[BE.POOL_KEY][bk] as Array):
				var s: Dictionary = BE.seed_as_human(g as Dictionary, int(GameState.season_id))
				seed_n += 1
				var pr2: Dictionary = s.get("profile", {})
				var st := str(pr2.get("tag", ""))
				if not P2.tag_valid(st):
					bad_seed.append(st)
				var ow := BE.owner_tag_of_id(str(pr2.get("id", "")))
				if ow != "" and P2.player_tag(ow.split("_")[1]) == st:
					rel_seed += 1
				var person := BE.seed_person_of(str(s.get("ghost_id", "")))
				if not by_person.has(person):
					by_person[person] = {}
				(by_person[person] as Dictionary)[st] = true
	var multi := 0
	var drift := 0
	for person in by_person.keys():
		if (by_person[person] as Dictionary).size() > 1:
			drift += 1
	for person in by_person.keys():
		multi += 1
	_ok("★分母: 陪练 ≥ 300 支, 人 ≥ 20 个", seed_n >= 300 and multi >= 20, "%d 支 / %d 人" % [seed_n, multi])
	_ok("★★陪练的 profile.tag 全是同一种形状", bad_seed.is_empty(), str(bad_seed.slice(0, 5)))
	_ok("★★同一个陪练各场次同一个号", drift == 0, "%d 人的号变了" % drift)
	_ok("★陪练的号与快照里的 uid 也没有可验证的关系", rel_seed == 0, "%d 支" % rel_seed)

	## ── ④ 对手卡片 / 自己那张卡片 ──
	var mm = MM.new()
	var r2 := RandomNumberGenerator.new()
	r2.seed = 11
	var bot: Dictionary = BE.make_bot(7, r2)
	var pb: Dictionary = mm._opponent_from_ghost(bot)
	_ok("★★机器人卡片上的 ID = 它快照里的 tag", str(pb.get("id")) == str(bot["profile"]["tag"]), str(pb.get("id")))
	var ph: Dictionary = mm._opponent_from_ghost(human)
	_ok("★★真人卡片上的 ID = 那个人自己的 ID", str(ph.get("id")) == h_tag, str(ph.get("id")))
	_ok("★卡片那一行是「ID #XXXXXX」", MM.card_id_text(ph) == "ID " + h_tag, MM.card_id_text(ph))
	## 老快照(2026-10-04 之前上传的, 没有 tag): 同一种形状, 同一个人各场次同一个号
	var old1 := human.duplicate(true)
	(old1["profile"] as Dictionary).erase("tag")
	var gid2 := BE.player_ghost_id(int(GameState.season_id), leaders, 6)
	var old2 := old1.duplicate(true)
	old2["profile"]["id"] = gid2
	var o1 := str(mm._opponent_from_ghost(old1).get("id"))
	var o2 := str(mm._opponent_from_ghost(old2).get("id"))
	_ok("★老快照(没有 tag)也显示同一种形状, 同一个人两场同一个号", P2.tag_valid(o1) and o1 == o2, "%s / %s" % [o1, o2])
	var weird := str(mm._opponent_from_ghost({"profile": {"name": "x", "id": "autoplay-b2_COH7"}, "leaders": ["basic"]}).get("id"))
	var empty := str(mm._opponent_from_ghost({"profile": {"name": "x"}, "leaders": ["basic"]}).get("id"))
	_ok("★内部串 / 空 id 也折成同一种形状(卡片上不许出现第二种长相)", P2.tag_valid(weird) and P2.tag_valid(empty),
		"%s / %s" % [weird, empty])
	var me: Dictionary = mm._player_profile()
	_ok("★★「我」那张卡片上的 ID = 我自己的 ID(原来是同赛季所有人同一个号)", str(me.get("id")) == BE.my_tag(), str(me.get("id")))
	mm.free()

	## ── ⑤ 设置页看得见自己的 ID ──
	GameState.account_id = A
	GameState.account_email = "someone@example.com"
	var st_inst = SETTINGS.instantiate()
	st_inst.acct_override = 1
	add_child(st_inst)
	for _i in range(30):
		await get_tree().process_frame
	var idl = st_inst.find_child(SETTINGS_SCRIPT.ACCT_ROW_PREFIX + "Id", true, false)
	var idtxt := str(idl.text) if idl is Label else "<没有这一行>"
	_ok("★★设置页账号那一块有「ID #XXXXXX」, 就是我的 ID", idtxt == "ID " + BE.my_tag(), idtxt)
	_ok("★那一行字比账号标题小(不抢眼)", idl is Label and (idl as Label).get_theme_font_size("font_size") < 15,
		str((idl as Label).get_theme_font_size("font_size")) if idl is Label else "")
	st_inst.queue_free()
	await get_tree().process_frame

	## ── ⑥ 名字不当键: 排行榜同名两人是两行, 只有重名的行带号 ──
	var lb_pool := {BE.POOL_KEY: {"5": [
		_gp("111111111111", "石头统领", 4, "#2345BC"),
		_gp("222222222222", "石头统领", 3, "#6789CD"),
		_gp("333333333333", "彩虹大师", 2, "#BCDFGH")]}}
	var rows: Array = BE.leaderboard(lb_pool, "海盗龟王", 1, 3, 0, 1 << 30)
	var stone := 0
	for rw in rows:
		if str((rw as Dictionary).get("name")) == "石头统领":
			stone += 1
	_ok("★★两个同名的人在榜上是两行(名字不当键)", stone == 2, "%d 行" % stone)
	## 认不出「谁」的畸形快照(没有 g_<uid>_ 段, profile.id 就是 ghost_id): 原来落到【昵称】那一级 ⇒ 同名两人合成一行。
	var w1 := {"ghost_id": "weird_1", "profile": {"name": "石头统领", "id": "weird_1", "tag": "#2345BC"}}
	var w2 := {"ghost_id": "weird_2", "profile": {"name": "石头统领", "id": "weird_2", "tag": "#6789CD"}}
	_ok("★★认不出人的畸形快照: 同名两人的 person_key 也不同(昵称不当键)",
		BE.person_key(w1) != BE.person_key(w2), "%s / %s" % [BE.person_key(w1), BE.person_key(w2)])
	var w3 := {"ghost_id": "weird_3", "profile": {"name": "改了名", "id": "weird_3", "tag": "#2345BC"}}
	_ok("★同一个 ID 改了名仍是同一个人", BE.person_key(w1) == BE.person_key(w3), BE.person_key(w3))
	var dup: Dictionary = P2.names_needing_tag(["石头统领", "石头统领", "彩虹大师", "海盗龟王"])
	_ok("★只有重名的名字要带号", dup.has("石头统领") and not dup.has("彩虹大师") and dup.size() == 1, str(dup.keys()))
	## 真入口: 排行榜屏
	BE.pool_override = lb_pool
	var lb: Node = (load("res://scenes/Leaderboard.tscn") as PackedScene).instantiate()
	add_child(lb)
	for _i in range(20):
		await get_tree().process_frame
	var tag_texts := []
	_collect_tags(lb, tag_texts)
	tag_texts.sort()
	_ok("★★排行榜屏: 只有那两行同名的带号, 号就是各自的 ID", tag_texts == ["#2345BC", "#6789CD"], str(tag_texts))
	lb.queue_free()
	BE.pool_override = {}

	## 对阵图(真入口: 桶地图 `set_bucket` 吃的就是 `parse_finals` 的产物)。4 人里两个同名。
	var body4 := JSON.stringify({"ok": true, "n": 4, "round": 1, "entrants": [
		{"seed": 0, "name": "石头统领", "account_id": "a0"}, {"seed": 1, "name": "彩虹大师", "account_id": "a1"},
		{"seed": 2, "name": "石头统领", "account_id": "a2"}, {"seed": 3, "name": "海盗龟王", "account_id": "a3"}], "done": {}})
	var fv4: Dictionary = SB.parse_finals(true, 200, body4, "", 0)
	var bm = load("res://scripts/scenes/BracketMapScene.gd").new()
	get_tree().root.add_child(bm)
	await get_tree().process_frame
	bm.set_bucket(fv4)
	await get_tree().process_frame
	var bt := []
	var q: Array = [bm]
	while not q.is_empty():
		var nd = q.pop_back()
		for ch in nd.get_children():
			q.append(ch)
			if ch is Label:
				bt.append(str((ch as Label).text))
	var t0 := P2.player_tag("a0")
	var t2 := P2.player_tag("a2")
	var with_tag := 0
	var other_tagged := 0
	for tx in bt:
		if tx.find("石头统领") >= 0 and (tx.find(t0) >= 0 or tx.find(t2) >= 0):
			with_tag += 1
		if (tx.find("彩虹大师") >= 0 or tx.find("海盗龟王") >= 0) and tx.find("#") >= 0:
			other_tagged += 1
	_ok("★★对阵图: 两个同名的人各自带上自己的号", with_tag == 2 and str(bt).find(t0) >= 0 and str(bt).find(t2) >= 0,
		"%d 格 / %s" % [with_tag, str(bt.filter(func(x): return str(x).find("统领") >= 0))])
	_ok("★对阵图: 不重名的格子不带号", other_tagged == 0, "%d 格" % other_tagged)
	bm.queue_free()
	await get_tree().process_frame

	GameState.account_id = acct0
	GameState.install_uid = uid0
	GameState.account_email = mail0
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 玩家 ID" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _collect_tags(n: Node, out: Array) -> void:
	for ch in n.get_children():
		if ch is Label and str(ch.name).begins_with("RowTag"):
			out.append(str((ch as Label).text))
		_collect_tags(ch, out)


func _gp(uid: String, name: String, wins: int, tag: String) -> Dictionary:
	var gid := "g_%s_%d_basic-stone-ice_b5" % [uid, int(GameState.season_id)]
	return {"schema_ver": BE.SCHEMA_VER, "ghost_id": gid, "is_bot": false, "origin": BE.ORIGIN_REMOTE,
		"profile": {"name": name, "id": gid, "tag": tag},
		"leaders": ["basic", "stone", "ice"], "season_total_battles": 5,
		"season_wins": wins, "hearts": 3, "season_sweeps": 0}
