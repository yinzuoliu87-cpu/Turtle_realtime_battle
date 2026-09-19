extends Node
## verify_exact_match.gd — A6：**只和场次完全相同的人打**，同场次里取最新的那份
##
## ★★为什么这条门禁非有不可（方案书 §2.3 自己写的警告）:
##   `pool_find` 有 **10 处调用**(产品 1 / 门禁 5 / 探针 4), 新参数必须带默认值,
##   否则一起炸。**但带了默认值就意味着老门禁全绿却一条新行为都没验到** ——
##   不能靠"现有门禁没红"当作没问题(同族 memory: 判据没错但被测对象不在场)。
##
## ★由来(母方案书 §10.35 C7): 旧 `player_ghost_id` **不含场次**, 而 `pool_add` 按 id 去重
##   ⇒ 同一玩家在池里只有最新一份 ⇒ **场次比你低的人永远匹配不到你**, 而且是静默的。
##
## ★D10「同场次的多份按上传时刻倒序取最新」**不需要时间戳字段**:
##   `pool_add` 用 `bucket.push_front(snapshot)` ⇒ 桶本身就是上传倒序。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_exact_match.tscn --quit-after 900

const Backend := preload("res://scripts/net/backend.gd")

var _ok := 0
var _fail := 0

func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])

## 造一份【别人的】快照。★必须带 origin=remote, 否则 `_is_self_ghost` 会把它当自己跳掉,
## 那样"没选中"就成了**别的原因**造成的, 判据变恒真式。
func _ghost(id: String, battles: int) -> Dictionary:
	return {
		"schema_ver": Backend.SCHEMA_VER,
		"ghost_id": id,
		"is_bot": false,
		"bracket": 3,
		"origin": Backend.ORIGIN_REMOTE,
		"profile": {"name": "对手%s" % id},
		"leaders": ["basic", "ninja", "stone"],
		"season_total_battles": battles,
	}

func _ready() -> void:
	await get_tree().process_frame
	print("── A6: 精确同场次 + 倒序取最新 ──")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260919

	## ── ① 场数不同的三份 ⇒ 必须选中场数 == N 的那份 ──
	var pool := {"brackets": {}}
	Backend.pool_add(pool, _ghost("r_low", 5))
	Backend.pool_add(pool, _ghost("r_mine", 12))
	Backend.pool_add(pool, _ghost("r_high", 20))
	_chk("① ★分母: 桶里确实有 3 份", (pool["brackets"]["3"] as Array).size() == 3,
		"%d 份" % (pool["brackets"]["3"] as Array).size())
	## ★先证明【不加过滤】时这三份都可能被选中 —— 否则下面"选中了 r_mine"
	##   可能只是因为另外两份本来就进不了候选, 判据就没测到过滤。
	var seen := {}
	for i in range(60):
		var r = Backend.pool_find(pool, 3, [], rng)
		if r != null:
			seen[str(r.get("ghost_id", ""))] = true
	_chk("① ★分母: 不加过滤时三份都可能被选中(证明过滤才是起作用的那一步)",
		seen.size() == 3, "选到过 %s" % str(seen.keys()))

	var got = Backend.pool_find(pool, 3, [], rng, 12)
	_chk("① ★精确过滤: 选中了场数 12 的那份", got != null and str(got.get("ghost_id", "")) == "r_mine",
		str(got.get("ghost_id", "")) if got != null else "null")
	var none = Backend.pool_find(pool, 3, [], rng, 7)
	_chk("① ★池里没有场数 7 的人 ⇒ 返回 null(回落交给 find_opponent, 不在这里兜底)",
		none == null)

	## ── ② 两份同为 N 场、上传先后不同 ⇒ 必须选中【较新】的那份 ──
	var pool2 := {"brackets": {}}
	Backend.pool_add(pool2, _ghost("r_old", 12))    # 先传
	Backend.pool_add(pool2, _ghost("r_new", 12))    # 后传 ⇒ push_front ⇒ 在前
	_chk("② ★分母: 两份都在且场数相同", (pool2["brackets"]["3"] as Array).size() == 2)
	var got2 = Backend.pool_find(pool2, 3, [], rng, 12)
	_chk("② ★同场次取最新那份(桶序 = 上传倒序)",
		got2 != null and str(got2.get("ghost_id", "")) == "r_new",
		str(got2.get("ghost_id", "")) if got2 != null else "null")

	## ── ③ ghost_id 真的带上了场次维, 且同一人不同场次【并存】不互相顶掉 ──
	var id_a: String = Backend.player_ghost_id(1, ["basic", "ninja", "stone"], 3)
	var id_b: String = Backend.player_ghost_id(1, ["basic", "ninja", "stone"], 4)
	var id_old: String = Backend.player_ghost_id(1, ["basic", "ninja", "stone"])
	_chk("③ ★同一人同阵容、不同场次 ⇒ 不同 id", id_a != id_b, "%s vs %s" % [id_a, id_b])
	## ★判据要卡住【结尾的 _b<数字>】, 不能用 `contains("_b")` ——
	##   老格式 id 里的 `_basic` 就含 "_b", 第一版这么写当场误报。
	##   (同族: 「判据要刚好卡住那个形状」—— 宽一格就造出假 bug。)
	var re_suffix := RegEx.new()
	re_suffix.compile("_b[0-9]+$")
	_chk("③ ★带场次时结尾是 _b<数字>", re_suffix.search(id_a) != null, id_a)
	_chk("③ ★不传场次 = 老格式(留给只验 id 互不相同的老门禁)",
		re_suffix.search(id_old) == null, id_old)
	var pool3 := {"brackets": {}}
	Backend.pool_add(pool3, _ghost(id_a, 3))
	Backend.pool_add(pool3, _ghost(id_b, 4))
	_chk("③ ★★同一人的两个场次在池里【并存】(这正是「场次低的人也能匹配到你」的前提)",
		(pool3["brackets"]["3"] as Array).size() == 2,
		"%d 份" % (pool3["brackets"]["3"] as Array).size())

	## ── ④ 记账: 三种来源各自计数(A-R3 靠它才答得了) ──
	var c0 := int(Backend.match_src_counts.get("exact", 0))
	Backend._tally("exact")
	_chk("④ ★匹配来源记账在走(exact 计数 +1)",
		int(Backend.match_src_counts.get("exact", 0)) == c0 + 1)

	_done()

func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 精确同场次匹配 (%d/%d)" % [_ok, _ok])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok])
	get_tree().quit(1 if _fail > 0 else 0)
