extends Node
## verify_matchmaking_phase.gd — 匹配 × 相位：把「现在」钉死，七天全扫
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁为什么存在
## ══════════════════════════════════════════════════════════════════════
## 2026-09-27 查实：匹配那一侧**一条相位断言都没有**。不是漏写，是写不了 ——
## `scripts/` + `autoload/` 共 23 处就地 `Time.get_unix_time_from_system()`（16 处喂赛程判定），
## 其中两处**就在匹配路径上**（`MatchmakingScene._ready()` 选走哪条匹配、
## `Backend.gauntlet_pool_find()` 判快照新鲜度）。钉不住「现在」，
## 跟相位有关的判据就只有两种写法，两种都不能进棘轮：
##   ① 不写；② 写成"今天是星期几"的形状 —— 本地绿 / CI 偶发红。
## 本仓「判据挂在星期几上」已栽过五次（v0.19.446 一轮修了四条）。
##
## ⇒ 于是在 `phase2_config` 开了一条**纯静态时间缝** `now_override_ts` / `now_utc()`
##   （样式照抄 `Backend.pool_override` / `Supabase._transport_for_test` /
##     `MainMenuScene.clock_override_ts`：默认值就是"关"，static ⇒ 用完必须还原）。
##   本文件就是那条缝的第一个消费者，也是它的门禁。
##
## ══════════════════════════════════════════════════════════════════════
##  判据的形状：**每条都配一条分母**
## ══════════════════════════════════════════════════════════════════════
## 「对星期几不敏感」这句话有两种假法，都见过：
##   · 假法一：判据其实一次都没跑到（钉住的时刻压根没换过相位）
##     ⇒ 所以 ② 整组是分母：七个钉住时刻必须覆盖全部 4 个相位、同属一周。
##   · 假法二：被测函数对**任何**输入都返回同一个东西（"永远返回第一个"也能绿）
##     ⇒ 所以每条"七天答案相同"的旁边都摆一条"换个输入答案必须不同"。
##
## ★④/⑤ 两组是**源码判据**：行为判据量不到"将来有人往尺子里塞时间"这件事 ——
##   因为塞进去的那行会读**真实系统时钟**，我的缝钉不住它，于是行为照旧全绿。
##   ⇒ 那条线只能在源码层守。它的分母不是合成字符串，而是**同一台探测器在
##     `gauntlet_pool_find` 里确实照出了 `Time.get_`**（那一行真实存在）。
##
## 跑法:
##   APPDATA=/c/tmp/ad_mmk TURTLE_BACKEND=" " TURTLE_SUPABASE=" " \
##   <godot> --headless --audio-driver Dummy --path . \
##     res://tests/verify_matchmaking_phase.tscn --quit-after 900

const BE := preload("res://scripts/net/backend.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

## 2026-09-14 周一 00:00:00 UTC —— 一个干净的周锚点（`verify_gauntlet_match` 用的同一个）。
const MON0 := 1789344000
const NOON := 12 * 3600

## 被测源码。★路径写死是故意的：文件搬走了这条门禁必须红（它量的就是那几个函数体）。
const SRC_BACKEND := "res://scripts/net/backend.gd"
const SRC_MMK := "res://scripts/scenes/MatchmakingScene.gd"

## 选靶链上**一个都不许出现**的符号。出现任何一个，匹配的尺子就跟"现在几点"绑上了。
const TIME_TOKENS := ["Time.get_", "phase_at_utc", "phase_of_weekday",
	"iso_weekday_utc", "now_utc(", "PHASE_GAUNTLET", "PHASE_RANKED", "week_phase"]

var _n := 0
var _fail := 0


func _chk(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])


## 造一份【别人的】按场次匹配用的快照。
## ★必须带 origin=remote，否则 `_is_self_ghost` 会把它当自己跳掉 ——
##   那样"没选中"就成了别的原因造成的，判据变恒真式。
func _ghost(id: String, battles: int) -> Dictionary:
	return {
		"schema_ver": BE.SCHEMA_VER,
		"ghost_id": id,
		"is_bot": false,
		"origin": BE.ORIGIN_REMOTE,
		"profile": {"name": "对手%s" % id},
		"leaders": ["basic", "ninja", "stone"],
		"season_total_battles": battles,
	}


## 造一份闯关赛（按战绩标签）用的快照。age_sec = 上传距今多久。
func _gl(id: String, gw: int, gl: int, age_sec: int) -> Dictionary:
	return {
		"ghost_id": id, "name": "假人" + id, "avatar": "basic",
		"origin": BE.ORIGIN_REMOTE,
		"gl_w": gw, "gl_l": gl,
		"gl_ts": int(Time.get_unix_time_from_system()) - age_sec,
	}


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload GameState")
		get_tree().quit(1)
		return
	gs.test_mode = true

	print("=== 匹配 × 相位: 时间缝 + 七天全扫 ===")
	_t_seam()
	_t_week_coverage()
	_t_battles_ruler()
	_t_source_ruler()
	_t_dispatch()
	_t_gauntlet_label()
	_t_lockout_sweep()
	_t_restored()

	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS (%d/%d) — 匹配 × 相位" % [_n, _n])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _n - _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ═════════════════════════════════════════════════════════════════
# ① 缝本身: 默认透明 / 钉得住 / 还原得回去
# ═════════════════════════════════════════════════════════════════
func _t_seam() -> void:
	print("── ① 时间缝 ──")
	_chk("① ★分母: 缝默认是关的(now_override_ts == 0) —— 否则下面全是在量别人留下的状态",
		P2.now_override_ts == 0, "now_override_ts=%d" % P2.now_override_ts)
	var sys0: int = int(Time.get_unix_time_from_system())
	_chk("① 关着时 now_utc() 就是系统时钟(玩家路径一字不动)",
		absi(P2.now_utc() - sys0) <= 1, "now_utc=%d system=%d" % [P2.now_utc(), sys0])
	_chk("① ★分母: 系统时钟是个像样的值(> 2020 年), 不是 0",
		sys0 > 1577836800, "system=%d" % sys0)

	## 钉住七个互不相同的时刻, 逐值相等
	var exact := 0
	var differ := 0
	for d in range(7):
		var pin: int = MON0 + d * 86400 + NOON
		P2.now_override_ts = pin
		if P2.now_utc() == pin:
			exact += 1
		if P2.now_utc() != int(Time.get_unix_time_from_system()):
			differ += 1
	_chk("① 钉住 7 个时刻 ⇒ now_utc() 逐值相等", exact == 7, "%d/7" % exact)
	_chk("① ★分母: 7 个钉住值都**不等于**真实系统时钟(证明上一条不是「碰巧就是现在」)",
		differ == 7, "%d/7" % differ)

	P2.now_override_ts = 0
	_chk("① 还原成 0 ⇒ 又回到系统时钟",
		absi(P2.now_utc() - int(Time.get_unix_time_from_system())) <= 1)
	## 只认 > 0: unix 0 / 负数不是任何人想钉的时刻, 而"0 = 关"是三个先例的口径
	P2.now_override_ts = -1
	_chk("① 负数一律当「关」(不许把 1970 年当成钉住的时刻)",
		absi(P2.now_utc() - int(Time.get_unix_time_from_system())) <= 1,
		"now_utc=%d" % P2.now_utc())
	P2.now_override_ts = 0


# ═════════════════════════════════════════════════════════════════
# ② 七天覆盖(整组都是分母): 钉住的那七个时刻真的走遍了四个相位、还同属一周
# ═════════════════════════════════════════════════════════════════
func _t_week_coverage() -> void:
	print("── ② 七天覆盖(分母组) ──")
	var by_phase := {}
	var wds := {}
	var anchors := {}
	for d in range(7):
		P2.now_override_ts = MON0 + d * 86400 + NOON
		var n: int = P2.now_utc()
		var ph: String = P2.phase_at_utc(n)
		by_phase[ph] = int(by_phase.get(ph, 0)) + 1
		wds[P2.iso_weekday_utc(n)] = true
		anchors[P2.week_anchor_utc(n)] = true
	P2.now_override_ts = 0
	print("    相位分布: %s" % str(by_phase))
	_chk("② ★分母: 七个钉住时刻覆盖全部 4 个相位(rest / ranked / gauntlet / finals)",
		by_phase.size() == 4
		and int(by_phase.get(P2.PHASE_REST, 0)) == 1
		and int(by_phase.get(P2.PHASE_RANKED, 0)) == 4
		and int(by_phase.get(P2.PHASE_GAUNTLET, 0)) == 1
		and int(by_phase.get(P2.PHASE_FINALS, 0)) == 1, str(by_phase))
	_chk("② ★分母: 七个时刻的 ISO 星期几是 1..7 各一次(没有两天撞在一起)",
		wds.size() == 7, str(wds.keys()))
	_chk("② ★分母: 七天算出来的周锚点是**同一个**(是同一周, 不是滑出去了)",
		anchors.size() == 1 and anchors.has(MON0), str(anchors.keys()))


# ═════════════════════════════════════════════════════════════════
# ③ 积分赛匹配的尺子: 走真入口 `Backend.find_opponent()`, 七天答案必须一样
# ═════════════════════════════════════════════════════════════════
func _t_battles_ruler() -> void:
	print("── ③ 按场次匹配: 七天答案完全相同(真入口) ──")
	## 池子形状由**产品自己**决定 —— 一律走 `pool_add`, 不手写
	## (memory fb-gate-subject-never-constructed: 手写的扁平池全仓没人生产)。
	var pool := {}
	for i in range(8):
		BE.pool_add(pool, _ghost("p_%d" % i, 12))
	_chk("③ ★分母: 注入池是产品自己 pool_add 出来的形状(顶层键就是 POOL_KEY)",
		pool.has(BE.POOL_KEY) and pool.size() == 1, str(pool.keys()))
	var bucket: Array = (pool.get(BE.POOL_KEY, {}) as Dictionary).get("12", []) as Array
	_chk("③ ★分母: 场次 12 那格 8 条(不是空池 ⇒ 下面「找到人」不是恒假)",
		bucket.size() == 8, "%d 条" % bucket.size())
	_chk("③ ★分母: 只有 12 这一格(没有邻格能顶上 ⇒ 下面 999 那条不是「抽到隔壁」)",
		(pool.get(BE.POOL_KEY, {}) as Dictionary).size() == 1,
		str((pool.get(BE.POOL_KEY, {}) as Dictionary).keys()))

	BE.pool_override = pool
	var ids := {}
	var right := 0
	var wrong: Array = []
	var bots := 0
	var bot_report := 0
	var bot_ids := {}
	for d in range(7):
		P2.now_override_ts = MON0 + d * 86400 + NOON
		var rng := RandomNumberGenerator.new()
		rng.seed = 424242
		var g: Dictionary = BE.find_opponent(12, [], rng)
		ids[str(g.get("ghost_id", "?"))] = true
		if int(g.get("season_total_battles", -1)) == 12 and not bool(g.get("is_bot", false)):
			right += 1
		else:
			wrong.append("%s(%d场,bot=%s)" % [str(g.get("ghost_id", "?")),
				int(g.get("season_total_battles", -1)), str(g.get("is_bot", false))])
		## 另一侧: 池里压根没有 999 那格 ⇒ 只能是 bot
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 424242
		var g2: Dictionary = BE.find_opponent(999, [], rng2)
		bot_ids[str(g2.get("ghost_id", "?"))] = true
		if bool(g2.get("is_bot", false)):
			bots += 1
		if int(g2.get("season_total_battles", -1)) == 999:
			bot_report += 1
	P2.now_override_ts = 0
	BE.pool_override = {}

	_chk("③ ★★★七天 × 同场次 12 ⇒ 7/7 都拿到真快照且对手场次 == 12, 0 次例外",
		right == 7 and wrong.is_empty(), "对 %d/7; 例外 %s" % [right, str(wrong)])
	_chk("③ ★★七天抽到的是**同一个** ghost_id(答案与今天星期几无关)",
		ids.size() == 1, str(ids.keys()))
	_chk("③ ★★分母(另一侧): 同场次一个人都没有的那一格 ⇒ 7/7 都是机器人",
		bots == 7, "bot %d/7" % bots)
	_chk("③ ★分母: 机器人如实报我的场次 999(7/7)", bot_report == 7, "%d/7" % bot_report)
	_chk("③ ★★分母: 真快照与机器人确实是**两个不同的答案** —— 否则上面两条可以同时「全绿」而什么都没测",
		ids.keys() != bot_ids.keys(), "真快照 %s / 机器人 %s" % [str(ids.keys()), str(bot_ids.keys())])
	_chk("③ ★★分母: 用完把 pool_override 清空了(它是 static, 漏清会污染同进程后面的用例)",
		BE.pool_override.is_empty())


# ═════════════════════════════════════════════════════════════════
# ④ 源码判据: 按场次那条选靶链上, **一个时间/相位符号都不许有**
# ═════════════════════════════════════════════════════════════════
## ★为什么行为判据不够: 将来有人往 `find_opponent` 里塞一行
##   `Time.get_unix_time_from_system()`，读的是**真实系统时钟** ——
##   我的缝钉不住它，③ 那组照旧七天全绿，而 bug 已经进去了。
##   （同族 memory: fb-gate-must-measure-requirement-not-my-hook）
## ★这条判据的分母**不是合成字符串**: 同一台探测器在 `gauntlet_pool_find`
##   里必须照出 `Time.get_`（那一行真实存在，backend.gd 里就有）。
##   照不出来 = 探测器读错了文件 / 切错了函数体 ⇒ 上面两条恒绿。
func _read_src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	return txt


## 取一个顶格函数的**函数体**(去掉空行与整行注释)。到下一个顶格 func 为止。
func _func_body(src: String, sig: String) -> Array:
	var out: Array = []
	var inside := false
	for raw in src.split("\n"):
		var s: String = str(raw).replace("\r", "")
		if not inside:
			if s.begins_with(sig):
				inside = true
			continue
		if s.begins_with("func ") or s.begins_with("static func "):
			break
		var t := s.strip_edges()
		if t == "" or t.begins_with("#"):
			continue
		out.append(t)
	return out


func _time_hits(body: Array) -> Array:
	var hits: Array = []
	for line in body:
		for tok in TIME_TOKENS:
			if str(line).find(str(tok)) >= 0:
				hits.append("%s ⇐ %s" % [str(tok), str(line).substr(0, 70)])
	return hits


func _t_source_ruler() -> void:
	print("── ④ 源码: 按场次选靶链上不许出现时间/相位 ──")
	var src := _read_src(SRC_BACKEND)
	_chk("④ ★分母: 读到了 backend.gd 源码", src.length() > 5000, "%d 字节" % src.length())

	var b_find := _func_body(src, "static func find_opponent(")
	var b_pick := _func_body(src, "static func pool_find_battles(")
	var b_gaunt := _func_body(src, "static func gauntlet_pool_find(")
	_chk("④ ★分母: 三个函数体都切出来了且都不是空的(切错了函数名 = 判据恒绿)",
		b_find.size() > 5 and b_pick.size() > 5 and b_gaunt.size() > 5,
		"find_opponent %d 行 / pool_find_battles %d 行 / gauntlet_pool_find %d 行"
		% [b_find.size(), b_pick.size(), b_gaunt.size()])

	## ★★这一条就是探测器的分母: 它在真源码里**必须**照得出 Time.get_
	var gaunt_hits := _time_hits(b_gaunt)
	_chk("④ ★★★分母: 同一台探测器在 gauntlet_pool_find 里**确实**照出时间符号(证明它会红, 不是空检查)",
		gaunt_hits.size() >= 1, "命中 %d 条: %s" % [gaunt_hits.size(), str(gaunt_hits)])

	var find_hits := _time_hits(b_find)
	var pick_hits := _time_hits(b_pick)
	_chk("④ ★★★find_opponent 的函数体里一个时间/相位符号都没有(尺子只认场次这一个入参)",
		find_hits.is_empty(), "命中 %d 条: %s" % [find_hits.size(), str(find_hits)])
	_chk("④ ★★★pool_find_battles 同上",
		pick_hits.is_empty(), "命中 %d 条: %s" % [pick_hits.size(), str(pick_hits)])


# ═════════════════════════════════════════════════════════════════
# ⑤ 分流: 周六走闯关赛匹配这件事, 必须由相位纯函数决定
# ═════════════════════════════════════════════════════════════════
func _t_dispatch() -> void:
	print("── ⑤ 分流: 七天里恰好一天走闯关赛匹配 ──")
	## 这里**照 MatchmakingScene 的原式子组合产品自己的两个纯函数**,
	## 不在测试里另写一份"== 周六"(那就是同一判据存两份, memory fb-hand-rolled-copies-drift)。
	var gaunt_days: Array = []
	for d in range(7):
		P2.now_override_ts = MON0 + d * 86400 + NOON
		var n: int = P2.now_utc()
		if P2.phase_at_utc(n) == P2.PHASE_GAUNTLET and P2.phase_mode_live(P2.PHASE_GAUNTLET):
			gaunt_days.append(P2.iso_weekday_utc(n))
	P2.now_override_ts = 0
	_chk("⑤ ★七天里恰好 1 天走闯关赛匹配, 其余 6 天走按场次匹配",
		gaunt_days.size() == 1, "走闯关赛的星期几: %s" % str(gaunt_days))
	_chk("⑤ ★分母: 那一天就是 ISO 周六(wd=6)",
		gaunt_days.size() == 1 and int(gaunt_days[0]) == 6, str(gaunt_days))

	## 源码那半: 分流的判据必须是共用的相位纯函数, 不许手写星期几或字符串字面量
	var msrc := _read_src(SRC_MMK)
	var code: Array = []
	for raw in msrc.split("\n"):
		var t := str(raw).replace("\r", "").strip_edges()
		if t != "" and not t.begins_with("#"):
			code.append(t)
	_chk("⑤ ★分母: 读到了 MatchmakingScene.gd 的代码行", code.size() > 100, "%d 行" % code.size())
	var has_phase := 0
	var has_live := 0
	var has_two := 0
	var bad_literal: Array = []
	for line in code:
		var s := str(line)
		if s.find("phase_at_utc(") >= 0:
			has_phase += 1
		if s.find("phase_mode_live(") >= 0:
			has_live += 1
		if s.find("find_gauntlet_opponent(") >= 0 or s.find("find_opponent(") >= 0:
			has_two += 1
		if s.find("iso_weekday_utc") >= 0 or s.find("\"gauntlet\"") >= 0:
			bad_literal.append(s.substr(0, 70))
	_chk("⑤ 分流走的是共用判据 phase_at_utc() + phase_mode_live()",
		has_phase >= 1 and has_live >= 1, "phase_at_utc %d 处 / phase_mode_live %d 处"
		% [has_phase, has_live])
	_chk("⑤ ★分母: 两条匹配入口都在这一屏里被调(证明这里就是分流点)",
		has_two >= 2, "匹配入口调用 %d 处" % has_two)
	_chk("⑤ ★不许手写星期几或相位字符串字面量(必须走 PHASE_* 常量)",
		bad_literal.is_empty(), str(bad_literal))


# ═════════════════════════════════════════════════════════════════
# ⑥ 闯关赛标签尺子: 七天里都**永不跨标签**
# ═════════════════════════════════════════════════════════════════
func _t_gauntlet_label() -> void:
	print("── ⑥ 闯关赛按标签选靶: 七天都永不跨标签 ──")
	var pool := {}
	for i in range(4):
		BE.pool_add(pool, _gl("g_same%d" % i, 3, 1, 60))
	BE.pool_add(pool, _gl("g_other_l", 3, 2, 60))
	BE.pool_add(pool, _gl("g_other_w", 2, 1, 60))
	var same := 0
	var other := 0
	for b in (pool.get(BE.POOL_KEY, {}) as Dictionary).keys():
		for g in ((pool[BE.POOL_KEY] as Dictionary)[b] as Array):
			if int((g as Dictionary).get("gl_w", -1)) == 3 and int((g as Dictionary).get("gl_l", -1)) == 1:
				same += 1
			else:
				other += 1
	_chk("⑥ ★分母: 池里同标签(3-1) 4 份 + 别的标签 2 份", same == 4 and other == 2,
		"同标签 %d / 其它 %d" % [same, other])

	var picked := {}
	var cross := 0
	var nulls := 0
	var draws := 0
	for d in range(7):
		P2.now_override_ts = MON0 + d * 86400 + NOON
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for _i in range(20):
			draws += 1
			var g = BE.gauntlet_pool_find(pool, 3, 1, [], rng)
			if g == null:
				nulls += 1
				continue
			var gid := str(g.get("ghost_id", "?"))
			picked[gid] = true
			if not gid.begins_with("g_same"):
				cross += 1
	P2.now_override_ts = 0
	_chk("⑥ ★分母: 一共抽了 %d 次(7 天 × 20), 非 null %d 次 —— 判据有东西可判"
		% [draws, draws - nulls], draws == 140 and nulls == 0,
		"draws=%d nulls=%d" % [draws, nulls])
	_chk("⑥ ★★★140 次抽样一次都没跨标签(七天答案一致)", cross == 0,
		"跨标签 %d 次; 抽到的集合 %s" % [cross, str(picked.keys())])

	## 另一侧: 把同标签全排除 ⇒ 必须 null。
	## 少了这条, 「永远返回第一个同标签」和「永远返回 null」都能让上面那条绿。
	var excl := ["g_same0", "g_same1", "g_same2", "g_same3"]
	var leaked: Array = []
	for d2 in range(7):
		P2.now_override_ts = MON0 + d2 * 86400 + NOON
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 99
		for _i in range(10):
			var g2 = BE.gauntlet_pool_find(pool, 3, 1, excl, rng2)
			if g2 != null:
				leaked.append(str(g2.get("ghost_id", "?")))
	P2.now_override_ts = 0
	_chk("⑥ ★★分母(另一侧): 同标签全排除 ⇒ 70 次全部为空, 一格都不降(证明上一条不是恒真)",
		leaked.is_empty(), str(leaked.slice(0, 4)))


# ═════════════════════════════════════════════════════════════════
# ⑦ 封盘窗口: 7 天 × 24 小时 × 3 个分钟位全扫
# ═════════════════════════════════════════════════════════════════
## ★为什么要全扫而不是"挑几个时刻": 封盘是**唯一**一条合法地挂在星期几上的匹配闸
##   (积分赛周五收盘 / 闯关赛周六收盘)。它的风险正好相反 —— **漏到别的天去**。
##   真实时钟一周只有两天多落在窗口里, 不钉住"现在"就只能验到七分之一。
## ⚠ 这里**不断言"封盘时刻恰好 4 个"** —— 那是把 CLOSE_LOCKOUT_SEC 抄第二份
##   (CLAUDE.md §「门禁不要断言常量等于某个数」)。判据是形状: 全部落在两个收盘日、
##   且都在各自收盘前 CLOSE_LOCKOUT_SEC 秒之内。
func _t_lockout_sweep() -> void:
	print("── ⑦ 封盘: 7 天 × 24 小时全扫 ──")
	var total := 0
	var blocked: Array = []
	var off_day: Array = []
	var off_window: Array = []
	for d in range(7):
		for h in range(24):
			for m in [0, 40, 50]:
				var ts: int = MON0 + d * 86400 + h * 3600 + m * 60
				P2.now_override_ts = ts
				total += 1
				if P2.can_start_match_utc(ts):
					continue
				var wd: int = P2.iso_weekday_utc(ts)
				var left: int = P2.close_left_sec(ts)
				blocked.append("wd%d %02d:%02d(left=%d)" % [wd, h, m, left])
				if wd != P2.RANKED_CLOSE_WD and wd != P2.GAUNTLET_CLOSE_WD:
					off_day.append("wd%d %02d:%02d" % [wd, h, m])
				if left < 0 or left > P2.CLOSE_LOCKOUT_SEC:
					off_window.append("wd%d %02d:%02d left=%d" % [wd, h, m, left])
	P2.now_override_ts = 0
	print("    封住的时刻: %s" % str(blocked))
	_chk("⑦ ★分母: 扫了 %d 个时刻(7 天 × 24 小时 × 3 个分钟位)" % total, total == 504,
		"total=%d" % total)
	_chk("⑦ ★分母: 确实封住过 %d 个时刻(0 个 = 空检查)" % blocked.size(),
		blocked.size() > 0, str(blocked))
	_chk("⑦ ★★★封盘只出现在两个收盘日, 别的五天一个都没有",
		off_day.is_empty(), "越界: %s" % str(off_day))
	_chk("⑦ ★★★每个封住的时刻都落在各自收盘前 CLOSE_LOCKOUT_SEC 秒之内",
		off_window.is_empty(), "越界: %s" % str(off_window))

	## 两侧精确验: 只验"封住"是半条判据("永远封住"也能绿)
	var rc: int = P2.ranked_close_ts(MON0)
	var gc: int = P2.gauntlet_close_ts(MON0)
	_chk("⑦ ★分母: ranked_close_ts 落在 ISO 周五 %d 点整" % P2.WEEK_CLOSE_HOUR_UTC,
		P2.iso_weekday_utc(rc) == P2.RANKED_CLOSE_WD
		and int(Time.get_datetime_dict_from_unix_time(rc).get("hour", -1)) == P2.WEEK_CLOSE_HOUR_UTC
		and P2.week_anchor_utc(rc) == MON0,
		"wd=%d hour=%s" % [P2.iso_weekday_utc(rc),
			str(Time.get_datetime_dict_from_unix_time(rc).get("hour"))])
	_chk("⑦ ★分母: gauntlet_close_ts 落在 ISO 周六 %d 点整" % P2.WEEK_CLOSE_HOUR_UTC,
		P2.iso_weekday_utc(gc) == P2.GAUNTLET_CLOSE_WD
		and int(Time.get_datetime_dict_from_unix_time(gc).get("hour", -1)) == P2.WEEK_CLOSE_HOUR_UTC
		and P2.week_anchor_utc(gc) == MON0,
		"wd=%d hour=%s" % [P2.iso_weekday_utc(gc),
			str(Time.get_datetime_dict_from_unix_time(gc).get("hour"))])
	_chk("⑦ 收盘前恰好 CLOSE_LOCKOUT_SEC 秒 ⇒ 封住(两个收盘日都验)",
		not P2.can_start_match_utc(rc - P2.CLOSE_LOCKOUT_SEC)
		and not P2.can_start_match_utc(gc - P2.CLOSE_LOCKOUT_SEC))
	_chk("⑦ ★另一侧: 再往前一秒就放开(否则「永远封住」也能让上一条绿)",
		P2.can_start_match_utc(rc - P2.CLOSE_LOCKOUT_SEC - 1)
		and P2.can_start_match_utc(gc - P2.CLOSE_LOCKOUT_SEC - 1))

	## 休赛(周一) / 决赛日(周日): 没有收盘概念 ⇒ 48 小时全扫都不封
	var noclose := 0
	var noclose_left := 0
	for d2 in [0, 6]:
		for h in range(24):
			var ts2: int = MON0 + d2 * 86400 + h * 3600
			P2.now_override_ts = ts2
			if P2.can_start_match_utc(ts2):
				noclose += 1
			if P2.close_left_sec(ts2) < 0:
				noclose_left += 1
	P2.now_override_ts = 0
	_chk("⑦ 休赛日 + 决赛日没有收盘概念 ⇒ 48 小时全扫 close_left_sec 恒 < 0 且都能开局",
		noclose == 48 and noclose_left == 48, "can_start %d/48 / left<0 %d/48"
		% [noclose, noclose_left])

	## ─── 只报不判: 收盘之后到午夜那一小时又开了 ───────────────────
	## `close_left_sec()` 收盘后转负, 而 `can_start_match_utc()` 把"负数"当成
	## "这个阶段没有收盘概念" ⇒ 周五 23:00:01~23:59:59 又能开新局。
	## ★这里**不写成断言**: 断言"现在的行为"就是把这个形状焊死
	##   (memory fb-gate-can-pin-the-bug-in-place); 要不要改是产品决定, 不是门禁决定。
	var after: Array = []
	for spec in [[4, 23, 30], [5, 23, 30]]:
		var ts3: int = MON0 + int(spec[0]) * 86400 + int(spec[1]) * 3600 + int(spec[2]) * 60
		after.append("wd%d %02d:%02d phase=%s left=%d can_start=%s"
			% [P2.iso_weekday_utc(ts3), int(spec[1]), int(spec[2]), P2.phase_at_utc(ts3),
				P2.close_left_sec(ts3), str(P2.can_start_match_utc(ts3))])
	print("    [INFO·只报不判] 收盘后到午夜: %s" % str(after))


# ═════════════════════════════════════════════════════════════════
# ⑧ 收尾: static 的缝必须都还原了
# ═════════════════════════════════════════════════════════════════
func _t_restored() -> void:
	print("── ⑧ 收尾: static 注入点全部还原 ──")
	_chk("⑧ ★now_override_ts 还原成 0(static, 漏还原会波及同进程后面的用例)",
		P2.now_override_ts == 0, "now_override_ts=%d" % P2.now_override_ts)
	_chk("⑧ ★Backend.pool_override 还原成空", BE.pool_override.is_empty(),
		str(BE.pool_override.keys()))
	_chk("⑧ ★还原之后 now_utc() 又是真实系统时钟",
		absi(P2.now_utc() - int(Time.get_unix_time_from_system())) <= 1)
