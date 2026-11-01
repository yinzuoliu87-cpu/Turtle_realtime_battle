class_name BracketInfo
extends RefCounted
## bracket_info.gd —— 对阵图各块要说的「话」与要摆的「数」(2026-10-31 · 方案书 docs/plans/20261031c-周日赛事界面重做.md §4 B 行)
##
## 只算、不画: 处境句 / 主按钮 / 下一场 / 我这一路 / 名牌墙 / 备战屏 / 宫格 / 来历标签 / 冠军收盘数据 … 都从这里取,
## 画在 `bracket_hero.gd`(对阵本体)、`bracket_chrome.gd`(固定件)、`bracket_stage.gd`(过场)。
## ★判定一律走场景已有的那一份(match_state / winner_side / competitor / premiere_*), 开播档期一律走
##   `premiere_schedule.gd`(S 分身的地盘, 这里只读) —— 这里一个胜负 / 开播条件都不自己再算一遍。
## ★别的组(宫格 / 我这一路的冠军杯段)不在 `cur()` 里: 用同一套纯函数(`_B.occupant_seed` / `_LS.premiere_hidden`)喂那一组的字典。

const _B := preload("res://scripts/gamedata/bracket.gd")
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const _LS := preload("res://scripts/systems/replay/live_spectate.gd")
const _PS := preload("res://scripts/systems/replay/premiere_schedule.gd")
const _H := preload("res://scripts/scenes/bracket/bracket_hero.gd")
const _CD := preload("res://scripts/scenes/bracket/champion_data.gd")
const _M := preload("res://scripts/ui/finals_day_model.gd")
const _FC := preload("res://scripts/ui/finals_copy.gd")

var s
## 本次运行里见过「决赛还没揭晓」的那几张图(只有亲眼等到揭晓才算「那一刻」; 开屏就是收盘的不算)、已经报过的那几张。
static var champ_waiting: Dictionary = {}
static var champ_fired: Dictionary = {}


func _init(scene) -> void:
	s = scene


# ═══════════════════════════════════════════════════════════════════
#  时钟 / 写法
# ═══════════════════════════════════════════════════════════════════
## 任一组的服务端此刻(与场景 `srv_now()` 同一条纪律: 收包时服务端的钟 + 本机过了多久)。
func srv_now_of(b: Dictionary) -> int:
	if int(s._now_override) > 0:
		return int(s._now_override)
	var sn := int(b.get("srv_now", 0))
	var ra := int(b.get("recv_at", 0))
	if sn > 0 and ra > 0:
		return sn + (int(s._delta_now()) - ra)
	return int(_P2C.now_utc())


## 大倒计时(⑫ 开赛前那一块): 「1 小时 32 分 05 秒」/「23 分 15 秒」(全决赛日同一种写法 `finals_copy.dur`)。
static func big_countdown(sec: int) -> String:
	if sec <= 0:
		return "即将开始"
	return _FC.dur(sec)


func cup_start_hhmm() -> String:
	return _P2C.local_hhmm(int(s._cup_start_ts()))


# ═══════════════════════════════════════════════════════════════════
#  标题 / 列 / 冠军位
# ═══════════════════════════════════════════════════════════════════
func is_cup() -> bool:
	return str(s._view) == "finals"


func hero_title() -> String:
	if is_cup():
		return _P2C.STAGE_CUP
	if bool(s._grid_on):
		return "全部小组"
	var c: Dictionary = s.cur()
	if int(c.get("size", 0)) >= 1 and int(c.get("bucket", -1)) >= 0:
		return "%s %s" % [_P2C.STAGE_GROUP, s.sheet_name(c)]
	return _P2C.STAGE_GROUP


func champion_title() -> String:
	return "冠军" if is_cup() else "%s冠军" % s.sheet_name(s.cur())


## 冠军位下面那一行: 冠军拿什么(一件事)。★2026-11-01: 原来「组冠军得「组冠军」头衔 · 每轮 +8 深海币」——
##   后半句是**每个参赛者**每轮都有的(FINALS_COINS_PER_ROUND 不看输赢), 拼在冠军那一行读成冠军专属; 它在每场结束的
##   「本轮奖励」里另有一拍。⇒ 这里只写冠军奖励。
func reward_line() -> String:
	var t := _P2C.TITLE_CHAMPION if is_cup() else _P2C.TITLE_GROUP_CHAMPION
	return _FC.kv("冠军奖励", "「%s」头衔" % str(_P2C.TITLE_LABEL.get(t, "")))


## 哪一列标题点亮(C02): 正在一场接一场开播的那一轮; 没有在播的 = 当前轮。收盘 = 不点。
func title_round() -> int:
	var c: Dictionary = s.cur()
	if bool(c.get("closed", false)) and live_rm().x < 0:
		return -1
	var lr := live_rm()
	if lr.x >= 1:
		return lr.x
	var up := upcoming_rm()
	if up.x >= 1:
		return up.x
	return int(c.get("round", 1))


func podium_on() -> bool:
	if not is_cup():
		return false
	var c: Dictionary = s.cur()
	var n := int(c.get("size", 0))
	if n < 2 or not bool(c.get("closed", false)):
		return false
	return int(s.winner_side(_B.rounds_for(n), 0)) >= 0


## 领奖台: {1: [冠军], 2: [亚军], 3: [四强…]}(单败没有三四名决赛 ⇒ 两位四强并列第 3 台)。
func podium_places() -> Dictionary:
	var c: Dictionary = s.cur()
	var n := int(c.get("size", 0))
	var total := _B.rounds_for(n)
	var ws := int(s.winner_side(total, 0))
	if ws < 0:
		return {}
	var out := {1: [s.competitor(total, 0, ws)], 2: [s.competitor(total, 0, 1 - ws)]}
	var thirds: Array = []
	if total >= 2:
		for m in range(_B.matches_in_round(n, total - 1)):
			var w := int(s.winner_side(total - 1, m))
			if w < 0:
				continue
			var lo: Dictionary = s.competitor(total - 1, m, 1 - w)
			if int(lo.get("seed", -1)) >= 0 and not bool(lo.get("bye", false)):
				thirds.append(lo)
	if not thirds.is_empty():
		out[3] = thirds
	return out


## 来历标签(⑦ · 1-14): 冠军杯赛里每位选手是哪一组的冠军; 上周冠军另标「卫冕」。小组赛 = ""。
func origin_label(sd: int) -> String:
	if not is_cup() or sd < 0:
		return ""
	var c: Dictionary = s.cur()
	var accs: Array = c.get("accs", []) if c.get("accs", []) is Array else []
	var acc := str(accs[sd]) if sd < accs.size() else ""
	if acc == "":
		return ""
	var out := ""
	for b in s._champ_buckets():
		var bd: Dictionary = b
		var cs := int(s.champion_seed(bd))
		var ba: Array = bd.get("accs", []) if bd.get("accs", []) is Array else []
		if cs >= 0 and cs < ba.size() and str(ba[cs]) == acc:
			out = "%s冠军" % _CD.group_name(int(bd.get("bucket", 0)))
			break
	if str(s.defending_acc) != "" and str(s.defending_acc) == acc:
		out = (out + "（卫冕）") if out != "" else "卫冕冠军"
	return out


# ═══════════════════════════════════════════════════════════════════
#  在播 / 即将开播(只读场景的状态)
# ═══════════════════════════════════════════════════════════════════
func live_rm() -> Vector2i:
	var c: Dictionary = s.cur()
	var n := int(c.get("size", 0))
	var mine := Vector2i(-1, -1)
	var first := Vector2i(-1, -1)
	for r in range(1, _B.rounds_for(n) + 1):
		for m in range(_B.matches_in_round(n, r)):
			if str(s.match_state(r, m)) == str(s.ST_PREMIERE):
				if first.x < 0:
					first = Vector2i(r, m)
				if bool(s.is_my_match(r, m)):
					mine = Vector2i(r, m)
	return mine if mine.x >= 0 else first


func upcoming_rm() -> Vector2i:
	var c: Dictionary = s.cur()
	var fr := _PS.flipped_round(c)
	if fr < 1:
		return Vector2i(-1, -1)
	var now := int(s.srv_now())
	for it in _PS.lineup(c, fr):
		if now < int(it[1]):
			return Vector2i(fr, int(it[0]))
	return Vector2i(-1, -1)


## 第 r 轮此刻开播中(能点开)的场数。
func live_count(r: int) -> int:
	var c: Dictionary = s.cur()
	var k := 0
	for m in range(_B.matches_in_round(int(c.get("size", 0)), r)):
		if str(s.match_state(r, m)) == str(s.ST_PREMIERE) and bool(s.can_open(r, m)):
			k += 1
	return k


## 一场接一场里这一场是第几场(1 起); 不在档期里 = 0。
## ★小组赛同一轮同时开播(S 10-31 改: `PremiereSchedule.together`)⇒ 没有「第 k 场」的先后, 返回 0(只写轮名)。
func seq_index(r: int, m: int) -> int:
	var ln := _PS.lineup(s.cur(), r)
	if _PS.together(ln):
		return 0
	for i in range(ln.size()):
		if int(ln[i][0]) == m:
			return i + 1
	return 0


## 「半决赛第 1 场」/「决赛」/「半决赛」
func match_label(r: int, m: int) -> String:
	var n := int(s.cur().get("size", 0))
	var rn := _H.round_name(n, r)
	if r >= _B.rounds_for(n):
		return rn
	var k := seq_index(r, m)
	return "%s第 %d 场" % [rn, k] if k > 0 else rn


## 观战那一侧的两张名牌(C 块 `FinalsCtx` 的 cards): 冠军杯里写他是哪一组的冠军(组号从 0 起)、上周冠军挂「卫冕」。小组赛 = []。
func cards_for(r: int, m: int) -> Array:
	if not is_cup():
		return []
	var c: Dictionary = s.cur()
	var accs: Array = c.get("accs", []) if c.get("accs", []) is Array else []
	var out: Array = []
	for side in [0, 1]:
		var sd := int(s.competitor(r, m, side).get("seed", -1))
		var acc := str(accs[sd]) if sd >= 0 and sd < accs.size() else ""
		var card := {}
		for b in s._champ_buckets():
			var bd: Dictionary = b
			var cs := int(s.champion_seed(bd))
			var ba: Array = bd.get("accs", []) if bd.get("accs", []) is Array else []
			if acc != "" and cs >= 0 and cs < ba.size() and str(ba[cs]) == acc:
				card["group"] = int(bd.get("bucket", 0))
		if acc != "" and str(s.defending_acc) == acc:
			card["title"] = "卫冕"
		out.append(card)
	return out


## 判负(坏快照)那一场(S 子方案书 §4.4 第 10 条): 一场接一场的组里「有结果、没有档期、不是轮空」= 服务端判的, 没有录像。
##   老规则(没有 seq)认不出来 ⇒ 恒 false。
func is_forfeit(r: int, m: int) -> bool:
	var c: Dictionary = s.cur()
	if not _PS.is_seq(c):
		return false
	if not (c.get("done", {}) as Dictionary).has("%d-%d" % [r, m]):
		return false
	if bool(s.competitor(r, m, 0).get("bye", false)) or bool(s.competitor(r, m, 1).get("bye", false)):
		return false
	return _PS.slot(c, r, m).is_empty() and r <= _PS.flipped_round(c)


## 卡顶左边那一句。★只翻译场景判好的状态。
## ★2026-11-01: 原来决赛卡写「决赛 · 等待中」「决赛 · 已结束」、即将开播写「第 2 场 · 2 分 25 秒后」(一行两件事)。
##   ⇒ 左边只写一件事: 决赛卡 =「决赛」(状态挪到右边 `card_head_state`), 其余卡 = 状态; 即将开播 = 开播时刻(右边有「即将开播」签)。
func card_head_text(r: int, m: int) -> String:
	var c: Dictionary = s.cur()
	var n := int(c.get("size", 0))
	var total := _B.rounds_for(n)
	var fin := r >= total
	var st := str(s.match_state(r, m))
	## 轮空那一场服务端也补一行 done(side 0) ⇒ match_state 会说「已结束」; 卡顶照实写「轮空」
	if st == str(s.ST_BYE) or bool(s.competitor(r, m, 0).get("bye", false)) or bool(s.competitor(r, m, 1).get("bye", false)):
		return "轮空"
	var k := seq_index(r, m)
	var who := ("第 %d 场" % k) if (k > 0 and not fin) else ("决赛" if fin else _H.round_name(n, r))
	if st == str(s.ST_UPCOMING):
		return "%s %s 开播" % [who, _FC.at(_PS.start_of(c, r, m))]
	if fin or st == str(s.ST_PREMIERE):
		return who
	return card_status_word(r, m)


## 决赛卡右边那个状态词(左边写了「决赛」); 不是决赛 / 开播中 / 即将开播 / 轮空 = ""(那几种左边已经说了或有签)。
func card_head_state(r: int, m: int) -> String:
	var n := int(s.cur().get("size", 0))
	if r < _B.rounds_for(n):
		return ""
	var st := str(s.match_state(r, m))
	if st == str(s.ST_PREMIERE) or st == str(s.ST_UPCOMING) or st == str(s.ST_BYE):
		return ""
	return card_status_word(r, m)


## 一场此刻的状态词(2~4 字, 商业游戏状态签那一种): 已结束 / 判负 / 等待中 / 备战中 / 结算中 / 等待开播。
func card_status_word(r: int, m: int) -> String:
	var c: Dictionary = s.cur()
	var st := str(s.match_state(r, m))
	if st == str(s.ST_DONE):
		return "判负" if is_forfeit(r, m) else "已结束"
	if st == str(s.ST_LIVE):
		var ra := int(c.get("round_at", 0))
		var now := int(s.srv_now())
		if _PS.before_shop(c, now):
			return "等待中"     # 上一轮还在一场接一场地播
		if ra > 0 and _P2C.finals_shop_open(ra, now):
			return "备战中"
		if _PS.settling(c, now):
			return "结算中"
		return "等待开播"
	return "等待中"


# ═══════════════════════════════════════════════════════════════════
#  ⑥ 一句我的处境(P3 · S 清单第 3 / 4 / 9 条)
# ═══════════════════════════════════════════════════════════════════
## ★2026-11-01 改写(用户「作为玩家看到的东西是什么呢？…一定要按照商业游戏的口吻」):
##   原来一行拼三件事(「观战 · A 组 · 半决赛备战中」「你的半决赛 · 对手 Kiki · 备战中」「你止步半决赛 · 可继续观看其他对局」)。
##   ⇒ 这一行只说**一件事**(是什么 / 几点), 倒计时归下一行 `tip_line()`, 动作归主按钮。
##   观众不加「观战 · A 组」前缀(缎带上已经写着在看哪一组; 旁观视角写第三人称, Dota「{轮次}的比赛正在进行中。」)。
##   时刻全从 `next_premiere()` / `_PS.start_of` 出 —— 与底部「下一场」卡、全局小条同一份。
func hero_status_line() -> String:
	if bool(s._grid_on) and not is_cup():
		var lv := 0
		for b in s._spectate_list():
			if group_live_rm(b).x >= 0:
				lv += 1
		return ("%d 个小组开播中" % lv) if lv > 0 else "选择小组查看对阵"
	var c: Dictionary = s.cur()
	var n := int(c.get("size", 0))
	if n < 2:
		return ""
	var total := _B.rounds_for(n)
	var me := int(c.get("me", -1))
	var where: String = _P2C.STAGE_CUP if is_cup() else str(s.sheet_name(c))
	var cws := int(s.winner_side(total, 0))
	if cws >= 0:
		var champ: Dictionary = s.competitor(total, 0, cws)
		if me >= 0 and int(champ.get("seed", -1)) == me:
			return ("你获得%s冠军！" if is_cup() else "你获得 %s冠军！") % where
		if is_cup():
			return "%s已结束" % _P2C.STAGE_CUP
		return _FC.kv("%s冠军" % where, str(champ.get("name", "")))
	var lr := live_rm()
	var now := int(s.srv_now())
	var ra := int(c.get("round_at", 0))
	var shop: bool = ra > 0 and _P2C.finals_shop_open(ra, now) and not _PS.before_shop(c, now)
	if me < 0:
		var nlive := live_count(lr.x) if lr.x >= 1 else 0
		if nlive >= 2:
			return "%s %d 场开播中" % [_H.round_name(n, lr.x), nlive]     # 小组赛同一轮同时开播: 真实的 N
		if lr.x >= 1:
			return "%s开播中" % match_label(lr.x, lr.y)
		if shop:
			return "%s备战中" % _H.round_name(n, int(c.get("round", 1)))
		## 上一轮播完、下一轮备战还没开始(一场接一场): 说下一轮几点开始备战(那是定了的时刻; 开播时刻要等演算)
		if _PS.before_shop(c, now) and ra > now and upcoming_rm().x < 0:
			return "%s备战 %s 开始" % [_H.round_name(n, mini(int(c.get("round", 1)), total)), _FC.at(ra)]
		var eta := next_premiere()
		if not eta.is_empty():
			return "%s %s 开播" % [eta_label(eta), _FC.at(int(eta["at"]))]
		if _PS.settling(c, now):
			return "%s即将开播" % _H.round_name(n, mini(int(c.get("round", 1)), total))
		return ""
	## 我出局了
	for r in range(1, total + 1):
		for m in range(_B.matches_in_round(n, r)):
			var ws := int(s.winner_side(r, m))
			if ws >= 0 and bool(s._is_me_side(r, m, 1 - ws)) and not bool(s.competitor(r, m, ws).get("bye", false)):
				return _FC.join("你止步", _H.round_name(n, r))
	## 我首轮轮空(本轮还在播)
	var up := upcoming_rm()
	for m2 in range(_B.matches_in_round(n, 1)):
		if bool(s.is_my_match(1, m2)) and (bool(s.competitor(1, m2, 0).get("bye", false)) or bool(s.competitor(1, m2, 1).get("bye", false))):
			if int(c.get("round", 1)) <= 2 and (lr.x == 1 or up.x == 1 or (int(c.get("round", 1)) == 1)):
				return _FC.join("首轮轮空，直接晋级", _H.round_name(n, 2))
	var f: Vector2i = s.my_focus()
	if f.x < 1:
		return ""
	var rn := _H.round_name(n, f.x)
	var st := str(s.match_state(f.x, f.y))
	if st == str(s.ST_PREMIERE):
		return _FC.join("你的", rn) + "开播中"
	if st == str(s.ST_UPCOMING):
		return "%s %s 开播" % [_FC.join("你的", rn), _FC.at(_PS.start_of(c, f.x, f.y))]
	var a: Dictionary = s.competitor(f.x, f.y, 0)
	var b: Dictionary = s.competitor(f.x, f.y, 1)
	var foe: Dictionary = b if int(a.get("seed", -1)) == me else a
	if int(foe.get("seed", -1)) < 0:
		return _FC.join("你已晋级", rn)
	return _FC.kv(_FC.join("你的", rn) + "对手", str(foe.get("name", "")))


## ★★这一屏「下一次开播」的唯一答案: 正在看的那张图 → `FinalsDayModel.premiere_eta`(全局小条 / 主菜单同一个函数)。
func next_premiere() -> Dictionary:
	return _M.premiere_eta(s.cur(), int(s.srv_now()))


## 「半决赛第 2 场」(知道是哪一场)/「半决赛」(还没翻面, 只知道是哪一轮)。
func eta_label(eta: Dictionary) -> String:
	var r := int(eta.get("r", 1))
	if int(eta.get("m", -1)) >= 0:
		return match_label(r, int(eta["m"]))
	return _H.round_name(int(s.cur().get("size", 0)), r)


## 处境句下面那一行: **只放倒计时**, 前面一个固定说法(「备战剩余」「距开播」)。`""` = 不出现。
## ★倒计时与处境句 / 底部卡 / 全局小条同一个时刻来源 —— 原来这一行写「下一轮 3 分 0 秒后开播」(第 1 轮也叫「下一轮」),
##   主按钮又把同一句写一遍, 底部卡写「约 18:03」(备战结束时刻, 18:05 时已经过去)。
func tip_line() -> String:
	if bool(s._grid_on) and not is_cup():
		return ""
	var c: Dictionary = s.cur()
	var n := int(c.get("size", 0))
	if n < 2 or bool(c.get("closed", false)) and live_rm().x < 0 and upcoming_rm().x < 0:
		return ""
	var now := int(s.srv_now())
	var ra := int(c.get("round_at", 0))
	if ra > 0 and _P2C.finals_shop_open(ra, now) and not _PS.before_shop(c, now):
		## 备战屏开着(它自己数)/ 我在这一张图里(下面「我的阵容」那一行数)⇒ 不在这里再数一遍
		if bool(s.prep_showing()) or int(c.get("me", -1)) >= 0:
			return ""
		return "备战剩余 %s" % _FC.dur(_P2C.finals_shop_left(ra, now))
	## 选手: 只数**跟我有关的**那一刻(一场接一场时别人那场先播, 数到别人那场就和上一行「你的…」对不上):
	##   我那场即将开播 ⇒ 距开播; 我那场在播 ⇒ 不数; 我这一轮打完了、下一轮备战还没开始 ⇒ 距下一轮备战
	if int(c.get("me", -1)) >= 0:
		var f: Vector2i = s.my_focus()
		var fst := str(s.match_state(f.x, f.y)) if f.x >= 1 else ""
		if fst == str(s.ST_UPCOMING):
			return "距开播 %s" % _FC.dur(_PS.start_of(c, f.x, f.y) - now)
		if fst == str(s.ST_PREMIERE):
			return ""
		if _PS.before_shop(c, now) and ra > now:
			return "距下一轮备战 %s" % _FC.dur(ra - now)
		var e2 := next_premiere()
		if not e2.is_empty() and int(e2["m"]) < 0:
			return "距开播 %s" % _FC.dur(int(e2["at"]) - now)        # 还没翻面: 我下一场最早这一刻开播
		return ""
	var eta := next_premiere()
	if not eta.is_empty():
		return ("距下一场开播 %s" if live_rm().x >= 1 else "距开播 %s") % _FC.dur(int(eta["at"]) - now)
	if _PS.before_shop(c, now) and ra > now:
		return "距下一轮备战 %s" % _FC.dur(ra - now)
	return ""


# ═══════════════════════════════════════════════════════════════════
#  ⑳ / S 清单第 5 条: 唯一主按钮
# ═══════════════════════════════════════════════════════════════════
## {"text", "enabled", "rm", "kind"(live / replay / cup / wait), "tick"(字每秒刷新)}; {} = 不出现。
## ★2026-11-01: 等待时的按钮只写状态词(「等待开播」「备战中」), **不再带倒计时** —— 倒计时只在处境句下面那一行
##   (原来按钮与那一行逐字相同:「下一轮 3 分 0 秒后开播」说两遍)。
func cta_spec() -> Dictionary:
	var c: Dictionary = s.cur()
	var n := int(c.get("size", 0))
	if n < 2 or bool(s._grid_on):
		return {}
	var total := _B.rounds_for(n)
	var lr := live_rm()
	if lr.x >= 1 and bool(s.can_open(lr.x, lr.y)):
		if bool(s.is_my_match(lr.x, lr.y)):
			return {"text": "观看我的比赛", "enabled": true, "rm": lr, "kind": "live"}
		## 小组赛同一轮几场同时开播、我不在播: 「观看开播」, 点了在对阵图上点亮那几格(挑一场点开)
		var nl := live_count(lr.x)
		if nl >= 2:
			return {"text": "观看开播", "enabled": true, "rm": lr, "kind": "live_pick"}
		return {"text": "观看 %s" % pair_text(lr.x, lr.y, 120.0), "enabled": true, "rm": lr, "kind": "live"}
	if int(s.winner_side(total, 0)) >= 0:
		if is_cup():
			return {"text": "重看决赛", "enabled": bool(s.can_open(total, 0)), "rm": Vector2i(total, 0), "kind": "replay"}
		if int(s._finals.get("size", 0)) >= 1:
			return {"text": "前往%s" % _P2C.STAGE_CUP, "enabled": true, "kind": "cup"}
		return {"text": "%s %s 开赛" % [_P2C.STAGE_CUP, cup_start_hhmm()], "enabled": false, "kind": "wait"}
	var now := int(s.srv_now())
	var ra := int(c.get("round_at", 0))
	if upcoming_rm().x >= 1:
		return {"text": "等待开播", "enabled": false, "kind": "wait"}
	if _PS.before_shop(c, now) and ra > now:
		return {"text": "等待下一轮", "enabled": false, "kind": "wait"}
	if ra > 0 and _P2C.finals_shop_open(ra, now) and not _PS.before_shop(c, now):
		## 备战屏开着时它自己有大倒计时 + 「查看对阵图」⇒ 主按钮让位
		if bool(s.prep_showing()):
			return {}
		return {"text": "备战中", "enabled": false, "kind": "wait"}
	if _PS.settling(c, now):
		return {"text": "结算中", "enabled": false, "kind": "wait"}
	if not bool(c.get("closed", false)):
		return {"text": "等待开播", "enabled": false, "kind": "wait"}
	return {}


## 「甲 对 乙」(每个名字按像素截短)
func pair_text(r: int, m: int, each_px: float) -> String:
	var a := str(s.competitor(r, m, 0).get("name", ""))
	var b := str(s.competitor(r, m, 1).get("name", ""))
	return "%s 对 %s" % [s._fit_name(a, each_px, false, 20.0), s._fit_name(b, each_px, false, 20.0)]


# ═══════════════════════════════════════════════════════════════════
#  ⑬ 下一场 A 对 B · hh:mm(G3)
# ═══════════════════════════════════════════════════════════════════
func next_info() -> Dictionary:
	var c: Dictionary = s.cur()
	var n := int(c.get("size", 0))
	if n < 2 or bool(c.get("closed", false)) or bool(s._grid_on):
		return {}
	var eta := next_premiere()
	var lr := live_rm()
	## 已排进档期的下一场(知道是哪一场、几点)
	if not eta.is_empty() and int(eta["m"]) >= 0 and Vector2i(int(eta["r"]), int(eta["m"])) != lr:
		var r0 := int(eta["r"])
		var m0 := int(eta["m"])
		return {"head": _FC.kv("下一场", match_label(r0, m0)), "pair": pair_text(r0, m0, 104.0),
			"time": _FC.at(int(eta["at"])), "rm": Vector2i(r0, m0)}
	var r := int(c.get("round", 1))
	if r > _B.rounds_for(n):
		return {}
	for m2 in range(_B.matches_in_round(n, r)):
		var a: Dictionary = s.competitor(r, m2, 0)
		var b: Dictionary = s.competitor(r, m2, 1)
		if bool(a.get("bye", false)) or bool(b.get("bye", false)) or int(a.get("seed", -1)) < 0 or int(b.get("seed", -1)) < 0:
			continue
		## ★时刻只在知道的时候写(= 处境句 / 全局小条那一个); 不知道就空着 —— 不写「约 xx:xx」(原来写的是备战结束时刻, 会过去)
		var tm := _FC.at(int(eta["at"])) if (not eta.is_empty() and int(eta["r"]) == r) else ""
		return {"head": _FC.kv("下一场", _H.round_name(n, r)), "pair": pair_text(r, m2, 104.0), "time": tm, "rm": Vector2i(r, m2)}
	return {}


# ═══════════════════════════════════════════════════════════════════
#  ⑯ 我这一路(G15): 小组赛几格 + 冠军杯赛几格
# ═══════════════════════════════════════════════════════════════════
## {"cells": [{"label", "state"}], "split": 冠军杯段从第几格起, "champion": bool}; 不是选手 = {}。
func my_path() -> Dictionary:
	var g: Dictionary = s._bucket
	var me := int(g.get("me", -1))
	var gn := int(g.get("size", 0))
	if me < 0 or gn < 1:
		return {}
	var cells: Array = []
	var group_won := false
	var group_out := false
	if gn == 1:
		cells.append({"label": "直接晋级", "state": "bye"})
		group_won = true
	else:
		var seg := _segment(g, me, "")
		cells.append_array(seg["cells"])
		group_won = bool(seg["champion"])
		group_out = bool(seg["out"])
	var split := cells.size()
	var cup: Dictionary = s._finals
	var cn := int(cup.get("size", 0))
	var champion := false
	if cn >= 2 and int(cup.get("me", -1)) >= 0:
		var seg2 := _segment(cup, int(cup.get("me", -1)), "")
		cells.append_array(seg2["cells"])
		champion = bool(seg2["champion"])
	elif cn == 1 and int(cup.get("me", -1)) == 0:
		cells.append({"label": "直接夺冠", "state": "won"})
		champion = true
	else:
		var groups: int = maxi(2, s._spectate_list().size())
		var rounds := _B.rounds_for(groups)
		for r in range(1, rounds + 1):
			var st := "pending"
			if group_out:
				st = "locked"
			elif group_won and r == 1:
				st = "next"
			cells.append({"label": _short(rounds, r), "state": st})
	return {"cells": cells, "split": split, "champion": champion}


## 格子下面的轮次名: 与全决赛日同一套(`finals_copy.round_name`; 原来这里叫「半决」「8强」「组决赛」, 对阵图叫「半决赛」「1/4 决赛」)。
static func _short(total: int, r: int) -> String:
	return _FC.round_name(1 << total, r)


## 一张图里我这一段: 每一轮一格(赢 / 输 / 轮空 / 在播 / 下一场 / 还没到 / 已出局)。
func _segment(b: Dictionary, me: int, prefix: String) -> Dictionary:
	var n := int(b.get("size", 0))
	var total := _B.rounds_for(n)
	var done: Dictionary = b.get("done", {}) if b.get("done", {}) is Dictionary else {}
	var now := srv_now_of(b)
	var cells: Array = []
	var out := false
	var champ := false
	for r in range(1, total + 1):
		var lab := prefix + _short(total, r)
		if out:
			cells.append({"label": lab, "state": "locked"})
			continue
		var found := -1
		var side := -1
		for m in range(_B.matches_in_round(n, r)):
			for sd in [0, 1]:
				if _B.occupant_seed(r, m, sd, n, done) == me and not _src_hidden(b, r, m, sd, now):
					found = m
					side = sd
		if found < 0:
			cells.append({"label": lab, "state": "pending"})
			continue
		var other := _B.occupant_seed(r, found, 1 - side, n, done)
		var key := "%d-%d" % [r, found]
		if other == _B.OCC_BYE:
			cells.append({"label": lab, "state": "bye"})
			if r == total:
				champ = true
			continue
		if done.has(key) and not _LS.premiere_hidden(b, r, found, now):
			var won := int(done[key]) == side
			cells.append({"label": lab, "state": "won" if won else "lost"})
			if not won:
				out = true
			elif r == total:
				champ = true
			continue
		if done.has(key) and not _LS.premiere_upcoming(b, r, found, now):
			cells.append({"label": lab, "state": "live"})
		else:
			cells.append({"label": lab, "state": "next"})
	return {"cells": cells, "champion": champ, "out": out}


## 这个坑的人是从「还在开播 / 即将开播」的那一场晋级上来的 ⇒ 还不能说他在这儿(G2 不剧透)。
func _src_hidden(b: Dictionary, r: int, m: int, side: int, now: int) -> bool:
	if r < 2:
		return false
	return _LS.premiere_hidden(b, r - 1, m * 2 + side, now)


# ═══════════════════════════════════════════════════════════════════
#  别的组里的一位(宫格 / 备战屏 / 名牌墙): 名字 + 头像 id(+ 来历)
# ═══════════════════════════════════════════════════════════════════
func seat_of(b: Dictionary, sd: int) -> Dictionary:
	if sd < 0:
		return {}
	var names: Array = b.get("names", []) if b.get("names", []) is Array else []
	var tags: Array = b.get("tags", []) if b.get("tags", []) is Array else []
	var pid := ""
	var avs = b.get("avatars", null)
	if avs is Array and sd < (avs as Array).size():
		pid = str(avs[sd])
	if pid == "" and sd < tags.size():
		pid = str(s._portraits.get(str(tags[sd]), ""))
	var raw := str(names[sd]) if sd < names.size() else "神秘龟"
	var tg := str(tags[sd]) if sd < tags.size() else ""
	return {"seed": sd, "name": s._BLK.shown_name(raw, tg), "_pid": pid, "bye": false}


func group_live_rm(b: Dictionary) -> Vector2i:
	var n := int(b.get("size", 0))
	var r := _LS.premiere_round(b)
	if r < 1:
		return Vector2i(-1, -1)
	var now := srv_now_of(b)
	for m in range(_B.matches_in_round(n, r)):
		if r == 1 and (_B.is_bye_slot(m * 2, n) or _B.is_bye_slot(m * 2 + 1, n)):
			continue
		if _LS.premiere_hidden(b, r, m, now) and not _LS.premiere_upcoming(b, r, m, now):
			return Vector2i(r, m)
	return Vector2i(-1, -1)


func _group_seat(b: Dictionary, r: int, m: int, side: int, now: int) -> Dictionary:
	var n := int(b.get("size", 0))
	var done: Dictionary = b.get("done", {}) if b.get("done", {}) is Dictionary else {}
	var sd := _B.occupant_seed(r, m, side, n, done)
	if sd < 0 or _src_hidden(b, r, m, side, now):
		return {}
	return seat_of(b, sd)


# ═══════════════════════════════════════════════════════════════════
#  ⑲ 全部组宫格
# ═══════════════════════════════════════════════════════════════════
func grid_cells() -> Array:
	var out: Array = []
	for b0 in s._spectate_list():
		var b: Dictionary = b0
		var n := int(b.get("size", 0))
		var total := _B.rounds_for(n)
		var bk := int(b.get("bucket", -1))
		var now := srv_now_of(b)
		var done: Dictionary = b.get("done", {}) if b.get("done", {}) is Dictionary else {}
		var cell := {"bucket": bk, "title": _CD.group_name(bk),
			"mine": bk == int(s._bucket.get("bucket", -2)) and int(s._bucket.get("me", -1)) >= 0}
		var cs := _B.champion_seed(n, done)
		var lr := group_live_rm(b)
		var ra := int(b.get("round_at", 0))
		if bool(b.get("closed", false)) and cs >= 0 and not _LS.premiere_hidden(b, total, 0, now):
			cell.merge({"state": "done", "chip": "已结束", "a": seat_of(b, cs), "line": ""})
		elif lr.x >= 1:
			var k := 0
			var ln := _PS.lineup(b, lr.x)
			for i in range(ln.size()):
				if int(ln[i][0]) == lr.y and not _PS.together(ln):
					k = i + 1                    # 同一轮同时开播(小组赛)不写「第 k 场」
			cell.merge({"state": "live", "chip": "开播中", "a": _group_seat(b, lr.x, lr.y, 0, now),
				"b": _group_seat(b, lr.x, lr.y, 1, now),
				"line": _H.round_name(n, lr.x) + (("第 %d 场" % k) if k > 0 and lr.x < total else "")})
		else:
			var r := int(b.get("round", 1))
			var shop: bool = ra > 0 and _P2C.finals_shop_open(ra, now) and not _PS.before_shop(b, now)
			var pa := {}
			var pb := {}
			for m in range(_B.matches_in_round(n, mini(r, total))):
				pa = _group_seat(b, mini(r, total), m, 0, now)
				pb = _group_seat(b, mini(r, total), m, 1, now)
				if not pa.is_empty() and not pb.is_empty():
					break
			cell.merge({"state": "prep" if shop else "wait", "chip": "备战中" if shop else "等待开播", "a": pa, "b": pb,
				"line": _FC.kv("下一场", _H.round_name(n, mini(r, total)))})
		out.append(cell)
	return out


# ═══════════════════════════════════════════════════════════════════
#  ⑭ 本轮名牌墙 / ⑮ 备战屏 的数据
# ═══════════════════════════════════════════════════════════════════
func wall_data() -> Dictionary:
	var c: Dictionary = s.cur()
	var n := int(c.get("size", 0))
	if n < 2 or bool(c.get("closed", false)):
		return {}
	var total := _B.rounds_for(n)
	var fr := _LS.premiere_round(c)
	if fr < 1 or fr >= total:
		return {}
	var any_real := false
	for m in range(_B.matches_in_round(n, fr)):
		if bool(s.competitor(fr, m, 0).get("bye", false)) or bool(s.competitor(fr, m, 1).get("bye", false)):
			continue
		any_real = true
		if str(s.match_state(fr, m)) != str(s.ST_DONE):
			return {}
	if not any_real:
		return {}
	var key := "%d|%d|%d|%d" % [int(c.get("bucket", -1)), int(s.feed_week()), _LS.flip_ts_of(c), fr]
	var seats: Array = []
	for m2 in range(_B.matches_in_round(n, fr)):
		var a: Dictionary = s.competitor(fr, m2, 0)
		var b: Dictionary = s.competitor(fr, m2, 1)
		var bye := bool(a.get("bye", false)) or bool(b.get("bye", false))
		var ws := int(s.winner_side(fr, m2))
		for side in [0, 1]:
			var cc: Dictionary = a if side == 0 else b
			if bool(cc.get("bye", false)) or int(cc.get("seed", -1)) < 0:
				continue
			seats.append({"c": cc, "lost": (not bye) and ws >= 0 and side != ws, "bye": bye,
				"mine": bool(s._is_me_side(fr, m2, side)), "origin": origin_label(int(cc.get("seed", -1)))})
	var pairs: Array = []
	for m3 in range(_B.matches_in_round(n, fr + 1)):
		var pa: Dictionary = s.competitor(fr + 1, m3, 0)
		var pb: Dictionary = s.competitor(fr + 1, m3, 1)
		if int(pa.get("seed", -1)) >= 0 and int(pb.get("seed", -1)) >= 0:
			pairs.append([pa, pb])
	return {"key": key, "title": "%s结果" % _H.round_name(n, fr), "seats": seats,
		"next_title": _H.round_name(n, fr + 1), "pairs": pairs}


func prep_data() -> Dictionary:
	var c: Dictionary = s.cur()
	var n := int(c.get("size", 0))
	if n < 2 or bool(c.get("closed", false)):
		return {}
	var now := int(s.srv_now())
	var ra := int(c.get("round_at", 0))
	if ra <= 0 or not _P2C.finals_shop_open(ra, now) or _PS.before_shop(c, now):
		return {}
	var total := _B.rounds_for(n)
	var r := mini(int(c.get("round", 1)), total)
	var key := "%d|%d|%d" % [int(c.get("bucket", -1)), int(s.feed_week()), r]
	var me := int(c.get("me", -1))
	var pairs: Array = []
	var players: Array = []
	var mine_in := false
	for m in range(_B.matches_in_round(n, r)):
		var a: Dictionary = s.competitor(r, m, 0)
		var b: Dictionary = s.competitor(r, m, 1)
		for cc in [a, b]:
			if int((cc as Dictionary).get("seed", -1)) >= 0 and not bool((cc as Dictionary).get("bye", false)):
				var pc: Dictionary = (cc as Dictionary).duplicate()
				pc["_origin"] = origin_label(int(pc.get("seed", -1)))
				pc["_me"] = int(pc.get("seed", -1)) == me
				players.append(pc)
		if bool(a.get("bye", false)) or bool(b.get("bye", false)):
			continue
		var mine: bool = bool(s.is_my_match(r, m))
		mine_in = mine_in or mine
		var a2: Dictionary = a.duplicate()
		var b2: Dictionary = b.duplicate()
		a2["_me"] = int(a.get("seed", -1)) == me and me >= 0
		b2["_me"] = int(b.get("seed", -1)) == me and me >= 0
		pairs.append([a2, b2, mine])
	var rn := _H.round_name(n, r)
	var stake := ""
	if r >= total:
		stake = "胜者夺得%s冠军" % _P2C.STAGE_CUP if is_cup() else "胜者获得%s冠军，晋级%s" % [s.sheet_name(c), _P2C.STAGE_CUP]
	else:
		stake = _FC.join("胜者进入", _H.round_name(n, r + 1))
	return {"key": key, "title": "%s备战" % rn, "end_ts": ra + int(_P2C.FINALS_SHOP_SEC),
		"progress": "本轮 %d 场，剩余 %d 人" % [pairs.size(), players.size()], "pairs": pairs, "stake": stake,
		"me_line": _M.TXT_KEEP_LINEUP if mine_in else "", "players": players}


# ═══════════════════════════════════════════════════════════════════
#  冠军决出那一刻交给 D 的数据(挂点 `BracketMapScene._on_champion_decided(data)`)
# ═══════════════════════════════════════════════════════════════════
## 一张图的冠军收盘数据。冠军未揭晓(或还在开播) = {}。
## ★夺冠阵容(lineup)客户端拿不到: 对阵数据刻意不下发快照(只有 finals_opponent 每人每轮问一次) ⇒ 留空数组, 由 D 那边决定怎么补。
func champion_data(b: Dictionary) -> Dictionary:
	var n := int(b.get("size", 0))
	if n < 2:
		return {}
	var total := _B.rounds_for(n)
	var done: Dictionary = b.get("done", {}) if b.get("done", {}) is Dictionary else {}
	var now := srv_now_of(b)
	if not done.has("%d-0" % total) or _LS.premiere_hidden(b, total, 0, now):
		return {}
	var cs := _B.champion_seed(n, done)
	if cs < 0:
		return {}
	var cup := int(b.get("bucket", -1)) == int(_P2C.FINALS_CUP_BUCKET)
	var fw := int(done["%d-0" % total])
	var ru := _B.occupant_seed(total, 0, 1 - fw, n, done)
	var scores: Dictionary = b.get("scores", {}) if b.get("scores", {}) is Dictionary else {}
	var semis: Array = []
	if total >= 2:
		for m in range(_B.matches_in_round(n, total - 1)):
			var k := "%d-%d" % [total - 1, m]
			if not done.has(k):
				continue
			var lo := _B.occupant_seed(total - 1, m, 1 - int(done[k]), n, done)
			if lo >= 0:
				semis.append(_seat_full(b, lo))
	var path: Array = []
	for r in range(1, total + 1):
		for m2 in range(_B.matches_in_round(n, r)):
			for sd in [0, 1]:
				if _B.occupant_seed(r, m2, sd, n, done) != cs:
					continue
				var opp := _B.occupant_seed(r, m2, 1 - sd, n, done)
				var k2 := "%d-%d" % [r, m2]
				var pair: Array = []
				if scores.has(k2):
					pair = s.DL_SCORE.score_pair(int(scores[k2]))
				path.append({"round": r, "match": m2, "round_name": _H.round_name(n, r), "bye": opp == _B.OCC_BYE,
					"opponent": _seat_full(b, opp) if opp >= 0 else {}, "score": pair, "won": true})
	var total_entrants := 0
	for gb in s._champ_buckets():
		total_entrants += int((gb as Dictionary).get("size", 0))
	return {"stage": "cup" if cup else "group", "bucket": int(b.get("bucket", -1)),
		"group_no": 0 if cup else int(b.get("bucket", 0)) + 1, "sheet_name": str(s.sheet_name(b)),
		"week": int(s.feed_week()), "champion": _seat_full(b, cs), "runner_up": _seat_full(b, ru) if ru >= 0 else {},
		"semifinalists": semis, "path": path, "entrants": n, "total_entrants": maxi(total_entrants, n),
		"is_me": int(b.get("me", -1)) == cs, "lineup": []}


func _seat_full(b: Dictionary, sd: int) -> Dictionary:
	var d := seat_of(b, sd)
	var tags: Array = b.get("tags", []) if b.get("tags", []) is Array else []
	var accs: Array = b.get("accs", []) if b.get("accs", []) is Array else []
	d["tag"] = str(tags[sd]) if sd < tags.size() else ""
	d["acc"] = str(accs[sd]) if sd < accs.size() else ""
	d["avatar"] = str(d.get("_pid", ""))
	return d


# ═══════════════════════════════════════════════════════════════════
#  组页签(⑩) / 收盘滚动名单(⑰) / 冠军决出那一刻(G10)
# ═══════════════════════════════════════════════════════════════════
## 组页签出不出: 小组赛页、本周不止一组。
func chips_on() -> bool:
	return not is_cup() and s._spectate_list().size() >= 2


## [{"key": "all" / 组号, "text", "on", "mine", "live"}]
func chip_items() -> Array:
	var any_live := false
	var out: Array = []
	var cb := int(s.cur().get("bucket", -9))
	for b in s._spectate_list():
		var bk := int((b as Dictionary).get("bucket", -1))
		var lv: bool = group_live_rm(b).x >= 0
		any_live = any_live or lv
		out.append({"key": bk, "text": _CD.group_name(bk), "on": not bool(s._grid_on) and bk == cb,
			"mine": int(s._bucket.get("me", -1)) >= 0 and bk == int(s._bucket.get("bucket", -2)), "live": lv})
	out.push_front({"key": "all", "text": "全部", "on": bool(s._grid_on), "mine": false, "live": any_live})
	return out


## 收盘那一条滚动名单: 本周决赛日全部参赛者。
func entrants_text() -> String:
	var names: Array = []
	for b in s._champ_buckets():
		for nm in ((b as Dictionary).get("names", []) as Array):
			names.append(str(nm))
	if names.is_empty():
		return ""
	return "本周决赛日参赛选手（%d 人）　%s" % [names.size(), "　".join(PackedStringArray(names))]


## 冠军决出那一刻: 只认「亲眼等到揭晓」的那一下(本次运行里**刚刚**见过这张图的决赛还没揭晓), 每张图只报一次 ⇒ 场景的挂点。
## ★「刚刚」= 上一次看见它没揭晓距此刻不超过 CHAMP_FRESH_SEC: 18:10 看过小组、冠军杯赛开赛后才回来看的人,
##   不该在冠军杯页上突然被弹一段 A 组冠军仪式(录屏自查抓到的; 错过的补看归 M 的 finals_day_recap)。
const CHAMP_FRESH_SEC := 900
func check_champion_moment() -> void:
	var seen := {}
	for b in [s.cur(), s._finals, s._bucket]:
		var bd: Dictionary = b
		if int(bd.get("size", 0)) < 2:
			continue
		var key := "%d|%d" % [int(bd.get("bucket", -1)), int(s.feed_week())]
		if seen.has(key):
			continue
		seen[key] = true
		var now := srv_now_of(bd)
		var d: Dictionary = champion_data(bd)
		if d.is_empty():
			champ_waiting[key] = now
			continue
		var gap := now - int(champ_waiting.get(key, 0))
		if champ_waiting.has(key) and not champ_fired.has(key) and gap >= 0 and gap <= CHAMP_FRESH_SEC:
			champ_fired[key] = true
			d["view"] = s._week_view()
			s._on_champion_decided(d)
