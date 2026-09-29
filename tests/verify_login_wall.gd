extends Node
## verify_login_wall.gd — 登录墙 (2026-09-24)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-09-24:「直接改为必须绑定账号吧」，在三个选项里选的是
## **开局就必须绑，没有 guest** —— 明确接受「没网 / 后端挂了就打不开」。
##
## 这道墙最容易出的两种错，各自成节：
##   ① **挡多了**：把「后端没配置」也挡住 ⇒ 384 条门禁当场全红、开发机打不开游戏。
##      「没配」是 dev 状态，不是玩家状态；「配了但连不上」才该挡。
##   ② **挡不住**：墙上留着「关闭」或返回键还能用 —— **关得掉的墙不是墙**。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 判定是纯函数 ⇒ **穷举** 后端配没配 × 绑没绑 四格，不靠起整个场景去试。
## ★② 「墙上没有关闭」不数源码，**真开一次墙、在节点树里数 Button**。
## ★③ 返回键：量它接的**方法名**（具名方法才量得到），再单独验那个方法在墙上不跳转。
## ★④ 每条都配分母：没墙时那些东西**必须在**，否则「墙上没有」是恒真式。
##
## 跑法: <godot> --headless --path . res://tests/verify_login_wall.tscn --quit-after 900

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const SET := preload("res://scripts/scenes/SettingsScene.gd")
const SB := preload("res://scripts/net/supabase.gd")
## ★素材路径与摆位几何都在产品那边(`WALL_ART_TEX` / `place_logo`),
##   测试里再抄一份就是抄一遍永远落后。
const WALL_ART := preload("res://scripts/scenes/settings/login_wall_art.gd")
const DEAD_URL := "http://127.0.0.1:9"

var _n := 0
var _fail := 0
const KEYS := ["account_email", "account_id", "nickname"]
var _bak := {}
## ★注入传输用: 记下**真实发出去的请求**(方法/地址/正文)。
## 照抄 `verify_session_refresh.gd` 的形状 —— 那是本仓验"发没发、发给谁"的标准写法。
var _reqs: Array = []


func _spy(method, url, headers, body, cb) -> void:
	_reqs.append({"method": str(method), "url": str(url), "body": str(body)})
	## 回一个"连不上", 让产品侧照常走它的失败分支(我们只关心它发没发)
	cb.call({"ok": false, "code": 0, "body": ""})


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
	print("=== 登录墙 ===")
	_t_rule()
	await _t_wall_ui()
	## ★★必须排在 `_t_identity_under_wall` **之前**: 那一节会真 `change_scene_to_file`
	##   把 MainMenu 加到 root 上, 而它**画在本门禁后面** ⇒ 它会把这一节推进去的
	##   鼠标事件全部吃掉(命中测试只认最上面那个)。顺序反了这一整节就是空检查。
	await _t_touch()
	await _t_identity_under_wall()
	for k in KEYS:
		GameState.set(k, _bak[k])
	SB._transport_for_test = Callable()
	OS.set_environment("TURTLE_SUPABASE", " ")
	SB._reset_auth_for_test()
	print("")
	print("  (共 %d 条断言)" % _n)

	## ══════════════════════════════════════════════════════════════════════
	##  ④ ★★★绑成功之后, 被挡住的人走得掉吗 (2026-09-27)
	## ══════════════════════════════════════════════════════════════════════
	## memory `fb-a-wall-must-let-the-unblocking-action-through`:
	## 加了拦截就要验「被拦住的人**能不能完成解锁动作**」。上面三节全在验「挡得住」,
	## 一条都没验「解锁之后放不放人」—— 而探针实测(`tests/_probe_wall_escape.gd`)
	## 原来**走不掉**: 遮罩不消、返回箭头还藏着, 屏幕写着「邮箱绑好了」,
	## 唯一出路是杀进程重开(重开能进, 因为邮箱已经写盘 ⇒ memory `fb-restart-is-a-separate-scenario`)。
	## 下周 10 人测试**第一个动作**就会撞上它。
	##
	## ★量的是产品自己的决策 `_post_bind_dest()`(纯函数), 不是我插的标记。
	##   为什么不直接调 `_email_poll` 走到底: 它会 `change_scene_to_file`,
	##   **当场把门禁自己拆掉** —— 本仓 `verify_mainmenu_layout` 2026-09-26 正是
	##   这样一周有两天整份不算数。⇒ 门禁量决策, 端到端交给探针。
	print("  ── ④ 绑成功之后走得掉吗 ──")
	GameState.account_email = ""
	var st4 = SET.new()
	st4.acct_override = 1                        ## 强制「后端开着 + 未绑定」= 墙的条件
	add_child(st4)
	for _i4 in range(4):
		await get_tree().process_frame
	_ok("④ ★分母: 墙真的立起来了(没立起来 ⇒ 下面全是空检查)",
		st4._email_layer != null and is_instance_valid(st4._email_layer))
	_ok("④ ★分母: 这一刻**还不能**放人走(还没绑)",
		st4._post_bind_dest() == "", st4._post_bind_dest())

	## 绑成功: 邮箱落地 ⇒ `login_wall_on` 变假。**不碰 `_post_bind_dest` 自己的任何字段**。
	GameState.account_email = "tester@x.co"
	st4.acct_override = 0                        ## 回到真实取值
	_ok("④ ★★★绑成功之后**放人进主菜单**(原来这里只把字染成绿色, 人一步也走不了)",
		st4._post_bind_dest() == "res://scenes/MainMenu.tscn", st4._post_bind_dest())
	st4.queue_free()
	await get_tree().process_frame

	## ★对照组: **自己点开的**对话框(可关闭)绑成功后不该跳走 —— 他在设置里,
	##   跳走等于把他从正在看的页面上扯开。⇒ 判据必须分得清「墙」和「自己点开的」。
	GameState.account_email = "tester@x.co"
	var st5 = SET.new()
	add_child(st5)
	await get_tree().process_frame
	st5._open_email_dialog(SB.FLOW_BIND)          ## 可关闭那一档
	await get_tree().process_frame
	_ok("④ ★分母: 自己点开的对话框真的开着", st5._email_layer != null)
	_ok("④ ★★对照组: **自己点开的**对话框绑成功后留在原地(不跳走)",
		st5._post_bind_dest() == "", st5._post_bind_dest())
	st5.queue_free()
	await get_tree().process_frame

	## ══════════════════════════════════════════════════════════════════════
	##  ⑤ ★★★墙上必须印版本号 (2026-09-28)
	## ══════════════════════════════════════════════════════════════════════
	## 用户实测撞上的: 他被墙挡住、报「邮箱注册没用」, 而**说不出自己装的是哪个版本** ——
	## 因为版本号只画在**主菜单右下角**(`MainMenuScene.gd:659`), 而这堵墙**挡在主菜单之前**。
	## ⇒ **最需要报版本的人, 恰恰是唯一看不到版本的人。**
	## CLAUDE.md §2.5 原话:「版本号的全部价值在于测试者报 bug 时能说清是哪个版本」
	## —— 那句话在这一屏上一直不成立, 而这一屏是**每个新玩家看到的第一屏**。
	## ★判据量两件事: ①墙上真的有那行字 ②它**等于 ProjectSettings 里的真值**
	##   (不许写死 —— 写死的版本号比没有更坏: 它会一直报一个假版本)。
	print("── ⑤ 墙上要印版本号 ──")
	GameState.account_email = ""          ## 没绑邮箱 ⇒ 墙该立起来
	var st6 = SET.new()
	add_child(st6)
	await get_tree().process_frame
	st6._open_email_dialog(SB.FLOW_BIND, false)   ## false = **墙**那一档
	await get_tree().process_frame
	_ok("⑤ ★分母: 墙真的建起来了(否则下面量的是空气)", st6._email_layer != null)
	var _vtxt := ""
	var _stack: Array = [st6]
	while not _stack.is_empty():
		var n = _stack.pop_back()
		if n is Label and str((n as Label).text).begins_with("版本 "):
			_vtxt = str((n as Label).text)
		for c in (n as Node).get_children():
			_stack.append(c)
	var _real := str(ProjectSettings.get_setting("application/config/version", ""))
	_ok("⑤ ★分母: ProjectSettings 里读得到版本(读不到的话下一条是空检查)",
		_real != "", _real)
	_ok("⑤ ★★★墙上印着版本号(被墙挡住的人才报得出自己是哪个版本)",
		_vtxt != "", _vtxt)
	_ok("⑤ ★★墙上那个版本 == ProjectSettings 的真值(不许写死)",
		_vtxt.find(_real) >= 0, "墙上「%s」 vs 真值「%s」" % [_vtxt, _real])
	st6.queue_free()
	await get_tree().process_frame

	print("ALL PASS — 登录墙" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 判定: 四格穷举
# ─────────────────────────────────────────────────────────────
func _t_rule() -> void:
	print("── ① 什么时候挡 ──")
	_ok("① ★★后端配了 + 没绑 ⇒ **挡**", P2C.login_wall_on(true, ""))
	_ok("① 后端配了 + 绑了 ⇒ 不挡", not P2C.login_wall_on(true, "me@x.co"))
	_ok("① ★★★后端**没配**(dev/门禁) ⇒ **不挡** —— 挡住的话 384 条门禁当场全红",
		not P2C.login_wall_on(false, ""))
	_ok("① 后端没配 + 绑了 ⇒ 不挡", not P2C.login_wall_on(false, "me@x.co"))
	## ★空白邮箱也算没绑 —— 存档里留一串空格不该当成绑过了
	_ok("① ★邮箱是空白 ⇒ 仍然挡", P2C.login_wall_on(true, "   "))
	## 文案: 墙上第一句要让老玩家别慌
	var body := str(P2C.login_wall_body())
	print("     墙上第一句: 「%s」" % body.split("\n")[0])
	_ok("① ★★墙上第一句先说【进度还在】—— 老玩家升级过来会被挡一次, 别让他以为丢了",
		body.find("进度还在") >= 0, body.substr(0, 40))
	_ok("① ★还告诉他收不到验证码怎么办(不然就是死路)",
		body.find("垃圾") >= 0 or body.find("重发") >= 0 or body.find("换一个") >= 0,
		body.substr(0, 60))
	_t_copy_tone()
	_t_suggest_pool()


# ──────────────────────────────────────────────────────────
# ⑦ B · ★★★恐吓换成退路 (2026-09-29)
#
#    量出来的依据(`tools/login_screen_audit.py`, 13 屏逐像素):
#    参考里「以后还能改」这句话到处都是(Pokémon HOME / Nier / Octopath /
#    Smash Legends / Sonic Rumble), 而**没有一屏是靠恐吓把人推过去的**。
#
#    ★★两边都要守, 只守一边就会把事情弄反:
#      · 只守「不许恐吓」⇒ 下一个人把丢档那句话删干净也绿, 而那是用户 2026-09-24
#        点名要的(「这一点要在 UI 上说清楚」)。
#      · 只守「事实要在」⇒ 又退回原样。
#    ★★★判据自己能不能 FAIL 当场证: 拿**旧那两句原文**当样本跑同一个谓词,
#    它必须被判成恐吓 —— 否则这整节是恒真式。
# ──────────────────────────────────────────────────────────
## “这句话在吓人”的谓词。★只看**第一句** —— 参考的做法是第一句说得到什么,
##   代价往后摆; 把「业务会丢」摆在第一眼就是用恐惧开场。
## ★“⚠” 也算 —— 它是警告标, 不是句子。
func _is_scary(first_line: String) -> bool:
	return first_line.find("丢") >= 0 or first_line.find("⚠") >= 0


## ★不带 await —— `_t_rule` 是同步的, 把它变成协程 ⇒ `_ready` 会跳过它往下跑,
##   后面那几节的断言**静默少跑**(memory `fb-null-readback-makes-test-silently-abort`)。
func _t_copy_tone() -> void:
	print("── ⑦B 恐吓 → 退路 ──")
	var body := str(P2C.login_wall_body())
	var lines: PackedStringArray = body.split("\n")
	for i in range(lines.size()):
		print("     [%d] %s" % [i, str(lines[i])])
	## ★分母①: 谓词真的会 FAIL —— 拿旧版原文试一遍。
	##   这两句是 v0.19.471 与 D-3 那两版的原文(审计报告里引的就是它们)。
	var OLD_A := "你的进度还在这台手机上 —— 不绑就会丢档"
	var OLD_B := "⚠ 龟和装备是存在这台手机上的，换设备仍然会丢。"
	_ok("⑦B ★分母: 谓词拿旧版原文跑一遍 **两句都判成恐吓**(判不出来 ⇒ 下面恒真)",
		_is_scary(OLD_A) and _is_scary(OLD_B),
		"A=%s B=%s" % [str(_is_scary(OLD_A)), str(_is_scary(OLD_B))])
	_ok("⑦B ★★★第一句**不再是恐吓**(不开口就说丢档 / 不抬⚠)",
		not _is_scary(str(lines[0])), str(lines[0]))
	_ok("⑦B ★★★说了**以后还能改**(参考里到处都是这句, 它把这一步的心理成本压下去)",
		body.find("以后") >= 0 and body.find("改") >= 0, body)
	## ★★用户 2026-09-24 点名的那个**事实不许删**。两个字都要在:
	##   “不绑”(条件) + “换手机/换设备”(场景) —— 只剩一个就不叫说清楚了。
	_ok("⑦B ★★★「没绑邮箱换手机就拿不回来」这个**事实还在**(用户 2026-09-24 点名要的)",
		body.find("不绑") >= 0 and (body.find("换手机") >= 0 or body.find("换设备") >= 0), body)
	## `verify_account` §④ 的禁令: 服务端根本没存存档, 不许承诺「存档」能找回。
	var lied: Array = []
	for bad in ["丢失存档", "取回存档", "找回存档"]:
		if body.find(str(bad)) >= 0:
			lied.append(str(bad))
	_ok("⑦B ★不许冒出「取回存档」这类假承诺(与 `verify_account` ④ 同一条禁令)",
		lied.is_empty(), str(lied))
	## ★按步分发的前提: 至少两行, 而**最后一行必须是「收不到码」**那一句 ——
	##   `SettingsScene` 就是拿最后一行当第二步的文字的。顺序反了,
	##   第二步会去印「不绑会…」而当下正在等码的人需要的是「收不到怎么办」。
	_ok("⑦B ★分母: 文案至少两行(只一行 ⇒ 两步就共用同一句, 分发没意义)",
		lines.size() >= 2, "%d 行" % lines.size())
	_ok("⑦B ★★最后一行是「收不到验证码」那句(第二步就拿它当正文)",
		str(lines[lines.size() - 1]).find("验证码") >= 0, str(lines[lines.size() - 1]))
	## ★而第一步印的那几行里**不该**有「收不到码」—— 那一步还没发码。
	var head_join := "\n".join(lines.slice(0, maxi(lines.size() - 1, 1)))
	_ok("⑦B ★第一步要印的那几行里没有「收不到码」(还没发码, 印了只是多两行字)",
		head_join.find("收不到") < 0, head_join)


# ──────────────────────────────────────────────────────────
# ⑦ A · ★★★名字池: 全池穷举 + 熵 (2026-09-29)
#
#    参考里取名那一步的设计目标是「不打字也能过」⇒ 昵称框预填一个名字。
#    ★★判据不能只问「有没有预填」—— 预填一个**固定**名字也能过那一条,
#      而那会让排行榜上一片同名。⇒ 要量**熵**: N 次生成有多少个不同的。
#    ★三条各管一事, 缺一条就能被蒙过去:
#      ① 全池每一个名字都合法(不超 `NICK_MAX`) —— 否则玩家一点确认就报错
#      ② 名字**像这个游戏的** —— 字形得能在 pets.json 里找到出处, 且没有 ASCII
#      ③ 熵 —— 池子大小 + 重复率
# ──────────────────────────────────────────────────────────
## “这个名字像不像这个游戏的”的谓词。两位一体:
##   · 没有 ASCII 字母/数字(`Player_561962` 就是这样被判掉的)
##   · 去掉尾部名头之后剩下的字**在 pets.json 里找得到**(龟名或被动技名)
func _looks_like_this_game(s: String) -> bool:
	for i in range(s.length()):
		var c := s.unicode_at(i)
		if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95:
			return false
	var stem := s
	for h in P2C.NICK_HEADS:
		if s.ends_with(str(h)):
			stem = s.substr(0, s.length() - str(h).length())
			break
	if stem == s or stem == "":
		return false
	for p in DataRegistry.all_pets:
		var pd := p as Dictionary
		if str(pd.get("name", "")).find(stem) >= 0:
			return true
		if str((pd.get("passive", {}) as Dictionary).get("name", "")).find(stem) >= 0:
			return true
	return false


func _t_suggest_pool() -> void:
	print("── ⑦A 名字池 ──")
	var n: int = P2C.nickname_suggest_count()
	var stems: Array = P2C.nickname_stems()
	print("     池子 = %d 个定语 × %d 个名头 = %d 个名字"
		% [stems.size(), P2C.NICK_HEADS.size(), n])
	## ★分母①: 池子真的建起来了。N=0 时下面的「每一个都合法」是空检查。
	_ok("⑦A ★分母: 池子里真有名字(N=%d, 读不到 pets.json 就只剩兑底的 6×6)" % n,
		n >= 150 and stems.size() >= 40, "定语 %d / 名字 %d" % [stems.size(), n])
	## ★★词表的**出处**也要守: `NICK_WORDS` 只拿得出名头表 + 定语的源文件,
	##   定语池本身必须是从那个文件摸出来的 —— 哪天有人把 28 个龟名抄进
	##   代码里当常量, 新加的龟就悄悄不进池了(memory `fb-hand-rolled-copies-drift`)。
	var words: Dictionary = P2C.NICK_WORDS
	var src: String = str(words.get("stem_src", ""))
	_ok("⑦A ★`NICK_WORDS` 指的词表源文件真存在: %s" % src,
		src != "" and ResourceLoader.exists(src) and (words.get("heads", []) as Array).size() >= 4,
		"src=%s heads=%d" % [src, (words.get("heads", []) as Array).size()])
	## 定语池是不是真从那个文件摸的: 每一个定语都要能在 pets.json 里找到。
	var orphan: Array = []
	for st in stems:
		var hit := false
		for p in DataRegistry.all_pets:
			var pd := p as Dictionary
			if str(pd.get("name", "")).find(str(st)) >= 0 \
					or str((pd.get("passive", {}) as Dictionary).get("name", "")).find(str(st)) >= 0:
				hit = true
				break
		if not hit:
			orphan.append(str(st))
	_ok("⑦A ★★`NICK_WORDS` 的 %d 个定语**每一个**都在 pets.json 里找得到(不是手抄的表)" % stems.size(),
		orphan.is_empty(), "找不到出处的 %d 个: %s" % [orphan.size(), str(orphan.slice(0, 5))])
	## ① 全池穷举: 每一个都得合法, 且像这个游戏的
	var bad_len: Array = []
	var bad_style: Array = []
	var seen_all: Dictionary = {}
	var heads: int = P2C.NICK_HEADS.size()
	for idx in range(n):
		var s := str(P2C.nickname_suggest_at(idx / heads, idx % heads))
		seen_all[s] = true
		if not P2C.nickname_valid(s):
			bad_len.append("%s(%d 字)" % [s, s.length()])
		if not _looks_like_this_game(s):
			bad_style.append(s)
	print("     例: %s" % str(seen_all.keys().slice(0, 8)))
	_ok("⑦A ★★全池 %d 个名字**每一个**都过 `nickname_valid`(2~%d 字)" % [n, P2C.NICK_MAX],
		bad_len.is_empty(), "越线 %d 个: %s" % [bad_len.size(), str(bad_len.slice(0, 5))])
	_ok("⑦A ★★★全池 %d 个名字都**像这个游戏的**(字在 pets.json 里找得到 · 没 ASCII)" % n,
		bad_style.is_empty(), "不像的 %d 个: %s" % [bad_style.size(), str(bad_style.slice(0, 5))])
	## ★分母②: 谓词真的会 FAIL —— 拿参考里那两个名字跑一遍。
	_ok("⑦A ★分母: 谓词把 `Player_561962` / `AwesomeHyacinth` 判成**不像**(判不出 ⇒ 上条恒真)",
		not _looks_like_this_game("Player_561962")
			and not _looks_like_this_game("AwesomeHyacinth"))
	_ok("⑦A ★分母: 谓词把池子里随便一个判成**像**(判不出 ⇒ 上条也恒真)",
		_looks_like_this_game(str(P2C.nickname_suggest_at(0, 0))),
		str(P2C.nickname_suggest_at(0, 0)))
	## ③ 熵: 抽 400 次, 数去重。
	##   ★★固定预填一个名字 ⇒ 去重 = 1; 这条把它卡在外面。
	##   期望值 = N×(1-(1-1/N)^400); N=336 时 ≈ 233 ⇒ 卡 120 留着余量。
	var draws := 400
	var seen: Dictionary = {}
	for _i in range(draws):
		seen[str(P2C.nickname_suggest())] = true
	print("     熵: 抽 %d 次 ⇒ %d 个不同的(池子 %d)" % [draws, seen.size(), n])
	_ok("⑦A ★★★**名字熵**够: 抽 %d 次至少 120 个不同(固定预填一个名字 ⇒ 只有 1 个)" % draws,
		seen.size() >= 120, "实测 %d 个" % seen.size())
	## ★「换一个」永远不该给同一个名字 —— 全池逐个验。
	var same: Array = []
	for k in seen_all.keys():
		if str(P2C.nickname_suggest(str(k))) == str(k):
			same.append(str(k))
	_ok("⑦A ★★★全池 %d 个名字每一个当 avoid 传进去, 都**不会再得到它**(否则就是点了没反应)" % seen_all.size(),
		same.is_empty(), "重复的 %d 个: %s" % [same.size(), str(same.slice(0, 5))])


# ─────────────────────────────────────────────────────────────
# ② ★★真开一次墙: 关不掉、返回不了
# ─────────────────────────────────────────────────────────────
func _t_wall_ui() -> void:
	print("── ② 墙关不关得掉 ──")
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._reset_auth_for_test()
	GameState.account_email = ""
	GameState.account_id = "uid-wall"

	var st = SET.new()
	add_child(st)
	await get_tree().process_frame
	_ok("② ★分母: 后端算「配了」(否则下面全是空检查)", SB.enabled())
	_ok("② ★★墙真的开了(对话框在场)",
		st._email_layer != null and is_instance_valid(st._email_layer),
		str(st._email_layer))

	var btns := _buttons(st._email_layer)
	var labels: Array = []
	for b in btns:
		labels.append(str((b as Button).text))
	print("     墙上的按钮: %s" % str(labels))
	_ok("② ★★★墙上**没有「关闭」** —— 关得掉的墙不是墙",
		not labels.has("关闭"), str(labels))
	_ok("② ★分母: 墙上该有的按钮在(发验证码 / 确认)",
		labels.has("发验证码") and labels.has("确认"), str(labels))
	## ★★实拍拓出来的: 顶栏在更高的 CanvasLayer 上, 遮罩盖不住返回箭头 ⇒
	##   它看着能按、按下去却没反应。本仓原则:「点了没反应」比「按钮是灰的」糟得多。
	_ok("② ★★★墙上返回箭头**藏起来了**(而不是留着让人点了没反应)",
		st._top_bar != null and st._top_bar.back_btn != null
			and not st._top_bar.back_btn.visible,
		str(st._top_bar.back_btn.visible) if st._top_bar != null else "<no bar>")
	st.queue_free()
	await get_tree().process_frame

	## ★同一个对话框在**设置里主动绑定**时该有「关闭」—— 否则上面那条是恒真式
	GameState.account_email = "me@x.co"          # 绑过了 ⇒ 不开墙
	var st2 = SET.new()
	add_child(st2)
	await get_tree().process_frame
	_ok("② ★分母: 绑过了就不开墙", st2._email_layer == null, str(st2._email_layer))
	st2._open_email_dialog(SB.FLOW_BIND)          # 主动打开(可关闭那一档)
	await get_tree().process_frame
	var labels2: Array = []
	for b in _buttons(st2._email_layer):
		labels2.append(str((b as Button).text))
	_ok("② ★★分母: **主动**打开时「关闭」在 —— 证明上面那条是「墙」挡的, 不是对话框本来就没有",
		labels2.has("关闭"), str(labels2))

	_ok("② ★返回键接的是具名方法 `_on_back`(匿名闭包门禁量不到)",
		st2.has_method("_on_back"))
	_ok("② ★分母: 没墙时返回箭头**看得见**(否则下面那条是恒真)",
		st2._top_bar != null and st2._top_bar.back_btn != null
			and st2._top_bar.back_btn.visible,
		str(st2._top_bar.back_btn.visible) if st2._top_bar != null else "<no bar>")
	st2.queue_free()
	await get_tree().process_frame


# ─────────────────────────────────────────────────────────────
# ③ ★★被墙挡住的人, 还拿不拿得到服务端身份
#
#    v0.19.440 上墙之后出的真 bug(2026-09-24 实测): 主菜单 `_ready` 里
#    `ensure_signed_in_async()` 排在墙的 `return` **后面** ⇒ 全新安装永远没有 token
#    ⇒ 点「发验证码」撞上 FLOW_BIND 的 `_token != ""` 前置条件 ⇒ 回「先联网开一局再绑」
#    ⇒ **而墙正好不让他开局**。唯一兜底是 GameState 那个第一次要等 20 秒的保活 tick。
#
#    这一节守两件事, 缺一不可:
#      ①「墙触发了, 身份照样在建」—— 真走主菜单入口量, 不看源码顺序
#         (源码顺序是我改的东西, 拿它当判据等于自己数自己)
#      ②「提示不许教玩家去做墙不让他做的事」—— 量**函数真的吐出来的那句话**
# ─────────────────────────────────────────────────────────────
func _t_identity_under_wall() -> void:
	print("── ③ 被墙挡住时, 身份还建不建 ──")
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._reset_auth_for_test()
	GameState.account_email = ""
	GameState.account_id = ""

	## ── ②先验文案: 没有 token 时点「发验证码」, 玩家看到什么 ──
	_ok("③ ★分母: 复位之后确实没有 token(否则下面走不到那一支)", SB._token == "")
	SB.send_code_async("newplayer@example.com", SB.FLOW_BIND)
	var msg := str(SB._email_msg)
	print("     玩家看到: 「%s」" % msg)
	_ok("③ ★分母: 确实走到了「没有 token」那一支(state=err 且有话说)",
		SB._email_state == SB.EM_ERR and msg != "", "%s / %s" % [SB._email_state, msg])
	_ok("③ ★★★提示不许教玩家「先开一局」—— 墙就是开局前那一屏, 他做不到",
		msg.find("开一局") < 0, msg)
	_ok("③ ★提示要说清现在在干嘛 + 怎么办(不然玩家只知道失败了)",
		msg.find("再点") >= 0 or msg.find("重试") >= 0 or msg.find("再试") >= 0, msg)
	## 验码那一侧同一句话的另一份拷贝(`bind_accepts`), 一起守 —— 两处各写一份必然漂
	var br: Dictionary = SB.bind_accepts({"ok": true, "account_id": "a"}, "")
	_ok("③ ★分母: `bind_accepts` 确实走到「本机没账号」那一支",
		not bool(br.get("ok", true)) and str(br.get("reason", "")) != "", str(br))
	_ok("③ ★★`bind_accepts` 的同一句话也不许说「开一局」",
		str(br.get("reason", "")).find("开一局") < 0, str(br.get("reason", "")))

	## ── ①再验真入口: 走一次真实开机, 看墙触发之后身份有没有在建 ──
	## ★★★判据换过一次(2026-09-24 CI 当场红): 原来量的是 `_auth_inflight`,
	##   那是个**瞬时量** —— 只在请求在飞的那几帧为真, 回包一到就被清回 false。
	##   同一份代码, 本地跑到 412 帧它还是 true, CI 上 16 帧就已经是 false 了
	##   ⇒ 这条判据的答案**跟机器快慢走**, 本地必绿、CI 必红(本仓「尺子跟机器速度走」那一族)。
	## ⇒ 改成注入传输, 量**真实发出去的那个请求**: 发没发、发去哪儿。
	##   它是记录下来的, 不会被时间清掉; 而且量的是产品自己拼的 URL, 不是我插的计数器。
	SB._reset_auth_for_test()
	_reqs.clear()
	SB._transport_for_test = _spy
	## ★★给一张**待补报的单子**, 否则「补报跑没跑」那条恒绿(没单子本来就不该发)。
	##   token/account 也要给 —— 补报那条与看桶/报名同一道闸:「服务端认得出你是谁」。
	GameState.finals_report_pending = {"bucket": 1, "round": 2, "match": 0, "side": 0, "seed": 9}
	GameState.account_id = "uid-wall"
	SB._token = "tok-wall"
	SB.finals_report_clear()
	## ★★同样给**报名**那条的前置, 否则它那一条也恒绿:
	##   已晋级(闯关赛 4 胜 = state "in") + 本周还没报到 + 有阵容。
	GameState.promoted = true
	GameState.gauntlet_wins = 4
	GameState.gauntlet_losses = 0
	GameState.week_anchor_ts = 1789862400
	if (GameState.season_leaders as Array).is_empty():
		GameState.season_leaders = ["basic", "fire", "shell"]
	## 「本周还没报到」= `finals_entered_week != 本周` —— 判据在 `SB.finals_entered()`,
	## 这里只要把那个字段清掉就行(它就是产品自己的记账)。
	GameState.finals_entered_week = 0
	_ok("③ ★★分母: 进主菜单之前一个请求都没发 —— 否则下面那条是恒真式",
		_reqs.size() == 0, str(_reqs.size()))
	## ★不能直接 `change_scene_to_file`: 门禁自己就是 `current_scene`, 那一句当场把
	##   门禁拆掉(本仓踩过)。先把 current_scene 置空 —— 引擎只 `memdelete(current_scene)`,
	##   置空之后它谁也不删, 门禁作为 root 的普通子节点活下来继续量。
	## ★必须走真 `change_scene_to_file`: 墙的条件里有 `current_scene == self`,
	##   手动 `add_child` 的话墙根本不会触发(第一版探针就是这么骗过自己的)。
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	for _i in 16:
		await get_tree().process_frame
	var cur := get_tree().current_scene
	_ok("③ ★★分母: 墙**真的触发了**(被送到 Settings) —— 否则下面量的是没墙的路径",
		cur != null and cur.name == "Settings", cur.name if cur != null else "<null>")
	var urls: Array = []
	for r in _reqs:
		urls.append(str(r.get("url", "")).replace(DEAD_URL, ""))
	print("     墙触发之后, 真实发出去的请求: %s" % str(urls))
	_ok("③ ★★★墙触发之后, 建身份**仍然跑了** —— 不跑的话玩家永远发不出验证码",
		urls.has("/auth/v1/signup"), str(urls))
	## ★★★同一条纪律的第二例(2026-09-27): 决赛日那一场的**结果补报**也挂在主菜单
	##   `_ready` 上, 和建身份并排。挂在墙的 `return` **后面**的话, 被墙挡住的人
	##   (=没绑邮箱的)永远补不了报 —— 而本仓正是这样把 `ensure_signed_in_async`
	##   排丢过一次(「全新安装的头 20 秒打不开游戏」)。
	## ★量的是**真实发出去的那个请求**, 不是「函数被调用了」这种我自己插的标记。
	_ok("③ ★★★墙触发之后, 决赛日**结果补报**仍然跑了(排在墙后面 = 被挡住的人永远补不了报)",
		urls.has("/rest/v1/rpc/finals_report"), str(urls))
	## ★★★第三条(2026-09-27 补齐): **报名**也挂在这儿, 而它正是 v0.19.446 修的那条
	##   (「那一刻没网 / token 刚过期 / 杀了 App 就静默漏报, 而报名在周六第 4 胜那一刻」)。
	##   三条「必须在墙之前跑」的调用, 原来只有两条有门禁守着。
	_ok("③ ★★★墙触发之后, 决赛日**报名补报**也仍然跑了(v0.19.446 修的那条, 位置没人守)",
		urls.has("/rest/v1/rpc/finals_enter"), str(urls))
	SB._transport_for_test = Callable()
	GameState.finals_report_pending = {}
	SB.finals_report_clear()
	_reqs.clear()


# ─────────────────────────────────────────────────────────────
# ⑥ ★★★墙上到底点得到吗 —— 触摸层 (2026-09-28)
#
#    由来: 用户真机报「邮箱注册没用, app 里操作没反应」。
#    发信层(手工 `PUT /auth/v1/user` 回 200 · 两个邮箱都收到码)与客户端状态机
#    (`tests/_probe_wall_live.gd` 真后端实测 token→sending→sent)都已排除
#    ⇒ 剩下**触摸层**这一条从没人查过, 而上面 ①~⑤ 一条都不碰它:
#    它们验的是「墙该不该立」「关不关得掉」「放不放人」「印没印版本」,
#    **没有一条验「玩家的手指按下去, 产品有没有动」**。
#
#    ★三件事各自成段, 每段都配分母:
#      ⑥a 热区 + **谁吃到这一点**(`gui_get_hovered_control` 让引擎自己算, 不看
#          `mouse_filter` 猜 —— `RichTextLabel` 那条坑证明光看 filter 是不够的)
#      ⑥b **按下去真的有事发生**: 推真 `InputEventMouseButton`, 看产品状态/真实请求
#      ⑥c **虚拟键盘**: 全仓原来一处都没处理(`grep -rn virtual_keyboard --include=*.gd` = 0),
#          而 iPhone 横屏键盘 41.5% 屏高 ⇒ 实测「验证码」框与「确认」钮都在键盘底下。
# ─────────────────────────────────────────────────────────────
## iPhone 14/15 横屏画布(2.167:1) —— 与 `verify_ios_ui` 同一口径。
const VP_PHONE := Vector2(1560.0, 720.0)
## 本仓触控线: 81px = 44pt(见 `top_bar.gd` / `verify_ui_consistency.TOUCH_MIN`)。
const PX_PER_PT := 81.0 / 44.0


func _wf(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


## 这棵子树里**玩家能操作**的控件。判据与 `verify_ui_consistency._interactive` 同口径。
func _hot(root) -> Array:
	var out: Array = []
	if root == null or not is_instance_valid(root):
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			if c is BaseButton or c is Range or c is LineEdit or c is TextEdit:
				out.append(c)
		for ch in (n as Node).get_children():
			stack.append(ch)
	return out


func _txt_of(c: Control) -> String:
	if c is Button:
		return str((c as Button).text)
	if c is LineEdit:
		return "输入框「%s」" % str((c as LineEdit).placeholder_text)
	return c.name


## 引擎在 `p` 这一点真正选中的是谁 —— 推真 MouseMotion, 让 GUI 系统自己算。
func _hover_at(p: Vector2) -> Control:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	get_viewport().push_input(mm)
	var h = get_viewport().gui_get_hovered_control()
	return h as Control if h is Control else null


func _tap(p: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		get_viewport().push_input(e)


## 本仓触摸线 81px = 44pt, 与 `verify_ui_consistency.TOUCH_MIN` 同一个数。
const TOUCH_MIN_PX := 81.0
## 相邻靶子至少要隔多少。★这一条**没有权威出处**(44pt 有: iOS HIG),
##   是 2026-09-28 本轮拍的下限 —— 上一版实测只有 **4 / 6 / 12 / 6 px**,
##   而「瞄发验证码高 7px 就点进邮箱框」正好弹出键盘 = 玩家看到的「点了没反应」。
## ★★★ 2026-09-29 从 12 抬到 20(棘轮: 只往上)。依据不再是“拍”:
##   参考真值(`python tools/login_screen_audit.py thresholds`, 13 屏逐像素):
##     最小相邻间隙 中位 **23.3pt(≈43px)** · p10 9.2pt · 地板 Hungry Shark 8.2pt。
##   旧值 12px = **6.5pt**, 低于参考里任何一屏。
##   新值 21px = **11.4pt**, 过了地板与 p10, 但还到不了中位 —— 因为中位在
##   「一步三行 44pt」的前提下**算不出来**(见 ⑥e 那条天花板判据)。
## ★为何卡 20 而不是 21: 这一条只管“别掉回去”; “有没有抬到顶”由 ⑥e 两头卡住。
const GAP_MIN_PX := 20.0
## ★★★`GAP_RAISED` 棘轮的旧值。卡「严格大于旧值」而不是「等于 21」 ——
##   写死等于 21 会把下一次合理的上调也判成红; 而只卡 ≥12 等于没抬。
##   「有没有抬到顶」由 ⑥g 那两条两头卡住。
const GAP_RAISED_FROM := 12.0
## 三档键盘(占视口高的比例) —— 依据各自写清楚, 不凭印象:
##   0.415 = iPhone 14/15 横屏 ASCII 键盘 162pt / 屏高 390pt
##   0.520 = 同上加中文候选条(产品注释里写的「≈52%」那档)
##   0.580 = 窄屏 + 候选条的最坏一档(iPhone 13 mini 横屏 360pt 高, 键盘+候选条 ≈203pt)
const KB_TIERS := [0.415, 0.520, 0.580]
## 三种视口: 设计基准 / iPhone 横屏 / iPad 4:3。
const VP_MATRIX := [Vector2(1280.0, 720.0), Vector2(1560.0, 720.0), Vector2(1280.0, 960.0)]


## 一个**回成功**的注入传输 —— ⑥d 要走真的「发码成功」那条路,
## 而 `_spy` 回的是连不上(永远到不了 EM_SENT)。
func _spy_ok(method, url, _headers, body, cb) -> void:
	_reqs.append({"method": str(method), "url": str(url), "body": str(body)})
	cb.call({"ok": true, "code": 200, "body": "{}"})


## 屏幕上那一步的靶子: 短边 / 相邻间隙 / 谁吃到这一点。
##
## ★为什么要按步量: 分两步之后另一步的控件**还在树上只是隐的**,
##   一起数会把屏幕上没有的东西也算进来(而玩家瞄不到隐掉的那些)。
## ★间隙只在**真的上下叠着**(水平投影有重叠)时才算 —— 并排的两个钮
##   竖向间隙是 0, 但那不是「挤在一起」(手指左右还分得开)。
func _t_step_targets(inst, step: int) -> void:
	var hot := _hot(inst._email_layer)
	print("     ── ⑥a 第 %d 步 ──" % step)
	_ok("⑥a ★分母: 第 %d 步屏幕上真的有 ≥3 个可点元素(没有 ⇒ 下面整段是空检查)" % step,
		hot.size() >= 3, "实得 %d 个" % hot.size())
	hot.sort_custom(func(a, b): return (a as Control).get_global_rect().position.y < (b as Control).get_global_rect().position.y)
	var eaten: Array = []
	var small: Array = []
	var tight: Array = []
	var prev: Control = null
	for c in hot:
		var cc := c as Control
		var r: Rect2 = cc.get_global_rect()
		var mn: float = minf(r.size.x, r.size.y)
		var h := _hover_at(r.get_center())
		var mine: bool = h == cc or (h != null and cc.is_ancestor_of(h))
		var gap: float = INF
		if prev != null:
			var pr: Rect2 = prev.get_global_rect()
			## 水平投影有重叠 = 真的上下叠着
			if r.position.x < pr.position.x + pr.size.x and pr.position.x < r.position.x + r.size.x:
				gap = r.position.y - (pr.position.y + pr.size.y)
		print("        %-22s %s  短边 %.0fpx=%.1fpt  间隙 %s  吃到这一点: %s"
			% [_txt_of(cc).substr(0, 20),
				"%.0f,%.0f %.0fx%.0f" % [r.position.x, r.position.y, r.size.x, r.size.y],
				mn, mn / PX_PER_PT,
				("—" if is_inf(gap) else "%+.0fpx" % gap),
				("自己" if mine else str(h))])
		if not mine:
			eaten.append("%s ← %s" % [_txt_of(cc), str(h)])
		if mn < TOUCH_MIN_PX:
			small.append("%s %.0fx%.0f(短边 %.1fpt)" % [_txt_of(cc), r.size.x, r.size.y, mn / PX_PER_PT])
		if not is_inf(gap) and gap < GAP_MIN_PX:
			tight.append("%s 与上一个只隔 %.0fpx" % [_txt_of(cc), gap])
		prev = cc
	## ★这一条**不是恒真**: 反向验证把 `dim.mouse_filter` 换成一块盖在按钮上的
	##   `MOUSE_FILTER_STOP` 兄弟节点, 这里立刻报"← 那个节点"。
	_ok("⑥a ★★★第 %d 步每个可点元素**自己**吃到落在它身上那一点(被别人吃掉 = 点了没反应)" % step,
		eaten.is_empty(), str(eaten))
	## ★★★**长条不再豁免**。上一版那条豁免(`maxf(w,h) >= 200` 就放行)让
	##   5 个宽 440 的靶子带着 22.8~25.0pt 的高度一路绿 —— 而手指瞄的是**竖向**,
	##   长条只解决了水平那一维。这一屏改成两步之后竖向装得下, 豁免就没理由了。
	_ok("⑥a ★★★第 %d 步每个可点元素短边 ≥44pt(81px) —— 长条**不再豁免**" % step,
		small.is_empty(), str(small))
	_ok("⑥a ★★★第 %d 步相邻靶子竖直间隙 ≥%dpx(挤太近 = 瞄 A 点到 B)" % [step, int(GAP_MIN_PX)],
		tight.is_empty(), str(tight))


func _t_touch() -> void:
	print("── ⑥ 墙上点得到吗(触摸层) ──")
	var vp0 := get_tree().root.size
	get_tree().root.size = Vector2i(VP_PHONE)
	await _wf(2)
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._reset_auth_for_test()
	GameState.account_email = ""
	GameState.account_id = "uid-touch"
	var inst = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	inst.acct_override = 1          ## ★必须在 add_child **之前** —— `_ready` 那一刻就决定建不建墙
	add_child(inst)
	await _wf(8)
	_ok("⑥ ★分母: 墙真的立起来了(没立起来 ⇒ 下面整节是空检查)",
		inst._email_layer != null and is_instance_valid(inst._email_layer))
	if inst._email_layer == null:
		inst.queue_free()
		get_tree().root.size = vp0
		await _wf(2)
		return

	# ── ⑥a 热区 + 谁吃到这一点 ────────────────
	## ★分母: 两步加起来的节点数 —— 墙上本来就该有昵称/邮箱/发码/码/确认 五个起,
	##   少了就是流程被我拆没了, 而不是"排得更开"。
	var all_nodes := 0
	for ch in (inst._email_box as Node).get_children():
		if ch is LineEdit or ch is BaseButton:
			all_nodes += 1
	_ok("⑥a ★分母: 两步加起来仍有 ≥5 个可点节点(昵称/邮箱/发码/码/确认…)",
		all_nodes >= 5, "实得 %d 个" % all_nodes)
	for step in [1, 2]:
		inst._email_set_step(step)
		await _wf(3)
		await _t_step_targets(inst, step)
	inst._email_set_step(1)
	await _wf(3)
	await _t_no_typing(inst)
	await _t_wall_art(inst)
	_t_gap_ceiling(inst)

	## ⑥a-2 居中: 原来位置写死成 1280x720 设计坐标 ⇒ 1560 宽的屏上整块偏左 140px。
	var box: Control = null
	for ch in (inst._email_layer as Node).get_children():
		if ch is Panel:
			box = ch as Control
	_ok("⑥a ★分母: 找到了对话框那块框", box != null)
	if box != null:
		var cx: float = box.get_global_rect().get_center().x
		_ok("⑥a ★★墙在**真实视口**里居中(写死设计坐标 ⇒ iPhone 横屏偏左 140px)",
			absf(cx - VP_PHONE.x / 2.0) <= 1.0,
			"框中心 x=%.0f  视口中心 x=%.0f" % [cx, VP_PHONE.x / 2.0])

	# ── ⑥b 按下去真的有事发生 ──────────────────
	inst._email_edit.text = "touch@example.com"
	SB.reset_email_flow()
	await _wf(20)
	_ok("⑥b ★分母①: 不按的话状态**不会自己变**(变了 ⇒ 下面那条恒真)",
		SB.email_state() == SB.EM_IDLE, SB.email_state())
	var dimr: Rect2 = (inst._email_layer as Control).get_global_rect()
	_tap(Vector2(dimr.position.x + 20.0, dimr.position.y + 20.0))
	await _wf(6)
	_ok("⑥b ★分母②: 点**空白遮罩**不该有事发生(有 ⇒ 我注入的事件本身在乱改状态)",
		SB.email_state() == SB.EM_IDLE, SB.email_state())
	_ok("⑥b ★分母③: 「发验证码」这一刻是**可用**的(disabled 的钮按了本来就不变)",
		not inst._email_send_btn.disabled)
	_tap(inst._email_send_btn.get_global_rect().get_center())
	await _wf(6)
	_ok("⑥b ★★★按「发验证码」**产品状态真的动了**(idle → %s)" % SB.email_state(),
		SB.email_state() != SB.EM_IDLE, "msg=「%s」" % SB.email_msg())

	## 「确认」那一钮: 状态机会在同一帧里 VERIFYING→ERR(注入的传输是同步回包的)
	## ⇒ 判据换成**真实发出去的那个请求**, 它是记录下来的, 不会被时间清掉。
	SB._reset_auth_for_test()
	SB._token = "tok-touch"
	SB._transport_for_test = _spy
	SB.reset_email_flow()
	SB.send_code_async("touch@example.com", SB.FLOW_BIND)
	await _wf(10)
	inst._email_poll()
	## ★★分两步之后「确认」在**第二步**。这里用产品自己的入口把它推过去
	##   (注入的传输回的是"连不上" ⇒ 到不了 EM_SENT, 不会自己翻页)。
	inst._email_set_step(2)
	await _wf(3)
	GameState.nickname = "阿龟"
	inst._nick_edit.text = "阿龟"
	inst._code_edit.text = "12345678"
	_ok("⑥b ★分母④: 「确认」这一刻**看得见、可用**, 且 `_email_pending` 有值(否则验码会静默早退)",
		inst._email_ok_btn.is_visible_in_tree() and not inst._email_ok_btn.disabled
			and SB._email_pending != "",
		"可见=%s disabled=%s pending=「%s」" % [str(inst._email_ok_btn.is_visible_in_tree()),
			str(inst._email_ok_btn.disabled), SB._email_pending])
	_reqs.clear()
	await _wf(20)
	_ok("⑥b ★分母⑤: 不按的话**一个请求都不会发**(否则下面那条恒真)",
		_reqs.size() == 0, "实得 %d 条" % _reqs.size())
	_tap(inst._email_ok_btn.get_global_rect().get_center())
	await _wf(6)
	var urls: Array = []
	for r in _reqs:
		urls.append(str(r.get("url", "")).replace(DEAD_URL, ""))
	_ok("⑥b ★★★按「确认」**真的发出了验码请求**(不是「函数存在」, 是线上真的动了)",
		urls.has("/auth/v1/verify"), str(urls))
	SB._transport_for_test = Callable()

	# ── ⑥c 虚拟键盘: 三档键盘 × 三种视口 × 两步 = 18 格 ──────
	## ★上一版只量了**一格**(1560x720 × 41.5% × 一步)。判据一个字没放宽,
	##   只是从 1 格摊到 18 格 —— 因为重排之后“装不装得下”是按键盘档位分胜负的,
	##   只量最宽松那一档等于没量。
	print("     ── ⑥c 虚拟键盘: 三档 × 三种视口 × 两步 ──")
	var cells := 0
	var denom := 0
	var bad: Array = []
	for v in VP_MATRIX:
		get_tree().root.size = Vector2i(v)
		await _wf(3)
		for step in [1, 2]:
			inst._email_set_step(step)
			await _wf(3)
			var hot2 := _hot(inst._email_layer)
			for frac in KB_TIERS:
				var kb: float = v.y * float(frac)
				var kb_top: float = v.y - kb
				## ★分母: **不让位**的话这一格真的有东西被埋。
				##   没有 ⇒ 那一格是空检查(memory `fb-gate-subject-never-constructed`)。
				SET.vkb_override_vp = -1.0
				await _wf(2)
				if not _under(hot2, kb_top).is_empty():
					denom += 1
				SET.vkb_override_vp = kb
				await _wf(2)
				cells += 1
				var bu := _under(hot2, kb_top)
				var ab: Array = []
				for c in hot2:
					if (c as Control).get_global_rect().position.y < 0.0:
						ab.append(_txt_of(c as Control))
				print("        %dx%d 第%d步 kb %.1f%%(顶边 %.0f) ⇒ 埋 %d / 顶出 %d  框 y=%.0f"
					% [int(v.x), int(v.y), step, float(frac) * 100.0, kb_top,
						bu.size(), ab.size(), (box.position.y if box != null else -1.0)])
				if not bu.is_empty() or not ab.is_empty():
					bad.append("%dx%d/步%d/kb%.0f%%: 埋%s 顶%s"
						% [int(v.x), int(v.y), step, float(frac) * 100.0, str(bu), str(ab)])
	_ok("⑥c ★分母①: 18 个格子真的都量了(三档 × 三视口 × 两步)",
		cells == 18, "实测 %d 格" % cells)
	_ok("⑥c ★分母②: **不让位**的话每一格都真有元素被埋(否则那一格是空检查)",
		denom == cells, "%d/%d 格有被埋的" % [denom, cells])
	_ok("⑥c ★★★让位后 **0 个可点元素被埋、 0 个被顶出上沿**(iOS 上键盘是盖上来的, 视口不缩)",
		bad.is_empty(), str(bad))
	SET.vkb_override_vp = -1.0
	get_tree().root.size = Vector2i(VP_PHONE)
	inst._email_set_step(1)
	await _wf(3)
	var y_home: float = box.position.y if box != null else 0.0
	SET.vkb_override_vp = VP_PHONE.y * 0.415
	await _wf(3)
	_ok("⑥c ★分母: 键盘弹出时框**真的挖了**(没挖 ⇒ 下面那条回位是恒真)",
		box != null and absf(box.position.y - y_home) > 1.0,
		"y=%.0f  原位 %.0f" % [(box.position.y if box != null else -1.0), y_home])
	SET.vkb_override_vp = -1.0
	await _wf(3)
	_ok("⑥c ★键盘收起后框**回到原位**(不回 = 键盘按一次墙就永久歪了)",
		box != null and absf(box.position.y - y_home) <= 1.0,
		"现在 y=%.0f  原位 y=%.0f" % [(box.position.y if box != null else -1.0), y_home])
	## 纯函数: 物理窗口像素 → 视口单位。★无头读不到真键盘, 这一条量的是**折算本身**。
	##   iPhone 14 横屏 3x: 键盘 162pt=486px, 窗口 390pt=1170px ⇒ 720 * 486/1170 = 299.1
	var conv: float = SET._vkb_to_vp(486.0, VP_PHONE, Vector2(1560.0, 1170.0))
	_ok("⑥c ★★折算对(物理 486px / 窗口 1170px × 视口 720 = 299.1 —— 不折算会挖错 1.6 倍)",
		absf(conv - 299.08) <= 0.5, "%.2f" % conv)
	_ok("⑥c ★无头 `window_get_size()` 是 (0,0) ⇒ 折算必须返回 0, 不许除零",
		SET._vkb_to_vp(486.0, VP_PHONE, Vector2.ZERO) == 0.0)

	# ── ⑥d 两步流程本身: 自动翻页 + 退路 + 退路不是出口 ──────
	## ★为什么要单列一节: "分两步"引入了三个新的死法,
	##   而上面 ⑥a~⑥c 一条都碰不到它们:
	##     ① 发完码不翻页 ⇒ 玩家永远看不到验证码框
	##     ② 第二步没退路 ⇒ 邮箱打错一个字母就是**死局**(墙关不掉)
	##     ③ 退回第一步却被状态机又弹回去(忘了 reset) ⇒ 又一个「点了没反应」
	print("     ── ⑥d 两步流程本身 ──")
	SB._reset_auth_for_test()
	SB._token = "tok-step"
	SB._transport_for_test = _spy_ok
	SB.reset_email_flow()
	inst._email_set_step(1)
	await _wf(3)
	inst._email_edit.text = "step@example.com"
	_ok("⑥d ★分母: 现在停在第一步, 而「确认」钮**不在屏幕上**(在 ⇒ 下面那条恒真)",
		inst._email_step == 1 and not inst._email_ok_btn.is_visible_in_tree(),
		"step=%d 确认可见=%s" % [inst._email_step, str(inst._email_ok_btn.is_visible_in_tree())])
	_tap(inst._email_send_btn.get_global_rect().get_center())
	await _wf(10)
	inst._email_poll()
	await _wf(3)
	_ok("⑥d ★分母: 发码真的成功了(state=%s)" % SB.email_state(),
		SB.email_state() == SB.EM_SENT, "msg=「%s」" % SB.email_msg())
	_ok("⑥d ★★★发码成功 ⇒ **自己翻到第二步**(不让玩家去找「下一步」在哪)",
		inst._email_step == 2 and inst._email_ok_btn.is_visible_in_tree()
			and inst._code_edit.is_visible_in_tree(),
		"step=%d 确认可见=%s 码框可见=%s" % [inst._email_step,
			str(inst._email_ok_btn.is_visible_in_tree()), str(inst._code_edit.is_visible_in_tree())])
	_ok("⑥d ★★第二步屏幕上写着**码发去了哪个邮箱** —— 状态行会被「码不对」覆盖, 地址得有个稳的地方",
		str(inst._email_hint.text).find("step@example.com") >= 0, str(inst._email_hint.text))
	_ok("⑥d ★分母: 第二步有「回上一步改邮箱」且看得见",
		inst._email_back_btn != null and inst._email_back_btn.is_visible_in_tree())
	_tap(inst._email_back_btn.get_global_rect().get_center())
	await _wf(6)
	_ok("⑥d ★★★点「回上一步改邮箱」**真的回到第一步**(邮箱打错一个字母 = 这堤墙的死局出口)",
		inst._email_step == 1 and inst._email_edit.is_visible_in_tree(),
		"step=%d" % inst._email_step)
	_ok("⑥d ★★★回上一步**没把墙关掉**(关得掉的墙不是墙)",
		inst._email_layer != null and is_instance_valid(inst._email_layer)
			and (inst._email_layer as Control).is_visible_in_tree())
	inst._email_poll()
	await _wf(6)
	inst._email_poll()
	await _wf(3)
	_ok("⑥d ★★回到第一步之后**不会被自己又弹回去**(忘了 reset 流程就会: 看着像「点了没反应」)",
		inst._email_step == 1, "step=%d state=%s" % [inst._email_step, SB.email_state()])
	SB._transport_for_test = Callable()
	SB.reset_email_flow()

	inst.queue_free()
	get_tree().root.size = vp0
	await _wf(2)


# ──────────────────────────────────────────────────────────
# ⑥e A · ★★★玩家**一个字不打**能不能过去 (2026-09-29)
#
#    上面 ⑦A 量的是**池子**(纯函数); 这一节量的是**屏幕上那个框**:
#    池子再好, 控件没接上就是空框(memory `fb-write-without-reader-and-fake-gates`)。
# ──────────────────────────────────────────────────────────
func _t_no_typing(inst) -> void:
	print("     ── ⑥e 一个字不打能不能过 ──")
	_ok("⑥e ★分母: 昵称框在屏幕上", inst._nick_edit != null
		and inst._nick_edit.is_visible_in_tree())
	var pre := str(inst._nick_edit.text)
	print("     预填的名字: 「%s」" % pre)
	## ★★真正的判据: 不碰键盘的情况下, 这个名字**已经能过规则**。
	##   量的是产品自己那道门(`nickname_error` 就是「确认」按下去跑的那一条)。
	_ok("⑥e ★★★**预填名**能直接过(玩家不碰键盘也能按确认)",
		P2C.nickname_error(pre) == "", "「%s」 ⇒ %s" % [pre, P2C.nickname_error(pre)])
	_ok("⑥e ★预填的名字像这个游戏的(不是 `Player_561962`)",
		_looks_like_this_game(pre), pre)
	## 「换一个」
	var re: Button = inst._email_side.get(inst._nick_edit)
	_ok("⑥e ★分母: `NICK_REROLL` 那颗钮在第一步看得见, 且短边 ≥ 44pt",
		re != null and re.is_visible_in_tree()
			and minf(re.get_global_rect().size.x, re.get_global_rect().size.y) >= TOUCH_MIN_PX,
		str(re.get_global_rect()) if re != null else "<不在>")
	## ★字也要对得上 —— 钮在那里但写着另一句话, 玩家也找不到它。
	_ok("⑥e ★那颗钮上写的字 == `NICK_REROLL`(产品那一处, 不是测试里拼的)",
		re != null and str(re.text) == str(P2C.NICK_REROLL),
		"「%s」 vs 「%s」" % [str(re.text) if re != null else "", str(P2C.NICK_REROLL)])
	if re == null:
		return
	## ★分母: 不点的话名字**不会自己变**(会变 ⇒ 下面那条恒真)。
	await _wf(20)
	_ok("⑥e ★分母: 不点「换一个」的话名字不会自己变",
		str(inst._nick_edit.text) == pre, "%s → %s" % [pre, str(inst._nick_edit.text)])
	_tap(re.get_global_rect().get_center())
	await _wf(6)
	var post := str(inst._nick_edit.text)
	_ok("⑥e ★★★按「换一个」名字**真的换了**(换完还是同一个 = 点了没反应)",
		post != pre and post != "", "「%s」 → 「%s」" % [pre, post])
	_ok("⑥e ★换完那个也直接能过(换出一个不合法的 = 把人坑进报错里)",
		P2C.nickname_error(post) == "", "「%s」 ⇒ %s" % [post, P2C.nickname_error(post)])
	## ★★第二步必须藏掉它 —— 那一步没名字可换, 而且它会被 `_email_ctl_band`
	##   算进键盘让位的 band 里。
	inst._email_set_step(2)
	await _wf(3)
	_ok("⑥e ★★「换一个」在第二步**藏掉了**(那一步没名字可换)",
		not re.is_visible_in_tree())
	inst._email_set_step(1)
	await _wf(3)
	## ★★对照组: **已经有名字的人不允许被覆盖**。
	##   老玩家升级过来会被墙挡一次, 覆了就是把他的名字默默改掉。
	var keep := "龟主阿龟"
	GameState.nickname = keep
	var st7 = SET.new()
	add_child(st7)
	await _wf(2)
	st7._open_email_dialog(SB.FLOW_BIND, false)
	await _wf(3)
	_ok("⑥e ★★已经有名字的人: 框里还是他自己的名字(不被随机名覆盖)",
		st7._nick_edit != null and str(st7._nick_edit.text) == keep,
		str(st7._nick_edit.text) if st7._nick_edit != null else "<没框>")
	st7.queue_free()
	GameState.nickname = ""
	await _wf(2)


# ──────────────────────────────────────────────────────────
# ⑥f C · ★★★这一屏看不看得见这个游戏 (2026-09-29)
#
#    探针 `tests/_probe_wall_look.gd` 实测过: `_maybe_login_wall` 把 self 下的
#    Control 整批藏掉(连 `_bg()` 建的底色/平铺砖/渐变) ⇒ 这一屏一只龟都没有。
#    ★判据量“屏幕上有没有一张盖满的真图”, 不量“源码里有没有 load 一张图”。
#    ★★配对照组: **自己点开的对话框没有这层** —— 否则证不了是墙才有。
# ──────────────────────────────────────────────────────────
## 遮罩层里那些**贴了真贴图**的 TextureRect。
func _art_of(layer) -> Array:
	var out: Array = []
	if layer == null or not is_instance_valid(layer):
		return out
	for ch in (layer as Node).get_children():
		if ch is TextureRect and (ch as TextureRect).texture != null:
			out.append(ch)
	return out


func _t_wall_art(inst) -> void:
	print("     ── ⑥f 这一屏看得见这个游戏吗 ──")
	var vp: Vector2 = Vector2(get_tree().root.size)
	var art: Array = _art_of(inst._email_layer)
	var covers: Array = []
	for a in art:
		var r: Rect2 = (a as Control).get_global_rect()
		print("        %-12s %s  tex %s" % [(a as Node).get_class(), str(r),
			str((a as TextureRect).texture.get_size())])
		if r.size.x >= vp.x - 1.0 and r.size.y >= vp.y - 1.0:
			covers.append(a)
	_ok("⑥f ★★★墙背后铺了**一张盖满屏幕的游戏美术**(原来是 0.65 纯黑 + 菜单平铺砖)",
		covers.size() >= 1, "遮罩层里 %d 张图, 其中 %d 张盖满 %s" % [art.size(), covers.size(), str(vp)])
	## 素材得是仓库里已经有的(本轮不新生成)
	for p in [WALL_ART.WALL_ART_TEX, WALL_ART.WALL_LOGO_TEX]:
		_ok("⑥f ★`WALL_ART_TEX` 指的是仓库里**已经有的**素材: %s" % str(p).get_file(),
			ResourceLoader.exists(str(p)))
	## ★★★光“存在”不够 —— 得证明**画在屏幕上那张就是它**。
	var on_screen: Array = []
	for a in covers:
		on_screen.append(str((a as TextureRect).texture.resource_path))
	_ok("⑥f ★★★盖满屏幕那张图的 resource_path == `WALL_ART_TEX`(不是别处随便一张)",
		on_screen.has(str(WALL_ART.WALL_ART_TEX)), str(on_screen))
	## ★★这一条守的是「**不再是所有菜单屏共用的那张平铺花砖**」:
	##   `PersistentBg`(autoload·layer -100) 与 `SettingsScene._bg()` 画的都是
	##   `menu-bg-tile.png`。墙上这层美术不许又是它 —— 换了张图还是同一块砖,
	##   玩家看到的一点没变。
	_ok("⑥f ★★★铺的不是 `PersistentBg` / `_bg()` 那张共用平铺花砖(又是它 = 白换)",
		not on_screen.has("res://assets/sprites/menu/menu-bg-tile.png"), str(on_screen))
	## ★美术不许抢点击 —— 抢了就是「点了没反应」。拿引擎自己算,
	##   不看 `mouse_filter`(看标记 = 插一行数一行)。
	var gut: Vector2 = Vector2(16.0, vp.y * 0.5)
	var h := _hover_at(gut)
	_ok("⑥f ★★美术**不吃点击**(点在图上时命中的不是 TextureRect)",
		not (h is TextureRect), "%s @ %s" % [str(h), str(gut)])
	## 标: 在屏幕上, 且**不跋框**
	var logo = inst._email_logo
	_ok("⑥f ★分母: 斗龟场的标在屏幕上(看不见 ⇒ 下一条是空检查)",
		logo != null and is_instance_valid(logo) and (logo as Control).is_visible_in_tree(),
		str((logo as Control).get_global_rect()) if logo != null else "<不在>")
	if logo != null and is_instance_valid(logo) and (logo as Control).is_visible_in_tree():
		var lr: Rect2 = (logo as Control).get_global_rect()
		var br: Rect2 = (inst._email_box as Control).get_global_rect()
		_ok("⑥f ★★标**不压到框上**(压上去就是把要填的东西遮住)",
			not lr.intersects(br), "标 %s vs 框 %s" % [str(lr), str(br)])
		_ok("⑥f ★标在屏幕里(没戳出左/上沿)",
			lr.position.x >= -1.0 and lr.position.y >= -1.0, str(lr))
	## ★★对照组: 玩家自己在设置里点开的那个对话框**没有**这层 ——
	##   否则上面那条只是“对话框本来就带张图”, 证不了是墙才铺的。
	GameState.account_email = "someone@x.co"
	var st8 = SET.new()
	add_child(st8)
	await _wf(2)
	st8._open_email_dialog(SB.FLOW_BIND)
	await _wf(3)
	_ok("⑥f ★★对照组: **自己点开的**对话框没有这层美术(背后本来就是设置页)",
		_art_of(st8._email_layer).is_empty() and st8._email_logo == null,
		"实测 %d 张图" % _art_of(st8._email_layer).size())
	st8.queue_free()
	GameState.account_email = ""
	await _wf(2)


# ──────────────────────────────────────────────────────────
# ⑥g D · ★★★间隙**抬到顶了吗** —— 两头卡住 (2026-09-29)
#
#    上面 ⑥a 只卡住了下限(gap ≥ GAP_MIN_PX)。光有下限不够:
#      · 往下掉回 12px —— 下限卡住了 ✅
#      · 往上越过天花板 —— ⑥c 那 18 格卡住了 ✅
#      · **停在中间白白浪费净空** —— 两条都管不到❗
#    ⇒ 这一条量「还剩多少净空没用上」。天花板不写死:
#    拿 **产品自己的 band** 与 **本文件自己的 KB_TIERS / _KB_GAP** 算,
#    两边都不是我在这一行手抄的数字。
# ──────────────────────────────────────────────────────────
func _t_gap_ceiling(inst) -> void:
	print("     ── ⑥g 间隙抬到顶了吗 ──")
	var band: Vector2 = inst._email_ctl_band()
	var bh: float = band.y - band.x
	## 最坏那一档键盘留给可点元素的净空。720 高那两个视口是最穿的一档。
	var worst: float = 0.0
	for f in KB_TIERS:
		worst = maxf(worst, float(f))
	var room: float = VP_PHONE.y * (1.0 - worst) - 2.0 * float(SET._KB_GAP)
	print("        band 高 %.1f px  ·  最坏一档(kb %.1f%%)净空 %.1f px  ·  剩 %.1f px"
		% [bh, worst * 100.0, room, room - bh])
	print("        算式: %d 行 × %.0f(44pt) + %d × gap %.0f = %.0f  ≤  %.0f×(1-%.3f) - 2×%.0f = %.1f"
		% [SET._W_ROWS, SET._W_ROW_H, SET._W_ROWS - 1, SET._W_ROW_GAP, bh,
			VP_PHONE.y, worst, SET._KB_GAP, room])
	_ok("⑥g ★分母: band 量到了(0 ⇒ 下面两条是空检查)", bh > 100.0, "%.1f px" % bh)
	_ok("⑥g ★★GAP_RAISED: `_W_ROW_GAP` 真的从旧值 %.0f 抬上去了(现在 %.0f)"
			% [GAP_RAISED_FROM, SET._W_ROW_GAP],
		float(SET._W_ROW_GAP) > GAP_RAISED_FROM, "%.0f px" % SET._W_ROW_GAP)
	_ok("⑥g ★★没越过天花板(越了 ⇒ 最坏一档键盘底下埋东西, ⑥c 那 18 格会同时红)",
		bh <= room + 0.01, "band %.1f > 净空 %.1f" % [bh, room])
	## ★★★上限: 剩下的净空不得超过 **一个行隙**。
	##   剩得比一个行隙还多 ⇒ 那一步本来可以再抬, 却没抬 ⇒ 白白浪费。
	##   (旧值 gap=12 时 band=267, 剩 19.4px > 行隙 ⇒ 这一条当场红。
	##    新值 gap=21 时 band=285, 剩 1.4px ⇒ 绿。)
	_ok("⑥g ★★★GAP_RAISED **抬到顶了**: 剩下的净空 %.1f px < 一个行隙 %.0f px(剩得多 ⇒ 本来还能再抬)"
			% [room - bh, SET._W_ROW_GAP],
		room - bh < float(SET._W_ROW_GAP),
		"剩 %.1f px, 一个行隙 %.0f px —— 抬不动了才叫到顶" % [room - bh, SET._W_ROW_GAP])


## `hot` 里有哪些控件的下沿越过了 `line`(= 键盘上沿)。
func _under(hot: Array, line: float) -> Array:
	var out: Array = []
	for c in hot:
		var r: Rect2 = (c as Control).get_global_rect()
		if r.position.y + r.size.y > line:
			out.append("%s@%.0f" % [_txt_of(c as Control), r.position.y])
	return out


## 递归收集某棵子树里的 Button。
func _buttons(root) -> Array:
	var out: Array = []
	if root == null or not is_instance_valid(root):
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Button:
			out.append(n)
		for c in (n as Node).get_children():
			stack.append(c)
	return out
