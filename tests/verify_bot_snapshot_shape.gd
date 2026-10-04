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

const BE := preload("res://scripts/net/backend.gd")
const SB := preload("res://scripts/net/supabase.gd")
const RP := preload("res://scripts/net/remote_pool.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const TC := preload("res://scripts/scenes/TrainerConfigScene.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

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
	## 机器人自报的 profile.id 用产品自己的身份解析器读得出「谁」, 与真人一样。
	_ok("★profile.id 与真人同形(产品的 owner_tag_of_id 解析得出人)",
		BE.owner_tag_of_id(str((bot["profile"] as Dictionary)["id"])) != ""
			and BE.owner_tag_of_id(str((human["profile"] as Dictionary)["id"])) != "",
		"%s / %s" % [(bot["profile"] as Dictionary)["id"], (human["profile"] as Dictionary)["id"]])
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
