class_name RefereeJob
extends RefCounted
## 服务器裁判 —— 任务单(job)与结果单(result)的形状 + 「A 方快照 → 左方 GameState」。全静态, 不碰场景树。
## 方案书: docs/plans/20261019-服务器裁判.md §1。入口见 `referee_runner.gd`(跑一局) / `referee_main.gd`(命令行)。
##
## ══════════════════════════════════════════════════════════════════════
##  任务单(JSON, 由 server/referee/referee_poller.py 从 `referee_jobs` 领来、原样写进文件)
## ══════════════════════════════════════════════════════════════════════
##   v               格式版本(= FORMAT)
##   job_id          服务端任务号(原样带回结果单)
##   match_id        uuid v4 = 录像 id = `matches.match_id`(缺 / 不合法 ⇒ 裁判自己生成)
##   mode            "gauntlet"(周六闯关) / "finals"(周日决赛)
##   key             这一场是谁(原样带回; 写回 RPC 用它落账, 裁判不读)
##   seed            1 ~ 2^53-1 的整数(`_battle_rng` 种子; 服务端生成, 不由客户端给)
##   client_version  这份任务要求的游戏版本; 与本机不等 ⇒ 拒算(wrong_version) —— 结果只在同版本里成立
##   level           可选: **左方(A)**的等级(服务端 `referee_level_of(A 快照)` 填的就是 A 的 season_level)。
##                   以 A 快照里的 season_level 为准; A 没带才用它; 都没有才按 A 的场次推算(bot_level_for_battles, 只给缺字段的旧快照兜底)。
##                   ★右方(B)的等级不在这里: 战斗场自己读 B 快照(`dual_ghost`)里的 season_level(用户 2026-10-19「赛季等级」双方各用各的);
##                     B 是没带等级的旧快照 ⇒ 战斗场退回「与左方同级」的老口径(客户端同一条, 手机播录像时一致)。
##   a / b           双方快照(`Backend.build_ghost_snapshot` 同一形状)。A 在左、B 在右。
##   a_state         可选: A 方开局那一刻的 `ReplayRecorder.capture_state()`(以后「本地先播、服务器落账」用) —— 有它就不从快照推
##
## ══════════════════════════════════════════════════════════════════════
##  左方为什么要「从快照推」
## ══════════════════════════════════════════════════════════════════════
##   战斗场里两方走的是两条路: 右方(对手)读 `GameState.dual_ghost`(快照), 左方读 GameState 本身
##   (`dual_lineup` / `season_leaders` / `persistent_equipped` / `loadouts` / `trainer_skill` / 宝箱 / 斧头……,
##    就是 `ReplayRecorder.STATE_KEYS`)。服务器上没有 A 的存档 ⇒ 把 A 的快照翻成那几个变量。
##   ★翻译口径 = 「这份快照若站在右边会怎么打」: 每路规整到 3 单位用的就是战斗场自己的 `_foe_normalize_lane`
##     (调用方传进来, 不抄第二份); 快照里没有的东西(糖果临时等级 / 命运之轮层数 / 香火刻痕 / 斧头进度条)按右方的口径取 0 / 空,
##     因为右方在战斗里也拿不到它们。

const FORMAT := 1
const MODES := ["gauntlet", "finals"]
const SEED_MAX := 9007199254740991          # 2^53 - 1 (= GameState.BATTLE_SEED_MAX; JSON 往返不掉位的上限)
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const Duallane := preload("res://scripts/gamedata/phase2_duallane.gd")
const Uploader := preload("res://scripts/systems/replay/replay_uploader.gd")
const BE := preload("res://scripts/net/backend.gd")

## 错误码(英文短码, 进服务端 `referee_jobs.error`)。permanent = 重算也不会变好 ⇒ 写回失败、不重领。
const ERR_PERMANENT := ["bad_job", "bad_mode", "bad_seed", "wrong_version", "a_bad_snapshot", "b_bad_snapshot"]


## "" = 能算; 否则是拒算的错误码。纯函数。
static func validate(job) -> String:
	if not (job is Dictionary):
		return "bad_job"
	var j: Dictionary = job
	if int(j.get("v", 0)) != FORMAT:
		return "bad_job"
	if not str(j.get("mode", "")) in MODES:
		return "bad_mode"
	if seed_of(j) <= 0:
		return "bad_seed"
	var want := str(j.get("client_version", ""))
	if want != "" and want != ReplayRecorder.client_version():
		return "wrong_version"
	if not (j.get("a") is Dictionary) or leaders_of(j["a"]).size() != 3:
		return "a_bad_snapshot"
	if not _lanes_ok(j["a"]):
		return "a_bad_snapshot"
	if not (j.get("b") is Dictionary) or not _lanes_ok(j["b"]):
		return "b_bad_snapshot"
	return ""


## 种子: 1 ~ 2^53-1 的整数(JSON 解析出来是 float ⇒ 要求是整数值)。不合法 = -1。
static func seed_of(j: Dictionary) -> int:
	var s = j.get("seed", null)
	if not (s is int or s is float):
		return -1
	var f := float(s)
	if f != floor(f) or f < 1.0 or f > float(SEED_MAX):
		return -1
	return int(s)


## 快照的三统领(去空、去重, 保持顺序)。
static func leaders_of(snap) -> Array:
	var out: Array = []
	if not (snap is Dictionary):
		return out
	var l = (snap as Dictionary).get("leaders", [])
	if l is Array:
		for pid in l:
			var p := str(pid)
			if p != "" and not out.has(p):
				out.append(p)
	return out


## 分路表态了且不是「0 统领」那种坏快照(判据 = 战斗场自己用的 `Backend.ghost_lanes_broken`)。
## 左方另要求: 每只统领恰好在一路里出现一次(否则 `GameState._dl_structure_ok` 会把阵容重置成默认阵 —— 静默换人)。
static func _lanes_ok(snap) -> bool:
	if not (snap is Dictionary):
		return false
	var la = (snap as Dictionary).get("lane_assign", null)
	if not (la is Dictionary) or not ((la as Dictionary).get("top") is Array) or not ((la as Dictionary).get("bottom") is Array):
		return false
	return not BE.ghost_lanes_broken(snap)


## 左方(A)的等级(1 ~ MAX_LEVEL)。右方的等级战斗场从 B 快照读(见文件头 `level` 一条)。
## ★2026-10-19 起快照带 `season_level`(`build_ghost_snapshot`); 按场次推算只给缺这个键的旧快照兜底。
static func level_for(j: Dictionary) -> int:
	var a: Dictionary = j.get("a", {})
	var sl := BE.ghost_level(a)                  # A 快照自带的(与右方读 B 快照同一个判据)
	if sl >= 1:
		return sl
	var lv = j.get("level", null)
	if (lv is int or lv is float) and int(lv) >= 1:
		return clampi(int(lv), 1, P2.MAX_LEVEL)
	var b = a.get("season_total_battles", 0)
	return clampi(P2.bot_level_for_battles(int(b) if (b is int or b is float) else 0), 1, P2.MAX_LEVEL)


## 左方(A)开局 GameState —— `ReplayRecorder.STATE_KEYS` 全部都给值(不留本机残值)。
## `normalize` = 战斗场的 `_foe_normalize_lane`(每路规整到 3 单位, 与右方同一条规则)。
static func state_for(j: Dictionary, normalize: Callable) -> Dictionary:
	var b: Dictionary = (j["b"] as Dictionary).duplicate(true)
	var st: Dictionary
	if j.get("a_state") is Dictionary:
		st = {}
		var a_st: Dictionary = j["a_state"]
		for k in ReplayRecorder.STATE_KEYS:
			if a_st.has(k):
				var v = a_st[k]
				st[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	else:
		st = _state_from_snapshot(j["a"], normalize)
	st["dual_ghost"] = b
	st["dual_active"] = true
	st["tutorial_active"] = false
	st["debug_level"] = 0
	st["season_level"] = level_for(j)
	return st


static func _state_from_snapshot(a: Dictionary, normalize: Callable) -> Dictionary:
	var leaders := leaders_of(a)
	var la: Dictionary = a.get("lane_assign", {})
	var loff: Dictionary = a.get("leader_off", {}) if a.get("leader_off") is Dictionary else {}
	var mins: Dictionary = a.get("minions", {}) if a.get("minions") is Dictionary else {}
	var dl := {}
	for lane in ["top", "bottom"]:
		var specs: Array = []
		for pid in (la.get(lane, []) as Array):
			var p := str(pid)
			if not leaders.has(p):
				continue
			var spec := {"kind": "leader", "slot": leaders.find(p), "id": p}
			var o = loff.get(p, null)
			if o is Array and (o as Array).size() == 2:
				spec["off"] = LineupPos.pack(Vector2i(int(o[0]), int(o[1])))
			specs.append(spec)
		var ml = mins.get(lane, [])
		for m in (ml if ml is Array else []):
			if not (m is Dictionary):
				continue
			var md: Dictionary = m
			var ms := {"kind": "minion", "role": str(md.get("role", "front")), "equips": []}
			if md.get("equips") is Array:
				ms["equips"] = (md["equips"] as Array).duplicate(true)
			var mo = md.get("off", null)
			if mo is Array and (mo as Array).size() == 2:
				ms["off"] = LineupPos.pack(Vector2i(int(mo[0]), int(mo[1])))
			specs.append(ms)
		dl[lane] = normalize.call(specs)
	## 一只统领分到两路(坏快照) ⇒ 上面按 lane_assign 原样排了两次; `validate` 只查了「3 只」, 这里补查「恰好各一次」。
	var seen := {}
	for lane in dl:
		for u in dl[lane]:
			if u is Dictionary and str((u as Dictionary).get("kind", "")) == "leader":
				seen[str(u["id"])] = int(seen.get(str(u["id"]), 0)) + 1
	for p in leaders:
		if int(seen.get(p, 0)) != 1:
			return {"_error": "a_bad_snapshot"}
	var pe := {}
	var eq = a.get("equipped", {})
	if eq is Dictionary:
		for p in leaders:
			if (eq as Dictionary).get(p) is Array:
				pe[p] = ((eq as Dictionary)[p] as Array).duplicate(true)
	var lo := {}
	var alo = a.get("loadouts", {})
	if alo is Dictionary:
		for k in alo:
			var v = alo[k]
			if v is int or v is float:
				lo[str(k)] = int(v)
	var ts := str(a.get("trainer_skill", ""))
	var cw: Array = []
	var acw = a.get("chest_treasures_won", [])
	if acw is Array:
		for t in acw:
			cw.append(str(t))
	var cv = a.get("chest_treasure_value", 0.0)
	var axe: Dictionary = AxeEvolution.progress_of_snapshot(a)
	return {
		"dual_lineup": dl,
		"season_leaders": leaders,
		"persistent_equipped": pe,
		"loadouts": lo,
		"candy_temp_levels": {},          # 快照不带; 右方也拿不到 ⇒ 两边同口径
		"trainer_skill": ts if ts != "" else "hook",   # 与右方回落相同(battle_spawn: 老快照没有 ⇒ hook)
		"gambler_wheel_stacks": {},       # 同上(命运之轮跨场累积只给玩家本机那一方)
		"chest_treasure_value": float(cv) if (cv is int or cv is float) else 0.0,
		"chest_treasures_won": cw,
		"incense_marks": 0,               # 右方每场从 0 起(incense_stone_system D3)
		"incense_charge": 0,
		"trainer_appearance": "default",
		"axe_exp_bar": 0,                 # 右方不在局内进化(快照不传进度条) ⇒ 同口径
		"axe_exp_total": int(axe.get("total", 0)),
		"axe_stage": int(axe.get("stage", 0)),
		"axe_final": str(axe.get("final", "")),
	}


## 打完的结果单。`rec` = 裁判录下的那一份(已带 end); `lane_results` / `egg_hp` = 结算那一刻 GameState 里的。
static func ok_result(j: Dictionary, rec: Dictionary, lane_results: Dictionary, egg_hp: Dictionary,
		elapsed_ms: int, frames: int) -> Dictionary:
	var end: Dictionary = rec.get("end", {})
	var a_won := bool(end.get("won", false))
	var fights := 0
	for e in rec.get("events", []):
		if e is Dictionary and str((e as Dictionary).get("k", "")) == "fight":
			fights += 1
	var b64: String = Uploader.upload_b64(rec)
	return {
		"ok": true,
		"v": FORMAT,
		"job_id": job_id_of(j),
		"mode": str(j.get("mode", "")),
		"key": j.get("key", {}),
		"match_id": str(rec.get("id", "")),
		"winner": "a" if a_won else "b",
		"a_won": a_won,
		"winner_side": 0 if a_won else 1,        # 周日: A = 上半区(side 0)
		"score_code": Duallane.score_code(lane_results, egg_hp),
		"lane_results": lane_results,            # left = A, right = B
		"egg_hp": egg_hp,
		"steps": int(end.get("s", 0)),
		"digest": str(end.get("h", "")),
		"seed": int(rec.get("seed", 0)),
		"level": int((rec.get("state", {}) as Dictionary).get("season_level", 0)),
		"client_version": str(rec.get("client_version", "")),
		"engine": str(Engine.get_version_info().get("string", "")),
		"plat": str(rec.get("plat", "")),
		"arch": str(rec.get("arch", "")),
		"fights": fights,
		"cps": (rec.get("cps", []) as Array).size(),
		"replay_b64": b64,
		"replay_ok_size": b64.length() <= Uploader.REPLAY_MAX_B64,
		"elapsed_ms": elapsed_ms,
		"frames": frames,
	}


## 任务号原样带回。JSON 解析把整数变成 float(1 → 1.0)⇒ 整数值的 float 还原成 int, 免得写回时 bigint 列收到「1.0」。
static func job_id_of(j: Dictionary):
	var v = j.get("job_id", null)
	if v is float and float(v) == floor(float(v)) and absf(float(v)) <= float(SEED_MAX):
		return int(v)
	return v


static func error_result(job, code: String) -> Dictionary:
	var j: Dictionary = job if job is Dictionary else {}
	return {
		"ok": false,
		"v": FORMAT,
		"job_id": job_id_of(j),
		"error": code,
		"permanent": code in ERR_PERMANENT,
		"client_version": ReplayRecorder.client_version(),
	}
