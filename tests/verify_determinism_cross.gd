extends Node
## verify_determinism_cross.gd — **跨平台**确定性: 逐步指纹压成摘要, 与钉住的金标逐字相同
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁存在的理由(原稿逐字)
## ══════════════════════════════════════════════════════════════════════
## `docs/design/斗龟场大轮赛制方案v2-用户原稿.md` §五.1:
##   「**确定性模拟是全部前提**: 同种子 + 同双方阵容摆位 ⇒ 必然同结果。一切随机走同一
##     种子驱动的 PRNG; 禁止裸调 Math.random(); **禁用依赖帧率/浮点平台差异的逻辑**
##     (定点数或固定步长模拟)。…**此项排期在赛制上线之前**。」
## §五.3:「**结算权在服务端**: 结算一次、存档一份(种子 + 双方阵容包 + 结果摘要);
##     客户端只做重放渲染。」
##
## ⇒ 周日要做成「服务端结算一次 + 双方各看同一份重放」, 前提是**不同设备跑同一份输入
##   必须得到同一份输出**。在这之前, 周日只能各自本机打 —— 而那正是「两边都赢」的根因
##   (双方各算一遍, 服务端 `on conflict do nothing` 先报的算, 后报的那个早就发过奖了)。
##
## ══════════════════════════════════════════════════════════════════════
##  它与 `verify_determinism_b` 的分工(**不是重复**)
## ══════════════════════════════════════════════════════════════════════
## | | 它证明的 | 它证明不了的 |
## |---|---|---|
## | `verify_determinism_b` | 同种子**同进程**两遍逐步逐字相同 | 换个进程 / 换台机器 |
## | **本门禁** | 逐步指纹的摘要 == **钉住的常量** ⇒ 换进程、换 OS、换 libm 都得一样 | 换 CPU 架构(ARM) —— CI 没有 ARM runner, 见 §缺口 |
##
## ★同一份场景表(`tests/_det_scenarios.gd`), 两个门禁共用 —— 抄第二份必然漂。
##
## ══════════════════════════════════════════════════════════════════════
##  为什么「与金标比」这个形状是对的
## ══════════════════════════════════════════════════════════════════════
## 本地跑 Windows(MSVC 的 libm), CI 跑 ubuntu(glibc)。IEEE-754 **只保证**
## `+ - * / sqrt` 逐位一致, **不保证** `sin/cos/tan/atan2/pow/exp/log` ——
## 那几个是各家 libm 各自实现的近似, 差一个 ulp 就够让一局分叉。
## 全仓 sim 路径上这些函数**确实在用**(2026-09-26 扫: RealtimeBattle3DScene 31 处、
## star_system 20、hookbomb 17、chest 11、headless 10、signal_wave 10、phoenix 9 …)。
## ⇒ 静态数数答不了「差多远」, 只有把同一份输入在两个平台上跑出来对一下才知道。
## 金标钉在仓库里 ⇒ **CI 每次 push 都在替我做这个对比**, 不用我手工两边跑。
##
## ★★金标**不是**"随手记一串"。它必须先满足三条, 否则钉住的是噪声:
##   ① 同一台机器跑两遍摘要相同(跨进程稳定) —— 本门禁自己带这一条
##   ② 摘要随场景变化(11 个场景不能出同一个摘要) —— 否则摘要函数坏了
##   ③ 换种子摘要必须变 —— 否则摘要根本没读到随机
##
## ══════════════════════════════════════════════════════════════════════
##  缺口(诚实登记, 不假装覆盖到了)
## ══════════════════════════════════════════════════════════════════════
## · **ARM 没验**: 玩家跑 iOS(ARM64), 而 CI 只出 IPA、不跑测试。本门禁证明的是
##   「Windows/MSVC ↔ Linux/glibc 一致」。ARM 要么上 macOS/ARM runner,
##   要么做成「首次上线时用真机跑一次并把摘要回传」。**在那之前不许声称跨设备确定**。
## · 只覆盖这 13 个场景(2026-10-04 ⑫⑬ 补齐 28 龟: 每只龟至少出场一次)。场景外的技能/装备没被这条尺子量过。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_determinism_cross.tscn --quit-after 12000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SC := preload("res://tests/_det_scenarios.gd")

const GOLDEN_PATH := "res://tests/golden/determinism_cross.json"

## ══════════════════════════════════════════════════════════════════════
##  ★★★已知跨平台分叉台账(2026-09-27) —— 存量记着, **只减不增**
## ══════════════════════════════════════════════════════════════════════
## 为什么要台账而不是让 CI 一直红: **永久红的门禁等于没有门禁** ——
## 它会把所有新出现的分叉一起淹掉, 而那才是这把尺子的价值。
## (本仓已有同形状的先例: `asset_orphan_debt.json` / `tween_capture` 台账。)
##
## 台账里这一条的**全部已知事实**(五轮 CI 实测, 见 `docs/plans/20260926-A跨设备确定性.md` §9):
##   · 10 个场景里**只有这一个**分叉, 另外 9 个 Windows/MSVC ↔ Linux/glibc **逐位相同**
##   · 二分到具体装备: 18 件逐件都不飘, **三件同时在场才飘**(组合效应)
##   · 分叉在**第 271 步**(≈4.5 游戏秒), 前 270 步逐位相同
##   · 差的是**一个浮点末位**: 石头龟的 x, 本地 658.13 / CI 658.12;
##     血量/护盾/暴击/其余 7 只单位**全部相同** ⇒ 不是逻辑分叉, 是数值精度
##
## ★★★2026-10-05 结案、台账清零: 那「一个浮点末位」**根本不是 sim 分叉, 是指纹的格式化**。
##   658.125 / 1274.125 这类**恰好是 .5 的二进制精确值**, `%.2f` 交给各平台 printf 舍入 ——
##   Windows 往远离零舍(658.13), glibc 银行家舍入(658.12)。探针(位模式逐步写盘, WSL 里跑
##   同版本 Linux Godot 对比)实测: ③ 600 步、⑬ 1000 步, 九个字段的**位模式两边逐位相同**,
##   只有格式化后的串不同(③ 101 步、⑬ 1 步: 右队 basic x = 1274.125)。
##   ⇒ 指纹改走位模式(`_det_scenarios.fp`), 金标随之重生; 台账这一条划掉。
##   「三件同时在场才飘」也就说得通了: 只是那个组合恰好把某个坐标走到了 .xx5。
##
## ⚠ **它不阻塞周日的玩法**: v0.19.450 起周日打完不当场宣布胜负, 权威只有服务端的
##   对阵结果, 客户端算出什么都不作数。确定性是**重放**(C 阶段)才要的 ——
##   重放若按「种子 + 阵容」重算, 两台机器必须得出同一份画面。
const KNOWN_DIVERGE := {
}

var _ledger_seen: Array = []

var _fail := 0
var _n := 0
var _digests := {}      # tag → 摘要


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## 全场快照 —— ★与 `verify_determinism_b._fp()` **同一个口径**。
## ⚠ 两处必须一致, 否则两个门禁量的不是同一个东西。`_det_scenarios.gd` 只能抽数据,
##   抽不了这个函数(它读 `scene._units`, 而两边建场的方式不同) ⇒ 用下面那条
##   「字段清单」断言把口径钉住: 加了字段就得两边一起加。
const FP_FIELDS := ["hp", "pos.x", "pos.y", "alive", "shield", "gold", "energy",
	"prism_color", "crit"]

func _fp(scene) -> String:
	return SC.fp(scene)   # ★两个门禁共用一份(见 `_det_scenarios.fp` 头注: 位模式, 不走 %.Nf)


## 跑一个场景 → 返回 [摘要, 逐步指纹数组, 不同指纹数, 累计承伤]
func _run(sc: Dictionary) -> Array:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()
	var lo: Dictionary = sc.get("loadouts", {})
	if not lo.is_empty():
		var gs2 = get_node_or_null("/root/GameState")
		if gs2 != null:
			for k in lo:
				gs2.loadouts[str(k)] = int(lo[k])
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	for p in (sc["pairs"] as Array):
		var pid: String = str(p[0])
		if pid.begins_with("__minion__"):
			var bits: PackedStringArray = pid.split(":")
			s._edit_minion_role = str(bits[1]) if bits.size() > 1 else "front"
			pid = "__minion__"
		var u: Dictionary = s._debug._edit_place_unit(pid, str(p[1]),
			Vector2(float(p[2]), float(p[3])))
		if (p[4] as Array).size() > 0:
			var el: Array = []
			for e in (p[4] as Array):
				el.append({"id": str(e), "star": 3})
			u["_edit_equips"] = el
		## 第 6 项 = 给右队假人恢复真实主动技(见 `_det_scenarios.gd` 的说明)。
		## ★两个消费者**必须一字不差地同样处理** —— 处理方式分家 = 两边跑的不是同一局,
		##   而金标是拿这边跑出来的(memory `fb-hand-rolled-copies-drift`)。
		if (p as Array).size() > 5 and bool(p[5]):
			u["active_skills"] = s._resolve_active_skills(pid, false)
			u["skill_idx"] = 0
	s._debug._edit_start_battle()
	var tr: Array = []
	for _i in range(int(sc["frames"])):
		await get_tree().process_frame
		tr.append(_fp(s))
	var taken := 0.0
	for u2 in s._units:
		taken += float(u2.get("_st_taken", 0.0))
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var uniq := {}
	for f in tr:
		uniq[str(f)] = true
	## ★摘要用 SHA-256 而不是"取前几步" —— 取前几步会把后半局的分叉整段漏掉。
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for f2 in tr:
		ctx.update(str(f2).to_utf8_buffer())
	return [(ctx.finish() as PackedByteArray).hex_encode(), tr, uniq.size(), taken]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		## ★★钉死一个**绝对**周锚点, 不用"今天那一周" —— 否则下周一金标集体失效,
		##   而失效的理由跟确定性一点关系都没有(见 `_det_scenarios.PIN_WEEK_ANCHOR` 头注)。
		gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)

	var scs: Array = SC.all()
	_ok("★分母: 场景表读到 %d 个场景(与 verify_determinism_b 同一份表)" % scs.size(),
		scs.size() == 15, "%d 个" % scs.size())

	var golden: Dictionary = _load_golden()
	var missing: Array = []

	for sc in scs:
		var tag: String = str((sc as Dictionary)["tag"])
		OS.set_environment("TURTLE_SEED", str((sc as Dictionary)["seed"]))
		var r: Array = await _run(sc as Dictionary)
		OS.set_environment("TURTLE_SEED", "")
		var dig: String = str(r[0])
		_digests[tag] = dig
		## 分母: 这一局真的在推进(不然摘要是"静止画面"的摘要, 稳定得毫无意义)
		_ok("分母 · %s · 真的在推进(不同指纹 %d 个 > 1, 累计承伤 %.0f > 0)"
			% [tag, int(r[2]), float(r[3])], int(r[2]) > 1 and float(r[3]) > 0.0)
		if golden.has(tag):
			var want: String = str(golden[tag])
			var same: bool = (dig == want)
			var known: bool = KNOWN_DIVERGE.has(tag)
			var det := ""
			if not same:
				det = _first_diff(r[1] as Array, tag)
			if known:
				## ★★★台账里的那条: **不判红**, 但要把它**喊出来**。
				##   为什么不干脆删掉这个场景: 删了就再也不知道它有没有恶化,
				##   而「一个 ulp」和「整局分叉」是两回事。
				## ★方向是**只减不增**: 下面那条「台账里的必须还在分叉」守着 ——
				##   哪天它自己变一致了, 门禁会红, 逼人把它从台账里划掉。
				print("  [台账] %s · 已知跨平台分叉(实得 %s / 金标 %s) —— %s"
					% [tag, dig.substr(0, 16), want.substr(0, 16), KNOWN_DIVERGE[tag]])
				_ledger_seen.append(tag)
			else:
				_ok("★★★%s · 摘要 == 金标" % tag, same,
					("实得 %s / 金标 %s%s" % [dig.substr(0, 16), want.substr(0, 16),
						("  " + det) if det != "" else ""]) if not same else dig.substr(0, 16))
		else:
			missing.append(tag)
			print("  [MISS] %s · 金标里没有这一条 ⇒ 摘要 = %s" % [tag, dig])

	## ── ① 跨进程稳定: 同一台机器再跑一遍第 ① 个场景, 摘要必须一样 ──
	## ★★这一条是金标能不能成立的前提。它要是不成立, 下面所有"与金标比"都是噪声,
	##   而**噪声也会稳定地红**, 看着像"跨平台不一致"——两件事必须分得开。
	var sc0: Dictionary = scs[0]
	OS.set_environment("TURTLE_SEED", str(sc0["seed"]))
	var again: Array = await _run(sc0)
	OS.set_environment("TURTLE_SEED", "")
	_ok("★★① 同一台机器、同一进程内再跑一遍 ⇒ 摘要逐字相同(金标成立的前提)",
		str(again[0]) == str(_digests[str(sc0["tag"])]),
		"%s vs %s" % [str(again[0]).substr(0, 16), str(_digests[str(sc0["tag"])]).substr(0, 16)])

	## ── ①b ★★台账只减不增: 记在册的**必须还在分叉** ──
	## ★没有这一条, 台账就是个单向的免死金牌: 哪天它真的被修好了(或者场景被改成
	##   一个根本不走那段代码的形状), 没人会知道, 台账会永远挂着一条假债。
	for tg in KNOWN_DIVERGE.keys():
		_ok("①b ★★台账里的「%s」**仍在分叉**(不分叉了就把它从台账划掉)" % str(tg),
			_ledger_seen.has(str(tg)), "本轮台账命中: %s" % str(_ledger_seen))
	_ok("①b ★分母: 台账只有 %d 条(条数变多 = 有人拿它当垃圾桶)" % KNOWN_DIVERGE.size(),
		KNOWN_DIVERGE.size() <= 1, "%d 条" % KNOWN_DIVERGE.size())

	## ── ② 摘要真的在区分场景 ──
	var uniq_dig := {}
	for k in _digests:
		uniq_dig[str(_digests[k])] = true
	_ok("★★② %d 个场景出了 %d 个**不同**摘要(相同 = 摘要函数根本没读到战斗状态)"
		% [_digests.size(), uniq_dig.size()], uniq_dig.size() == _digests.size(),
		str(uniq_dig.size()))

	## ── ③ 换种子摘要必须变 ──
	var cp: Dictionary = {"tag": "反证", "frames": 240, "seed": "424242", "loadouts": {},
		"pairs": SC.counter_proof_pairs()}
	OS.set_environment("TURTLE_SEED", "424242")
	var g1: Array = await _run(cp)
	OS.set_environment("TURTLE_SEED", "77")
	var g2: Array = await _run(cp)
	OS.set_environment("TURTLE_SEED", "")
	_ok("★★③ 反证 · 换种子(424242→77) ⇒ 摘要必须不同(相同 = 结果不吃 _battle_rng)",
		str(g1[0]) != str(g2[0]),
		"%s vs %s" % [str(g1[0]).substr(0, 16), str(g2[0]).substr(0, 16)])

	## ── 金标缺项: 打出来让人能一次贴进去, 但**判 FAIL** ──
	if not missing.is_empty():
		print("")
		print("  ★金标缺 %d 条。把下面整段存成 %s:" % [missing.size(), GOLDEN_PATH])
		print(JSON.stringify(_digests, "  "))
		_ok("★金标覆盖了全部 %d 个场景(缺 %d 条 —— 缺一条就是那一条没人看着)"
			% [scs.size(), missing.size()], false, str(missing))

	print("")
	if _fail == 0:
		print("ALL PASS — 跨平台确定性 (%d/%d)" % [_n, _n])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _n - _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _load_golden() -> Dictionary:
	if not FileAccess.file_exists(GOLDEN_PATH):
		print("  [MISS] 金标文件不存在: %s" % GOLDEN_PATH)
		return {}
	var f := FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt: String = f.get_as_text()
	f.close()
	_check_golden_eol(txt)
	return _parse_golden(txt)


## 金标文本 → {tag: 摘要}。★唯一的解析口, 下面那条行尾判据也走它(判的就是门禁真用的那个解析)。
func _parse_golden(txt: String) -> Dictionary:
	var p = JSON.parse_string(txt)
	return p if p is Dictionary else {}


## ★★金标比对**对行尾必须不敏感**(2026-10-04 补·`docs/plans/20261002-文案落点BBCode普查.md` §6 点名)。
##   本仓 `core.autocrlf=true` ⇒ 新 clone / 新 worktree 检出来是 CRLF, CI(Linux) 与 Godot 写的是 LF。
##   `verify_elite_anim` 就栽在这上面: 按行切、行尾多一个 CR ⇒ 新 worktree 必红、主仓绿。
##   这一份今天走 JSON 解析(空白不敏感), 所以**现在**不瞎 —— 这条判据把「现在」钉住:
##   哪天有人把解析换成按行切(比如为了逐行报 diff), CRLF 那一侧会读出带 CR 的键/值, 当场红。
##   ★不靠"我看过 JSON 不在乎空白": 同一份文本**强制**造出 LF 版与 CRLF 版, 过同一个解析口, 结果必须逐键相同。
func _check_golden_eol(txt: String) -> void:
	var lf: String = txt.replace("\r\n", "\n")
	var crlf: String = lf.replace("\n", "\r\n")
	var a: Dictionary = _parse_golden(lf)
	var b: Dictionary = _parse_golden(crlf)
	var same: bool = a.size() == b.size()
	var cr_in := 0
	for k in b:
		if str(k).contains("\r") or str(b[k]).contains("\r"): cr_in += 1
		if not a.has(k) or str(a[k]) != str(b[k]): same = false
	_ok("★分母: 金标 LF 版解析出 %d 条(0 条 = 下一条恒真)" % a.size(), a.size() >= 13, "%d 条" % a.size())
	_ok("★金标比对与行尾无关: LF / CRLF 两种行尾过同一个解析口 ⇒ 逐键相同、键值里 0 个 CR(实测 %d 个)"
		% cr_in, same and cr_in == 0, "LF %d 条 / CRLF %d 条 —— 解析对行尾敏感 ⇒ 新 worktree(CRLF) 与 CI(LF) 会读出两份不同的金标" % [a.size(), b.size()])


## 摘要对不上时, 报**第一个分叉步**与那一步里不同的段 —— 只说"摘要不同"等于没说。
## ★这一条是本门禁真正的价值: 它要能告诉我「是哪一只单位的哪个字段在第几步开始飘」,
##   否则跨平台不一致这件事永远只是个结论, 没法修。
## ⚠ 需要金标那一侧也留着逐步指纹才能逐步比。金标只存摘要(存全量太大) ⇒
##   这里只能报「本机这一侧第一步在哪儿开始与自己上一步不同」这类线索, 帮不上逐步对比。
##   ⇒ 真要逐步对比时: 在两个平台上各跑一次, 各自把 `TURTLE_DET_DUMP=1` 的逐步指纹
##     写到文件里, 再离线 diff。下面这行就是那个开关。
func _first_diff(tr: Array, tag: String) -> String:
	if OS.get_environment("TURTLE_DET_DUMP") == "":
		return "(要逐步对比: TURTLE_DET_DUMP=1 再跑, 会把逐步指纹写到 user://det_dump_*.txt)"
	var safe := tag
	for ch in ["/", "\\", ":", " ", "(", ")", "★", "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨"]:
		safe = safe.replace(ch, "_")
	var path := "user://det_dump_%s.txt" % safe
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "(写不出 dump: %s)" % path
	for i in range(tr.size()):
		f.store_line("%d\t%s" % [i, str(tr[i])])
	f.close()
	return "逐步指纹已写到 %s(%d 步)" % [path, tr.size()]
