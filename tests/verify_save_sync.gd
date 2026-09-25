extends Node
## verify_save_sync.gd — D-8：存档同步（2026-09-21 用户「需要存档同步的」）
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## D-3b 核实出服务端五张表没有一张存玩家存档 ⇒ 绑邮箱只能找回账号，找不回龟和装备。
## D-8 让绑了邮箱的号把存档同步到云端（`saves` 表 + 服务端函数 `push_save`）。
##
## ★★最要守的三件事：
##   ② **身份永远不从云存档里读** —— 改一份云存档就能让设备「变成」另一个号，那是越权。
##   ⑤ **「没拿到回包」绝不能当成「云端没有存档」** —— 那会用本机的覆盖云端。
##   ⑦ **匿名号一次都不推** —— 隐私政策承诺了只有绑定者才上传。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★③ 往返：拉回来的存档应用后，再算一次 payload 与原来**逐字段相等** ——
##   这守的是「本机文件与云存档共用同一份字段表」。各写一份的话，
##   下一个加字段的人只会加一边，换设备取回时那个字段就静默丢了。
## ★⑦⑨ 走真入口 + `_transport_for_test` 截真实请求，量「发没发 / 发给谁 / 带的什么」，
##   不数我插的计数器。
## ★⑧ 备份与 `save()` 标脏都受存档闸（test_mode）保护 ⇒ 在门禁里默认零痕迹，
##   判据会变恒真式（memory `fb-debug-stage-writes-real-save` 第②条）。
##   ⇒ 临时开闸让写盘真发生，并把 savegame.json 与备份文件逐字节还原 / 删掉。
## ⚠ 服务端那一半（比较并交换、RLS、只能走函数写）要真 Supabase 才验得到，
##   见 `tests/_probe_d8.gd`；这里喂的是 schema.sql 里写死的回包形状。

const SB := preload("res://scripts/net/supabase.gd")
const DEAD_URL := "http://127.0.0.1:9"

var _ok := 0
var _fail := 0
var _tree: SceneTree = null
var _bak := {}
const KEYS := ["account_id", "account_email", "auth_refresh", "cloud_rev", "bgm_volume",
	"sfx_volume", "fullscreen", "perf_lite", "install_uid", "meta_deepsea_coins", "coins",
	"hearts", "season_wins", "pet_levels", "inventory", "season_leaders", "trainer_skill",
	"match_history", "season_total_battles", "season_id", "week_anchor_ts", "season_start_ts"]

var _reqs: Array = []
var _next := {}


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])


func _spy(method, url, headers, body, cb) -> void:
	_reqs.append({"method": str(method), "url": str(url), "headers": headers, "body": str(body)})
	cb.call(_next)


func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	GameState.test_mode = true
	for k in KEYS:
		var v = GameState.get(k)
		_bak[k] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	## ★存档文件要在【第一个可能写盘的用例之前】备份(⑧⑩ 会临时开闸)
	_savefile_bak = FileAccess.get_file_as_string(GameState.SAVE_PATH) \
		if FileAccess.file_exists(GameState.SAVE_PATH) else "<none>"
	print("=== D-8 存档同步 ===")
	_t_payload()
	_t_no_identity_from_cloud()
	_t_roundtrip()
	_t_push_kind()
	_t_pull_kind()
	_t_allowed()
	await _t_push_real_entry()
	await _t_pull_apply()
	await _t_recover_triggers_pull()
	await _t_save_marks_dirty()
	await _t_resolve_local()
	SB._transport_for_test = Callable()
	OS.set_environment("TURTLE_SUPABASE", " ")
	SB._reset_save_sync_for_test()
	SB._reset_auth_for_test()
	for k in KEYS:
		GameState.set(k, _bak[k])
	_restore_savefile()
	var now_file = FileAccess.get_file_as_string(GameState.SAVE_PATH) \
		if FileAccess.file_exists(GameState.SAVE_PATH) else "<none>"
	_chk("★收尾: savegame.json 逐字节还原(⑧⑩ 开过闸)", str(now_file) == str(_savefile_bak))
	_chk("★收尾: 没留下备份文件", _backups().is_empty(), str(_backups()))
	print("")
	print("  (共 %d 条断言)" % (_ok + _fail))
	print("ALL PASS — D-8 存档同步" if _fail == 0 else "FAIL x%d" % _fail)
	if _tree != null:
		_tree.quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 上云的是哪些
# ─────────────────────────────────────────────────────────────
func _t_payload() -> void:
	print("── ① 上云的那一份 ──")
	var full: Dictionary = GameState._save_dict()
	var p: Dictionary = GameState.cloud_payload()
	_chk("① ★分母: 完整存档有几十个字段(不是空字典)", full.size() >= 40, str(full.size()))
	var leaked: Array = []
	for k in GameState.DEVICE_LOCAL_KEYS:
		if p.has(k):
			leaked.append(k)
	_chk("① ★★设备本地键一个都没进云(音量/全屏/画质/安装标识/身份/登录令牌/版本号)",
		leaked.is_empty(), str(leaked))
	_chk("① ★分母: 设备本地键在完整存档里是【有】的(否则上一条是恒真式)",
		full.has("account_id") and full.has("auth_refresh") and full.has("bgm_volume")
		and full.has("cloud_rev"))
	var need := ["meta_deepsea_coins", "pet_levels", "inventory", "season_leaders",
		"hearts", "season_wins", "match_history", "trainer_skill", "persistent_equipped"]
	var miss: Array = []
	for k in need:
		if not p.has(k):
			miss.append(k)
	_chk("① ★★进度类字段都在云存档里(龟等级/装备/深海币/赛季/对局记录/训龟大师)",
		miss.is_empty(), str(miss))
	_chk("① 云存档 = 完整存档 − 设备本地键(一个不多一个不少)",
		p.size() == full.size() - GameState.DEVICE_LOCAL_KEYS.size(),
		"%d = %d − %d" % [p.size(), full.size(), GameState.DEVICE_LOCAL_KEYS.size()])


# ─────────────────────────────────────────────────────────────
# ② ★★身份永远不从云存档里读
# ─────────────────────────────────────────────────────────────
func _t_no_identity_from_cloud() -> void:
	print("── ② 云存档里就算带了身份也不认 ──")
	GameState.account_id = "uid-me"
	GameState.account_email = "me@x.co"
	GameState.auth_refresh = "rt-me"
	GameState.bgm_volume = 0.33
	var poisoned: Dictionary = GameState.cloud_payload()
	poisoned["account_id"] = "uid-ATTACKER"
	poisoned["account_email"] = "evil@x.co"
	poisoned["auth_refresh"] = "rt-evil"
	poisoned["bgm_volume"] = 0.0
	poisoned["meta_deepsea_coins"] = 777
	GameState.apply_cloud_payload(poisoned, 9)
	_chk("② ★分母: 进度字段确实被应用了(深海币变成 777)",
		int(GameState.meta_deepsea_coins) == 777, str(GameState.meta_deepsea_coins))
	_chk("② ★★account_id 没被云存档改掉(改了 = 改一份云存档就能冒充别的号)",
		str(GameState.account_id) == "uid-me", GameState.account_id)
	_chk("② ★★邮箱与登录令牌也没被改", str(GameState.account_email) == "me@x.co"
		and str(GameState.auth_refresh) == "rt-me",
		"%s / %s" % [GameState.account_email, GameState.auth_refresh])
	_chk("② 本机偏好(音量)没被云端那份覆盖", is_equal_approx(float(GameState.bgm_volume), 0.33),
		str(GameState.bgm_volume))
	_chk("② 云存档版本号 = 服务端给的那个", int(GameState.cloud_rev) == 9, str(GameState.cloud_rev))


# ─────────────────────────────────────────────────────────────
# ③ 往返: 应用后再算 payload 与原来逐字段相等
# ─────────────────────────────────────────────────────────────
func _t_roundtrip() -> void:
	print("── ③ 往返(本机文件与云存档共用一份字段表) ──")
	## ★★中间不是只改三个字段, 而是**清档**把几乎所有字段打回默认 ——
	##   只改三个的话, 「_save_dict 加了字段、_apply_save_dict 忘了读」这种漂移
	##   只有碰巧改到那个字段时才抓得到, 而那正是这条判据本来要守的事。
	##   先把一批字段设成非默认值, 让清档之后「真的变了」的字段尽量多。
	GameState.meta_deepsea_coins = 4321
	GameState.coins = 55
	GameState.hearts = 5
	GameState.season_wins = 7
	GameState.season_total_battles = 9
	GameState.trainer_skill = "whip"
	GameState.trainer_appearance = "mage"
	GameState.onboarded = true
	GameState.candy_jar_count = 4
	GameState.axe_exp_total = 33
	GameState.pet_levels = {"basic": 4, "stone": 2}
	GameState.inventory.assign(["p2eq_001", "p2eq_002"])
	## ★★★先让赛季逻辑结算一遍, 再取 p1(2026-09-26 修)。
	##
	## `apply_cloud_payload()` 里带一句 `ensure_season()` —— 云端那份可能是上一周的,
	## 所以应用之后必须让赛季逻辑自己滚。它会跑 `settle_ranked_close()` /
	## `settle_gauntlet_close()` / `sync_titles()`。
	##
	## ⇒ 不先结算就取 p1 的话, 这条往返判据量的是【往返 + 过了一天的结算】两件事:
	##   在**周六**(积分赛周五刚收盘)跑, `meta_deepsea_coins` / `backfill_paid` /
	##   `promoted` / `titles` / `season_level` / `season_xp` 六个字段会被合法地改掉
	##   ⇒ 判据红, 而产品**没有任何问题**。
	##
	## ★这条红是**闯关赛上线(v0.19.429~431, 2026-09-22)之后的第一个周六**才出现的 ——
	##   上个周六(09-19)那套还不存在。⇒ 「门禁在周一到周五是绿的」不等于它对:
	##   判据挂在星期几上, 一周里有两天必红而平时看不见(同族 memory:
	##   尺子跟时钟挂钩 / 门禁跨帧就恒真)。
	##
	## ★修法是**让两边口径一致**, 不是把那六个字段从判据里排除(那是放松):
	##   `settle_*` 都是幂等的(`backfill_paid` 记了已补的数, 第二次补 0),
	##   所以先结算一次之后, 应用回来再结算不会再动它们 ⇒ 判据只剩"序列化往返"。
	GameState.ensure_season()
	var p1: Dictionary = GameState.cloud_payload()
	GameState.reset_save()
	var pm: Dictionary = GameState.cloud_payload()
	var changed: Array = []
	for k in p1.keys():
		if JSON.stringify(p1[k]) != JSON.stringify(pm.get(k)):
			changed.append(k)
	_chk("③ ★分母: 清档之后至少 10 个字段真的变了(往返判据实际覆盖到的字段数)",
		changed.size() >= 10, "%d 个: %s" % [changed.size(), str(changed)])
	GameState.apply_cloud_payload(p1, 3)
	var p2: Dictionary = GameState.cloud_payload()
	var diff: Array = []
	for k in p1.keys():
		if JSON.stringify(p1[k]) != JSON.stringify(p2.get(k)):
			diff.append(k)
	for k in p2.keys():
		if not p1.has(k):
			diff.append("+" + str(k))
	_chk("③ ★★拉回来应用之后, payload 与推上去的逐字段相等", diff.is_empty(), str(diff))
	_chk("③ 哈希也相等(没变就不会再推)", SB.payload_hash(p2) == SB.payload_hash(p1))

	## ★★★上面那条判据成立**靠的是 `ensure_season()` 幂等** —— 直接把那条性质验出来。
	##
	## 为什么要单独验: `ensure_season()` 读的是**真实时钟**, 门禁没法把星期几钉住
	## ⇒ 上面那条在"今天"绿, 不等于它在别的星期几也绿。而它成立的**机制**是
	## 「结算函数第二次跑不会再动任何字段」(`backfill_paid` 记了已补的数、
	## `sync_titles` 第二次返回 0、`promoted` 稳定) —— 这条性质与星期几无关,
	## 每天都能验。⇒ 验机制, 而不是"今天碰巧对"。
	##
	## ★2026-09-26 的由来: 闯关赛上线(v0.19.429~431)后的**第一个周六**, 上面那条当场红 ——
	##   六个字段被周五收盘的结算合法改掉。判据挂在星期几上, 一周里两天必红而平时看不见。
	GameState.ensure_season()
	var p3: Dictionary = GameState.cloud_payload()
	var diff2: Array = []
	for k in p2.keys():
		if JSON.stringify(p2[k]) != JSON.stringify(p3.get(k)):
			diff2.append(k)
	_chk("③ ★★★`ensure_season()` 幂等: 再跑一次, 一个字段都不该变(这是上面两条的前提)",
		diff2.is_empty(), str(diff2))


# ─────────────────────────────────────────────────────────────
# ④ push_save 回包三类
# ─────────────────────────────────────────────────────────────
func _t_push_kind() -> void:
	print("── ④ 推送回包(只有 reason=conflict 才算冲突) ──")
	var ok: Dictionary = SB.push_result(true, 200, '{"ok": true, "rev": 4}')
	_chk("④ 成功 → ok + 新版本号", str(ok["kind"]) == "ok" and int(ok["rev"]) == 4, str(ok))
	var cf: Dictionary = SB.push_result(true, 200, '{"ok": false, "reason": "conflict", "rev": 6}')
	_chk("④ ★冲突 → conflict + 云端当前版本号", str(cf["kind"]) == "conflict" and int(cf["rev"]) == 6,
		str(cf))
	var nets := [
		["没登录(服务端函数自己判的)", true, 200, '{"ok": false, "reason": "not_signed_in", "rev": 0}'],
		["太大", true, 200, '{"ok": false, "reason": "too_large", "rev": 0}'],
		["连不上", false, 0, ""],
		["500", true, 500, '{"message":"x"}'],
		["函数不存在(表还没建时的 404)", true, 404, '{"code":"PGRST202"}'],
		["一坨 HTML", true, 200, "<html></html>"],
	]
	var wrong := 0
	for c in nets:
		var k := str(SB.push_result(bool(c[1]), int(c[2]), str(c[3]))["kind"])
		if k != "net":
			wrong += 1
		_chk("④ %s → 当网络问题(不是冲突)" % str(c[0]), k == "net", k)
	_chk("④ ★★六种非冲突失败一个都没被当成冲突(冲突会逼玩家二选一)", wrong == 0,
		"误判 %d/6" % wrong)


# ─────────────────────────────────────────────────────────────
# ⑤ ★★拉取: 「没拿到」≠「云端没有」
# ─────────────────────────────────────────────────────────────
func _t_pull_kind() -> void:
	print("── ⑤ 拉取回包(没拿到 ≠ 云端没有) ──")
	var f: Dictionary = SB.pull_result(true, 200, '[{"payload": {"hearts": 3}, "save_rev": 5}]')
	_chk("⑤ 有存档 → found + 内容 + 版本号", str(f["kind"]) == "found"
		and int((f["payload"] as Dictionary).get("hearts", -1)) == 3 and int(f["rev"]) == 5, str(f))
	_chk("⑤ 空数组 → empty(确定的答案: 云端没有这个号的存档)",
		str(SB.pull_result(true, 200, "[]")["kind"]) == "empty")
	var nets := [["连不上", false, 0, ""], ["500", true, 500, "x"], ["HTML", true, 200, "<html>"],
		["对象不是数组", true, 200, '{"message":"x"}'], ["行里没有 payload", true, 200, '[{"save_rev":1}]']]
	var as_empty := 0
	for c in nets:
		var k := str(SB.pull_result(bool(c[1]), int(c[2]), str(c[3]))["kind"])
		if k == "empty":
			as_empty += 1
		_chk("⑤ %s → net" % str(c[0]), k == "net", k)
	_chk("⑤ ★★五种「没拿到」一个都没被当成「云端没有」(当成了 = 用本机的覆盖云端)",
		as_empty == 0, "误判 %d/5" % as_empty)


# ─────────────────────────────────────────────────────────────
# ⑥ 谁能同步
# ─────────────────────────────────────────────────────────────
func _t_allowed() -> void:
	print("── ⑥ 谁能同步 ──")
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	_chk("⑥ ★分母: 后端启用、绑了邮箱、有 token ⇒ 能同步", SB.sync_allowed("uid", "a@b.co", "tok"))
	_chk("⑥ ★★匿名号(没邮箱)不同步", not SB.sync_allowed("uid", "", "tok"))
	_chk("⑥ 没 token 不同步(发了也是 401)", not SB.sync_allowed("uid", "a@b.co", ""))
	_chk("⑥ 没账号不同步", not SB.sync_allowed("", "a@b.co", "tok"))
	OS.set_environment("TURTLE_SUPABASE", " ")
	_chk("⑥ 后端没配不同步", not SB.sync_allowed("uid", "a@b.co", "tok"))


func _login(email: String) -> void:
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1","user":{"id":"uid-me","email":"%s"}}' % email)


# ─────────────────────────────────────────────────────────────
# ⑦ ★★走真入口: 推送发给谁、带什么; 匿名一次都不推
# ─────────────────────────────────────────────────────────────
func _t_push_real_entry() -> void:
	print("── ⑦ 走真入口 maybe_push_save() ──")
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._transport_for_test = _spy
	SB._reset_save_sync_for_test()

	# 匿名号
	_login("")
	GameState.account_email = ""
	_reqs.clear()
	SB.note_save_dirty()
	SB.maybe_push_save(true)
	await get_tree().process_frame
	_chk("⑦ ★★匿名号: 存档脏了、强制推, 也一个请求都没发(隐私政策承诺过)", _reqs.is_empty(),
		str(_reqs.size()))

	# 绑定号
	_login("me@x.co")
	GameState.cloud_rev = 2
	GameState.meta_deepsea_coins = 55
	_next = {"ok": true, "code": 200, "body": '{"ok": true, "rev": 3}'}
	_reqs.clear()
	SB.note_save_dirty()
	SB.maybe_push_save()
	await get_tree().process_frame
	_chk("⑦ ★分母: 绑定号脏了 ⇒ 真的发出去了", _reqs.size() == 1, str(_reqs.size()))
	var r: Dictionary = _reqs[0] if _reqs.size() > 0 else {}
	_chk("⑦ ★★打的是服务端函数 push_save(不是直接写表 —— 表上也没给直接写的策略)",
		str(r.get("url", "")).ends_with("/rest/v1/rpc/push_save"), str(r.get("url", "")))
	var j = JSON.parse_string(str(r.get("body", "{}")))
	var body: Dictionary = j if j is Dictionary else {}
	_chk("⑦ ★★带着「我上次对上的版本号」去比较并交换", int(body.get("p_expected_rev", -1)) == 2,
		str(body.get("p_expected_rev", "?")))
	var pl: Dictionary = body.get("p_payload", {}) if body.get("p_payload", null) is Dictionary else {}
	_chk("⑦ ★分母: 请求里真有 payload", int(pl.get("meta_deepsea_coins", -1)) == 55,
		str(pl.get("meta_deepsea_coins", "?")))
	_chk("⑦ ★★请求里的 payload 不含身份与登录令牌",
		not pl.has("account_id") and not pl.has("auth_refresh") and not pl.has("account_email"))
	_chk("⑦ 成功后本机版本号跟上服务端(3)", int(GameState.cloud_rev) == 3, str(GameState.cloud_rev))
	_chk("⑦ 成功记了一次账", SB.saves_pushed() == 1, str(SB.saves_pushed()))

	# 没变就不推
	_reqs.clear()
	SB.note_save_dirty()
	SB.maybe_push_save()
	await get_tree().process_frame
	_chk("⑦ ★内容没变(只是又 save 了一下) ⇒ 不推", _reqs.is_empty(), str(_reqs.size()))

	# 冲突之后停推
	GameState.meta_deepsea_coins = 56
	_next = {"ok": true, "code": 200, "body": '{"ok": false, "reason": "conflict", "rev": 8}'}
	SB.note_save_dirty()
	SB.maybe_push_save()
	await get_tree().process_frame
	_chk("⑦ ★分母: 冲突确实被识别了", SB.save_conflict())
	_reqs.clear()
	GameState.meta_deepsea_coins = 57
	SB.note_save_dirty()
	SB.maybe_push_save(true)
	await get_tree().process_frame
	_chk("⑦ ★★冲突之后【停推】(等玩家二选一, 不许自动覆盖另一台设备的进度)", _reqs.is_empty(),
		str(_reqs.size()))
	_chk("⑦ 冲突不改本机版本号", int(GameState.cloud_rev) == 3, str(GameState.cloud_rev))


# ─────────────────────────────────────────────────────────────
# ⑧ ★★拉回来的落地: 先备份再替换; 没拿到就不动
# ─────────────────────────────────────────────────────────────
func _t_pull_apply() -> void:
	print("── ⑧ 拉回来的落地(先备份再替换·没拿到不动) ──")
	SB._reset_save_sync_for_test()
	_login("me@x.co")

	# net ⇒ 一个字不动
	GameState.meta_deepsea_coins = 111
	GameState.cloud_rev = 3
	var k: String = SB.apply_pull_save(false, 0, "", "t")
	_chk("⑧ ★★没拿到回包 ⇒ 本机存档一个字没动", k == "net" and int(GameState.meta_deepsea_coins) == 111
		and int(GameState.cloud_rev) == 3, "%s / %d / %d" % [k, GameState.meta_deepsea_coins, GameState.cloud_rev])

	# empty ⇒ 版本号归 0, 标脏(把本机的推上去)
	k = SB.apply_pull_save(true, 200, "[]", "t")
	_chk("⑧ 云端没有 ⇒ 版本号归 0、本机进度不动", k == "empty" and int(GameState.cloud_rev) == 0
		and int(GameState.meta_deepsea_coins) == 111)

	# found ⇒ 先备份(开闸让写盘真发生)再替换
	var tm: bool = GameState.test_mode
	GameState.test_mode = false
	var before_files := _backups()
	GameState.meta_deepsea_coins = 222
	var expect_backup := JSON.stringify(GameState._save_dict(), "  ")
	var cloud: Dictionary = GameState.cloud_payload()
	cloud["meta_deepsea_coins"] = 999
	k = SB.apply_pull_save(true, 200, JSON.stringify([{"payload": cloud, "save_rev": 12}]), "recover")
	var new_files: Array = []
	for f in _backups():
		if not before_files.has(f):
			new_files.append(f)
	GameState.test_mode = tm
	_chk("⑧ ★分母: 这次确实判成「云端有存档」", k == "found", k)
	_chk("⑧ ★★替换之前先写了一份备份", new_files.size() == 1, str(new_files))
	var got := ""
	if new_files.size() == 1:
		got = FileAccess.get_file_as_string("user://" + str(new_files[0]))
	_chk("⑧ ★★备份的内容 = 替换前的存档(深海币 222 那一份)", got == expect_backup,
		"%d 字节 vs %d 字节" % [got.length(), expect_backup.length()])
	_chk("⑧ 然后才换成云端的(深海币 999)", int(GameState.meta_deepsea_coins) == 999,
		str(GameState.meta_deepsea_coins))
	_chk("⑧ 版本号跟上云端(12)", int(GameState.cloud_rev) == 12, str(GameState.cloud_rev))
	for f in new_files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + str(f)))
	_restore_savefile()


var _savefile_bak = null
func _backups() -> Array:
	var out: Array = []
	var d := DirAccess.open("user://")
	if d == null:
		return out
	for f in d.get_files():
		if str(f).begins_with("savegame.before-"):
			out.append(str(f))
	return out


func _restore_savefile() -> void:
	## ⑧⑩ 开闸时 save() 会真写 savegame.json ⇒ 收尾写回原样(门禁进程的 APPDATA 是隔离的,
	##   这一步是给「手动单跑忘了隔离」兜底)。
	if _savefile_bak == null:
		return
	if str(_savefile_bak) == "<none>":
		if FileAccess.file_exists(GameState.SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	else:
		var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(str(_savefile_bak))
			f.close()


# ─────────────────────────────────────────────────────────────
# ⑨ 取回(换设备)之后自动拉云存档
# ─────────────────────────────────────────────────────────────
func _t_recover_triggers_pull() -> void:
	print("── ⑨ 用邮箱取回 ⇒ 拉那个号的云存档 ──")
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._transport_for_test = _spy
	SB._reset_save_sync_for_test()
	SB._reset_auth_for_test()
	GameState.account_id = "uid-local"
	GameState.account_email = ""
	GameState.cloud_rev = 5
	_reqs.clear()
	## ★拉取故意回【失败】: 回 [] 的话 empty 那条路自己也会把版本号设 0,
	##   下面「换号时归零」就分不清是谁干的 —— 两条路都得 0 的判据是恒真式。
	_next = {"ok": false, "code": 0, "body": ""}
	var ok: bool = SB._apply_verify(true, 200,
		'{"access_token":"at-r","expires_in":3600,"refresh_token":"rt-r","user":{"id":"uid-cloud","email":"a@b.co"}}',
		SB.FLOW_RECOVER)
	await get_tree().process_frame
	_chk("⑨ ★分母: 取回成功、换成了云端那个号", ok and str(GameState.account_id) == "uid-cloud",
		GameState.account_id)
	var pulls: Array = []
	for r in _reqs:
		if str(r["method"]) == "GET" and str(r["url"]).contains("/rest/v1/saves"):
			pulls.append(r)
	_chk("⑨ ★★取回之后真的去拉了云存档", pulls.size() == 1, str(pulls.size()))
	_chk("⑨ ★★拉的是【取回的那个号】的存档(不是本机原来那个)",
		pulls.size() == 1 and str(pulls[0]["url"]).contains("account_id=eq.uid-cloud"),
		str(pulls[0]["url"]) if pulls.size() == 1 else "")
	_chk("⑨ ★换号时版本号归零(旧号的版本号对新号没意义; 不归零会撞冲突)",
		int(GameState.cloud_rev) == 0, str(GameState.cloud_rev))


# ─────────────────────────────────────────────────────────────
# ⑩ 真 save() 会标脏
# ─────────────────────────────────────────────────────────────
func _t_save_marks_dirty() -> void:
	print("── ⑩ 真 save() 会标脏 ──")
	SB._reset_save_sync_for_test()
	_login("me@x.co")
	GameState.cloud_rev = 3
	GameState.meta_deepsea_coins = 4040
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._transport_for_test = _spy
	_next = {"ok": true, "code": 200, "body": '{"ok": true, "rev": 4}'}
	_reqs.clear()
	SB.maybe_push_save()
	await get_tree().process_frame
	_chk("⑩ ★分母: 没 save 过 ⇒ 不脏 ⇒ 不推", _reqs.is_empty(), str(_reqs.size()))
	var tm: bool = GameState.test_mode
	GameState.test_mode = false        # 开闸: save() 在 test_mode 下直接 return, 标脏那行永远走不到
	GameState.save()
	GameState.test_mode = tm
	SB.maybe_push_save()
	await get_tree().process_frame
	_chk("⑩ ★★真的 save() 一次之后, 下一拍就推了(推送挂在 save() 上, 不靠逐个挂钩)",
		_reqs.size() == 1, str(_reqs.size()))
	_restore_savefile()


# ─────────────────────────────────────────────────────────────
# ⑪ 冲突二选一 ②: 用这台的覆盖云端
# ─────────────────────────────────────────────────────────────
func _t_resolve_local() -> void:
	print("── ⑪ 冲突时选「用这台的」 ──")
	SB._reset_save_sync_for_test()
	_login("me@x.co")
	GameState.cloud_rev = 3
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._transport_for_test = _spy
	_next = {"ok": true, "code": 200, "body": '{"ok": false, "reason": "conflict", "rev": 8}'}
	GameState.meta_deepsea_coins = 8080
	SB.note_save_dirty()
	SB.maybe_push_save()
	await get_tree().process_frame
	_chk("⑪ ★分母: 先造出一次冲突(云端第 8 版)", SB.save_conflict())
	_reqs.clear()
	_next = {"ok": true, "code": 200, "body": '{"ok": true, "rev": 9}'}
	SB.resolve_conflict_use_local()
	await get_tree().process_frame
	var j = JSON.parse_string(str(_reqs[0]["body"])) if _reqs.size() == 1 else {}
	_chk("⑪ ★★选「用这台的」⇒ 拿云端当前版本(8)去比较并交换 —— 明确表示「我知道是第 8 版, 就要覆盖它」",
		j is Dictionary and int((j as Dictionary).get("p_expected_rev", -1)) == 8,
		str((j as Dictionary).get("p_expected_rev", "?")) if j is Dictionary else "没发")
	_chk("⑪ 覆盖成功后冲突解除、版本号 9", not SB.save_conflict() and int(GameState.cloud_rev) == 9,
		str(GameState.cloud_rev))
