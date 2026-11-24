extends Node
## verify_lane_carryover.gd —— 换路清场: 上一路的东西一样都不许带进下一路(2026-11-15)。
##
## 用户 11-15:「你上半战场打完之后，你整个场没清干净嘛？…他有个龟带那个…放大器对吧？他在上半战场的最后一刻
##   释放了一个波，结果这个波怎么继承到下半战场，然后出 bug 了呢？这是个很严重的问题，你必须得修啊！」
## 正式服冠军杯决赛(referee_jobs 8845)本机逐字复现(v0.23.3, digest fdac3765… / 4074 步与正式服相同):
##   凤凰龟上路 25.63 秒放出 038 电磁波, 换路后 26.47~26.83 秒在下路打中精英 / 近战 / 远程小将与 2 个亡魂(魔伤 + 眩晕 2.5 秒)。
## 根因: DualLaneFlow._dl_clear_units 逐个调了装备延时队列 / 斧头 / 赛博 / 时停的 reset_for_lane, 漏了 SignalWaveSystem._waves;
##   放波的龟活着进下一路, 波的 tick 用 _pick_enemies_of(src) 扫到的就是下一路的敌人。
## ★同类不止一张表的可能 ⇒ 这条门禁不按名单查「谁清了没有」, 而是换路清场完那一刻**从战斗场出发通扫**:
##   所有脚本变量(各系统对象 → 数组 → 字典, 递归), 谁还拿着上一路的单位字典就报出路径。
##
## 判据:
##   ① 规则指纹那 5 局(verify_rules_fingerprint.CASES: 28 龟 / 全部装备 / 顶档羁绊 / 两边训龟大师, 裁判真入口 RefereeRunner.run):
##      每次换路后下一路战场搭好、开打之前(DualLaneFlow.on_lane_cleared, 各系统的换路撤场都跑完了), 通扫不许命中(KEEP 白名单除外, 各写理由)
##   ② ★038 定点: 第 1 局再跑一遍, 每一步左方没有在途波就让一只活着的左方单位放一道 ⇒ 换路那一刻必有在途波;
##      清场后 _sigwave._waves 为空、通扫不报
##   ③ 分母: 换路次数、每次扫到的对象 / 数组 / 字典数、② 换路前一步的在途波数
## 反向验证(11-15): 删掉 _dl_clear_units 里的 `_sigwave.reset_for_lane()` ⇒ ② 两条红、通扫报 `_equip_sys._sigwave._waves[0]{src}`。

const RF := preload("res://tests/verify_rules_fingerprint.gd")
const SC := preload("res://scripts/referee/det_scenarios.gd")

## 换路后**有意**还拿着上一路单位的地方(路径前缀 → 理由)。只放查过、确实不会再推进对局的。
const KEEP := {}

const MAX_DEPTH := 9
const MAX_ARR := 4000

var _n := 0
var _fail := 0
var _scan := {"obj": 0, "arr": 0, "dict": 0}


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, d])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 换路清场: 上一路的东西不许带进下一路 ===")
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)
	var rf = RF.new()
	## ── ① 5 局通扫 ──
	var clears := 0
	var games := 0
	var games_ok := 0
	var all_hits: Array = []
	for c in ([] if OS.has_environment("LC_ONLY_038") else RF.CASES):
		var pr := {"clears": 0, "hits": [], "scan": []}
		var res: Dictionary = await RefereeRunner.run(self, rf._job(c), func(bt) -> void:
			bt._dl_sys.on_lane_cleared = func(olds: Array) -> void: _on_cleared(bt, olds, pr))
		print("  [局] %s · %s · %d 步 · 换路 %d 次 · 扫描 %s" % [str(c["tag"]), "ok" if bool(res.get("ok", false)) else "ERR",
			int(res.get("steps", 0)), int(pr["clears"]), str(pr["scan"])])
		clears += int(pr["clears"])
		games += 1
		if bool(res.get("ok", false)) and int(pr["clears"]) >= 1:
			games_ok += 1
		for h in pr["hits"]:
			all_hits.append("%s: %s" % [str(c["tag"]), h])
	rf.free()
	## 11-15 实测: 5 局共换路 7 次(每局上 → 下, ④⑤ 两局再进终极); 11-24 钩锁瞄准改了(RULES_VER 9)后 6 次(只一局进终极)。
	##   ★判据量的是需求「每局都换过路 + 至少一局进了终极战场」(= 次数 ≥ 局数 + 1), 不钉某一次实测的次数
	_ok("① 分母: %d 局裁判都算完、每局至少换路 1 次(%d / %d), 共换路 %d 次 ≥ 局数 + 1(至少一局进终极)" % [games, games_ok, games, clears],
		games == RF.CASES.size() and games_ok == games and clears >= games + 1)
	_ok("① ★换路清场后, 战斗场里没有任何地方还拿着上一路的单位(%d 处)" % all_hits.size(), all_hits.is_empty(),
		"\n      " + "\n      ".join(PackedStringArray(all_hits.slice(0, 300))))
	## ── ② 038 定点 ──
	var rf2 = RF.new()
	var pr2 := {"clears": 0, "hits": [], "scan": [], "inflight": [], "after": [], "last_n": 0, "fired": 0}
	var res2: Dictionary = await RefereeRunner.run(self, rf2._job(RF.CASES[0]), func(bt) -> void:
		bt.sim_stepped.connect(func() -> void: _force_wave(bt, pr2))
		bt._dl_sys.on_lane_cleared = func(olds: Array) -> void:
			(pr2["inflight"] as Array).append(int(pr2["last_n"]))
			_on_cleared(bt, olds, pr2)
			(pr2["after"] as Array).append((bt._equip_sys._sigwave._waves as Array).size()))
	rf2.free()
	print("  [局] 038 定点 · %s · 换路 %d 次 · 手动放波 %d 道 · 换路前一步在途 %s · 清场后剩 %s" % [
		"ok" if bool(res2.get("ok", false)) else "ERR", int(pr2["clears"]), int(pr2["fired"]), str(pr2["inflight"]), str(pr2["after"])])
	var inflight_min: int = 99
	for k in pr2["inflight"]:
		inflight_min = mini(inflight_min, int(k))
	_ok("② 分母: 换路 %d 次 ≥ 1, 每次换路前一步都有在途电磁波(最少 %d 道)" % [int(pr2["clears"]), inflight_min],
		int(pr2["clears"]) >= 1 and inflight_min >= 1 and inflight_min < 99)
	var after_max := 0
	for k in pr2["after"]:
		after_max = maxi(after_max, int(k))
	_ok("② ★换路清场后 038 在途波一道不剩(最多剩 %d 道)" % after_max, after_max == 0)
	_ok("② ★换路清场后通扫不报(%d 处)" % (pr2["hits"] as Array).size(), (pr2["hits"] as Array).is_empty(),
		"\n      " + "\n      ".join(PackedStringArray((pr2["hits"] as Array).slice(0, 20))))
	## ── ③ 扫描本身不是空的 ──
	_ok("③ 分母: 通扫走过的对象 %d / 数组 %d / 字典 %d 都 > 0" % [int(_scan["obj"]), int(_scan["arr"]), int(_scan["dict"])],
		int(_scan["obj"]) > 0 and int(_scan["arr"]) > 0 and int(_scan["dict"]) > 0)
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


## 每一步: 场上没有在途波 ⇒ 挑一只活着的单位(哪边都行: 一路打完时只有赢的那边还有人)朝对面一个活着的放一道(038 一星);
##   对面已经死光 ⇒ tgt 传空字典(_fire 按 Vector2.RIGHT 放)。记下这一步之后的在途数。
func _force_wave(bt, pr: Dictionary) -> void:
	var sw = bt._equip_sys._sigwave
	if (bt._units as Array).is_empty():
		return   # 换路幕布期间(上一路清完、下一路还没生成): 不放、也不改「换路前一步」的在途数
	if (sw._waves as Array).is_empty():
		var src = null
		for u in bt._units:
			if u.get("alive", false) and not u.get("_isEgg", false) and not u.get("is_trainer", false):
				src = u
				break
		if src != null:
			var tgt: Dictionary = {}
			for u in bt._units:
				if u.get("alive", false) and not u.get("_isEgg", false) and not u.get("is_trainer", false) \
						and str(u.get("side", "")) != str(src.get("side", "")):
					tgt = u
					break
			sw._fire(src, tgt, 0, {})
			pr["fired"] = int(pr["fired"]) + 1
	pr["last_n"] = (sw._waves as Array).size()
	## 查「换路前一步为什么没有在途波」用: LC_TRACE=1 逐步打印(LC_ONLY_038=1 只跑 ②)
	if OS.has_environment("LC_TRACE"):
		var al := 0
		for u in bt._units:
			if u.get("alive", false):
				al += 1
		var who: Array = []
		for u in bt._units:
			if u.get("alive", false):
				who.append("%s/%s/%s%s" % [str(u.get("pet", u.get("name", "?"))), str(u.get("side", "")), "E" if u.get("_isEgg", false) else "", "T" if u.get("is_trainer", false) else ""])
		print("LC_TRACE t=%.2f units=%d alive=%d waves=%d st=%s over=%s %s" % [float(bt._t), (bt._units as Array).size(), al, (sw._waves as Array).size(), str(bt._dl_state), str(bt._over), str(who)])


func _on_cleared(bt, olds: Array, pr: Dictionary) -> void:
	pr["clears"] = int(pr["clears"]) + 1
	var s0 := _scan.duplicate()
	var hits: Array = []
	_visit(bt, "battle", olds, hits, {}, 0)
	(pr["scan"] as Array).append("%d/%d/%d" % [int(_scan["obj"]) - int(s0["obj"]), int(_scan["arr"]) - int(s0["arr"]),
		int(_scan["dict"]) - int(s0["dict"])])
	for h in hits:
		var kept := false
		for k in KEEP.keys():
			if str(h).begins_with(str(k)):
				kept = true
				break
		if not kept and not (pr["hits"] as Array).has(h):
			(pr["hits"] as Array).append(h)


func _is_unit(d: Dictionary) -> bool:
	return d.has("side") and d.has("hp") and d.has("pos") and d.has("alive")


## 通扫: 对象(只走 res://scripts/ 下的脚本变量, 按实例去重) → 数组 → 字典。单位字典不往里走(互相引用成环), 只比是不是上一路的。
func _visit(v, path: String, olds: Array, hits: Array, seen: Dictionary, depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	match typeof(v):
		TYPE_OBJECT:
			if v == null or not is_instance_valid(v):
				return
			var id: int = (v as Object).get_instance_id()
			if seen.has(id):
				return
			seen[id] = true
			var sc = (v as Object).get_script()
			if sc == null or not str(sc.resource_path).begins_with("res://scripts/"):
				return
			_scan["obj"] = int(_scan["obj"]) + 1
			for p in (v as Object).get_property_list():
				if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
					continue
				var nm := str(p["name"])
				_visit((v as Object).get(nm), path + "." + nm, olds, hits, seen, depth + 1)
		TYPE_ARRAY:
			_scan["arr"] = int(_scan["arr"]) + 1
			var a: Array = v
			for i in range(mini(a.size(), MAX_ARR)):
				_visit(a[i], "%s[%d]" % [path, i], olds, hits, seen, depth + 1)
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if _is_unit(d):
				for o in olds:
					if is_same(o, d):
						hits.append(path)
						break
				return
			_scan["dict"] = int(_scan["dict"]) + 1
			for k in d.keys():
				_visit(d[k], "%s{%s}" % [path, str(k)], olds, hits, seen, depth + 1)
