extends Node
## verify_battle_seed.gd — 守「这一场战斗的 sim 种子被如实登记, 并一路走到决赛上报的 p_seed」。
##
## ★由来(2026-09-28 查实): `GameState.battle_seed` **全仓零个写入点** —— 声明(GameState.gd:170)、
##   `reset_dual_lane()` 里清 0、两个读者, 就是没有人写非 0 值。于是:
##     · `Backend.report_finals_if_any()` 的 `p_seed` **恒为 0** ⇒ 每一场周日决赛报上去都是
##       「这一场没留下可复算的种子」(服务端 `finals_results.seed_used`, schema 注释「确定性重算用的种子」)。
##     · `GameState.ai_dual_shop()` 里 `if battle_seed != 0` 恒假(而那个函数本身零调用者=另一笔债)。
##   真值一直存在 —— `RealtimeBattle3DScene._battle_rng` 在 `battle_world_builder._build_camera()`
##   里被播种(`TURTLE_SEED` 设了用它, 否则 `randomize()`)。缺的只是**登记这一步**。
##   ⇒ 修法: `_ready()` 紧跟 `_build_camera()` 调 `GameState.note_battle_seed(_battle_rng.seed)`。
##   (memory `fb-read-a-field-nobody-writes`: 镜像有读者、没有写者。)
##
## ★★本门禁面对的是「死代码型」的变异不红(memory `fb-mutation-not-reddening-can-mean-dead-code`),
##   所以**每条断言都配一条分母** —— 证明被测对象在场、那条路真的被走到, 而不是"什么都没发生两遍一样"。
##
## ⚠ 诚实边界: 本门禁**不声称**「决赛已可服务端复算」。正式对局不开 `_deterministic`
##   (只有 `TURTLE_SEED` 设时才开), 且 `_juice_rng` 等落点无条件 `randomize()`
##   (清单见 `tests/_det_scenarios.gd` ⑧)。这里只守「种子被如实记下、且如实传到上报那一层」。
##
## 重场景按 BSOD 记忆**顺序**建/free, 不同时开(与 verify_battle_determinism 同做法)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const _BE := preload("res://scripts/net/backend.gd")
const _SB := preload("res://scripts/net/supabase.gd")

var _fail := 0
var _n := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)


## 把一个整数送一趟「存档/上云」真实走的那条序列化路: `JSON.stringify` → `JSON.new().parse()`
## (与 `GameState.save()` / `_load` 同一对函数), 返回回来之后的值。
func _json_roundtrip(v: int) -> int:
	var txt := JSON.stringify({"s": v})
	var j := JSON.new()
	if j.parse(txt) != OK:
		return 0
	return int((j.data as Dictionary).get("s", 0))

## 建一场轻量战斗场(DEBUG_EDIT=空编辑场·不跑整场对局), 走的是**真入口 `_ready()`**。
func _build() -> Node:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _free(s: Node) -> void:
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("FAILED: 拿不到 /root/GameState")
		get_tree().quit(1)
		return
	gs.test_mode = true          # 不许往 user:// 写存档
	gs.week_anchor_ts = 1700000000
	_SB.finals_report_clear()    # 本进程「报过了」的记账清干净, 否则 ③ 会被自己的去重挡住

	# ───────────────────────────── ① TURTLE_SEED 设时: 登记的就是那个种子
	gs.battle_seed = 0
	_ok("分母①a 建场前 battle_seed == 0(证明下面的非 0 是这一次建场写进去的, 不是遗留值)",
		int(gs.battle_seed) == 0, "battle_seed=%d" % int(gs.battle_seed))
	OS.set_environment("TURTLE_SEED", "808808")
	var s1 = await _build()
	_ok("分母①b 播种那一步真的跑到了(_deterministic=true ⇒ TURTLE_SEED 分支被走到)",
		s1._deterministic == true)
	_ok("分母①c 真值源在场且被播了种(_battle_rng.seed == 808808)",
		int(s1._battle_rng.seed) == 808808, "rng.seed=%d" % int(s1._battle_rng.seed))
	_ok("★① TURTLE_SEED 设时 battle_seed 登记为该种子(可复现/回放能报出是哪一场)",
		int(gs.battle_seed) == 808808, "battle_seed=%d" % int(gs.battle_seed))
	_ok("★② battle_seed 与真值源 _battle_rng.seed 逐位相同(不是另抄一个数 —— 手抄的副本必然落后)",
		int(gs.battle_seed) == int(s1._battle_rng.seed),
		"%d vs %d" % [int(gs.battle_seed), int(s1._battle_rng.seed)])
	await _free(s1)

	# ───────────────────────────── ② 不设 TURTLE_SEED = 正式对局那条路
	OS.set_environment("TURTLE_SEED", "")
	gs.battle_seed = 0
	var s2 = await _build()
	_ok("分母②a 走的是正式对局那一支(_deterministic=false ⇒ randomize 分支)",
		s2._deterministic == false)
	var sd2: int = int(s2._battle_rng.seed)
	_ok("分母②b randomize() 给出了非 0 种子(真值源非空, 否则下面是空检查)",
		sd2 != 0, "rng.seed=%d" % sd2)
	_ok("★③ 正式对局(无 TURTLE_SEED)也登记, 且登记的就是 randomize 出来的那个真种子",
		int(gs.battle_seed) == sd2 and int(gs.battle_seed) != 0,
		"battle_seed=%d rng.seed=%d" % [int(gs.battle_seed), sd2])
	_ok("★④ 对局中 battle_seed != 0 ⇒ GameState.gd 那条 `if battle_seed != 0` 的前置条件不再恒假",
		int(gs.battle_seed) != 0, "battle_seed=%d" % int(gs.battle_seed))

	# ── ②' 落盘/上云的 JSON 往返不许把种子漂掉(过夜补报单就走这条路)
	#    ★分母是"这条检查真的抓得住东西": 拿一个**未规范化的完整 int64** 去走同一趟往返,
	#      它必须漂掉。不打这条分母, 下面那句就可能是"任什么数都通得过"的空检查。
	var raw64: int = -3986105570584568105          # 探针实测 randomize() 的真实量级
	_ok("分母②c 同一趟 JSON 往返对【未规范化的 int64】确实会漂(证明这条检查抓得住东西)",
		_json_roundtrip(raw64) != raw64, "%d → %d" % [raw64, _json_roundtrip(raw64)])
	_ok("★⑤ 规范化后的 battle_seed 走 JSON 往返逐位不变(存档/上云/过夜补报单都走这一趟)",
		_json_roundtrip(sd2) == sd2, "%d → %d" % [sd2, _json_roundtrip(sd2)])
	_ok("★⑥ battle_seed 落在 [1, 2^53-1](0 是保留值·上界是 double 精确整数上限)",
		sd2 >= 1 and sd2 <= gs.BATTLE_SEED_MAX, "sd=%d 上界=%d" % [sd2, int(gs.BATTLE_SEED_MAX)])

	# ───────────────────────────── ③ 端到端: 种子真的进了决赛上报的 p_seed
	_BE.last_finals_report = {}
	gs.finals_report_pending = {}
	gs.finals_pending_reveal = {}
	gs.finals_match = {"bucket": 3, "round": 2, "match": 5, "side": 0}
	_ok("分母③a 上报前留痕是空的(证明下面那份是这一次写的)",
		(_BE.last_finals_report as Dictionary).is_empty())
	_BE.report_finals_if_any(true)                     # ★真入口, 不是重算一遍公式
	var rep: Dictionary = _BE.last_finals_report
	_ok("分母③b 上报那条路真的走完了, 且留痕就是我这一场(round=2 / match=5)",
		not rep.is_empty() and int(rep.get("round", -1)) == 2 and int(rep.get("match", -1)) == 5,
		str(rep))
	_ok("分母③c finals_match 被清空(函数跑到了末尾, 不是半路早退)",
		(gs.finals_match as Dictionary).is_empty())
	_ok("★⑦ 报上去的 p_seed == 这一场的 battle_seed 且非 0(原来恒 0 = 服务端复算不出那一场)",
		int(rep.get("seed", -1)) == sd2 and sd2 != 0,
		"报=%d  本场=%d" % [int(rep.get("seed", -1)), sd2])
	_ok("★⑧ 过夜补报单上的 seed 与真发出去的那个是同一个(两份一分岔, 补报就报成另一场)",
		int((gs.finals_report_pending as Dictionary).get("seed", -1)) == sd2,
		"单子=%d  本场=%d" % [int((gs.finals_report_pending as Dictionary).get("seed", -1)), sd2])
	var body: Dictionary = _SB.finals_report_body(
		int(gs.week_anchor_ts), 3, 2, 5, 0, int(rep.get("seed", 0)))
	_ok("分母③d 组包里确实有 p_seed 这个键(键名与服务端对不上是这类接口最常见的死法)",
		body.has("p_seed"), str(body.keys()))
	_ok("★⑨ 发给服务端的 body.p_seed 非 0 且 == 本场种子(→ finals_results.seed_used)",
		int(body.get("p_seed", 0)) == sd2 and sd2 != 0, "p_seed=%d" % int(body.get("p_seed", -1)))
	await _free(s2)

	# ───────────────────────────── ④ 换一场 → 换一个种子
	gs.battle_seed = 0
	var s3 = await _build()
	var sd3: int = int(gs.battle_seed)
	_ok("分母④a 第三场也登记了非 0 种子", sd3 != 0, "battle_seed=%d" % sd3)
	_ok("★⑩ 换一场就换一个种子(不是写死的常量, 也不是上一场的残留)",
		sd3 != sd2, "第三场=%d  第二场=%d" % [sd3, sd2])
	await _free(s3)

	# ───────────────────────────── ⑤ 开新局清 0 的契约没坏
	_ok("分母⑤a 清 0 之前它是非 0 的", int(gs.battle_seed) != 0, "battle_seed=%d" % int(gs.battle_seed))
	gs.reset_dual_lane()
	_ok("★⑪ reset_dual_lane() 仍把它清回 0(0 的含义=这一场没留下可复算的种子)",
		int(gs.battle_seed) == 0, "battle_seed=%d" % int(gs.battle_seed))

	# ── 收尾: 变异过的进程内状态还原(本测不落盘, 但别把脏值留给同进程后续)
	OS.set_environment("TURTLE_SEED", "")
	gs.battle_seed = 0
	gs.finals_match = {}
	gs.finals_report_pending = {}
	gs.finals_pending_reveal = {}
	_BE.last_finals_report = {}
	_SB.finals_report_clear()

	if _fail == 0:
		print("ALL PASS (%d/%d) — 这一场的 sim 种子被如实登记, 并一路走到决赛上报的 p_seed" % [_n, _n])
	else:
		print("FAILED: %d/%d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
