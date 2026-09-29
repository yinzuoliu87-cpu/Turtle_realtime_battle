extends Node
## _probe_autopilot_nochange.gd — 自动驾驶**不许改变战斗结果或经济**。
##
## 跑法(≈20 秒):
##   APPDATA=/c/tmp/ap_nc TURTLE_BACKEND=" " TURTLE_SUPABASE=" " \
##   <godot> --headless --audio-driver Dummy --path . \
##   res://tests/_probe_autopilot_nochange.tscn --quit-after 6000
##
## ★为什么是 `_probe_` 不是 `verify_`: 要跑**三场**对局 ≈2000 帧, 而
## `run-tests.sh` 的默认帧预算是 **500 帧**, 登记表 `frames_for()` 本轮不由我改。
## 要收进门禁: 改名 `verify_autopilot_nochange.gd/.tscn` + 加一行
## `verify_autopilot_nochange) echo 6000 ;;`。**只改名不登记就会半路被掐断。**
##
## ══════════════════════════════════════════════════════════════════════
##  判据
## ══════════════════════════════════════════════════════════════════════
## 同一颗种子、同一支队、同一个对手快照, 跑三遍:
##   A ) `DL_AUTOFIGHT`  —— 进摆位屏**立刻**开打(老路子, 连按钮都不建)
##   A2) `DL_AUTOFIGHT`  —— 同上, 再跑一遍 ⇒ **本进程自己的噪声底**
##   B ) `SIM_AUTOPILOT` —— 停 `DWELL_PLACE` 帧, 然后**按那颗「开打」按钮**
## 扣掉 A↔A2 的噪声底之后, A↔B 必须**逐字相同**。
##
## ★为什么要噪声底而不是直接判「0 分叉」: 实测同种子跑两遍本来就不是逐字相同 ——
##   训龟大师(`__trainer__`)开场坐标每局差 ~0.2px, 它扔石头的落点/时序跟着变,
##   三只龟的血量各差 1 点。那是本仓**一条一直存在的确定性漏洞**, 与自动驾驶无关。
##   ⇒ 照 CLAUDE.md 那条「改成耗时 ÷ 同进程参照负载」的路子: 先量底, 再比增量。
##   而且哪天有人把它修掉, 噪声底自己缩小, 这条判据**自动变严**, 不用回来改数字。
##   (本探针另外开 `NO_TRAINER` 把它隔开 —— 项目自己给"对照实验要干净环境"留的开关,
##    `battle_spawn.gd:544`。实测开了之后噪声底是 **0**。)
##
## ★指纹**按 `battle._t` 对齐**, 不按 engine 帧号 —— 两遍按下按钮的时刻差 100 帧,
##   而 `_t` 在 `place` 阶段根本不涨(`_fight_on` 恒假, `RealtimeBattle3DScene.gd:2219`),
##   所以按 `_t` 对齐才是同一步比同一步。
## ★指纹函数**直接复用** `verify_determinism_b._fp`, 不另抄一份
##   (memory `fb-hand-rolled-copies-drift`: 手抄的副本必然落后)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const DetB := preload("res://tests/verify_determinism_b.gd")   # ★只借它的 _fp 指纹函数

const EQ_TEAM := ["basic", "stone", "bamboo"]
const EQ_STEPS := 600          # 从开打起采 600 步 sim(= 10 游戏秒)
const EQ_WAIT_CAP := 2500      # 等"开打"的帧上限(含 DWELL_PLACE + 建场)
const SEED_TXT := "20260929"

var _fail := 0
var _n := 0
var _fpr = DetB.new()          # 不 add_child ⇒ 它的 _ready 不跑, 只当指纹函数用


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true     # 绝不写玩家存档
	GameState.season_leaders = []
	GameState.season_total_battles = 0
	GameState.hearts = 8
	await _phase_no_battle_change()
	if _fail == 0:
		print("ALL PASS (%d/%d)" % [_n, _n])
	else:
		print("FAILED %d/%d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _phase_no_battle_change() -> void:
	print("── 停 %d 帧再按「开打」 vs 立刻开打: 逐步指纹必须逐字相同 ──" % SimAutopilot.DWELL_PLACE)
	var was_no_present: bool = bool(DualLaneFlow.NO_PRESENT)
	DualLaneFlow.NO_PRESENT = true   # 跳开场 10 秒纯演出(它自己的头注: 对胜负零影响)
	OS.set_environment("TURTLE_SEED", SEED_TXT)
	OS.set_environment("NO_TRAINER", "1")   # 见文件头: 隔开训龟大师那条既有的确定性漏洞

	var econ0 := _econ()
	var a: Array = await _one_run("autofight")
	var a2: Array = await _one_run("autofight")
	var b: Array = await _one_run("autopilot")
	var econ1 := _econ()

	OS.unset_environment("TURTLE_SEED")
	OS.unset_environment("NO_TRAINER")
	OS.unset_environment("DL_AUTOFIGHT")
	OS.unset_environment(SimAutopilot.ENV)
	DualLaneFlow.NO_PRESENT = was_no_present

	var fa: Dictionary = a[0]
	var fa2: Dictionary = a2[0]
	var fb: Dictionary = b[0]
	_ok("★分母: 三遍都真的开打了 + 都在 det 模式",
		bool(a[1]) and bool(a2[1]) and bool(b[1]) and bool(a[4]) and bool(b[4]),
		"A=%s(%d帧) A2=%s(%d帧) B=%s(%d帧) det=%s/%s" % [
			str(a[1]), int(a[2]), str(a2[1]), int(a2[2]), str(b[1]), int(b[2]),
			str(a[4]), str(b[4])])
	_ok("★分母: 「立刻开打」那两遍**没有**按过按钮(走的是 DL_AUTOFIGHT 老路)",
		int(a[3]) == 0 and int(a2[3]) == 0, "press_go=%d/%d" % [int(a[3]), int(a2[3])])
	_ok("★分母: 「自动驾驶」那遍**真的按了**那颗按钮, 而且晚了整整 %d 帧" % SimAutopilot.DWELL_PLACE,
		int(b[3]) >= 1 and int(b[2]) > int(a[2]), "press_go=%d  A 等 %d 帧 / B 等 %d 帧"
			% [int(b[3]), int(a[2]), int(b[2])])

	## ── 噪声底: 同模式两遍之间会分叉的段号 ──
	var base: Array = _diff(fa, fa2, {})
	var ign: Dictionary = base[1]
	var segs_n: int = int(base[3])
	print("    [噪声底] 同模式两遍: 可比 %d 步 · 分叉 %d 次 · 分叉段 %s" % [
		int(base[0]), int(base[2]), str(ign.keys())])
	for k in ign.keys():
		print("    [噪声底] 段%s 例: %s" % [str(k), str(ign[k])])
	_ok("★分母: 噪声底只占 %d / %d 段 —— 占满了下面那条就没东西可比了" % [ign.size(), segs_n],
		segs_n >= 8 and ign.size() <= 2, "段数=%d 噪声段=%d" % [segs_n, ign.size()])
	_ok("★分母: 同模式两遍可比步数 %d(0 步 = 空检查)" % int(base[0]),
		int(base[0]) >= EQ_STEPS / 2, "%d 步" % int(base[0]))

	## ── 正题: 扣掉噪声底之后, 自动驾驶那遍必须逐字相同 ──
	var t: Array = _diff(fa, fb, ign)
	_ok("★分母: 扣掉噪声底后还有 %d 步 × %d 段可比" % [int(t[0]), segs_n - ign.size()],
		int(t[0]) >= EQ_STEPS / 2 and (segs_n - ign.size()) >= 8,
		"%d 步 × %d 段" % [int(t[0]), segs_n - ign.size()])
	var uniq := {}
	for k in fa.keys():
		if fb.has(k):
			uniq[str(fa[k])] = true
	_ok("★分母: 指纹随步变化(%d 种) —— 不变就说明根本没在推进" % uniq.size(),
		uniq.size() > 1, "%d 种" % uniq.size())
	_ok("★★扣掉噪声底后逐步指纹逐字相同(分叉 %d 次)" % int(t[2]), int(t[2]) == 0,
		"分叉段 %s" % str((t[1] as Dictionary).keys()))
	for k in (t[1] as Dictionary).keys():
		print("    [探针] 新分叉 段%s: %s" % [str(k), str((t[1] as Dictionary)[k])])
	## 经济: 三遍跑完, 币/命/等级/背包/装备 逐字不变。
	_ok("★经济逐字未动: %s" % econ0, econ0 == econ1, "跑完=%s" % econ1)
	## `DetB.new()` 是个 Node(不是 RefCounted) ⇒ 不显式 free 会在退出时报实例泄漏。
	if is_instance_valid(_fpr):
		_fpr.free()


## 两份 {_t 串 → 指纹} 逐步逐段比。ignore = 不比的段号。
## 返回 [可比步数, {分叉段号 → 首个例子}, 分叉次数, 每步段数]
func _diff(fa: Dictionary, fb: Dictionary, ignore: Dictionary) -> Array:
	var steps := 0
	var segs := {}
	var bad := 0
	var seg_n := 0
	for k in fa.keys():
		if not fb.has(k):
			continue
		steps += 1
		var sa: PackedStringArray = str(fa[k]).split("|")
		var sb: PackedStringArray = str(fb[k]).split("|")
		seg_n = maxi(seg_n, maxi(sa.size(), sb.size()))
		for i in range(maxi(sa.size(), sb.size())):
			if ignore.has(i):
				continue
			var xa: String = str(sa[i]) if i < sa.size() else "<缺>"
			var xb: String = str(sb[i]) if i < sb.size() else "<缺>"
			if xa != xb:
				bad += 1
				if not segs.has(i):
					segs[i] = "%s  ⇄  %s" % [xa, xb]
	return [steps, segs, bad, seg_n]


## 跑一遍双路对局, 返回 [{_t 串 → 指纹}, 开打了吗, 等了几帧, 按了几次开打, det?]
## ★★`OS.set_environment(k, "")` **不等于没这个变量** —— `OS.has_environment(k)`
##   对空串照样返回 true, 而 `DL_AUTOFIGHT` 判的就是 `has_environment`。
##   第一版写成 set("") ⇒ 两遍都走 DL_AUTOFIGHT、自动驾驶那遍 press_go=0,
##   分母断言当场接住了。要清就得 `unset_environment`。
func _one_run(mode: String) -> Array:
	if mode == "autofight":
		OS.set_environment("DL_AUTOFIGHT", "1")
	else:
		OS.unset_environment("DL_AUTOFIGHT")
	if mode == "autopilot":
		OS.set_environment(SimAutopilot.ENV, "1")
	else:
		OS.unset_environment(SimAutopilot.ENV)
	SimAutopilot.reset_ledger_for_test()
	GameState.reset_dual_lane()
	GameState.dual_active = true
	GameState.season_leaders = EQ_TEAM.duplicate()
	GameState.dual_ghost = _fixed_ghost()
	GameState.get_dual_lineup()

	var s = RB.new()
	add_child(s)
	var w := 0
	while w < EQ_WAIT_CAP and float(s._t) <= 0.0:
		await get_tree().process_frame
		w += 1
	var started: bool = float(s._t) > 0.0
	var out := {}
	if started:
		for _i in range(EQ_STEPS):
			out["%.5f" % float(s._t)] = str(_fpr._fp(s))
			await get_tree().process_frame
	var pressed := int(SimAutopilot.press_go)
	## ★判完先宽限几帧再释放 —— 在飞的演出会在 await 之后撞上已释放的 battle
	##   (与 tests/_autoplay.gd 同一条经验)。
	for _g in range(20):
		await get_tree().process_frame
	var det: bool = bool(s._deterministic)
	s.queue_free()
	for _i in range(4):
		await get_tree().process_frame
	return [out, started, w, pressed, det]


## 固定对手快照(照 TutorialDirector.make_weak_ghost 的形状)—— 不走 Backend, 零随机。
func _fixed_ghost() -> Dictionary:
	return {
		"schema_ver": 1,
		"ghost_id": "autopilot_fixed_foe",
		"is_bot": true,
		"bracket": 0,
		"profile": {"name": "固定木桩", "avatar": "basic", "id": "APT"},
		"leaders": ["basic", "stone"],
		"lane_assign": {"top": ["basic"], "bottom": ["stone"]},
		"minions": {"top": [], "bottom": []},
		"loadouts": {},
		"equipped": {},
		"pet_levels": {"basic": 1, "stone": 1},
		"season_total_battles": 0,
		"season_eggs_killed": 0,
	}


func _econ() -> String:
	return "币=%d 命=%d 等级=%d xp=%d 胜=%d 场次=%d 背包=%d 装=%d" % [
		int(GameState.meta_deepsea_coins), int(GameState.hearts),
		int(GameState.season_level), int(GameState.season_xp), int(GameState.season_wins),
		int(GameState.season_total_battles),
		(GameState.persistent_bench as Array).size(),
		(GameState.persistent_equipped as Dictionary).size()]
