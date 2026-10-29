extends RefCounted
## 周六闯关 · 配上之后跟播自己这一局(2026-10-29 · 方案书 docs/plans/20261029c-闯关赛排队时可回主页.md §4.4~§4.6 B1~B7)。
## 用户 10-29「就跟lol观战一样呢」: 配上之后不在 VS 卡下干等「正在结算」, 裁判一开算(任务 claimed)就进战斗场看这一局的直播;
##   画面落后于服务器(服务器算得比 1 倍快), 结果播到最后才揭晓。
##
## 会话 referee_run(活在 root 上)按下面的时机调本文件; 本文件不持有节点, 只持有「离场后真记账」那一份(静态 ⇒ 沙盒还原碰不到)。
##   wanted()                   走不走跟播: 逐帧直播开着(StreamWatch.wanted)且不是陪练号跳过观看(RefereeWatch.skip_play)
##   lookup_seed(mid, cb)       任务 claimed ⇒ 问「正在算的裁判局」列表(referee_live_gauntlet)按录像号找种子(不改服务端, U9)
##   enter(tree, run, seed)     进战斗场跟播(StreamWatch.enter_own_live)。A 方: 左我右对手; B 方: 左对手右我、「我方」指右边
##   on_done(run, res)          算完: 在播放沙盒里**预演**记账(settle preview, 结算屏读到「打完之后」的数), 结果原地填进会话;
##                              真记账要的那一份存进 `_bill`, 等离场
##   on_failed(run, msg)        算失败 / 没这一单: 销单、结束播放回主菜单、主菜单飘那句话(与匹配屏那条同一句、同一个销单)
##   on_left(sess)              StreamWatch._left 在沙盒还原(end_play)之后调: 结果已到 ⇒ 真记账(落盘 / 战绩页 / 上传);
##                              没到 ⇒ 什么都不做(单子留给主菜单补记); 没看到结算屏就走了 ⇒ 主菜单飘「上一场闯关：胜利 / 失败」
## ★为什么不在沙盒里真记: 播放期间 GameState 是备份过的, 离场整份还原 ⇒ 沙盒里加的币 / 战绩离场就没了,
##   而单子已经清了 ⇒ 这一局的账永久丢失(R2)。所以沙盒里只预演, 真记账挪到离场之后。
## ★不会记两次: settle 只认单子上那个任务号, 记完单子就清(离场记账与主菜单补记谁先到谁记)。
## ★预演只在**这一局的沙盒里**做(`in_own`: 会话是这一局 且 GameState 有备份); 不在(玩家已离开跟播)⇒ 什么都不做, 单子留给主菜单。

const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")

## 收尾处「正在确认结果」最多等多久(秒; 协调约定 120 秒)。等满仍没有结果 ⇒ 回主菜单飘「稍后自动记入」, 单子留给主菜单补记
##   (会话可能已因跟播上限自删, 不能一直停在收尾处)。
const CONFIRM_MAX_SEC := 120.0
## 【门禁注入点】> 0 时替代 CONFIRM_MAX_SEC。默认 0 = 不生效; static ⇒ 活过场景切换 ⇒ 用完必须还原(同 `RefereeWatch.poll_max_for_test`)。
static var confirm_max_for_test := 0.0

## 算完那一份(离场后真记账用): {job_id, st: referee_job_status 回包}; 没有 = {}。
static var _bill: Dictionary = {}
## on_failed 在沙盒里销了单(存盘空转)⇒ 离场还原后补存一次。
static var _dirty := false
## 观测量(门禁分母)
static var lookups := 0
static var enters := 0
static var previews := 0
static var settles := 0
static var fails := 0


static func wanted() -> bool:
	return SW.wanted() and not RW.skip_play


static func confirm_max_sec() -> float:
	return confirm_max_for_test if confirm_max_for_test > 0.0 else CONFIRM_MAX_SEC


## 任务 claimed ⇒ 问「正在算的裁判局」列表找这一局的种子。`cb.call(seed: int)` 恰好一次; 找不到 / 问不到 ⇒ -1。
##   没配后端(请求发不出去)⇒ 当场同步回 -1。
static func lookup_seed(match_id: String, cb: Callable) -> void:
	lookups += 1
	var sent: bool = RW.RN.live_gauntlet_async(func(res: Dictionary) -> void:
		if cb.is_valid():
			cb.call(seed_in(res, match_id)))
	if not sent and cb.is_valid():
		cb.call(-1)


## 纯函数: 列表回包(`RefereeNet.parse_live`)里录像号 = `match_id` 那一行的种子; 没有 ⇒ -1。
static func seed_in(res: Dictionary, match_id: String) -> int:
	if not RW.SB.is_uuid(match_id) or not (res.get("rows", null) is Array):
		return -1
	for r in (res["rows"] as Array):
		if r is Dictionary and str((r as Dictionary).get("match_id", "")) == match_id:
			var s := int((r as Dictionary).get("seed", 0))
			return s if s > 0 else -1
	return -1


## 纯函数: 跟播自己这一局时左右两边的名字(`ReplayRecorder.play_names`)。直接交给看录像那条的 `RefereeWatch.watch_names`
##   (谁能给出 side = b 只住在那一处, verify_gauntlet_online_queue V 段静态钉着):
##   A ⇒ {}(左 = 看的人自己, 右 = 对手卡的名字: enter_own_live 把对手卡放进开局状态 dual_ghost);
##   B ⇒ {l: 对手, r: 我, side: b}(「我方」指右边, `ReplayRecorder.viewer_side`); 名字拼不出来 ⇒ {}(与看录像那条一样)。
static func names_for(side: String, foe: Dictionary) -> Dictionary:
	var pf = foe.get("profile", null)
	return RW.watch_names({"side": side, "foe_name": str((pf as Dictionary).get("name", "")) if pf is Dictionary else ""})


## 进战斗场跟播。返回 true = 已进(会话据此进 ST_LIVE); false = 没进(开关关 / 陪练号 / 种子或任务号不对 / 版本不同), 会话照旧等。
##   `src` = 会话在 VS 卡上已经拉了开播那几块的块来源(`SW.own_live_source`); null ⇒ 进场时现建。
static func enter(tree: SceneTree, run: Node, seed: int, src: StreamSource.Http = null) -> bool:
	if run == null or not is_instance_valid(run) or not wanted() or seed <= 0:
		return false
	var opp = run.get("opp")
	var foe: Dictionary = (opp as Dictionary).duplicate(true) if opp is Dictionary else {}
	var jid := int(run.get("job_id"))
	var w := SW.enter_own_live(tree, {"id": str(run.get("match_id")), "seed": seed, "ver": ReplayRecorder.client_version(),
		"job_id": jid, "foe": foe, "src": src}, RW.MAIN_MENU, names_for(str(run.get("side")), foe))
	if w != "":
		return false
	_bill = {}
	_dirty = false
	enters += 1
	return true


## 现在是不是正在这一局的跟播沙盒里(会话是自己那一局、任务号对得上、GameState 有备份)。
static func in_own(job_id: int) -> bool:
	var c: Dictionary = SW.current
	return job_id > 0 and bool(c.get("own", false)) and int(c.get("job_id", -1)) == job_id and ReplayRecorder._has_backup


## 算完(会话拿到 done 那份回包): 沙盒里预演记账, 结果原地填进会话(守卫与 HUD 拿的是同一个字典); 真记账那一份留到离场。
static func on_done(run: Node, status_res: Dictionary) -> void:
	if run == null or not is_instance_valid(run):
		return
	var jid := int(run.get("job_id"))
	if not in_own(jid):
		return                            # 玩家已离开跟播: 不预演(不在沙盒里), 单子留给主菜单补记
	var v := RW.settle(GameState, jid, status_res, true)
	if v.is_empty():
		## 不是这一单 / 上一周的 / 结果不明: 结算屏照服务器的胜负出, 奖励 0(与匹配屏那条同一个兜底)
		var gw := int(status_res.get("gw", -1))
		var gl := int(status_res.get("gl", -1))
		v = {"won": int(status_res.get("won", 0)) == 1, "reward": 0,
			"gw": gw if gw >= 0 else int(GameState.gauntlet_wins), "gl": gl if gl >= 0 else int(GameState.gauntlet_losses)}
	if str(run.get("side")) == "b":
		var opp = run.get("opp")
		var pf = (opp as Dictionary).get("profile", null) if opp is Dictionary else null
		v["side"] = "b"
		v["foe_name"] = str((pf as Dictionary).get("name", "")) if pf is Dictionary else ""
	_bill = {"job_id": jid, "st": status_res.duplicate(true)}
	previews += 1
	var r = SW.current.get("result", null)
	if r is Dictionary:
		(r as Dictionary).merge(v, true)
	else:
		SW.current["result"] = v


## 算失败 / 服务端没这一单: 销单(与匹配屏那条一致), 跟播中 ⇒ 结束播放回主菜单, 主菜单飘 `msg`。
static func on_failed(run: Node, msg: String) -> void:
	var jid := int(run.get("job_id")) if run != null and is_instance_valid(run) else -1
	var own := in_own(jid)
	_bill = {}
	var p = GameState.referee_pending
	if jid > 0 and p is Dictionary and int((p as Dictionary).get("job_id", -1)) == jid:
		GameState.referee_pending = {}    # referee_pending 不进播放备份 ⇒ 离场还原不会把它改回来
		GameState.save()                  # 沙盒里存盘空转 ⇒ 离场后 on_left 再存一次
		_dirty = true
	fails += 1
	if not own:
		return
	if msg != "":
		RW.notice = msg
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		SceneNav.go(tree, RW.MAIN_MENU)


## 收尾处等结果等满 `confirm_max_sec()`: 回主菜单, 主菜单飘「稍后自动记入」(单子留着, 主菜单补记)。battle_hud 调。
static func confirm_timeout(tree: SceneTree) -> void:
	RW.notice = RW.TXT_LATER
	if tree != null:
		SceneNav.go(tree, RW.MAIN_MENU)


## StreamWatch._left(沙盒已还原)调。结果已到 ⇒ 真记账; 没看到结算屏 ⇒ 主菜单飘结果那一句。结果没到 ⇒ 不动。
static func on_left(sess: Dictionary) -> void:
	if ReplayRecorder._has_backup:
		return                            # 还在某个沙盒里(不该发生): 不记, 单子留给主菜单补记
	if _dirty:
		_dirty = false
		GameState.save()
	var jid := int(sess.get("job_id", -1))
	if _bill.is_empty() or int(_bill.get("job_id", -1)) != jid:
		return                            # 结果还没到: 单子留着(主菜单补记)
	var st: Dictionary = _bill["st"]
	_bill = {}
	var v := RW.settle(GameState, jid, st)
	if v.is_empty():
		return                            # 已经记过(不是这一单)
	settles += 1
	if not bool(sess.get("shown", false)):
		RW.notice = RW.resume_text(v)
		RW.resumed_view = v                 # 主菜单据此补演晋级仪式（第 4 胜）；`_on_referee_resumed` 会把上面那句换成仪式后的同一句
