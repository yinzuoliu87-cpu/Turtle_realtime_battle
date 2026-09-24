extends Node
## verify_nickname.gd — 玩家昵称 (2026-09-24)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-09-24:「这个在创建账号应该一起吧」⇒ 昵称挂在**绑定邮箱**那一屏
## （这个项目里玩家唯一感知得到的「创建账号」时刻 —— 首启建匿名号是**静默**的）。
##
## 三件事最容易出错，各自成节：
##   ① **规则**：规范化 + 长度。★先规范化再判长度 —— 否则「  a  」能靠空白凑够。
##   ② **跨重置**：昵称属于**账号**不属于「这局游戏」⇒ 大轮切换不清、**清档也不清**。
##      清了的话玩家清一次档就变回兜底短码，而服务器上还是同一个账号 —— 名字对不上。
##   ③ **一个来源**：对阵图 / 快照(排行榜显示的就是它) / 排行榜"我"那一行，
##      三处必须是同一个答案。以前是三处各写一份死字符串（「玩家阵容」「我 (玩家)」）。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 规则层是纯函数 ⇒ **穷举**边界（正好 MIN / 差一个 / 正好 MAX / 超一个 / 全空白）。
## ★② 两种重置各验一次 —— 它们是**两段各自手写**的清除列表，只验一条另一条漏了没人知道。
## ★③ 三处「同一个来源」不靠读源码判断，而是**改一次昵称、看三处一起变**。
## ★④ 兜底短码要证明**两个账号不重名**（取前缀那一版就是这么红的）。
##
## 跑法: <godot> --headless --path . res://tests/verify_nickname.tscn --quit-after 600

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BK := preload("res://scripts/net/backend.gd")

var _n := 0
var _fail := 0
const KEYS := ["nickname", "account_id", "account_email", "install_uid", "season_id",
	"season_leaders", "ranked_used", "week_anchor_ts", "titles"]
var _bak := {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	for k in KEYS:
		_bak[k] = GameState.get(k)
	print("=== 玩家昵称 ===")
	_t_rules()
	_t_fallback()
	_t_one_source()
	_t_survive_resets()
	for k in KEYS:
		GameState.set(k, _bak[k])
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 玩家昵称" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 规则(纯函数, 穷举边界)
# ─────────────────────────────────────────────────────────────
func _t_rules() -> void:
	print("── ① 规则 ──")
	_ok("① 边界: 正好 %d 个字 ⇒ 合法" % P2C.NICK_MIN,
		P2C.nickname_valid("阿龟"), P2C.nickname_error("阿龟"))
	_ok("① 边界: 少一个字 ⇒ 不合法", not P2C.nickname_valid("龟"))
	_ok("① 边界: 正好 %d 个字 ⇒ 合法" % P2C.NICK_MAX,
		P2C.nickname_valid("一二三四五六七八"))
	_ok("① 边界: 多一个字 ⇒ 不合法", not P2C.nickname_valid("一二三四五六七八九"))
	_ok("① 空串 ⇒ 不合法", not P2C.nickname_valid(""))

	## ★★先规范化再判长度 —— 否则空白能凑数
	_ok("① ★★「  龟  」去掉首尾空白之后只剩 1 个字 ⇒ 不合法(空白不许凑数)",
		not P2C.nickname_valid("  龟  "), "clean=「%s」" % P2C.nickname_clean("  龟  "))
	_ok("① ★全是空白 ⇒ 不合法", not P2C.nickname_valid("      "))
	_ok("① ★首尾空白被去掉", P2C.nickname_clean("  阿龟  ") == "阿龟",
		"「%s」" % P2C.nickname_clean("  阿龟  "))
	_ok("① ★内部连续空白压成一个", P2C.nickname_clean("阿   龟") == "阿 龟",
		"「%s」" % P2C.nickname_clean("阿   龟"))
	## ★控制字符: 换行/制表贴进来不许留下
	_ok("① ★★换行/制表被丢掉(贴一段文字进来不许把排版带进名字)",
		P2C.nickname_clean("阿\n\t龟") == "阿龟", "「%s」" % P2C.nickname_clean("阿\n\t龟"))
	_ok("① ★分母: 正常名字**不被改动**(证明上面几条不是「把什么都洗掉」)",
		P2C.nickname_clean("阿龟大王") == "阿龟大王")

	## 报错文案: 太短/太长各有各的话
	_ok("① 太短有话说", P2C.nickname_error("龟").find("太短") >= 0, P2C.nickname_error("龟"))
	_ok("① 太长有话说", P2C.nickname_error("一二三四五六七八九").find("太长") >= 0,
		P2C.nickname_error("一二三四五六七八九"))
	_ok("① ★合法 ⇒ 空串(调用方据此判断要不要报错)", P2C.nickname_error("阿龟") == "")


# ─────────────────────────────────────────────────────────────
# ② 兜底短码
# ─────────────────────────────────────────────────────────────
func _t_fallback() -> void:
	print("── ② 没设昵称时 ──")
	var a := str(P2C.nickname_fallback("uid-aaaa-1111"))
	var b := str(P2C.nickname_fallback("uid-bbbb-2222"))
	print("     两个号: 「%s」 / 「%s」" % [a, b])
	_ok("② ★★两个账号的兜底短码**不一样**(取前缀那一版就是这么红的: id 有公共前缀时全员重名)",
		a != b, "%s vs %s" % [a, b])
	_ok("② ★同一个号每次算出来都一样(确定性)",
		P2C.nickname_fallback("uid-aaaa-1111") == a)
	_ok("② 空 id 也有个名字, 不是空串", str(P2C.nickname_fallback("")) != "")
	_ok("② ★★有昵称就用昵称, 不用兜底",
		str(P2C.display_name("阿龟", "uid-aaaa-1111")) == "阿龟")
	_ok("② ★昵称不合法(太短)时回落到兜底 —— 不显示半个名字",
		str(P2C.display_name("龟", "uid-aaaa-1111")) == a,
		str(P2C.display_name("龟", "uid-aaaa-1111")))
	_ok("② ★昵称是空白时也回落",
		str(P2C.display_name("   ", "uid-aaaa-1111")) == a)


# ─────────────────────────────────────────────────────────────
# ③ ★★三处显示是同一个来源 —— 改一次, 三处一起变
# ─────────────────────────────────────────────────────────────
func _t_one_source() -> void:
	print("── ③ 一个来源 ──")
	GameState.account_id = "uid-me-1234"
	GameState.nickname = ""
	var fb := str(BK.player_display_name())
	_ok("③ ★分母: 没设昵称时是兜底短码", fb == P2C.nickname_fallback("uid-me-1234"), fb)
	GameState.nickname = "阿龟大王"
	_ok("③ ★★设了昵称 ⇒ 统一出处跟着变", str(BK.player_display_name()) == "阿龟大王",
		str(BK.player_display_name()))

	## 快照(排行榜显示的就是它)
	GameState.season_leaders = ["basic", "fortune", "ninja"]
	GameState.season_id = 1
	var gid := str(BK.player_ghost_id(1, GameState.season_leaders, -1))
	var snap: Dictionary = BK.build_ghost_snapshot(gid,
		{"name": BK.player_display_name(), "avatar": "basic", "id": gid})
	_ok("③ ★★快照里的名字 = 昵称(以前全世界都叫「玩家阵容」)",
		str((snap.get("profile", {}) as Dictionary).get("name", "")) == "阿龟大王",
		str((snap.get("profile", {}) as Dictionary).get("name", "")))

	## ★自己认自己不许坏: 快照改了名字之后, `_is_self_ghost` 还得认得出
	##   (那条第三判据读的是写死的「玩家阵容」—— 它只对**没有 origin** 的老条目生效)
	snap[BK.ORIGIN_KEY] = BK.ORIGIN_LOCAL
	_ok("③ ★★改了名字之后「认自己」没坏(前两条判据: ghost_id 前缀 / origin)",
		BK._is_self_ghost(snap), str(snap.get("ghost_id", "")))

	GameState.nickname = ""


# ─────────────────────────────────────────────────────────────
# ④ ★★★跨两种重置 —— 昵称属于账号不属于这局游戏
# ─────────────────────────────────────────────────────────────
func _t_survive_resets() -> void:
	print("── ④ 跨重置 ──")
	GameState.nickname = "阿龟大王"
	GameState.account_id = "uid-me-1234"
	GameState.ranked_used = 11

	GameState.start_new_season()
	_ok("④ ★★★大轮切换 ⇒ 昵称还在", str(GameState.nickname) == "阿龟大王",
		str(GameState.nickname))
	_ok("④ ★分母: 同一次切换里 ranked_used 确实被清了(证明清除逻辑真的跑了)",
		int(GameState.ranked_used) == 0)

	GameState.ranked_used = 7
	GameState.reset_save()
	_ok("④ ★★★清档 ⇒ 昵称还在(清的是「这局游戏」, 不是「你是谁」)",
		str(GameState.nickname) == "阿龟大王", str(GameState.nickname))
	_ok("④ ★分母: 同一次清档里 ranked_used 确实被清了",
		int(GameState.ranked_used) == 0)
	_ok("④ ★分母: 账号本身也留着(与昵称同一条线)",
		str(GameState.account_id) == "uid-me-1234")

	var payload: Dictionary = GameState.cloud_payload()
	_ok("④ ★昵称进了存档载荷(不然重开游戏就没了)",
		str(payload.get("nickname", "")) == "阿龟大王", str(payload.get("nickname")))
