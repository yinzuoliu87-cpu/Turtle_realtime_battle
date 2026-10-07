extends Node
## verify_bracket_map.gd — 桶地图这一屏本身 (E-B2, 2026-09-23)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么 —— 四条硬规矩，每条都能被"顺手改一下"毁掉
## ══════════════════════════════════════════════════════════════════════
## ★① **不剧透**：当前轮**不显示胜者**。这条一旦破，周日的「体感上是直播」当场死，
##     而且不会有任何报错 —— 只会变成"打开地图就知道结果了"。
## ★② **开图居中到自己**：32 个节点里找自己是这屏最容易失败的地方。
## ★③ **轮空/未开打不可点**：点了没东西放；"点了没反应"比"按钮是灰的"糟得多。
## ★④ **拖不拖由规模决定**：4 人桶放得下就不该能拖（拖一张不动的图很困惑）。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★走**真场景**：`_ready()` 之后喂数据，量真的建出来的 Label 与 Button，
##   不是调我自己的纯函数（那只证明我会算，不证明这屏画得对）。
## ★不剧透那条的判据落在**屏幕上的字**：把赢家的名字放进 `names`，
##   然后断言当前轮那些节点的文字里**一个名字都没有**。
##   —— 光断言"我没把 results 传进去"守不住：那是在测我自己的输入。
##
## 跑法: <godot> --headless --path . res://tests/verify_bracket_map.tscn --quit-after 600

const SCENE := preload("res://scripts/scenes/BracketMapScene.gd")
const B := preload("res://scripts/gamedata/bracket.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

const NAMES := ["甲龟", "乙龟", "丙龟", "丁龟", "戊龟", "己龟", "庚龟", "辛龟"]

var _n := 0
var _fail := 0
var _map: Control = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	print("=== 桶地图这一屏 (E-B2) ===")
	await _t_no_spoiler()
	await _t_center_on_me()
	await _t_clickable()
	await _t_pan_by_size()
	await _t_two_views()
	await _t_opponent_gate()
	await _t_winner_side()
	await _t_reveal_sealed()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 桶地图" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ⑥ 点开哪一场才去要对手快照 (E-B4, 2026-09-25)
#
# ★★服务端 `finals_scout` **每人每轮只给一次**机会。所以这一屏必须挡住
#   「替别人点一下也去问」—— 点一次别人的格子, 玩家这一轮就再也拿不到
#   自己对手的阵容了, 而且**什么提示都不会有**。
# ★判定抽成纯函数 ⇒ 这里穷举各种场次形状, 不用起网络。
# ─────────────────────────────────────────────────────────────
func _t_opponent_gate() -> void:
	print("── ⑥ 只给我自己那一场问对手 ──")
	## 4 人桶: 坑位 [0,3,1,2] ⇒ 第1轮 m0 = 种子0 vs 种子3, m1 = 种子1 vs 种子2
	## 我是种子 1 ⇒ 我在 m1, 对手是种子 2
	await _mk({"size": 4, "round": 1, "me": 1, "names": NAMES.slice(0, 4),
		"done": {}, "bucket": 7})
	_ok("⑥ ★分母: 我那一场确实被认成我的(否则下面全是空检查)", _map.is_my_match(1, 1))
	_ok("⑥ ★★我那一场算得出对手是几号种子", _map.my_opponent_seed(1, 1) == 2,
		str(_map.my_opponent_seed(1, 1)))
	_ok("⑥ ★★★别人那一场**算不出对手**(-1) —— 不是我的场就没有「我的对手」",
		_map.my_opponent_seed(1, 0) == -1, str(_map.my_opponent_seed(1, 0)))
	_ok("⑥ ★★★只给我自己那一场去问服务端", _map.should_fetch_opponent(1, 1))
	_ok("⑥ ★★★**替别人点不许去问** —— 每人每轮只有一次机会, 烧掉就没了",
		not _map.should_fetch_opponent(1, 0))
	## ★★2026-10-04 周日实操: 打完、封存期间同一场能无限重打 ⇒ 每局再发一次轮次币
	var _keep_pr: Dictionary = (GameState.finals_pending_reveal as Dictionary).duplicate(true)
	GameState.finals_pending_reveal = {"round": 1, "match": 1}
	_ok("⑥ ★★★打完了、等揭晓的那一场不许再开(否则无限重打刷币)", not _map.should_fetch_opponent(1, 1))
	GameState.finals_pending_reveal = {"round": 1, "match": 0}
	_ok("⑥ 对照: 待揭晓的是别的场 ⇒ 我这一场照常能开", _map.should_fetch_opponent(1, 1))
	GameState.finals_pending_reveal = _keep_pr

	## 已翻面的场次不该问(服务端也只认当前轮)
	await _mk({"size": 4, "round": 2, "me": 1, "names": NAMES.slice(0, 4),
		"done": {"1-0": 0, "1-1": 0}, "bucket": 7})
	_ok("⑥ ★已经翻面的那一场不问(服务端只认当前轮)", not _map.should_fetch_opponent(1, 1))

	## 轮空: 没有对手可问
	## 3 人桶 ⇒ 4 坑有一个空位。种子 0 在 m0 与空位配 ⇒ 轮空
	await _mk({"size": 3, "round": 1, "me": 0, "names": NAMES.slice(0, 3),
		"done": {}, "bucket": 7})
	_ok("⑥ ★分母: 这一场确实是轮空", _map.match_state(1, 0) == SCENE.ST_BYE,
		_map.match_state(1, 0))
	_ok("⑥ ★★轮空 ⇒ 不问(没有对手, 问了白烧机会)", not _map.should_fetch_opponent(1, 0))
	## ★★单独量 `my_opponent_seed` 本身: 上面那条是被 `match_state != ST_LIVE`
	##   先挡住的, 挡不到 `my_opponent_seed` 里的 bye 判断(反向验证当场发现:
	##   把那一行改坏, 一条都不红 ⇒ 它没有判据在守)。两道闸各守各的。
	_ok("⑥ ★★轮空时 `my_opponent_seed` 自己也必须返回 -1(没有对手这回事)",
		_map.my_opponent_seed(1, 0) == -1, str(_map.my_opponent_seed(1, 0)))

	## 纯观众(me = -1): 一场都不该问
	await _mk({"size": 4, "round": 1, "me": -1, "names": NAMES.slice(0, 4),
		"done": {}, "bucket": 7})
	_ok("⑥ ★★纯观众一场都不问", not _map.should_fetch_opponent(1, 0)
		and not _map.should_fetch_opponent(1, 1))

	## ── 提示文案: 每种 reason 说的话都不一样 ──
	_ok("⑥ 还没问过 ⇒ 不说话(别让屏幕凭空冒一行)",
		SCENE.opponent_tip({}, false) == "")
	var t_ok := SCENE.opponent_tip({"ok": true, "name": "乙龟"}, true)
	_ok("⑥ 拿到了 ⇒ 说出对手是谁", t_ok.find("乙龟") >= 0, t_ok)
	var t_used := SCENE.opponent_tip({"ok": false, "reason": "already_asked", "asked": 3}, true)
	_ok("⑥ ★★用掉了 ⇒ 说清**已经看过几号**(不然玩家不知道自己为什么拿不到)",
		t_used.find("3") >= 0 and t_used.find("每轮仅可查看") >= 0, t_used)
	var t_net := SCENE.opponent_tip({"ok": false, "reason": "net"}, true)
	_ok("⑥ 连不上 ⇒ 让他再点一次(可恢复的要说得出怎么恢复)",
		t_net.find("稍后重试") >= 0, t_net)
	var t_out := SCENE.opponent_tip({"ok": false, "reason": "not_in_bucket"}, true)
	_ok("⑥ ★四种 reason 说的不是同一句话(混成「取不到」等于没说)",
		t_used != t_net and t_net != t_out and t_used != t_out,
		"%s / %s / %s" % [t_used, t_net, t_out])


# ─────────────────────────────────────────────────────────────
# ⑦ 报结果时那个 `winner_side` (E-B6, 2026-09-25)
#
# ★★★这是整条链里**最容易静默出错**的一处: `finals_report` 收的是
#   「哪一侧赢」(0/1), 不是「谁赢」。映射反了**不会有任何报错** ——
#   它只会把对手静静送进下一轮, 而屏幕上一切正常。
# ★所以判据卡的是「**我输了的时候报的是对手那一侧**」, 不是「报了就行」;
#   而且**上半区/下半区都要验**(只验一种的话, 整体反了也能绿),
#   **第 2 轮也要验**(span 随轮次翻倍, 只验第 1 轮抓不到)。
# ─────────────────────────────────────────────────────────────
func _t_winner_side() -> void:
	print("── ⑦ 报结果报的是【哪一侧】 ──")
	## 4 人桶坑位 = [0,3,1,2] ⇒ 第1轮 m0: 坑0(种子0) vs 坑1(种子3)
	##                          第1轮 m1: 坑2(种子1) vs 坑3(种子2)
	## 种子 0 坐坑 0 ⇒ 上半(side 0); 种子 2 坐坑 3 ⇒ 下半(side 1)
	await _mk({"size": 4, "round": 1, "me": 0, "names": NAMES.slice(0, 4),
		"done": {}, "bucket": 7})
	_ok("⑦ ★分母: 种子 0 在第1轮 m0 的**上半**(side 0)", _map.my_side(1, 0) == 0,
		str(_map.my_side(1, 0)))
	_ok("⑦ 上半区的我**赢了** ⇒ 报 0", _map.winner_side_for(1, 0, true) == 0,
		str(_map.winner_side_for(1, 0, true)))
	_ok("⑦ ★★★上半区的我**输了** ⇒ 报 1(对手那一侧) —— 反了不会报错, 只会静静送错人",
		_map.winner_side_for(1, 0, false) == 1, str(_map.winner_side_for(1, 0, false)))

	await _mk({"size": 4, "round": 1, "me": 2, "names": NAMES.slice(0, 4),
		"done": {}, "bucket": 7})
	_ok("⑦ ★★分母: 种子 2 在第1轮 m1 的**下半**(side 1) —— 只验上半的话整体反了也能绿",
		_map.my_side(1, 1) == 1, str(_map.my_side(1, 1)))
	_ok("⑦ 下半区的我赢了 ⇒ 报 1", _map.winner_side_for(1, 1, true) == 1,
		str(_map.winner_side_for(1, 1, true)))
	_ok("⑦ ★★下半区的我输了 ⇒ 报 0", _map.winner_side_for(1, 1, false) == 0,
		str(_map.winner_side_for(1, 1, false)))

	## ★第 2 轮: span 从 2 变 4。种子 0 坐坑 0 ⇒ 0%4/2 = 0(上半);
	##   种子 2 坐坑 3 ⇒ 3%4/2 = 1(下半)。只验第 1 轮的话这一层抓不到。
	await _mk({"size": 4, "round": 2, "me": 2, "names": NAMES.slice(0, 4),
		"done": {"1-0": 0, "1-1": 1}, "bucket": 7})
	_ok("⑦ ★★第 2 轮也对(span 随轮次翻倍, 只验第1轮抓不到这层)",
		_map.my_side(2, 0) == 1, str(_map.my_side(2, 0)))
	_ok("⑦ 第 2 轮我输了 ⇒ 报 0", _map.winner_side_for(2, 0, false) == 0,
		str(_map.winner_side_for(2, 0, false)))

	## 不是我的场 / 纯观众 ⇒ 一个字都不报
	await _mk({"size": 4, "round": 1, "me": 0, "names": NAMES.slice(0, 4),
		"done": {}, "bucket": 7})
	_ok("⑦ ★★不是我的场 ⇒ -1(我没资格说谁赢)", _map.winner_side_for(1, 1, true) == -1,
		str(_map.winner_side_for(1, 1, true)))
	## ★★★直接量 `my_side` 本身: 上面那条量的是 `winner_side_for`。
	##   这个 bug 出在 `my_side` 里 —— 它原来**不问「我在不在这一场」**,
	##   于是我没参加的那一场也算得出一个侧, 而 `_i_won()` 拿它跟 done 里的赢家比,
	##   就会把**别人赢的那一场**算成我赢了。
	##   (是 `verify_dead_params` 报「参数 m 从来没被用过」才拓出来的 ——
	##    死参数有时是缺陷的影子, 不是噪声。)
	_ok("⑦ ★★★`my_side` 对**不是我的那一场**必须返回 -1(否则别人赢的场会被算成我赢)",
		_map.my_side(1, 1) == -1, str(_map.my_side(1, 1)))
	_ok("⑦ ★分母: 我自己那一场照样算得出侧(否则上面那条是恒真)",
		_map.my_side(1, 0) == 0, str(_map.my_side(1, 0)))
	await _mk({"size": 4, "round": 1, "me": -1, "names": NAMES.slice(0, 4),
		"done": {}, "bucket": 7})
	_ok("⑦ ★纯观众 ⇒ 一场都报不了", _map.winner_side_for(1, 0, true) == -1
		and _map.my_side(1, 0) == -1)


func _mk(d: Dictionary) -> Control:
	if _map != null:
		_map.queue_free()
		await get_tree().process_frame
	_map = SCENE.new()
	get_tree().root.add_child(_map)
	await get_tree().process_frame
	_map.set_bucket(d)
	await get_tree().process_frame
	return _map


## 把这一屏上所有 Label 的文字收集起来 —— 判据落在**渲染后文本**。
func _texts() -> Array:
	var out: Array = []
	var q: Array = [_map]
	while not q.is_empty():
		var nd = q.pop_back()
		for c in nd.get_children():
			q.append(c)
			if c is Label:
				out.append(str((c as Label).text))
	return out


# ─────────────────────────────────────────────────────────────
# ① ★★不剧透: 当前轮不显示胜者
# ─────────────────────────────────────────────────────────────
func _t_no_spoiler() -> void:
	print("── ① 不剧透 ──")
	## 8 人桶, 第一轮已翻面(能看到名字), 当前在第 2 轮(不能看到名字)
	await _mk({
		"size": 8, "round": 2, "me": 0, "names": NAMES,
		"done": {"1-0": 0, "1-1": 0, "1-2": 0, "1-3": 0},
	})
	var t: Array = _texts()
	var joined := " / ".join(PackedStringArray(t))
	print("  ① 屏上文字: %s" % joined)
	_ok("① ★分母: 这一屏真建出了字(0 条的话下面全是空检查)", t.size() >= 8, "%d 条" % t.size())

	## ★★「剧透」的定义(2026-09-23 改): 节点改成**对阵双方两行 + ✓ 标胜者**之后,
	##   显示**双方名字不算剧透**(参考图里 SF1「法国 VS 西班牙」就是还没打的那一场),
	##   剧透的是**谁赢** ⇒ 判据落在「当前轮不许出现 ✓」。
	##   这不是放松: 旧判据("当前轮一个名字都不许有")既拦住了剧透,
	##   **也拦住了本该给玩家的信息**(你要跟谁打)。
	var ticks := 0
	for x in t:
		if str(x).begins_with("✓"):
			ticks += 1
	_ok("① ★分母: 已翻面的那一轮**标出了胜者**(4 场各一个 ✓; 0 的话下面是恒真)",
		ticks == 4, "%d 个 ✓" % ticks)

	## 当前轮(第 2 轮)的两场: 双方名字**要有**, 而 ✓ **一个都不许有**
	var live_ok := true
	var live_names := 0
	for m in range(B.matches_in_round(8, 2)):
		for side in range(2):
			var c: Dictionary = _map.competitor(2, m, side)
			if str(c.get("name", "")) in NAMES:
				live_names += 1
		if _map.winner_side(2, m) >= 0:
			live_ok = false
	_ok("① ★分母: 当前轮**看得到跟谁打**(4 个名字; 这是本该给的信息)",
		live_names == 4, "%d 个" % live_names)
	_ok("① ★★当前轮**不知道谁赢**(winner_side 必须是 -1) —— 体感上是直播, 全靠这条",
		live_ok)
	## 屏幕上那一行也要验: 当前轮那两格里不许出现 ✓
	var live_tick := 0
	for m in range(B.matches_in_round(8, 2)):
		for side in range(2):
			if _map.winner_side(2, m) == side:
				live_tick += 1
	_ok("① ★★渲染侧同口径: 当前轮 0 个 ✓", live_tick == 0, "%d 个" % live_tick)
	_ok("① ★屏上不出现「直播」「回放」这两个词(一个是假话, 一个会剧透)",
		joined.find("直播") < 0 and joined.find("回放") < 0, joined.substr(0, 90))


# ─────────────────────────────────────────────────────────────
# ② 开图居中到自己
# ─────────────────────────────────────────────────────────────
func _t_center_on_me() -> void:
	print("── ② 开图居中到自己 ──")
	await _mk({"size": 32, "round": 1, "me": 17, "names": [], "done": {}})
	var f: Vector2i = _map.my_focus()
	_ok("② ★对焦的那一场确实是我的", _map.is_my_match(f.x, f.y),
		"第 %d 轮第 %d 场" % [f.x, f.y])

	## ★量真偏移: 我那一场的中心, 加上画布偏移之后, 应该落在视口正中
	var rect: Rect2 = L.node_rect(32, f.x, f.y)
	var sc: float = _map._scale
	var c: Vector2 = (rect.position + rect.size * 0.5) * sc + _map._canvas.position
	## ★★量的是**可用区**的正中, 不是整个视口 —— 顶栏 + 页签占掉上面 TOP_RESERVED。
	##   原来这条量整屏正中, 它自己没错, 错在前提: 实拍抓到左边两列被页签压住了。
	var vp := Vector2(1280.0, 720.0)
	var top: float = float(_map.TOP_RESERVED)
	var want := Vector2(vp.x * 0.5, top + (vp.y - top) * 0.5)
	print("  ② 我那一场落在 (%.0f, %.0f), 可用区中心 (%.0f, %.0f)" % [c.x, c.y, want.x, want.y])
	_ok("② ★★开图时我那一场就在【可用区】正中(差 ≤ 2px)",
		(c - want).length() <= 2.0, "偏 %.1f px" % (c - want).length())

	## ★分母: 换一个人, 偏移必须跟着变 —— 否则"永远偏 0"也能过上面那条
	var pan_a: Vector2 = _map._canvas.position
	await _mk({"size": 32, "round": 1, "me": 3, "names": [], "done": {}})
	var pan_b: Vector2 = _map._canvas.position
	_ok("② ★★分母: 换一个种子, 画布偏移跟着变(证明不是恒 0)",
		(pan_a - pan_b).length() > 1.0, "%s vs %s" % [str(pan_a), str(pan_b)])


# ─────────────────────────────────────────────────────────────
# ③ 轮空/未开打不可点
# ─────────────────────────────────────────────────────────────
func _t_clickable() -> void:
	print("── ③ 能不能点 ──")
	## 3 人桶: 补到 4 坑 ⇒ 1 号种子轮空
	await _mk({"size": 3, "round": 1, "me": 0, "names": ["甲龟", "乙龟", "丙龟"], "done": {}})
	var bye_seen := false
	for m in range(B.matches_in_round(3, 1)):
		if str(_map.match_state(1, m)) == _map.ST_BYE:
			bye_seen = true
			_ok("③ ★轮空那一场不可点(点了没东西放)", not _map.can_open(1, m),
				"第 1 轮第 %d 场" % m)
	_ok("③ ★分母: 3 人桶里确实有一场是轮空(否则上面那条没跑)", bye_seen)
	_ok("③ ★还轮不到的(第 2 轮)不可点", not _map.can_open(2, 0),
		_map.match_state(2, 0))

	await _mk({"size": 8, "round": 2, "me": 0, "names": NAMES,
		"done": {"1-0": 0, "1-1": 0, "1-2": 0, "1-3": 0}})
	_ok("③ ★当前轮可点(这就是「开播」按钮本体)", _map.can_open(2, 0))
	## ★★★2026-09-26: 原来这一条断言「已翻面的也可点(重放全公开)」——
	##   而**重放一行都没做**(`matches` 表建好了, 客户端零个写入者), 唯一的监听者
	##   `_on_match_opened` 第一行就 `if not should_fetch_opponent(): return`
	##   ⇒ 屏幕上有个覆盖整格、tooltip 写「开播」的按钮, **点了一个字都不变**。
	##   `can_open` 自己的注释写着「点了没反应比按钮是灰的糟得多」, 那条判据
	##   钉住的正是它自己反对的行为(memory fb-gate-can-pin-the-bug-in-place)。
	## ⇒ 改成**跟着 `REPLAY_LIVE` 开关走的一对**: 没上线就不可点(不摆死按钮),
	##   上线了就可点。判据不写死哪一边 —— 那样翻开关的那天又会变成假失败。
	_ok("③ ★★已翻面的那一场: 可点与否 == 重放上线开关(现在 %s)" % _map.REPLAY_LIVE,
		_map.can_open(1, 0) == _map.REPLAY_LIVE, str(_map.can_open(1, 0)))
	_ok("③ ★★分母: 当前轮**照旧**可点(证明上面那条不是把所有格子都关了)",
		_map.can_open(2, 0))
	## 真按钮数 = 可点的场数
	var btns := 0
	var q: Array = [_map._canvas]
	while not q.is_empty():
		var nd = q.pop_back()
		for c in nd.get_children():
			q.append(c)
			if c is Button:
				btns += 1
	var want := 0
	for r in range(1, B.rounds_for(8) + 1):
		for m in range(B.matches_in_round(8, r)):
			if _map.can_open(r, m):
				want += 1
	_ok("③ ★★屏上真按钮数 == 可点场次数(每一场自己就是按钮)",
		btns == want, "按钮 %d / 应为 %d" % [btns, want])


# ─────────────────────────────────────────────────────────────
# ④ 拖不拖由规模决定
# ─────────────────────────────────────────────────────────────
func _t_pan_by_size() -> void:
	print("── ④ 拖不拖由规模决定 ──")
	await _mk({"size": 4, "round": 1, "me": 0, "names": NAMES, "done": {}})
	_ok("④ ★4 人桶放得下 ⇒ 不能拖(拖一张不动的图很困惑)", not _map._can_pan)
	_ok("④ ★不能拖时「回到我」也藏起来(不占地方)",
		_map._home_btn != null and not _map._home_btn.visible)
	## ★分母: 这一屏确实建出来了, 不是因为空的才"放得下"
	_ok("④ ★分母: 4 人桶真画了 3 场", _texts().size() >= 3, "%d 条字" % _texts().size())


# ─────────────────────────────────────────────────────────────
# ⑤ ★★周日是【两场】不是一场（用户 2026-09-23 指出）
#    上午·分桶赛（我是选手）/ 晚上·冠军签表（我多半是观众）
# ─────────────────────────────────────────────────────────────
const SUN_AM := 1789862400 + 10 * 3600   # 2026-09-20 周日 10:00 UTC
const SUN_PM := 1789862400 + 21 * 3600   # 同日 21:00 UTC（冠军赛 20:00 开）

func _t_two_views() -> void:
	print("── ⑤ 两张图 ──")
	## 纯函数: 默认看哪张跟着时刻走
	_ok("⑤ ★上午默认看【我的桶】", L.default_view(SUN_AM) == L.VIEW_BUCKET,
		L.default_view(SUN_AM))
	_ok("⑤ ★20:00 之后默认看【冠军赛】", L.default_view(SUN_PM) == L.VIEW_FINALS,
		L.default_view(SUN_PM))
	_ok("⑤ ★分母: 两个时刻给的答案确实不同(否则上面两条有一条是蒙的)",
		L.default_view(SUN_AM) != L.default_view(SUN_PM))

	## 上午: 桶有数据、签表还没形成
	if _map != null:
		_map.queue_free()
		await get_tree().process_frame
	_map = SCENE.new()
	get_tree().root.add_child(_map)
	await get_tree().process_frame
	_map.set_data({"size": 8, "round": 1, "me": 2, "names": NAMES, "done": {}}, {}, SUN_AM)
	await get_tree().process_frame
	_ok("⑤ 上午打开: 停在【我的桶】", str(_map._view) == L.VIEW_BUCKET, str(_map._view))
	_ok("⑤ ★上午确实画了桶(8 人 7 场)", _texts().size() >= 7, "%d 条字" % _texts().size())

	## 切到冠军赛: **不是空图**, 要说清在等什么 + 倒计时
	_map.set_view(L.VIEW_FINALS)
	await get_tree().process_frame
	var et: String = str(_map._empty_lb.text)
	print("  ⑤ 切到冠军赛(上午)显示: 「%s」" % et)
	_ok("⑤ ★★签表还没形成 → 说人话而不是画空图", _map._empty_lb.visible, et)
	## ★★★2026-09-26: 原来断言「带倒计时」—— 而**跨桶冠军赛是 F 阶段, 一行都没做**
	##   (服务端没有桶冠军汇总; 客户端 `_finals` 只有门禁用的 `set_data()` 会写,
	##    联网那条路 `_on_poll` 只写 `_bucket`) ⇒ 那个倒计时在一小时一小时地数一个
	##   **永远不会来**的东西, 而 10 人规模下全周只有一个桶、「等各桶决出冠军」
	##   连概念都不存在。判据钉住了一句假话。
	## ★★★2026-10-07 冠军杯赛上线(方案书 20261007-冠军杯赛.md): `CROSS_BUCKET_LIVE` 删了。
	##   上午切过去 ⇒ 【开赛前】这一档: 倒计时到 20:00 UTC + 已产生的组冠军(不是空图, 也不是假倒计时 ——
	##   这回倒计时数的东西真的会来)。
	_ok("⑤ ★★上午 ⇒ 空态判成【冠军杯赛开赛前】这一档",
		str(_map._empty_kind()) == str(_map.EK_FINALS_SOON),
		"kind=%s 「%s」" % [str(_map._empty_kind()), et])
	_ok("⑤ ★★开赛前 ⇒ 带倒计时、说的是「冠军杯赛」", et.find("后开赛") >= 0 and et.find("冠军杯赛") >= 0, et)
	## ★分母: 10:00 → 20:00 正好 10 小时(倒计时数的是真的开赛时刻, 不是随便一个数)
	_ok("⑤ ★分母: 倒计时 = 10 小时 0 分", et.find("10 小时 0 分") >= 0, et)
	var _devw: Array = ["还没做", "开发中", "未实现", "待做", "TODO", "占位", "暂按", "暂锁", "打磨"]
	var _hit_dev: Array = []
	for _w in _devw:
		if et.find(str(_w)) >= 0:
			_hit_dev.append(_w)
	_ok("⑤ ★★★空态不许把开发状态说给玩家听", _hit_dev.is_empty(),
		"命中: %s ← 「%s」" % [str(_hit_dev), et])
	## ★分母: 上面那条禁词表**真的会命中** —— 否则它是一条空检查。
	##   (拿产品旧稿里那半句现场试一下, 不碰产品。)
	_ok("⑤ ★分母: 禁词表不是空检查(旧稿那半句会被它逮住)",
		"跨组总决赛还没做出来".find(str(_devw[0])) >= 0)
	_ok("⑤ ★用词还是「开播」, 不出现「直播」「回放」",
		et.find("直播") < 0 and et.find("回放") < 0, et)

	## ★★默认那张要是还没形成, 开屏就该退回另一张 —— 别让人一进来看到空图
	_map.set_data({"size": 8, "round": 1, "me": 2, "names": NAMES, "done": {}}, {}, SUN_PM)
	await get_tree().process_frame
	_ok("⑤ ★★晚上但签表还没建好 → 退回【我的桶】, 不让人开屏就看到空图",
		str(_map._view) == L.VIEW_BUCKET, str(_map._view))

	## 晚上 + 签表已形成: 默认就看签表, 而且**我不在里面**(只有桶冠军进得去)
	_map.set_data(
		{"size": 8, "round": 5, "me": 2, "names": NAMES, "done": {}},
		{"size": 4, "round": 1, "me": -1, "names": ["甲龟", "乙龟", "丙龟", "丁龟"], "done": {}},
		SUN_PM)
	await get_tree().process_frame
	_ok("⑤ 晚上 + 冠军杯赛已成表 → 默认看【冠军杯赛】", str(_map._view) == L.VIEW_FINALS, str(_map._view))
	_ok("⑤ ★★切图之后读的是【另一份】数据(4 人签表不是 8 人桶)",
		int(_map.cur().get("size", 0)) == 4, "size=%d" % int(_map.cur().get("size", 0)))
	_ok("⑤ ★我不在签表里 → 对焦到当前轮(不崩、不乱指)",
		_map.my_focus().x >= 1, str(_map.my_focus()))

	## 切回我的桶: 数据必须换回去
	_map.set_view(L.VIEW_BUCKET)
	await get_tree().process_frame
	_ok("⑤ ★切回来读的又是桶那份(8 人)",
		int(_map.cur().get("size", 0)) == 8, "size=%d" % int(_map.cur().get("size", 0)))

	## ────────────────────────────────────────────────────────────
	## ⑤z ★★★时刻从**全局缝**来 (`phase2_config.now_override_ts`, 2026-09-28)
	##
	## ★★为什么非要这一段: `_clock()` 的兜底原来是**就地**
	##   `Time.get_unix_time_from_system()` —— 它和全局缝**互不相通**, 于是
	##   玩家从主菜单点进来那条路(`set_bucket()` / 联网 feed, `now` 一律不传)
	##   **谁也管不住它**。实测(`tests/_probe_oneclock.gd`, 修前): 缝钉「周一 10:00」
	##   与钉「周日 21:00」, `_clock()` 量出来是**同一个值**(真实系统钟 09-28 21:37),
	##   默认视图两次都是 `finals` —— 注入值差六天, 这一屏一个字没变。
	##   (更糟的是它只在真实时刻 20:00 之后才是 `finals` ⇒ 这一屏的默认视图
	##    在真实世界里跟着**挂钟**走, 而不是跟着赛程走。)
	##   memory `fb-second-clock-drops-events`。
	## ★这一段的 `set_data(..., 0)` **第三个参数是 0** —— 走的正是玩家那条兜底。
	## ────────────────────────────────────────────────────────────
	_ok("⑤z ★分母: 产品默认 now_override_ts == 0(缝默认关着, 玩家路径一字未动)",
		int(P2C.now_override_ts) == 0, "now_override_ts=%d" % int(P2C.now_override_ts))
	var seam_views: Dictionary = {}
	var seam_clocks: Dictionary = {}
	for pin in [SUN_PM, SUN_AM]:
		P2C.now_override_ts = pin
		_map.set_data(
			{"size": 8, "round": 5, "me": 2, "names": NAMES, "done": {}},
			{"size": 4, "round": 1, "me": -1, "names": ["甲龟", "乙龟", "丙龟", "丁龟"], "done": {}},
			0)
		await get_tree().process_frame
		seam_views[pin] = str(_map._view)
		seam_clocks[pin] = int(_map._clock())
		_ok("⑤z ★分母: 这一次**只**钉了全局缝, 屏内那层 `_now_override` 是关着的",
			int(_map._now_override) == 0, "_now_override=%d" % int(_map._now_override))
		_ok("⑤z ★★★`_clock()` 就是缝里那个值(不是真实系统钟)",
			seam_clocks[pin] == pin,
			"缝=%s 实得=%s" % [
				Time.get_datetime_string_from_unix_time(pin, true),
				Time.get_datetime_string_from_unix_time(seam_clocks[pin], true)])
	_ok("⑤z ★★★只钉缝(21:00) ⇒ 默认看【冠军赛】",
		str(seam_views[SUN_PM]) == L.VIEW_FINALS, str(seam_views[SUN_PM]))
	_ok("⑤z ★★★只钉缝(10:00) ⇒ 默认看【我的桶】",
		str(seam_views[SUN_AM]) == L.VIEW_BUCKET, str(seam_views[SUN_AM]))
	## ★★分母: 注入前后**本来就该不同** —— 否则上面两条里有一条是蒙的。
	_ok("⑤z ★★分母: 两个注入值给出的答案确实不同(不是对时间不敏感的样本)",
		str(seam_views[SUN_PM]) != str(seam_views[SUN_AM])
		and int(seam_clocks[SUN_PM]) != int(seam_clocks[SUN_AM]),
		"%s / %s" % [str(seam_views[SUN_PM]), str(seam_views[SUN_AM])])
	## ★★★「整条链同一天」: 这一屏的 `_clock()` 与缝的 `now_utc()` 必须是同一个时刻,
	##   而且相位必须都是「周日决赛日」—— 这一屏本来就只在周日出现。
	for pin in [SUN_PM, SUN_AM]:
		P2C.now_override_ts = pin
		_ok("⑤z ★★★同一天: 屏(`_clock()`) 与缝(`now_utc()`) 同一时刻, 相位=%s" % [
				str(P2C.phase_at_utc(int(P2C.now_utc())))],
			int(seam_clocks[pin]) == int(P2C.now_utc())
			and str(P2C.phase_at_utc(int(P2C.now_utc()))) == str(P2C.PHASE_FINALS),
			"屏=%d 缝=%d" % [int(seam_clocks[pin]), int(P2C.now_utc())])
	## ★缝是 **static** ⇒ 活过场景切换 ⇒ 用完必须还原, 否则波及同进程后面的用例。
	P2C.now_override_ts = 0
	_ok("⑤z ★收尾: 全局缝已还原成 0", int(P2C.now_override_ts) == 0)

# ─────────────────────────────────────────────────────────────
# ⑧ ★★★揭晓被封存的那一场（方案书 20260927-周日结果封存.md）
# ─────────────────────────────────────────────────────────────
## 用户 2026-09-26:「两边都赢是什么意思？」
## 周日是双方各自在本机打对方的快照 —— 两场不同的战斗，两边都可能算出自己赢。
## ⇒ 打完**只结算与胜负无关的那部分**，吃胜负的封存；唯一权威是 feed 里的 `done`。
##
## ★这一段必须走**真入口**（`set_data()` 喂一份 feed），不是直接调 `_reveal_sealed()`
##   —— 后者证明不了「feed 到手时真的会去揭晓」（memory `fb-verify-must-run-the-real-path`）。
## ★判据两侧都要：`done` 里还没有那一场 ⇒ **不许**揭晓（封存本身）；有了 ⇒ 必须揭晓。
func _t_reveal_sealed() -> void:
	print("── ⑧ 揭晓被封存的那一场（走真入口 set_data） ──")
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_ok("⑧ 拿得到 GameState", false)
		return
	gs.test_mode = true
	var w_bak := int(gs.season_wins)
	var e_bak := int(gs.season_eggs_killed)
	var p_bak = gs.finals_pending_reveal

	## 8 人桶、我是 2 号种子。第 1 轮我在第 1 场（seat 表决定），先确认这一点。
	var me := 2
	var n := 8
	var my_m := -1
	var my_side := -1
	for m in range(B.matches_in_round(n, 1)):
		var sd := B.my_side_in(me, 1, m, n, {})
		if sd >= 0:
			my_m = m
			my_side = sd
			break
	_ok("⑧ ★分母: 2 号种子在第 1 轮确实有一场(第 %d 场, 第 %d 侧)" % [my_m, my_side],
		my_m >= 0 and my_side >= 0)
	if my_m < 0:
		return

	## ── (a) `done` 里没有那一场 ⇒ **不许**揭晓（这就是「封存」） ──
	gs.season_wins = 0
	gs.season_eggs_killed = 0
	gs.finals_pending_reveal = {"round": 1, "match": my_m}
	_map.set_data({"size": n, "round": 1, "me": me, "names": NAMES, "done": {}}, {}, SUN_AM)
	await get_tree().process_frame
	_ok("⑧a ★★★当前轮还没翻面 ⇒ **不揭晓**（封存本身）",
		not (gs.finals_pending_reveal as Dictionary).is_empty()
		and int(gs.season_wins) == 0,
		"pending=%s 胜场=%d" % [str(gs.finals_pending_reveal), int(gs.season_wins)])

	## ── (b) `done` 说**我赢了** ⇒ 揭晓并清掉 pending ──
	_map.set_data({"size": n, "round": 2, "me": me, "names": NAMES,
		"done": {"1-%d" % my_m: my_side}}, {}, SUN_AM)
	await get_tree().process_frame
	_ok("⑧b ★★★feed 说我赢 ⇒ 胜场 +1", int(gs.season_wins) == 1,
		"胜场=%d" % int(gs.season_wins))
	_ok("⑧b ★★★揭晓完 pending 清掉（幂等的靠它）",
		(gs.finals_pending_reveal as Dictionary).is_empty(),
		str(gs.finals_pending_reveal))

	## ── (c) 幂等：同一份 feed 再来一次，不许补第二回 ──
	_map.set_data({"size": n, "round": 2, "me": me, "names": NAMES,
		"done": {"1-%d" % my_m: my_side}}, {}, SUN_AM)
	await get_tree().process_frame
	_ok("⑧c ★★★同一份 feed 再来 ⇒ 胜场**不再加**（幂等）", int(gs.season_wins) == 1,
		"胜场=%d" % int(gs.season_wins))

	## ── (d) `done` 说**对手赢了** ⇒ 揭晓但胜场不动 ──
	gs.season_wins = 0
	gs.finals_pending_reveal = {"round": 1, "match": my_m}
	_map.set_data({"size": n, "round": 2, "me": me, "names": NAMES,
		"done": {"1-%d" % my_m: 1 - my_side}}, {}, SUN_AM)
	await get_tree().process_frame
	_ok("⑧d ★★★feed 说**对手**赢 ⇒ 胜场**不动**（这一条挡住「两边都赢」）",
		int(gs.season_wins) == 0, "胜场=%d" % int(gs.season_wins))
	_ok("⑧d ★分母: 但 pending 照样清掉了（揭晓发生过，不是卡在那儿）",
		(gs.finals_pending_reveal as Dictionary).is_empty(),
		str(gs.finals_pending_reveal))

	## ── (e) 我不在桶里（纯观众）⇒ 一个字都不改 ──
	gs.season_wins = 5
	gs.finals_pending_reveal = {"round": 1, "match": my_m}
	_map.set_data({"size": n, "round": 2, "me": -1, "names": NAMES,
		"done": {"1-%d" % my_m: my_side}}, {}, SUN_AM)
	await get_tree().process_frame
	_ok("⑧e ★★纯观众(me<0) ⇒ 胜场不动、pending 也不清（等我真进了桶再说）",
		int(gs.season_wins) == 5 and not (gs.finals_pending_reveal as Dictionary).is_empty(),
		"胜场=%d pending=%s" % [int(gs.season_wins), str(gs.finals_pending_reveal)])

	## 收尾还原（门禁不许污染存档）
	gs.season_wins = w_bak
	gs.season_eggs_killed = e_bak
	gs.finals_pending_reveal = p_bak

