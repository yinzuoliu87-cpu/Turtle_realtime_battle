class_name ChampionData
extends RefCounted
## champion_data.gd —— 周日冠军收盘 / 组冠军 / 冠军杯开场 / 奖励链 / 冠军墙 要喂的数据(纯函数)。
## 方案书 docs/plans/20261031c-周日赛事界面重做.md 块 D(G7 G10 G11 G12 G13)。
##
## ★只吃客户端已经拿得到的东西, 一个字段都不编:
##   · `SupabaseNet.parse_finals_week()` 的回包形状(`{"buckets": [组…], "cup": {…}}`, 每组 = `_bucket_from` 那一份:
##     size / done / scores / names / tags / accs / me / closed)
##   · 可选 `rows`: `matches` 表里本周决赛那几行(`finals_rows_query()` 的查询串取回), 每行
##     `{result:{steps, fb, fr, fm, won}, lp/rp: 双方 profile, la/ra: 双方三统领 id}` ——
##     阵容(统领)、头像、单场时长都从这里来。没有 = 空, 屏幕照常演, 只是那一拍少一块。
## ★座次推导一律调 `bracket.gd`(与对阵图、发头衔同一份), 这里不写第二遍。
## ★「单场最高伤害」「最强一只龟」客户端拿不到(录像只录输入, 伤害要整场重算) —— 见 `best_cards()` 注释。

const _B := preload("res://scripts/gamedata/bracket.gd")
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const DL_SCORE := preload("res://scripts/gamedata/phase2_duallane.gd")
const _BE := preload("res://scripts/net/backend.gd")

const WEEK_SEC := 7 * 86400
## 第 1 届冠军杯所在那一周的周一锚点(UTC 2026-10-05 00:00)。冠军杯赛 2026-10-07 上正式服(schema.sql「champion_cup 20261007b 已上生产」),
## 第一个冠军杯周日是 10-11 ⇒ 届数 = 从这一周数起。★调用方可以在 data 里直接给 "edition" 覆盖。
const CUP_FIRST_WEEK := 1791158400
const SIM_HZ := 60            # matches.result.steps 的单位: sim 步, 每秒 60 步
const TITLE_UNTIL := "至下周日"

## #ID → 头像 的补充表(对阵图从同周赛况板拿到的那份 `BracketMapScene._portraits`)。
## ★为什么要它: 下面所有函数的头像只从比赛记录 rows 里取, 而对阵图开仪式时手里没有 rows(传 [])
##   ⇒ 冠军仪式 / 开场亮相 / 冠军墙全画默认龟(B 录视频时发现)。调用方开演前把手里那份喂进来;
##   rows 里有的仍以 rows 为准(更新)。
static var portraits: Dictionary = {}


# ═══════════════════════════════════════════════════════════════════
#  名字 / 届数 / 日期
# ═══════════════════════════════════════════════════════════════════
## 组号 → 「A 组」。★组号从 0 起(服务端 bucket_no), 与对阵图「第 N 组」同一个顺序。
static func group_name(bucket_no: int) -> String:
	if bucket_no < 0:
		return ""
	if bucket_no < 26:
		return "%s 组" % char(65 + bucket_no)
	return "第 %d 组" % (bucket_no + 1)


## 第几届冠军杯。周锚点不对 / 早于第一届 ⇒ 0(屏幕不写届数)。
static func edition_of(week: int) -> int:
	if week < CUP_FIRST_WEEK:
		return 0
	return (week - CUP_FIRST_WEEK) / WEEK_SEC + 1


## 那一周的周日是几月几日(UTC)。
static func date_text(week: int) -> String:
	if week <= 0:
		return ""
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(week + 6 * 86400)
	return "%d 月 %d 日" % [int(d.get("month", 0)), int(d.get("day", 0))]


## 「第 4 届　11 月 1 日」(届次与日期两个并列名词, 全角空格隔开; 不用「·」)。缺哪样省哪样。
static func edition_line(week: int, edition: int = -1) -> String:
	var ed := edition if edition >= 0 else edition_of(week)
	var parts: Array = []
	if ed > 0:
		parts.append("第 %d 届" % ed)
	var dt := date_text(week)
	if dt != "":
		parts.append(dt)
	return "　".join(parts)


## 单败表里第 r 轮叫什么(从决赛往回数)。`group` = 小组赛那一张(末轮叫「组决赛」)。
static func round_name(n: int, r: int, group: bool = false) -> String:
	var total := _B.rounds_for(n)
	var back := total - r
	if back == 0:
		return "组决赛" if group else "决赛"
	if back == 1:
		return "半决赛"
	if back == 2:
		return "1/4 决赛"
	return "1/%d 决赛" % (1 << back)        # 与全决赛日同一套(finals_copy.round_name); 原来写「第 r 轮」


## 毫秒级时长 → 「1:52」。
static func mmss(sec: float) -> String:
	var s := maxi(0, int(round(sec)))
	return "%d:%02d" % [s / 60, s % 60]


## 头衔页那一行: 「有效期至下周日」。★永久记录(`GameState.titles` 里那条 {id, week})不随周清;
##   「至下周日」说的是**名字旁那块牌**: 排行榜 / 对阵图按「上周终榜」贴冠军 / 亚军 / 四强, 下一届冠军诞生就换人。
static func title_until_line() -> String:
	return "有效期至%s" % TITLE_UNTIL.trim_prefix("至")


# ═══════════════════════════════════════════════════════════════════
#  从对阵数据里认人
# ═══════════════════════════════════════════════════════════════════
## 一张表(组或杯)的冠军种子; -1 = 还没决出。
static func champion_seed_of(b: Dictionary) -> int:
	var n := int(b.get("size", 0))
	if n <= 0:
		return -1
	return _B.champion_seed(n, b.get("done", {}) if b.get("done", {}) is Dictionary else {})


## 决赛的输家种子(亚军); -1 = 没有(1 人表 / 决赛没翻面)。
static func runner_up_seed_of(b: Dictionary) -> int:
	var n := int(b.get("size", 0))
	var total := _B.rounds_for(n)
	if total <= 0:
		return -1
	var done: Dictionary = b.get("done", {}) if b.get("done", {}) is Dictionary else {}
	var w := int(done.get("%d-0" % total, -1))
	if w < 0:
		return -1
	var sd := _B.occupant_seed(total, 0, 1 - w, n, done)
	return sd if sd >= 0 else -1


static func _arr_at(b: Dictionary, key: String, i: int) -> String:
	var a = b.get(key, [])
	if a is Array and i >= 0 and i < (a as Array).size():
		return str(a[i])
	return ""


## 这个账号是哪一组的组冠军 → 组号; -1 = 不是任何一组的组冠军。
static func group_of_champion(view: Dictionary, acc: String, tag: String = "") -> int:
	for b in (view.get("buckets", []) as Array):
		if not (b is Dictionary):
			continue
		var sd := champion_seed_of(b)
		if sd < 0:
			continue
		if (acc != "" and _arr_at(b, "accs", sd) == acc) or (acc == "" and tag != "" and _arr_at(b, "tags", sd) == tag):
			return int((b as Dictionary).get("bucket", -1))
	return -1


## 来历标签: 「A 组冠军」; 认不出 = 空串。
static func origin_of(view: Dictionary, acc: String, tag: String = "") -> String:
	var g := group_of_champion(view, acc, tag)
	return (group_name(g) + "冠军") if g >= 0 else ""


## 本周决赛日一共几个人(各组人数之和)= 规模「24 人冠军」的那个数。
static func entrant_count(view: Dictionary) -> int:
	var n := 0
	for b in (view.get("buckets", []) as Array):
		if b is Dictionary:
			n += int((b as Dictionary).get("size", 0))
	return n


# ═══════════════════════════════════════════════════════════════════
#  matches 行(阵容 / 头像 / 时长)
# ═══════════════════════════════════════════════════════════════════
## ★取这些行**现在没有现成的函数**(只有周六赛况板那一条 `fetch_gauntlet_board_async`)。要补的那条读(与赛况板同一种写法,
##   只取 profile / 三统领 / result, 不取整份快照、不取录像本体; 周日那一场揭晓之前本来就不上传):
##   GET /rest/v1/matches?phase=eq.finals&season_week=eq.<周>&select=match_id,created_at,result,
##       lp:left_snapshot->profile,rp:right_snapshot->profile,la:left_snapshot->leaders,ra:right_snapshot->leaders
##       &order=created_at.asc&limit=200
##   取回来的数组直接喂 `people_from_rows` / `best_cards` / `cup_show(rows=…)`。


## ★#ID 的认法与周六赛况板同一份(`Backend.profile_tag`), 不另写。
static func _tag_of_prof(prof) -> String:
	if prof is Dictionary:
		return _BE.profile_tag(prof)
	return ""


static func _leaders(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for x in raw:
			if out.size() < 3 and (x is String) and str(x) != "":
				out.append(str(x))
	return out


## 行 → {#ID: {"lineup": [三统领], "avatar": 头像}}。同一个人多行取最后一行(最后一场 = 最新阵容)。
static func people_from_rows(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for tg in portraits:
		if str(tg) != "" and str(portraits[tg]) != "":
			out[str(tg)] = {"lineup": [], "avatar": str(portraits[tg])}
	for r in rows:
		if not (r is Dictionary):
			continue
		for sd in [["lp", "la"], ["rp", "ra"]]:
			var prof = (r as Dictionary).get(sd[0], null)
			var tag := _tag_of_prof(prof)
			if tag == "":
				continue
			var lu := _leaders((r as Dictionary).get(sd[1], null))
			var av := str((prof as Dictionary).get("avatar", "")) if prof is Dictionary else ""
			var cur: Dictionary = out.get(tag, {"lineup": [], "avatar": ""})
			if not lu.is_empty():
				cur["lineup"] = lu
			if av != "":
				cur["avatar"] = av
			out[tag] = cur
	return out


# ═══════════════════════════════════════════════════════════════════
#  一个人(选手卡)
# ═══════════════════════════════════════════════════════════════════
static func person(b: Dictionary, sd: int, view: Dictionary, people: Dictionary) -> Dictionary:
	if sd < 0:
		return {}
	var tag := _arr_at(b, "tags", sd)
	var acc := _arr_at(b, "accs", sd)
	var pp: Dictionary = people.get(tag, {}) if tag != "" else {}
	var lu: Array = (pp.get("lineup", []) as Array).duplicate()
	var av := str(pp.get("avatar", ""))
	if av == "":
		av = _arr_at(b, "avatars", sd)       # 对阵图喂进来的按种子序头像(BracketMapScene.portrait_of 同一来源)
	if av == "" and not lu.is_empty():
		av = str(lu[0])                      # 与排行榜同一条: 头像 = 第一只统领
	return {"name": _arr_at(b, "names", sd), "tag": tag, "acc": acc, "avatar": av,
		"lineup": lu, "origin": origin_of(view, acc, tag), "seed": sd}


## 这个人在这张表里一路怎么走过来的: [{round, foe, foe_avatar, score:[我, 对手], won, bye}]。
static func path_of(b: Dictionary, sd: int, people: Dictionary, group: bool) -> Array:
	var out: Array = []
	var n := int(b.get("size", 0))
	var total := _B.rounds_for(n)
	var done: Dictionary = b.get("done", {}) if b.get("done", {}) is Dictionary else {}
	var scores: Dictionary = b.get("scores", {}) if b.get("scores", {}) is Dictionary else {}
	for r in range(1, total + 1):
		for m in range(_B.matches_in_round(n, r)):
			var side := _B.my_side_in(sd, r, m, n, done)
			if side < 0:
				continue
			var foe := _B.occupant_seed(r, m, 1 - side, n, done)
			var key := "%d-%d" % [r, m]
			var row := {"round": round_name(n, r, group), "foe": "", "foe_avatar": "", "score": [], "won": false, "bye": false}
			if foe == _B.OCC_BYE:
				row["bye"] = true
				row["won"] = true
				out.append(row)
				continue
			row["foe"] = _arr_at(b, "names", foe)
			var ft := _arr_at(b, "tags", foe)
			var fp: Dictionary = people.get(ft, {}) if ft != "" else {}
			row["foe_avatar"] = str(fp.get("avatar", ""))
			if row["foe_avatar"] == "" and not (fp.get("lineup", []) as Array).is_empty():
				row["foe_avatar"] = str((fp["lineup"] as Array)[0])
			if done.has(key):
				row["won"] = int(done[key]) == side
				if scores.has(key):
					var pair: Array = DL_SCORE.score_pair(int(scores[key]))
					if pair.size() == 2:
						row["score"] = [pair[0], pair[1]] if row["won"] else [pair[1], pair[0]]
			out.append(row)
	return out


# ═══════════════════════════════════════════════════════════════════
#  三种演出的数据
# ═══════════════════════════════════════════════════════════════════
## 冠军杯冠军收盘(G10)。决赛还没翻面 / 没有杯 ⇒ {}(调用方别演)。
## `my_acc` 用来判「看的人是不是冠军本人」(冠军本人定格卡上多一个「领取奖励」)。
static func cup_show(view: Dictionary, week: int, rows: Array = [], my_acc: String = "",
		bests: Array = []) -> Dictionary:
	var cup = view.get("cup", null)
	if not (cup is Dictionary):
		return {}
	var c: Dictionary = cup
	var sd := champion_seed_of(c)
	if sd < 0:
		return {}
	var people := people_from_rows(rows)
	var champ := person(c, sd, view, people)
	var ru := person(c, runner_up_seed_of(c), view, people)
	return {"mode": "cup", "week": week, "edition": edition_of(week), "date": date_text(week),
		"entrants": entrant_count(view), "champion": champ, "runner_up": ru,
		"lineup": champ.get("lineup", []), "path": path_of(c, sd, people, false),
		"bests": bests if not bests.is_empty() else best_cards(view, rows),
		"viewer_is_champion": my_acc != "" and str(champ.get("acc", "")) == my_acc}


## 冠军杯决赛**刚播完**那一刻(观战收尾第二拍交过来的 `info`, 见 finals_end_beats.gd `end_info`)→ 收盘数据。
## ★那一刻本机缓存的对阵数据里决赛多半还没翻面(只填已播完的场), 所以冠军 / 亚军 / 阵容 / 决赛比分取 `info`,
##   之前几轮的夺冠之路、规模、来历取缓存的 `view`(拿不到就只有决赛那一行)。
##   info 用到的键: win("left"/"right")· me · names{left,right} · pids{left,right} · leaders{left,right} ·
##   origins{left,right} · score{left,right}。
static func cup_show_from_end(info: Dictionary, view: Dictionary, week: int, rows: Array = []) -> Dictionary:
	var win := str(info.get("win", ""))
	if win != "left" and win != "right":
		return {}
	var lose := "right" if win == "left" else "left"
	var names: Dictionary = info.get("names", {}) if info.get("names", {}) is Dictionary else {}
	var pids: Dictionary = info.get("pids", {}) if info.get("pids", {}) is Dictionary else {}
	var leaders: Dictionary = info.get("leaders", {}) if info.get("leaders", {}) is Dictionary else {}
	var origins: Dictionary = info.get("origins", {}) if info.get("origins", {}) is Dictionary else {}
	var sc: Dictionary = info.get("score", {}) if info.get("score", {}) is Dictionary else {}
	var people := people_from_rows(rows)
	var champ := {"name": str(names.get(win, "")), "avatar": str(pids.get(win, "")), "lineup": _leaders(leaders.get(win, [])),
		"origin": str(origins.get(win, "")), "tag": "", "acc": ""}
	var ru := {"name": str(names.get(lose, "")), "avatar": str(pids.get(lose, "")), "origin": str(origins.get(lose, ""))}
	var path: Array = []
	var cup = view.get("cup", null)
	if cup is Dictionary:
		var n := int((cup as Dictionary).get("size", 0))
		var sd := ((cup as Dictionary).get("names", []) as Array).find(champ["name"])
		if sd >= 0:
			var fin := round_name(n, _B.rounds_for(n), false)
			for row in path_of(cup, sd, people, false):
				if str(row["round"]) != fin:
					path.append(row)
			if str(champ["origin"]) == "":
				champ["origin"] = origin_of(view, _arr_at(cup, "accs", sd), _arr_at(cup, "tags", sd))
	var score: Array = []
	if sc.has(win) and sc.has(lose) and int(sc[win]) > 0:
		score = [int(sc[win]), int(sc[lose])]
	path.append({"round": "决赛", "foe": ru["name"], "foe_avatar": ru["avatar"], "score": score, "won": true, "bye": false})
	return {"mode": "cup", "week": week, "edition": edition_of(week), "date": date_text(week),
		"entrants": entrant_count(view), "champion": champ, "runner_up": ru, "lineup": champ["lineup"], "path": path,
		"bests": best_cards(view, rows), "viewer_is_champion": str(info.get("me", "")) == win}


## 组冠军缩短版。这一组还没决出 ⇒ {}。
static func group_show(view: Dictionary, bucket_no: int, week: int, rows: Array = [], my_acc: String = "",
		next_text: String = "") -> Dictionary:
	for b in (view.get("buckets", []) as Array):
		if not (b is Dictionary) or int((b as Dictionary).get("bucket", -1)) != bucket_no:
			continue
		var sd := champion_seed_of(b)
		if sd < 0:
			return {}
		var people := people_from_rows(rows)
		var champ := person(b, sd, view, people)
		return {"mode": "group", "week": week, "edition": edition_of(week), "date": date_text(week),
			"group": group_name(bucket_no), "entrants": int((b as Dictionary).get("size", 0)),
			"champion": champ, "lineup": champ.get("lineup", []), "path": path_of(b, sd, people, true),
			"viewer_is_champion": my_acc != "" and str(champ.get("acc", "")) == my_acc,
			"next_text": next_text if next_text != "" else "晋级冠军杯赛"}
	return {}


## 冠军杯开场: 组冠军依次亮相(G7)。`defending_acc` = 上一届冠军杯冠军的账号(从上周 finals_week_view 认,
##   见 `defending_acc_of`); 本届组冠军里有他就标「卫冕」。顺序 = 组号。
static func cup_intro(view: Dictionary, week: int, rows: Array = [], defending_acc: String = "") -> Dictionary:
	var people := people_from_rows(rows)
	var ents: Array = []
	for b in (view.get("buckets", []) as Array):
		if not (b is Dictionary):
			continue
		var sd := champion_seed_of(b)
		if sd < 0:
			continue
		var p := person(b, sd, view, people)
		p["origin"] = group_name(int((b as Dictionary).get("bucket", -1))) + "冠军"
		p["defending"] = defending_acc != "" and str(p.get("acc", "")) == defending_acc
		ents.append(p)
	return {"week": week, "edition": edition_of(week), "date": date_text(week), "entrants": ents,
		"total": entrant_count(view)}


## 上一届冠军杯冠军的账号(喂上周的 finals_week_view 回包); 没有 = 空串。
static func defending_acc_of(prev_view: Dictionary) -> String:
	var cup = prev_view.get("cup", null)
	if not (cup is Dictionary):
		return ""
	var sd := champion_seed_of(cup)
	return _arr_at(cup, "accs", sd) if sd >= 0 else ""


# ═══════════════════════════════════════════════════════════════════
#  今晚之最(G13)
# ═══════════════════════════════════════════════════════════════════
## 从 matches 行算得出来的卡。★只有「最快结束的一场」算得出(result.steps = 整场 sim 步数)。
##   「单场最高伤害」「最强一只龟」**客户端拿不到**: 录像只录重算所需的输入(ReplayRecorder 头注),
##   伤害要把整场重算一遍; 裁判写回的 result 里也只有 won / steps / 坐标。要服务端(裁判)在 result 里补
##   `top_dmg: {tid, dmg, side}` 才能做(报告里写给 S)。调用方拿到了可以直接塞进 data["bests"]。
static func best_cards(view: Dictionary, rows: Array) -> Array:
	var best := {}
	var best_steps := 1 << 30
	## ★同一场可能有好几行(双方本机各打一份 + 裁判那一份); 有裁判写回的行就只认裁判的(与 finals_replay 采纳同一份)。
	var any_ref := false
	for x in rows:
		if x is Dictionary and (x as Dictionary).get("result", null) is Dictionary 				and bool(((x as Dictionary)["result"] as Dictionary).get("referee", false)):
			any_ref = true
	for x in rows:
		if not (x is Dictionary):
			continue
		var res = (x as Dictionary).get("result", null)
		if not (res is Dictionary):
			continue
		if any_ref and not bool((res as Dictionary).get("referee", false)):
			continue
		var st := int((res as Dictionary).get("steps", 0))
		if st <= 0 or st >= best_steps:
			continue
		best_steps = st
		best = x
	if best.is_empty():
		return []
	var res: Dictionary = best["result"]
	var fb := int(res.get("fb", -1))
	var fr := int(res.get("fr", -1))
	var where := ""
	var cup = view.get("cup", null)
	if cup is Dictionary and int((cup as Dictionary).get("bucket", -9)) == fb:
		where = _P2C.STAGE_CUP + round_name(int((cup as Dictionary).get("size", 0)), fr, false)
	else:
		for b in (view.get("buckets", []) as Array):
			if b is Dictionary and int((b as Dictionary).get("bucket", -9)) == fb:
				where = group_name(fb) + round_name(int((b as Dictionary).get("size", 0)), fr, true).trim_prefix("组")
	var ln := str(((best.get("lp", {}) if best.get("lp", {}) is Dictionary else {}) as Dictionary).get("name", ""))
	var rn := str(((best.get("rp", {}) if best.get("rp", {}) is Dictionary else {}) as Dictionary).get("name", ""))
	var won := bool(res.get("won", true))
	var winner := ln if won else rn
	var lu := _leaders(best.get("la", null) if won else best.get("ra", null))
	return [{"kind": "fast", "title": "最快结束的一场", "value_sec": float(best_steps) / float(SIM_HZ),
		"value": mmss(float(best_steps) / float(SIM_HZ)), "who": winner,
		"sub": ("%s：" % where if where != "" else "") + ("%s 对 %s" % [ln, rn]),
		"turtle": str(lu[0]) if not lu.is_empty() else ""}]


# ═══════════════════════════════════════════════════════════════════
#  奖励链(G11)
# ═══════════════════════════════════════════════════════════════════
## 一页一件。`titles` = 这一周拿到的头衔 id(TITLE_*), 只放最高那一档一页(其余在副标题里提一句)。
## ★2026-11-08 删掉「深海币入账」那一页(用户「为什么获得冠军之后还讲深海币啊？冠军之后获得深海币没意义了呀。你每轮每轮就应该发呀」):
##   轮次币每轮出结果就发、对阵图当场提示(`RefereeWatch.finals_grant_round`), 冠军仪式只放头衔。
static func reward_pages(titles: Array) -> Array:
	var pages: Array = []
	for tid in _P2C.TITLE_ORDER:
		if tid in titles and tid != _P2C.TITLE_FINALS_DAY and tid != _P2C.TITLE_FULL_QUOTA:
			pages.append({"kind": "title", "id": tid, "name": str(_P2C.TITLE_LABEL.get(tid, tid)),
				"sub": title_until_line()})
			break
	return pages


# ═══════════════════════════════════════════════════════════════════
#  冠军墙(G12)
# ═══════════════════════════════════════════════════════════════════
## 一届一行。没决出 ⇒ {}。`replay` = 决赛录像的坐标(`SupabaseNet.fetch_finals_replay_async` 四个参数)。
static func wall_entry(week: int, view: Dictionary, rows: Array = []) -> Dictionary:
	var cup = view.get("cup", null)
	if not (cup is Dictionary):
		return {}
	var c: Dictionary = cup
	var sd := champion_seed_of(c)
	if sd < 0:
		return {}
	var people := people_from_rows(rows)
	var p := person(c, sd, view, people)
	var total := _B.rounds_for(int(c.get("size", 0)))
	var rp := {}
	if total > 0:
		rp = {"week": week, "bucket": int(c.get("bucket", -1)), "round": total, "match": 0}
	var ru := person(c, runner_up_seed_of(c), view, people)
	return {"week": week, "edition": edition_of(week), "date": date_text(week), "name": str(p.get("name", "")),
		"avatar": str(p.get("avatar", "")), "lineup": p.get("lineup", []), "origin": str(p.get("origin", "")),
		"runner_up": str(ru.get("name", "")), "entrants": entrant_count(view), "replay": rp}
