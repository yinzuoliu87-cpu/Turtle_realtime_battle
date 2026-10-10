extends Node
## verify_replay_roundtrip.gd — 回放 S1: 本机录、本机播, 逐步一致(方案书 docs/plans/20261003-跨设备回放.md §6)
##
## 用户 2026-10-03:「我希望……我能在其他设备上看到比赛回放」。第一步只做「本机录、本机播」:
##   真实交互对局(**非 det 模式**、帧长乱跳、有人点幕布/拖站位/按开打/认输)
##   → 录一份记录 → 把 GameState 改成另一份 → 照记录重算 → **每一个 sim 步**的全场指纹都要和原局一样。
##
## ★这把尺子量的是「实战可复现」, 所以录制那一局必须是**交互模式**:
##   不设 TURTLE_SEED(`_deterministic` 为假) ⇒ 走固定步长累加器; 每帧喂的 delta 故意乱跳(一帧 0~3 步),
##   演出 tween / 对局协程都得真的挂在 sim 步上才对得上 —— 这正是 §4.1 ①A 改的东西。
##   播放那一遍换**另一组**帧长序列: 两遍帧切法不同, 指纹仍须逐步相同。
##
## 对应验收:
##   V1 实战可复现: 逐步指纹一致 + 产品自己的校验点一个不差 + 终局一致
##      反证: 种子改一位 / 一个站位挪 40 码 / 删掉那条认输 ⇒ 都必须停下(diverged_at ≥ 0)
##   V2 指纹不吃演出随机: 两遍的 `_juice_rng` 种子不同(分母), 指纹照样一致
##   V3 录制字段完整: 播之前把 GameState 改成另一份合法阵容, 并且**所有不在 STATE_KEYS 里的变量**都换成另一份 ⇒ 仍一致;
##      反证: 从记录里删掉 `persistent_equipped`(那件装备真的在场上) / `season_level` ⇒ 必须对不上
##   V3b 录像瘦身(2026-10-04): 录像 state 的键 ⊆ STATE_KEYS; 一串已知敏感字段(币/邮箱/令牌/设备 id/昵称/背包/装备池/
##      赛季战绩……)一个都不在录像里 —— 分母: 录制那一刻 GameState 里它们**都有值**; 未上场统领的持久装备不在录像里
##      (分母: GameState 里有); 判据函数自检: 往录像里塞回一个币 ⇒ 判据必须报出来。
##   V5 回放零副作用: 存档文件逐字节不变 / 战绩条数不变 / 不多录一份回放 / GameState 播完还原
##   V6 版本闸: 版本号不同 ⇒ `play()` 返回原因、不进战斗场、GameState 不动
##   V7 地图一致(2026-10-04「每场随机一张」): 正式对局的地图由战斗种子决定 ⇒ 播放那一遍的
##      `ArenaTheme.active` 必须与录制时同一张, 且不是 V0_BASE(已从正式对局退役)。
##      反向: 选图改成裸 randi ⇒ 录与播各掷一次, 3/4 概率换图 ⇒ 这条红(2026-10-04 实测红, 方案书 docs/plans/20261003-四版完整地图.md §6)。
##   V1b 引擎帧不走也一致(2026-10-04 修「约 40 次红 1 次 · 第 360 步校验点 5」):
##      播放时从「建场」到「开打后 40 帧」**一帧都不让引擎走**(连着调 `_process`、中间不 await)
##      ⇒ 物理帧一个都不推进(分母断言: 物理帧计数前后相等)。
##      根因: 寻路图(NavigationServer2D)默认**异步**, 建好之后要等下一个**物理帧**才生效,
##        而物理帧按墙钟走 ⇒ 开打头几步走直线还是绕障, 取决于那几帧真实花了多久。
##        回放摆位期 8 倍速快进, 建场到开打只隔约 5 帧 —— 机器快到这 5 帧不满 1/60 秒, 就分叉。
##      这一遍把「这几帧不满 1/60 秒」从运气造成必然: 修之前**必红**, 修之后必绿。
##   V8 斧头召唤物(2026-10-10): 096 的召唤物血/攻/档位按**本机** GameState 砍伐进度建(不在单位身上) ⇒ 录像必须带进度。
##      实测: 周六赛况板 92 场录像 37 场在斧头登场后的第一个校验点分叉(多为「第 660 步 校验点 10」)。
##      录制方带 096 + 非零进度; V3 篡改把本机进度 +7 ⇒ 不录就分叉。反证: 录像里删掉 axe_exp_total ⇒ 必须停下。
##
## ★分母: 录到的校验点数 > 0, 每类输入(fight / present / surrender)至少一条, 两路都开打过。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const TRACE := preload("res://tests/_gs_read_trace.gd")

## 两组不同的帧长序列(秒)。都含「一帧 0 步」(0.004)与「一帧 2~3 步」(0.04/0.05)。
const PAT_REC := [0.016, 0.004, 0.04, 0.0167, 0.025, 0.05, 0.009, 0.0333]
const PAT_PLAY := [0.05, 0.0167, 0.004, 0.03, 0.012, 0.0167, 0.045, 0.02]
const MAX_FRAMES := 30000
const AT := preload("res://scripts/gamedata/arena_theme.gd")
const EQ_ID := "p2eq_001"          # 录制方统领身上那件持久装备(V3 反证要删的就是它)
## V8(2026-10-10 周六赛况板 37 场「斧头登场后第一个校验点」分叉): 096 小木斧 —— 召唤物按本机砍伐进度建, 进度必须进录像。
const AXE_EQ := "p2eq_096"
## V3b: 录像里**绝不许**出现的 GameState 变量(录制时都摆上值, 当分母)。不是 STATE_KEYS 的反面清单 ——
##   判据主体是「键 ⊆ STATE_KEYS」, 这张只是把最要紧的几样点名, 让报错一眼看得懂。
const SENSITIVE := {
	"coins": 12345, "meta_deepsea_coins": 678, "account_email": "rec@example.invalid", "auth_refresh": "r-secret",
	"install_uid": "inst-secret", "nickname": "录制者", "inventory": ["p2eq_010"],
	"persistent_bench": [{"id": "p2eq_022", "star": 2}], "equip_pool": {"p2eq_030": 2},
	"season_wins": 9, "gauntlet_wins": 3, "gauntlet_losses": 1, "titles": ["t1"], "hearts": 2,
	"recent_ghost_ids": ["bot_3_1"],
}
const UNFIELDED := "ninja"         # 不在阵上的龟: 它的持久装备不许进录像

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _setup_gs(gs) -> void:
	gs.reset_dual_lane()
	gs.test_mode = false                     # ★V5 要量真存档: 门禁每个测试一份独立 user://
	gs.tutorial_active = false
	gs.week_phase = "gauntlet"               # 周六闯关赛(Q3 2026-10-05 用户改: 积分赛也录, 见 verify_replay_controls ①)
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "slot": 0, "id": "basic"},          # 不带 equips ⇒ 读 persistent_equipped
			{"kind": "minion", "role": "front", "equips": []},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []},
		],
	}
	gs.persistent_equipped = {"basic": [{"id": EQ_ID, "star": 3}, {"id": AXE_EQ, "star": 1}], UNFIELDED: [{"id": "p2eq_065", "star": 3}]}
	## ★V8(2026-10-10): 斧头召唤物的血/攻/档位读的是**本机** GameState 的砍伐进度(不在单位身上)。
	##   摆一份非零的进度 ⇒ V3 篡改(int +7)会把看的人那份变成另一个数 ⇒ 不录就第一只斧头登场那步分叉。
	gs.axe_exp_bar = 40
	gs.axe_exp_total = 150
	gs.axe_stage = 1
	gs.axe_final = ""
	for k in SENSITIVE:
		var v = SENSITIVE[k]
		if v is Array:
			(gs.get(k) as Array).assign(v)       # inventory 是 Array[String](带类型), 直接 set 一个无类型数组会被拒
		else:
			gs.set(k, v.duplicate(true) if v is Dictionary else v)
	gs.season_level = 4
	gs.trainer_skill = "hook"
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	gs.dual_ghost = Backend.make_bot(3, rng)
	gs.dual_active = true


## 把 GameState 改成**另一份合法**阵容(V3): 统领/站位/装备/等级/大师技能/对手全换。
func _tamper_gs(gs) -> void:
	gs.reset_dual_lane()
	gs.season_leaders = ["ninja", "dice", "pirate"]
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "ninja", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "dice", "equips": []},
			{"kind": "leader", "slot": 2, "id": "pirate", "equips": []}],
	}
	gs.persistent_equipped = {"basic": [{"id": "p2eq_065", "star": 1}]}
	gs.season_level = 9
	gs.axe_exp_bar = 3                       # V8: 看的人自己的砍伐进度(与录制时 40/150/1 不同)
	gs.axe_exp_total = 157
	gs.axe_stage = 2
	gs.trainer_skill = "whistle"
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	gs.dual_ghost = Backend.make_bot(20, rng)
	gs.week_phase = "ranked"
	gs.dual_active = true
	## ★V3 加强(2026-10-04 录像瘦身): 不在 STATE_KEYS 里的变量**全部**换成另一份 —— 看回放的那台设备
	##   上它们是什么值都不许影响结果。局内临时的几个摆成「上一局打完留下的」样子(泛型扰动对空容器无效)。
	var n := 0
	for p in gs.get_property_list():
		if (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var k := str(p.get("name", ""))
		## BACKUP_SKIP(令牌/设备身份/战绩/补报单/上传队列)播放前后都不碰, V5 要量它们「播完不变」, 这里也不扰动
		if k in ReplayRecorder.STATE_KEYS or k in ReplayRecorder.BACKUP_SKIP:
			continue
		var pv = _perturb(gs.get(k))
		if pv != null:
			gs.set(k, pv)
			n += 1
	gs.current_lane = "bottom"
	gs.egg_hp = {"left": 77, "right": 88}
	gs.lane_results = {"top": "right"}
	gs.dual_survivors = {"left": ["basic"], "right": []}
	gs.dual_ms_stacks = {"left": 9, "right": 9}
	gs.foe_loadouts = {"basic": 2}
	gs.tutorial = true
	_perturbed = n


var _perturbed := 0


## 泛型扰动: 换成同类型的另一个值(非空容器 → 空; 空容器/对象 → 不动)。
static func _perturb(v):
	match typeof(v):
		TYPE_BOOL: return not v
		TYPE_INT: return v + 7
		TYPE_FLOAT: return v + 0.37
		TYPE_STRING: return v + "_v"
		TYPE_ARRAY: return [] if not (v as Array).is_empty() else null
		TYPE_DICTIONARY: return {} if not (v as Dictionary).is_empty() else null
	return null


## V3b 判据: 录像 state 里的违规键(表外 / 敏感 / 未上场统领的装备)。空数组 = 干净。
static func _leaks(st: Dictionary) -> Array:
	var bad: Array = []
	for k in st:
		if not str(k) in ReplayRecorder.STATE_KEYS:
			bad.append("表外:" + str(k))
	for k in SENSITIVE:
		if st.has(k):
			bad.append("敏感:" + str(k))
	if (st.get("persistent_equipped", {}) as Dictionary).has(UNFIELDED):
		bad.append("未上场装备:" + UNFIELDED)
	return bad


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	## ★手跑也不许打真网络: project.godot 里填着真 Supabase 地址; 空白串 = 后端整层停用(与 run-tests.sh 同)
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	OS.set_environment("TURTLE_SEED", "")       # ★交互模式: 不许 det
	_setup_gs(gs)
	print("=== 录: 交互模式真实对局(帧长乱跳 + 人点幕布/拖站位/按开打/认输) ===")
	var rec_run: Dictionary = await _run(PAT_REC, true)
	var hist: Array = gs.match_history
	var rid: String = str((hist[0] as Dictionary).get("replay_id", "")) if not hist.is_empty() else ""
	_ok("分母 · 录制那一局是交互模式(_deterministic=false)", not bool(rec_run["det"]))
	_ok("分母 · 一帧跑过 0 步也跑过 ≥2 步(帧切法真的在乱跳)", int(rec_run["min_pf"]) == 0 and int(rec_run["max_pf"]) >= 2,
		"min %d / max %d" % [int(rec_run["min_pf"]), int(rec_run["max_pf"])])
	_ok("分母 · 这一局打完了(_dl_state=done)", str(rec_run["state"]) == "done", str(rec_run["state"]))
	_ok("★战绩行挂上了回放 id(record_match 接上了)", rid != "", rid)
	var rec: Dictionary = ReplayRecorder.load_record(rid) if rid != "" else {}
	_ok("★记录从 user://replays/ 读得回来", not rec.is_empty())
	if rec.is_empty():
		_finish()
		return
	var kinds := {}
	var fights := 0
	for e in rec["events"]:
		kinds[str(e["k"])] = int(kinds.get(str(e["k"]), 0)) + 1
	fights = int(kinds.get("fight", 0))
	_ok("分母 · 每类输入至少一条(fight=%d present=%d surrender=%d)" % [fights, int(kinds.get("present", 0)), int(kinds.get("surrender", 0))],
		fights >= 2 and int(kinds.get("present", 0)) >= 1 and int(kinds.get("surrender", 0)) == 1)
	_ok("分母 · 录到 %d 个校验点 > 0" % (rec["cps"] as Array).size(), (rec["cps"] as Array).size() > 0)
	_ok("分母 · 记录带版本号 = 本机版本", str(rec.get("client_version", "")) == ReplayRecorder.client_version())
	_ok("分母 · 站位被我拖过(开打时的站位 ≠ 出生点)", bool(rec_run["dragged"]))
	var raw_size: int = ReplayRecorder.encode(rec).size()
	print("  [量] 一局记录 %d 字节(deflate 后) · 事件 %d 条 · 校验点 %d 个 · 结束步 %d" % [
		raw_size, (rec["events"] as Array).size(), (rec["cps"] as Array).size(), int(rec["end"]["s"])])

	# ── V3b 录像瘦身: 录像里只有 STATE_KEYS, 敏感字段一个都没有 ──
	var full: Dictionary = rec.duplicate(true)
	full["state"] = ReplayRecorder.capture_all()
	var rst: Dictionary = rec["state"]
	print("  [量] 录像 state %d 个键 · 瘦身前(整份 GameState)%d 个键 —— 整局记录 %d 字节 vs 瘦身前 %d 字节" % [
		rst.size(), (full["state"] as Dictionary).size(), raw_size, ReplayRecorder.encode(full).size()])
	var den := 0
	for k in SENSITIVE:
		var gv = gs.get(k)
		if gv != null and str(gv) != "" and str(gv) != "0" and str(gv) != "[]" and str(gv) != "{ }" and str(gv) != "{}":
			den += 1
	_ok("分母 · 录制那一刻 %d/%d 个敏感字段在 GameState 里都有值、未上场的 %s 身上有装备" % [den, SENSITIVE.size(), UNFIELDED],
		den == SENSITIVE.size() and (gs.persistent_equipped as Dictionary).has(UNFIELDED))
	var leaks: Array = _leaks(rst)
	_ok("★★V3b 录像 state 只有 STATE_KEYS 里的键、没有敏感字段、没有未上场统领的装备", leaks.is_empty(), str(leaks))
	_ok("★V3b 上传那一份同样干净", _leaks(RU.for_upload(rec)["state"]).is_empty(), str(_leaks(RU.for_upload(rec)["state"])))
	_ok("分母 · 上场统领的装备还在录像里(裁的是未上场的, 不是全裁)",
		(rst.get("persistent_equipped", {}) as Dictionary).has("basic"))
	var doctored: Dictionary = rst.duplicate(true)
	doctored["coins"] = 12345
	_ok("★V3b 判据自检: 往录像里塞回一个「币」⇒ 判据报出来", not _leaks(doctored).is_empty(), str(_leaks(doctored)))
	var old_style: Dictionary = rec.duplicate(true)
	old_style["state"] = ReplayRecorder.capture_all()
	_ok("★V3b 瘦身之前录的老录像(整份存档)上传时也按表裁干净", _leaks(RU.for_upload(old_style)["state"]).is_empty()
		and not _leaks(old_style["state"]).is_empty(), str(_leaks(RU.for_upload(old_style)["state"])))

	# ── V5 基线: 播之前的存档 / 战绩 / 回放目录 ──
	var save0: PackedByteArray = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	_ok("分母 · 录制那一局真的写过存档(否则 V5 的「字节不变」是空检查)", save0.size() > 0, "%d 字节" % save0.size())
	var hist_n0: int = (gs.match_history as Array).size()
	var rp_n0: int = _count_replays()
	var q0: PackedByteArray = var_to_bytes(gs.replay_upload_pending)
	_ok("S2 录像里不带上传队列(不然每份录像都背着前几份的单子, 播放时还会被它覆盖)",
		not (rec["state"] as Dictionary).has("replay_upload_pending") and (rec["state"] as Dictionary).has("dual_ghost"))
	_ok("分母 · 录制那一局进了上传队列(S2; V5 的「队列不变」才不是空检查)",
		(gs.replay_upload_pending as Array).size() >= 1 and str((gs.replay_upload_pending as Array)[-1].get("id", "")) == rid)

	# ── S2: 播的是**上传用的那一份**(摘掉了会让人认出机器人的字段)——别的设备拿到的就是它 ──
	var fg: Dictionary = (rec["state"] as Dictionary).get("dual_ghost", {})
	_ok("分母 · 录制时的对手确实带着机器人标记(is_bot / bot_ 开头的 ghost_id)",
		bool(fg.get("is_bot", false)) and str(fg.get("ghost_id", "")).begins_with("bot_"), str(fg.get("ghost_id", "")))
	var up_rec: Dictionary = RU.for_upload(rec)
	var ufg: Dictionary = (up_rec["state"] as Dictionary).get("dual_ghost", {})
	_ok("★S2 上传那一份里没有机器人标记", not ufg.has("is_bot") and not ufg.has("ghost_id") and ufg.size() > 0,
		str(ufg.keys()))

	# ── V3: 播之前把 GameState 改成另一份 ──
	_tamper_gs(gs)
	var tampered: Dictionary = ReplayRecorder.capture_all()
	_ok("分母 · V3 播之前把 %d 个表外变量换成了另一份(≥70; 其余是空容器/对象, 泛型扰动不了)" % _perturbed, _perturbed >= 70)
	var tm0: bool = bool(gs.test_mode)

	print("=== 播: GameState 已改成另一份, 换一组帧长重算(播上传用的那一份) ===")
	ReplayRecorder.begin_play(up_rec)
	var play: Dictionary = await _run(PAT_PLAY, false)
	_ok("★★V1 播放全程没有一个校验点对不上(diverged_at=%d %s)" % [int(play["div"]), str(play["why"])], int(play["div"]) < 0)
	var n_real_cp := 0
	for h in rec["cps"]:
		if str(h) != ReplayRecorder.PLACE_CP: n_real_cp += 1
	_ok("★V1 产品自己比过 %d 个校验点(= 录到的非摆位校验点 %d 个)" % [int(play["cps"]), n_real_cp],
		int(play["cps"]) == n_real_cp and n_real_cp > 0)
	_ok("★V1 回放也结算在同一步、同一个结局(finished)", bool(play["finished"]) and str(play["state"]) == "done")
	var cmp: Array = _compare(rec_run["fps"], play["fps"], int(rec["end"]["s"]))
	_ok("★★★V1 逐 sim 步全场指纹一致: %d/%d 步分叉(首个 %d)" % [int(cmp[0]), int(cmp[1]), int(cmp[2])],
		int(cmp[0]) == 0 and int(cmp[1]) >= int(rec["end"]["s"]) / 2, str(cmp[3]))
	_ok("★V2 两遍的演出随机种子不同(%d / %d)而指纹一致" % [int(rec_run["juice"]), int(play["juice"])],
		int(rec_run["juice"]) != int(play["juice"]) and int(cmp[0]) == 0)
	_ok("分母 · 回放那一遍一帧也跑过 0 步与 ≥2 步", int(play["min_pf"]) == 0 and int(play["max_pf"]) >= 2)
	_ok("★★V7 回放那一遍的地图 == 录制时那张(%s / %s), 且是种子算出的那张" % [str(rec_run["theme"]), str(play["theme"])],
		str(rec_run["theme"]) == str(play["theme"]) and str(play["theme"]) == AT.theme_for_seed(int(rec["seed"])),
		"种子 %d → %s" % [int(rec["seed"]), AT.theme_for_seed(int(rec["seed"]))])
	_ok("★V7 正式对局的地图不是 V0_BASE(已退役) —— 在四张池里", AT.MATCH_POOL.has(str(rec_run["theme"])), str(rec_run["theme"]))
	## ── V8 斧头召唤物(096)按本机砍伐进度建 ⇒ 进度必须录进去 ──
	var axe_steps := 0
	for k in rec_run["fps"]:
		if str(rec_run["fps"][k]).contains("/_summon_axe/"):
			axe_steps += 1
	_ok("分母 · V8 录制那一局斧头召唤物真的上场了(%d 步指纹里有它)" % axe_steps, axe_steps > 0)
	_ok("分母 · V8 看的人那份砍伐进度与录制时不同(本机 %d / 录像 %s)" % [int(gs.axe_exp_total), str((rec["state"] as Dictionary).get("axe_exp_total", "缺"))],
		int(gs.axe_exp_total) == 157 and int(gs.axe_stage) == 2)
	_ok("★★V8 录像里带着砍伐进度(axe_exp_total / axe_stage / axe_exp_bar / axe_final)",
		(rec["state"] as Dictionary).get("axe_exp_total", -1) == 150 and (rec["state"] as Dictionary).get("axe_stage", -1) == 1
		and (rec["state"] as Dictionary).get("axe_exp_bar", -1) == 40 and (rec["state"] as Dictionary).has("axe_final"))

	# ── V1b: 建场 → 开打后 40 帧, 引擎一帧都不走(物理帧不推进) ──
	print("=== 播(V1b): 从建场到开打后 40 帧, 引擎一帧都不走 ===")
	ReplayRecorder.begin_play(rec)
	var hold: Dictionary = await _run(PAT_PLAY, false, true)
	_ok("分母 · V1b 那段窗口里物理帧真的一个没走(建场后 %d / 开打后 40 帧 %d)" % [int(hold["pf_a"]), int(hold["pf_b"])],
		int(hold["pf_a"]) >= 0 and int(hold["pf_b"]) == int(hold["pf_a"]))
	_ok("★★V1b 引擎帧不走 ⇒ 播放全程校验点仍一个不差(diverged_at=%d %s)" % [int(hold["div"]), str(hold["why"])],
		int(hold["div"]) < 0 and int(hold["cps"]) == n_real_cp)
	var cmp_h: Array = _compare(rec_run["fps"], hold["fps"], int(rec["end"]["s"]))
	_ok("★★V1b 逐 sim 步全场指纹一致: %d/%d 步分叉(首个 %d)" % [int(cmp_h[0]), int(cmp_h[1]), int(cmp_h[2])],
		int(cmp_h[0]) == 0 and int(cmp_h[1]) >= int(rec["end"]["s"]) / 2, str(cmp_h[3]))

	# ── V5 回放零副作用 ──
	_ok("★V5 播完 GameState 还原成播之前那一份(篡改后的那份)", _same(ReplayRecorder.capture_all(), tampered))
	_ok("★V5 test_mode 还原(%s)" % str(gs.test_mode), bool(gs.test_mode) == tm0)
	_ok("★V5 存档文件逐字节不变", FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == save0)
	_ok("★V5 战绩条数不变(%d)" % (gs.match_history as Array).size(), (gs.match_history as Array).size() == hist_n0)
	_ok("★V5 没有多录一份回放(%d)" % _count_replays(), _count_replays() == rp_n0)
	_ok("★V5 上传队列不变(播放既不入队、也没被记录里的那份覆盖)", var_to_bytes(gs.replay_upload_pending) == q0)

	# ── V6 版本闸 ──
	var old: Dictionary = rec.duplicate(true)
	old["client_version"] = "0.0.1"
	var why: String = ReplayRecorder.play(null, old)
	_ok("★V6 版本号不同 ⇒ 不播并说明原因", why != "" and why.contains("版本"), why)
	_ok("★V6 不播时没挂上待播、GameState 没被动", ReplayRecorder.pending_play.is_empty() and _same(ReplayRecorder.capture_all(), tampered))

	# ── V3c 回放那一遍实际读了 GameState 的哪些变量(运行时给每个变量补 getter 记读)──
	##   必须 ⊆ STATE_KEYS ∪ PLAY_READS_NOT_RECORDED。这是 STATE_KEYS 的**来源**(方案书 §9.5), 每次门禁重新量一遍。
	print("=== V3c: 量回放读了哪些 GameState 变量 ===")
	var tr = TRACE.new()
	var terr: String = tr.install(gs)
	_ok("分母 · 读记录器装上了(补 getter 的变量 %d 个)" % tr.var_names.size(), terr == "" and tr.var_names.size() >= 100, terr)
	ReplayRecorder.begin_play(up_rec)
	tr.begin(gs)
	var tp: Dictionary = await _run(PAT_PLAY, false, false, tr, gs)
	tr.uninstall(gs)
	var reads: Dictionary = tp.get("reads", {})
	var rk: Array = reads.keys()
	rk.sort()
	print("  [量] 回放那一遍读过 %d 个 GameState 变量: %s" % [rk.size(), str(rk)])
	var unrec: Array = []
	for k in rk:
		if not k in ReplayRecorder.STATE_KEYS and not k in ReplayRecorder.PLAY_READS_NOT_RECORDED:
			unrec.append(k)
	_ok("分母 · 装着读记录器那一遍也播完了、没分叉(diverged_at=%d)" % int(tp["div"]), int(tp["div"]) < 0 and bool(tp["finished"]))
	_ok("分母 · 读记录器真的记到了(≥12 个, 且含 persistent_equipped / dual_ghost / season_level)",
		rk.size() >= 12 and reads.has("persistent_equipped") and reads.has("dual_ghost") and reads.has("season_level"), str(rk.size()))
	_ok("★★V3c 回放读到的 GameState 变量全在 STATE_KEYS ∪ PLAY_READS_NOT_RECORDED 里", unrec.is_empty(),
		"表外被读: " + str(unrec))

	# ── 反证: 每一条都必须让播放停下 ──
	print("=== 反证(每条都必须停下) ===")
	var r1: Dictionary = rec.duplicate(true)
	r1["seed"] = int(r1["seed"]) ^ 1
	await _reverse("V1-① 种子改一位", r1)
	var r2: Dictionary = rec.duplicate(true)
	for e in r2["events"]:
		if str(e["k"]) == "fight":
			for p in e["p"]:
				if str(p[1]) == "left" and not str(p[0]).begins_with("__"):
					p[2] = (p[2] as Vector2) + Vector2(-40.0, 0.0)
					break
			break
	await _reverse("V1-② 第一路开打时一个站位挪 40 码", r2)
	var r3: Dictionary = rec.duplicate(true)
	var evs: Array = []
	for e in r3["events"]:
		if str(e["k"]) != "surrender":
			evs.append(e)
	r3["events"] = evs
	await _reverse("V1-③ 删掉那条认输", r3)
	var r4: Dictionary = rec.duplicate(true)
	(r4["state"] as Dictionary).erase("persistent_equipped")
	await _reverse("V3 记录里删掉 persistent_equipped(那件装备真的在场上)", r4)
	var r5: Dictionary = rec.duplicate(true)
	(r5["state"] as Dictionary).erase("season_level")
	await _reverse("V3 记录里删掉 season_level(本机是 9, 录制时是 4)", r5)
	var r6: Dictionary = rec.duplicate(true)
	(r6["state"] as Dictionary).erase("axe_exp_total")
	await _reverse("V8 记录里删掉 axe_exp_total(本机 157, 录制时 150 ⇒ 斧头血差 35)", r6)
	_finish()


func _reverse(name: String, r: Dictionary) -> void:
	ReplayRecorder.begin_play(r)
	var res: Dictionary = await _run(PAT_PLAY, false)
	_ok("★反证 · %s ⇒ 必须停下(diverged_at=%d · %s)" % [name, int(res["div"]), str(res["why"])], int(res["div"]) >= 0)


## 跑一局。rec=true 时扮演玩家(点幕布/拖站位/按开打/第二路打一会儿认输)。
## hold=true(V1b): 从第一路预览期到开打后 40 帧不 await 引擎帧 ⇒ 这段里物理帧一个都不走。
func _run(pat: Array, as_player: bool, hold: bool = false, tr = null, gs = null) -> Dictionary:
	var s = RB.new()
	add_child(s)
	s.set_process(false)          # 帧长由我喂(交互模式的累加器照常工作, 只是帧切法受控)
	var fps := {}
	s.sim_stepped.connect(func() -> void: fps[int(s._sim_step_n)] = ReplayRecorder.fingerprint(s))
	await get_tree().process_frame
	var juice: int = int(s._juice_rng.seed)
	var det: bool = bool(s._deterministic)
	var st_frames := 0
	var last_state := ""
	var fights := 0
	var present_clicked := 0
	var surrendered := false
	var dragged := false
	var min_pf := 99
	var max_pf := 0
	var done_frames := 0
	var pf_a := -1                 # V1b: 第一路建场之后(第一次看到摆位/开打)的物理帧计数
	var pf_b := -1                 # V1b: 第一路开打后第 40 帧的物理帧计数
	var i := 0
	while i < MAX_FRAMES:
		var st: String = str(s._dl_state)
		if st != last_state:
			last_state = st
			st_frames = 0
		st_frames += 1
		if as_player:
			if (st == "overview" or st == "lane_settle") and st_frames == 9:
				s._dl_sys._dl_present_click()            # 人点掉幕布(真入口: 幕布 gui_input 调的就是它)
				present_clicked += 1
			elif st == "place" and st_frames == 6:
				for u in s._units:                        # 人拖一只我方龟(真入口写的就是 _dl_clamp_place 的结果)
					if str(u.get("side", "")) == "left" and s._can_place_drag(u):
						var p0: Vector2 = u["pos"]
						u["pos"] = s._dl_sys._dl_clamp_place(p0 + Vector2(-70.0, 30.0 + 20.0 * fights))
						dragged = dragged or (u["pos"] as Vector2) != p0
						break
			elif st == "place" and st_frames == 25 and is_instance_valid(s._dl_go_btn):
				s._dl_go_btn.pressed.emit()               # 人按「开打」
				fights += 1
			elif st == "fight" and fights >= 2 and st_frames == 300 and not surrendered:
				s._do_surrender()                          # 第二路打一会儿认输(真入口: 确认钮调的就是它)
				surrendered = true
		var before: int = int(s._sim_step_n)
		s._process(float(pat[i % pat.size()]))
		var st2: String = str(s._dl_state)
		if hold and pf_a < 0 and (st2 == "place" or st2 == "fight"):
			pf_a = Engine.get_physics_frames()
		if hold and pf_a >= 0 and pf_b < 0 and st == "fight" and st2 == "fight" and st_frames >= 40:
			pf_b = Engine.get_physics_frames()
		var holding: bool = hold and pf_b < 0 and (st == "preview" or st2 == "preview" or pf_a >= 0)
		if not holding:
			await get_tree().process_frame
		var stepped: int = int(s._sim_step_n) - before
		if str(s._dl_state) == "fight":
			min_pf = mini(min_pf, stepped)
			max_pf = maxi(max_pf, stepped)
		i += 1
		if s._replay.diverged_at >= 0:
			break
		if str(s._dl_state) == "done":
			done_frames += 1
			if done_frames > 30:
				break
	var out := {"fps": fps, "juice": juice, "det": det, "state": str(s._dl_state), "theme": AT.active,
		"div": int(s._replay.diverged_at), "why": str(s._replay.diverge_why),
		"cps": int(s._replay.cp_checked), "finished": bool(s._replay.finished),
		"min_pf": min_pf, "max_pf": max_pf, "dragged": dragged, "frames": i, "pf_a": pf_a, "pf_b": pf_b}
	if tr != null:
		out["reads"] = tr.end(gs)          # V3c: 窗口 = 建场 → 打完(不含离场还原)
	for _g in range(10):
		await get_tree().process_frame
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	return out


func _compare(a: Dictionary, b: Dictionary, end_s: int) -> Array:
	var bad := 0
	var n := 0
	var first := -1
	var det := ""
	for k in range(1, end_s + 1):
		if not a.has(k) or not b.has(k):
			continue
		## 摆位屏上是人还在拖的中间态(不进对局; 开打那一刻的站位由 fight 事件逐个比对) ⇒ 不比
		if str(a[k]).contains("|place|") or str(b[k]).contains("|place|"):
			continue
		n += 1
		if str(a[k]) != str(b[k]):
			bad += 1
			if first < 0:
				first = k
				var sa: PackedStringArray = str(a[k]).split("|")
				var sb: PackedStringArray = str(b[k]).split("|")
				for j in range(mini(sa.size(), sb.size())):
					if sa[j] != sb[j]:
						det = "%s ≠ %s" % [sa[j], sb[j]]
						break
	return [bad, n, first, det]


func _same(x: Dictionary, y: Dictionary) -> bool:
	return var_to_bytes(x) == var_to_bytes(y)


func _count_replays() -> int:
	var d := DirAccess.open(ReplayRecorder.SAVE_DIR)
	if d == null:
		return 0
	return d.get_files().size()


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 回放 S1 本机录/本机播 逐步一致 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
