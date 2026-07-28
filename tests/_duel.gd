extends Node
## _duel.gd — 【龟×技能 胜率统计器】无装备下 84 个组合的全循环赛
##
## 用户 2026-07-28:「我需要你把这个技能胜率统计器做成好的工具，方便未来改技能后也能统计新的排行情况」
## 方案书: docs/plans/20260728-无装备龟技能平衡-机器人论衡.md
##
## ══ 它测什么 ══
##   84 个【龟 × 技能】组合 = 28 龟 × 3选1 主动技(skillPool[1..3]; [0]是普攻固定不可换)。
##   一只龟带不同技能是不同的强度 → 测量单位是组合, 不是龟。
##
## ══ 赛制 ══
##   全循环 R=1: 84×83/2 = 3486 对, 每对打一场。每个组合打 83 场(对手=其余全部)。
##   ★一场记两笔(左赢=左组合+1胜、右组合+1负) → 3486 场喂饱 84×83=6972 笔。
##   左右由固定种子随机分配 → 每组合约一半在左一半在右, 先手偏差在自己的胜率里平掉。
##
## ══ 单场结构 ══
##   上路(测的就是这条): [被测龟·带指定技能] + 近战小将 ×2      ← 小将无技能无被动 = 中性陪跑
##   下路(纯填充·双方完全相同): [填充龟1] [填充龟2] + 小将 ×1   ← 只为满足"恰好3统领"的结构校验
##   判定: 只读 lane_results["top"], 上路一分胜负立即结束 → 机时约减半
##   固定条件: 无装备 / 赛季 Lv5 / 关训龟大师 / 双方配置完全一致
##
## ══ 跑法 ══
##   单进程:
##     SHIP=1 DL_AUTOFIGHT=1 TURTLE_SEED=20260728 \
##     <godot> --headless --audio-driver Dummy --path . res://tests/_duel.tscn
##   8 并行(推荐; 每片跑 3486/8 对):
##     for i in 0..7: DUEL_SHARD=$i DUEL_SHARDS=8 DUEL_OUT=res://tools/duel/s$i ... &
##
## ══ 环境变量 ══
##   DUEL_SHARD / DUEL_SHARDS  分片(默认 0/1 = 不分片)。按对子下标取模, 各片互不重叠
##   DUEL_LEVEL                赛季等级(默认 5) —— 影响龟主属性 +5%/级、攻速 +2%/级, 双方同级
##   DUEL_LIMIT                只跑前 N 对(默认 0=全部) —— 探针/标定用
##   DUEL_OUT                  输出目录(默认 res://tools/duel)
##   TURTLE_SEED               战斗与左右分配的种子。★换种子重跑 = 检验结论对 RNG 是否稳健
##
## ══ 产出 ══
##   <DUEL_OUT>/duel-<shard>.csv  逐场: 左组合/右组合/谁赢/帧数/双方技能释放次数
##   汇总由 tools/duel_report.py 读 CSV 生成(报表与对局分离 → 换排序/加列不必重跑)
##
## ★不进门禁: 下划线前缀, run-tests.sh 只自动发现 verify_*.gd
## ★不写玩家存档: GameState.test_mode + backend.save_pool 守卫

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

const FRAME_CAP := 40000        # 单场帧上限(det模式 1帧=1/60秒 → 667游戏秒, 远超单路)
const SKILL_IDXS := [1, 2, 3]   # 候选主动技下标; [0] 是普攻, 固定不可换

var _rng := RandomNumberGenerator.new()
var _combos: Array = []         # [{turtle, sidx, skill_name}]
var _fillers: Array = []        # 两只填充龟(下路, 不参与判定)
var _rows: Array = []
var _shard := 0
var _shards := 1
var _level := 5


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	var dr = get_node_or_null("/root/DataRegistry")
	if gs == null or dr == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true

	var st := OS.get_environment("TURTLE_SEED")
	_rng.seed = int(st) if st.is_valid_int() else 20260728
	_shard = int(OS.get_environment("DUEL_SHARD")) if OS.get_environment("DUEL_SHARD").is_valid_int() else 0
	_shards = maxi(1, int(OS.get_environment("DUEL_SHARDS")) if OS.get_environment("DUEL_SHARDS").is_valid_int() else 1)
	_level = int(OS.get_environment("DUEL_LEVEL")) if OS.get_environment("DUEL_LEVEL").is_valid_int() else 5
	var limit := int(OS.get_environment("DUEL_LIMIT")) if OS.get_environment("DUEL_LIMIT").is_valid_int() else 0

	# ── 造 84 个组合 ──
	for p in dr.launch_pets:
		var pd: Dictionary = p
		var pool: Array = pd.get("skillPool", [])
		for si in SKILL_IDXS:
			if si < pool.size():
				_combos.append({
					"turtle": str(pd["id"]),
					"tname": str(pd.get("name", pd["id"])),
					"sidx": si,
					"sname": str((pool[si] as Dictionary).get("name", "?")),
					"stype": str((pool[si] as Dictionary).get("type", "")),
				})
	# ── 填充龟: 取【不在被测集合里也无所谓】的两只, 固定用前两只, 双方完全相同 ──
	#    它们只在下路, 下路不参与判定 → 选谁都不影响结果, 固定是为了可复现。
	var all_ids: Array = []
	for p in dr.launch_pets:
		all_ids.append(str((p as Dictionary)["id"]))
	_fillers = [all_ids[0], all_ids[1]]

	# ── 全部对子 ──
	var pairs: Array = []
	for i in range(_combos.size()):
		for j in range(i + 1, _combos.size()):
			pairs.append([i, j])
	var mine: Array = []
	for k in range(pairs.size()):
		if k % _shards == _shard:
			mine.append(pairs[k])
	if limit > 0 and mine.size() > limit:
		mine = mine.slice(0, limit)

	print("=== 龟×技能 胜率统计器 ===")
	print("  组合 %d 个 (28龟 × 3技) | 全部对子 %d | 本片(%d/%d) %d 对" % [
		_combos.size(), pairs.size(), _shard, _shards, mine.size()])
	print("  赛季等级 Lv%d | 填充龟(下路·不判定) %s | 种子 %d" % [_level, str(_fillers), int(_rng.seed)])
	if _combos.size() != 84:
		print("  ⚠ 组合数不是 84 —— 龟数或技能池变了, 表的规模会随之变")

	var t0 := Time.get_ticks_msec()
	for k in range(mine.size()):
		await _fight(gs, mine[k][0], mine[k][1], k)
		if k > 0 and k % 50 == 0:
			var el := float(Time.get_ticks_msec() - t0) / 1000.0
			print("  …%d/%d 对  %.1f 秒/场  预计剩余 %.1f 分钟" % [
				k, mine.size(), el / float(k), el / float(k) * float(mine.size() - k) / 60.0])
	var elapsed := float(Time.get_ticks_msec() - t0) / 1000.0
	_write(elapsed)
	get_tree().quit(0)


## 打一场: a 与 b 两个组合, 左右由种子决定
func _fight(gs, ia: int, ib: int, k: int) -> void:
	var ca: Dictionary = _combos[ia]
	var cb: Dictionary = _combos[ib]
	# 左右分配: 用 (对子下标 + 种子) 决定, 可复现且大致均衡
	var a_left: bool = ((k * 2654435761 + int(_rng.seed)) % 2) == 0
	var L: Dictionary = ca if a_left else cb
	var R: Dictionary = cb if a_left else ca

	_setup_left(gs, L)
	gs.dual_ghost = _ghost_of(R)

	var s = RB.new()
	add_child(s)
	if k == 0:
		await get_tree().process_frame
		await get_tree().process_frame
		_dump_setup(s)     # 首场体检: 上路结构与无装备必须属实(阵容被校验打回会静默变 2 统领)
	var fr := 0
	# 技能释放计数: 放技时会写 u["skill_cd"][stype] = 满冷却(主文件 2383/2390/2398),
	# 所以【冷却值变大 = 刚放了一次】。逐帧采样, 不碰产品代码、不依赖任何 tween。
	var casts := {"left": 0, "right": 0}
	var prev := {"left": 0.0, "right": 0.0}
	var lt := str(L["stype"])
	var rt := str(R["stype"])
	# ★只等上路出结果 —— 不打下路/终极, 机时约减半
	while fr < FRAME_CAP and not (gs.lane_results as Dictionary).has("top"):
		await get_tree().process_frame
		fr += 1
		for u in s._units:
			if u.get("_isMinion", false) or u.get("is_trainer", false) or u.get("_isEgg", false):
				continue
			var sd := str(u.get("side", ""))
			if not casts.has(sd):
				continue
			var want := lt if sd == "left" else rt
			if str(u.get("id", "")) != str((L if sd == "left" else R)["turtle"]):
				continue
			var cd: float = float((u.get("skill_cd", {}) as Dictionary).get(want, 0.0))
			if cd > float(prev[sd]) + 0.01:
				casts[sd] = int(casts[sd]) + 1
			prev[sd] = cd
	var top: String = str((gs.lane_results as Dictionary).get("top", ""))
	s.queue_free()
	for _g in range(6):
		await get_tree().process_frame

	if top == "":
		_rows.append({"l": L, "r": R, "win": "timeout", "fr": fr, "lc": 0, "rc": 0})
		return
	_rows.append({
		"l": L, "r": R, "win": ("L" if top == "left" else "R"), "fr": fr,
		"lc": int(casts.get("left", 0)), "rc": int(casts.get("right", 0)),
	})


## 左队: 被测龟独占上路 + 2 近战小将; 下路两只填充龟 + 1 小将(满足"恰好3统领"校验)
func _setup_left(gs, c: Dictionary) -> void:
	gs.reset_dual_lane()
	gs.dual_active = true
	gs.season_level = _level
	gs.hearts = 8
	gs.season_total_battles = 10
	gs.persistent_bench = []
	gs.persistent_equipped = {}          # ★无装备
	gs.season_leaders = [str(c["turtle"]), str(_fillers[0]), str(_fillers[1])]
	gs.left_team.assign(gs.season_leaders)
	gs.loadouts = {str(c["turtle"]): int(c["sidx"])}    # ★指定被测技能
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "id": str(c["turtle"]), "slot": 0},
			{"kind": "minion", "role": "front"},         # 近战小将
			{"kind": "minion", "role": "front"},         # 近战小将
		],
		"bottom": [
			{"kind": "leader", "id": str(_fillers[0]), "slot": 1},
			{"kind": "leader", "id": str(_fillers[1]), "slot": 2},
			{"kind": "minion", "role": "front"},
		],
	}


## 右队 ghost: 与左队完全同构(镜像), 只有上路那只龟+技能不同
func _ghost_of(c: Dictionary) -> Dictionary:
	return {
		"schema_ver": 1,
		"ghost_id": "duel_%s_%d" % [str(c["turtle"]), int(c["sidx"])],
		"is_bot": false,
		"bracket": 4,
		"profile": {"name": "%s·%s" % [str(c["tname"]), str(c["sname"])], "avatar": str(c["turtle"]), "id": "DUEL"},
		"leaders": [str(c["turtle"]), str(_fillers[0]), str(_fillers[1])],
		"lane_assign": {"top": [str(c["turtle"])], "bottom": [str(_fillers[0]), str(_fillers[1])]},
		"minions": {
			"top": [{"role": "front", "elite": false, "equips": []}, {"role": "front", "elite": false, "equips": []}],
			"bottom": [{"role": "front", "elite": false, "equips": []}],
		},
		"loadouts": {str(c["turtle"]): int(c["sidx"])},   # ★敌侧技能选择(foe_loadouts 读它)
		"equipped": {},                                   # ★无装备
		"pet_levels": {},
		"season_total_battles": 10,
		"season_eggs_killed": 0,
	}


## 首场体检: 打印上路实际结构 + 双方装备件数。
## 为什么必验: GameState._dl_structure_ok 硬要求"恰好3统领", 阵容不合法会【静默】重置成默认
## (上路 2 统领) —— 那样整个实验测的就不是"1龟+2近战小将"了, 而且不报错。
func _dump_setup(s) -> void:
	var lead := {"left": 0, "right": 0}
	var mini := {"left": 0, "right": 0}
	var eq := {"left": 0, "right": 0}
	for u in s._units:
		if u.get("is_trainer", false) or u.get("_isEgg", false):
			continue
		var sd := str(u.get("side", ""))
		if not lead.has(sd):
			continue
		if u.get("_isMinion", false):
			mini[sd] = int(mini[sd]) + 1
		else:
			lead[sd] = int(lead[sd]) + 1
		eq[sd] = int(eq[sd]) + ((u.get("equips", []) as Array).size() if u.get("equips", null) is Array else 0)
	print("  [体检] 上路结构 左 %d统领+%d小将 / 右 %d统领+%d小将  (应各 1+2)" % [
		lead["left"], mini["left"], lead["right"], mini["right"]])
	print("  [体检] 装备件数 左 %d / 右 %d  (应均 0)" % [eq["left"], eq["right"]])

func _write(elapsed: float) -> void:
	var dir := OS.get_environment("DUEL_OUT")
	if dir == "":
		dir = "res://tools/duel"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir)
	var to := 0
	for r in _rows:
		if str(r["win"]) == "timeout":
			to += 1
	print("")
	print("=== 本片完成: %d 场 / 墙钟 %.1f 秒 / %.2f 秒每场 ===" % [
		_rows.size(), elapsed, elapsed / maxf(1.0, float(_rows.size()))])
	print("  超时未分胜负: %d 场 %s" % [to, "★需查" if to > 0 else ""])
	print("  ★分母: %d 场 (0 = 空跑)" % _rows.size())

	var csv := "左龟,左技能idx,左技能,右龟,右技能idx,右技能,胜方,帧数,左释放,右释放\n"
	for r in _rows:
		var L: Dictionary = r["l"]
		var R: Dictionary = r["r"]
		csv += "%s,%d,%s,%s,%d,%s,%s,%d,%d,%d\n" % [
			L["turtle"], int(L["sidx"]), L["sname"],
			R["turtle"], int(R["sidx"]), R["sname"],
			r["win"], int(r["fr"]), int(r["lc"]), int(r["rc"])]
	var path := "%s/duel-%d.csv" % [dir, _shard]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(csv); f.close()
		print("  CSV: %s" % path)
	else:
		print("  [WARN] 写不出 %s" % path)
