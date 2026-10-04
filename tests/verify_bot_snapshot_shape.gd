extends Node
## verify_bot_snapshot_shape.gd — 机器人对手的**快照**与真人对手的快照看不出区别。
##
## 用户 2026-10-04:「行，但问题是不能让玩家知道是机器人，以及对手的场次一定要相同」
##   卡片那一半由 verify_bot_card_honest 守; 这里守**数据**那一半 —— 对手快照会进录像
##   (`var_to_bytes`, 连 int/float 都保留)和 `matches.right_snapshot`, 任何登录用户都读得到。
##
## ★两边都走产品自己的路, 不手造:
##   真人 = `Backend.build_ghost_snapshot`(积分赛) / `Backend.upload_gauntlet_ghost`(周六)产出的快照,
##          再经对手真正到手的那条路: JSON 回包 → `SupabaseNet.snapshots_from_body` → `RemotePool.ingest_remote`。
##   机器人 = `Backend.find_opponent` / `Backend.find_gauntlet_opponent` 池空时回落的那一份。
## ★比法: 递归逐层取「路径 → 类型」全集, 两个方向都比。动态键(龟 id)折成 `*`, 数组折成 `[]`
##   —— 折法按**值**判(这个键是不是龟 id), 不按我以为的路径白名单判。
## ★分母: 真人快照里每个容器都必须非空(否则递归根本没走到下一层), 唯一例外写明理由。
## ★★内置陪练(`data/ghost_seed.json`, 396 支)也不是真人 —— 文件 → `_ensure_seeded` → `find_opponent`
##   逐支取出来, 每一支都与真人对手比(键/类型/值域/同一个人跨场次连贯), 并且**战斗强度不变**:
##   原样与转换后交给战斗场自己的 `_dual_foe_lane` 读, 逐字相同。见 `_check_seeds`。

const BE := preload("res://scripts/net/backend.gd")
const SB := preload("res://scripts/net/supabase.gd")
const RP := preload("res://scripts/net/remote_pool.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const TC := preload("res://scripts/scenes/TrainerConfigScene.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 真人快照里**允许是空**的容器(以及为什么)。不在这里的空容器 = 分母不够 = 红。
const EMPTY_OK := {
	## 宝箱战利品: 没养宝箱龟的真人就是 []; 机器人恒为 [](与战斗侧缺键回落值相同, 不改战斗)。
	"chest_treasures_won": true,
}

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _is_pet_id(k) -> bool:
	return DataRegistry.pet_by_id.has(str(k))


## 递归取形状: out[路径] = {类型名: true}。
func _shape(v, path: String, out: Dictionary, empties: Array) -> void:
	var t := type_string(typeof(v))
	if not out.has(path):
		out[path] = {}
	(out[path] as Dictionary)[t] = true
	if v is Dictionary:
		if (v as Dictionary).is_empty():
			empties.append(path)
		for k in (v as Dictionary).keys():
			var seg := "*" if _is_pet_id(k) else str(k)
			_shape((v as Dictionary)[k], path + "/" + seg, out, empties)
	elif v is Array:
		if (v as Array).is_empty():
			empties.append(path)
		for e in (v as Array):
			_shape(e, path + "/[]", out, empties)


func _flat(shape: Dictionary) -> Dictionary:
	var s := {}
	for p in shape.keys():
		for t in (shape[p] as Dictionary).keys():
			s["%s : %s" % [p, t]] = true
	return s


## 真人快照 → 对手手里拿到的那一份(服务端 JSON 回包 → 解包 → 入池盖章)。
func _as_remote_opponent(snap: Dictionary, battles: int) -> Dictionary:
	var body := JSON.stringify([{"snapshot": snap, "uploaded_at": "2026-10-04T00:00:00Z"}])
	var snaps: Array = SB.snapshots_from_body(body)
	var pool := {BE.POOL_KEY: {}}
	var st: Dictionary = RP.ingest_remote(pool, snaps)
	if int(st.get("added", 0)) != 1:
		print("    ingest 没收: ", st)
		return {}
	var bucket: Array = (pool[BE.POOL_KEY] as Dictionary).get(str(battles), [])
	return bucket[0] if not bucket.is_empty() else {}


## 比一对快照; 返回比过的条数。
func _compare(tag: String, human: Dictionary, bot: Dictionary) -> int:
	var hs := {}
	var he: Array = []
	_shape(human, "", hs, he)
	var bs := {}
	var be: Array = []
	_shape(bot, "", bs, be)
	var hf := _flat(hs)
	var bf := _flat(bs)
	var missing: Array = []
	var extra: Array = []
	for k in hf.keys():
		if not bf.has(k):
			missing.append(k)
	for k in bf.keys():
		if not hf.has(k):
			extra.append(k)
	missing.sort()
	extra.sort()
	print("  —— %s: 真人 %d 条「路径 : 类型」, 机器人 %d 条" % [tag, hf.size(), bf.size()])
	for m in missing:
		print("     真人有、机器人没有: ", m)
	for x in extra:
		print("     机器人有、真人没有: ", x)
	var bad_empty: Array = []
	for p in he:
		var key := str(p).trim_prefix("/")
		if not EMPTY_OK.has(key):
			bad_empty.append(p)
	_ok("★分母(%s): 真人快照里每个容器都非空(递归真的走到了每一层)" % tag, bad_empty.is_empty(), str(bad_empty))
	_ok("★分母(%s): 比过的「路径 : 类型」≥ 30 条" % tag, hf.size() >= 30, "%d 条" % hf.size())
	_ok("★★%s: 真人快照的每个键/类型机器人都有(逐层)" % tag, missing.is_empty(), str(missing))
	_ok("★★%s: 机器人没有真人快照里没有的键/类型(逐层)" % tag, extra.is_empty(), str(extra))
	## 出站那一份(录像 / right_snapshot 都过 strip_ghost)也要同形 —— 而且不许带内部标记。
	var hs2 := RU.strip_ghost(human)
	var bs2 := RU.strip_ghost(bot)
	var k1: Array = hs2.keys()
	var k2: Array = bs2.keys()
	k1.sort()
	k2.sort()
	_ok("★%s: 出站那一份(strip_ghost 后)顶层键集合相同" % tag, k1 == k2, "%s / %s" % [str(k1), str(k2)])
	_ok("★%s: 出站那一份没有 is_bot / ghost_id" % tag,
		not bs2.has("is_bot") and not bs2.has("ghost_id") and not hs2.has("is_bot"), str(bs2.keys()))
	return hf.size()


func _setup_human(battles: int) -> void:
	var gs = GameState
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
		for u in gs.dual_lineup[lk]:
			if str((u as Dictionary).get("kind", "")) != "leader":
				u["equips"] = [gs.mk_eq(str(shop[1]), 2)]
	gs.persistent_equipped = {}
	for i in range(3):
		gs.persistent_equipped[ids[i]] = [gs.mk_eq(str(shop[0]), 1), gs.mk_eq(str(shop[2]), 3)]
	gs.loadouts = {ids[0]: 2, ids[1]: 1, ids[2]: 3}
	gs.trainer_skill = "glacier"
	gs.season_total_battles = battles
	gs.season_eggs_killed = 9
	gs.season_wins = 9
	gs.hearts = 3
	gs.season_sweeps = 4
	gs.chest_treasures_won = []
	gs.chest_treasure_value = 1234.0


func _ready() -> void:
	await get_tree().process_frame
	print("=== 机器人对手快照与真人快照看不出区别(键/类型/值域) ===")
	OS.set_environment(SB.ENV_URL, " ")      # 不碰网络(门禁本来也这么设, 单跑时补上)
	GameState.test_mode = true
	## 选一个场次: 机器人的装备预算要够分到**每个**小将(否则 minions/[]/equips 那一层比不全)。
	##   make_bot 先填满 3 统领(3×上限), 再依次填 上路小将 / 下路第一个小将(各填满), 最后下路第二个 ⇒
	##   预算 ≥ 5×上限 + 1 才保证三个小将都有装备。(小将没装备时 `equips` 键本来就不写 —— 真人也一样。)
	var N := -1
	for n in range(0, 60):
		if P2.team_equip_cap(P2.bot_level_for_battles(n)) >= 5 * P2.UNIT_EQUIP_CAP + 1:
			N = n
			break
	_ok("★分母: 找到一个机器人装备能分到小将的场次", N >= 0, "N=%d" % N)
	if N < 0:
		_finish()
		return
	N = maxi(N, int(P2.PROMOTE_WINS) + 3)
	_setup_human(N)

	## ── 积分赛 ──
	var leaders: Array = GameState.season_leaders
	var gid := BE.player_ghost_id(int(GameState.season_id), leaders, N)
	var human_raw: Dictionary = BE.build_ghost_snapshot(gid,
		{"name": BE.player_display_name(), "avatar": str(leaders[0]), "id": gid})
	var human := _as_remote_opponent(human_raw, N)
	_ok("★分母: 真人快照走完了服务端回包 → 入池那条路", not human.is_empty())
	BE.pool_override = {BE.POOL_KEY: {}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var bot: Dictionary = BE.find_opponent(N, [], rng)
	_ok("★分母: 积分赛回落到的是机器人", bool(bot.get("is_bot", false)), str(bot.get("ghost_id", "")))
	var cmp_n := _compare("积分赛", human, bot)

	## ── 周六 ──
	var gw := 2
	var gl := 1
	BE.pool_override = {BE.POOL_KEY: {}}
	BE.upload_gauntlet_ghost(gw, gl)
	var gh_local: Dictionary = {}
	for b in (BE.pool_override[BE.POOL_KEY] as Dictionary).keys():
		for g in (BE.pool_override[BE.POOL_KEY][b] as Array):
			if (g as Dictionary).has("gl_w"):
				gh_local = g
	_ok("★分母: 周六真人快照由 upload_gauntlet_ghost 产出", not gh_local.is_empty())
	## 本地池那份盖的是 origin=local(只在本机); 传上服务端的是没盖章的原件(upload_ghost 盖在副本上)。
	var gh_sent: Dictionary = gh_local.duplicate(true)
	gh_sent.erase(BE.ORIGIN_KEY)
	var ghuman := _as_remote_opponent(gh_sent, N)
	BE.pool_override = {BE.POOL_KEY: {}}
	var gbot: Dictionary = BE.find_gauntlet_opponent(gw, gl, [], rng)
	_ok("★分母: 周六回落到的是机器人", bool(gbot.get("is_bot", false)), str(gbot.get("ghost_id", "")))
	cmp_n += _compare("周六", ghuman, gbot)
	BE.pool_override = {}

	## ── 值域: 真人产得出来的值 ──
	var skill_ids := {}
	for s in TC.SKILLS:
		skill_ids[str((s as Dictionary)["id"])] = true
	var bad: Array = []
	var shown := 0
	for n in range(0, 25):
		for k in range(8):
			var r := RandomNumberGenerator.new()
			r.seed = n * 100 + k
			var b: Dictionary = BE.make_bot(n, r)
			var why := _value_problem(b, n, -1, -1, skill_ids)
			if why != "":
				bad.append("n=%d: %s" % [n, why])
	for k in range(40):
		var r2 := RandomNumberGenerator.new()
		r2.seed = 9000 + k
		var ggw := k % 4
		var ggl := (k / 4) % 3
		var nn := int(P2.RANKED_QUOTA) + ggw + ggl
		var b2: Dictionary = BE.make_bot(nn, r2, ggw, ggl)
		var why2 := _value_problem(b2, nn, ggw, ggl, skill_ids)
		if why2 != "":
			bad.append("gauntlet %d-%d: %s" % [ggw, ggl, why2])
	shown = 25 * 8 + 40
	_ok("★★值域: %d 个机器人的场次/战绩/命/等级/技能/ID 都是真人产得出来的" % shown, bad.is_empty(),
		str(bad.slice(0, 5)))
	## ★玩家 ID: 真人那份(经服务端回包 → 入池)带着, 就是自己设置页上那串; 机器人同形。
	var _htag := str((human["profile"] as Dictionary).get("tag", ""))
	_ok("★★真人快照的 profile.tag 到了对手手里还在, 且 = 上传者自己的 ID", _htag == BE.my_tag() and P2.tag_valid(_htag), _htag)
	_ok("★★机器人的 profile.tag 与真人同一种形状", P2.tag_valid(str((bot["profile"] as Dictionary).get("tag", ""))),
		str((bot["profile"] as Dictionary).get("tag", "")))
	## 机器人自报的 profile.id 用产品自己的身份解析器读得出「谁」, 与真人一样。
	_ok("★profile.id 与真人同形(产品的 owner_tag_of_id 解析得出人)",
		BE.owner_tag_of_id(str((bot["profile"] as Dictionary)["id"])) != ""
			and BE.owner_tag_of_id(str((human["profile"] as Dictionary)["id"])) != "",
		"%s / %s" % [(bot["profile"] as Dictionary)["id"], (human["profile"] as Dictionary)["id"]])
	## ── 内置陪练(data/ghost_seed.json) —— 它们也不是真人 ──
	cmp_n += _check_seeds(human, skill_ids)
	print("")
	print("  比过的「路径 : 类型」共 %d 条" % cmp_n)
	_finish()


## "" = 没毛病。
func _value_problem(b: Dictionary, battles: int, gw: int, gl: int, skill_ids: Dictionary) -> String:
	if int(b.get("season_total_battles", -1)) != battles:
		return "场次 %s ≠ %d" % [str(b.get("season_total_battles")), battles]
	var w := int(b.get("season_wins", -1))
	var h := int(b.get("hearts", -1))
	var sw := int(b.get("season_sweeps", -1))
	if w < 0 or w > battles:
		return "胜场 %d 越界" % w
	if int(b.get("season_eggs_killed", -1)) != w:
		return "碎蛋 %s ≠ 胜场 %d" % [str(b.get("season_eggs_killed")), w]
	if h < 0 or h > int(P2.HEARTS_MAX):
		return "命 %d 越界" % h
	if sw < 0 or sw > w:
		return "横扫 %d 越界" % sw
	var ladder := battles - maxi(0, gw) - maxi(0, gl)
	var ladder_w := w - maxi(0, gw)
	if ladder_w + (int(P2.HEARTS_MAX) - h) != ladder:
		return "积分赛胜 %d + 负 %d ≠ %d 场" % [ladder_w, int(P2.HEARTS_MAX) - h, ladder]
	if gw >= 0 and ladder_w < mini(int(P2.PROMOTE_WINS), ladder):
		return "打周六却没晋级(积分赛胜 %d)" % ladder_w
	if not skill_ids.has(str(b.get("trainer_skill", ""))):
		return "大师技能 %s 不在玩家选项里" % str(b.get("trainer_skill"))
	for k in (b.get("pet_levels", {}) as Dictionary).keys():
		if int(b["pet_levels"][k]) != 1:
			return "pet_levels %s=%s(真人恒 1)" % [k, str(b["pet_levels"][k])]
	if BE.owner_tag_of_id(str((b.get("profile", {}) as Dictionary).get("id", ""))) == "":
		return "profile.id %s 不是真人 id 的形状" % str((b.get("profile", {}) as Dictionary).get("id", ""))
	## ★玩家 ID(2026-10-04): 与真人同一个算法同一种长相(`_P2.tag_valid`) ——
	##   而且**不许**等于「拿快照里看得见的 uid 算出来的号」: 真人的号由账号算、与 uid 无关,
	##   机器人要是 = f(uid), 拿到快照的人逐条一验就认出来了(机器人独有特征)。
	var _prf: Dictionary = b.get("profile", {}) if b.get("profile") is Dictionary else {}
	var _tg := str(_prf.get("tag", ""))
	if not P2.tag_valid(_tg):
		return "profile.tag %s 不是玩家 ID 的形状" % _tg
	var _ow := BE.owner_tag_of_id(str(_prf.get("id", "")))
	if _ow != "" and P2.player_tag(_ow.split("_")[1]) == _tg:
		return "profile.tag 能由 profile.id 里的 uid 算出来(机器人独有特征)"
	if gw >= 0:
		if int(b.get("gl_w", -1)) != gw or int(b.get("gl_l", -1)) != gl:
			return "周六标签 %s-%s ≠ %d-%d" % [str(b.get("gl_w")), str(b.get("gl_l")), gw, gl]
		var age := int(P2.now_utc()) - int(b.get("gl_ts", 0))
		if age < 0 or age > 30 * 60:
			return "gl_ts 不在 30 分钟新鲜窗里(%d 秒)" % age
	return ""


func _finish() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 机器人快照看不出区别" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## ══ 内置陪练(data/ghost_seed.json)══════════════════════════════════════════
## 种子池那几百支也不是真人(队列模拟跑出来的), 而它们在冷启动/断网时**就是**玩家遇到的全部对手。
## ★走产品自己的路: 文件 → `_ensure_seeded`(`load_pool` 调的同一个) → `find_opponent` 同场次命中,
##   一支一支地取(把取到的放进 exclude 再取), 直到回落成机器人 ⇒ 每个桶里**能被抽到的**全部过一遍。
## ★分母: 文件里有几条, 就必须从匹配那条路上取到几条(取不到的那几条压根没被比)。
## ★战斗强度不许变: 同一支种子, 原样(文件里那份)与转换后那份交给**战斗场自己的** `_dual_foe_lane`
##   与敌方大师/宝箱读的那几个字段, 结果逐字相同。
func _check_seeds(human: Dictionary, skill_ids: Dictionary) -> int:
	print("")
	print("  —— 内置陪练: 文件 → _ensure_seeded → find_opponent 同场次逐支取 → 与真人逐条比 ——")
	var raw_by_id := {}
	var raw_n := 0
	var raw = JSON.parse_string(FileAccess.get_file_as_string(BE.SEED_PATH))
	if raw is Dictionary and (raw as Dictionary).get(BE.POOL_KEY) is Dictionary:
		for b in (raw[BE.POOL_KEY] as Dictionary).keys():
			for g in (raw[BE.POOL_KEY][b] as Array):
				raw_by_id[str((g as Dictionary).get("ghost_id", ""))] = g
				raw_n += 1
	_ok("★分母: 种子文件读到 ≥ 300 条", raw_n >= 300, "%d 条" % raw_n)

	var spool := {BE.POOL_KEY: {}}
	BE._ensure_seeded(spool)
	BE.pool_override = spool
	var got: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for b in (spool[BE.POOL_KEY] as Dictionary).keys():
		var n := int(b)
		var excl: Array = []
		while excl.size() < 1000:
			var opp: Dictionary = BE.find_opponent(n, excl, rng)
			if bool(opp.get("is_bot", false)) or not BE.is_sparring(opp):
				break
			excl.append(str(opp.get("ghost_id", "")))
			got.append(opp)
	BE.pool_override = {}
	_ok("★分母: 匹配那条路上取到的陪练 = 文件里的条数(每一条都被比过)", got.size() == raw_n,
		"取到 %d / 文件 %d" % [got.size(), raw_n])

	var hs := {}
	var he: Array = []
	_shape(human, "", hs, he)
	var hf := _flat(hs)
	var h_top: Array = human.keys()
	h_top.sort()
	var h_prof: Array = (human.get("profile", {}) as Dictionary).keys()
	h_prof.sort()
	var h_out: Array = RU.strip_ghost(human).keys()
	h_out.sort()
	var union := {}
	var problems := {}          ## 毛病 → 条数(打印全表)
	var proj_bad: Array = []
	var proj_n := 0
	var by_person := {}         ## 同一个「人」的各场次: 名字 / 身份 / 胜场要连贯
	var sid := int(GameState.season_id)
	var rb = RB.new()
	var _digits := RegEx.create_from_string("[0-9.]+")
	var dg0 = GameState.dual_ghost
	var flo0 = GameState.foe_loadouts
	for sd in got:
		var s: Dictionary = sd
		var n := int(s.get("season_total_battles", -1))
		var ss := {}
		var se: Array = []
		_shape(s, "", ss, se)
		var sf := _flat(ss)
		for k in sf.keys():
			union[k] = true
			if not hf.has(k):
				_tally(problems, "陪练有、真人没有: " + str(k))
		var top: Array = s.keys()
		top.sort()
		for k in h_top:
			if not top.has(k):
				_tally(problems, "真人有、陪练没有(顶层键): " + str(k))
		var prof: Array = (s.get("profile", {}) as Dictionary).keys()
		prof.sort()
		if prof != h_prof:
			_tally(problems, "profile 键集合不同: %s" % str(prof))
		var out: Array = RU.strip_ghost(s).keys()
		out.sort()
		if out != h_out:
			_tally(problems, "出站那一份(strip_ghost 后)顶层键集合与真人不同")
		var why := _value_problem(s, n, -1, -1, skill_ids)
		if why != "":
			_tally(problems, "值域: " + _digits.sub(why, "#", true))
		## 空装备数组: 真人上传时**不写**(`build_ghost_snapshot` 只收非空的)。
		for pid in (s.get("equipped", {}) as Dictionary).keys():
			if ((s["equipped"] as Dictionary)[pid] as Array).is_empty():
				_tally(problems, "值域: equipped 里有空数组(真人不产)")
		for lk in (s.get("minions", {}) as Dictionary).keys():
			for m in (s["minions"][lk] as Array):
				if (m as Dictionary).has("equips") and ((m as Dictionary)["equips"] as Array).is_empty():
					_tally(problems, "值域: 小将 equips 是空数组(真人不产)")
		var prf: Dictionary = s.get("profile", {})
		var nm := str(prf.get("name", ""))
		if not P2.nickname_valid(nm) or P2.nickname_clean(nm) != nm:
			_tally(problems, "值域: 名字不是玩家能起的名字(nickname_valid)")
		var pidv := str(prf.get("id", ""))
		if not pidv.ends_with("_b%d" % n) or BE.owner_tag_of_id(pidv) == "" \
				or not pidv.begins_with(BE.owner_tag_of_id(pidv)) \
				or BE.owner_tag_of_id(pidv).get_slice("_", 2) != str(sid):
			_tally(problems, "值域: profile.id 不是「g_<uid>_<本赛季>_<三龟>_b<场次>」")
		var person := str(s.get("ghost_id", "")).get_slice("_b", 0)
		if not by_person.has(person):
			by_person[person] = []
		(by_person[person] as Array).append(s)
		## ── 战斗强度: 原样 vs 转换后, 交给战斗场自己的读法 ──
		var r0 = raw_by_id.get(str(s.get("ghost_id", "")), null)
		if r0 == null:
			proj_bad.append("%s 在文件里找不到" % str(s.get("ghost_id", "")))
			continue
		var p_raw := _battle_view(rb, r0)
		var p_new := _battle_view(rb, s)
		proj_n += 1
		if p_raw != p_new:
			if proj_bad.is_empty():
				print("     战斗视图不同(第一条): 原样 ", p_raw)
				print("                          转换 ", p_new)
			proj_bad.append(str(s.get("ghost_id", "")))
	GameState.dual_ghost = dg0
	GameState.foe_loadouts = flo0
	rb.free()
	var miss_union: Array = []
	for k in hf.keys():
		if not union.has(k):
			miss_union.append(k)
	miss_union.sort()
	for k in miss_union:
		_tally(problems, "真人有、全体陪练都没有: " + str(k))
	## 同一个人: 名字/身份不变, 场次越多胜场不减。
	var multi := 0
	for person in by_person.keys():
		var arr: Array = by_person[person]
		if arr.size() < 2:
			continue
		multi += 1
		arr.sort_custom(func(a, c) -> bool: return int(a["season_total_battles"]) < int(c["season_total_battles"]))
		for i in range(1, arr.size()):
			var a0: Dictionary = arr[i - 1]
			var a1: Dictionary = arr[i]
			if str(a0["profile"]["name"]) != str(a1["profile"]["name"]):
				_tally(problems, "同一个人不同场次名字变了")
			if BE.owner_tag_of_id(str(a0["profile"]["id"])) != BE.owner_tag_of_id(str(a1["profile"]["id"])):
				_tally(problems, "同一个人不同场次身份(uid)变了")
			if str(a0["profile"].get("tag", "")) != str(a1["profile"].get("tag", "")):
				_tally(problems, "同一个人不同场次玩家 ID 变了")
			if int(a1.get("season_wins", 0)) < int(a0.get("season_wins", 0)):
				_tally(problems, "同一个人场次多了胜场反而少了")
	var keys: Array = problems.keys()
	keys.sort()
	print("  —— 陪练 %d 支 × 真人 %d 条「路径 : 类型」; 差异表(毛病 : 条数) ——" % [got.size(), hf.size()])
	for k in keys:
		print("     %s  ×%d" % [k, int(problems[k])])
	if keys.is_empty():
		print("     (无)")
	_ok("★分母: 陪练里有同一个人打了多个场次的(连贯性检查真的比过)", multi >= 10, "%d 人" % multi)
	_ok("★★陪练 %d 支: 键/类型/值域与真人对手无差异" % got.size(), keys.is_empty(), "%d 种毛病" % keys.size())
	_ok("★分母: 战斗强度比过的陪练条数 = 取到的条数", proj_n == got.size() and proj_n > 0,
		"%d / %d" % [proj_n, got.size()])
	_ok("★★战斗强度不变: 原样 vs 转换后, 战斗场读出来的两路阵容/装备/技能/大师/宝箱逐字相同",
		proj_bad.is_empty(), str(proj_bad.slice(0, 5)))

	## ── 老存档: 池里躺着上一版(原样形状)的陪练 + 一条真人 ⇒ 升版后陪练换成新形状, 真人留着 ──
	var any_raw: Dictionary = raw_by_id.values()[0]
	var nb := str(int(any_raw["season_total_battles"]))
	var old_pool := {BE.POOL_KEY: {nb: [any_raw.duplicate(true), human.duplicate(true)]}, "_seed_ver": BE.SEED_VER - 1}
	BE._ensure_seeded(old_pool)
	var left_old := 0
	var human_kept := false
	var n_all := 0
	for b in (old_pool[BE.POOL_KEY] as Dictionary).keys():
		for g in (old_pool[BE.POOL_KEY][b] as Array):
			n_all += 1
			if (g as Dictionary).has("_strategy") or (g as Dictionary).has("season_level"):
				left_old += 1
			if str((g as Dictionary).get("ghost_id", "")) == str(human.get("ghost_id", "")):
				human_kept = true
	_ok("★老存档升版: 旧形状陪练 0 条留下、真人快照还在、新陪练并进来", left_old == 0 and human_kept and n_all == raw_n + 1,
		"旧形状 %d / 真人在 %s / 共 %d 条" % [left_old, str(human_kept), n_all])

	## ── 换赛季: 陪练的 profile.id 跟着换赛季号, 桶序一个不动(不许整批压到真人前面) ──
	var order0 := {}
	for b in (spool[BE.POOL_KEY] as Dictionary).keys():
		var ids: Array = []
		for g in (spool[BE.POOL_KEY][b] as Array):
			ids.append(str((g as Dictionary).get("ghost_id", "")))
		order0[b] = ids
	var sid0 := int(GameState.season_id)
	GameState.season_id = sid0 + 1
	BE._ensure_seeded(spool)
	var stale := 0
	var moved := 0
	var seen_n := 0
	for b in (spool[BE.POOL_KEY] as Dictionary).keys():
		var ids2: Array = []
		for g in (spool[BE.POOL_KEY][b] as Array):
			seen_n += 1
			ids2.append(str((g as Dictionary).get("ghost_id", "")))
			if BE.owner_tag_of_id(str(g["profile"]["id"])).get_slice("_", 2) != str(sid0 + 1):
				stale += 1
		if ids2 != order0.get(b, []):
			moved += 1
	GameState.season_id = sid0
	_ok("★换赛季: %d 条陪练的 profile.id 全换成新赛季号, 桶序不变" % seen_n,
		seen_n == raw_n and stale == 0 and moved == 0, "旧赛季号 %d 条 / 桶序变了 %d 个桶" % [stale, moved])
	return got.size()


func _tally(d: Dictionary, k: String) -> void:
	d[k] = int(d.get(k, 0)) + 1


## 战斗场从对手快照里读出来的全部东西(读法用战斗场自己的函数, 不另写一份):
##   两路规格(统领+装备 / 小将+装备, `_dual_foe_lane`) / 技能选择(`foe_loadouts`) /
##   敌方大师技能(`battle_spawn` 读 trainer_skill) / 宝箱进度(`battle_spawn` 读那两个键) / 统领名单。
func _battle_view(rb, g) -> String:
	GameState.dual_ghost = (g as Dictionary).duplicate(true)
	var top := _effective_specs(rb._dual_foe_lane("top"))
	var bot := _effective_specs(rb._dual_foe_lane("bottom"))
	var d: Dictionary = g
	return JSON.stringify([top, bot, GameState.foe_loadouts, str(d.get("trainer_skill", "")),
		d.get("chest_treasures_won", []) if d.has("chest_treasures_won") else [],
		float(d.get("chest_treasure_value", 0.0)), d.get("leaders", [])], "", true)


## 敌方规格里的 `equips` 落到战斗里**实际生效**的那一份。
## ★`_dual_foe_lane` 原样搬快照: 文件里统领的 `equipped` 是空数组时它写 `equips: []`, 缺键时不写。
##   而这份规格的三个下游读者对两者给的是同一个结果, 所以这里按读者的口径折一次:
##     · `battle_spawn._spawn_lane_side`: 只在 `equips` **非空**时转 `_dl_equips`; 敌方没有 `_dl_equips`
##       时 `_inject_equipment` 给空表(`persistent_equipped` 只给左方)
##     · `dual_lane_flow._dl_spec_equips(spec, false)`(布阵预览): `equips` 在就用它, 否则 `[]`
##     · `synergy_system._roster_equip_ids`(敌方羁绊): `get("equips", [])`
##   ⇒ 「生效的装备」= `get("equips", [])`。除此之外规格逐字比。
func _effective_specs(specs: Array) -> Array:
	var out: Array = []
	for sp in specs:
		var c: Dictionary = (sp as Dictionary).duplicate(true)
		c["equips"] = c.get("equips", []) if c.get("equips") is Array else []
		out.append(c)
	return out
