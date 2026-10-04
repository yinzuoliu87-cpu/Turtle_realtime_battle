extends RefCounted
## 周六赛况板的数据层 —— **纯函数**(服务端回来的行 → 战绩榜 + 对局流水)。
## 方案书: docs/plans/20261004-周末看回放.md §4.1。页面在 `scripts/scenes/GauntletBoardScene.gd`。
##
## ══════════════════════════════════════════════════════════════════════
##  一行 = 一场周六闯关赛的录像摘要(`SupabaseNet.gauntlet_board_query` 只取这些):
##    match_id / created_at / result{won, gw?, gl?} / lp = 录像方 profile / rp = 对手 profile /
##    rw, rl = 对手快照上的战绩标签(那一刻他几胜几负; 闯关只同标签互配)
## ══════════════════════════════════════════════════════════════════════
## ★人按 `#ID`(profile.tag)认 —— 两侧一视同仁。对手是真人快照还是机器人, 这一层**看不出来也不问**
##   (录像与 right_snapshot 上传前都摘掉了 is_bot / ghost_id; 机器人的名字与号与真人同一套生成法)。
##   用户 2026-10-04「不能让玩家知道是机器人」。
## ★战绩取「证据里场次最多的那一条」:
##   · 自己上传的行带 `result.gw/gl`(那一局**打完后**的战绩) —— 最准;
##   · 老行没有 gw/gl ⇒ 退回数自己上传了几胜几负;
##   · 只以对手身份出现的(录像没传上来的真人 / 机器人) ⇒ 用他快照上的标签(那一刻的战绩)。
##   三条对所有人是**同一条规则**, 不分真人机器人。
## ★状态 = `Phase2Config.gauntlet_state`(4 胜晋级 / 3 负出局); 周六收盘后还没定的算出局
##   (没打满就到收盘 = 没晋级, 与 `gauntlet_backfill_owed` 同一口径)。

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BE := preload("res://scripts/net/backend.gd")

const ST_TEXT := {
	"running": "在打",
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
		games.append({"id": str(r.get("match_id", "")), "t": t, "lw": lw,
			"l": _side(r.get("lp", null), lt), "r": _side(r.get("rp", null), rt)})
		if lt != "":
			var p: Dictionary = _person(ppl, lt, r.get("lp", null), t)
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


## 一场的胜者名字。
static func winner_name(g: Dictionary) -> String:
	return str((g["l"] if bool(g.get("lw", false)) else g["r"]).get("name", "?"))


static func _player_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["w"]) != int(b["w"]):
		return int(a["w"]) > int(b["w"])
	if int(a["l"]) != int(b["l"]):
		return int(a["l"]) < int(b["l"])
	if str(a["name"]) != str(b["name"]):
		return str(a["name"]) < str(b["name"])
	return str(a["tag"]) < str(b["tag"])


static func _side(prof, tag: String) -> Dictionary:
	var av := ""
	if prof is Dictionary:
		av = str((prof as Dictionary).get("avatar", ""))
	return {"tag": tag, "name": name_of(prof), "avatar": av}


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
