extends RefCounted
## battle_log_net.gd —— 战绩页的服务器数据(2026-11-18 · 方案书 docs/plans/20261118-对局记录重做.md §4.2; 服务端迁移 20261118b · my_battle_log)。
##
## 用户 11-18「对局记录现在就只有…积分赛…周日是不是没有啊？偷袭的是不是也没有啊？…时间双方的装备也没有。」
##   原来战绩页只读本机 GameState.match_history(只记这台设备打的、没装备没时间)。服务器 referee_jobs 四种都有 ⇒ 从这里取。
## 一行(`parse` 规整后): {id, kind: ranked|gauntlet|finals|raid|local, week, at(秒), won, secs, lanes {top, bottom: me|foe|""},
##   match_id, replay(服务器有录像), finals {bucket, round, match}, raid_role: attack|defend|"", b_side(我在 b 方),
##   me / foe = {name, tag, avatar, leaders: [3], equipped: {统领: [{id, star}]}, lanes: {top: [], bottom: []}}}
## 本机老记录(`from_local`)规整成同一个形状(kind = local, 没有装备), 页面一套画法。

const SB := preload("res://scripts/net/supabase.gd")
const RPC := "/rest/v1/rpc/my_battle_log"
const PAGE := 20
const KINDS := ["ranked", "gauntlet", "finals", "raid"]

static var fetches := 0        # 发出去几次(门禁量)
static var dropped := 0        # 回包时回调方已释放、丢掉的次数(门禁量)


## 纯函数: my_battle_log 回包 → {ok, rows}。看不懂 / 断网 ⇒ ok false(rows 空)。一行不合法(没有 id / 不认识的种类)就丢掉那一行。
static func parse(ok: bool, code: int, body: String) -> Dictionary:
	if not ok or code < 200 or code >= 300:
		return {"ok": false, "rows": [], "reason": "net"}
	var j = JSON.parse_string(body)
	if not (j is Array):
		return {"ok": false, "rows": [], "reason": "net"}
	var rows: Array = []
	for x in j:
		if not (x is Dictionary):
			continue
		var d: Dictionary = x
		var kind := str(d.get("kind", ""))
		if int(d.get("id", 0)) <= 0 or not kind in KINDS:
			continue
		var lanes: Dictionary = d.get("lanes", {}) if d.get("lanes") is Dictionary else {}
		rows.append({
			"id": int(d.get("id", 0)), "kind": kind, "week": int(d.get("week", 0)), "at": int(d.get("at", 0)),
			"won": bool(d.get("won", false)), "secs": maxi(0, int(d.get("secs", 0))),
			"lanes": {"top": _lane(lanes.get("top")), "bottom": _lane(lanes.get("bottom"))},
			"match_id": str(d.get("match_id", "")), "replay": bool(d.get("replay", false)),
			"finals": d.get("finals", {}) if d.get("finals") is Dictionary else {},
			"raid_role": str(d.get("raid_role", "")) if d.get("raid_role") is String else "",
			"b_side": str(d.get("side", "a")) == "b",
			"me": side_of(d.get("me", {})), "foe": side_of(d.get("foe", {})),
		})
	return {"ok": true, "rows": rows, "reason": ""}


static func _lane(v) -> String:
	var s := str(v) if v is String else ""
	return s if s == "me" or s == "foe" else ""


## 一方: 名字 / 标签 / 三统领 / 三统领各自的装备 / 上下路。形状不对的字段一律给空, 页面照画空槽。
static func side_of(v) -> Dictionary:
	var d: Dictionary = v if v is Dictionary else {}
	var leaders: Array = []
	for l in (d.get("leaders", []) if d.get("leaders") is Array else []):
		if leaders.size() < 3:
			leaders.append(str(l))
	var eq: Dictionary = {}
	var src: Dictionary = d.get("equipped", {}) if d.get("equipped") is Dictionary else {}
	for l in leaders:
		var items: Array = []
		for it in (src.get(l, []) if src.get(l) is Array else []):
			if it is Dictionary and str((it as Dictionary).get("id", "")) != "":
				items.append({"id": str(it["id"]), "star": clampi(int((it as Dictionary).get("star", 1)), 1, 3)})
		eq[l] = items
	var la: Dictionary = d.get("lanes", {}) if d.get("lanes") is Dictionary else {}
	var lanes := {"top": [], "bottom": []}
	for k in ["top", "bottom"]:
		for p in (la.get(k, []) if la.get(k) is Array else []):
			(lanes[k] as Array).append(str(p))
	return {"name": str(d.get("name", "")), "tag": str(d.get("tag", "")), "avatar": str(d.get("avatar", "")),
		"leaders": leaders, "equipped": eq, "lanes": lanes}


## 统领 pid 在这一方的哪一路: "top" / "bottom" / ""。
static func lane_of(side: Dictionary, pid: String) -> String:
	var la: Dictionary = side.get("lanes", {})
	for k in ["top", "bottom"]:
		if (la.get(k, []) as Array).has(pid):
			return k
	return ""


## 本机老记录(GameState.match_history 一行)→ 同一个形状。kind = local(说不清是积分赛还是闯关赛), 没有装备 / 路况。
static func from_local(m: Dictionary, my_name: String) -> Dictionary:
	var mine: Array = []
	for p in (m.get("lineup", []) if m.get("lineup") is Array else []):
		var pid := str((p as Dictionary).get("id", "")) if p is Dictionary else str(p)
		if pid != "" and mine.size() < 3:
			mine.append(pid)
	var foe: Array = []
	for p in (m.get("foe", []) if m.get("foe") is Array else []):
		if foe.size() < 3:
			foe.append(str(p))
	return {"id": 0, "kind": "local", "week": 0, "at": int(m.get("ts", 0)), "won": str(m.get("result", "")) == "win",
		"secs": maxi(0, int(m.get("turn", 0))), "lanes": {"top": "", "bottom": ""},
		"match_id": str(m.get("replay_id", "")), "replay": false, "finals": {}, "raid_role": "",
		"b_side": str(m.get("side", "")) == "b", "local": m,
		"me": side_of({"name": my_name, "leaders": mine}), "foe": side_of({"name": str(m.get("foe_name", "")), "leaders": foe})}


## 取一页。`before` = 上一页最后一行的 id(0 = 第一页)。`done(res: {ok, rows, reason})` 恰好一次。
static func fetch(before: int, done: Callable) -> void:
	if not SB.enabled():
		_reply(done, {"ok": false, "rows": [], "reason": "off"})
		return
	var n = SB._spawn()
	if n == null:
		_reply(done, {"ok": false, "rows": [], "reason": "net"})
		return
	fetches += 1
	_send(n, JSON.stringify({"p_limit": PAGE, "p_before": (before if before > 0 else null)}), done)


## 回调方(对局记录页)可能在回包之前就被关掉了(等登录令牌 / 网络那几秒里点了返回) ⇒ 对象已释放的回调直接丢掉。
## 2026-11-18 CI 抓到: verify_replay_window 进页后立刻换屏, 回包时 `null::_on_fetched` 报 SCRIPT ERROR。
static func _reply(done: Callable, r: Dictionary) -> void:
	if done.is_valid():
		done.call(r)
	else:
		dropped += 1


## ★夺冠之路(journey_net.gd)也走这里: 传它自己的 `rpc` 与 `parse_fn`(dup_primitive_audit: 同一份实现不许抄两遍)。
static func _send(n, body: String, done: Callable, rpc: String = RPC, parse_fn: Callable = Callable()) -> void:
	if not await n._await_token():
		n._bye()
		_reply(done, {"ok": false, "rows": [], "reason": "not_signed_in" if SB.session_lost() else "net"})
		return
	var pf: Callable = parse_fn if parse_fn.is_valid() else parse
	n._http("POST", SB.base_url().rstrip("/") + rpc, body, func(res: Dictionary) -> void:
		var r: Dictionary = pf.call(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", "")))
		n._bye()
		_reply(done, r),
		"Content-Type: application/json")
