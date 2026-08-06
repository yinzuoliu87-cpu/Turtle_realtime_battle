extends Node
## verify_b4_wiring.gd — 批④(077~094 共 17 件)的【接线】门禁
##
## 2026-08-06 用户把这十七件逐件亲手重做（方案书 `docs/plans/20260805-装备逐件重做.md` §0.5）。
## 实装分工与接口见 `docs/plans/20260806-实装契约-批④.md`。
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁替换了谁, 为什么
## ══════════════════════════════════════════════════════════════════════
## 它取代 `tests/verify_equip_periodic_batch1.gd`（609 行·批①周期类）。
## 那份文件里**每一个**逐件测试测的都是 077/079/080/081/087/088/089/090/091/094 的
## **旧效果**——十件全被整条重做掉了，所以它不是"需要修几条断言"，是**整份过时**。
## 逐件的数值门禁改由各路自己的 `tests/verify_eq_*_batch.gd` 承担；
## **这份只守结构**：十七件有没有真的接上、有没有漏、旧的有没有真的拆干净。
##
## ★为什么结构也要单独守：分派表写错不会崩、不会报错，只会让某件装备**静默不生效**，
##   而它自己的逐件门禁如果是直接调效果函数的，照样全绿（memory
##   [[fb-verify-must-run-the-real-path]]：「断言函数存在」守不住「还有没有人调它」）。
##
## ══════════════════════════════════════════════════════════════════════
##  本文件的规矩
## ══════════════════════════════════════════════════════════════════════
## · 源码扫描一律**先剥注释**——否则会命中我自己写的说明文字（这个项目吃过两次亏：
##   把 `pass  # battle._hpl.check(u)` 判成"接线还在"）。
## · 每组带一条**分母**断言（N=0 是空检查不是通过）。
## · 期望值**不引用被测常量**（引用就是拿代码跟自己比，永远绿）。
## · 能用**真行为**验的就不用源码扫描：`_b4_eq` 这条走真的 `_eq_apply_all_stats`。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 批④ 十七件（字面写死，**不从 B4_OWNER 读** —— 读了就是拿表跟自己比）
const B4_IDS := [
	"p2eq_077", "p2eq_078", "p2eq_079", "p2eq_080",
	"p2eq_081", "p2eq_082", "p2eq_083", "p2eq_084",
	"p2eq_085", "p2eq_086", "p2eq_087",
	"p2eq_088", "p2eq_089", "p2eq_090",
	"p2eq_091", "p2eq_093", "p2eq_094",
]

## 十七件的旧效果函数（被整批删除，留一个就是死代码被门禁保护着）
const DEAD_FNS := [
	"_double_barrel_shot", "_eq_derringer_volley", "_derringer_shot",
	"_eq_armory_burst", "_armory_shot", "_eq_breacher_cannon",
	"_eq_wicker_shield", "_eq_abyss_mint", "_eq_tide_scepter",
	"_eq_eclipse_talisman", "_eq_tide_codex", "_eq_ancient_scute",
	"_eq_awaken_core", "_eq_tide_rapier", "_eq_clam_mitigate",
	"_eq_fang_refresh", "_eq_brass_ward", "_eq_polar_recoil",
]

## 十七件的旧常驻字段（写入点已撤；留着写入 = 旧行为还在跑）
const DEAD_FIELDS := ["_clam_dr", "_fang_pct", "_fang_ls", "_b3_gadget", "_apply_altar_egg_hp"]

var _n := 0
var _fail := 0
var _s = null
var _code := ""      # equip_system.gd（已剥注释）
var _apply := ""     # equip_stats_apply.gd（已剥注释）


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 剥掉行注释后的源码。★不剥的话下面每一条扫描都会命中注释里的说明文字。
func _strip(path: String) -> String:
	var raw: String = FileAccess.get_file_as_string(path)
	var out := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		out += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	return out


## 取某个函数的函数体（到下一个顶格 func 为止）。
func _fn_body(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var e: int = code.find("\nfunc ", i + 1)
	return code.substr(i, (e - i) if e > i else -1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 批④ 接线门禁(077~094 共 17 件) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	# ⓪ 分母: 场景与源码都真的拿到了(拿不到的话下面全是空检查)
	_ok("⓪ ★分母: 战斗场景实例化成功", _s != null and _s._equip_sys != null)
	_code = _strip("res://scripts/systems/equip/equip_system.gd")
	_apply = _strip("res://scripts/systems/equip/equip_stats_apply.gd")
	_ok("⓪ ★分母: equip_system.gd 剥注释后仍非空", _code.length() > 20000, "len=%d" % _code.length())
	_ok("⓪ ★分母: equip_stats_apply.gd 剥注释后仍非空", _apply.length() > 3000, "len=%d" % _apply.length())
	if _s == null or _s._equip_sys == null or _code.length() < 20000:
		print("FAIL x%d — 前置分母不成立, 后面全是空检查, 提前退出" % maxi(_fail, 1))
		get_tree().quit(1)
		return

	_t_owner_table()
	_t_hooks()
	_t_old_removed()
	_t_spawn_flag()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 批④ 接线(17 件)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 路由表: 十七件一件不少, 每件都指到一个真的存在的系统
# ─────────────────────────────────────────────────────────────
func _t_owner_table() -> void:
	print("── ① 路由表 ──")
	var es = _s._equip_sys
	var miss: Array = []
	var nullsys: Array = []
	for iid in B4_IDS:
		if not es.B4_OWNER.has(iid):
			miss.append(iid)
			continue
		if es._b4(iid) == null:
			nullsys.append(iid)
	_ok("① 十七件全在 B4_OWNER 表里", miss.is_empty(), "缺 %s" % str(miss))
	_ok("① 每件都能 _b4() 取到一个非 null 的系统", nullsys.is_empty(), "取不到 %s" % str(nullsys))
	_ok("① ★分母: 表的大小正好是 17(多了就是有别的 id 混进来)",
		es.B4_OWNER.size() == 17, "size=%d" % es.B4_OWNER.size())
	# ★反向: 不是批④的件必须取不到系统(否则 _b4 恒返回同一个东西, 上面那条恒真)
	_ok("① ★反向: 非批④的件(001/060/075)取不到系统",
		es._b4("p2eq_001") == null and es._b4("p2eq_060") == null and es._b4("p2eq_075") == null)

	# 六个系统: 非 null、互不相同
	var all: Array = es._b4_all()
	_ok("① _b4_all() 返回 6 个系统", all.size() == 6, "size=%d" % all.size())
	var distinct := 0
	for i in range(all.size()):
		if all[i] == null:
			continue
		var dup := false
		for j in range(i):
			if all[j] != null and is_same(all[i], all[j]):
				dup = true
		if not dup:
			distinct += 1
	_ok("① 六个系统互不相同且都非 null", distinct == 6, "distinct=%d" % distinct)

	# 每一路的件数(照 §0.5 分工写死, 不从表里数)
	var cnt: Dictionary = {}
	for iid in B4_IDS:
		var k: String = str(es.B4_OWNER.get(iid, "?"))
		cnt[k] = int(cnt.get(k, 0)) + 1
	_ok("① 分路件数 = 枪4/盾剑4/奇械3/法器3/遗物2/香火石1",
		int(cnt.get("gun", 0)) == 4 and int(cnt.get("blade", 0)) == 4
		and int(cnt.get("gadget", 0)) == 3 and int(cnt.get("arcane", 0)) == 3
		and int(cnt.get("relic", 0)) == 2 and int(cnt.get("incense", 0)) == 1,
		str(cnt))


# ─────────────────────────────────────────────────────────────
# ② 十个钩子: EquipSystem 真的把它们分派出去了
#    ★这是本文件最重要的一组 —— 分派漏了不会崩、不会报错, 只会让装备静默不生效
# ─────────────────────────────────────────────────────────────
func _t_hooks() -> void:
	print("── ② 钩子分派 ──")
	# 钩子函数名 → 它的函数体里必须出现的调用
	var need := {
		"func _eq_on_basic_attack": ".on_basic(",
		"func _eq_on_hit": ".on_hit(",
		"func _eq_on_target": ".on_damaged(",
		"func _eq_on_death": ".on_death(",
		"func _eq_on_magic_hurt": ".on_magic_hurt(",
	}
	var bad: Array = []
	var checked := 0
	for hdr in need:
		var body: String = _fn_body(_code, hdr)
		if body.length() < 50:
			bad.append("%s 函数体取不到(len=%d)" % [hdr, body.length()])
			continue
		checked += 1
		if not body.contains(str(need[hdr])):
			bad.append("%s 里没有 %s" % [hdr, str(need[hdr])])
	_ok("② 五个逐件钩子都把批④分派出去了", bad.is_empty(), str(bad))
	_ok("② ★分母: 真的取到了 5 个函数体(取不到会让上面那条恒真)", checked == 5, "checked=%d" % checked)

	# tick / tick_unit: 全局与逐单位两条驱动
	# ★★2026-08-06 全局那条从 `_eq_tick` 里【搬出来】成了 `EquipSystem.tick_global`。
	#   原因(E 路 agent 报的真耦合): `_eq_tick` 挂在主循环的
	#   `if not u.get("equips", []).is_empty():` 之内 ⇒ **场上没有一个带装备的活单位时,
	#   全局在途表就停摆**。而 094 祖龟碑正是"携带者已经死了、碑还要继续放光环和石雷",
	#   077 的小手枪 / 079 的炮台 / 080 的直升机也都要在携带者死后继续动。
	var gl_body: String = _fn_body(_code, "func tick_global")
	_ok("② tick_global 里有【全局】驱动 `_b4_all()` 的 tick(delta)",
		gl_body.contains("_b4_all()") and gl_body.contains(".tick(delta)"),
		"len=%d" % gl_body.length())
	_ok("② ★分母: tick_global 函数体非空", gl_body.length() > 100, "len=%d" % gl_body.length())
	# ★★接线: 主循环真的每帧调它 —— 不调的话上面全绿而游戏里碑/召唤物一动不动
	var rb_src: String = _strip("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("② ★★主循环每帧调 `_equip_sys.tick_global(dt)`",
		rb_src.contains("_equip_sys.tick_global(dt)"), "rb_len=%d" % rb_src.length())
	# ★判据要精准: `_eq_tick` 里【仍然】有 `_b4_all()`(逐单位那条驱动就在里面),
	#   所以不能拿 `_b4_all()` 当判据 —— 那样写会永远红。真正要守的是
	#   "全局那种 `.tick(delta)` 的调用不许再出现在这个逐单位函数里"。
	_ok("② ★全局的 .tick(delta) 不在【逐单位】的 _eq_tick 里(那正是 E 路报的耦合)",
		not _fn_body(_code, "func _eq_tick").contains(".tick(delta)"), "")

	var tick_body: String = _fn_body(_code, "func _eq_tick")
	_ok("② _eq_tick 里有【逐单位】驱动 tick_unit(u, delta)",
		tick_body.contains(".tick_unit(u, delta)"), "len=%d" % tick_body.length())
	_ok("② 逐单位驱动由常驻字段 `_b4_eq` 守门(不遍历 equips = 零开销)",
		tick_body.contains("_b4_eq"), "")

	# 法器三件走 on_mana_full(它们的触发时机是法力条满, 不排周期)
	var fire_body: String = _fn_body(_code, "func fire_equip_effect")
	_ok("② 法器三件(088/089/090)在 fire_equip_effect 里路由到 on_mana_full",
		fire_body.contains("\"p2eq_088\"") and fire_body.contains("\"p2eq_089\"")
		and fire_body.contains("\"p2eq_090\"") and fire_body.contains("on_mana_full("),
		"len=%d" % fire_body.length())
	_ok("② ★分母: fire_equip_effect 函数体非空", fire_body.length() > 500, "len=%d" % fire_body.length())

	# 登场钩: _eq_apply_all_stats 末尾统一跑一遍
	var all_body: String = _fn_body(_apply, "func _eq_apply_all_stats")
	_ok("② 登场钩 `_b4_on_spawn_all()` 挂在 _eq_apply_all_stats 上",
		all_body.contains("_b4_on_spawn_all()"), "len=%d" % all_body.length())
	var spawn_body: String = _fn_body(_apply, "func _b4_on_spawn_all")
	_ok("② `_b4_on_spawn_all` 真的调了 on_spawn 且写了 `_b4_eq`",
		spawn_body.contains(".on_spawn(") and spawn_body.contains("_b4_eq"),
		"len=%d" % spawn_body.length())

	# 换路撤场: dual_lane_flow 要调 clear_all
	var dl: String = _strip("res://scripts/scenes/battle/dual_lane_flow.gd")
	_ok("② 换路时会调批④六个系统的 clear_all()",
		dl.contains("_b4_all()") and dl.contains("clear_all()"),
		"dl_len=%d" % dl.length())


# ─────────────────────────────────────────────────────────────
# ③ 旧的真的拆干净了(留一个就是"新旧同时生效"或"死代码被门禁保护")
# ─────────────────────────────────────────────────────────────
func _t_old_removed() -> void:
	print("── ③ 旧效果拆干净 ──")
	var left: Array = []
	for fn in DEAD_FNS:
		if _code.contains("func %s(" % fn):
			left.append(fn)
	_ok("③ 十八个旧效果函数全部删净(留着 = 零调用者的死代码)", left.is_empty(), "残留 %s" % str(left))
	_ok("③ ★分母: 名单非空(%d 个)" % DEAD_FNS.size(), DEAD_FNS.size() == 18, "")
	# ★反向分母: 拿一个【确实还在】的函数验证扫描方式有效, 否则上面那条可能因为
	#   `contains("func x(")` 这个写法根本匹配不上而恒真。
	_ok("③ ★反向分母: 扫描方式有效(还活着的 `_eq_on_hit` 能被扫到)",
		_code.contains("func _eq_on_hit("), "")

	var fleft: Array = []
	for f in DEAD_FIELDS:
		if _apply.contains("\"%s\"] =" % f) or _apply.contains("%s()" % f):
			fleft.append(f)
	_ok("③ 旧常驻字段的写入点全部撤掉(_clam_dr/_fang_*/_b3_gadget/龟蛋加血)",
		fleft.is_empty(), "残留 %s" % str(fleft))

	# 消费点也要撤 —— 写入撤了消费点留着不会报错, 只会永远读到默认值(看着像"没生效")
	var dmg: String = _strip("res://scripts/scenes/battle/battle_damage.gd")
	_ok("③ battle_damage 里 082 的旧减伤消费点已撤(_eq_clam_mitigate 0 处)",
		not dmg.contains("_eq_clam_mitigate"), "")
	_ok("③ battle_damage 的法术受伤守卫已从 `_b3_gadget` 换成 `_b4_eq`",
		not dmg.contains("_b3_gadget") and dmg.contains("_b4_eq"), "")

	# 周期表: 十七件一件都不许留(留着 = 每帧多查一次永远不成立的分支)
	var iv: Dictionary = _s._equip_sys.EQ_IV_BATCH1
	var still: Array = []
	for iid in B4_IDS:
		if iv.has(iid):
			still.append(iid)
	_ok("③ EQ_IV_BATCH1 里一件批④装备都没有(它们全改成召唤/触发式了)",
		still.is_empty(), "残留 %s" % str(still))
	_ok("③ ★分母: 周期表里真周期件(067 毒药瓶 / 075 测距绳结)还在",
		iv.has("p2eq_067") and iv.has("p2eq_075"),
		"size=%d keys=%s" % [iv.size(), str(iv.keys())])


# ─────────────────────────────────────────────────────────────
# ④ 真行为: `_b4_eq` 这条不靠源码扫描, 走真的 `_eq_apply_all_stats`
# ─────────────────────────────────────────────────────────────
func _t_spawn_flag() -> void:
	print("── ④ 登场标记(真行为, 非源码扫描) ──")
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	# 带批④件的
	var withb4: Dictionary = _s._spawn._make_unit("fortune", "left", c + Vector2(-200.0, -120.0))
	withb4["equips"] = [{"id": "p2eq_083", "star": 1}]
	withb4["eq_state"] = {}
	_s._units.append(withb4)
	# 不带的(分母)
	var plain: Dictionary = _s._spawn._make_unit("fortune", "left", c + Vector2(-200.0, 120.0))
	plain["equips"] = [{"id": "p2eq_001", "star": 1}]
	plain["eq_state"] = {}
	_s._units.append(plain)

	_s._equip_sys._stats._eq_apply_all_stats()

	_ok("④ 带批④装备的单位 `_b4_eq` = true", bool(withb4.get("_b4_eq", false)),
		"实测 %s" % str(withb4.get("_b4_eq", null)))
	_ok("④ ★分母: 不带批④装备的单位 `_b4_eq` 仍为 false(不是所有人都被打上)",
		not bool(plain.get("_b4_eq", false)), "实测 %s" % str(plain.get("_b4_eq", null)))
	_s._units.clear()
	_t33_both_paths()


# ─────────────────────────────────────────────────────────────
# ⑤ ★★CLAUDE.md §3.3: 受伤钩必须【两条伤害路径都挂】
#
#    这一条是本文件最值钱的一组, 因为它守的正是这次实装挖出来的既有缺口:
#    `_eq_on_target` 只挂在 `_apply_damage_from`(普攻/技能)上, DoT/真伤那条路
#    (`_apply_damage`)【根本不调它】⇒ 081 的举盾充能条 / 085 的受伤转龟能 /
#    087 的压载舱 会漏掉灼烧·中毒·流血·诅咒·真伤的全部伤害, 而且不会报任何错。
#
#    ★用【真行为】验, 不用源码扫描: `_b4_on_damaged_any` 会在单位字典上写 `_b4_dot`
#      (进这条路置 true, 出去置 false), `_eq_on_target` 的批④分支写 false。
#      ⇒ **这个键存不存在** 就是"批④受伤路由到底跑没跑"的同步证据 —— 它是被测代码
#      自己写的副作用, 不是我重新实现了一遍公式再跟自己比(那是恒真式)。
# ─────────────────────────────────────────────────────────────
func _t33_both_paths() -> void:
	print("── ⑤ §3.3 两条伤害路径都要挂受伤钩 ──")
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5

	# ① DoT/真伤路: _apply_damage
	var a: Dictionary = _mk_probe(c + Vector2(-260.0, -160.0), "p2eq_081")
	a.erase("_b4_dot")
	_s._damage._apply_damage(a, 50, Color("#ff8844"), null, "dot")
	_ok("⑤ ★★【DoT/真伤路】_apply_damage 走到了批④受伤路由", a.has("_b4_dot"),
		"_b4_dot=%s" % str(a.get("_b4_dot", "键不存在")))

	# ② 普攻/技能路: _apply_damage_from
	var b: Dictionary = _mk_probe(c + Vector2(-260.0, -80.0), "p2eq_081")
	var atk: Dictionary = _mk_probe(c + Vector2(-60.0, -80.0), "p2eq_001")
	atk["side"] = "right"
	b.erase("_b4_dot")
	_s._damage._apply_damage_from(atk, b, 50, Color("#ffffff"))
	_ok("⑤ ★★【普攻/技能路】_apply_damage_from 走到了批④受伤路由", b.has("_b4_dot"),
		"_b4_dot=%s" % str(b.get("_b4_dot", "键不存在")))

	# ③ 分母: 不带批④装备的单位, 两条路都【不该】写这个键
	#    —— 没有这条的话, 上面两条在"路由对所有人无条件跑"时也会绿
	var p: Dictionary = _mk_probe(c + Vector2(-260.0, 0.0), "p2eq_001")
	p.erase("_b4_dot")
	_s._damage._apply_damage(p, 50, Color("#ff8844"), null, "dot")
	_s._damage._apply_damage_from(atk, p, 50, Color("#ffffff"))
	_ok("⑤ ★分母: 不带批④装备的单位两条路都没写 `_b4_dot`(证明上面两条不是无条件跑)",
		not p.has("_b4_dot"), "_b4_dot=%s" % str(p.get("_b4_dot", "键不存在")))

	# ④ 口径标志真的分得开两条路 —— 082 靠它排除 DoT
	var d: Dictionary = _mk_probe(c + Vector2(-260.0, 80.0), "p2eq_082")
	var seen: Array = []
	# 直接调路由(这里量的是"标志被置成什么", 不是"钩子有没有被调" —— 后者上面已验)
	_s._equip_sys._b4_on_damaged_any(d, null, 50)
	seen.append(str(d.get("_b4_dot", "无")))
	_ok("⑤ DoT 路跑完后 `_b4_dot` 复位成 false(不许粘住, 否则下一段普攻会被 082 误当 DoT 丢掉)",
		d.has("_b4_dot") and not bool(d["_b4_dot"]), "实测 %s" % str(seen))
	_s._units.clear()


## 干净合成探针单位: 放 ARENA 内、清掉一切会干扰的减伤/护盾/闪避。
func _mk_probe(pos: Vector2, iid: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("fortune", "left", pos)
	u["maxHp"] = 100000.0
	u["hp"] = 100000.0
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["dodge_bonus"] = 0.0
	u["damage_reduction"] = 0.0
	u["crit"] = 0.0
	u["buffs"] = []
	u["equips"] = [{"id": iid, "star": 1}]
	u["eq_state"] = {}
	u["_b4_eq"] = (iid in B4_IDS)   # 平时由 EquipStatsApply._b4_on_spawn_all 写, 这里直接置
	_s._units.append(u)
	return u
