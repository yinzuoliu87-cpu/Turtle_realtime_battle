extends RefCounted
## 周日决赛日「今天的事」的判据中心(2026-10-31 · 方案书 docs/plans/20261031c-周日赛事界面重做.md 块 M)。
## 主菜单决赛日卡 / 全局小条 / 30 秒弹窗 / 跑马灯 / 收盘补看 五处都从这里取同一个答案 —— 一件事只判一次
##   (memory fb-hand-rolled-copies-drift)。
##
## ★纯函数: 只吃组字典(`SupabaseNet._bucket_from` 的形状)+ 「现在」(服务端时钟, 调用方读一次传进来), 不碰网络 / 场景 / 静态状态。
## ★★不剧透: 一场的胜负只在它「已揭晓」之后才算数 —— 开播中 / 即将开播的那几场一律当没结果
##   (`visible_done`, 判据在 live_spectate.premiere_hidden, 与对阵图同一份)。
##   原来的试做直接读 `done` ⇒ 18:05 我那场还在开播, 主菜单已经写「已止步」。
## ★时刻全从 phase2_config 取(分组 FINALS_SEAT_HOUR_UTC / 冠军杯赛 FINALS_START_HOUR_UTC), 显示按设备时区(local_hhmm)。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _B := preload("res://scripts/gamedata/bracket.gd")
const _L := preload("res://scripts/gamedata/bracket_layout.gd")
const _LS := preload("res://scripts/systems/replay/live_spectate.gd")
const _PS := preload("res://scripts/systems/replay/premiere_schedule.gd")

## 今天走到哪一段(按时刻 + 已揭晓的赛果)。
const PH_PRE := "pre"        # 18:00 分组之前
const PH_GROUP := "group"    # 小组赛进行中
const PH_INTER := "inter"    # 各组都决出了, 等冠军杯赛开赛(FINALS_START_HOUR_UTC)
const PH_CUP := "cup"        # 冠军杯赛进行中
const PH_DONE := "done"      # 冠军杯赛已决出(已揭晓)

## 决赛日卡顶上那条状态带的三态(G14 / 2-2)。
const S3_COUNT := "countdown"
const S3_LIVE := "live"
const S3_END := "ended"

## 「我这一路」一格的状态(G15)。
const C_PENDING := "pending"   # 还没轮到
const C_NOW := "now"           # 正在备战 / 开播中 / 等开播(我的下一场就是这一格)
const C_WON := "won"
const C_LOST := "lost"
const C_BYE := "bye"           # 轮空直接晋级
const C_SKIP := "skip"         # 前面输了, 这一格不会再有

## 我的下一场此刻在哪一步。
const K_NONE := ""
const K_SHOP := "shop"         # 3 分钟备战中(阵容还能改)
const K_NEXT := "next"         # 下一轮备战还没开始(一场接一场: 上一轮其余几场还在播)
const K_WAIT := "wait"         # 备战结束, 服务器演算 / 等翻面
const K_UPCOMING := "upcoming" # 已排进档期, 还没开播(一场接一场)
const K_LIVE := "live"         # 开播中
const K_CUP_WAIT := "cup_wait" # 我拿下了小组, 等冠军杯赛成表

## 「不调整就沿用当前阵容」—— 服务端在玩家不调整时用 `finals_entrants.snapshot`(入座时那份, 备战里改阵容会更新它)。
const TXT_KEEP_LINEUP := "不调整就沿用当前阵容"


# ══════════════════════════════ 时刻 ══════════════════════════════

static func seat_ts(now: int) -> int:
	return _P2.finals_seat_ts(_P2.week_anchor_utc(now))


static func cup_ts(now: int) -> int:
	return _P2.week_anchor_utc(now) + 6 * 86400 + int(_P2.FINALS_START_HOUR_UTC) * 3600


## 今天是不是决赛日(UTC 周日 17:30 闯关赛收盘之后)。
static func is_finals_time(now: int) -> bool:
	return _P2.iso_weekday_utc(now) == 7 and _P2.phase_at_utc(now) == _P2.PHASE_FINALS


## 剩余秒 → 「1:05:09」/「4:07」(倒计时一律带秒走, 动起来)。`full` ⇒ 不满一小时也写「0:20:00」
##   (卡上子卡紧挨着「18:00」这种开赛时刻, 只写「20:00」分不清是时刻还是剩多久)。
static func clock_text(sec: int, full: bool = false) -> String:
	var s := maxi(0, sec)
	if s >= 3600 or full:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


# ══════════════════════════════ 一张图 ══════════════════════════════

## 此刻看得见的胜负(开播中 / 即将开播的那几场剔掉)。`now` = 服务端此刻。
static func visible_done(b: Dictionary, now: int) -> Dictionary:
	var out := {}
	var d = b.get("done", {})
	if not (d is Dictionary):
		return out
	for k in (d as Dictionary):
		var parts := str(k).split("-")
		if parts.size() != 2:
			continue
		if _LS.premiere_hidden(b, int(parts[0]), int(parts[1]), now):
			continue
		out[str(k)] = int(d[k])
	return out


## 这张图此刻(按已揭晓的)决出冠军了吗; 冠军是几号种子(-1 = 没有)。
static func champion_visible(b: Dictionary, now: int) -> int:
	var n := int(b.get("size", 0))
	if n < 1:
		return -1
	return _B.champion_seed(n, visible_done(b, now))


static func name_of(b: Dictionary, sd: int) -> String:
	var nm = b.get("names", [])
	if sd >= 0 and nm is Array and sd < (nm as Array).size():
		return str(nm[sd])
	return ""


static func tag_of(b: Dictionary, sd: int) -> String:
	var t = b.get("tags", [])
	if sd >= 0 and t is Array and sd < (t as Array).size():
		return str(t[sd])
	return ""


static func is_cup(b: Dictionary) -> bool:
	return int(b.get("bucket", -1)) == int(_P2.FINALS_CUP_BUCKET)


## 「C 组」/「冠军杯赛」。★组名唯一来源 ChampionData.group_name(主会话 10-31 定: 玩家可见的组名一律字母「A 组 / B 组 …」)。
static func sheet_name(b: Dictionary) -> String:
	if is_cup(b):
		return _P2.STAGE_CUP
	return ChampionData.group_name(int(b.get("bucket", 0)))


## 轮次名: 走对阵图那一份(bracket_layout.round_label), 对阵图改了这里跟着改。
static func round_name(n: int, r: int) -> String:
	return _L.round_label(n, r)


## 「冠军杯赛 · 半决赛」/「C 组 · 决赛」。
static func stage_line(b: Dictionary, r: int) -> String:
	return "%s · %s" % [sheet_name(b), round_name(int(b.get("size", 0)), r)]


## 第 r 轮第 m 场两边的名字(未定 = "")。按已揭晓的结果推(不剧透下一轮谁上来)。
static func pair_names(b: Dictionary, r: int, m: int, now: int) -> Array:
	var n := int(b.get("size", 0))
	var vd := visible_done(b, now)
	var out: Array = []
	for side in [0, 1]:
		out.append(name_of(b, _B.occupant_seed(r, m, side, n, vd)))
	return out


# ══════════════════════════════ 开播 ══════════════════════════════

## 这一场此刻开播中吗(一场接一场: 档期里; 老规则: 翻面窗口里)。
static func is_live(b: Dictionary, r: int, m: int, now: int) -> bool:
	if not (b.get("done", {}) as Dictionary).has("%d-%d" % [r, m]):
		return false
	return _LS.premiere_hidden(b, r, m, now) and not _LS.premiere_upcoming(b, r, m, now)


## 这张图此刻开播中的场次: [[r, m], ...]。
static func live_in(b: Dictionary, now: int) -> Array:
	var out: Array = []
	var n := int(b.get("size", 0))
	var r := _PS.flipped_round(b)
	if n < 2 or r < 1:
		return out
	for m in range(_B.matches_in_round(n, r)):
		if is_live(b, r, m, now):
			out.append([r, m])
	return out


## 这张图下一场(还没开播)的开播时刻; 0 = 没排上 / 老规则。返回 [开播, r, m] 或 []。
static func next_slot(b: Dictionary, now: int) -> Array:
	var r := _PS.flipped_round(b)
	if r < 1:
		return []
	for it in _PS.lineup(b, r):
		if int(it[1]) > now:
			return [int(it[1]), r, int(it[0])]
	return []


## 这张图下一次翻面(下一轮开播)大概是几点(服务端 next_at); 0 = 不知道。
static func flip_eta(b: Dictionary) -> int:
	var left := int(b.get("left", -1))
	var sn := int(b.get("srv_now", 0))
	if left < 0 or sn <= 0 or bool(b.get("closed", false)):
		return 0
	return sn + left


## 所有图(各组 + 冠军杯赛)里此刻开播中的: [{"b", "r", "m"}, ...]。冠军杯赛排最前(全服一路), 其余按组号。
static func live_all(groups: Array, cup: Dictionary, now: int) -> Array:
	var out: Array = []
	if not cup.is_empty():
		for rm in live_in(cup, now):
			out.append({"b": cup, "r": int(rm[0]), "m": int(rm[1])})
	for g in groups:
		if g is Dictionary:
			for rm in live_in(g, now):
				out.append({"b": g, "r": int(rm[0]), "m": int(rm[1])})
	return out


## 所有图里最早的下一场: {"b", "r", "m", "at"}; 没有 = {}。
static func next_all(groups: Array, cup: Dictionary, now: int) -> Dictionary:
	var best := {}
	var all: Array = groups.duplicate()
	if not cup.is_empty():
		all.push_front(cup)
	for g in all:
		if not (g is Dictionary):
			continue
		var s := next_slot(g, now)
		if s.is_empty():
			continue
		if best.is_empty() or int(s[0]) < int(best["at"]):
			best = {"b": g, "r": int(s[1]), "m": int(s[2]), "at": int(s[0])}
	return best


# ══════════════════════════════ 今天走到哪 ══════════════════════════════

## 各组都(按已揭晓的)决出冠军了吗。一组都没有 = false。
static func groups_done(groups: Array, now: int) -> bool:
	var k := 0
	for g in groups:
		if not (g is Dictionary) or int((g as Dictionary).get("size", 0)) < 1:
			continue
		k += 1
		if champion_visible(g, now) < 0:
			return false
	return k > 0


static func phase(now: int, groups: Array, cup: Dictionary) -> String:
	if now < seat_ts(now):
		return PH_PRE
	if not cup.is_empty() and champion_visible(cup, now) >= 0 and now >= cup_ts(now):
		return PH_DONE
	if now >= cup_ts(now):
		return PH_CUP
	if groups_done(groups, now):
		return PH_INTER
	return PH_GROUP


## 小组赛那张子卡此刻: S3_COUNT(还没开)/ S3_LIVE / S3_END。
static func group_state(now: int, groups: Array) -> String:
	if now < seat_ts(now):
		return S3_COUNT
	if groups_done(groups, now) or (now >= cup_ts(now) and groups.is_empty()):
		return S3_END
	return S3_LIVE


static func cup_state(now: int, cup: Dictionary) -> String:
	if now < cup_ts(now):
		return S3_COUNT
	if not cup.is_empty() and champion_visible(cup, now) >= 0:
		return S3_END
	return S3_LIVE


## 卡顶状态带: 有一段在打 ⇒ 进行中; 两段都完 ⇒ 已结束; 其余 = 开赛倒计时(数到下一段开始)。
static func state3(now: int, groups: Array, cup: Dictionary) -> String:
	var g := group_state(now, groups)
	var c := cup_state(now, cup)
	if g == S3_LIVE or c == S3_LIVE:
		return S3_LIVE
	if g == S3_END and c == S3_END:
		return S3_END
	return S3_COUNT


# ══════════════════════════════ 我这一路(G15) ══════════════════════════════

## 一张图里我第 r 轮那一格: [状态, 场号]。`me` < 0 或图是空的 ⇒ [C_PENDING, -1]。
static func _cell_in(b: Dictionary, r: int, now: int) -> Array:
	var n := int(b.get("size", 0))
	var me := int(b.get("me", -1))
	if n < 2 or me < 0:
		return [C_PENDING, -1]
	var vd := visible_done(b, now)
	## 前面已经输过 ⇒ 这一格不会再有
	for pr in range(1, r):
		for pm in range(_B.matches_in_round(n, pr)):
			var ps := _B.my_side_in(me, pr, pm, n, vd)
			if ps >= 0 and vd.has("%d-%d" % [pr, pm]) and int(vd["%d-%d" % [pr, pm]]) != ps:
				return [C_SKIP, -1]
	for m in range(_B.matches_in_round(n, r)):
		var side := _B.my_side_in(me, r, m, n, vd)
		if side < 0:
			continue
		var k := "%d-%d" % [r, m]
		if vd.has(k):
			return [C_WON if int(vd[k]) == side else C_LOST, m]
		if r == 1 and _B.occupant_seed(1, m, 1 - side, n, vd) == _B.OCC_BYE:
			return [C_BYE, m]
		return [C_NOW if r <= int(b.get("round", 1)) or bool(b.get("closed", false)) else C_PENDING, m]
	return [C_PENDING, -1]


## 「我这一路」: [{"sec": "group"|"cup", "label": 轮次名, "st": C_*, "r", "m"}, ...] —— 小组赛 + 冠军杯赛各轮, 尽头是奖杯(调用方画)。
## 没进决赛日 ⇒ []。冠军杯赛还没成表 ⇒ 按组数估几轮(6 组 ⇒ 8 签 3 轮), 全是 pending; 组里输了 ⇒ 杯那几格全 skip。
static func path_cells(entered: bool, group: Dictionary, cup: Dictionary, groups: Array, now: int) -> Array:
	var out: Array = []
	if not entered:
		return out
	var gn := int(group.get("size", 0))
	var g_total := _B.rounds_for(gn) if gn >= 2 else (0 if gn == 1 else 2)
	var g_lost := false
	for r in range(1, g_total + 1):
		var c: Array = _cell_in(group, r, now) if gn >= 2 else [C_PENDING, -1]
		if str(c[0]) == C_LOST or str(c[0]) == C_SKIP:
			g_lost = true
		out.append({"sec": "group", "label": round_name(gn if gn >= 2 else 4, r), "st": str(c[0]), "r": r, "m": int(c[1])})
	var cn := int(cup.get("size", 0))
	var est := cn
	if est < 2:
		est = maxi(2, groups.size()) if groups.size() >= 2 else 8
	var c_total := _B.rounds_for(est)
	var in_cup := cn >= 2 and int(cup.get("me", -1)) >= 0
	for r in range(1, c_total + 1):
		var st := C_PENDING
		var m := -1
		if g_lost:
			st = C_SKIP
		elif in_cup:
			var c2: Array = _cell_in(cup, r, now)
			st = str(c2[0])
			m = int(c2[1])
		elif cn == 1 and int(cup.get("me", -1)) == 0:
			st = C_WON
		out.append({"sec": "cup", "label": round_name(est, r), "st": st, "r": r, "m": m})
	return out


## 这一路走到头了吗: 1 = 夺冠, -1 = 止步, 0 = 还在路上。
static func path_end(cells: Array) -> int:
	if cells.is_empty():
		return 0
	for c in cells:
		if str(c["st"]) == C_LOST:
			return -1
	var last: Dictionary = cells[cells.size() - 1]
	return 1 if str(last["st"]) == C_WON else 0


# ══════════════════════════════ 我的下一场 ══════════════════════════════

## 我的下一场: {"k": K_*, "b": 那张图, "r", "m", "at": 关键时刻(开播 / 备战结束 / 冠军杯赛开赛), "opp": 对手名}; 没有 = {"k": K_NONE}。
static func my_next(entered: bool, group: Dictionary, cup: Dictionary, now: int) -> Dictionary:
	var none := {"k": K_NONE}
	if not entered:
		return none
	var b: Dictionary = {}
	if int(cup.get("size", 0)) >= 2 and int(cup.get("me", -1)) >= 0:
		b = cup
	elif int(group.get("size", 0)) >= 2 and int(group.get("me", -1)) >= 0:
		b = group
	if b.is_empty():
		return none
	var n := int(b.get("size", 0))
	var me := int(b.get("me", -1))
	var vd := visible_done(b, now)
	for r in range(1, _B.rounds_for(n) + 1):
		for m in range(_B.matches_in_round(n, r)):
			var side := _B.my_side_in(me, r, m, n, vd)
			if side < 0:
				continue
			var k := "%d-%d" % [r, m]
			if vd.has(k):
				if int(vd[k]) != side:
					return none                       # 输了: 没有下一场
				continue
			if r == 1 and _B.occupant_seed(1, m, 1 - side, n, vd) == _B.OCC_BYE:
				continue                              # 轮空: 直接看下一轮
			var opp_sd := _B.occupant_seed(r, m, 1 - side, n, vd)
			var base := {"b": b, "r": r, "m": m, "opp": name_of(b, opp_sd), "opp_sd": opp_sd, "me_sd": me}
			if (b.get("done", {}) as Dictionary).has(k):
				## 已翻面、还没揭晓 ⇒ 即将开播 / 开播中
				if _LS.premiere_upcoming(b, r, m, now):
					base["k"] = K_UPCOMING
					base["at"] = _PS.start_of(b, r, m)
				else:
					base["k"] = K_LIVE
					base["at"] = _PS.start_of(b, r, m) if _PS.start_of(b, r, m) > 0 else _LS.flip_ts_of(b)
				return base
			if r > int(b.get("round", 1)):
				return none                           # 上一轮还没揭晓(不该到这里), 不猜
			if _P2.finals_shop_open(int(b.get("round_at", 0)), now):
				base["k"] = K_SHOP
				base["at"] = int(b.get("round_at", 0)) + int(_P2.FINALS_SHOP_SEC)
				return base
			if int(b.get("round_at", 0)) > now:
				## 一场接一场: 下一轮备战还没开始(上一轮还在播)
				base["k"] = K_NEXT
				base["at"] = int(b.get("round_at", 0))
				return base
			base["k"] = K_WAIT
			base["at"] = flip_eta(b)
			return base
	## 我那张图打完了: 小组赛拿下了 ⇒ 等冠军杯赛
	if is_same(b, group) and champion_visible(group, now) == me and int(cup.get("me", -1)) < 0:
		return {"k": K_CUP_WAIT, "b": group, "r": 0, "m": -1, "at": cup_ts(now), "opp": ""}
	return none


# ══════════════════════════════ 名次(G21 收盘补看) ══════════════════════════════

## 一个人在一张图里走到的深度值(决赛 = 0 往下数, 越大越好): 冠军 +5。
static func _depth_val(b: Dictionary, sd: int, now: int) -> int:
	var n := int(b.get("size", 0))
	if n <= 1:
		return 100 + 5
	var pg: Dictionary = _B.my_progress(sd, n, visible_done(b, now))
	var total := int(pg.get("total", 0))
	var deepest := int(pg.get("deepest", 0))
	return 100 - 10 * (total - deepest) + (5 if bool(pg.get("champion", false)) else 0)


## 本周名次表: [{"acc", "name", "tag", "v", "rank"}, ...] 按名次排。冠军杯赛的人 +1000(进了杯一律在组里止步的人前面)。
## 冠军杯赛没决出 ⇒ []。
static func standings(groups: Array, cup: Dictionary, now: int) -> Array:
	if cup.is_empty() or champion_visible(cup, now) < 0:
		return []
	var rows: Dictionary = {}
	for g in groups:
		if not (g is Dictionary):
			continue
		var n := int((g as Dictionary).get("size", 0))
		var accs = (g as Dictionary).get("accs", [])
		for sd in range(n):
			var acc := str(accs[sd]) if accs is Array and sd < (accs as Array).size() else ""
			var key := acc if acc != "" else "g%d:%d" % [int(g.get("bucket", 0)), sd]
			rows[key] = {"acc": acc, "name": name_of(g, sd), "tag": tag_of(g, sd), "v": _depth_val(g, sd, now)}
	var cn := int(cup.get("size", 0))
	var caccs = cup.get("accs", [])
	for sd in range(cn):
		var acc := str(caccs[sd]) if caccs is Array and sd < (caccs as Array).size() else ""
		var key := acc if acc != "" else "c:%d" % sd
		rows[key] = {"acc": acc, "name": name_of(cup, sd), "tag": tag_of(cup, sd), "v": 1000 + _depth_val(cup, sd, now)}
	var out: Array = rows.values()
	out.sort_custom(func(a, b2): return int(a["v"]) > int(b2["v"]))
	for row in out:
		var better := 0
		for o in out:
			if int(o["v"]) > int(row["v"]):
				better += 1
		row["rank"] = better + 1
	return out


## 名次 → 「第 1 名」/「并列第 3 名」。
static func rank_text(rank: int, rows: Array) -> String:
	var same := 0
	for o in rows:
		if int(o["rank"]) == rank:
			same += 1
	return ("并列第 %d 名" if same > 1 else "第 %d 名") % rank


## 我这一周打过的几场(已揭晓): [{"b", "r", "m", "label", "opp", "won", "score"}, ...]。
static func my_matches(group: Dictionary, cup: Dictionary, now: int) -> Array:
	var out: Array = []
	for b in [group, cup]:
		var n := int((b as Dictionary).get("size", 0))
		var me := int((b as Dictionary).get("me", -1))
		if n < 2 or me < 0:
			continue
		var vd := visible_done(b, now)
		for r in range(1, _B.rounds_for(n) + 1):
			for m in range(_B.matches_in_round(n, r)):
				var side := _B.my_side_in(me, r, m, n, vd)
				var k := "%d-%d" % [r, m]
				if side < 0 or not vd.has(k):
					continue
				var sc = (b as Dictionary).get("scores", {})
				out.append({"b": b, "r": r, "m": m, "label": stage_line(b, r),
					"opp": name_of(b, _B.occupant_seed(r, m, 1 - side, n, vd)), "won": int(vd[k]) == side,
					"score": int((sc as Dictionary).get(k, -1)) if sc is Dictionary else -1})
	return out


# ══════════════════════════════ 跑马灯(G16 / 8-1) ══════════════════════════════

## 此刻成立的「事」: {键: 一句话}。调用方前后两拍比, 新出现的键才播(开屏那一拍只当底, 不把已发生的刷一遍)。
## ★只收服务端下发的真东西: 已揭晓的赛果、排进档期的开播时刻、开赛时刻(常量)。拿不到的不编。
## `mine` = 我那一组的组号(-1 = 没进 / 观众): 小组赛只播组冠军 + 我那一组的晋级与开播, 6 组同时打不刷屏。
static func facts(groups: Array, cup: Dictionary, now: int, mine: int) -> Dictionary:
	var out := {}
	## 开赛前 10 分钟: 「冠军杯赛 20:00 开赛」(时刻是常量, 不是编的)
	if now >= seat_ts(now) - 600 and now < seat_ts(now):
		out["start:g"] = "%s %s 开赛" % [_P2.STAGE_GROUP, _P2.local_hhmm(seat_ts(now))]
	if now >= cup_ts(now) - 600 and now < cup_ts(now):
		out["start:c"] = "%s %s 开赛" % [_P2.STAGE_CUP, _P2.local_hhmm(cup_ts(now))]
	var all: Array = groups.duplicate()
	if not cup.is_empty():
		all.push_front(cup)
	var gw := {}                    # 观众: 同一轮同一刻开播的组(「轮@开播时刻」→ [轮次名, {组号}])
	for b in all:
		if not (b is Dictionary):
			continue
		var bd: Dictionary = b
		var n := int(bd.get("size", 0))
		if n < 2:
			continue
		var cupb := is_cup(bd)
		var minec := int(bd.get("bucket", -2)) == mine
		var total := _B.rounds_for(n)
		var vd := visible_done(bd, now)
		var bk := int(bd.get("bucket", 0))
		## 赛果(已揭晓才算)
		for k in vd:
			var r := int(str(k).get_slice("-", 0))
			var m := int(str(k).get_slice("-", 1))
			var w := _B.occupant_seed(r, m, int(vd[k]), n, vd)
			var wn := name_of(bd, w)
			if wn == "":
				continue
			if r == total:
				if cupb:
					out["res:%d:%s" % [bk, k]] = "%s 夺得%s冠军" % [wn, _P2.STAGE_CUP]
				else:
					out["res:%d:%s" % [bk, k]] = "%s 夺得 %s冠军，晋级%s" % [wn, sheet_name(bd), _P2.STAGE_CUP]
			elif cupb or minec:
				out["res:%d:%s" % [bk, k]] = ("%s 晋级%s%s" if cupb else "%s 晋级 %s%s") % [wn, sheet_name(bd), round_name(n, r + 1)]
		## 开播(只收冠军杯赛 + 我那一组; 观众另有一句「小组赛 半决赛开播 · N 组同时进行」, 见循环后)
		if not (cupb or minec):
			if mine < 0 and not cupb:
				var gr := _PS.flipped_round(bd)
				for it0 in _PS.lineup(bd, gr):
					if now >= int(it0[1]) and now < int(it0[2]):
						var gk := "%d@%d" % [gr, int(it0[1])]
						if not gw.has(gk):
							gw[gk] = [round_name(n, gr), {}]
						(gw[gk][1] as Dictionary)[bk] = true
			continue
		var fr := _PS.flipped_round(bd)
		if fr < 1:
			continue
		## ★同一开播时刻的几场并成一句(用户 10-31 纠正: 小组赛同一轮所有场同时开播); 只有开播时刻不止一个(冠军杯赛一场接一场)
		##   才说「第 k 场」。开播时刻 / 揭晓时刻都按服务端档期, 不按赛制猜。
		var ln := _PS.lineup(bd, fr)
		var waves: Array = []           # [[开播, 最晚揭晓, [场号…]], …] 按开播先后
		for it in ln:
			if waves.is_empty() or int(waves[waves.size() - 1][0]) != int(it[1]):
				waves.append([int(it[1]), int(it[2]), [int(it[0])]])
			else:
				var wv: Array = waves[waves.size() - 1]
				wv[1] = maxi(int(wv[1]), int(it[2]))
				(wv[2] as Array).append(int(it[0]))
		for i in range(waves.size()):
			var wv: Array = waves[i]
			var which := round_name(n, fr) if waves.size() == 1 else "%s 第 %d 场" % [round_name(n, fr), i + 1]
			var who := ""
			if (wv[2] as Array).size() == 1:
				var pr := pair_names(bd, fr, int(wv[2][0]), now)
				who = "%s 对 %s" % [pr[0], pr[1]] if str(pr[0]) != "" and str(pr[1]) != "" else ""
			if now < int(wv[0]):
				out["up:%d:%d@%d" % [bk, fr, int(wv[0])]] = "%s %s %s 开播" % [sheet_name(bd), which, _P2.local_hhmm(int(wv[0]))]
			elif now < int(wv[1]):
				out["live:%d:%d@%d" % [bk, fr, int(wv[0])]] = "%s %s开播%s" % [sheet_name(bd), which, ("：" + who) if who != "" else ""]
	## 观众: 各组同一轮同时开播 ⇒ 一句「小组赛 半决赛开播 · 6 组同时进行」(不逐组刷屏)
	for gk in gw:
		var nb := (gw[gk][1] as Dictionary).size()
		out["gwave:%s" % gk] = "%s %s开播%s" % [_P2.STAGE_GROUP, str(gw[gk][0]), (" · %d 组同时进行" % nb) if nb > 1 else ""]
	return out
