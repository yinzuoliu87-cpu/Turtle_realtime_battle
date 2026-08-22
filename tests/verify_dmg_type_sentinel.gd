extends Node
## verify_dmg_type_sentinel.gd — 伤害飘字【类型不许是捡来的】+ 触手拍击【不许静默丢伤害】
##
## ══════════════════════════════════════════════════════════════════════
##  由来（用户 2026-08-22 两条实拍）
## ══════════════════════════════════════════════════════════════════════
## ①「怎么还是有时候看到触手打得时候跳的伤害数字是紫色的没有符合规则，
##    这是很严重的bug有的时候物理伤害被跳成了蓝色数字，得彻查吧」
## ②「而且有的时候触手打中没任何伤害是什么bug」
##
## 【① 的病根】飘字颜色**只看全局** `battle._last_dmg_type`，而它**只有
##   `_resolve_dmg` 会写**。任何不走 `_resolve_dmg` 的伤害，落地时读到的是
##   【上一发别人的伤害】留下的类型 —— 物理跳成蓝，物理暴击跳成紫（`crit-magic`）。
##   仓库里有 230 个伤害调用点，靠读代码挑出"哪些没走 `_resolve_dmg`"是 158 个嫌疑，
##   逐个人肉判断必然漏。⇒ 改成**运行时记账**：`_resolve_dmg` 置 fresh，
##   伤害落地时取用并清掉；取用时发现 fresh 已经是 false ⇒ 这一发是捡来的，记一笔。
##   一场真实对局跑下来，30 发捡类型，**全部**出自弹道（飞行途中全局被覆写）。
##
## 【② 的病根】拍击伤害走的是 `_queue_shots(delay=hit_delay())` 这条**第二时钟**，
##   到点再用 `is_striking(serial)` 复核。延时 1.48s，闸门窗口只有 1.63s ⇒ 余量 0.15s；
##   且时停时队列冻结、触手动画照走 ⇒ 两钟必然错开。探针实测 13% 的拍击
##   **完整演出、零伤害**。已改成挂在触手自己的"梢端触地"一次性标志上。
##
## ══════════════════════════════════════════════════════════════════════
##  这条门禁为什么能守住（而不是又一个"数我自己插的标记"）
## ══════════════════════════════════════════════════════════════════════
## · 记账点在**产品自己取用类型的那一行**（`battle_damage._take_dtype`），
##   不是我在某个 fix 旁边插的标记 —— 新写的伤害代码只要不设类型就会被记上，
##   我不需要预先知道它存在。(memory [[fb-gate-must-measure-requirement-not-my-hook]])
## · **每条断言配分母**：`sentinel_total()` = 一共取用了多少次类型。
##   N=0 是"这场没打伤害"= 空检查，不是通过。(memory [[fb-gate-subject-never-constructed]])
## · 触手账本同样是**无条件记账**、放在事件发生处，不采样。
##
## 反向验证（怎么证明它会红）：把 `battle_ballistics._push_proj` 里那行
##   `d["dtype"] = battle._last_dmg_type` 删掉，本用例立刻报 ★FAIL 且数字回到 30 上下；
##   把 `tentacle_vfx` 里 `_cb.call()` 那行删掉，触手账本 resolved 掉到 0。
## 本轮实测递减序列（同一份探针、同一条判据）：30 → 6 → 1 → 0。
##
## 跑：<godot> --path . res://tests/verify_dmg_type_sentinel.tscn
##   SENT_SECS=40  跑多少秒（默认 40）

const MIN_TOTAL := 150          # 分母下限：这场至少要打出这么多次伤害，否则不算数
const MIN_SLAPS := 3            # 触手至少要拍这么多次，否则触手那半边不算数

var _fails: PackedStringArray = []


func _ok(cond: bool, msg: String) -> void:
	print(("  [ OK ] " if cond else "  [FAIL] ") + msg)
	if not cond:
		_fails.append(msg)


func _ready() -> void:
	## 哨兵是 env 开关的（正式对局零开销）⇒ 门禁自己把它打开。
	OS.set_environment("DMGSENTINEL", "1")
	OS.set_environment("SHIP", "1")          # 关 demo 劫持, 否则假人不死、结算路径测不到
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame

	## ★★这条门禁必须是【确定的】—— 阵容随机 ⇒ 同一份代码这次绿下次红,
	##   而且"这场没打到那只龟"会让真实缺陷漏网(实测三连跑里两次 0、一次 3)。
	##   ⇒ ① 播种 sim RNG ② 用**写死的名单**建双方阵容, 覆盖那些自己重写伤害的龟。
	scn._battle_rng.seed = 20260822
	for u in scn._units.duplicate():
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp):
			sp.queue_free()
	scn._units.clear()
	## 名单挑的是【伤害路径自己重写过】的龟(哨兵历轮抓出来的那些 + 各类远程/DoT/延时结算),
	## 不是随手抓 —— 判据要能照到被测对象(memory [[fb-gate-subject-never-constructed]])。
	var ROSTER := ["shell", "headless", "two_head", "bubble", "line", "stone",
		"lava", "pirate", "ninja", "crystal", "bamboo", "phoenix"]
	for si in range(2):
		var sd: String = "left" if si == 0 else "right"
		for i in range(ROSTER.size()):
			var px: float = scn.ARENA.position.x + scn.ARENA.size.x * (0.22 if si == 0 else 0.78)
			var py: float = scn.ARENA.position.y + scn.ARENA.size.y * (0.14 + 0.062 * float(i))
			var nu: Dictionary = scn._spawn._make_unit(str(ROSTER[i]), sd, Vector2(px, py))
			## 灵物件塞满 ⇒ 两边都长触手(不塞的话触手那半边断言全是空检查)
			nu["equips"] = [{"id": "p2eq_032", "star": 1}, {"id": "p2eq_025", "star": 1},
				{"id": "p2eq_014", "star": 1}, {"id": "p2eq_045", "star": 1},
				{"id": "p2eq_051", "star": 1}]
			scn._units.append(nu)
	## ★必须先 clear 再 apply_all —— apply_all 里有 is_empty() 守卫, 缓存非空就不重算,
	##   我换掉的阵容会被忽略(A6 场景第一版就栽在这)。
	scn._synergy.clear()
	scn._synergy.apply_all()
	for u in scn._units:
		scn._recalc_stats(u)
	var tl: int = int(scn._spirit_syn._side_tier("left"))
	var tr: int = int(scn._spirit_syn._side_tier("right"))

	var secs: float = float(OS.get_environment("SENT_SECS")) if OS.has_environment("SENT_SECS") else 40.0
	## ★墙钟，不是帧数、不是游戏时钟（CLAUDE.md §3.5：三把尺子里只有墙钟对）。
	var t0: float = float(Time.get_ticks_msec()) / 1000.0
	while float(Time.get_ticks_msec()) / 1000.0 - t0 < secs:
		await get_tree().process_frame

	print("=== verify_dmg_type_sentinel ===")
	print("  分母: 灵物档位 左=%d 右=%d" % [tl, tr])
	_ok(tl > 0 and tr > 0, "分母·两边都有触手 (左=%d 右=%d)" % [tl, tr])

	# ── ① 飘字类型不许是捡来的 ──────────────────────────────────
	var rep: Dictionary = scn._damage.sentinel_report()
	var total: int = int(scn._damage.sentinel_total())
	var stale := 0
	for k in rep:
		stale += int(rep[k])
	print("  分母: 本场共取用伤害类型 %d 次" % total)
	_ok(total >= MIN_TOTAL, "分母·取用次数 %d ≥ %d（太少=空检查）" % [total, MIN_TOTAL])
	if stale > 0:
		var rows: Array = []
		for k in rep:
			rows.append([int(rep[k]), str(k)])
		rows.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
		for r in rows.slice(0, 12):
			print("      ★捡类型 %d 次: %s" % [int(r[0]), str(r[1])])
	_ok(stale == 0, "①飘字类型: 捡来的 %d 发（必须 0；非 0 时上面列出了 文件:行号）" % stale)
	## ★★第二只眼(归属校验)。①的 `fresh` 只能发现"**没人**设过类型", 发现不了
	##   "同一帧里**别人**刚设了、被我捡走" —— 那种照样是错色, 而且更隐蔽。
	##   ⇒ `_resolve_dmg` 顺手记下"这份类型是算给哪个目标的"(`_dt_owner`),
	##     取用时目标对不上就是捡了别人的。
	##   实测: 刚加上时 128/1292(10%) 不符, 主要是【我自己手写 `_last_dmg_type = ...`
	##   却没记归属】的那几处; 全部收口到 `_damage.set_dtype(类型, 目标)` 后归零。
	##   ⇒ 已从诊断量提升为**判据**。新代码若手写全局而不用 set_dtype, 这条会红。
	var wo: Dictionary = scn._damage.sentinel_wrongowner()
	var wo_n := 0
	for k in wo:
		wo_n += int(wo[k])
	print("  归属校验: 不符 %d 发 / 共 %d 次取用" % [wo_n, total])
	if wo_n > 0:
		var worows: Array = []
		for k in wo:
			worows.append([int(wo[k]), str(k)])
		worows.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
		for r in worows.slice(0, 10):
			print("      ★归属不符 %d 次: %s" % [int(r[0]), str(r[1])])
	_ok(wo_n == 0, "①b 归属校验: 用了【算给别人的】类型 %d 发（必须 0）" % wo_n)

	# ── ② 触手拍击不许静默丢伤害 ────────────────────────────────
	var pk: Dictionary = scn._spirit_syn._pk
	var queued: int = int(pk.get("queued", 0))
	var dropped: int = int(pk.get("dropped", 0))
	var resolved: int = int(pk.get("resolved", 0))
	print("  触手账本: 发起 %d / 被闸门丢掉 %d / 真结算 %d / 零命中 %d" % [
		queued, dropped, resolved, int(pk.get("zero_hit", 0))])
	_ok(queued >= MIN_SLAPS, "分母·本场拍了 %d 次 ≥ %d（太少=空检查）" % [queued, MIN_SLAPS])
	_ok(dropped == 0, "②拍击伤害: 被静默丢弃 %d 次（必须 0）" % dropped)
	## 发起的每一击, 要么已结算, 要么还在动作中（截断那一刻正好在拍）。
	## 允许的在途上限 = 场上触手根数（每根最多欠一击）。
	var in_flight: int = queued - resolved
	var max_flight: int = int(scn._tentacle_vfx.count())
	_ok(in_flight >= 0 and in_flight <= maxi(1, max_flight),
		"②账目平: 发起 %d − 结算 %d = 在途 %d ≤ 触手根数 %d" % [queued, resolved, in_flight, max_flight])

	if _fails.is_empty():
		print("ALL PASS")
	else:
		print("★FAIL x%d" % _fails.size())
		for m in _fails:
			print("   - " + m)
	## ★按仓库标准收尾: 先 queue_free 再让出一帧, 不要让引擎在退出时立即 free 战斗场 ——
	##   那条路径会踩到已登记的拆除时序缺口(KNOWN_LAMBDA_CAP, 见 run-tests.sh)。
	## ★★不 queue_free、直接退出。
	##   实测: 让引擎在退出前多跑几帧释放, `Lambda capture at index N was freed`
	##   反而【越等越多】(1 帧 6 条 → 12 帧 62 条) —— 那是已登记的拆除时序老账
	##   (run-tests.sh 的 KNOWN_LAMBDA_CAP), 场上活的东西越多刷得越凶,
	##   而本用例是 12v12 打满 40 秒, 正是最凶的场面。
	##   与本用例要量的两件事(飘字类型 / 拍击丢伤害)完全无关 ⇒ 不给它机会刷。
	get_tree().quit(0 if _fails.is_empty() else 1)
