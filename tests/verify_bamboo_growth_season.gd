extends Node
## verify_bamboo_growth_season.gd —— 竹叶龟【生长】永久最大生命: 18% / 25% × 攻击力 + 一大轮内跨场累积(2026-11-19)
##
## 用户 11-19:「竹叶龟的被动…永久提升最大生命值…希望改为随一大轮保留…新的一大轮会重置…一直打下去…越来越多…
##   不应该是基础攻击力，就是攻击力的百分比…没有带足迹(竹击)的情况下…百分之十八的攻击力…携带了足迹…百分之二十五乘攻击力」
##   答未决点:「就跟命运之轮一一样的，一直的上路成长，那肯定是在对。嗯，没有上限…竹弓…不要动啊。说明你要显示」
## 方案书 docs/plans/20261119-竹叶龟生长随大轮保留.md
##   ① 系数与底数: 攻击力 100 / 基础攻击力 40 ⇒ 不带竹击 +18、带竹击 +25(按攻击力, 不是基础攻击力)
##   ② 这一局的账 grown: 左右各记各的; 缩头随从那只竹叶龟不记
##   ③ 登场: 左方 + 存档累积、右方 + 对手快照累积; 满血登场
##   ④ 终极战场重建: + 本大轮累积 + 这一局已长的, 血量按原比例(带血进终极的不被回满)
##   ⑤ 快照读数: 只认有限正数、封到上限; 本机快照长过才带 bamboo_hp
##   ⑥ 结果回包 → 入账: parse_bamboo / apply_bamboo 累加; 缺键 / 坏值什么都不发
##   ⑦ 存档读写 + 新大轮清零; 旧录像(没这个键)回放时清 0
##   ⑧ 裁判: 封顶取较小值; 结果单 / 左方状态一律写这个键(源码)
##   ⑨ 说明里那一行: 有累积才显示「本大轮已累积：最大生命值 +N」
## 反向验证见本文件末尾注释。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BE := preload("res://scripts/net/backend.gd")
const RNET := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RJ := preload("res://scripts/referee/referee_job.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(side: String, px: float) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("bamboo", side, Vector2(px, 400.0))
	u["alive"] = true
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 竹叶龟·生长: 18%/25%×攻击力 + 一大轮内跨场累积 ===")
	var keep_hp: float = float(gs.bamboo_growth_hp)
	var keep_ghost = gs.dual_ghost
	var keep_lo: Dictionary = (gs.loadouts as Dictionary).duplicate()
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false
	var bs = _s._bamboo_sys

	# ① 系数与底数
	gs.loadouts.erase("bamboo")
	var a1 := _mk("left", 400.0)
	a1["atk"] = 100.0; a1["base_atk"] = 40.0
	a1["maxHp"] = 1000.0; a1["hp"] = 1000.0
	_s._units.clear(); _s._units.append(a1)
	bs.grown = {"left": 0.0, "right": 0.0}
	bs.grow_absorb(a1)
	_ok("① ★不带竹击: 最大生命 +18(18%×攻击力 100, 不是基础攻击力 40)", absf(float(a1["maxHp"]) - 1018.0) < 0.01, "%.2f" % float(a1["maxHp"]))
	_ok("① 当前生命同加", absf(float(a1["hp"]) - 1018.0) < 0.01, "%.2f" % float(a1["hp"]))
	gs.loadouts["bamboo"] = 2   # skillPool[2] = bambooSmack
	_ok("① 分母: 竹叶龟此刻选的是【竹击】", "bambooSmack" in _s._chosen_skill_types("bamboo", true))
	a1["atk"] = 100.0   # 上一次吸收后 _recalc_stats 按基础攻击力重算回 40(合成单位没有装备); 真对局里攻击力本来就是重算出来的
	var m0: float = float(a1["maxHp"])
	bs.grow_absorb(a1)
	_ok("① ★带竹击: 最大生命 +25(25%×攻击力 100)", absf(float(a1["maxHp"]) - m0 - 25.0) < 0.01, "+%.2f" % (float(a1["maxHp"]) - m0))
	gs.loadouts.erase("bamboo")

	# ② 这一局的账
	_ok("② ★左方这一局记 43(18 + 25)", absf(float(bs.grown["left"]) - 43.0) < 0.01, "%.2f" % float(bs.grown["left"]))
	var r2 := _mk("right", 700.0)
	r2["atk"] = 50.0
	bs.grow_absorb(r2)
	_ok("② 右方各记各的(+9)", absf(float(bs.grown["right"]) - 9.0) < 0.01 and absf(float(bs.grown["left"]) - 43.0) < 0.01, "%.2f" % float(bs.grown["right"]))
	var mn := _mk("left", 420.0)
	mn["minion_kind"] = "hiding"
	mn["atk"] = 100.0
	bs.grow_absorb(mn)
	_ok("② 缩头随从那只竹叶龟不记进玩家的账", absf(float(bs.grown["left"]) - 43.0) < 0.01, "%.2f" % float(bs.grown["left"]))

	# ③ 登场
	gs.bamboo_growth_hp = 500.0
	gs.dual_ghost = {"bamboo_hp": 300.0}
	bs.grown = {"left": 0.0, "right": 0.0}
	var l3 := _mk("left", 400.0)
	var base_l: float = float(l3["maxHp"])
	_s._units.clear(); _s._units.append(l3)
	_s._spawn._apply_spawn_passive_one(l3)
	_ok("③ ★左方登场 + 存档累积 500", absf(float(l3["maxHp"]) - base_l - 500.0) < 0.01, "%.0f → %.0f" % [base_l, float(l3["maxHp"])])
	_ok("③ 满血登场", absf(float(l3["hp"]) - float(l3["maxHp"])) < 0.01)
	var r3 := _mk("right", 700.0)
	var base_r: float = float(r3["maxHp"])
	_s._spawn._apply_spawn_passive_one(r3)
	_ok("③ ★右方登场 + 对手快照累积 300", absf(float(r3["maxHp"]) - base_r - 300.0) < 0.01, "%.0f → %.0f" % [base_r, float(r3["maxHp"])])

	# ④ 终极战场重建: + 这一局已长的, 血量按比例
	bs.grown = {"left": 27.0, "right": 0.0}
	var l4 := _mk("left", 400.0)
	var base4: float = float(l4["maxHp"])
	l4["hp"] = base4 * 0.5   # 带一半血进终极(battle_spawn 先按 hp_frac 定血, 再跑登场被动)
	_s._spawn._apply_spawn_passive_one(l4)
	_ok("④ ★终极战场: + 存档 500 + 这一局上路长的 27", absf(float(l4["maxHp"]) - base4 - 527.0) < 0.01, "%.0f → %.0f" % [base4, float(l4["maxHp"])])
	_ok("④ 血量按原比例 50%(不被回满)", absf(float(l4["hp"]) / float(l4["maxHp"]) - 0.5) < 0.001, "%.3f" % (float(l4["hp"]) / float(l4["maxHp"])))
	gs.bamboo_growth_hp = 0.0
	gs.dual_ghost = {}
	bs.grown = {"left": 0.0, "right": 0.0}
	var l4b := _mk("left", 400.0)
	var b4b: float = float(l4b["maxHp"])
	_s._spawn._apply_spawn_passive_one(l4b)
	_ok("④ 分母: 什么都没攒 ⇒ 登场不变", absf(float(l4b["maxHp"]) - b4b) < 0.01)

	# ⑤ 快照读数
	_ok("⑤ 快照读数: 坏值一律 0(字符串 / 负数 / 缺键 / NaN)",
		BE.ghost_bamboo_hp({"bamboo_hp": "999"}) == 0.0 and BE.ghost_bamboo_hp({"bamboo_hp": -5.0}) == 0.0
		and BE.ghost_bamboo_hp({}) == 0.0 and BE.ghost_bamboo_hp(null) == 0.0 and BE.ghost_bamboo_hp({"bamboo_hp": NAN}) == 0.0)
	_ok("⑤ 快照读数: 正数留两位、超大封到 %.0f" % BE.BAMBOO_HP_MAX,
		absf(BE.ghost_bamboo_hp({"bamboo_hp": 12.345}) - 12.35) < 0.001 and BE.ghost_bamboo_hp({"bamboo_hp": 1e12}) == BE.BAMBOO_HP_MAX)
	var bsrc := FileAccess.get_file_as_string("res://scripts/net/backend.gd")
	_ok("⑤ 本机快照: 长过才带 bamboo_hp(build_ghost_snapshot)", bsrc.find("out[\"bamboo_hp\"] = bh") > 0 and bsrc.find("if bh > 0.0:") > 0)

	# ⑥ 回包 → 入账
	_ok("⑥ parse_bamboo: 9.123 → 9.12、缺 / 字符串 → 0",
		absf(RNET.parse_bamboo(9.123) - 9.12) < 0.001 and RNET.parse_bamboo(null) == 0.0 and RNET.parse_bamboo("5") == 0.0)
	gs.bamboo_growth_hp = 100.0
	var ok1: bool = RW.apply_bamboo(gs, {"bamboo_new": 9.5})
	_ok("⑥ ★apply_bamboo 累加: 100 + 9.5 = 109.5", ok1 and absf(float(gs.bamboo_growth_hp) - 109.5) < 0.001, "%.2f" % float(gs.bamboo_growth_hp))
	var ok2: bool = RW.apply_bamboo(gs, {})
	var ok3: bool = RW.apply_bamboo(gs, {"bamboo_new": -3.0})
	_ok("⑥ 缺键 / 负数 ⇒ 什么都不发", not ok2 and not ok3 and absf(float(gs.bamboo_growth_hp) - 109.5) < 0.001)

	# ⑦ 存档读写 + 新大轮清零 + 旧录像
	var sd: Dictionary = gs._save_dict()
	_ok("⑦ 存档带 bamboo_growth_hp", absf(float(sd.get("bamboo_growth_hp", -1.0)) - 109.5) < 0.001)
	gs.bamboo_growth_hp = 0.0
	gs._apply_save_dict({"bamboo_growth_hp": 77.0})
	_ok("⑦ 读档读回来", absf(float(gs.bamboo_growth_hp) - 77.0) < 0.001, "%.2f" % float(gs.bamboo_growth_hp))
	var wsrc := FileAccess.get_file_as_string("res://autoload/GameState.gd").replace("\r\n", "\n")
	var fi := wsrc.find("\nfunc start_new_season()")
	var fj := wsrc.find("\nfunc ", fi + 5)
	var ci := wsrc.find("\nfunc _clear_week_carry()")
	var cj := wsrc.find("\nfunc ", ci + 5)
	_ok("⑦ ★新大轮清零(start_new_season 调 _clear_week_carry, 里面 bamboo_growth_hp = 0.0)",
		fi > 0 and wsrc.substr(fi, (fj - fi) if fj > fi else -1).find("_clear_week_carry()") > 0
		and ci > 0 and wsrc.substr(ci, (cj - ci) if cj > ci else -1).find("bamboo_growth_hp = 0.0") > 0)   # 是文件最后一个函数时 find 返回 -1
	_ok("⑦ 录像 STATE_KEYS 带 bamboo_growth_hp", "bamboo_growth_hp" in ReplayRecorder.STATE_KEYS)
	gs.bamboo_growth_hp = 55.0
	ReplayRecorder.apply_state({"season_level": int(gs.season_level)})
	_ok("⑦ ★旧录像(没这个键)回放: 清 0, 不让看的人自己的累积顶进去", float(gs.bamboo_growth_hp) == 0.0, "%.2f" % float(gs.bamboo_growth_hp))

	# ⑧ 裁判
	_ok("⑧ 封顶取较小值: (500, 300) → 300、(200, 300) → 200", absf(RJ.bamboo_cap(500.0, 300) - 300.0) < 0.001 and absf(RJ.bamboo_cap(200.0, 300.0) - 200.0) < 0.001)
	var jsrc := FileAccess.get_file_as_string("res://scripts/referee/referee_job.gd")
	_ok("⑧ 左方状态一律写 bamboo_growth_hp(旧客户端交的状态没有也不沿用上一局)", jsrc.find("\tst[\"bamboo_growth_hp\"] = BE.ghost_bamboo_hp(") > 0)
	var rsrc := FileAccess.get_file_as_string("res://scripts/referee/referee_runner.gd")
	_ok("⑧ 结果单带 bamboo_new / bamboo_new_b", rsrc.find("res[\"bamboo_new\"] = ") > 0 and rsrc.find("res[\"bamboo_new_b\"] = ") > 0)

	# ⑨ 说明那一行
	_ok("⑨ 有累积 ⇒「本大轮已累积：最大生命值 +123」; 没有 ⇒ 空", BambooSystem.season_note(123.4).find("最大生命值 +123") >= 0 and BambooSystem.season_note(0.0) == "")

	gs.bamboo_growth_hp = keep_hp
	gs.dual_ghost = keep_ghost
	gs.loadouts = keep_lo
	_s._units.clear()   # 不用 erase: 单位字典按内容比较会递归(CLAUDE.md §4.2)
	print("=== 共 %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0 and _n >= 25:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)

## 反向验证(11-19): 底数写回 base_atk ⇒ ① 红; 登场不套用 ⇒ ③④ 红; apply_bamboo 不累加 ⇒ ⑥ 红; _clear_week_carry 不清 ⇒ ⑦ 红;
##   apply_state 不清 ⇒ ⑦ 红; 终极战场不加 grown ⇒ ④ 红。
