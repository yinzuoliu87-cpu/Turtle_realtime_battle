extends RefCounted
## 周日决赛日 · 开播一场接一场(2026-11-01 · 方案书 docs/plans/20261101-决赛日开播一场接一场.md)。
## 用户 2026-10-31「有任何商业游戏会同时播两个半决赛吗」。
##
## ══════════════════════════════════════════════════════════════════════
##  数据: 服务端 20261101 迁移起每组多下发一个键 seq(`SupabaseNet._bucket_from` 原样带过来)
## ══════════════════════════════════════════════════════════════════════
##   seq = {"v": 1, "until": unix, "settle_at": unix, "p": {"轮-场": [开播, 揭晓], ...}}
##     · p     : 已翻面那几轮里**有录像的真实场次**的档期(服务端 `finals_premiere_plan`; 每场 = ceil(步数/60) + 30 秒开场与幕布):
##               小组赛各桶 = 同一轮都从翻面时刻开播(同时); 冠军杯赛 = 按场号一场接一场(场间 25 秒)。
##               用户 10-31「桶内就是这样子同时跑，但是决赛里面就一定是一场场跑」。轮空 / 兜底判 / 判负不在里面 ⇒ 翻面即揭晓。
##     · until : 这一次翻面的档期整段结束(= 下一轮 3 分钟备战开始 = 组的 round_at; 收盘那一轮 = 决赛播完 + 25 秒)。
##               第 1 轮翻面之前 = 0(服务端开关开着时每组都回 seq, p 为空)。
##     · settle_at: 本轮备战结束时刻(之后服务器在算、结果齐了就翻面, 最早备战结束 + 60 秒); 收盘 = 0。
##   没有 seq(老服务端 / 开关关 / 那一次翻面按老规则)⇒ `is_seq() == false` ⇒ 调用方退回 `live_spectate` 的老窗口
##   (同一轮同一刻开播), 一个字不改老行为。
##
## ══════════════════════════════════════════════════════════════════════
##  一场的三态(`state`): 即将开播 → 开播中 → 已揭晓
## ══════════════════════════════════════════════════════════════════════
##   · S_UPCOMING 即将开播: 已翻面、还没轮到它 —— 不显示胜负、不能点开(点了只能对着第 0 步干等)
##   · S_LIVE     开播中  : 不显示胜负; 点开 = 观赛跟播(开播会话的起点 = 这一场的开播时刻)
##   · S_REVEALED 已揭晓  : 显示胜负; 点开 = 回放。这台设备看完了的那一场(`watched`)在开播中也算已揭晓。
##   · S_NONE            : 不是开播场次(没有结果 / 不在档期里 / 老规则)
## ★纯函数: 只吃一份组字典 + 服务端此刻(unix 秒), 不碰网络 / 场景 / 静态状态(看没看过由调用方传进来)。

const S_NONE := 0
const S_UPCOMING := 1
const S_LIVE := 2
const S_REVEALED := 3

## 屏上的字(短名词 / 短指令)。
const TXT_LIVE := "开播中"
## 备战结束 → 翻面那一段(服务器在算; 翻面时刻取决于裁判多快写回, 不给倒计时)。
const TXT_SETTLE := "即将开播"


## 这一组的 seq; 没有 / 形状不对 / 版本不认识 ⇒ {}(= 老规则)。
static func seq_of(b: Dictionary) -> Dictionary:
	var s = b.get("seq", null)
	if not (s is Dictionary):
		return {}
	if int((s as Dictionary).get("v", 0)) < 1 or not ((s as Dictionary).get("p", null) is Dictionary):
		return {}
	return s


## 这一组最近一次翻面是按「一场接一场」排的吗。
static func is_seq(b: Dictionary) -> bool:
	return not seq_of(b).is_empty()


## 一场的档期 [开播, 揭晓](unix 秒); 没有 ⇒ []。
## ★与 `done` 同一道锁(`_bucket_from` 第二道锁): 没收盘时当前轮及以后的不认 —— 服务端哪天多发了也不提前开播。
static func slot(b: Dictionary, r: int, m: int) -> Array:
	var s := seq_of(b)
	if s.is_empty() or r < 1:
		return []
	if not bool(b.get("closed", false)) and r >= int(b.get("round", 1)):
		return []
	var v = (s["p"] as Dictionary).get("%d-%d" % [r, m], null)
	if not (v is Array) or (v as Array).size() < 2:
		return []
	var a := int(v[0])
	var e := int(v[1])
	if a <= 0 or e < a:
		return []
	return [a, e]


## ★判据中心: 这一场此刻是哪一态。`now` = 服务端此刻; `watched` = 这台设备看完了这一场。
static func state(b: Dictionary, r: int, m: int, now: int, watched: bool = false) -> int:
	if not (b.get("done", {}) as Dictionary).has("%d-%d" % [r, m]):
		return S_NONE
	var sl := slot(b, r, m)
	if sl.is_empty():
		return S_NONE
	if now < int(sl[0]):
		return S_UPCOMING
	if now < int(sl[1]) and not watched:
		return S_LIVE
	return S_REVEALED


## 此刻不许显示胜负(即将开播 / 开播中)。
static func hidden(b: Dictionary, r: int, m: int, now: int, watched: bool = false) -> bool:
	var st := state(b, r, m, now, watched)
	return st == S_UPCOMING or st == S_LIVE


## 开播会话的起点(观赛跟播「该到第几步」= (此刻 − 起点) × 60): 这一场的开播时刻; 没有档期 ⇒ 0(调用方用老规则的翻面时刻)。
static func start_of(b: Dictionary, r: int, m: int) -> int:
	var sl := slot(b, r, m)
	return int(sl[0]) if not sl.is_empty() else 0


## 第 r 轮排了档期的场次, 按开播先后(同时开播的按场号): [[m, 开播, 揭晓], ...]。
static func lineup(b: Dictionary, r: int) -> Array:
	var out: Array = []
	var s := seq_of(b)
	if s.is_empty():
		return out
	for k in (s["p"] as Dictionary):
		var parts := str(k).split("-")
		if parts.size() != 2 or int(parts[0]) != r:
			continue
		var sl := slot(b, r, int(parts[1]))
		if not sl.is_empty():
			out.append([int(parts[1]), int(sl[0]), int(sl[1])])
	out.sort_custom(func(x, y): return int(x[1]) < int(y[1]) or (int(x[1]) == int(y[1]) and int(x[0]) < int(y[0])))
	return out


## 这一轮是不是「同时开播」(小组赛): 只有一场, 或所有场次开播时刻相同。冠军杯赛(一场接一场)= false。
static func together(ln: Array) -> bool:
	if ln.size() <= 1:
		return true
	for it in ln:
		if int(it[1]) != int(ln[0][1]):
			return false
	return true


## 最近一次翻面的那一轮(没收盘 = 当前轮 − 1; 收盘 = 最后一轮 = round)。0 = 还没翻过。
static func flipped_round(b: Dictionary) -> int:
	var rnd := int(b.get("round", 1))
	return rnd if bool(b.get("closed", false)) else rnd - 1


## 下一轮 3 分钟备战还没开始、而这一组正在一场接一场地播(⇒ 备战那一行不出现, 顶上那一行说开播进度)。
static func before_shop(b: Dictionary, now: int) -> bool:
	if not is_seq(b) or bool(b.get("closed", false)) or now <= 0:
		return false
	return now < int(b.get("round_at", 0))


## 这一组此刻在「结算」那一段吗: 本轮备战已结束、还没翻面(服务器在算这一轮)。老规则 / 收盘恒 false。
static func settling(b: Dictionary, now: int) -> bool:
	if bool(b.get("closed", false)) or now <= 0:
		return false
	var sa := int(seq_of(b).get("settle_at", 0))
	return sa > 0 and now >= sa


## 顶上那一行(对阵图倒计时位); "" = 不归这里管(调用方照旧写)。
## `fmt` = 秒数 → 「2 分 30 秒」(对阵图 `countdown_text`, 同一种写法只有一份)。
##   · 小组赛(同一轮同时开播)⇒ 「本轮 N 场开播中 · 下一轮备战 X后开始」(N = 此刻还在播的场数, 短的那场揭晓后变小)
##   · 冠军杯赛(一场接一场)⇒ 「第 k 场开播中 · 第 k+1 场 X后开播」/ 场间「第 k 场 X后开播」/ 最后一场带下一轮备战倒计时
##   · 本轮播完、下一轮备战还没开始 ⇒ 「下一轮备战 X后开始」(收盘那一轮不说)
##   · 收盘那一轮只有决赛一场 ⇒ 「决赛开播中」/「决赛 X后开播」
##   · 备战结束、还没翻面 ⇒ 「结算中 · 即将开播」(第 1 轮也有)
static func round_line(b: Dictionary, now: int, fmt: Callable, watched_keys: Dictionary = {}) -> String:
	if not is_seq(b) or now <= 0:
		return ""
	var r := flipped_round(b)
	if r < 1:
		return TXT_SETTLE if settling(b, now) else ""
	var closed := bool(b.get("closed", false))
	var ln := lineup(b, r)
	var single := closed and ln.size() == 1
	var shop_at := int(b.get("round_at", 0))
	var live: Array = []             # 此刻开播中的(lineup 下标)
	var next_i := -1                 # 第一场还没开播的
	for i in range(ln.size()):
		var it: Array = ln[i]
		if now < int(it[1]):
			if next_i < 0:
				next_i = i
		elif now < int(it[2]) and not watched_keys.has(int(it[0])):
			live.append(i)
	var shop_tail := ("距下一轮备战 %s" % fmt.call(shop_at - now)) if (not closed and shop_at > now) else ""
	if not live.is_empty():
		var head := ""
		if single:
			head = "决赛" + TXT_LIVE
		elif together(ln) or live.size() > 1:
			head = "本轮 %d 场%s" % [live.size(), TXT_LIVE]
		else:
			head = _name(int(live[0]), false) + TXT_LIVE
		## ★2026-11-01 一行一件事: 有一场在播就只说在播(下一场几点在底部「下一场」卡 / 下一行倒计时)
		return head
	if next_i >= 0:
		return "%s距开播 %s" % [_name(next_i, single), fmt.call(int(ln[next_i][1]) - now)]
	if shop_tail != "":
		return shop_tail
	return TXT_SETTLE if settling(b, now) else ""


static func _name(i: int, single: bool) -> String:
	return "决赛" if single else "第 %d 场" % (i + 1)
