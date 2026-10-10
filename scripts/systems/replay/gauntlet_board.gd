extends RefCounted
## 周六赛况板的数据层 —— **纯函数**(服务端回来的行 → 战绩榜 + 对局流水)。
## 方案书: docs/plans/20261004-周末看回放.md §4.1。页面在 `scripts/scenes/GauntletBoardScene.gd`。
##
## ══════════════════════════════════════════════════════════════════════
##  一行 = 一场周六闯关赛的录像摘要(`SupabaseNet.gauntlet_board_query` 只取这些):
##    match_id / created_at / result{won, gw?, gl?} / lp = 录像方 profile / rp = 对手 profile /
##    la / ra = 双方三统领 id(对局卡上画阵容; 老查询 / 门禁造的行没有 ⇒ 空槽) /
##    rw, rl = 对手快照上的战绩标签(那一刻他几胜几负; 闯关只同标签互配) /
##    client_version = 录下时的版本(`version_differs`; 老查询没有 ⇒ 不知道)
## ══════════════════════════════════════════════════════════════════════
## ★人按 `#ID`(profile.tag)认 —— 两侧一视同仁。对手是真人快照还是机器人, 这一层**看不出来也不问**
##   (录像与 right_snapshot 上传前都摘掉了 is_bot / ghost_id; 机器人的名字与号与真人同一套生成法)。
##   用户 2026-10-04「不能让玩家知道是机器人」。
## ★战绩取「证据里场次最多的那一条」:
##   · 自己上传的行带 `result.gw/gl`(那一局**打完后**的战绩) —— 最准;
##   · 老行没有 gw/gl ⇒ 退回数自己上传了几胜几负;
##   · 他被别人打到时快照上的标签(那一刻的战绩)也算一条证据。
##   ★★但只以对手身份出现过的人**不进榜**(2026-10-10): 机器人每场一个新号, 进榜就露馅。
##   三条对所有人是**同一条规则**, 不分真人机器人。
## ★状态 = `Phase2Config.gauntlet_state`(4 胜晋级 / 3 负出局); 周六收盘后还没定的算出局
##   (没打满就到收盘 = 没晋级, 与 `gauntlet_backfill_owed` 同一口径)。

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BE := preload("res://scripts/net/backend.gd")
const SB := preload("res://scripts/net/supabase.gd")

const ST_TEXT := {
	## ★「待定」不是「在打」(用户 2026-10-10「在打又是什么说法呢」): 这一档 = 没晋级也没出局, 与此刻在不在打无关;
	##   正在打的另有红色「直播」签(`GauntletBoardScene._apply_live`)。
	"running": "待定",   # devnote-ok: 闯关赛状态词(晋级与否未定), 玩家该读的规则, 与对阵表那格「待定」同一类
	"in": "已晋级",
	"out": "已出局",
}


## 一份 profile → 这个人的 #ID。认不出 ⇒ ""(这一侧不进榜, 但流水照样显示名字)。
static func tag_of(prof) -> String:
	if not (prof is Dictionary):
		return ""
	return BE.profile_tag(prof)


static func name_of(prof) -> String:
	if not (prof is Dictionary):
		return "?"
	var n := str((prof as Dictionary).get("name", "")).strip_edges()
	return n if n != "" else "?"


## ISO 时间串(PostgREST 的 timestamptz, 例 `2026-10-03T12:34:56.789+00:00`)→ unix 秒(UTC)。认不出 ⇒ 0。
static func iso_to_unix(s: String) -> int:
	if s.length() < 19:
		return 0
	var base := s.substr(0, 19)
	var t := int(Time.get_unix_time_from_datetime_string(base))
	if t <= 0:
		return 0
	## 时区偏移(`+08:00` / `-05:00` / `Z`)。PostgREST 默认给 +00:00, 防一手别的。
	var rest := s.substr(19)
	var k := maxi(rest.rfind("+"), rest.rfind("-"))
	if k >= 0 and rest.length() - k >= 6:
		var sg := 1 if rest[k] == "+" else -1
		var hh := int(rest.substr(k + 1, 2))
		var mm := int(rest.substr(k + 4, 2))
		t -= sg * (hh * 3600 + mm * 60)
	return t


## 行 → {"players": [...], "games": [...]}。
##   players: {tag, name, avatar, w, l, state, state_text, me} —— 胜多在前、负少在前、名字。
##   games:   {id, t, l:{tag,name,avatar}, r:{...}, lw(录像方赢了吗)} —— 新的在前。
## `my_tag` = 我自己的 #ID(标「我」); `closed` = 周六已收盘。
static func build(rows: Array, my_tag: String, closed: bool) -> Dictionary:
	var ppl := {}            # tag → {name, avatar, best_w, best_l, cw, cl, t}
	var games: Array = []
	for r0 in rows:
		if not (r0 is Dictionary):
			continue
		var r: Dictionary = r0
		var res: Dictionary = r.get("result", {}) if r.get("result", {}) is Dictionary else {}
		var lw := bool(res.get("won", false))
		var t := iso_to_unix(str(r.get("created_at", "")))
		var lt := tag_of(r.get("lp", null))
		var rt := tag_of(r.get("rp", null))
		games.append({"id": str(r.get("match_id", "")), "t": t, "lw": lw, "ver": _ver(r),
			"l": _side(r.get("lp", null), lt, r.get("la", null)), "r": _side(r.get("rp", null), rt, r.get("ra", null))})
		if lt != "":
			var p: Dictionary = _person(ppl, lt, r.get("lp", null), t)
			p["own"] = true
			if res.has("gw") and res.has("gl"):
				_offer(p, int(res.get("gw", 0)), int(res.get("gl", 0)))
			else:
				if lw:
					p["cw"] = int(p["cw"]) + 1
				else:
					p["cl"] = int(p["cl"]) + 1
		if rt != "":
			var q: Dictionary = _person(ppl, rt, r.get("rp", null), t)
			if r.get("rw", null) != null and r.get("rl", null) != null:
				_offer(q, int(r.get("rw", 0)), int(r.get("rl", 0)))
	var players: Array = []
	for tg in ppl:
		var p: Dictionary = ppl[tg]
		## ★★只以对手身份出现过的人不进榜(2026-10-10 周六实操): 机器人每场都是一个新号, 原来每个都进榜、
		##   战绩冻在赛前标签、整天「在打」又从不出现在流水的录像方 —— 一对比就认得出(用户「不能让玩家知道是机器人」)。
		##   规则仍对所有人相同: 自己传过一场才进榜(真人打一场就会传)。他快照上的标签仍算进下面的战绩证据。
		if not bool(p.get("own", false)):
			continue
		_offer(p, int(p["cw"]), int(p["cl"]))
		var w := int(p["best_w"])
		var l := int(p["best_l"])
		var st: String = P2C.gauntlet_state(w, l)
		if closed and st == P2C.GAUNTLET_RUNNING:
			st = P2C.GAUNTLET_OUT
		players.append({"tag": str(tg), "name": str(p["name"]), "avatar": str(p["avatar"]),
			"w": w, "l": l, "state": st, "state_text": str(ST_TEXT.get(st, st)),
			"me": my_tag != "" and str(tg) == my_tag})
	players.sort_custom(_player_before)
	games.sort_custom(func(a, b) -> bool:
		if int(a["t"]) != int(b["t"]):
			return int(a["t"]) > int(b["t"])
		return str(a["id"]) < str(b["id"]))
	return {"players": players, "games": games}


## 某个人打过 / 被打过的那几场(点名字时右栏换成它)。顺序沿用 `games`(新的在前)。
static func games_of(games: Array, tag: String) -> Array:
	var out: Array = []
	for g in games:
		if g is Dictionary and (str(g["l"].get("tag", "")) == tag or str(g["r"].get("tag", "")) == tag):
			out.append(g)
	return out


## 这一场能不能看。★赛况板的每一行都是 `matches` 表里的一份录像(上传侧 `upload_match_async` 不带录像本体
##   一律不发, 见 supabase.gd 那一处 `str(row.get("replay", "")) == ""`), 所以判据就是「这一行有合法的 match_id」
##   —— 点下去按 match_id 去取。认不出 id 的行(脏数据 / 门禁造的)⇒ 不放「观看」, 不摆死按钮。
static func watchable(g: Dictionary) -> bool:
	return SB.is_uuid(str(g.get("id", "")))


## 这一场(打完的 / 正在打的)录下时的版本与本机不同 ⇒ 卡上不摆「观看」/「观赛」, 换成「版本不同」灰签
##   (点了也播不了: 回放走 `ReplayRecorder.play` 的版本闸, 观赛走 `live_spectate` 的版本闸)。
##   `ver` = 行里的 `client_version`(两条查询都取这一列); 老查询 / 门禁造的行没有 ⇒ 不知道 ⇒ 照旧摆按钮。
static func version_differs(g: Dictionary) -> bool:
	return ReplayRecorder.version_differs(str(g.get("ver", "")))


static func _ver(r: Dictionary) -> String:
	var v = r.get("client_version", null)
	return str(v) if v is String else ""


## 一场的胜者名字。
static func winner_name(g: Dictionary) -> String:
	return str((g["l"] if bool(g.get("lw", false)) else g["r"]).get("name", "?"))


# ─────────────────────────────── 正在打(周六直播, 2026-10-07) ───────────────────────────────
## 方案书 docs/plans/20261007-实时观赛.md。一行 = `live_matches` 的摘要(`SupabaseNet.live_board_query` 只取这些):
##   match_id / started_at / updated_at / client_version / lp rp(双方 profile) / la ra(双方三统领)。
## ★「正在打」卡**不写胜负**(观赛 ≠ 回放: 看之前不知道结果)。

## 一行直播多久没写算断了(秒)。打的人每 3 秒心跳一次 ⇒ 45 秒没动静就是断网 / 杀进程(方案书风险 1)。
const LIVE_STALE_SEC := 45


## 一行直播还算「正在打」吗。**纯函数**(时钟由调用方给; updated_at 是服务端写的, `now` 用跟服务器走的钟)。
static func live_stale(updated: int, now: int) -> bool:
	return updated <= 0 or now - updated > LIVE_STALE_SEC


## 直播行 → 「正在打」卡: {id, t(开打时刻), l, r}(l/r 同 `games` 的形状)。新开打的在前。
##   丢掉: 已结束的 / 断了的(`live_stale`) / 已经打完上了「最近对局」的(同一个 match_id)/ id 不是 uuid 的。
static func live_games(rows: Array, finished_ids: Array, now: int) -> Array:
	var out: Array = []
	for r0 in rows:
		if not (r0 is Dictionary):
			continue
		var r: Dictionary = r0
		var id := str(r.get("match_id", ""))
		if not SB.is_uuid(id) or finished_ids.has(id) or bool(r.get("ended", false)):
			continue
		if live_stale(iso_to_unix(str(r.get("updated_at", ""))), now):
			continue
		out.append({"id": id, "t": iso_to_unix(str(r.get("started_at", ""))), "ver": _ver(r),
			"l": _side(r.get("lp", null), tag_of(r.get("lp", null)), r.get("la", null)),
			"r": _side(r.get("rp", null), tag_of(r.get("rp", null)), r.get("ra", null))})
	out.sort_custom(func(a, b) -> bool:
		if int(a["t"]) != int(b["t"]):
			return int(a["t"]) > int(b["t"])
		return str(a["id"]) < str(b["id"]))
	return out


## 战绩榜标「直播」: 正在打的那一方(录像方 = 左边; 右边是对手快照, 不是人在打)。
##   榜上还没有他(这周第一场还没打完)⇒ 补一行 0-0「在打」。改 `data` 本身, 补完重新排序。
static func mark_live(data: Dictionary, live: Array, my_tag: String) -> void:
	var on := {}
	for g in live:
		var tg := str((g as Dictionary)["l"].get("tag", ""))
		if tg != "":
			on[tg] = g["l"]
	var players: Array = data.get("players", [])
	for p in players:
		(p as Dictionary)["live"] = on.has(str(p["tag"]))
		on.erase(str(p["tag"]))
	for tg in on:
		var sd: Dictionary = on[tg]
		players.append({"tag": str(tg), "name": str(sd.get("name", "?")), "avatar": str(sd.get("avatar", "")),
			"w": 0, "l": 0, "state": P2C.GAUNTLET_RUNNING, "state_text": str(ST_TEXT["running"]),
			"me": my_tag != "" and str(tg) == my_tag, "live": true})
	players.sort_custom(_player_before)
	data["players"] = players


static func _player_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["w"]) != int(b["w"]):
		return int(a["w"]) > int(b["w"])
	if int(a["l"]) != int(b["l"]):
		return int(a["l"]) < int(b["l"])
	if str(a["name"]) != str(b["name"]):
		return str(a["name"]) < str(b["name"])
	return str(a["tag"]) < str(b["tag"])


static func _side(prof, tag: String, leaders = null) -> Dictionary:
	var av := ""
	if prof is Dictionary:
		av = str((prof as Dictionary).get("avatar", ""))
	var lu: Array = []
	if leaders is Array:
		for x in leaders:
			if lu.size() < 3 and (x is String) and str(x) != "":
				lu.append(str(x))
	return {"tag": tag, "name": name_of(prof), "avatar": av, "lineup": lu}


## 取(或建)这个人的账。名字 / 头像取**最新**那一行的(改过名的人显示新名)。
static func _person(ppl: Dictionary, tag: String, prof, t: int) -> Dictionary:
	if not ppl.has(tag):
		ppl[tag] = {"name": name_of(prof), "avatar": "", "best_w": 0, "best_l": 0, "cw": 0, "cl": 0, "t": -1}
	var p: Dictionary = ppl[tag]
	if t >= int(p["t"]):
		p["t"] = t
		p["name"] = name_of(prof)
		if prof is Dictionary:
			p["avatar"] = str((prof as Dictionary).get("avatar", ""))
	return p


## 一条战绩证据: 场次更多的胜出(同场次取胜多的 —— 同一个人同场次只会有一个真实战绩, 这一条只防脏数据)。
static func _offer(p: Dictionary, w: int, l: int) -> void:
	w = maxi(0, w)
	l = maxi(0, l)
	var bw := int(p["best_w"])
	var bl := int(p["best_l"])
	if w + l > bw + bl or (w + l == bw + bl and w > bw):
		p["best_w"] = w
		p["best_l"] = l
