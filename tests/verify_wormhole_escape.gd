extends Node
## verify_wormhole_escape.gd — 星际龟「虫洞」方案 C：免控不被捕获 + 位移可脱离 (2026-08-29)
##
## ══════════════════════════════════════════════════════════════════════
##  由来
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-28:「别人如果有位移技能从虫洞跳出来了**为什么又会被闪现回去**？
##                   这个技能到底怎么设计呢」→ 三个方案里选了 **C**：
##   ① 免控免疫的单位不会被捕获
##   ② 被捕获的单位用位移技能能脱离
##
## **病根**：捕获期每一帧都无条件 `oc["pos"] = 洞心 + 轨道偏移` —— 那是**直接写坐标**，
## 谁在这一帧把它移走都会被下一帧覆盖回来。位移技能看着"生效了"其实白放。
##
## ══════════════════════════════════════════════════════════════════════
##  这条门禁守什么
## ══════════════════════════════════════════════════════════════════════
## ★判据落在**单位的真实坐标**（产品自己的 `pos`），走的是虫洞真正的推进闭包
##   —— 不是断言"我插的脱离标记被设过"
##   (memory [[fb-gate-must-measure-requirement-not-my-hook]])。
## ★脱离判据【不认技能名单】：产品侧判的是"它离我上一帧放它的地方有多远"，
##   所以测试也用**最朴素的办法**制造位移 —— 直接把 `pos` 挪走，
##   模拟"任何东西把它移开了"。这正是产品要支持的语义。
## ★每条断言配分母：先证明**没有免控、不位移**的对照单位【确实被抓住了】，
##   否则"没被抓"可能只是虫洞根本没跑起来 (memory [[fb-gate-subject-never-constructed]])。
##
## ★★反向验证要撤【两处】才会红 —— 免控在产品里有两道:
##   ① 捕获那一刻不抓(star_system 捕获分支)
##   ② 携带每帧复查, 中途拿到免控也放走(携带循环)
##   只撤 ①, ② 会在下一帧立刻把它放掉 ⇒ 它压根拖不动 ⇒ 门禁照样绿。
##   **这不是门禁失效, 是产品有兜底。** 我 2026-08-29 第一次反向验证时以为门禁坏了,
##   探针一量才看清(不给免控时 B 被拖 284 码, 给了就是 0)——
##   memory [[fb-probe-before-claiming-rootcause]]: 推理出来的根因不算根因。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_wormhole_escape.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const StarSystem := preload("res://scripts/systems/skills/star_system.gd")

## 被虫洞往【前】(+X, 虫洞飞行方向)拖走多远算"被抓住了"。
## ★引力场只把它往洞心吸一小段, 被携带才会跟着虫洞一路走 ⇒ 这个距离拉得开。
const CAUGHT_DX := 150.0

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 一个单位算不算"被虫洞抓着"：它离洞心在捕获轨道范围内、且被每帧改写着位置。
## ★判据用【离洞心的距离】而不是我插的标记 —— 被携带的单位半径会缓收到 52 码，
##   所以"贴着洞心转"是被抓的**可观察后果**。
func _is_orbiting(o: Dictionary, hole_c: Vector2) -> bool:
	return (o["pos"] as Vector2).distance_to(hole_c) <= StarSystem.WORM_CAPTURE_R


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 虫洞·方案 C(免控不捕获 / 位移可脱离) ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	_ok("★分母: WORM_ESCAPE_DIST 在合理区间(50~400 码)",
		StarSystem.WORM_ESCAPE_DIST >= 50.0 and StarSystem.WORM_ESCAPE_DIST <= 400.0,
		"%.0f 码" % StarSystem.WORM_ESCAPE_DIST)
	## ★2026-08-30 语义从【单帧】改成【累计】后, 这条分母也得跟着换问题:
	##   旧问的是"单帧阈值 > 轨道直径", 理由是"正常绕转不许被误判成脱离"。
	##   累计语义下这个理由不成立 —— 实测捕获期 1971 帧里 **1433 帧漂移恰好 0.000 码**
	##   (虫洞每帧写死坐标, 没人动它就是 0), 绕转一分都不贡献。
	##   现在该问的是: 阈值不能小到【一两帧噪声就攒满】。
	_ok("★分母: 累计阈值 ≥ 单帧最大观测漂移的 10 倍(不然噪声就能攒满)",
		StarSystem.WORM_ESCAPE_DIST >= 1.8 * 10.0,
		"阈值 %.0f vs 实测单帧最大 1.8 码" % StarSystem.WORM_ESCAPE_DIST)

	# ══ 造场：星际龟朝右放虫洞，三个敌人并排站在虫洞必经之路上 ══
	## A = 对照组（什么都不做，必须被抓）
	## B = 免控免疫（不该被抓）
	## C = 被抓之后用"位移"挪走（必须脱离）
	var c0: Vector2 = _s.ARENA.position + Vector2(160.0, _s.ARENA.size.y * 0.5)
	var star: Dictionary = _s._spawn._make_unit("space", "left", c0)
	star["no_basic"] = true
	star["no_move"] = true
	star["atk"] = 100.0
	var mk := func(off: float) -> Dictionary:
		var e: Dictionary = _s._spawn._make_unit("basic", "right", c0 + Vector2(420.0, off))
		e["maxHp"] = 1.0e8
		e["hp"] = 1.0e8
		e["no_basic"] = true
		e["no_move"] = true
		return e
	var ea: Dictionary = mk.call(-30.0)          # 对照
	var eb: Dictionary = mk.call(0.0)            # 免控
	var ec: Dictionary = mk.call(30.0)           # 位移脱离
	eb["cc_immune_until"] = _s._t + 60.0         # ★全仓唯一的免控闸门
	_s._units.clear()
	_s._units.append(star)
	_s._units.append(ea)
	_s._units.append(eb)
	_s._units.append(ec)
	_s._edit_mode = false
	_s._over = false

	_ok("★分母: 免控单位确实处在免控窗口内(不然下面那条是空检查)",
		_s._damage._is_cc_immune(eb) and not _s._damage._is_cc_immune(ea))

	## 朝右放虫洞（目标给 ea，方向就是 +X，三个敌人都在路上）
	_s._star_sys._sk_star_wormhole(star, ea)

	## ★墙钟等虫洞飞过它们（CLAUDE.md §3.5：帧数在无头下每帧只推 1ms；
	##   游戏时钟 `_kill` 后会冻结）。虫洞 140 码/秒，420 码 ≈ 3 秒。
	## ★★"被抓住了"的判据 = **它被虫洞一路拖向边界**（虫洞恒速飞到 ARENA 边界才炸，
	##   被携带的敌人跟着走）。这是被抓的**唯一可观察后果**，而且方向单一、幅度大。
	##
	## ★第一版判据是"离原站位偏移 > 60 码"，**守不住** —— 反向验证当场抓到：
	##   撤掉免控闸门之后门禁照样 ALL PASS。因为免控那只站在虫洞正前方，
	##   即使被抓、绕着洞心转，偏移也可能不到 60 码（轨道半径会缩到 52）。
	##   判据没问对问题 (memory [[fb-judge-must-fit-the-shape]])。
	var base_x: float = c0.x + 420.0
	var maxdx := {"a": 0.0, "b": 0.0, "c": 0.0}
	var c_escaped := false
	var moved_c := false
	var move_y := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		for pair in [[ea, "a"], [eb, "b"], [ec, "c"]]:
			var o: Dictionary = pair[0]
			var dx: float = (o["pos"] as Vector2).x - base_x
			if dx > float(maxdx[str(pair[1])]):
				maxdx[str(pair[1])] = dx
		## C 一旦被明显拖走, 立刻"用位移技能跳走"—— 直接改 pos, 模拟任何位移来源
		if float(maxdx["c"]) > CAUGHT_DX and not moved_c:
			ec["pos"] = (ec["pos"] as Vector2) + Vector2(0.0, 300.0)   # 远超 WORM_ESCAPE_DIST
			move_y = (ec["pos"] as Vector2).y
			moved_c = true
		if moved_c:
			await get_tree().process_frame
			await get_tree().process_frame
			## 脱离成功 = 它留在我们挪过去的那一带, 没被拽回洞心
			c_escaped = absf((ec["pos"] as Vector2).y - move_y) < 120.0
			if not c_escaped:
				break
		await get_tree().process_frame
	var caught_a: bool = float(maxdx["a"]) > CAUGHT_DX
	var caught_b: bool = float(maxdx["b"]) > CAUGHT_DX
	var caught_c: bool = float(maxdx["c"]) > CAUGHT_DX
	print("  [量到] 被往前拖的距离: A(对照)=%.0f  B(免控)=%.0f  C(位移)=%.0f  (阈值 %.0f)"
		% [float(maxdx["a"]), float(maxdx["b"]), float(maxdx["c"]), CAUGHT_DX])

	# ── ① 分母：对照组【确实被抓住了】 ──
	## 没这条的话，"免控没被抓"可能只是虫洞压根没跑起来 —— 那就全是假绿。
	_ok("★★① 分母·对照组(无免控·不位移)确实被虫洞抓住了", caught_a,
		"往前只被拖了 %.0f 码(阈值 %.0f) ⇒ 虫洞没跑起来, 下面两条全是空检查" % [float(maxdx["a"]), CAUGHT_DX])

	# ── ② 方案 C-①：免控免疫的【不被捕获】 ──
	_ok("★★② 免控免疫的单位没有被捕获", not caught_b,
		"往前被拖了 %.0f 码(阈值 %.0f) ⇒ `_is_cc_immune` 那道闸门没生效" % [float(maxdx["b"]), CAUGHT_DX])

	# ── ③ 方案 C-②：被抓之后位移【能脱离】，不会被拽回去 ──
	_ok("★分母: C 真的先被抓住过(不然'脱离'无从谈起)", caught_c,
		"往前被拖了 %.0f 码" % float(maxdx["c"]))
	_ok("★★③ 位移之后没有被闪现回虫洞(用户原话的那个 bug)", moved_c and c_escaped,
		"moved=%s escaped=%s  跳到 y=%.0f, 最终 y=%.0f(洞心一带 y≈%.0f)"
			% [str(moved_c), str(c_escaped), move_y, (ec["pos"] as Vector2).y, c0.y])

	await _t_smooth_escape(c0)
	_done()


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 7:
		print("  [FAIL] ★分母: 断言只有 %d 条(<7) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 虫洞方案 C" if _fail == 0 else "FAIL x%d — 虫洞方案 C" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ④ ★★【平滑位移】也必须能脱离 —— 2026-08-30 用户实测抓到的真 bug
#
#   ★上面 ③ 用的是"直接把 pos 挪 300 码" = **瞬移**。而游戏里绝大多数位移技是
#     **平滑**的(近战小将【人体浪板】拉己滑行 / 猎人翻滚 / 熔岩跃击),
#     实测每帧只把单位挪 **1.7 码**。
#     旧判据"一帧内被挪走 >130 码"对它们**一次都不成立** ⇒ 有位移技也逃不掉,
#     而 ③ 全绿 —— **判据只测了容易的那一半**。
#     (同族 memory [[fb-judge-must-fit-the-shape]]: 判据要刚好卡住那个形状。)
#
#   ★本条就照真实形态喂: 每帧只挪一点点, 累计到阈值就该放人。
# ─────────────────────────────────────────────────────────────
const SMOOTH_STEP := 1.7      # 码/帧 —— 实测人体浪板的真实速率


func _t_smooth_escape(c0: Vector2) -> void:
	print("── ④ 平滑位移(每帧 %.1f 码)也要能脱离 ──" % SMOOTH_STEP)
	var star: Dictionary = _s._units[0]
	var e: Dictionary = _s._spawn._make_unit("basic", "right", c0 + Vector2(420.0, 0.0))
	e["maxHp"] = 1.0e8
	e["hp"] = 1.0e8
	e["no_basic"] = true
	e["no_move"] = true
	_s._units.clear()
	_s._units.append(star)
	_s._units.append(e)
	_s._over = false
	_s._star_sys._sk_star_wormhole(star, e)

	var base_x: float = c0.x + 420.0
	var maxdx := 0.0
	var pushing := false
	var pushed := 0.0
	var freed := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		maxdx = maxf(maxdx, (e["pos"] as Vector2).x - base_x)
		if maxdx > CAUGHT_DX:
			pushing = true
		if pushing and not freed:
			## ★每帧只挪一点点 —— 这就是平滑位移技的真实形态
			e["pos"] = (e["pos"] as Vector2) + Vector2(0.0, SMOOTH_STEP)
			pushed += SMOOTH_STEP
			## ★判据 = 【净位移留下来了多少】。
			##   捕获期虫洞每帧把坐标写回轨道 ⇒ 我推的那 1.7 码当帧就被抹掉, 净位移 ≈ 0。
			##   只有**真被放走**的那些帧, 推的位移才留得下来。
			##   (放走之后它还在 100 码捕获半径内会被再抓, 所以净位移不会很大 ——
			##    判据要卡的是"留下没留下", 不是"跑多远"。)
			if pushed > 300.0:
				break
		await get_tree().process_frame

	_ok("④ ★分母: 它真的先被虫洞抓住并往前拖了(不然'脱离'无从谈起)",
		pushing, "被拖了 %.0f 码" % maxdx)
	## ★判据量【产品自己记的账】: 虫洞放走它几次。
	##   第一版量的是"最终净位移", 反向验证当场抓到它是假的 —— 虫洞飞到边界会自己结束,
	##   之后单位当然自由, 于是【退回旧判据门禁照样绿】。净位移被"洞没了"满足了。
	var n_freed: int = int(e.get("_worm_freed_n", 0))
	freed = n_freed > 0
	_ok("④ ★★平滑位移(每帧 %.1f 码)累计够了就必须放人 —— 不是只有瞬移才算" % SMOOTH_STEP,
		freed, "虫洞放走它 %d 次(累计推了 %.0f 码); 旧的【单帧】判据下这里恒为 0"
			% [n_freed, pushed])
