class_name FriendsNet
extends RefCounted
## friends_net.gd —— 好友 + 切磋取阵容(2026-10-24 · 方案书 docs/plans/20261023-好友切磋.md §4.1)。
##
## 服务端(server/supabase/migrations/20261024_friends.sql), 全是 security definer RPC, 两张表客户端直连读写一律被拒:
##   put_lineup      传我的最新背包阵容(离开背包 / 打开好友页 / 出战时; 只在阵容变了才传)
##   friend_lookup   按玩家 ID 找人(ID 不唯一 ⇒ 可能回几个, 让玩家按昵称挑)
##   friend_request  申请(对方已申请过我 ⇒ 直接成为好友) / friend_respond 同意 · 拒绝 / friend_remove 删 · 撤回
##   friend_list     好友页一次拿全(我的 ID、好友、收到的申请、发出的申请)
##   friend_lineup   切磋取好友最新阵容(服务端先验是好友)
## ★上传走 `supabase.gd` 的现成机制(`_spawn` → `_await_token` → `_http`), 形状照抄 `report_net.gd`; supabase.gd 不改。
## ★回包正文 {ok:true} 才算成(memory `fb-200-ok-is-not-it-happened`); 每个回调**一定**被调一次。

const SB := preload("res://scripts/net/supabase.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const BackendS := preload("res://scripts/net/backend.gd")
const RR := preload("res://scripts/systems/replay/replay_recorder.gd")

const RPC := "/rest/v1/rpc/"
## 好友上限(与服务端 friend_request / friend_respond 里的 100 同一个数; 服务端 friend_list 也回 cap)。
const CAP := 100

## 失败原因 → 屏上那句话(服务端 reason 原样作键; 不认识的一律「网络异常」)。
const MSG := {
	"net": "网络异常，请稍后再试",
	"off": "未连接服务器",
	"not_signed_in": "账号未登录，请稍后再试",
	"bad_tag": "玩家 ID 格式不正确",
	"self": "这是你自己的玩家 ID",
	"not_found": "未找到该玩家",
	"already": "已是好友",
	"full": "好友数量已达上限 %d 人" % CAP,
	"their_full": "对方好友数量已达上限",
	"limit": "今日好友申请次数已达上限",
	"not_friends": "双方尚未成为好友",
	"no_lineup": "对方尚未配置阵容",
	"rules_old_mine": "当前版本较旧，请先更新游戏",
	"rules_old_theirs": "对方版本较旧，待对方更新后再切磋",
	"bad_lineup": "对方阵容读取失败",
}

## 观测量(门禁分母): 真交给 `_http` 的条数(按 RPC 名) / 上次传上去的阵容摘要(同一份不重传)。
static var posts: Dictionary = {}
static var _last_put := ""


static func msg(reason: String) -> String:
	return str(MSG.get(reason, MSG["net"]))


## 纯判据: 一次 RPC 回包 → {ok, reason, data}。2xx 且正文 {ok:true} 才算 ok。
static func parse(ok: bool, code: int, body: String, blocked: bool = false) -> Dictionary:
	if blocked or not ok or code < 200 or code >= 300:
		return {"ok": false, "reason": "net", "data": {}}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return {"ok": false, "reason": "net", "data": {}}
	var d: Dictionary = j.data
	if bool(d.get("ok", false)):
		return {"ok": true, "reason": "", "data": d}
	return {"ok": false, "reason": str(d.get("reason", "net")), "data": d}


## 调一个 RPC。`done(res: Dictionary)` 一定会被调一次(res 形状见 `parse`)。
static func call_rpc(fn: String, args: Dictionary, done: Callable) -> void:
	if not SB.enabled():
		done.call({"ok": false, "reason": "off", "data": {}})
		return
	var n = SB._spawn()
	if n == null:
		done.call({"ok": false, "reason": "net", "data": {}})
		return
	_send(n, fn, JSON.stringify(args), done)


static func _send(n, fn: String, body: String, done: Callable) -> void:
	if not await n._await_token():
		n._bye()
		done.call({"ok": false, "reason": "not_signed_in" if SB.session_lost() else "net", "data": {}})
		return
	posts[fn] = int(posts.get(fn, 0)) + 1
	n._http("POST", SB.base_url().rstrip("/") + RPC + fn, body, func(res: Dictionary) -> void:
		var r := parse(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", "")),
			bool(res.get("blocked", false)))
		n._bye()
		done.call(r),
		"Content-Type: application/json")


# ─────────────────────────── 我的最新阵容 ───────────────────────────

## 我现在的阵容快照(与积分赛结算上传的是同一个函数 `build_ghost_snapshot`, 战斗那边读得懂)。
## 统领没选满 ⇒ {}(服务端也收: 还没配阵容的人也要能被按 ID 找到)。
static func my_snapshot() -> Dictionary:
	var gs = SB._gs()
	if gs == null:
		return {}
	var ldr = gs.get("season_leaders")
	if not (ldr is Array) or (ldr as Array).size() < 3:
		return {}
	var gid: String = BackendS.player_ghost_id(int(gs.season_id), gs.season_leaders, int(gs.season_total_battles))
	return BackendS.build_ghost_snapshot(gid,
		{"name": BackendS.player_display_name(), "avatar": str((ldr as Array)[0]), "id": gid})


## 传我的最新阵容。和上次传的一样 ⇒ 一个请求都不发(`done` 照样调, reason = "same")。
## ★教程沙盒里不传(那时内存里是教程的阵容, 不是我的); test_mode(门禁 / 回放 / 切磋)里不传 ——
##   `force` 只跳过 test_mode 这一道(门禁用), 不跳过「没变不传」。
static func put_lineup(done: Callable = Callable(), force: bool = false) -> void:
	var gs = SB._gs()
	var cb := done if done.is_valid() else func(_r: Dictionary) -> void: pass
	if gs == null or bool(gs.get("tutorial_active")) or (bool(gs.get("test_mode")) and not force):
		cb.call({"ok": false, "reason": "skip", "data": {}})
		return
	var snap := my_snapshot()
	var name: String = BackendS.player_display_name()
	var key := (name + "|" + JSON.stringify(snap, "", true)).sha256_text()
	if key == _last_put:
		cb.call({"ok": true, "reason": "same", "data": {}})
		return
	call_rpc("put_lineup", {"p_name": name.left(40), "p_snapshot": snap, "p_rules_ver": int(_P2.RULES_VER),
			"p_client_version": RR.client_version()},
		func(r: Dictionary) -> void:
			if bool(r["ok"]):
				_last_put = key
			cb.call(r))


# ─────────────────────────── 好友 ───────────────────────────

static func lookup(tag: String, done: Callable) -> void:
	var t := tag.strip_edges().to_upper()
	if not t.begins_with("#"):
		t = "#" + t
	if not _P2.tag_valid(t):
		done.call({"ok": false, "reason": "bad_tag", "data": {}})
		return
	call_rpc("friend_lookup", {"p_tag": t}, done)


static func request(account: String, done: Callable) -> void:
	call_rpc("friend_request", {"p_other": account}, done)


static func respond(account: String, accept: bool, done: Callable) -> void:
	call_rpc("friend_respond", {"p_other": account, "p_accept": accept}, done)


static func remove(account: String, done: Callable) -> void:
	call_rpc("friend_remove", {"p_other": account}, done)


static func list(done: Callable) -> void:
	call_rpc("friend_list", {}, done)


# ─────────────────────────── 切磋取阵容 ───────────────────────────

## 纯判据: 好友的阵容能不能打。"" = 能; 否则是 MSG 的键。
##   规则版本不同 ⇒ 不打(同一份快照在两套规则下不是同一支队伍): 谁旧说谁。
##   快照结构版本旧(< SCHEMA_VER, 匹配池载入时也整批丢) / 没统领 / 分路坏 ⇒ 读取失败。
static func lineup_check(d: Dictionary) -> String:
	var rv := int(d.get("rules_ver", -1))
	if rv != int(_P2.RULES_VER):
		return "rules_old_theirs" if rv < int(_P2.RULES_VER) else "rules_old_mine"
	var s = d.get("snapshot", null)
	if not (s is Dictionary):
		return "bad_lineup"
	var snap: Dictionary = s
	if int(snap.get("schema_ver", 0)) < int(BackendS.SCHEMA_VER):
		return "rules_old_theirs"
	var ldr = snap.get("leaders", null)
	if not (ldr is Array) or (ldr as Array).is_empty() or BackendS.ghost_lanes_broken(snap):
		return "bad_lineup"
	return ""


## 取好友阵容。`done(r)`: r.ok 时 r.data 是服务端回包(snapshot / name / tag / source …); 不能打时 ok=false、reason 是 MSG 的键。
static func fetch_lineup(account: String, done: Callable) -> void:
	call_rpc("friend_lineup", {"p_other": account}, func(r: Dictionary) -> void:
		if not bool(r["ok"]):
			done.call(r)
			return
		var why := lineup_check(r["data"])
		if why != "":
			done.call({"ok": false, "reason": why, "data": r["data"]})
			return
		done.call(r))


# ─────────────────────────── 排行榜上切磋(2026-10-30) ───────────────────────────
## 方案书 docs/plans/20261030-排行榜切磋.md。用户「点击这个玩家之后，除了加好友选项，那还应该有这个切磋选项」。
## 排行榜上大多数人不是好友, 而 `friend_lineup` 只认好友 ⇒ 非好友打**他在榜上那份**阵容:
##   `ghosts` 里这个人这一周的积分赛快照(所有登录玩家可读, 匹配拉对手就是这么读的), 不改服务器。

## 查询串: 这个人这一周的快照, 场次 / 上传时刻倒序(与 week_leaderboard_page 的 latest 同序)。账号不像 uuid ⇒ ""。
static func board_query(account: String, week: int) -> String:
	var re := RegEx.create_from_string("^[0-9a-fA-F-]{32,36}$")
	if re.search(account) == null or week <= 0:
		return ""
	return "select=snapshot,rules_ver,battles,uploaded_at&account_id=eq.%s&season_week=eq.%d&order=battles.desc,uploaded_at.desc&limit=20" % [account, week]


## 纯判据: 一页 ghosts 行里挑排行榜算的那一行(与 week_leaderboard_page 的 latest 同一套筛选:
##   去 `seed_` / 机器人 / 闯关行(gl_w 或 gl_l 不为 0), 取第一行)。挑不出 ⇒ {}。
static func pick_board_row(rows) -> Dictionary:
	if not (rows is Array):
		return {}
	for r in rows:
		if not (r is Dictionary) or not ((r as Dictionary).get("snapshot") is Dictionary):
			continue
		var s: Dictionary = r["snapshot"]
		if str(s.get("ghost_id", "")).begins_with("seed_") or str(s.get("is_bot", "false")) == "true":
			continue
		if int(s.get("gl_w", 0)) != 0 or int(s.get("gl_l", 0)) != 0:
			continue
		return r
	return {}


## 取这个人在榜上的那份阵容。`done(r)` 一定调一次; r 形状同 `fetch_lineup`(data.source = "board")。
static func fetch_board_lineup(account: String, week: int, done: Callable) -> void:
	var q := board_query(account, week)
	if q == "":
		done.call({"ok": false, "reason": "no_lineup", "data": {}})
		return
	if not SB.enabled():
		done.call({"ok": false, "reason": "off", "data": {}})
		return
	var n = SB._spawn()
	if n == null:
		done.call({"ok": false, "reason": "net", "data": {}})
		return
	if not await n._await_token():
		n._bye()
		done.call({"ok": false, "reason": "not_signed_in" if SB.session_lost() else "net", "data": {}})
		return
	posts["ghosts"] = int(posts.get("ghosts", 0)) + 1
	n._http("GET", SB.base_url().rstrip("/") + "/rest/v1/ghosts?" + q, "", func(res: Dictionary) -> void:
		n._bye()
		var code := int(res.get("code", 0))
		if bool(res.get("blocked", false)) or not bool(res.get("ok", false)) or code < 200 or code >= 300:
			done.call({"ok": false, "reason": "net", "data": {}})
			return
		var row := pick_board_row(JSON.parse_string(str(res.get("body", ""))))
		if row.is_empty():
			done.call({"ok": false, "reason": "no_lineup", "data": {}})
			return
		var d := {"source": "board", "snapshot": row["snapshot"], "rules_ver": int(row.get("rules_ver", 0))}
		var why := lineup_check(d)
		done.call({"ok": why == "", "reason": why, "data": d}))


## 排行榜上的切磋: 是好友 ⇒ 他最新的背包阵容(与好友页一致); 不是好友 ⇒ 他在榜上那份(`fetch_board_lineup`)。
static func fetch_for_spar(account: String, week: int, done: Callable) -> void:
	fetch_lineup(account, func(r: Dictionary) -> void:
		if not bool(r["ok"]) and str(r["reason"]) == "not_friends":
			fetch_board_lineup(account, week, done)
			return
		done.call(r))
