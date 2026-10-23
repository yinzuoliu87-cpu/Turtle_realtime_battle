extends RefCounted
## 服务器裁判 · 客户端流程(2026-10-19 · 方案书 docs/plans/20261019-服务器裁判.md §3 ①②)。
## 用户 10-19「我们的所有对局不应该在本机上吧，应该放服务器上吧」「周六周日让服务器记」。
##
## ══════════════════════════════════════════════════════════════════════
##  周六闯关(开关 `gauntlet_on` 开着时; 关着时一字不变走老路 = 本机打、本机记)
## ══════════════════════════════════════════════════════════════════════
##   匹配屏(本机不挑对手)→ `Run`:
##     提交 ── referee_gauntlet_start(我的快照, 第几场) ──► 服务端挑对手(同标签真人 → 机器人)、定种子、建任务
##             ⇒ 回任务号 + 对手卡片(匹配屏画 VS 卡) ⇒ 落「待记账单」(GameState.referee_pending, 进存档)
##     等待 ── 每 POLL_SEC 秒 referee_job_status ──► done ⇒ 按服务器的胜负 / 战绩 / 战斗内铸币记账(`settle`, 清单 + 存档同一刻)
##     播放 ── 按录像号取录像(matches)──► ReplayRecorder.play + 观赛会话 KIND_REFEREE:
##             1 倍从头放、没有「回放」小签、没有播放控件; 放完走正常结算屏, 胜负 / 战绩 / 奖励都是服务器那一份
##   ★账在播之前就记完: 播到一半杀进程 / 退出, 账也不会丢、不会记两次。
##   ★断网 / 超时 / 服务端拒收 ⇒ 屏上一句话, **不出本地成绩**(问题总表 B1)。
##     交上去之后才断网 / 等到上限还没算完(ST_LATER)⇒ 待记账单留着, 匹配屏自己回主菜单并飘「稍后自动记入」(`notice`);
##     主菜单开着时每 MENU_POLL_SEC 秒查一次任务状态补记(`resume_if_any`), 杀进程的话下次开主菜单补记。
##     (2026-10-22 内测服整周彩排: 裁判机排队 > 180 秒的 7 / 100 局把 8 个号停在匹配屏, 要自己退回主菜单才补记。)
##   ★服务端回 `off`(开关刚关)⇒ 记下开关, 退回老路本机打(行为与开关关着一样)。
##   ★录像在本机重算对不上(`_diverge`)⇒ 结算屏照样按服务器结果出, 加一行「录像无法在本设备播放」。
##   ★★逐帧直播 S5(docs/plans/20261019-服务器逐帧直播.md §4): 开关 `stream_on` 开着时「播放」这一步改成**播服务器的状态流**
##     (`play_settled_route` → stream_watch.gd; 手机一步 sim 都不跑, 不存在「对不上」)。录像仍然先取: 种子 / 开局状态 / 版本号 /
##     认场都靠它, 但不再拿它重算。服务器那边没有这份流 ⇒ 不播、也不重算, 屏上「结果 · 画面无法播放」(账已记完)。
##     开关关 ⇒ `play_settled` 原样(本机重算)。
##
## ══════════════════════════════════════════════════════════════════════
##  周日决赛(开关 `finals_on`): 判据与界面在 BracketMapScene(点开自己那一场 = 看), 这里只放它要的记账 `finals_seal`
##  与战斗内铸币的待取单(`claim_finals_coins`: 翻面后按服务器给的数发, 2026-10-20)
## ══════════════════════════════════════════════════════════════════════

const RN := preload("res://scripts/net/referee_net.gd")
const SB := preload("res://scripts/net/supabase.gd")
const RF := preload("res://scripts/systems/replay/replay_fetcher.gd")
const LS := preload("res://scripts/systems/replay/live_spectate.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BE := preload("res://scripts/net/backend.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")

## 屏上的字(短、名词化; 不拟人)。
const TXT_SUBMITTING := "正在提交阵容"
const TXT_SETTLING := "正在结算"
const TXT_NEED_SERVER := "连接服务器后才能比赛"
const TXT_LATER := "对局结果计算中，稍后自动记入战绩"
const TXT_FAILED := "结算失败，请重新开战"
const TXT_UPDATE := SW.TXT_UPDATE   # 与逐帧直播的版本闸同一句话(只存一份)
const TXT_CLOSED := "闯关赛仅限周六"
const TXT_FINISHED := "本周闯关已结束"
const TXT_BAD_LINEUP := "阵容无效，请检查背包"
const TXT_UNPLAYABLE := "录像无法在本设备播放"
const TXT_STALE := "战绩已同步，请重新开战"
const TXT_NO_MATCH := "匹配失败，请稍后重试"
const TXT_SHOP := "备战阶段 · 结束后开赛"
const TXT_RESUMED_WIN := "上一场闯关：胜利"
const TXT_RESUMED_LOSE := "上一场闯关：失败"
const TXT_FINALS_COINS := "战斗内铸币 +%d"
const MAIN_MENU := "res://scenes/MainMenu.tscn"

## 查任务的间隔(秒)与上限(次): 合计 180 秒还没算完 ⇒ 不再干等(ST_LATER: 回主菜单, 待记账单留着由主菜单补记)。
##   实测一局: 内测服裁判机约 29 秒 / 局(10-22 彩排); 正式服 CX33 上满装备三路打满不录约 150 秒(referee_poller.py 头注)。
##   裁判机那边一局的墙钟上限是 JOB_TIMEOUT_SEC = 600 —— 那是「判这一局超时」的线, 不是玩家该在匹配屏干等的时长。
const POLL_SEC := 2.0
const POLL_MAX := 90
## 【门禁注入点】> 0 时替代 POLL_MAX(门禁不用真等 180 秒)。默认 0 = 不生效 ⇒ 玩家路径一字不动;
##   static ⇒ 活过场景切换 ⇒ 用完必须还原(样式同 `SupabaseNet.match_fetch_timeout_for_test`)。
static var poll_max_for_test := 0


static func poll_max() -> int:
	return poll_max_for_test if poll_max_for_test > 0 else POLL_MAX


## 连着几次问不到服务端(交上去之后断网)⇒ 不再干等。
const OFFLINE_MAX := 3
## 主菜单开着、待记账单还挂着 ⇒ 多久再查一次任务状态(秒)。单子清掉就不再查。
const MENU_POLL_SEC := 10.0
## 主菜单要飘的一行(匹配屏等不到结果、回主菜单时写)。读走即清(样式同 `AbandonedMatch.notice`)。
static var notice := ""
## 周日等开播时对阵图多久拉一次(秒; 平时 30 秒)。
const FINALS_POLL_SEC := 5.0

## Run 的状态。
const ST_SUBMIT := "submit"
const ST_WAIT := "wait"
const ST_FETCH := "fetch"
const ST_PLAY := "play"
const ST_LOCAL := "local"       # 服务端说开关已关 ⇒ 调用方走老路(本机打)
const ST_ERROR := "error"       # 停在原地, msg 说清原因(没有本地成绩)
const ST_LATER := "later"       # 交上去了、结果没等到(等到上限 / 问不到): 单子留着 ⇒ 调用方回主菜单, 主菜单补记


## 周六这一场交给服务器吗(调用方已判过「今天是周六且闯关赛上线」, 这里只看开关)。
static func gauntlet_on() -> bool:
	return RN.gauntlet_on()


## 我的阵容快照(与周六上传那份同一个构造 `Backend.build_ghost_snapshot`, 含站位 / 赛季等级)。
static func my_snapshot() -> Dictionary:
	if GameState == null:
		return {}
	var leaders = GameState.season_leaders
	var base := BE.player_ghost_id(int(GameState.season_id), leaders, -1)
	var gid := "%s_g%d-%d" % [base, int(GameState.gauntlet_wins), int(GameState.gauntlet_losses)]
	var av := str(leaders[0]) if (leaders is Array and (leaders as Array).size() > 0) else "basic"
	return BE.build_ghost_snapshot(gid, {"name": BE.player_display_name(), "avatar": av, "id": gid})


## 交上去那一刻的待记账单。
static func pending_for(job_id: int, match_id: String, week: int, foe: Dictionary) -> Dictionary:
	var ldr: Array = []
	for x in (foe.get("leaders", []) if foe.get("leaders", []) is Array else []):
		if ldr.size() < 3:
			ldr.append(str(x))
	var pf = foe.get("profile", null)
	return {"job_id": job_id, "match_id": match_id, "week": week, "foe": ldr,
		"foe_name": str((pf as Dictionary).get("name", "")) if pf is Dictionary else ""}


## ★记账: 服务器算完的这一场(周六口径, 与 `_settle_season` 的闯关分支 + 收尾同一套)。
##   只认待记账单上那一个任务号 ⇒ 匹配屏与主菜单补记两条路谁先到谁记, 另一条什么都不做(不会记两次)。
##   战绩(gw / gl)以服务器账本为准(`referee_job_status` 回的是记完这一场之后的数)。
##   ★战斗内铸币(奇械羁绊 / 035 齿轮)= 服务器那一局算出来的 `coins`(裁判写进账本), 与本机打完 `_settle_season`
##     同一个位置加进奖励、同一条「出局那一局不发」。客户端不重算、不自报(2026-10-20; 之前服务器局一枚都不发)。
##   返回结算屏要的 {won, reward, coins, gw, gl}; {} = 不是这一单 / 结果不明 / 已经记过。
static func settle(gs, job_id: int, st: Dictionary) -> Dictionary:
	if gs == null:
		return {}
	var p = gs.get("referee_pending")
	if not (p is Dictionary) or (p as Dictionary).is_empty() or int((p as Dictionary).get("job_id", -1)) != job_id:
		return {}
	var pd: Dictionary = p
	var wi := int(st.get("won", -1))
	if wi < 0:
		return {}
	if int(pd.get("week", 0)) != P2C.week_anchor_utc(int(P2C.now_utc())):
		gs.referee_pending = {}           # 上一周交的: 不记进这一周(换周时 start_new_season 也会清)
		gs.save()
		return {}
	var won := wi == 1
	var coins := maxi(0, int(st.get("coins", 0)))
	var reward: int = gs.gauntlet_settle(won) + coins   # 与 `_settle_season` 同序: 场次币 + 战斗内铸币
	if int(st.get("gw", -1)) >= 0 and int(st.get("gl", -1)) >= 0:
		gs.gauntlet_wins = int(st["gw"])
		gs.gauntlet_losses = int(st["gl"])
	if gs.is_eliminated():
		reward = 0                        # 与 `_settle_season` 同一条: 出局那一局不发币(含战斗内铸币)
	gs.meta_deepsea_coins += reward
	apply_chest(gs, st.get("chest", {}))   # 服务器那一局里宝箱龟攒的财宝值 / 开出的战利品(2026-10-22b)
	apply_incense(gs, st.get("incense", {}))   # 服务器那一局里 093 香火石的刻痕 / 充能(2026-10-23)
	gs.battles_total += 1
	if won:
		gs.battles_won += 1
	var mid := str(pd.get("match_id", ""))
	if SB.is_uuid(mid):
		gs.replay_pending_id = mid        # 战绩页那一行挂上录像(服务器那一份)
	var lineup: Array = (gs.season_leaders as Array).slice(0, 3) if gs.season_leaders is Array else []
	gs.referee_pending = {}
	gs.record_match("win" if won else "lose", lineup, "实时", 0)
	if not gs.match_history.is_empty():
		var row: Dictionary = gs.match_history[0]
		row["ts"] = int(Time.get_unix_time_from_system())
		## 对手 = 交上去的那份(主菜单补记时 dual_ghost 可能早已换过)
		if (pd.get("foe", []) as Array).size() > 0:
			row["foe"] = (pd["foe"] as Array).duplicate()
		if str(pd.get("foe_name", "")) != "":
			row["foe_name"] = str(pd["foe_name"])
	gs.save()
	## 快照池: 以服务器给的新战绩标签再传一份(服务端写回时挂进池的那份没有 gl_* 标签, 本机匹配层认不出)。
	BE.upload_gauntlet_ghost(int(gs.gauntlet_wins), int(gs.gauntlet_losses))
	BE.report_finals_entry()
	return {"won": won, "reward": reward, "coins": coins, "gw": int(gs.gauntlet_wins), "gl": int(gs.gauntlet_losses)}


## 服务器那一局结束时我方宝箱龟的进度 → 存档(2026-10-22b · 方案书 20261022-宝箱龟整条链路修复 A)。
##   用户「宝箱整个是不是有bug啊」: 原来服务器局里攒的财宝值 / 开出的箱子一概不进存档, 下一场又从旧值起算。
##   `chest` = RefereeNet.parse_chest 的结果({} = 服务器没给 ⇒ 不动)。裁判机是从我交上去的进度起算的,
##   所以它那份正常就是「本地 + 这一局」; 仍取 max / 较长那份, 防迟到的回包把本地已经更新的进度倒退回去。
##   调用方负责「不是这一周的结果不记」(settle / on_finals_coins 都先查周)。返回存档有没有变。
static func apply_chest(gs, chest: Dictionary) -> bool:
	if gs == null or chest.is_empty():
		return false
	var changed := false
	var v: float = float(chest.get("value", 0.0))
	if v > float(gs.chest_treasure_value):
		gs.chest_treasure_value = v
		changed = true
	var won: Array = chest.get("won", [])
	if won.size() > (gs.chest_treasures_won as Array).size():
		gs.chest_treasures_won = won.duplicate()
		changed = true
	return changed


## 服务器那一局结束时我方 093 香火石的刻痕 + 充能 → 存档(2026-10-23 · 方案书 20261023-香火石四个问题 3)。
##   `inc` = RefereeNet.parse_incense 的结果({} = 服务器没给 ⇒ 不动)。裁判机从我交上去的进度起算 ⇒ 它那份正常就是
##   「本地 + 这一局」; 仍只往前走(刻痕多 ⇒ 两个都换; 刻痕一样 ⇒ 充能取大), 防迟到的回包把本地已经更新的进度倒退回去。
##   调用方负责「不是这一周的结果不记」(与 apply_chest 同一处调用)。返回存档有没有变。
static func apply_incense(gs, inc: Dictionary) -> bool:
	if gs == null or inc.is_empty():
		return false
	var m: int = int(inc.get("marks", 0))
	var c: int = int(inc.get("charge", 0))
	if m > int(gs.incense_marks):
		gs.incense_marks = m
		gs.incense_charge = c
		return true
	if m == int(gs.incense_marks) and c > int(gs.incense_charge):
		gs.incense_charge = c
		return true
	return false


## 开战时服务端说「第几场」对不上(stale): 以账本为准。上一场的账还挂着 ⇒ 先补记那一场(它带着服务器的战绩与铸币);
##   没挂着 ⇒ 直接把本机战绩对齐到账本。
static func adopt_ledger(gs, gw: int, gl: int) -> void:
	if gs == null or gw < 0 or gl < 0:
		return
	var p = gs.get("referee_pending")
	if p is Dictionary and not (p as Dictionary).is_empty():
		resume_if_any()
		return
	gs.gauntlet_wins = gw
	gs.gauntlet_losses = gl
	gs.save()


## 播服务器那一份录像(账已记完)。返回 "" = 已进战斗场; 否则是不能播的原因。
static func play_settled(tree: SceneTree, rec: Dictionary, view: Dictionary) -> String:
	LS.pending = {"kind": LS.KIND_REFEREE, "id": str(rec.get("id", "")), "result": view.duplicate(),
		"t_ms": Time.get_ticks_msec()}
	var why := ReplayRecorder.play(tree, rec, MAIN_MENU, {})
	if why != "":
		LS.pending = {}
	return why


## 同上, 但先过逐帧直播的分流口(S5)。`done.call(code, msg)` 恰好一次: "" = 已进战斗场。
##   开关关 ⇒ 同步走 `play_settled`(与改之前逐字一致); 开 ⇒ 有流播流, 没有流 / 断网 / 版本过旧 ⇒ 不进场(绝不本机重算)。
##   ★这一场确知是服务器裁判局(`known`): 没有流时**不**退回重算。
static func play_settled_route(tree: SceneTree, rec: Dictionary, view: Dictionary, done: Callable) -> void:
	SW.route(tree, rec, MAIN_MENU, {}, true, func() -> String: return play_settled(tree, rec, view), done,
		{"kind": SW.KIND_REFEREE, "result": view.duplicate()})


## 结算之后的一句话(播不了录像时屏上写它)。
static func result_line(view: Dictionary) -> String:
	var gl := P2C.gauntlet_label(int(view.get("gw", 0)), int(view.get("gl", 0)))
	return "闯关 %s · %s" % [gl, "胜利" if bool(view.get("won", false)) else "失败"]


# ─────────────────────────────── 主菜单补记 ───────────────────────────────
## 开主菜单查一次; 单子还挂着 ⇒ 主菜单开着时每 MENU_POLL_SEC 秒再查(`has_pending` 为假就不再查)。
## 两处同时查到同一个 done 也只记一次: `settle` 只认单子上那个任务号, 记完单子就清了。

## 有没有挂着的待记账单。
static func has_pending() -> bool:
	if GameState == null:
		return false
	var p = GameState.get("referee_pending")
	return p is Dictionary and not (p as Dictionary).is_empty()


## 有待记账单 ⇒ 查一次任务状态: 算完了就补记(`done.call(view)`), 失败 / 没这一单就销单, 还在算就留着。
## 返回 false = 没发(没有单子 / 没配后端)。
static func resume_if_any(done: Callable = Callable()) -> bool:
	if GameState == null:
		return false
	var p = GameState.get("referee_pending")
	if not (p is Dictionary) or (p as Dictionary).is_empty():
		return false
	var jid := int((p as Dictionary).get("job_id", -1))
	if jid <= 0:
		GameState.referee_pending = {}
		GameState.save()
		return false
	return RN.job_status_async(jid, func(res: Dictionary) -> void: _on_resume(jid, res, done))


static func _on_resume(jid: int, res: Dictionary, done: Callable) -> void:
	var err := str(res.get("err", ""))
	var st := str(res.get("status", ""))
	if err == "no_job" or (err == "" and st == "failed"):
		if int((GameState.referee_pending as Dictionary).get("job_id", -1)) == jid:
			GameState.referee_pending = {}    # 服务端没算成: 销单(这一场不算; 重新开战会重交同一场)
			GameState.save()
		return
	if err != "" or st != "done":
		return                                # 问不到 / 还在算: 留着下次
	var v := settle(GameState, jid, res)
	if not v.is_empty() and done.is_valid():
		done.call(v)


static func resume_text(view: Dictionary) -> String:
	return TXT_RESUMED_WIN if bool(view.get("won", false)) else TXT_RESUMED_LOSE


# ─────────────────────────────── 结算屏(战斗场 HUD 调) ───────────────────────────────

## 这一场是不是服务器裁判局(周六看自己那一场)。
static func is_watch(battle) -> bool:
	var rp = battle.get("_replay")
	return rp != null and rp.is_live() and str(rp.live.kind) == LS.KIND_REFEREE


static func server_won(battle) -> bool:
	return bool((battle._replay.live.result as Dictionary).get("won", false))


## 裁判局放完: 把服务器那一份摆进结算口径(周六), 让 HUD 走正常结算屏。不是裁判局 ⇒ false(照旧回放收尾)。
static func dress_settle(battle) -> bool:
	if not is_watch(battle):
		return false
	var v: Dictionary = battle._replay.live.result
	battle._had_season = true
	battle._last_settle_kind = P2C.SETTLE_GAUNTLET
	battle._last_was_exhibition = false
	battle._last_reward = int(v.get("reward", 0))
	return true


## 录像在本机对不上: 结算屏(服务器结果)上加一行说明。
static func note_unplayable(scr: Node) -> void:
	if scr == null or not is_instance_valid(scr):
		return
	var lb := Label.new()
	lb.name = "RefereeUnplayable"
	lb.text = TXT_UNPLAYABLE
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 20)
	lb.add_theme_color_override("font_color", Color("#ff9b7a"))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pr: Node = scr.find_child("PageResult", true, false)
	if pr != null:
		pr.add_child(lb)
		pr.move_child(lb, mini(2, pr.get_child_count() - 1))
	else:
		scr.add_child(lb)


# ─────────────────────────────── 周日 ───────────────────────────────

## 周日点开自己那一场(购物窗已关、交给服务器算): 与胜负无关的那部分(场次 / 经验 / 轮次币)此刻就给,
##   吃胜负的等对阵图揭晓(`finals_pending_reveal` → `BracketMapScene._reveal_sealed_from`, 老路同一条)。
##   ★同一场只给一次(待揭晓单就是凭据)。返回 true = 这一次真给了。
## `week` = 对阵图那一周(`BracketMapScene.feed_week`); > 0 ⇒ 同时记一张战斗内铸币的待取单(翻面后 `claim_finals_coins` 取)。
static func finals_seal(gs, bucket: int, r: int, m: int, week: int = -1) -> bool:
	if gs == null or bucket < 0 or r < 1 or m < 0:
		return false
	var p = gs.get("finals_pending_reveal")
	if p is Dictionary and int((p as Dictionary).get("round", -1)) == r and int((p as Dictionary).get("match", -1)) == m \
			and int((p as Dictionary).get("bucket", -1)) == bucket:
		return false
	gs.finals_pending_reveal = {"round": r, "match": m, "bucket": bucket}
	var reward: int = gs.finals_settle_sealed()
	if gs.is_eliminated():
		reward = 0
	gs.meta_deepsea_coins += reward
	gs.battles_total += 1
	if week > 0:
		_add_coins_ticket(gs, {"week": week, "bucket": bucket, "round": r, "match": m})
	gs.save()
	return true


# ─────────────────────────────── 周日: 战斗内铸币 ───────────────────────────────
## ★2026-10-20(方案书 docs/plans/20261019-服务器裁判.md R8): 老路本机打完 `_settle_season` 把奇械羁绊 / 035 齿轮的铸币加进奖励;
##   服务器算的周日局原来一枚都没发。现在: 裁判结果单带两侧各自的铸币(`coins` = A 上侧 / `coins_b` = B 下侧, 同一个出口
##   `EquipTickSystem.match_minted`), 服务端记账本; 点开自己那一场时记一张待取单, 翻面后问 `referee_finals_coins`
##   (服务端按账号认侧、翻面之前回 pending), 按回包发、发完把单子标成已发(同一场只发一次; 单子随周清)。
##   ★客户端不报数、不报侧, 也不拿本机任何计数补(老服务端 / 没有裁判局 ⇒ 0)。出局那一局不发(与 `_settle_season` 同一条)。

## 一次只问一张; 有一张发完就接着问下一张。
static var _coins_busy := false


## 待取单的四个坐标(全是合法的非负整数 ⇒ 键; 否则 "")。
static func _coins_ticket_key(t) -> String:
	if not (t is Dictionary):
		return ""
	var d: Dictionary = t
	for k in ["week", "bucket", "round", "match"]:
		var v = d.get(k, null)
		if not (v is int or v is float):
			return ""
	if int(d["week"]) <= 0 or int(d["bucket"]) < 0 or int(d["round"]) < 1 or int(d["match"]) < 0:
		return ""
	return "%d:%d:%d:%d" % [int(d["week"]), int(d["bucket"]), int(d["round"]), int(d["match"])]


static func _add_coins_ticket(gs, t: Dictionary) -> void:
	var k := _coins_ticket_key(t)
	var l = gs.get("finals_coins_pending")
	if k == "" or not (l is Array):
		return
	for x in (l as Array):
		if _coins_ticket_key(x) == k:
			return                            # 同一场已有单子(发没发过都算): 不重记
	var nt := t.duplicate()
	nt["paid"] = false
	(l as Array).append(nt)


## 按服务器的数发一张单子的币。返回发了几枚; -1 = 没有这张单子 / 已经发过(不重复发)。
static func finals_coins_settle(gs, t: Dictionary, coins: int) -> int:
	if gs == null:
		return -1
	var k := _coins_ticket_key(t)
	var l = gs.get("finals_coins_pending")
	if k == "" or not (l is Array):
		return -1
	for x in (l as Array):
		if _coins_ticket_key(x) == k and not bool((x as Dictionary).get("paid", false)):
			var n := maxi(0, coins)
			if gs.is_eliminated():
				n = 0                         # 与 `_settle_season` 同一条: 出局那一局不发币
			(x as Dictionary)["paid"] = true
			(x as Dictionary)["coins"] = n
			gs.meta_deepsea_coins += n
			gs.save()
			return n
	return -1


## 有没发的待取单 ⇒ 问服务端(一次一张)。`done.call(n)` 每发出一张非 0 的调一次。
##   返回 false = 没发请求(没有单子 / 正在问 / 没配后端)。
static func claim_finals_coins(done: Callable = Callable()) -> bool:
	if GameState == null or _coins_busy:
		return false
	var l = GameState.get("finals_coins_pending")
	if not (l is Array):
		return false
	var t: Dictionary = {}
	for x in (l as Array):
		if _coins_ticket_key(x) != "" and not bool((x as Dictionary).get("paid", false)):
			t = (x as Dictionary).duplicate()
			break
	if t.is_empty():
		return false
	_coins_busy = true
	var sent: bool = RN.finals_coins_async(int(t["week"]), int(t["bucket"]), int(t["round"]), int(t["match"]),
		func(res: Dictionary) -> void:
			_coins_busy = false
			on_finals_coins(t, res, done))
	if not sent:
		_coins_busy = false
	return sent


## 回包 → 发 / 销 / 留(门禁直接喂它)。返回发了几枚; -1 = 留着下次(问不到 / 还没翻面 / 没有这张单子)。
static func on_finals_coins(t: Dictionary, res: Dictionary, done: Callable = Callable()) -> int:
	var err := str(res.get("err", ""))
	var n := -1
	if err == "no_bucket" or err == "not_in_match":
		n = finals_coins_settle(GameState, t, 0)   # 服务端说这一场与我无关: 销单(一枚不发)
	elif err == "" and str(res.get("status", "")) == "done":
		n = finals_coins_settle(GameState, t, int(res.get("coins", 0)))
		## 宝箱进度跟着这张单子一起记(只记一次: 单子已发过 ⇒ n = -1; 不是这一周的单子不记)
		if n >= 0 and int(t.get("week", 0)) == P2C.week_anchor_utc(int(P2C.now_utc())):
			var ch_c: bool = apply_chest(GameState, res.get("chest", {}))
			var in_c: bool = apply_incense(GameState, res.get("incense", {}))   # 093 香火石(2026-10-23), 同一张单子同一道闸
			if ch_c or in_c:
				GameState.save()
	else:
		return -1                             # 问不到 / 还没翻面: 留着下次
	if n > 0 and done.is_valid():
		done.call(n)
	if n >= 0:
		claim_finals_coins(done)              # 接着问下一张
	return n
