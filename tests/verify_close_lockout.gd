extends Node
## verify_close_lockout.gd — A4 的第三种拦截：**封盘时「开打」真的被拦住**
##
## ★★由来(2026-09-18 用户点出来的): 方案书把 A4 记成「三种原因各自一条提示」,
##   `MainMenuScene._start_battle_flow` 的注释也这么写, **而代码只做了 2/3** ——
##   `can_start_match_utc` 在产品代码里的唯一调用点是 `MainMenuScene.gd:850`,
##   那里**只渲染文案**(「已封盘 / 收盘前 N 分钟起不开新局」), 没有任何地方拿它拦开局。
##
## ★★而当时**已经有一条门禁在"测"它**: `verify_week_season` ⑥ 喂时间戳给
##   `can_start_match_utc` 看返回 true/false —— 那测的是**那个纯函数本身**,
##   不是「开打那一刻被拦住」。典型的「判据没错但被测对象不在场」。
##   ⇒ 本门禁必须走**真入口** `TeamSelectScene._on_start()`, 断言**没有换场景**。
##
## ★为什么闸在 TeamSelect 不在主菜单: `phase2_config.can_start_match_utc` 自带警告
##   「⚠ 调用点必须是**点「开打」那一刻**, 不是点匹配 —— 摆位不限时, 设在匹配就盖不住」。
##   流程是 主菜单→TeamSelect 摆位→`_on_start()`→Matchmaking→战斗, 所以开打 = `_on_start()`。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_close_lockout.tscn --quit-after 900

## ★实例化**场景**不是脚本: 直接 `TeamSelectScene.gd.new()` 会在 `_ready` 里
##   碰 `theme` 等场景自带的东西而炸(第一版就这么炸的)。仓库里 `_probe_card/_rail/_toast`
##   三个探针都是 load .tscn 再 instantiate —— 照现成的来, 别自创。
const TS_SCENE := preload("res://scenes/TeamSelect.tscn")
const TS := preload("res://scripts/scenes/TeamSelectScene.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

var _ok := 0
var _fail := 0
## ★缓存场景树: ② 之后 `change_scene_to_file` 会在帧末把当前场景掀掉,
##   那时 `get_tree()` 已是 null ⇒ `_done()` 里再调 `get_tree().quit()` 会抛
##   「Cannot call method 'quit' on a null value」。**断言全过但日志里有 SCRIPT ERROR,
##   `run-tests.sh` 的致命正则照样判红** —— 第一版就是这么绿着却会红的。
var _tree: SceneTree = null

func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])

## 找一个【确定有收盘】的基准时刻。
## ★★**2026-09-20 修一条潜伏 bug**: 原实现直接拿 `now` 去算 `close_left_sec`,
##   而它在**周一休赛 / 周日决赛日返回 -1**(没有"收盘"这回事) ⇒
##   这条门禁**每周有两天必红**, 与代码对不对无关。
##   2026-09-20(周日)全套门禁就红在这里: `in=-1 out=-1`。
##   ★分母断言把它拦住了(没有静默通过) —— 这正是分母断言的价值。
## ⇒ 现在**往后逐天找**, 找到第一个有收盘的日子再造样本(最多找 8 天, 一周内必有)。
## ★仍然**不写死日期** —— 收盘是"每周某天某点", 写死的几年后就不在那一周了。
func _base_ts_with_close() -> int:
	var now := int(Time.get_unix_time_from_system())
	for d in range(9):
		var ts := now + d * 86400
		if int(P2C.close_left_sec(ts)) >= 0:
			return ts
	return -1

## 【确定落在封盘窗内】的 UTC 时间戳: 收盘前 (LOCKOUT/2) 秒。
func _ts_inside_lockout() -> int:
	var base := _base_ts_with_close()
	if base < 0:
		return -1
	var left := int(P2C.close_left_sec(base))
	if left < 0:
		return -1
	return base + left - int(P2C.CLOSE_LOCKOUT_SEC / 2)

func _ts_outside_lockout() -> int:
	var base := _base_ts_with_close()
	if base < 0:
		return -1
	var left := int(P2C.close_left_sec(base))
	if left < 0:
		return -1
	return base + left - int(P2C.CLOSE_LOCKOUT_SEC) - 600   # 封盘线之外再退 10 分钟

func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	print("── A4 第三闸: 封盘时开打被拦住 ──")

	var t_in := _ts_inside_lockout()
	var t_out := _ts_outside_lockout()
	_chk("★分母: 造得出「封盘窗内」与「窗外」两个时刻", t_in > 0 and t_out > 0,
		"in=%d out=%d" % [t_in, t_out])
	if t_in <= 0 or t_out <= 0:
		_done(); return
	## ★先验尺子: 这两个时刻本身必须一个被判封盘、一个不封盘。
	##   否则下面"开打被拦住"可能是**别的原因**拦的, 而我会当成这条闸生效了。
	_chk("★分母: 窗内时刻确实被 can_start_match_utc 判为封盘",
		not P2C.can_start_match_utc(t_in))
	_chk("★分母: 窗外时刻确实不封盘", P2C.can_start_match_utc(t_out))

	## ── 走真入口 ──
	var inst = TS_SCENE.instantiate()
	add_child(inst)
	var w := 0
	while w < 600 and not inst.is_node_ready():
		await get_tree().process_frame
		w += 1
	for _i in range(10):
		await get_tree().process_frame

	## 凑够 REQUIRED_PETS 只龟, 否则 `_on_start` 会在人数那一关就 return ——
	## 那样"没换场景"是**人数不够**造成的, 不是封盘, 判据就成了恒真式。
	var pool: Array = []
	## ★字段名是 `all_pets` 不是 `pets` —— 第一版我凭印象写了 `pets`,
	##   运行时报 "Invalid access to property or key 'pets'"。分母断言接住了。
	for p in DataRegistry.all_pets:
		if p is Dictionary and p.has("id"):
			pool.append(str(p["id"]))
		if pool.size() >= int(TS.REQUIRED_PETS):
			break
	_chk("★分母: 取得到 %d 只龟填满阵容" % int(TS.REQUIRED_PETS),
		pool.size() >= int(TS.REQUIRED_PETS), "%d 只" % pool.size())
	if pool.size() < int(TS.REQUIRED_PETS):
		_done(); return
	for i in range(int(TS.REQUIRED_PETS)):
		inst.team[i] = pool[i]

	## ★★判据落在【产品自己的账】上, 不落在场景树。
	##   第一版判的是 `get_tree().current_scene` 有没有变 —— 三条变异**一条都没红**:
	##   拆掉闸之后 `_on_start()` 立刻换场景 ⇒ 树被掀 ⇒ 下一行 `await get_tree().process_frame`
	##   直接崩 ⇒ **测试函数中途中止、剩余断言不跑、`_done()` 也没跑**, 于是一条 FAIL 都没打出来。
	##   (同族 memory:「null 回读让测试静默中止假绿」。)
	##   ⇒ 改成量 `GameState.left_team`: `_on_start()` 在 `change_scene_to_file` **之前**
	##   会写它(见 TeamSelectScene 的 `GameState.left_team = left_typed`)。
	##   没写 = 提前 return 了 = 闸拦住了。**同步可读, 不依赖场景树活着。**
	GameState.left_team = [] as Array[String]

	## ① 封盘窗内点开打 ⇒ 闸拦住: left_team 仍为空, 且弹出封盘 toast
	inst.lockout_now_override = t_in
	inst._on_start()
	_chk("① ★封盘窗内点开打: 产品没写 left_team(= 提前 return 了, 闸真的拦住)",
		GameState.left_team.is_empty(), "left_team=%d 只" % GameState.left_team.size())
	_chk("① ★弹出了封盘提示(和淘汰/配额那两条不是同一条)",
		inst.get_node_or_null("LockoutToast") != null)

	## ────────────────────────────────────────────────────────────
	## ③ ★★★同一条闸, 时刻从**全局缝**来 (`phase2_config.now_override_ts`, 2026-09-28)
	##
	## ★★为什么非要这一条: 这条闸的兜底原来是**就地** `Time.get_unix_time_from_system()`
	##   —— 它和全局缝**互不相通**。实测(`tests/_probe_oneclock.gd`, 修前):
	##   缝钉在「周五 22:55 封盘窗内」而 `lockout_now_override` 留 0 ⇒ 这条闸
	##   **照旧放过去**(left_team 被写了 3 只), 因为它读的是真实系统钟。
	##   于是「整屏钉在收盘前五分钟」的端到端场景里, 主菜单已经在喊封盘、
	##   而点开打照样开得出去。memory `fb-second-clock-drops-events`。
	## ★这一条**不写** `lockout_now_override` —— 走的正是玩家路径那条兜底。
	## ────────────────────────────────────────────────────────────
	for c in inst.get_children():
		if c.name == "LockoutToast":
			c.queue_free()
			inst.remove_child(c)
	_chk("③ ★分母: 产品默认 now_override_ts == 0(缝默认关着, 玩家路径一字未动)",
		int(P2C.now_override_ts) == 0, "now_override_ts=%d" % int(P2C.now_override_ts))
	inst.lockout_now_override = 0
	P2C.now_override_ts = t_in
	GameState.left_team = [] as Array[String]
	_chk("③ ★分母: 这一次**只**钉了全局缝, 屏内那层是关着的",
		int(inst.lockout_now_override) == 0 and int(P2C.now_override_ts) == t_in,
		"屏内=%d 缝=%d" % [int(inst.lockout_now_override), int(P2C.now_override_ts)])
	inst._on_start()
	var seam_blocked_in: bool = GameState.left_team.is_empty()
	_chk("③ ★★★只钉全局缝也拦得住: 产品没写 left_team",
		seam_blocked_in, "left_team=%d 只" % GameState.left_team.size())
	_chk("③ ★★★只钉全局缝也弹得出封盘提示",
		inst.get_node_or_null("LockoutToast") != null)

	## ② 窗外点开打 ⇒ 这条闸不该拦(证明 ①/③ 不是恒真式: 同一次调用在窗外就会写 left_team)
	## ★★★驱动改用**全局缝**(2026-09-28): 一个进程里只能有**一次**"放过去", 因为放过去那次
	##   会真的 `change_scene_to_file` 把场景树掀掉 ⇒ 这一次留给**新**的那一层,
	##   它同时当 ① 与 ③ 的分母(证明 `_on_start()` 在不封盘时确实写得到 left_team),
	##   并且证明这条缝**两个方向都通**(钉窗内=拦住 / 钉窗外=放过)。
	##   屏内那层 `lockout_now_override` 的 ">0" 分支由 ① 与 `verify_week_phase_write` 守。
	for c in inst.get_children():
		if c.name == "LockoutToast":
			c.queue_free()
			inst.remove_child(c)
	inst.lockout_now_override = 0
	P2C.now_override_ts = t_out
	inst._on_start()
	## ★★这里**不许 await**: 窗外那次会真的走到 `change_scene_to_file("Matchmaking")`,
	##   而换场景是【延迟到帧末】执行的 —— 一 await 就把门禁自己的场景树掀掉,
	##   下一行 `get_tree().process_frame` 直接对 null 取属性而崩(第一版就这么炸的)。
	##   而 `_lockout_toast()` 里的 `add_child` 是**同步**的 ⇒ 不 await 也查得到它在不在。
	_chk("② ★窗外点开打: 没有弹封盘提示", inst.get_node_or_null("LockoutToast") == null)
	_chk("② ★窗外点开打: 产品写了 left_team(证明 ①/③ 的空不是「本来就没走到」)",
		GameState.left_team.size() == int(TS.REQUIRED_PETS),
		"left_team=%d 只" % GameState.left_team.size())
	## ★★分母: 同一条缝, 钉窗内=拦住 / 钉窗外=放过 —— 注入前后**本来就该不同**。
	##   少了这一条, ③ 就可能是在一个"怎么钉都拦"的实现上量的。
	## ★判据是**两侧翻面**, 不是"窗外这一侧写了" —— 后者与 ② 第二条一字不差,
	##   抄一遍等于白加一条(反向验证时它照样绿, 2026-09-28 实测过才改成这样)。
	var seam_blocked_out: bool = GameState.left_team.is_empty()
	_chk("③ ★★分母: 同一条缝两个方向都通(窗内=%s / 窗外=%s, 答案确实翻面)" % [
			"拦住" if seam_blocked_in else "放过", "拦住" if seam_blocked_out else "放过"],
		seam_blocked_in and not seam_blocked_out)

	## ★缝是 **static** ⇒ 活过场景切换 ⇒ 用完必须还原。
	P2C.now_override_ts = 0
	_chk("★收尾: 全局缝已还原成 0", int(P2C.now_override_ts) == 0)
	_done()

func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 封盘拦开打 (%d/%d)" % [_ok, _ok])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok])
	if _tree != null:
		_tree.quit(1 if _fail > 0 else 0)
