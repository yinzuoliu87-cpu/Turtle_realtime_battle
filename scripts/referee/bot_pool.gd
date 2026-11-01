extends RefCounted
## 周六服务器挑对手 · 机器人快照池(2026-10-20 · 方案书 docs/plans/20261019-服务器裁判.md 决策记录「10-20 用户授权自定：周六对手改服务器挑」)。
##
## 服务端(`referee_gauntlet_start`, 迁移 20261020c)挑不到同标签真人时要一份机器人快照, 而机器人生成(`Backend.make_bot`)是
##   GDScript。⇒ 用**同一个函数**离线生成一整池, 上传到 `gauntlet_bot_pool`(按 rules_ver / 场次 / 标签 / 序号存);
##   服务端挑中后只改两个与对局无关的键(`gl_ts` 上传时刻 = 现在往前 60~1500 秒、场次超出池子上限时的 `season_total_battles`)。
##   ★快照本身就是数据 ⇒ 与真人快照走完全同一条路(任务单 b → 裁判 → 录像), 对确定性零影响; 裁判程序一行不用改。
##
## 生成入口: `godot --headless --path <工程> res://scenes/Referee.tscn -- --bot-pool=<输出.json>`
##   (轮询器 `referee_poller.py --bot-pool` 对每个装了的版本跑一遍并上传, 见 server/referee/README.md)。
##
## 池子的形状(一个 json):
##   {v, client_version, rules_ver, max_battles, variants, rows: [{battles, gw, gl, variant, snapshot}]}
##   · 场次 0..MAX_BATTLES, 标签 = 周六所有还能开打的 (gw, gl)(gw < 4、gl < 3、gw + gl < 6), 且 gw + gl ≤ 场次;
##   · 每格 VARIANTS 份(同一个人一周最多打 6 场, 服务端排除本周已经碰过的那几份);
##   · 种子按 (规则版本, 场次, 标签, 序号) 定 ⇒ 同一版本重跑逐字节相同(门禁 verify_gauntlet_server_pick 比两遍)。
## ★摘掉两个键再存:
##   `origin` —— make_bot 盖 remote 章是为了与「本机从服务端拉回来的真人」同形; 服务端直接从 gauntlet_ghosts 取的真人快照
##     **没有**这个键(上传原样)。不摘 = 录像里一眼分得出机器人(用户 2026-10-04「不能让玩家知道是机器人」)。
##   `gl_ts` —— 生成时刻没有意义, 服务端挑中那一刻重新写。

const BE := preload("res://scripts/net/backend.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

const FORMAT := 1
## 池子覆盖到第几场。周六能到的场次 = 积分赛配额 16 + 周六 ≤ 5 = 21; 装备曲线在 28 场封顶(BOT_LV_MIN_BATTLES 末格)。
##   超过的服务端用 30 那一格、只把 season_total_battles 改成真实场次(装备 / 等级 / 砍伐进度都已到顶, 不改强度)。
const MAX_BATTLES := 30
const VARIANTS := 6
## 生成后摘掉的键(见头注)。
const STRIP := ["origin", "gl_ts"]


## 周六所有还能开打的标签 [gw, gl](与服务端 / `gauntlet_state` 同一组常量)。
static func labels() -> Array:
	var out: Array = []
	for gw in range(int(P2.GAUNTLET_WINS_IN)):
		for gl in range(int(P2.GAUNTLET_LOSSES_OUT)):
			if gw + gl < int(P2.GAUNTLET_QUOTA):
				out.append([gw, gl])
	return out


static func seed_for(battles: int, gw: int, gl: int, variant: int) -> int:
	return absi(("botpool|%d|%d|%d|%d|%d" % [int(P2.RULES_VER), battles, gw, gl, variant]).hash())


## 一份: 与客户端周六回落机器人同一个函数(`make_bot(场次, rng, gw, gl)`), 再摘 STRIP。
static func one(battles: int, gw: int, gl: int, variant: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(battles, gw, gl, variant)
	var snap: Dictionary = BE.make_bot(battles, rng, gw, gl)
	for k in STRIP:
		snap.erase(k)
	return snap


static func generate() -> Dictionary:
	var rows: Array = []
	for b in range(MAX_BATTLES + 1):
		for lb in labels():
			var gw: int = int(lb[0])
			var gl: int = int(lb[1])
			if gw + gl > b:
				continue
			for v in range(VARIANTS):
				rows.append({"battles": b, "gw": gw, "gl": gl, "variant": v, "snapshot": one(b, gw, gl, v)})
	return {"v": FORMAT, "client_version": ReplayRecorder.client_version(), "rules_ver": int(P2.RULES_VER),
		"max_battles": MAX_BATTLES, "variants": VARIANTS, "rows": rows}


# ─────────────────────────────── 积分赛池(2026-11-01) ───────────────────────────────
## 积分赛交给服务器(方案书 docs/plans/20261101c-积分赛服务器裁判.md)之后, 服务端挑对手(`referee_ranked_pick`)要两样
##   原来只在客户端的东西, 都用客户端**同一个函数**离线生成、上传到 `ranked_pool`:
##   · 内置陪练 seed: 客户端池子里那 396 份 = `Backend._load_seed()` 每一份过 `seed_as_human(g, 赛季号)`
##     (`_ensure_seeded` 同一条路)。场次 = 快照自报的 `season_total_battles`(选靶以快照自己的账为准, 不信桶键)。
##     赛季号固定 RANKED_SEED_SID: 它只进 `profile.id` 中间那一段(真人那一段是各自存档的大轮号, 本来就各不相同)。
##   · 兜底机器人 bot: `make_bot(场次, rng)`(积分赛口径: 不带周六标签), 场次 0..MAX_BATTLES、每格 VARIANTS 份。
##   两种都摘 `origin`(服务端直接取的真人快照没有这个键)。种子按 (规则版本, 场次, 序号) 定 ⇒ 同一版本重跑逐字节相同。
## 形状: {v, client_version, rules_ver, seed_rows: [{battles, variant, snapshot}], bot_rows: [{battles, variant, snapshot}]}
const RANKED_SEED_SID := 1


static func ranked_seed_for(battles: int, variant: int) -> int:
	return absi(("rankbot|%d|%d|%d" % [int(P2.RULES_VER), battles, variant]).hash())


static func ranked_bot(battles: int, variant: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = ranked_seed_for(battles, variant)
	var snap: Dictionary = BE.make_bot(battles, rng)
	snap.erase(BE.ORIGIN_KEY)
	return snap


static func generate_ranked() -> Dictionary:
	var seed_rows: Array = []
	var nth := {}
	var src: Dictionary = BE._load_seed()
	var buckets: Dictionary = src.get(BE.POOL_KEY, {})
	var keys: Array = buckets.keys()
	keys.sort_custom(func(a, b) -> bool: return int(a) < int(b))
	for k in keys:
		for g in (buckets[k] as Array):
			if not (g is Dictionary):
				continue
			var s: Dictionary = BE.seed_as_human(g as Dictionary, RANKED_SEED_SID)
			s.erase(BE.ORIGIN_KEY)
			var b := maxi(0, int(s.get("season_total_battles", 0)))
			var v := int(nth.get(b, 0))
			nth[b] = v + 1
			seed_rows.append({"battles": b, "variant": v, "snapshot": s})
	var bot_rows: Array = []
	for b in range(MAX_BATTLES + 1):
		for v in range(VARIANTS):
			bot_rows.append({"battles": b, "variant": v, "snapshot": ranked_bot(b, v)})
	return {"v": FORMAT, "client_version": ReplayRecorder.client_version(), "rules_ver": int(P2.RULES_VER),
		"seed_rows": seed_rows, "bot_rows": bot_rows}
