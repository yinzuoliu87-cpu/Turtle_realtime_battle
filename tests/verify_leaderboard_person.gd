extends Node
## verify_leaderboard_person.gd — **排行榜排的是「人」, 不是「快照」**(台账 ⑵ + ⑻)
## 判据名: **DEDUP_BY_PERSON**(与 `backend.person_key()` 头注、`verify_leaderboard_sort` ⑧ 同一个名字)
##
## ═══ 守的是哪两条真机 bug ═══
## ⑵「排行榜前 9 名只有 2 个人」/ ⑻「前 11 名只有 6 个真人, 有人占 3 行,
##   顶上却写「本周共 124 人上榜」」—— 同一个根因的两次实拍。
## 用户 2026-09-29 原话: **「就是要排人, 不能排快照」**。
##
## ═══ 为什么 `verify_leaderboard_sort` ⑧ 不够, 要再开这一份 ═══
## ⑧ 造的快照里 `leaders` 与 `ghost_id` 里的三龟段**永远是同一套**(它自己拼的),
## 而真机上**不是**: 探针跑 `user://ghost_pool.json`(426 条 / 其中 30 条真人)量到
##   `ghost_owner_tag()` 只在 **13/30** 条上解析成功, 另外 **17 条静默返回 ""**,
##   形状一律是 `gid=g_<uid>_3_diamond-ghost-two_head` 而 `leaders=["angel","ice","ninja"]`
##   —— 两个量**不同源**(id 来自 `season_leaders`, `leaders` 来自 `dual_lineup` 的分路)。
## 解析失败 ⇒ 掉到 `person_key` 的第三判据【昵称】, 而它的头注自己写着
##   「会撞(336 个随机昵称, 十来个人就有一成撞名)/ 改名会把一个人裂成两行 / 所以排第三」。
## ⇒ 本门禁的判据形状 = **拿真机上那个"两个量不同源"的形状去打**, 并且一路打到屏幕上的字。
##
## ═══ 三段 ═══
##   ① 身份这一维的形状(纯函数, 可穷举): `owner_tag_of_id` 是 `player_ghost_id` 的反函数
##   ② 真机形状: leaders 漂了 / 改过名 / 撞名不同人 —— 合该合、分该分
##   ③ **屏幕**: 真实例化 `Leaderboard.tscn`, 读活节点的 `text`
##      —— 一个人只占一行, 且「本周共 N 人上榜」那个 N 就是人数
##
## 跑法: TURTLE_SUPABASE=" " <godot> --headless --audio-driver Dummy --path . \
##         res://tests/verify_leaderboard_person.tscn --quit-after 500

const Backend := preload("res://scripts/net/backend.gd")

## 三个真人的 install uid(12 位十六进制 —— 与 `GameState.get_install_uid()` 同形状)。
## ★必须**互不相同**且都不等于本机 uid, 否则 `_is_self_ghost` 会把他们当成自己滤掉。
const UID_A := "a1a1a1a1a1a1"
const UID_B := "b2b2b2b2b2b2"
const UID_C := "c3c3c3c3c3c3"

var _ok := 0
var _fail := 0


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])


## 造一份【某个人某一场】的真人快照。
##
## ★`id_leaders` 与 `field_leaders` **分开传** —— 这就是本门禁的全部要点:
##   `ghost_id` 里那三龟(来自 `season_leaders`)和快照 `leaders` 字段(来自分路)
##   在真机上可以**不是同一套**。传成同一套就退化成 `verify_leaderboard_sort` ⑧ 了。
## ★id 的拼法与 `Backend.player_ghost_id()` 逐字相同 —— ① 段有一条断言拿生产函数钉住它。
func _gp(uid: String, season: int, id_leaders: Array, field_leaders: Array,
		battles: int, name: String, wins: int, hearts: int, sweeps: int) -> Dictionary:
	var srt: Array = []
	for x in id_leaders:
		srt.append(str(x))
	srt.sort()
	var gid := "g_%s_%d_%s_b%d" % [uid, season, "-".join(PackedStringArray(srt)), battles]
	return {"schema_ver": Backend.SCHEMA_VER, "ghost_id": gid, "is_bot": false,
		"origin": Backend.ORIGIN_REMOTE,
		"profile": {"name": name, "id": gid},      # ★真人快照的 profile.id **就是** ghost_id
		"leaders": field_leaders.duplicate(),
		"lane_assign": {"top": field_leaders.slice(0, 2), "bottom": field_leaders.slice(2)},
		"minions": {"top": [{"role": "front"}], "bottom": [{"role": "front"}]},
		"season_total_battles": battles,
		"season_wins": wins, "hearts": hearts, "season_sweeps": sweeps}


## 「这条快照的 `leaders` 段在它自己的 `ghost_id` 里**找不到**」 ——
## 也就是旧解析必然失败的那个形状。用它当**分母**: 证明 ② 段的数据真的是真机那个形状,
## 而不是我造了一批"其实两边一致"的快照去测一个不存在的场景。
func _drifted(g: Dictionary) -> bool:
	var srt: Array = []
	for x in (g.get("leaders", []) as Array):
		srt.append(str(x))
	srt.sort()
	return str(g.get("ghost_id", "")).find("_" + "-".join(PackedStringArray(srt))) <= 0


func _names(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append(str((r as Dictionary).get("name", "?")))
	return out


func _uniq(arr: Array) -> int:
	var d: Dictionary = {}
	for x in arr:
		d[str(x)] = 1
	return d.size()


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	_chk("⓪ ★分母: GameState 在位(拿不到它整条身份维都不存在)", gs != null)
	if gs == null:
		_done()
		return
	gs.test_mode = true
	var sid: int = int(gs.season_id)
	var me: String = str(gs.get_install_uid())

	_seg1(sid, me)
	_seg2(sid)
	await _seg3(sid)
	_done()


func _done() -> void:
	Backend.pool_override = {}         # ★static, 活过场景切换 —— 必须清
	print("")
	print("  (共 %d 条断言)" % (_ok + _fail))
	print("ALL PASS — 排行榜排人不排快照" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════════════
# ① 身份这一维的形状 —— `owner_tag_of_id()` 是 `player_ghost_id()` 的反函数
# ══════════════════════════════════════════════════════════════════════
func _seg1(sid: int, me: String) -> void:
	print("── ① 身份维: owner_tag_of_id 是 player_ghost_id 的反函数 ──")
	_chk("① ★分母: 本机 uid 非空", me != "", me)
	## ★这条钉的是**解析唯一用到的形状假设**: uid 是 12 位十六进制, 赛季是小整数,
	##   靠长度把 `g_<uid>_<赛季>_` 与 `g_<赛季>_` 分开。uid 换了长度/字符集就当场红,
	##   而不是静默把每个人的身份解析成另一个串。
	_chk("① ★★uid 的形状 = %d 位十六进制(解析靠它区分 uid 那一段)" % Backend.UID_HEX_LEN,
		me.length() == Backend.UID_HEX_LEN and me.is_valid_hex_number(false),
		"len=%d %s" % [me.length(), me])

	## ★★★穷举回归: 赛季 × 三龟(含**自带下划线**的 `two_head`) × 场次后缀,
	##   每一组都必须解析成 `self_season_prefix(赛季)` 逐字相同的那个串。
	##   打印**组数**当分母 —— 0 组就是空检查。
	var n := 0
	var bad := 0
	var first_bad := ""
	for s in [0, 1, 3, 12, 99]:
		for ldr in [["two_head"], ["two_head", "basic"], ["angel", "ice", "ninja"],
				["basic", "shell", "two_head"]]:
			for bt in [-1, 0, 7, 24]:
				var gid := Backend.player_ghost_id(s, ldr, bt)
				n += 1
				if Backend.owner_tag_of_id(gid) != Backend.self_season_prefix(s):
					bad += 1
					if first_bad == "":
						first_bad = "gid=%s 得=%s 应=%s" % [gid,
							Backend.owner_tag_of_id(gid), Backend.self_season_prefix(s)]
	_chk("① ★分母: 穷举了 %d 组生产 id(赛季 5 × 阵容 4 × 场次 4)" % n, n == 80, "%d 组" % n)
	_chk("① ★★★%d 组生产 id 全部解析成 `self_season_prefix(赛季)` 逐字相同" % n,
		bad == 0, first_bad if bad > 0 else "0 组不符")

	## 周赛制那条更长的 id(`_g<胜>-<负>` 后缀)也要落在同一个人身上。
	var gsat := Backend.player_ghost_id(sid, ["angel", "ice", "ninja"], -1) + "_g4-1"
	_chk("① 周赛制 id(`…_g4-1`)也解析成同一个人",
		Backend.owner_tag_of_id(gsat) == Backend.self_season_prefix(sid),
		"%s → %s" % [gsat, Backend.owner_tag_of_id(gsat)])

	## uid 为空那一支(`self_prefix()` 拿不到 GameState 时给 `"g_"`) —— 真机池里就有这种老 id。
	_chk("① uid 为空的老 id `g_1_bamboo-basic-stone` 解析成 `g_1_`",
		Backend.owner_tag_of_id("g_1_bamboo-basic-stone") == "g_1_",
		Backend.owner_tag_of_id("g_1_bamboo-basic-stone"))

	## ★★不该有 owner 的形状必须解析成 "" —— 否则会把陪练/机器人**当成人**去占名次。
	##   前缀不是我编的: `Backend.SEED_ID_PREFIX` 就是产品认陪练的那条。
	var none := [Backend.SEED_ID_PREFIX + "0_b3", "bot_lv5_1", "coh_0_b3",
		"uicons_r3", "", "g_", "g_abc", "g_%s_3" % UID_A]
	var leaked: Array = []
	for x in none:
		if Backend.owner_tag_of_id(str(x)) != "":
			leaked.append("%s→%s" % [str(x), Backend.owner_tag_of_id(str(x))])
	_chk("① ★分母: 拿 %d 种「不该有 owner」的 id 试过(含陪练前缀 `%s`、截断串 `g_<uid>_3`)"
			% [none.size(), Backend.SEED_ID_PREFIX], none.size() == 8, "%d 种" % none.size())
	_chk("① ★★陪练/机器人/队列模拟/截断串 一个都解析不出 owner", leaked.is_empty(),
		str(leaked))


# ══════════════════════════════════════════════════════════════════════
# ② 真机形状: `leaders` 与 `ghost_id` 不同源时, 合该合、分该分
# ══════════════════════════════════════════════════════════════════════
func _seg2(sid: int) -> void:
	print("── ② 真机形状: leaders 与 ghost_id 不同源(真机 17/30 条就是它) ──")
	## 甲: 同一个人打了 3 场, **每场 id 里的三龟都不一样**(换阵容),
	##     而 `leaders` 字段死死停在同一套(真机上那 17 条的形状), **而且他改过两次名**。
	var a1 := _gp(UID_A, sid, ["diamond", "ghost", "two_head"], ["angel", "ice", "ninja"],
		5, "甲的旧名", 2, 8, 0)
	var a2 := _gp(UID_A, sid, ["lava", "lightning", "phoenix"], ["angel", "ice", "ninja"],
		6, "甲的新名", 9, 3, 2)            # ← 他最好的那一场
	var a3 := _gp(UID_A, sid, ["gambler", "hunter", "pirate"], ["angel", "ice", "ninja"],
		7, "甲又改了名", 4, 8, 1)
	## 乙: **另一个人**(uid 不同), 昵称与甲的旧名**逐字相同**, leaders 同样漂着。
	var b1 := _gp(UID_B, sid, ["bubble", "candy", "line"], ["angel", "ice", "ninja"],
		5, "甲的旧名", 6, 6, 0)

	_chk("② ★分母: 甲这 3 条的 `ghost_id` 互不相同(同 id 的话 `pool_add` 早合掉了)",
		_uniq([a1["ghost_id"], a2["ghost_id"], a3["ghost_id"]]) == 3,
		str(a1["ghost_id"]))
	_chk("② ★★★分母: 这 4 条**全部**是「leaders 段在自己 id 里找不到」的形状 —— "
			+ "就是真机那 17 条; 不是这个形状的话本段在测一个不存在的场景",
		_drifted(a1) and _drifted(a2) and _drifted(a3) and _drifted(b1),
		"a1=%s a2=%s a3=%s b1=%s" % [_drifted(a1), _drifted(a2), _drifted(a3), _drifted(b1)])
	## ★这里读的是**快照**的 `profile.name`(不是榜行的 `name`) —— 拿错字段会全读成 "?"
	##   而 `_uniq(["?","?","?"]) == 1` 照样能让"两两不同"这条**红**, 所以它至少不会假绿。
	var a_names := [str((a1["profile"] as Dictionary)["name"]),
		str((a2["profile"] as Dictionary)["name"]), str((a3["profile"] as Dictionary)["name"])]
	_chk("② ★分母: 甲 3 条的昵称**两两不同**(改过名) —— 相同的话「改名」这一半是空检查",
		_uniq(a_names) == 3, str(a_names))
	_chk("② ★★分母: 甲的旧名与乙的昵称**逐字相同**(这才叫撞名)",
		str((a1["profile"] as Dictionary)["name"]) == str((b1["profile"] as Dictionary)["name"]),
		str((b1["profile"] as Dictionary)["name"]))

	_chk("② ★★★甲这 3 条的 `person_key` 是**同一个**(漂了也认得出是同一个人)",
		Backend.person_key(a1) == Backend.person_key(a2)
			and Backend.person_key(a2) == Backend.person_key(a3),
		Backend.person_key(a1))
	_chk("② ★★★甲与乙的 `person_key` **不同**(撞名不许合成一个人 —— 合了就有人从榜上消失)",
		Backend.person_key(a1) != Backend.person_key(b1),
		"%s vs %s" % [Backend.person_key(a1), Backend.person_key(b1)])
	_chk("② ★身份维走的是 owner 那一支(`o:` 前缀), 不是昵称兜底(`n:`)",
		Backend.person_key(a1).begins_with("o:"), Backend.person_key(a1))

	var pool := {Backend.POOL_KEY: {}}
	for g in [a1, b1, a2, a3]:
		Backend.pool_add(pool, g)
	var snaps := 0
	for b in (pool[Backend.POOL_KEY] as Dictionary).keys():
		snaps += ((pool[Backend.POOL_KEY] as Dictionary)[b] as Array).size()
	var rows: Array = Backend.leaderboard(pool, "我自己", 0, 0, 0, 1 << 30)
	print("    [分母] 池里快照 %d 条 → 参与排序的人 %d 个 → 榜上 %d 行 %s"
		% [snaps, rows.size() - 1, rows.size(), str(_names(rows))])
	_chk("② ★分母: 池里确实是 4 条快照(不是被 `pool_add` 提前合掉了)", snaps == 4, "%d 条" % snaps)
	_chk("② ★★★榜上 3 行 = 甲 + 乙 + 我(4 条快照合成 2 个人) —— 不去重是 5 行",
		rows.size() == 3, "%d 行 %s" % [rows.size(), str(_names(rows))])
	_chk("② ★★分母: 快照条数(%d) > 人数(%d) —— 相等就说明这一轮什么都没合, 上面那条是空检查"
			% [snaps, rows.size() - 1], snaps > rows.size() - 1)
	_chk("② 留下的是甲**最好**那一行(9 胜那场, 不是最后进池的 4 胜)",
		_names(rows).has("甲的新名"), str(_names(rows)))
	_chk("② ★乙那一行还在(撞名的两个人各占一行)",
		_names(rows).has("甲的旧名"), str(_names(rows)))


# ══════════════════════════════════════════════════════════════════════
# ③ 屏幕: 真实例化 Leaderboard.tscn, 读活节点的 text
#    —— 台账 ⑵/⑻ 是**看屏幕**发现的, 判据也得看到屏幕上的字
# ══════════════════════════════════════════════════════════════════════
func _seg3(sid: int) -> void:
	print("── ③ 屏幕: 一个人只占一行 + 「本周共 N 人上榜」的 N 就是人数 ──")
	## 三个人共 6 条快照。甲最好那场的昵称**独一无二**(「甲又改了名」),
	## 所以"屏上互异名字数 == 人数"这条不会被"两个人同名"这件正确的事弄红。
	var ppl := {
		UID_A: [["甲的旧名", 2], ["甲的新名", 4], ["甲又改了名", 11]],
		UID_B: [["乙", 7]],
		UID_C: [["丙", 5], ["丙", 3]],
	}
	var pool := {Backend.POOL_KEY: {}}
	var snaps := 0
	var bt := 5
	for uid in ppl.keys():
		for rec in (ppl[uid] as Array):
			bt += 1
			Backend.pool_add(pool, _gp(str(uid), sid,
				["diamond", "ghost", "two_head"], ["angel", "ice", "ninja"],
				bt, str((rec as Array)[0]), int((rec as Array)[1]), 4, 0))
			snaps += 1
	Backend.pool_override = pool
	_chk("③ ★分母: 注入 %d 条快照 / %d 个人(每人多份场次快照)" % [snaps, ppl.size()],
		snaps == 6 and ppl.size() == 3, "%d 条 / %d 人" % [snaps, ppl.size()])

	var ps: PackedScene = load("res://scenes/Leaderboard.tscn")
	_chk("③ ★分母: Leaderboard.tscn 载得进来", ps != null)
	if ps == null:
		return
	var inst: Node = ps.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	var consts: Dictionary = inst.get_script().get_script_constant_map()
	_chk("③ ★分母: 拿到本屏自己的版式常量 NAME_X(判据不另写一份坐标)",
		consts.has("NAME_X"), str(consts.get("NAME_X", "<缺>")))
	var name_x: float = float(consts.get("NAME_X", -1.0))

	var labels: Array = []
	var st: Array = [inst]
	while not st.is_empty():
		var n = st.pop_back()
		if n is Label and (n as Label).is_visible_in_tree():
			labels.append(n as Label)
		for ch in n.get_children():
			st.append(ch)
	_chk("③ ★分母: 屏上找到 %d 个可见 Label(0 个 = 屏根本没画出来)" % labels.size(),
		labels.size() >= 8, "%d 个" % labels.size())

	## 名字格 = 位置正好落在本屏自己的 `NAME_X` 上的那些 Label(空席画的是 `—`)。
	var shown: Array = []
	var cap_n := -1
	for l in labels:
		var t := str((l as Label).text).strip_edges()
		if t.find("人上榜") >= 0:
			var digits := ""
			for c in t:
				if str(c).is_valid_int():
					digits += str(c)
			cap_n = int(digits) if digits != "" else -1
		if absf((l as Label).position.x - name_x) < 0.5 and t != "" and t != "—":
			shown.append(t)
	print("    [分母] 屏上名字格 %d 个: %s ／ 顶上那句写的是 %d 人" % [shown.size(), str(shown), cap_n])
	_chk("③ ★分母: 屏上真画出了名字行(空屏/占位屏的话这里是 0)", shown.size() >= 4,
		"%d 个 %s" % [shown.size(), str(shown)])
	_chk("③ ★★★屏上每个名字**只出现一次** —— 台账 ⑻「有人占 3 行」就是这条红",
		_uniq(shown) == shown.size(), "%d 个名字 / %d 个互异 %s"
			% [shown.size(), _uniq(shown), str(shown)])
	_chk("③ ★★★屏上人数 = 3 个真人 + 我 = 4(6 条快照合成 3 个人)",
		shown.size() == 4, "%d 个 %s" % [shown.size(), str(shown)])
	_chk("③ ★★★「本周共 %d 人上榜」那个数就是屏上的人数, 不是快照条数(%d)"
			% [cap_n, snaps], cap_n == shown.size(),
		"句里 %d / 屏上 %d / 池里 %d 条" % [cap_n, shown.size(), snaps])
	_chk("③ ★分母: 那句话真的在屏上(找不到就不是 0 而是 -1, 上面那条会假绿)", cap_n >= 0,
		"%d" % cap_n)

	inst.queue_free()
	await get_tree().process_frame
