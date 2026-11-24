extends RefCounted
## journey_net.gd —— 夺冠之路一整周的数据(2026-11-24 · 方案书 docs/plans/20261124-夺冠之路一整周.md §4; 服务端迁移 20261124 · finals_week_journey)。
##
## 用户 11-24「不是人家打的积分赛那十六场啊，然后…瑞士轮那几场，然后…小组赛几场，冠军几场。那比分你都不展示吗？」
## 一行(`parse` 规整后): {id, kind: ranked|gauntlet|finals, at, won, lanes {top, bottom, final: me|foe|""},
##   finals {bucket, round, match}, foe {name, avatar, leaders: [..3]}}
## `stages(rows)` 按段分组: 积分赛 / 闯关赛 / 小组赛 / 冠军杯赛, 每段 {key, title, w, l, rows}; 空段不出。

const SB := preload("res://scripts/net/supabase.gd")
## 发请求 / 回调方已释放就丢 / 路的取值: 与对局记录共用 battle_log_net 那一份(dup_primitive_audit)
const BLN := preload("res://scripts/net/battle_log_net.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RPC := "/rest/v1/rpc/finals_week_journey"
const KINDS := ["ranked", "gauntlet", "finals"]
const ST_RANKED := "ranked"
const ST_GAUNTLET := "gauntlet"
const ST_GROUP := "group"
const ST_CUP := "cup"
const STAGE_ORDER := [ST_RANKED, ST_GAUNTLET, ST_GROUP, ST_CUP]

static var fetches := 0        # 发出去几次(门禁量)


## 纯函数: 回包 → {ok, rows, reason}。看不懂 / 断网 / 服务器拒(not_entrant)⇒ ok false。不合法的行丢掉。
static func parse(ok: bool, code: int, body: String) -> Dictionary:
	if not ok or code < 200 or code >= 300:
		return {"ok": false, "rows": [], "reason": "net"}
	var j = JSON.parse_string(body)
	if not (j is Dictionary):
		return {"ok": false, "rows": [], "reason": "net"}
	if not bool((j as Dictionary).get("ok", false)):
		return {"ok": false, "rows": [], "reason": str((j as Dictionary).get("reason", "net"))}
	var rows: Array = []
	for x in ((j as Dictionary).get("rows", []) if (j as Dictionary).get("rows") is Array else []):
		if not (x is Dictionary):
			continue
		var d: Dictionary = x
		var kind := str(d.get("kind", ""))
		if int(d.get("id", 0)) <= 0 or not kind in KINDS:
			continue
		var la: Dictionary = d.get("lanes", {}) if d.get("lanes") is Dictionary else {}
		var fo: Dictionary = d.get("foe", {}) if d.get("foe") is Dictionary else {}
		var leaders: Array = []
		for l in (fo.get("leaders", []) if fo.get("leaders") is Array else []):
			if leaders.size() < 3:
				leaders.append(str(l))
		rows.append({
			"id": int(d.get("id", 0)), "kind": kind, "at": int(d.get("at", 0)), "won": bool(d.get("won", false)),
			"lanes": {"top": BLN._lane(la.get("top")), "bottom": BLN._lane(la.get("bottom")), "final": BLN._lane(la.get("final"))},
			"finals": d.get("finals", {}) if d.get("finals") is Dictionary else {},
			"foe": {"name": str(fo.get("name", "")), "avatar": str(fo.get("avatar", "")), "leaders": leaders},
		})
	return {"ok": true, "rows": rows, "reason": ""}


## 比分 [我赢的路数, 对手赢的路数]: 上 / 下 / 终极各算一路(2:0 / 2:1 / 上路碎蛋 1:0 / 1-1 后碎蛋 1:1,
##   与 phase2_duallane.score_code 四种码对得上)。一路都没记(判负收尾)⇒ []。
static func score_of(row: Dictionary) -> Array:
	var la: Dictionary = row.get("lanes", {})
	var me := 0
	var foe := 0
	for k in ["top", "bottom", "final"]:
		var v := str(la.get(k, ""))
		if v == "me":
			me += 1
		elif v == "foe":
			foe += 1
	if me + foe == 0:
		return []
	return [me, foe]


## 这一行属于哪一段。
static func stage_of(row: Dictionary) -> String:
	match str(row.get("kind", "")):
		"ranked":
			return ST_RANKED
		"gauntlet":
			return ST_GAUNTLET
		"finals":
			var bk := int((row.get("finals", {}) as Dictionary).get("bucket", -1))
			return ST_CUP if bk == P2C.FINALS_CUP_BUCKET else ST_GROUP
	return ""


static func stage_title(key: String) -> String:
	match key:
		ST_RANKED:
			return "积分赛"
		ST_GAUNTLET:
			return "闯关赛"
		ST_GROUP:
			return P2C.STAGE_GROUP
		ST_CUP:
			return P2C.STAGE_CUP
	return ""


## 分段: [{key, title, w, l, rows}], 按 STAGE_ORDER; 段内按打的先后(行本来就是 job_id 正序)。空段不出。
static func stages(rows: Array) -> Array:
	var by := {}
	for r in rows:
		var k := stage_of(r)
		if k == "":
			continue
		if not by.has(k):
			by[k] = []
		(by[k] as Array).append(r)
	var out: Array = []
	for k in STAGE_ORDER:
		if not by.has(k):
			continue
		var w := 0
		var l := 0
		for r in by[k]:
			if bool(r["won"]):
				w += 1
			else:
				l += 1
		out.append({"key": k, "title": stage_title(k), "w": w, "l": l, "rows": by[k]})
	return out


## 取冠军(或组冠军)这一周。`done(res: {ok, rows, reason})` 恰好一次。
static func fetch(week: int, account: String, done: Callable) -> void:
	if not SB.enabled() or week <= 0 or account == "":
		BLN._reply(done, {"ok": false, "rows": [], "reason": "off"})
		return
	var n = SB._spawn()
	if n == null:
		BLN._reply(done, {"ok": false, "rows": [], "reason": "net"})
		return
	fetches += 1
	BLN._send(n, JSON.stringify({"p_week": week, "p_account": account}), done, RPC, parse)

