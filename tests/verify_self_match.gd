extends Node
## verify_self_match.gd — 接上后端之后【不许打到自己】 (2026-08-27)
##
## 用户 2026-08-27 问:「这应该不会匹配到当前历史的队伍吧, 或者自己id的队伍」——
## 一查确实有洞, 而且是两个独立的洞。本文件把五种情况逐个焊死。
##
## ★★根因: `ghost_id` 原本是 `g_<赛季>_<三龟>`, **完全不带"是谁"**。
##   单机本地池里够用(池里只有我), 变成共享池之后立刻塌:
##     · 自己那份从服务器绕回来会带 `origin=remote`, 而 `pool_add` 按 ghost_id 去重
##       把本地 `origin=local` 那份**顶掉** ⇒ 只看 origin 就会打到自己
##     · 两个玩家用同样三只龟 ⇒ **同一个 id** ⇒ 服务端互相覆盖
##   ⇒ 2026-08-27 把 uid 补进 id: `g_<uid>_<赛季>_<三龟>`。
##
## ★用户拍板:【上个赛季的自己不排除】(赛季 5 天一轮切轮全重置, 当对手合理; 池子越空越不该往外剔)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_self_match.tscn

const Backend := preload("res://scripts/net/backend.gd")
const RemotePool := preload("res://scripts/net/remote_pool.gd")

const SEASON := 3
const MY_TRIO := ["angel", "basic", "stone"]

var _n := 0
var _fail := 0
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _snap(gid: String) -> Dictionary:
	return {
		"schema_ver": Backend.SCHEMA_VER, "ghost_id": gid, "is_bot": false, "bracket": 3,
		"profile": {"name": "玩家阵容", "avatar": "angel", "id": gid},
		"leaders": ["angel"], "pet_levels": {"angel": 5}, "equipped": {},
		"minions": {}, "loadouts": {}, "lane_assign": {},
		"season_total_battles": 12, "season_eggs_killed": 0,
		"chest_treasures_won": [], "chest_treasure_value": 0.0,
	}


## 把一份快照放进一个干净的池, 再问 pool_find 抽不抽得到它。
## 抽到 = 会打到它; null = 被跳过。
func _matchable(snap: Dictionary, origin: String) -> bool:
	var pool := {"brackets": {}}
	var s2 := snap.duplicate(true)
	if origin != "":
		s2[Backend.ORIGIN_KEY] = origin
	Backend.pool_add(pool, s2)
	return Backend.pool_find(pool, 3, [], RandomNumberGenerator.new()) != null


func _ready() -> void:
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	_gs.season_id = SEASON
	print("=== 接上后端后不许打到自己 ===")

	# ── 分母 0: uid 真的生成了, 而且进了 id ──
	var uid := str(_gs.get_install_uid())
	var my_gid := Backend.player_ghost_id(SEASON, MY_TRIO)
	_ok("★分母: 本机 install_uid 非空(%s)" % uid, uid != "" and uid.length() >= 8)
	_ok("★★分母: ghost_id 里【带上了 uid】—— 没有这一维下面全都堵不住",
		my_gid.find(uid) >= 0, "id=%s" % my_gid)

	# ── ① 本机刚传的那份(还没绕过服务器) ──
	_ok("★★① 本机上传的那份(origin=local)不许被匹配到",
		not _matchable(_snap(my_gid), Backend.ORIGIN_LOCAL))

	# ── ② 自己那份【从服务器拉回来】(带 remote 章) ──
	## 这条是 2026-08-27 之前真会打到自己的那个洞。
	_ok("★★② 自己那份从服务器绕回来(origin=remote)也不许被匹配到",
		not _matchable(_snap(my_gid), Backend.ORIGIN_REMOTE),
		"服务端存的是上传原样, 拉回来盖 remote 章 ⇒ 只看 origin 会漏")

	# ── ③ 同赛季【换过龟】之后的旧阵容 ──
	var old_gid := Backend.player_ghost_id(SEASON, ["bubble", "candy", "chest"])
	_ok("★★③ 自己同赛季换龟前的旧阵容不许被匹配到(%s)" % old_gid,
		not _matchable(_snap(old_gid), Backend.ORIGIN_REMOTE))

	# ── ④ 上个赛季的自己 —— 用户拍板【不排除】, 所以必须【匹配得到】 ──
	## ★这条是"反向"断言: 挡多了也是错。没有它, 谁把判据放宽成"只要 uid 是我就跳过",
	##   会静默地把上赛季的自己也剔掉, 而池子本来就不满。
	var prev_gid := Backend.player_ghost_id(SEASON - 1, MY_TRIO).replace("_%d_" % SEASON, "_%d_" % (SEASON - 1))
	_gs.season_id = SEASON            # 当前仍是 SEASON, 拿上赛季的 id 来问
	_ok("★★④ 上个赛季的自己【要匹配得到】(用户 2026-08-27:「先不排除」)",
		_matchable(_snap(prev_gid), Backend.ORIGIN_REMOTE),
		"上赛季 id=%s" % prev_gid)

	# ── ⑤ 别人用同样三只龟 —— 不许被误判成自己 ──
	## ★这条守的是"挡自己"不能变成"挡别人": uid 不同就是别人, 哪怕三只龟一模一样。
	##   2026-08-27 之前 id 里没有 uid ⇒ 两人同三龟 = 同一个 id, 挡自己必然连别人一起挡。
	var other_gid := "g_%s_%d_%s" % ["ffffffffffff", SEASON, "-".join(PackedStringArray(MY_TRIO))]
	_ok("★★⑤ 别人用同样三只龟【必须能匹配到】(uid 不同就是别人)",
		_matchable(_snap(other_gid), Backend.ORIGIN_REMOTE),
		"别人的 id=%s" % other_gid)

	# ── ⑥ 内置策划队不受影响 ──
	## ⚠ 夹具坑(第一版栽在这): 不能拿 `_snap()` 造策划队 —— 它把 `profile.name` 写成
	##   "玩家阵容", 而那正是第三条【老池子兼容】判据认自己的特征 ⇒ 策划队被误判成自己。
	##   **错的是我的夹具不是产品。** 用真种子数据里的样子(它们有自己的昵称)。
	var seed_snap := _snap("seed_autoplay_autoplay-b1_coh_8_b0")
	seed_snap["profile"] = {"avatar": "dice", "id": "autoplay-b1_COH8", "name": "退休的海风啦"}
	_ok("★★⑥ 内置策划队照常能匹配到(没被误伤)", _matchable(seed_snap, ""),
		"策划队昵称不是「玩家阵容」⇒ 三条判据都不该认它")

	# ── ⑦ uid 跨清档存活 ──
	## ★清档清掉 uid 的话, 服务器上你之前传的快照就再也认不出是自己的 ⇒ 又会打到自己。
	var before := str(_gs.get_install_uid())
	_gs.reset_save()
	_ok("★★⑦ 清档之后 install_uid 不变(它是本机标识, 不是本局状态)",
		str(_gs.install_uid) == before and before != "",
		"清档前 %s / 清档后 %s" % [before, str(_gs.install_uid)])
	_done()


func _done() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 9:
		print("  [FAIL] ★分母: 断言只有 %d 条(<9) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 不打到自己" if _fail == 0 else "FAIL x%d — 不打到自己" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
