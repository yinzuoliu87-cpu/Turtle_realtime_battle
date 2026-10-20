extends Node
## verify_gauntlet_server_pick.gd — 周六对手由服务端挑(2026-10-20 · 方案书 docs/plans/20261019-服务器裁判.md 决策记录
##   「10-20 用户授权自定：周六对手改服务器挑」; 迁移 server/supabase/migrations/20261020c_gauntlet_server_pick_and_coins.sql)。
##
## 服务端那一半的行为由 SQL 沙盒脚本量(server/supabase/tests/20261020c_…_check.sql, PGlite 真跑 59 条); 这里量客户端与两边的约定:
##   S1 机器人池(scripts/referee/bot_pool.gd): 行数 = 31 个场次 × 每个场次能开打的标签 × 6 份; 每一份都能当左 / 右方开打
##      (裁判 RefereeJob.validate + 每只统领两路里恰好一次 —— 与 SQL referee_lineup_ok 同一组条件); 标签 / 场次 / 等级与
##      make_bot 同一条曲线; 没有 origin / gl_ts; 同一版本生成两遍逐字节相同; 就是 make_bot 同一个函数的产物
##   S2 ★不露馅: 服务端挑到的机器人(池子那份 + 服务端补的 gl_ts)与服务端挑到的真人(gauntlet_ghosts 里的原件)
##      逐层「路径 : 类型」相同(经 JSON, 出站摘掉 is_bot / ghost_id 之后), 两边都没有 origin
##   S3 客户端交的请求体: 恰好 {p_week, p_snapshot, p_match_no, p_client_version, p_rules_ver} —— 没有对手、没有种子;
##      键名 / 顺序 = SQL 形参; 卡片解析只留 name / avatar / id / tag + 三统领; 回包形状不对 ⇒ server
##   S4 SQL 与客户端常量对账: 30 分钟新鲜窗 / gl_ts 60~1500 秒 / 池子上限 30 场 / 4-3-6 / coins 0..999 / 卡片键 / 权限 / 旧接口闸
##   S5 客户端已经没有任何一处调旧接口(referee_submit_gauntlet)

const BE := preload("res://scripts/net/backend.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const BP := preload("res://scripts/referee/bot_pool.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const MIG := "res://server/supabase/migrations/20261020c_gauntlet_server_pick_and_coins.sql"
const CHECK := "res://server/supabase/tests/20261020c_gauntlet_server_pick_and_coins_check.sql"
const MARK_BEGIN := "-- >>> BEGIN gauntlet_server_pick_and_coins 20261020c >>>"
const MARK_END := "-- <<< END gauntlet_server_pick_and_coins 20261020c <<<"
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	GameState.test_mode = true
	_t_pool()
	_t_shape()
	_t_request()
	_t_sql()
	_t_no_legacy()
	_t_stale()
	_finish()


# ─────────────────────────────── S1 机器人池 ───────────────────────────────
func _t_pool() -> void:
	print("── S1 机器人池 ──")
	var labels: Array = BP.labels()
	var want := 0
	for b in range(BP.MAX_BATTLES + 1):
		for lb in labels:
			if int(lb[0]) + int(lb[1]) <= b:
				want += BP.VARIANTS
	_ok("分母: 标签 = 周六能开打的 %d 个(gw < %d、gl < %d、gw + gl < %d)" % [labels.size(), P2.GAUNTLET_WINS_IN, P2.GAUNTLET_LOSSES_OUT, P2.GAUNTLET_QUOTA],
		labels.size() == 12)
	var pool: Dictionary = BP.generate()
	var rows: Array = pool.get("rows", [])
	_ok("★S1 行数 = %d(31 个场次 × 能开打的标签 × %d 份)" % [want, BP.VARIANTS], rows.size() == want and want > 1000, str(rows.size()))
	_ok("S1 池子头: 本机版本 / 规则版本 / 上限 / 份数", str(pool.get("client_version", "")) == ReplayRecorder.client_version()
		and int(pool.get("rules_ver", 0)) == int(P2.RULES_VER) and int(pool.get("max_battles", 0)) == BP.MAX_BATTLES
		and int(pool.get("variants", 0)) == BP.VARIANTS)
	var bad: Array = []
	var seen := {}
	for r0 in rows:
		var r: Dictionary = r0
		var s: Dictionary = r["snapshot"]
		var b := int(r["battles"])
		var gw := int(r["gw"])
		var gl := int(r["gl"])
		var key := "%d|%d|%d|%d" % [b, gw, gl, int(r["variant"])]
		if seen.has(key):
			bad.append("重复 " + key)
		seen[key] = true
		var why := RefereeJob.validate({"v": 1, "mode": "gauntlet", "seed": 1, "client_version": "", "a": s, "b": s})
		if why != "":
			bad.append("%s 开不了打: %s" % [key, why])
		elif not _each_leader_once(s):
			bad.append("%s 统领不是恰好一路一次" % key)
		if s.has("origin") or s.has("gl_ts"):
			bad.append("%s 带了 origin / gl_ts" % key)
		if int(s.get("gl_w", -1)) != gw or int(s.get("gl_l", -1)) != gl or int(s.get("season_total_battles", -1)) != b:
			bad.append("%s 标签 / 场次不对" % key)
		if int(s.get("season_level", -1)) != P2.bot_level_for_battles(b):
			bad.append("%s 等级不在曲线上" % key)
		if not bool(s.get("is_bot", false)):
			bad.append("%s 没有 is_bot(服务端 / 门禁要分得清; 出站摘掉)" % key)
		if bad.size() > 5:
			break
	_ok("★S1 每一份都能当左 / 右方开打、标签 / 场次 / 等级对、没有 origin / gl_ts", bad.is_empty(), str(bad.slice(0, 5)))
	var again: Array = []
	for i in range(0, rows.size(), 97):
		var r: Dictionary = rows[i]
		if var_to_bytes(BP.one(int(r["battles"]), int(r["gw"]), int(r["gl"]), int(r["variant"]))) != var_to_bytes(r["snapshot"]):
			again.append(i)
	_ok("★S1 同一版本再生成一遍逐字节相同(抽 %d 份)" % ceili(rows.size() / 97.0), again.is_empty(), str(again))
	var rng := RandomNumberGenerator.new()
	rng.seed = BP.seed_for(17, 2, 1, 3)
	var mb: Dictionary = BE.make_bot(17, rng, 2, 1)
	for k in BP.STRIP:
		mb.erase(k)
	_ok("★S1 就是 make_bot 同一个函数的产物(同种子 ⇒ 除 origin / gl_ts 外逐字节相同)",
		var_to_bytes(mb) == var_to_bytes(BP.one(17, 2, 1, 3)))
	var lv_hi := true
	for r0 in rows:
		if int((r0 as Dictionary)["battles"]) == BP.MAX_BATTLES and int(((r0 as Dictionary)["snapshot"] as Dictionary).get("season_level", 0)) != int(P2.MAX_LEVEL):
			lv_hi = false
	_ok("S1 池子上限 %d 场时装备 / 等级已到顶(超出的服务端用这一格不改强度)" % BP.MAX_BATTLES, lv_hi
		and P2.bot_level_for_battles(BP.MAX_BATTLES) == P2.bot_level_for_battles(BP.MAX_BATTLES + 20))


func _each_leader_once(s: Dictionary) -> bool:
	var la: Dictionary = s.get("lane_assign", {})
	var all: Array = (la.get("top", []) as Array) + (la.get("bottom", []) as Array)
	for p in s.get("leaders", []):
		if all.count(p) != 1:
			return false
	return (s.get("leaders", []) as Array).size() == 3


# ─────────────────────────────── S2 不露馅 ───────────────────────────────
func _shape(v, path: String, out: Dictionary) -> void:
	var t := type_string(typeof(v))
	if not out.has(path):
		out[path] = {}
	(out[path] as Dictionary)[t] = true
	if v is Dictionary:
		for k in (v as Dictionary).keys():
			var seg := "*" if DataRegistry.pet_by_id.has(str(k)) else str(k)
			_shape((v as Dictionary)[k], path + "/" + seg, out)
	elif v is Array:
		for e in (v as Array):
			_shape(e, path + "/[]", out)


func _flat(v) -> Dictionary:
	var sh := {}
	_shape(v, "", sh)
	var s := {}
	for p in sh.keys():
		for t in (sh[p] as Dictionary).keys():
			s["%s : %s" % [p, t]] = true
	return s


func _t_shape() -> void:
	print("── S2 服务端挑到的机器人与真人看不出区别 ──")
	var gs = GameState
	## 场次: 机器人的装备预算要够分到每个小将(否则 minions/[]/equips 那一层比不全; 取法同 verify_bot_snapshot_shape)
	var N := -1
	for n in range(0, BP.MAX_BATTLES + 1):
		if P2.team_equip_cap(P2.bot_level_for_battles(n)) >= 5 * P2.UNIT_EQUIP_CAP + 1:
			N = n
			break
	N = clampi(maxi(N, int(P2.PROMOTE_WINS) + 3), 0, BP.MAX_BATTLES)
	var ids: Array = []
	for p in DataRegistry.launch_pets:
		ids.append(str((p as Dictionary)["id"]))
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	gs.season_leaders = [ids[0], ids[1], ids[2]]
	gs.dual_lineup = gs.default_dual_lineup()
	for lk in ["top", "bottom"]:
		var k := 0
		for u in gs.dual_lineup[lk]:
			if str((u as Dictionary).get("kind", "")) != "leader":
				u["equips"] = [gs.mk_eq(str(shop[1]), 2)]
			(u as Dictionary)["off"] = [20 * k - 40, 150 * k - 150]
			k += 1
	gs.persistent_equipped = {}
	for i in range(3):
		gs.persistent_equipped[ids[i]] = [gs.mk_eq(str(shop[0]), 1), gs.mk_eq(str(shop[2]), 3)]
	gs.loadouts = {ids[0]: 2, ids[1]: 1, ids[2]: 3}
	gs.trainer_skill = "glacier"
	gs.season_total_battles = N
	gs.season_wins = 12
	gs.season_eggs_killed = 12
	gs.hearts = 3
	gs.season_sweeps = 4
	gs.chest_treasures_won = []
	gs.chest_treasure_value = 1234.0
	BE.pool_override = {BE.POOL_KEY: {}}
	BE.upload_gauntlet_ghost(2, 1)
	var sent: Dictionary = {}
	for b in (BE.pool_override[BE.POOL_KEY] as Dictionary).keys():
		for g in (BE.pool_override[BE.POOL_KEY][b] as Array):
			if (g as Dictionary).has("gl_w"):
				sent = (g as Dictionary).duplicate(true)
	BE.pool_override = {}
	sent.erase(BE.ORIGIN_KEY)              # 传上服务端的是没盖章的原件(upload_ghost 盖在副本上)
	_ok("分母: 周六真人快照由 upload_gauntlet_ghost 产出", not sent.is_empty() and sent.has("gl_ts"))
	## 服务端那一侧: 真人 = gauntlet_ghosts 原件(jsonb ⇒ JSON); 机器人 = 池子那份 + 服务端补 gl_ts(整数秒)
	var human: Dictionary = JSON.parse_string(JSON.stringify(sent))
	human.erase("origin")
	var row: Dictionary = BP.one(N, 2, 1, 0)
	var bot: Dictionary = JSON.parse_string(JSON.stringify(row))
	bot["gl_ts"] = float(int(P2.now_utc()) - 300)
	_ok("分母: 机器人的小将都有装备(比得到 minions/[]/equips 那一层)", _minions_all_equipped(bot))
	var hf := _flat(RU.strip_ghost(human))
	var bf := _flat(RU.strip_ghost(bot))
	var missing: Array = []
	var extra: Array = []
	for k in hf.keys():
		if not bf.has(k):
			missing.append(k)
	for k in bf.keys():
		if not hf.has(k):
			extra.append(k)
	_ok("分母: 比过的「路径 : 类型」≥ 30 条(%d)" % hf.size(), hf.size() >= 30)
	_ok("★★S2 真人有的路径 / 类型机器人都有", missing.is_empty(), str(missing))
	_ok("★★S2 机器人没有真人没有的路径 / 类型", extra.is_empty(), str(extra))
	_ok("★S2 两边都没有 origin(服务端取真人不经本机盖章; 机器人池摘掉了)", not human.has("origin") and not bot.has("origin"))
	_ok("S2 出站那一份机器人没有 is_bot / ghost_id", not RU.strip_ghost(bot).has("is_bot") and not RU.strip_ghost(bot).has("ghost_id"))
	var hc := RN.card_of(human)
	var bc := RN.card_of(bot)
	var hk: Array = (hc.get("profile", {}) as Dictionary).keys()
	var bk: Array = (bc.get("profile", {}) as Dictionary).keys()
	hk.sort()
	bk.sort()
	_ok("★S2 对手卡片同形(profile 键 %s / 三统领)" % str(hk), hk == bk and hk == ["avatar", "id", "name", "tag"]
		and (hc["leaders"] as Array).size() == 3 and (bc["leaders"] as Array).size() == 3, "%s / %s" % [str(hk), str(bk)])


func _minions_all_equipped(s: Dictionary) -> bool:
	for lk in ["top", "bottom"]:
		for m in (s.get("minions", {}) as Dictionary).get(lk, []):
			if not (m as Dictionary).has("equips"):
				return false
	return true


# ─────────────────────────────── S3 请求体 / 回包 ───────────────────────────────
func _t_request() -> void:
	print("── S3 客户端交什么、认什么 ──")
	var body := RN.start_body(1, {"leaders": []}, 3, "9.9.9", 1)
	var keys: Array = body.keys()
	_ok("★S3 请求体恰好 5 个键: 周 / 阵容 / 第几场 / 版本 / 规则版本", keys == ["p_week", "p_snapshot", "p_match_no", "p_client_version", "p_rules_ver"], str(keys))
	var leak: Array = []
	for k in keys:
		if str(k).contains("opp") or str(k).contains("seed") or str(k).contains("coin"):
			leak.append(k)
	_ok("★S3 没有对手 / 种子 / 币数这一维", leak.is_empty(), str(leak))
	var mig := FileAccess.get_file_as_string(MIG)
	var sig := "referee_gauntlet_start(p_week bigint, p_snapshot jsonb, p_match_no int,\n    p_client_version text, p_rules_ver int)"
	_ok("★S3 键名 / 顺序 = 服务端形参", mig.replace("\r\n", "\n").find(sig) >= 0)
	var opp := {"profile": {"name": "kevin_99", "avatar": "ninja", "id": "g_x", "tag": "#ABCDEF", "extra": 1}, "leaders": ["ninja", "dice", "pirate", "x"]}
	var okb := JSON.stringify({"ok": true, "job_id": 9, "match_id": MID, "opp": opp, "gw": 2, "gl": 1})
	var r := RN.parse_start(true, 200, okb)
	_ok("S3 回包: 任务号 / 录像号 / 卡片(只留 name / avatar / id / tag、统领截到 3)/ 账本 2-1", str(r.get("err", "?")) == ""
		and int(r["job_id"]) == 9 and str(r["match_id"]) == MID and not ((r["opp"] as Dictionary)["profile"] as Dictionary).has("extra")
		and ((r["opp"] as Dictionary)["leaders"] as Array).size() == 3 and int(r["gw"]) == 2 and int(r["gl"]) == 1, str(r))
	_ok("S3 回包缺卡片 ⇒ server(不画一张空卡)", str(RN.parse_start(true, 200, JSON.stringify({"ok": true, "job_id": 9, "match_id": MID})).get("err", "")) == "server")
	var st := RN.parse_start(true, 200, JSON.stringify({"ok": false, "reason": "stale", "gw": 3, "gl": 1}))
	_ok("S3 stale 带账本上的 gw / gl", str(st.get("err", "")) == "stale" and int(st["gw"]) == 3 and int(st["gl"]) == 1)
	_ok("S3 断网 = offline / 404 = unavailable / no_opponent 原样", str(RN.parse_start(false, 0, "").get("err", "")) == "offline"
		and str(RN.parse_start(true, 404, "").get("err", "")) == "unavailable"
		and str(RN.parse_start(true, 200, "{\"ok\":false,\"reason\":\"no_opponent\"}").get("err", "")) == "no_opponent")


# ─────────────────────────────── S4 SQL 对账 ───────────────────────────────
func _fn(t: String, name: String) -> String:
	var a := t.find("create or replace function public.%s(" % name)
	if a < 0:
		return ""
	var b := t.find("$$;", t.find("$$", a) + 2)
	return t.substr(a, b - a) if b > a else ""


func _t_sql() -> void:
	print("── S4 迁移与客户端常量对账 ──")
	var mig := FileAccess.get_file_as_string(MIG).replace("\r\n", "\n")
	_ok("分母: 迁移读得到、首尾标记各一次", mig.length() > 5000 and mig.count(MARK_BEGIN) == 1 and mig.count(MARK_END) == 1)
	var pick := _fn(mig, "referee_gauntlet_pick")
	var start := _fn(mig, "referee_gauntlet_start")
	var legacy := _fn(mig, "referee_submit_gauntlet")
	_ok("分母: 挑对手 / 开战 / 旧接口三个函数都在", pick != "" and start != "" and legacy != "")
	_ok("★S4 30 分钟新鲜窗 = FRESH_SNAPSHOT_SEC(%d)" % P2.FRESH_SNAPSHOT_SEC, pick.count("make_interval(secs => %d)" % P2.FRESH_SNAPSHOT_SEC) == 2)
	var be_src := FileAccess.get_file_as_string("res://scripts/net/backend.gd")
	_ok("★S4 机器人 gl_ts = 现在往前 60~1500 秒(= make_bot 的 randi_range(60, 25 * 60))", pick.find("(60 + floor(random() * 1441))") >= 0
		and be_src.find("rng.randi_range(60, 25 * 60)") >= 0 and 60 + 1441 - 1 == 25 * 60)
	_ok("★S4 池子上限 = bot_pool.gd MAX_BATTLES(%d)" % BP.MAX_BATTLES, pick.find("p_gw + p_gl, 0), %d);" % BP.MAX_BATTLES) >= 0)
	_ok("★S4 永不跨标签: 真人 / 机器人都按 gw = p_gw and gl = p_gl 取", pick.find("gg.gw = p_gw and gg.gl = p_gl") >= 0
		and pick.find("b.gw = p_gw and b.gl = p_gl") >= 0)
	_ok("★S4 只挑同规则版本的真人 / 机器人", pick.find("gg.rules_ver = p_rules_ver") >= 0 and pick.find("b.rules_ver = p_rules_ver") >= 0)
	_ok("★S4 周六结束条件 = 客户端 %d 胜 / %d 负 / %d 场" % [P2.GAUNTLET_WINS_IN, P2.GAUNTLET_LOSSES_OUT, P2.GAUNTLET_QUOTA],
		start.find("v_gw >= %d or v_gl >= %d or v_gw + v_gl >= %d" % [P2.GAUNTLET_WINS_IN, P2.GAUNTLET_LOSSES_OUT, P2.GAUNTLET_QUOTA]) >= 0)
	_ok("★S4 种子由服务端生成(开战函数里只有 referee_new_seed, 形参里没有种子)", start.find("public.referee_new_seed()") >= 0
		and start.left(start.find("returns")).find("seed") < 0)
	_ok("★S4 卡片键 = 客户端 card_of 认的键", _fn(mig, "referee_opp_card").find("e.key in ('name', 'avatar', 'id', 'tag')") >= 0)
	_ok("★S4 coins 夹 0..999、只进任务账本不进 matches", _fn(mig, "referee_complete").find("between 0 and 999") >= 0
		and _fn(mig, "referee_complete").find("jsonb_build_object('ledger', res || jsonb_build_object('coins', v_coins))") >= 0)
	_ok("★S4 job_status 回 coins", _fn(mig, "referee_job_status").find("'coins', j.result->'ledger'->'coins'") >= 0)
	_ok("★S4 旧接口: gauntlet_server_pick 开 ⇒ update_required(在任何建任务之前)", legacy.find("if coalesce(cfg.gauntlet_server_pick, false) then") >= 0
		and legacy.find("if coalesce(cfg.gauntlet_server_pick, false) then") < legacy.find("insert into public.referee_jobs"))
	_ok("★S4 权限: 开战给 authenticated、池子上传只给 service_role、挑对手不授权",
		mig.find("grant execute on function public.referee_gauntlet_start(bigint, jsonb, int, text, int) to authenticated;") >= 0
		and mig.find("grant execute on function public.referee_bot_pool_load(text, int, jsonb, boolean) to service_role;") >= 0
		and mig.find("referee_bot_pool_load(text, int, jsonb, boolean) to authenticated") < 0
		and mig.find("grant execute on function public.referee_gauntlet_pick") < 0)
	_ok("S4 挑对手 / 池子去掉 origin(真人 / 机器人同形)", pick.find("g.snapshot - 'origin'") >= 0 and pick.find("bp.snapshot - 'origin'") >= 0
		and _fn(mig, "referee_bot_pool_load").find("(r->'snapshot') - 'origin' - 'gl_ts'") >= 0)
	var chk := FileAccess.get_file_as_string(CHECK)
	_ok("S4 服务端行为的检查脚本在(沙盒 / 内测服跑; 结尾一定抛异常回滚、≥ 45 条)", chk.find("raise exception 'ALL PASS (% 条)'") >= 0
		and chk.find("v_n >= 45") >= 0 and chk.count("select pg_temp.ck(") >= 45, str(chk.count("select pg_temp.ck(")))


# ─────────────────────────────── S5 客户端不再调旧接口 ───────────────────────────────
func _t_no_legacy() -> void:
	print("── S5 客户端不再调旧接口 ──")
	var hits: Array = []
	var n := _scan("res://scripts", hits) + _scan("res://autoload", hits)
	_ok("分母: 扫过的脚本 ≥ 150 个(%d)" % n, n >= 150)
	_ok("★S5 scripts/ autoload/ 里没有 referee_submit_gauntlet / p_opponent", hits.is_empty(), str(hits))
	var mm := FileAccess.get_file_as_string("res://scripts/scenes/MatchmakingScene.gd")
	var a := mm.find("if _gauntlet_now and _RW.gauntlet_on():")
	var b := mm.find("_pick_gauntlet_local(exclude, _rng)")
	_ok("★S5 匹配屏: 开关开时先走服务端挑(在本机挑之前 return)", a > 0 and b > a and mm.find("_server_pick(exclude, _rng)", a) < b)


# ─────────────────────────────── S6 stale: 以账本为准 ───────────────────────────────
func _t_stale() -> void:
	print("── S6 第几场对不上(stale) ⇒ 以服务端账本为准 ──")
	var gs = GameState
	var k := {"gw": int(gs.gauntlet_wins), "gl": int(gs.gauntlet_losses), "p": (gs.referee_pending as Dictionary).duplicate()}
	gs.referee_pending = {}
	gs.gauntlet_wins = 0
	gs.gauntlet_losses = 0
	RW.adopt_ledger(gs, 2, 1)
	_ok("★S6 没有挂着的单子 ⇒ 本机战绩对齐到账本 2-1", int(gs.gauntlet_wins) == 2 and int(gs.gauntlet_losses) == 1)
	gs.referee_pending = {"job_id": 5, "match_id": MID, "week": 1}
	RW.adopt_ledger(gs, 3, 1)
	_ok("★S6 上一场的单子还挂着 ⇒ 不直接改战绩(交给补记, 它带着服务器的币)", int(gs.gauntlet_wins) == 2 and int(gs.gauntlet_losses) == 1)
	RW.adopt_ledger(gs, -1, -1)
	_ok("S6 回包没带账本 ⇒ 什么都不动", int(gs.gauntlet_wins) == 2)
	gs.gauntlet_wins = k["gw"]
	gs.gauntlet_losses = k["gl"]
	gs.referee_pending = k["p"]


func _scan(dir: String, hits: Array) -> int:
	var n := 0
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	for f in d.get_files():
		if f.ends_with(".gd"):
			n += 1
			var t := FileAccess.get_file_as_string(dir.path_join(f))
			if t.find("referee_submit_gauntlet") >= 0 or t.find("\"p_opponent\"") >= 0:
				hits.append(dir.path_join(f))
	for sd in d.get_directories():
		n += _scan(dir.path_join(sd), hits)
	return n


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %.1f 秒)" % [_n, Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 周六对手由服务端挑" if _fail == 0 and _n >= 30 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
