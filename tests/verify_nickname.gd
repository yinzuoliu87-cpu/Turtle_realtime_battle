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
const KEYS := ["nickname", "nickname_default", "account_id", "account_email", "install_uid", "season_id",
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
	_t_default_name()
	await _t_frozen_default()
	_t_migrate_legacy()
	await _t_rename()
	await _t_bind_copy()
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
	_ok("① 太短有话说", P2C.nickname_error("龟").find("至少") >= 0, P2C.nickname_error("龟"))
	_ok("① 太长有话说", P2C.nickname_error("一二三四五六七八九").find("最多") >= 0,
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


# ─────────────────────────────────────────────────────────────
# ⑤ ★★★默认名像真人(用户 2026-10-04「换成随机像人的昵称」)
#
# 原来没起名的号显示「龟主-xxxxx」(周日实况 6 个真人号全是这个)。
# 现在从预填名生成器 `nickname_suggest_at`(机器人也用它)里按种子哈希挑一个。
# ★2026-10-07 生成器换成真人用户名的长相(kevin_99 / 不吃香菜), 池子不再能穷举 ⇒
#   「出自生成器」改成「合法 + 不撞屏蔽词 + 不是旧版名字」(`_gen_ok`)。
# ★三件事: ① 不是「龟主-」格式且合法、出自生成器池 ② 稳定 —— 存档写盘再读回来还是同一个
#   ③ 默认名**不落盘**(`nickname` 仍是 "") —— 这正是「默认 vs 自己起的」能分清的依据,
#   也是老玩家不用迁移代码就自动换名的原因; 自己起过名的(哪怕起的就是「龟主-…」)一个字不动。
# ─────────────────────────────────────────────────────────────
const _OLD_HEAD := "龟主-"
const _PROBE := "user://_verify_nickname_reopen.json"

## 「这是新生成器会给的名字」: 合法、不撞屏蔽词、不是旧版「定语 × 名头」。
func _gen_ok(nm: String) -> bool:
	return P2C.nickname_valid(nm) and not P2C.nickname_blocked(nm) and not P2C.nickname_is_legacy_default(nm)


## 真开机那条路: 存档字典 → JSON 写盘 → `_read_save_file` 读回 → `_apply_save_dict`。
func _reopen() -> void:
	var f := FileAccess.open(_PROBE, FileAccess.WRITE)
	f.store_string(JSON.stringify(GameState._save_dict(), "  "))
	f.close()
	GameState.nickname = "<没读回来>"
	GameState.nickname_default = "<没读回来>"
	GameState.account_id = "<没读回来>"
	GameState.install_uid = "<没读回来>"
	var d = GameState._read_save_file(_PROBE)
	if d is Dictionary:
		GameState._apply_save_dict(d)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_PROBE))


func _t_default_name() -> void:
	print("── ⑤ 默认名像真人 ──")
	_ok("⑤ ★分母: 生成器组合空间非空", P2C.nickname_suggest_count() >= 100000, "%d" % P2C.nickname_suggest_count())

	## ① 一批账号: 没有一个是「龟主-」, 全合法, 全出自生成器池, 不全同名
	var bad: Array = []
	var seen := {}
	for i in range(200):
		var nm := str(P2C.nickname_fallback("acct-%d-%s" % [i, str(i * 7919).sha256_text().substr(0, 8)]))
		seen[nm] = true
		if nm.begins_with(_OLD_HEAD) or not _gen_ok(nm):
			bad.append(nm)
	_ok("⑤ ★★★200 个账号的默认名: 没有「龟主-」、全过 nickname_valid、不撞屏蔽词、不是旧版名字",
		bad.is_empty(), str(bad.slice(0, 5)))
	_ok("⑤ ★分母: 默认名是散开的(不是全员同一个名字)", seen.size() >= 100, "%d 种" % seen.size())

	## ② 全新存档(真入口: 清空身份 → 本机安装号 → 统一出处)
	GameState.nickname = ""
	GameState.nickname_default = ""
	GameState.account_id = ""
	GameState.install_uid = ""
	var uid := str(GameState.get_install_uid())
	_ok("⑤ ★分母: 新装机拿到了安装号", uid.length() == 12, uid)
	var n0 := str(BK.player_display_name())
	print("     新存档(只有安装号)的默认名: 「%s」" % n0)
	_ok("⑤ ★★★新存档默认名不是「龟主-」格式且合法",
		not n0.begins_with(_OLD_HEAD) and _gen_ok(n0), n0)
	_reopen()
	_ok("⑤ ★分母: 读回来的确实是那份存档(安装号对得上)", str(GameState.install_uid) == uid,
		str(GameState.install_uid))
	_ok("⑤ ★★★重开之后默认名不变", str(BK.player_display_name()) == n0,
		"%s → %s" % [n0, BK.player_display_name()])
	## 还没账号的两台新机器不许同名(只认账号的话, 所有离线新人都是同一个兜底名)
	var offline := {}
	for u in ["0de247d8b100", "9a1c33e07f42", "5b6e0c2d9a18", "c4f81e2b7d63"]:
		GameState.install_uid = u
		GameState.nickname_default = ""     # 每台都是新机器: 还没冻结过默认名
		offline[str(BK.player_display_name())] = true
	GameState.install_uid = uid
	_ok("⑤ ★★没账号时按安装号散开(4 台新机器 ≥ 3 个不同名字)", offline.size() >= 3, str(offline.keys()))

	GameState.nickname_default = ""
	var n0b := str(BK.player_display_name())
	## 已冻结的默认名, 之后拿到账号也不换(首启静默登录不该让名字跳一下)
	GameState.account_id = "e0a790fd-1111-2222-3333-444455556666"
	_ok("⑤ ★已冻结的默认名: 拿到账号之后不变", str(BK.player_display_name()) == n0b,
		"%s → %s" % [n0b, BK.player_display_name()])
	## 换设备找回账号、云存档里没有默认名(老客户端推的) ⇒ 按账号种子生成, 重开也不变
	GameState.nickname_default = ""
	var n1 := str(BK.player_display_name())
	print("     有账号之后的默认名: 「%s」" % n1)
	_ok("⑤ ★★有账号的默认名也不是「龟主-」且合法",
		not n1.begins_with(_OLD_HEAD) and _gen_ok(n1), n1)
	_reopen()
	_ok("⑤ ★★★有账号: 重开之后默认名不变", str(BK.player_display_name()) == n1,
		"%s → %s" % [n1, BK.player_display_name()])
	GameState.install_uid = "ffffffffffff"
	GameState.nickname_default = ""
	_ok("⑤ ★账号优先: 换一台机器(安装号不同)找回同一个号, 名字还是那个",
		str(BK.player_display_name()) == n1, str(BK.player_display_name()))

	## ③ 默认名不落盘 —— 「默认 vs 自己起的」靠的就是 nickname == ""
	_ok("⑤ ★★★显示过默认名之后 `nickname` 仍是空(没被写回, 否则就分不清是不是自己起的)",
		str(GameState.nickname) == "", "「%s」" % GameState.nickname)
	_ok("⑤ ★存档里也没有它", str(GameState._save_dict().get("nickname", "x")) == "",
		str(GameState._save_dict().get("nickname")))

	## 老玩家: 自己起过名的不动 —— 哪怕起的就是旧格式
	GameState.nickname = "龟主-ab12c"
	_ok("⑤ ★★★自己起过的名字(哪怕是「龟主-ab12c」)原样保留",
		str(BK.player_display_name()) == "龟主-ab12c", str(BK.player_display_name()))
	_reopen()
	_ok("⑤ ★分母: 重开之后也还是它", str(BK.player_display_name()) == "龟主-ab12c",
		str(BK.player_display_name()))
	GameState.nickname = ""


# ─────────────────────────────────────────────────────────────
# ⑥ ★★★默认名首次显示时冻结进存档(用户 2026-10-04 拍板)
#
# 生成器的结果跟着词表走(2026-10-07 前是 pets.json, 现在是 data/nickname-words.json)
#   ⇒ 词表一改所有没起名的人都会换名。
# ⇒ 第一次显示时把名字存进**独立字段** `nickname_default` 并落盘, 之后一直用它。
#   ① 真落盘(从磁盘读回来看)  ② 换池子之后已存的不变、没存过的按新池生成
#   ③ 自己起的名不受影响  ④ 绑定邮箱那屏预填的就是存下来的这个
# ─────────────────────────────────────────────────────────────
## 模拟「词表改了」: 在模板表最前面插一个大权重模板 —— 几乎每个账号的结果都会变。
const _FAKE_TPL := {"id": "phrase", "w": 500}

func _t_frozen_default() -> void:
	print("── ⑥ 默认名冻结进存档 ──")
	GameState.nickname = ""
	GameState.install_uid = "0de247d8b100"

	## ① 真落盘: 临时开闸让 save() 真写 user://, 再从磁盘读回来。原存档逐字节备份、量完还原。
	var path: String = GameState.SAVE_PATH
	var had := FileAccess.file_exists(path)
	var orig := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()
	GameState.nickname_default = ""
	GameState.account_id = "acct-disk-0001"
	GameState.test_mode = false
	var nm := str(BK.player_display_name())
	GameState.test_mode = true
	var d = GameState._read_save_file(path)
	var disk_def := str((d as Dictionary).get("nickname_default", "<无>")) if d is Dictionary else "<读不出>"
	var disk_nick := str((d as Dictionary).get("nickname", "<无>")) if d is Dictionary else "<读不出>"
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(orig)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_ok("⑥① ★★★第一次显示后, 默认名已经落盘(从磁盘读回来就是它)", disk_def == nm, "盘上「%s」 显示「%s」" % [disk_def, nm])
	_ok("⑥① ★★落的是独立字段, `nickname` 在盘上仍是空(「没自己起过名」的判据没被破坏)",
		disk_nick == "", "「%s」" % disk_nick)
	_ok("⑥① ★分母: 存档还原了", (not had and not FileAccess.file_exists(path))
		or (had and FileAccess.get_file_as_bytes(path) == orig))

	## ② 换池子。先找一个「池子一变生成结果就变」的账号 —— 不然「没变」是空检查。
	var acct := ""
	var before := ""
	var after := ""
	var tpls: Array = P2C.nickname_words().get("templates", [])
	tpls.insert(0, _FAKE_TPL)
	var shifted := {}
	for i in range(40):
		var a := "acct-pool-%d" % i
		shifted[a] = str(P2C.nickname_fallback(a))
	tpls.remove_at(0)
	for i in range(40):
		var a := "acct-pool-%d" % i
		if str(P2C.nickname_fallback(a)) != str(shifted[a]):
			acct = a
			break
	_ok("⑥② ★分母: 找到一个池子一变生成结果就变的账号", acct != "", acct)
	GameState.account_id = acct
	GameState.nickname_default = ""
	before = str(BK.player_display_name())          # 旧池下第一次显示 ⇒ 冻结
	tpls.insert(0, _FAKE_TPL)                        # ★池子变了(模拟词表改了)
	var gen_now := str(P2C.nickname_fallback(acct))
	var shown_now := str(BK.player_display_name())
	_ok("⑥② ★分母: 新池下生成器给这个账号的确实是另一个名字", gen_now != before, "%s → %s" % [before, gen_now])
	_ok("⑥② ★★★池子变了, 已存的默认名**不变**", shown_now == before, "%s → %s" % [before, shown_now])
	_reopen()
	_ok("⑥② ★★重开之后也还是它", str(BK.player_display_name()) == before, str(BK.player_display_name()))
	GameState.nickname_default = ""                  # 没存过的新档
	after = str(BK.player_display_name())
	_ok("⑥② ★★没存过的新档按新池生成", after == gen_now, "%s (新池应为 %s)" % [after, gen_now])

	## ③ 自己起的名字: 池子怎么变都不碰
	GameState.nickname = "阿龟大王"
	_ok("⑥③ ★★自己起的名字不受影响", str(BK.player_display_name()) == "阿龟大王", str(BK.player_display_name()))
	_ok("⑥③ ★默认名字段也没被它覆盖(起名与默认名两不相干)", str(GameState.nickname_default) == after,
		str(GameState.nickname_default))
	tpls.remove_at(0)
	_ok("⑥ ★分母: 注入的假模板已撤掉", tpls.is_empty() or int((tpls[0] as Dictionary).get("w", 0)) != int(_FAKE_TPL["w"]))

	## 云存档: 字段跟着云存档走(换设备找回账号带得回来); 老客户端推的(没这个键) ⇒ 按账号种子重新生成
	GameState.nickname = ""
	GameState.nickname_default = before
	var cp: Dictionary = GameState.cloud_payload()
	_ok("⑥ ★★默认名进了云存档载荷", str(cp.get("nickname_default", "<无>")) == before, str(cp.get("nickname_default", "<无>")))
	GameState.nickname_default = "别的机器上的名字"
	GameState.apply_cloud_payload(cp, int(GameState.cloud_rev))
	_ok("⑥ ★★新设备取回云存档 ⇒ 默认名就是云端那个", str(BK.player_display_name()) == before, str(BK.player_display_name()))
	var old_cp: Dictionary = cp.duplicate(true)
	old_cp.erase("nickname_default")
	GameState.apply_cloud_payload(old_cp, int(GameState.cloud_rev))
	_ok("⑥ ★云端没有这个键(老客户端) ⇒ 按账号种子生成", str(BK.player_display_name()) == str(P2C.nickname_fallback(str(GameState.account_id))),
		"%s / %s" % [BK.player_display_name(), P2C.nickname_fallback(str(GameState.account_id))])

	## ④ 绑定邮箱那屏的预填 = 存下来的默认名(走真屏幕)
	GameState.nickname = ""
	GameState.nickname_default = before
	var inst = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	inst._open_email_dialog(inst._SB_ACC.FLOW_BIND)
	await get_tree().process_frame
	var pre := str(inst._nick_edit.text) if inst._nick_edit != null else "<没框>"
	_ok("⑥④ ★★★绑定邮箱那屏预填的就是存下来的默认名", pre == before, "预填「%s」 存的「%s」" % [pre, before])
	inst.queue_free()
	await get_tree().process_frame


# ─────────────────────────────────────────────────────────────
# ⑧ ★★★旧版默认名一次性迁移(2026-10-07 · 用户「默认昵称你得看现实玩家会用的名字啊，你这一看就是人机」)
#
# 默认名首次显示即冻结(2026-10-04 拍板) ⇒ 生成器换了, 老号存档里冻着的还是「石头统领」这类。
#   ① 没自己起过名 + 冻着旧名 ⇒ 按同一个种子换成新生成器的名字、落盘, 之后不再变
#   ② `nickname` 本身是旧池名字(绑邮箱时预填写进去的) ⇒ 读档时当作没起过名、换新, 只一次;
#      旧池以外的名字一个字不碰(主会话 2026-10-07 代用户拍板)
#   ③ 已经是新名字的 ⇒ 不动
#   ④ 换过之后上传(快照名字)用的就是新名字
# ─────────────────────────────────────────────────────────────
const _OLD_DEFAULT := "石头统领"
const _OLD_DEFAULT2 := "不屈龟主"

func _t_migrate_legacy() -> void:
	print("── ⑧ 旧版默认名迁移 ──")
	_ok("⑧ ★分母: 「%s」「%s」被认成旧版默认名(认不出 ⇒ 下面全是空检查)" % [_OLD_DEFAULT, _OLD_DEFAULT2],
		P2C.nickname_is_legacy_default(_OLD_DEFAULT) and P2C.nickname_is_legacy_default(_OLD_DEFAULT2))
	_ok("⑧ ★分母: 新名字**不**被认成旧版(kevin_99 / 不吃香菜)",
		not P2C.nickname_is_legacy_default("kevin_99") and not P2C.nickname_is_legacy_default("不吃香菜"))

	## ① 有账号、没起过名、冻着旧名
	var acct := "acct-legacy-0001"
	GameState.account_id = acct
	GameState.install_uid = "0de247d8b100"
	GameState.nickname = ""
	GameState.nickname_default = _OLD_DEFAULT
	var want := str(P2C.nickname_fallback(acct))
	var shown := str(BK.player_display_name())
	print("     旧「%s」 ⇒ 新「%s」" % [_OLD_DEFAULT, shown])
	_ok("⑧① ★★★冻着旧名的号 ⇒ 显示的是新生成器按**同一个种子**给的名字", shown == want and shown != _OLD_DEFAULT,
		"显示「%s」 应为「%s」" % [shown, want])
	_ok("⑧① ★★新名字写回了 `nickname_default`(会落盘、随云存档走)", str(GameState.nickname_default) == want,
		str(GameState.nickname_default))
	_ok("⑧① ★`nickname` 仍是空(迁移不许把默认名写成「自己起的」)", str(GameState.nickname) == "", str(GameState.nickname))
	_ok("⑧① ★★新名字本身不是旧版的(否则下次又迁一次 ⇒ 名字来回跳)", not P2C.nickname_is_legacy_default(shown), shown)
	_ok("⑧① ★★再调一次还是它(只迁一次)", str(BK.player_display_name()) == want, str(BK.player_display_name()))
	_reopen()
	_ok("⑧① ★★★重开之后还是新名字(冻结住了)", str(BK.player_display_name()) == want and str(GameState.nickname_default) == want,
		"%s / %s" % [BK.player_display_name(), GameState.nickname_default])
	## ④ 上传: 快照里的名字跟着换
	GameState.season_leaders = ["basic", "fortune", "ninja"]
	var gid := str(BK.player_ghost_id(1, GameState.season_leaders, -1))
	var snap: Dictionary = BK.build_ghost_snapshot(gid, {"name": BK.player_display_name(), "avatar": "basic", "id": gid})
	_ok("⑧④ ★★上传的快照名字 = 新名字(不是旧的「%s」)" % _OLD_DEFAULT,
		str((snap.get("profile", {}) as Dictionary).get("name", "")) == want,
		str((snap.get("profile", {}) as Dictionary).get("name", "")))

	## ① 没账号(只有安装号)的老号也迁, 种子 = 安装号
	GameState.account_id = ""
	GameState.nickname_default = _OLD_DEFAULT2
	var want2 := str(P2C.nickname_fallback("0de247d8b100"))
	_ok("⑧① ★没账号的老号: 按安装号换", str(BK.player_display_name()) == want2 and want2 != _OLD_DEFAULT2,
		"%s / %s" % [BK.player_display_name(), want2])
	## 云存档: 另一台设备推来的还是旧名(那台还没升级) ⇒ 这边照样换成同一个(种子相同 ⇒ 两台对得上)
	GameState.account_id = acct
	GameState.nickname_default = want
	var cp: Dictionary = GameState.cloud_payload()
	cp["nickname_default"] = _OLD_DEFAULT
	GameState.apply_cloud_payload(cp, int(GameState.cloud_rev))
	_ok("⑧① ★★云端拉回来的是旧名 ⇒ 也换成同一个新名字(两台设备结果一致)", str(BK.player_display_name()) == want,
		str(BK.player_display_name()))

	## ② ★★2026-10-07 主会话代用户拍板: `nickname` 本身是旧池名字(绑定邮箱那屏把预填的旧默认名写成了「自己起的」)
	##   ⇒ 当作没起过名, 读档时清空, 默认名按同一个种子换新 —— 只一次。旧池以外的名字一个字不碰。
	GameState.account_id = acct
	GameState.nickname = _OLD_DEFAULT
	GameState.nickname_default = _OLD_DEFAULT
	_reopen()
	_ok("⑧② ★★★`nickname` 是旧池名字(绑邮箱时预填写进去的) ⇒ 读档后当作没起过名", str(GameState.nickname) == "",
		"「%s」" % GameState.nickname)
	_ok("⑧② ★★★显示的是同一个种子给的新名字", str(BK.player_display_name()) == want, "%s / 应为 %s" % [BK.player_display_name(), want])
	_reopen()
	_ok("⑧② ★★重开之后稳定(只迁一次)", str(GameState.nickname) == "" and str(BK.player_display_name()) == want,
		"「%s」 / %s" % [GameState.nickname, BK.player_display_name()])
	## 旧池以外的: 自己起的「龟龟大王」、长得像旧版但不在池里的「石头大王」「龟主-ab12c」—— 一个字不碰
	for keep in ["龟龟大王", "石头大王", "龟主-ab12c"]:
		GameState.nickname = keep
		GameState.nickname_default = want
		_reopen()
		_ok("⑧② ★★旧池以外的名字「%s」原样保留(重开之后也是)" % keep,
			str(GameState.nickname) == keep and str(BK.player_display_name()) == keep, str(BK.player_display_name()))
	## 只在读档时迁: 显示时不改(否则刚把名字改成旧池里那个的人会被当场改回去)
	GameState.nickname = _OLD_DEFAULT2
	_ok("⑧② ★运行中直接设成旧池名字 ⇒ 显示时不改(迁移只在读档时做)", str(BK.player_display_name()) == _OLD_DEFAULT2,
		str(BK.player_display_name()))

	## ③ 已经是新名字的: 不动(哪怕不是这个种子算出来的 —— 冻结就是冻结)
	GameState.nickname = ""
	GameState.nickname_default = "kevin_99"
	_ok("⑧③ ★★已经是新形状的默认名 ⇒ 不动", str(BK.player_display_name()) == "kevin_99", str(BK.player_display_name()))
	_reopen()
	_ok("⑧③ ★重开之后也不动", str(BK.player_display_name()) == "kevin_99", str(BK.player_display_name()))
	GameState.nickname_default = ""


# ─────────────────────────────────────────────────────────────
# ⑦ 改名(2026-10-04 · E 阶段方案书 ③ done-when:「GameState 有改名入口 且 verify_nickname 有『改名』一节」)
# ─────────────────────────────────────────────────────────────
## ★走真入口: 设置页账号行那颗「改昵称」→ 弹框 → 填字 → 真按「就叫这个」。
##   后端要**真开着**(账号行只在后端开着时才建) —— 门禁进程默认关, 不开的话
##   被测对象根本不在场(memory `fb-gate-subject-never-constructed`)。
func _find_named(n: Node, nm: String) -> Node:
	if str(n.name) == nm:
		return n
	for c in n.get_children():
		var f = _find_named(c, nm)
		if f != null:
			return f
	return null


func _t_rename() -> void:
	print("── ⑦ 改名 ──")
	const SETS := preload("res://scripts/scenes/SettingsScene.gd")
	## (a) 规则那一半(静态, 不建界面)
	GameState.nickname = "老名字"
	GameState.nickname_default = "默认的名"
	var e1: String = SETS.rename_apply("a")
	_ok("⑦a 太短 ⇒ 报错且不改", e1 != "" and str(GameState.nickname) == "老名字", "err「%s」 名「%s」" % [e1, GameState.nickname])
	var e2: String = SETS.rename_apply("一二三四五六七八九")
	_ok("⑦a 太长 ⇒ 报错且不改", e2 != "" and str(GameState.nickname) == "老名字", "err「%s」" % e2)
	var e3: String = SETS.rename_apply("  新  名字 ")
	_ok("⑦a ★合法 ⇒ 规范化后写进 nickname", e3 == "" and str(GameState.nickname) == "新 名字",
		"err「%s」 名「%s」" % [e3, GameState.nickname])
	_ok("⑦a ★★nickname_default 一个字不动(它是「没起过名」时用的)", str(GameState.nickname_default) == "默认的名",
		str(GameState.nickname_default))
	_ok("⑦a ★显示名跟着变(三处同源)", str(BK.player_display_name()) == "新 名字", str(BK.player_display_name()))
	_ok("⑦a ★走现有上传链路: 云存档载荷里就是新名字", str(GameState.cloud_payload().get("nickname", "")) == "新 名字")

	## (b) 界面那一半: 后端开着 + 有账号 ⇒ 账号行建出来
	var env0: String = OS.get_environment("TURTLE_SUPABASE")
	var key0 = ProjectSettings.get_setting("turtle/supabase_anon_key", "")
	OS.set_environment("TURTLE_SUPABASE", "https://example.invalid")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "sb_publishable_forgate")
	GameState.account_id = "11111111-2222-3333-4444-555555555555"
	GameState.account_email = ""
	GameState.nickname = "老名字"
	var inst = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(3):
		await get_tree().process_frame
	var btn = _find_named(inst, str(SETS.ACCT_ROW_PREFIX) + "BtnRename")
	_ok("⑦b ★分母: 设置页账号行里有「改昵称」", btn != null and btn is Button and str((btn as Button).text) == str(SETS.RENAME_LABEL),
		"节点 %s" % str(btn))
	if btn != null:
		(btn as Button).pressed.emit()
		await get_tree().process_frame
	var ed = _find_named(inst, str(SETS.RENAME_EDIT))
	var okb = _find_named(inst, str(SETS.RENAME_OK))
	var stl = _find_named(inst, str(SETS.RENAME_STATUS))
	_ok("⑦b ★分母: 点了真弹出改名框(名字框 + 确定键 + 状态行)", ed is LineEdit and okb is Button and stl is Label)
	if ed is LineEdit and okb is Button and stl is Label:
		_ok("⑦b 名字框预填的是现在的名字", str((ed as LineEdit).text) == "老名字", str((ed as LineEdit).text))
		(ed as LineEdit).text = "x"
		(okb as Button).pressed.emit()
		await get_tree().process_frame
		_ok("⑦b ★不合法 ⇒ 框上说原因、名字不改、框还开着",
			str((stl as Label).text) != "" and str(GameState.nickname) == "老名字" and is_instance_valid(ed) and (ed as Node).is_inside_tree(),
			"状态「%s」 名「%s」" % [(stl as Label).text, GameState.nickname])
		(ed as LineEdit).text = "改过的名"
		(okb as Button).pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_ok("⑦b ★★★真按「就叫这个」⇒ GameState.nickname 改了", str(GameState.nickname) == "改过的名", str(GameState.nickname))
		_ok("⑦b 改好之后框关掉", _find_named(inst, str(SETS.RENAME_EDIT)) == null)
	inst.queue_free()
	await get_tree().process_frame
	OS.set_environment("TURTLE_SUPABASE", env0)
	ProjectSettings.set_setting("turtle/supabase_anon_key", key0)


# ─────────────────────────────────────────────────────────────
# ⑧ 绑定邮箱那屏不许再说假话(2026-10-04)
# ─────────────────────────────────────────────────────────────
## 原文「⚠ 龟和装备是存在这台手机上的，换设备仍然会丢。」—— v0.19.425 起云存档已同步
##   除设备设置与身份之外的全部进度(`GameState.cloud_payload()`), 而只在绑了邮箱时同步
##   (`SupabaseNet.sync_allowed`)。这句话对绑了邮箱的人是**假的**。
## ★量的是屏幕上那两块说明文字(`_email_why` 第一步 / `_email_why2` 第二步), 不是源码。
## ★配一条事实断言: 载荷里真的有龟和装备(否则「能取回龟和装备」这句也成了假话)。
func _t_bind_copy() -> void:
	print("── ⑧ 绑定屏说明 ──")
	var cp: Dictionary = GameState.cloud_payload()
	_ok("⑧ ★分母: 云存档载荷里真有龟和装备(新文案的承诺成立)",
		cp.has("season_leaders") and cp.has("persistent_equipped") and cp.has("persistent_bench"), str(cp.keys().slice(0, 8)))
	var inst = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	inst._open_email_dialog(inst._SB_ACC.FLOW_BIND)
	await get_tree().process_frame
	var t1 := str(inst._email_why.text) if inst._email_why != null else ""
	var t2 := str(inst._email_why2.text) if inst._email_why2 != null else ""
	var all := t1 + "\n" + t2
	print("     第一步「%s」 / 第二步「%s」" % [t1, t2])
	_ok("⑧ ★分母: 两块说明都建出来了", t1 != "" and t2 != "")
	_ok("⑧ ★★★不再说「换设备仍然会丢」", all.find("换设备仍然会丢") < 0, all)
	_ok("⑧ ★说了绑定之后进度能取回", t1.find("恢复") >= 0 and t1.find("进度") >= 0, t1)
	_ok("⑧ ★说了没绑定时进度只在这台设备上", all.find("仅保存在本设备") >= 0, all)
	inst.queue_free()
	await get_tree().process_frame
