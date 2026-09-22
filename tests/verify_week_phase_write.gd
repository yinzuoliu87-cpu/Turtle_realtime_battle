extends Node
## verify_week_phase_write.gd — 「这一局在哪个阶段开打」真的被产品自己写进存档了 (2026-09-20)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## `GameState.week_phase` 从 A2 落地起就是**三处读、零处写**：
##   · `battle_hud.gd`  结算屏的「本周场次 N / 配额」只在 `== "ranked"` 时显示
##   · `RealtimeBattle3DScene._settle_season`  拿它决定这一局吃不吃积分赛配额
##   · `GameState.ranked_quota_full()`  拿它决定闯关赛/决赛日要不要放行开局
## 而**没有任何产品代码写过它** ⇒ 永远读到 `""`，三处一律走「按积分赛算」的兜底分支，
## 于是「闯关赛 / 决赛日的场次不吃积分赛配额」这条设计**在真实游戏里从来没生效过**。
##
## ★★为什么此前的门禁看不见：那几条判据都是**测试自己先喂一个 `week_phase` 再去测它**
##   （`verify_week_season ④` 的 `_gs.week_phase = "gauntlet"`、`verify_settle_quota` 同理）。
##   「门禁自己喂那个字段再去测它 = 恒真式」—— memory `fb-read-a-field-nobody-writes`。
##   ⇒ 本门禁走**真入口** `TeamSelectScene._on_start()`，看产品自己写不写。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★★① **一个进程里只能成功走一次 `_on_start()`**。实测：走通那一次会
##     `change_scene_to_file`，而这会**当场**把 current_scene（也就是本门禁自己）拆掉
##     ⇒ 第二次调用起，`inst` 已不在树上，产品那行 `get_tree().change_scene_to_file()`
##     对 null 取方法 ⇒ 日志里出现 `SCRIPT ERROR`。
##     **那一版断言全 PASS、还打了 ALL PASS，但 `run-tests.sh` 的致命正则照样判红。**
##     ⇒ 只调一次，调完立刻 `_done()`（`verify_close_lockout` 头注记的是同一个坑）。
## ★★② 只调一次也要能**排除「产品写死了一个常量」**：
##     注入的日期**动态挑**成「阶段与今天不同」的那一天，然后同时断言
##       · `week_phase == phase_at_utc(注入时刻)`  ← 值是由注入时刻算出来的
##       · `week_phase != phase_at_utc(现在)`      ← 不是照着今天写的
##     写死任何一个常量都过不了这两条（写死的值要么不等于注入日的阶段，
##     要么就等于今天的阶段）。四天 → 四个阶段的映射表本身另由
##     `verify_week_roll ⑤` 逐天钉住，这里不重复。
## ★③ 调用前把 `week_phase` 设成**哨兵值**，断言它确实被改掉 ——
##     不然「产品压根没写、而字段恰好已经是对的」会静默通过。
## ★④ 判据落在 `GameState`（autoload，换场景也活着）上、**不落在场景树**，且全程不 await。
## ★⑤ 再接到**真消费者**上：只改 `week_phase` 一个字段，`ranked_quota_full()` 必须改答案 ——
##     证明这个字段不是写完就躺着。这一段放在 `_on_start()` **之前**跑（之后树就没了）。
## ★⚠ `_on_start()` 内部会 `GameState.save()` ⇒ 全程 `test_mode = true`，
##     并量存档文件的修改时刻证明真没写盘（memory `fb-debug-stage-writes-real-save`）。

## ★实例化**场景**不是脚本（照 `verify_close_lockout` 的做法，别自创）：
##   直接 `TeamSelectScene.gd.new()` 会在 `_ready` 里碰 `theme` 等场景自带的东西而炸。
const TS_SCENE := preload("res://scenes/TeamSelect.tscn")
const TS := preload("res://scripts/scenes/TeamSelectScene.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

## 真实日历样本（UTC），与 `verify_week_roll` 用的是同一周，那边已把日期核对过。
const NOON := 43200
const DAYS := [
	[1789344000, "周一 休赛"],      # 2026-09-14
	[1789603200, "周四 积分赛"],    # 2026-09-17
	[1789776000, "周六 闯关赛"],    # 2026-09-19
	[1789862400, "周日 决赛日"],    # 2026-09-20
]

const SENTINEL := "__门禁哨兵__"

var _ok := 0
var _fail := 0
var _tree: SceneTree = null


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])


func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	print("── week_phase: 开打那一刻由产品自己写 ──")

	GameState.test_mode = true
	_chk("★分母: test_mode 已置位(_on_start 内部会 save())", bool(GameState.test_mode))
	var save_p: String = str(GameState.SAVE_PATH)
	var had: bool = FileAccess.file_exists(save_p)
	var mtime0: int = FileAccess.get_modified_time(save_p) if had else -1

	## ── 挑注入日: 阶段必须【与今天不同】, 否则排除不掉「写死成今天的阶段」 ──
	var now: int = int(Time.get_unix_time_from_system())
	var ph_now: String = str(P2C.phase_at_utc(now))
	var pick_ts: int = 0
	var pick_label: String = ""
	var pick_phase: String = ""
	for d in DAYS:
		var ts: int = int(d[0]) + NOON
		var ph: String = str(P2C.phase_at_utc(ts))
		if ph != ph_now and P2C.can_start_match_utc(ts):
			pick_ts = ts
			pick_label = str(d[1])
			pick_phase = ph
			break
	_chk("★分母: 挑得出一个【阶段与今天不同】且不在封盘窗内的注入日", pick_ts > 0,
		"今天=%s / 选中=%s(%s)" % [ph_now, pick_label, pick_phase])
	if pick_ts <= 0:
		_done()
		return
	_chk("★分母: 选中日的阶段确实 ≠ 今天的阶段(下面那条才排除得掉「写死」)",
		pick_phase != ph_now, "选中 %s vs 今天 %s" % [pick_phase, ph_now])

	## ── ⑤ 先跑纯内存那一段: 这个字段到底有没有真消费者 ──
	##    ★必须放在 `_on_start()` **之前** —— 之后场景树就被拆了。
	##
	## ★★2026-09-22 换判据。原来这一段是:
	##     「闯关赛阶段 + 同样的 ranked_used → `ranked_quota_full()` 判为没打满(放行)」
	##   **那是同一条被钉死的判据的第三份副本**(另两份在 `verify_week_season ④`),
	##   而它钉住的洞是: 闯关赛/决赛日玩法没上线, 那几天却照常开局发奖、不吃配额。
	##   见 `phase2_config.PHASE_MODE_LIVE` 的长注释与 memory
	##   `fb-gate-can-pin-the-bug-in-place` / `fb-branch-to-an-unbuilt-mode-is-a-backdoor`。
	##
	## ★`ranked_quota_full()` 现在**不读这个字段**了 —— 它问的是「**现在**是什么阶段」(时钟),
	##   而存档里的 `week_phase` 回答的是「**上一场**属于哪个阶段」。所以拿它证明本字段活着
	##   本来就是错的消费者。真消费者是 `consume_ranked_quota()`(结算记账)。
	print("── ⑤ 这个字段的真消费者 ──")
	var keep_used: int = int(GameState.ranked_used)
	var keep_phase = GameState.week_phase

	## ⑤a 开局闸**不许**再读存档里那个阶段: 写着 gauntlet 也要按"现在"判
	GameState.ranked_used = int(P2C.RANKED_QUOTA)      # 配额打满
	GameState.week_phase = P2C.PHASE_GAUNTLET          # 上一场是周六打的
	_chk("⑤a ★存档写着 gauntlet + 配额打满 → 仍然拦住(开局闸问时钟不问存档)",
		bool(GameState.ranked_quota_full(1789603200)),   # 2026-09-17 周四
		"week_phase=%s" % str(GameState.week_phase))
	GameState.ranked_used = int(P2C.RANKED_QUOTA) - 1
	_chk("⑤a ★分母: 差一场没打满 → 放行(证明上一条不是恒真式)",
		not bool(GameState.ranked_quota_full(1789603200)))

	## ⑤b 真消费者 `consume_ranked_quota()` 确实读它 —— 答案跟着规则走
	## ★★2026-09-22 E-A: 周六闯关赛上线之后这条判据**又硬起来了** ——
	##   积分赛吃 24 场配额、闯关赛吃它自己的 6 场配额 ⇒ 只改 `week_phase` 这一个字段,
	##   记账结果就不同。上一版那条「显式登记的有意缺口」因此删掉: 缺口已经填上了。
	## ★期望**写死**(+1 / +0), 不问 `phase_mode_live()` —— 问被测函数等于拿它当尺子。
	var delta := {}
	for ph5 in [P2C.PHASE_RANKED, P2C.PHASE_GAUNTLET]:
		GameState.week_phase = ph5
		GameState.ranked_used = 0
		GameState.consume_ranked_quota()
		delta[ph5] = int(GameState.ranked_used)
	GameState.ranked_used = keep_used
	GameState.week_phase = keep_phase
	_chk("⑤b ★积分赛记一场配额 / 闯关赛一场都不记 —— 只改这一个字段答案就不同",
		delta[P2C.PHASE_RANKED] == 1 and delta[P2C.PHASE_GAUNTLET] == 0, str(delta))

	## ── 建真场景 ──
	var inst = TS_SCENE.instantiate()
	add_child(inst)
	var w := 0
	while w < 600 and not inst.is_node_ready():
		await get_tree().process_frame
		w += 1
	for _i in range(10):
		await get_tree().process_frame

	## 凑够 REQUIRED_PETS 只龟 —— 人数不够 `_on_start()` 会在那一关就 return,
	## 那样"没写 week_phase"是人数造成的, 判据就成了恒真式。
	var pool: Array = []
	for p in DataRegistry.all_pets:
		if p is Dictionary and p.has("id"):
			pool.append(str(p["id"]))
		if pool.size() >= int(TS.REQUIRED_PETS):
			break
	_chk("★分母: 取得到 %d 只龟填满阵容" % int(TS.REQUIRED_PETS),
		pool.size() >= int(TS.REQUIRED_PETS), "%d 只" % pool.size())
	if pool.size() < int(TS.REQUIRED_PETS):
		_done()
		return
	for i in range(int(TS.REQUIRED_PETS)):
		inst.team[i] = pool[i]

	## ── ① 走真入口, 只调这一次 ──
	print("── ① 真入口 TeamSelectScene._on_start()(注入 %s) ──" % pick_label)
	GameState.week_phase = SENTINEL
	GameState.left_team = [] as Array[String]
	inst.lockout_now_override = pick_ts
	inst._on_start()
	## ★★下面全部同步读, 一个 await 都不许有(树已经在这一刻被 change_scene 拆掉了)。
	_chk("① ★分母: `_on_start()` 真走到底了(产品写了 left_team, 与写 week_phase 同一段)",
		GameState.left_team.size() == int(TS.REQUIRED_PETS),
		"left_team=%d 只" % GameState.left_team.size())
	_chk("① ★分母: 哨兵被改掉了(证明产品确实写了 week_phase, 不是本来就对)",
		str(GameState.week_phase) != SENTINEL, "实得「%s」" % str(GameState.week_phase))
	_chk("① ★week_phase == phase_at_utc(注入时刻) —— 值是按开打那一刻算的",
		str(GameState.week_phase) == pick_phase,
		"实得「%s」/ 应为「%s」" % [str(GameState.week_phase), pick_phase])
	_chk("① ★★week_phase ≠ 今天的阶段 —— 排除「写死成一个常量」",
		str(GameState.week_phase) != ph_now,
		"实得「%s」/ 今天是「%s」" % [str(GameState.week_phase), ph_now])

	## ★收尾分母: 全程没碰存档文件
	var mtime1: int = FileAccess.get_modified_time(save_p) if FileAccess.file_exists(save_p) else -1
	_chk("★收尾: 存档文件没被写过(有/无 与 修改时刻都没变)",
		FileAccess.file_exists(save_p) == had and mtime1 == mtime0,
		"跑之前 %s/mtime=%d, 跑之后 %s/mtime=%d" % [
			"有" if had else "无", mtime0,
			"有" if FileAccess.file_exists(save_p) else "无", mtime1])
	_done()


func _done() -> void:
	print("")
	print("  (共 %d 条断言)" % (_ok + _fail))
	if _fail == 0:
		print("ALL PASS — week_phase 开打写入 (%d/%d)" % [_ok, _ok])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok])
	if _tree != null:
		_tree.quit(1 if _fail > 0 else 0)
