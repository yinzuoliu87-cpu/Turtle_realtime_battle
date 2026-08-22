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
	## ★★覆盖面: 直接从 `pets.json` 取【全部 28 只】, 不写死名单。
	##   第一版我手挑了 12 只(哨兵历轮抓出来的那几个) —— 那只能证明"我知道的那些修好了",
	##   证明不了"没有类似问题"。用户 2026-08-22 问的正是这个:「确定修好了吗, 没有类似问题吗」。
	##   从数据源取还有个好处: **以后新增的龟自动纳入**, 不需要有人记得来改这份名单。
	var ROSTER: Array = []
	for pid in DataRegistry.pet_by_id.keys():
		ROSTER.append(str(pid))
	ROSTER.sort()   # 确定顺序(字典遍历顺序不保证) —— 这条门禁要可复现
	## 28 只对半分两边 ⇒ 每只龟本场都在场(一边一半, 谁也不缺席)。
	for si in range(2):
		var sd: String = "left" if si == 0 else "right"
		var half: int = int(ceil(float(ROSTER.size()) * 0.5))
		var lo: int = 0 if si == 0 else half
		var hi: int = half if si == 0 else ROSTER.size()
		for i in range(lo, hi):
			var px: float = scn.ARENA.position.x + scn.ARENA.size.x * (0.22 if si == 0 else 0.78)
			var py: float = scn.ARENA.position.y + scn.ARENA.size.y * (0.12 + 0.055 * float(i - lo))
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
	print("  分母: 本场上场龟种 %d / 全库 %d" % [ROSTER.size(), DataRegistry.pet_by_id.size()])
	_ok(ROSTER.size() == DataRegistry.pet_by_id.size() and ROSTER.size() >= 28,
		"分母·全部龟种都在场 %d/%d（少一只就是那只没被测到）" % [ROSTER.size(), DataRegistry.pet_by_id.size()])

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

	# ── ①c 暴击态: 同一个病的双胞胎 ──────────────────────────────
	## `_last_atk_crit` 与 `_last_dmg_type` 是**同一行**由 `_resolve_dmg` 写的(主文件
	## 829/830 两行), 病也一样: 弹在飞, 全局被别人改掉, 命中时捡到别人的暴击。
	## 后果不止显示(大字+暴击图标+暴击音), 忍者斩击的流血层数就读它(暴击 3 层/否则 2 层)。
	## 修前实测: 51 发弹道命中里 12 发(24%)不一致。
	## ★这条断言【不是同义反复】: drift 是还原**之前**的不一致(病的频率, 当分母),
	##   applied_wrong 是还原**之后**的不一致 —— 谁把还原那行删了, 它立刻非 0。
	var cd: int = int(scn._ballistics._crit_drift)
	var cw: int = int(scn._ballistics._crit_applied_wrong)
	print("  暴击对账: 还原前不一致 %d 发(分母·病的频率) / 还原后仍不一致 %d 发" % [cd, cw])
	_ok(cd > 0, "分母·本场真的发生过跨帧弹道暴击漂移 %d 发（=0 则下面那条是空检查）" % cd)
	_ok(cw == 0, "①c 暴击态: 命中时用的暴击 ≠ 发射时掷的 %d 发（必须 0）" % cw)

	# ── ①d on-hit 的暴击态: 闭掉 equip_system 里那个自己登记的缺口 ─────
	## 原注释:「从掷骰到调 on-hit 之间, 若【防守方】带反伤(荆棘海胆/石头)或凤凰熔岩盾/
	## 闪电雷盾, 那几段反击也走 raw 掷骰, 会把这个全局值改成"反击那一发是否暴击"。
	## 要根治得给 on-hit 加一个入参(= 改 battle_damage.gd 的中央管线签名), 本批不动那条路。」
	## ⇒ 现在就是加了那个入参。`gap` = 传进来的快照与此刻全局不一致的次数 = **缺口的真实频率**,
	##   它 > 0 就证明这个缺口真的会发生(分母, 不是我假想的); `nopass` 必须为 0 ——
	##   有人调 on-hit 却不传 crit, 就是又退回读全局。
	var eg: int = int(scn._equip_sys._eq_crit_gap)
	var en: int = int(scn._equip_sys._eq_crit_nopass)
	print("  on-hit 暴击态: 快照≠全局 %d 次(缺口真实频率) / 没传参 %d 次" % [eg, en])
	_ok(en == 0, "①d on-hit 暴击态: 有 %d 次调用没传快照(会退回读全局·必须 0)" % en)

	# ── ② 触手拍击不许静默丢伤害 ────────────────────────────────
	var pk: Dictionary = scn._spirit_syn._pk
	var queued: int = int(pk.get("queued", 0))
	var dropped: int = int(pk.get("dropped", 0))
	var resolved: int = int(pk.get("resolved", 0))
	print("  触手账本: 发起 %d / 被闸门丢掉 %d / 真结算 %d / 零命中 %d" % [
		queued, dropped, resolved, int(pk.get("zero_hit", 0))])
	_ok(queued >= MIN_SLAPS, "分母·本场拍了 %d 次 ≥ %d（太少=空检查）" % [queued, MIN_SLAPS])
	_ok(dropped == 0, "②拍击伤害: 被静默丢弃 %d 次（必须 0）" % dropped)
	## ★②b 这条不只管触手 —— `_pending_shots` 是**全仓 25 个延时结算**(枪械连射/法器/
	##   药水落地/护盾羁绊…)共用的队列。回调失效 = 演出照演、结算永不发生, 且**一声不吭**。
	##   放在这里断言, 等于替那 25 处一起把关。
	_ok(int(scn._ballistics._ps_drop_invalid) == 0,
		"②b 延时结算队列: 回调失效被丢 %d 次（必须 0·覆盖全仓 25 个 _queue_shots 使用者）"
		% int(scn._ballistics._ps_drop_invalid))
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
