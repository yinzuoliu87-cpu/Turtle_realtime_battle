extends RefCounted
## 回放 S2: 录像上传队列 —— 打完先**落盘排队**, 再发; 服务端**回读得到**那一行才销单。
## 方案书: docs/plans/20261003-跨设备回放.md §4.6 / 门禁 V7(`tests/verify_replay_upload_retry.gd`)。
##
## ══════════════════════════════════════════════════════════════════════
##  为什么要队列(照 `finals_report_pending` 的样板, 但不是单槽)
## ══════════════════════════════════════════════════════════════════════
##   结算那一刻只有一次, 而那一刻可能没网 / 令牌刚过期 / 下一秒 App 被杀。
##   周六一天最多 6 场, 可能连着几场没网 ⇒ 必须是**队列**。
##   队列住在 `GameState.replay_upload_pending`(进本机存档, **不进云**: 录像文件只在这台设备上,
##   别的设备拿到这份单子也发不出去)。
##
##   一条单子 = {id, wk, acc, t, ls}:
##     id   录像 id = `matches.match_id`(uuid; 本地文件 user://replays/<id>.rpl)
##     wk   那一场的 `week_anchor_ts`(= `matches.season_week`)
##     acc  那一场打的时候的账号("" = 那时还没登录过)
##     t    入队时刻(只用于排序与日志)
##     ls   我方快照(`Backend.build_ghost_snapshot`, 结算那一刻取; 之后阵容会变)
##   录像本体**不进单子**: 它已经在 user://replays/ 里了, 发的时候现读 —— 不让存档背 4 KB × 6。
##
## ══════════════════════════════════════════════════════════════════════
##  销单只有两种
## ══════════════════════════════════════════════════════════════════════
##   ① 服务端回读到这一行、且录像逐字相同(`SupabaseNet.match_confirmed`)。2xx 不算。
##   ② **结构上永远发不出去**的: 录像文件没了 / 读不出 / 过了 U7 可见期 / 换了账号 / 太大。
##      留着它只会每次开主菜单都捶一下、永远捶不成(`retry_finals_report` 头注里点名的那种形状)。
##   没网 / 没令牌 / 服务端拒 ⇒ **留着**, 下次开主菜单再补。

const SB := preload("res://scripts/net/supabase.gd")
const BE := preload("res://scripts/net/backend.gd")
## ★录制器直接用它的 class_name `ReplayRecorder`, 不 preload: 录制器反过来 preload 本文件, 别造环。

## 队列上限。周六最多 6 场(4 胜或 3 负就停), 留一倍余量; 满了丢最旧的。
const QUEUE_MAX := 12
## U7: 重放只活周六~周一。`week_anchor_ts` 是那周周一 00:00 UTC ⇒ 可见期截止 = 下周二 00:00 = +8 天。
##   过了这一刻补上去也没人看得到(服务端每周二 00:00 UTC 清掉上周的(purge_old_matches)只是兜底)。
const VISIBLE_SEC := 8 * 86400
const WEEK_SEC := 7 * 86400
## 单子上的对局种类(= `matches.phase`)。
const PH_GAUNTLET := "gauntlet"
const PH_FINALS := "finals"
## 2026-10-05 用户改 Q3: 积分赛也录也传。服务端 `matches.phase` 没有约束 ⇒ 不用改表;
##   周六赛况板只查 `phase=eq.gauntlet`(`SupabaseNet.gauntlet_board_query`) ⇒ 积分赛的行混不进去。
const PH_RANKED := "ranked"
## base64 后的录像上限(字节)。★必须与 `server/supabase/schema.sql` 的 `matches_replay_size`
##   约束同一个数 —— 门禁 V7 逐字对过; 客户端先挡, 不让一条注定被服务端拒的单子永远留着。
const REPLAY_MAX_B64 := 65536
## 上传前从录像里摘掉的、**会让人认出对手是机器人**的字段(用户 2026-10-04「不能让玩家知道是机器人」)。
##   `matches` 任何登录用户都读得到 ⇒ 原样传 `dual_ghost.is_bot = true` / `ghost_id = "bot_…"` 就是露馅。
##   ★战斗场一个都不读(全仓 grep 过; 读者只有匹配屏), 而 V1 门禁播的正是摘过的这一份 ⇒ 摘了照样逐步一致。
const GHOST_STRIP := ["is_bot", "ghost_id"]
## (原 STATE_STRIP = ["recent_ghost_ids"]: 2026-10-04 录像瘦身后录像里只剩 `ReplayRecorder.STATE_KEYS`,
##   recent_ghost_ids 本来就不在里面; 上传前再按同一张表裁一遍, 管住瘦身之前录下、还在队列里的老录像。)

## 正在路上的 id(进程内)。同一条不并发发两次(主菜单来回进出会重入)。
static var _inflight: Dictionary = {}
## 本进程回读确认过几条(观测量, 门禁分母用)。
static var confirmed_count := 0


# ─────────────────────────────── 入队(结算那一刻) ───────────────────────────────

## `ReplayRecorder.on_settle` 存好本地录像之后调。**先**进队列(落盘由结算尾部那次 `save()` 带走), 再发。
static func enqueue(id: String) -> void:
	if GameState == null or id == "":
		return
	var q: Array = GameState.replay_upload_pending
	for e in q:
		if e is Dictionary and str((e as Dictionary).get("id", "")) == id:
			return
	var e := {
		"id": id,
		"wk": int(GameState.week_anchor_ts),
		"acc": str(GameState.account_id),
		"t": int(Time.get_unix_time_from_system()),
		"ls": my_snapshot(),
	}
	## 周末看回放(docs/plans/20261004-周末看回放.md): 单子记下「这是哪一种对局」。
	##   ★此刻在 `_settle_season` 第一行(`on_settle`)里: 闯关战绩还是**赛前**的、`finals_match` 还没清。
	var fm = GameState.get("finals_match")
	if fm is Dictionary and not (fm as Dictionary).is_empty():
		e["ph"] = PH_FINALS
		e["fk"] = {"b": int(fm.get("bucket", -1)), "r": int(fm.get("round", -1)),
			"m": int(fm.get("match", -1)), "s": int(fm.get("side", -1))}
	elif ReplayRecorder.current_settle_kind() == ReplayRecorder.Phase2Cfg.SETTLE_GAUNTLET:
		e["ph"] = PH_GAUNTLET
		e["gw0"] = int(GameState.gauntlet_wins)
		e["gl0"] = int(GameState.gauntlet_losses)
	else:
		e["ph"] = PH_RANKED          # 积分赛 / 表演赛: 不带闯关战绩
	q.append(e)
	while q.size() > QUEUE_MAX:
		var gone: Dictionary = q.pop_front()
		print("[Replay] 上传队列满, 丢掉最旧的一条 %s" % str(gone.get("id", "")))
	retry()


static func my_snapshot() -> Dictionary:
	var leaders = GameState.season_leaders
	var gid: String = BE.player_ghost_id(int(GameState.season_id), leaders, -1)
	var av := str(leaders[0]) if (leaders is Array and (leaders as Array).size() > 0) else "basic"
	return strip_ghost(BE.build_ghost_snapshot(gid, {"name": BE.player_display_name(), "avatar": av, "id": gid}))


# ─────────────────────────────── 补传(主菜单每次打开) ───────────────────────────────

## 过一遍队列: 结构上发不出去的销掉, 其余还没在路上的各发一次。
static func retry() -> void:
	if GameState == null:
		return
	var q: Array = GameState.replay_upload_pending
	if q.is_empty():
		return
	var now := int(Time.get_unix_time_from_system())
	var acc := str(GameState.account_id)
	var keep: Array = []
	var dropped := false
	for e in q:
		var why := drop_reason(e, now, acc)
		if why != "":
			print("[Replay] 上传单子销掉(发不出去): %s" % why)
			dropped = true
		else:
			keep.append(e)
	if dropped:
		GameState.replay_upload_pending = keep
		GameState.save()
	if acc == "":
		return                 # 还没有账号 ⇒ 这次不发, 单子留着(主菜单那一句 ensure_signed_in 会去建)
	for e in keep:
		var id := str((e as Dictionary).get("id", ""))
		if _inflight.has(id):
			continue
		## ★周日那一场**揭晓之前不发**(不剧透做在数据层: `matches` 现在谁都读得到 `result.won`)。
		##   单子留着; 对阵图拿到新数据时会再调 retry()。
		if not finals_upload_ready(e, now, _cached_buckets()):
			continue
		var row := build_row(e, ReplayRecorder.load_record(id), acc)
		if row.is_empty():
			continue
		## ★先标「在路上」再发: 令牌新鲜时整条路可能**同步**走完(回调先于这一行返回),
		##   后标的话回调里的 erase 早于这里的写入 ⇒ 这条单子永远卡在「在路上」, 再也不补(门禁 ⑦ 实测踩到)。
		_inflight[id] = true
		if not SB.upload_match_async(row, func(mid: String, ok: bool) -> void: _on_done(mid, ok)):
			_inflight.erase(id)


## "" = 这条还发得出去; 否则是销单原因(英文短码: 只进日志, 不是玩家文案)。纯判据(读一下本地录像文件在不在)。
static func drop_reason(e, now: int, acc: String) -> String:
	if not (e is Dictionary):
		return "not_dict"
	var d: Dictionary = e
	var id := str(d.get("id", ""))
	if not SB.is_uuid(id):
		return "bad_id:%s" % id
	var wk := int(d.get("wk", 0))
	if wk <= 0:
		return "no_week:%s" % id
	if now >= wk + VISIBLE_SEC:
		return "expired:%s" % id
	var a := str(d.get("acc", ""))
	if a != "" and acc != "" and a != acc:
		return "other_account:%s" % id
	var rec: Dictionary = ReplayRecorder.load_record(id)
	if rec.is_empty():
		return "no_local_file:%s" % id
	if upload_b64(rec).length() > REPLAY_MAX_B64:
		return "too_big:%s" % id
	return ""


## 回调: 只有回读确认了才销单。
static func _on_done(id: String, confirmed: bool) -> void:
	_inflight.erase(id)
	if not confirmed or GameState == null:
		return
	confirmed_count += 1
	var q: Array = GameState.replay_upload_pending
	for i in range(q.size()):
		if q[i] is Dictionary and str((q[i] as Dictionary).get("id", "")) == id:
			q.remove_at(i)
			GameState.save()
			return


# ─────────────────────────────── 拼行(纯函数) ───────────────────────────────

## 单子 + 本地录像 + 当前账号 → 要 POST 到 `matches` 的那一行。缺东西返回 {}(不填默认值)。
## ★`right_account` 恒为 null: 对手是真人还是机器人, 这一列一填就露馅(机器人没有账号);
##   而且快照里也没有可信的对手账号(拉对手快照时只取了 snapshot 列)。
static func build_row(e: Dictionary, rec: Dictionary, acc: String) -> Dictionary:
	if rec.is_empty() or acc == "":
		return {}
	var end: Dictionary = rec.get("end", {})
	var st: Dictionary = rec.get("state", {})
	var foe = st.get("dual_ghost", {})
	var surrendered := false
	for ev in rec.get("events", []):
		if ev is Dictionary and str((ev as Dictionary).get("k", "")) == "surrender":
			surrendered = true
	var won := bool(end.get("won", false))
	var result := {"won": won, "steps": int(end.get("s", 0)), "surrendered": surrendered}
	var ph := str(e.get("ph", PH_GAUNTLET))
	if ph == PH_FINALS:
		## 周日: 这一场在对阵图上的坐标。服务端 `finals_replay()` 按它 + `seed = finals_results.seed_used` 认出采纳那一份。
		var fk: Dictionary = e.get("fk", {}) if e.get("fk", {}) is Dictionary else {}
		result["fb"] = int(fk.get("b", -1))
		result["fr"] = int(fk.get("r", -1))
		result["fm"] = int(fk.get("m", -1))
	elif e.has("gw0"):
		## 周六: 这一局**打完之后**的战绩(赛况板拿它排名)。老单子没有赛前战绩 ⇒ 不写(赛况板退回数场次)。
		result["gw"] = int(e.get("gw0", 0)) + (1 if won else 0)
		result["gl"] = int(e.get("gl0", 0)) + (0 if won else 1)
	return {
		"match_id": str(e.get("id", "")),
		"season_week": int(e.get("wk", 0)),
		"phase": ph,
		"left_account": acc,
		"right_account": null,
		"seed": int(rec.get("seed", 0)),
		"left_snapshot": e.get("ls", {}) if e.get("ls", {}) is Dictionary else {},
		"right_snapshot": strip_ghost(foe if foe is Dictionary else {}),
		"result": result,
		"client_version": str(rec.get("client_version", "")),
		"replay": upload_b64(rec),
	}


## 周日单子能不能发了。**纯函数**(时钟与对阵数据都由调用方给, 门禁拿边界喂)。
##   不是周日单子 ⇒ 能。是 ⇒ 那一场已在某份对阵数据的 `done` 里(已揭晓), 或那一周已经过完(周日早结束了)。
## `buckets` = 本机缓存里的组(形状同 `SupabaseNet._bucket_from`, 带 `bucket` 与 `done`)。
static func finals_upload_ready(e, now: int, buckets: Array) -> bool:
	if not (e is Dictionary) or str((e as Dictionary).get("ph", "")) != PH_FINALS:
		return true
	var d: Dictionary = e
	if now >= int(d.get("wk", 0)) + WEEK_SEC:
		return true
	var fk: Dictionary = d.get("fk", {}) if d.get("fk", {}) is Dictionary else {}
	var key := "%d-%d" % [int(fk.get("r", -1)), int(fk.get("m", -1))]
	for b in buckets:
		if b is Dictionary and int((b as Dictionary).get("bucket", -2)) == int(fk.get("b", -1)) \
				and ((b as Dictionary).get("done", {}) as Dictionary).has(key):
			return true
	return false


## 本机手上的对阵数据: 我那一组(`finals_view`) + 观赛那几组(`finals_week_view`)。
static func _cached_buckets() -> Array:
	var out: Array = []
	var mine: Dictionary = SB.finals_cached()
	if mine.has("bucket"):
		out.append(mine)
	var wv: Dictionary = SB.finals_week_cached()
	for b in (wv.get("buckets", []) if wv.get("buckets", []) is Array else []):
		out.append(b)
	## 冠军杯赛那一张(2026-10-07): 杯里打完的那一场也要等它翻面才上传。
	var cup: Dictionary = SB.finals_cup_cached()
	if cup.has("bucket"):
		out.append(cup)
	return out


## 上传用的那一份录像(摘掉露馅字段) → base64。
static func upload_b64(rec: Dictionary) -> String:
	return Marshalls.raw_to_base64(ReplayRecorder.encode(for_upload(rec)))


## 上传用的副本: state 只留 `ReplayRecorder.STATE_KEYS`(持久装备只留上场统领的) + 对手快照摘掉 `GHOST_STRIP`。原件不动。
##   ★按表再裁一遍不是多余: 2026-10-04 瘦身之前录的录像装着几乎整份存档, 可能还在上传队列里。
static func for_upload(rec: Dictionary) -> Dictionary:
	var r: Dictionary = rec.duplicate(true)
	var st0: Dictionary = r.get("state", {})
	var st := {}
	for k in ReplayRecorder.STATE_KEYS:
		if st0.has(k):
			st[k] = st0[k]
	if st.get("persistent_equipped", null) is Dictionary:
		st["persistent_equipped"] = ReplayRecorder._fielded_equips(st["persistent_equipped"], st)
	if st.get("dual_ghost", null) is Dictionary:
		st["dual_ghost"] = strip_ghost(st["dual_ghost"])
	r["state"] = st
	return r


static func strip_ghost(g: Dictionary) -> Dictionary:
	var out: Dictionary = g.duplicate(true)
	for k in GHOST_STRIP:
		out.erase(k)
	return out
