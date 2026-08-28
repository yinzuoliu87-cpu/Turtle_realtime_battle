extends Node
## verify_skill_forms.gd — 多形态技能：当前形态判得对不对 (2026-08-28)
##
## 用户 2026-08-27~28 拍板：海盗船与精英铁锤各拆成两个技能图标，
## 「当时偷的哪个就放普通的还是强化的」。
##
## ★★本文件守的是【判据不许差一格】。
##   铁锤的实现是 `_hammer_n += 1` **然后** 判 `% 3 == 0`，
##   所以"下一发是不是强化"要看**当前值** `% 3 == 2`。
##   写成 `% 3 == 0` 的话图标会**永远比实际慢一发**，而且**不报任何错** ——
##   这种错只能靠逐值对账抓出来，看代码看不出来。
##
## ★判据落在【产品自己跑出来的结果】：真调 `_sk_elite_hammer` 让计数器自己走，
##   每次对比"放之前 SkillForms 说的形态" vs "这一发实际是不是强化"。
##   不是拿我算的期望值和我写的判据互相印证（那是恒真式）。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_skill_forms.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SkillForms := preload("res://scripts/gamedata/skill_forms.gd")

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 多形态技能·当前形态判据 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	# ── 分母：表本身是活的 ──
	_ok("★分母: FORMS 表里有条目(%d 个)" % SkillForms.FORMS.size(), SkillForms.FORMS.size() >= 2)
	_ok("★分母: 海盗船与精英铁锤都在表里",
		SkillForms.is_multi("pirateShipPassive") and SkillForms.is_multi("eliteHammer"))
	_ok("★分母: 不是多形态的技能要返回 false(否则整张表恒真)",
		not SkillForms.is_multi("ninjaBomb") and not SkillForms.is_multi(""))
	for st in ["pirateShipPassive", "eliteHammer"]:
		_ok("★分母: %s 正好两个形态且 key 不重" % st,
			SkillForms.form_keys(st).size() == 2
				and SkillForms.form_keys(st)[0] != SkillForms.form_keys(st)[1],
			str(SkillForms.form_keys(st)))

	# ── ① 海盗船：布尔判据 ──
	var pu := {"ship_summoned": false}
	_ok("★★① 海盗船·没召过船 → 形态0(冲锋)",
		SkillForms.current_index(pu, "pirateShipPassive") == 0,
		"名字=%s" % str(SkillForms.current_form(pu, "pirateShipPassive").get("name", "")))
	pu["ship_summoned"] = true
	_ok("★★① 海盗船·召过船之后 → 形态1(霰弹)",
		SkillForms.current_index(pu, "pirateShipPassive") == 1,
		"名字=%s" % str(SkillForms.current_form(pu, "pirateShipPassive").get("name", "")))

	# ── ② 铁锤：★★对着产品实际行为逐发核，不是对我自己的算式 ──
	## 造一个精英小将 + 一个打不死的靶子，连放 6 发，每发之前问 SkillForms
	## "下一发是不是强化"，放完之后看**产品自己**认为这一发是不是强化(`_hammer_n % 3 == 0`)。
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var el: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-120, 0))
	el["is_elite"] = true
	el["_hammer_n"] = 0
	el["atk"] = 100.0
	el["no_basic"] = true
	el["no_move"] = true
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	foe["maxHp"] = 1.0e9
	foe["hp"] = 1.0e9
	foe["no_basic"] = true
	foe["no_move"] = true
	_s._units.clear()
	_s._units.append(el)
	_s._units.append(foe)
	_s._edit_mode = false
	_s._over = false

	var seq_pred: Array = []
	var seq_real: Array = []
	for i in range(6):
		seq_pred.append(SkillForms.current_index(el, "eliteHammer"))      # 放之前预测
		_s._elite_sys._sk_elite_hammer(el, foe)                            # 走真入口
		seq_real.append(1 if (int(el.get("_hammer_n", 0)) % 3 == 0) else 0) # 产品自己认的
		for _k in range(3):
			await get_tree().process_frame

	_ok("★分母: 计数器真的在走(6 发之后 _hammer_n=%d)" % int(el.get("_hammer_n", 0)),
		int(el.get("_hammer_n", 0)) == 6)
	_ok("★★② 逐发对上: 预测 %s == 实际 %s" % [str(seq_pred), str(seq_real)],
		str(seq_pred) == str(seq_real),
		"差一格的话图标会永远比实际慢一发, 而且不报错")
	## ★这条防"两边恒相等"的假绿: 6 发里必须真的出现过强化态, 否则全 0 == 全 0 也算过。
	_ok("★★分母: 6 发里真的出现过强化态(否则全 0 相等是恒真式)",
		seq_real.has(1) and seq_pred.has(1),
		"实际序列 %s" % str(seq_real))

	# ── ③ ★★龟壳复制: 抄的是【被偷者当时的形态】, 不是龟壳自己的状态 ──
	## 用户 2026-08-28:「龟壳在偷技能就可以看海盗龟当前携带的是第一技能还是第二技能
	##                   从而释放哪个」/「当时偷的哪个就放普通的还是强化的」。
	##
	## ★判据落在【产品自己跑出来的动画名】—— `_elite_anim(u, "hammer_big"/"hammer")`
	##   是铁锤两态唯一的外部可观察差异。不数我插的标记(memory
	##   fb-gate-must-measure-requirement-not-my-hook)。
	for want in [0, 1]:
		var c2: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
		var shell: Dictionary = _s._spawn._make_unit("shell", "left", c2 + Vector2(-140, 0))
		shell["atk"] = 100.0
		shell["no_basic"] = true
		shell["no_move"] = true
		## ★龟壳自己的计数器【故意设成会给出相反答案的值】——
		##   want=0(要普通) 时把龟壳设成"下一发是强化"(2), want=1 时设成"下一发是普通"(0)。
		##   这样如果产品读的是龟壳自己的状态而不是被偷者的, 结果一定相反 ⇒ 门禁会红。
		shell["_hammer_n"] = 2 if want == 0 else 0
		var vic: Dictionary = _s._spawn._make_unit("basic", "right", c2 + Vector2(140, 0))
		vic["is_elite"] = true
		vic["active_skills"] = ["eliteHammer"]
		vic["_hammer_n"] = 2 if want == 1 else 0      # 被偷者: want=1 时下一发是强化
		vic["maxHp"] = 1.0e9
		vic["hp"] = 1.0e9
		vic["no_basic"] = true
		vic["no_move"] = true
		_s._units.clear()
		_s._units.append(shell)
		_s._units.append(vic)
		_s._over = false

		## 分母①: 被偷者身上这个技能确实是 want 这一态
		_ok("★分母: 被偷者(_hammer_n=%d) 当前形态 = %d" % [int(vic["_hammer_n"]), want],
			SkillForms.current_index(vic, "eliteHammer") == want)
		## 分母②: 龟壳自己的形态【与被偷者相反】—— 没有这条, "抄对了"可能只是巧合
		_ok("★★分母: 龟壳自己(_hammer_n=%d)的形态 = %d, 与被偷者【相反】"
				% [int(shell["_hammer_n"]), SkillForms.current_index(shell, "eliteHammer")],
			SkillForms.current_index(shell, "eliteHammer") != want,
			"没有这条的话读错来源也能碰巧全绿")

		var seen := _cast_form_via_copy(shell, vic)
		_ok("★★③ 龟壳按【被偷者】的形态放(want=%d) → 实际放了 %s" % [want, seen],
			seen == ("big" if want == 1 else "normal"),
			"期望 %s" % ("big" if want == 1 else "normal"))
		## 分母③: 放完钉子解掉了 —— 留着会让这只龟之后永远放同一态
		_ok("★分母: 放完解钉(否则形态永久卡住)",
			not SkillForms.is_pinned(shell, "eliteHammer"))
		## 分母④: 钉住时不推进【自己】的计数器(白名单头注说的"污染自身状态")
		_ok("★分母: 钉住释放不改龟壳自己的 _hammer_n(仍 %d)" % int(shell.get("_hammer_n", -1)),
			int(shell.get("_hammer_n", -1)) == (2 if want == 0 else 0))

	# ── ④ 形态信息完整 ──
	for st in ["pirateShipPassive", "eliteHammer"]:
		for idx in [0, 1]:
			var probe := {"ship_summoned": idx == 1, "_hammer_n": 2 if idx == 1 else 0}
			var f := SkillForms.current_form(probe, st)
			_ok("★④ %s 形态%d 的 name/icon/brief 都非空" % [st, idx],
				str(f.get("name", "")) != "" and str(f.get("icon", "")) != ""
					and str(f.get("brief", "")) != "",
				str(f.get("name", "")) + " / " + str(f.get("icon", "")))

	# ── ⑤ ★图标真的能加载(不只"路径字符串非空") ──
	## ★贴图没导入时 `ResourceLoader.exists` 是 false ⇒ 图标【静默不换】, 一句报错都没有
	##   (新 PNG 没 .import 文件就是这个下场; info_panel `_skill_icon_path` 头注踩过)。
	##   只断言"路径非空"守不住 —— 必须真 load 一下。
	var n_icon := 0
	for st2 in SkillForms.FORMS.keys():
		for fk in range(SkillForms.form_count(str(st2))):
			var probe2 := {"ship_summoned": fk == 1, "_hammer_n": 2 if fk == 1 else 0}
			var ff := SkillForms.current_form(probe2, str(st2))
			var ipath := "res://assets/sprites/" + str(ff.get("icon", ""))
			n_icon += 1
			_ok("★⑤ %s 形态%d 的图标真能 load: %s" % [str(st2), fk, str(ff.get("icon", ""))],
				ResourceLoader.exists(ipath) and load(ipath) != null)
	_ok("★分母: 真的查了 %d 张图标(N=0 是空检查不是通过)" % n_icon, n_icon >= 4)

	# ── ⑥ ★两态的图标与名字不允许相同 ──
	## 用户要的就是"两个图标"—— 两态指向同一张图 = 需求没实现, 而上面那条照样全绿。
	for st3 in SkillForms.FORMS.keys():
		var icons: Array = []
		var names: Array = []
		for fk2 in range(SkillForms.form_count(str(st3))):
			var pr := {"ship_summoned": fk2 == 1, "_hammer_n": 2 if fk2 == 1 else 0}
			var f3 := SkillForms.current_form(pr, str(st3))
			icons.append(str(f3.get("icon", "")))
			names.append(str(f3.get("name", "")))
		_ok("★⑥ %s 两态的图标不同(用户要的就是两个图标)" % str(st3),
			icons[0] != icons[1], str(icons))
		_ok("★⑥ %s 两态的名字不同(同名字玩家同样分不出)" % str(st3),
			names[0] != names[1], str(names))
	_done()


## 让龟壳走【真复制入口】放一次, 回报它实际放的是哪一态("normal"/"big"/"")。
##
## ★走 `_sk_shell_copy` 而不是直接 `_do_skill` —— 要验的正是"复制怎么挑形态",
##   直接 `_do_skill` 会跳过挑形态那段(memory fb-verify-must-run-the-real-path)。
##
## ★★判据选型踩过的两个坑, 记在这里免得下次再选错:
##   ① 一开始想读 `_elite_anim` 写的 `anim_state` —— **读不到**: `_elite_anim` 开头
##      `if not u.get("is_elite")` 直接 return, 而【龟壳不是精英】。判据没错, 是
##      被测对象根本不产生这个观察量(memory fb-gate-subject-never-constructed)。
##   ② 大招那半的伤害埋在 `jt.tween_callback` 链末尾, 无头 CI 下 tween 推不动
##      (CLAUDE.md §3.5 海盗钩索同款)—— 拿伤害当判据会永远读到 0。
##   ⇒ 选 `untargetable_until`: 大招分支【同步】写 `u["untargetable_until"] = _t + 1.6`
##     (滞空不可索敌), 普通分支一次都不写(逐行数过: 普通 0 次 / 大招 1 次)。
##     它是产品自己的字段, 不是我插的标记, 而且不经 tween、不经延时队列。
func _cast_form_via_copy(shell: Dictionary, vic: Dictionary) -> String:
	shell["untargetable_until"] = 0.0
	shell["_slam"] = false
	_s._shell_sys._sk_shell_copy(shell, vic)           # ★真入口(同步部分立刻执行完)
	var big: bool = float(shell.get("untargetable_until", 0.0)) > _s._t
	## ★分母: 铁锤确实【被放出来了】—— `_slam` 是两个分支开头都【同步】写的。
	##   (先前拿"延时队列有没有新条目"当分母是错的: 普通版同步塞 9 条,
	##    而大招的波次全埋在 tween 回调里、同步塞 0 条 ⇒ 大招被误报成"没放出来"。
	##    分母选错 = 把真结果当成空跑。)
	if not bool(shell.get("_slam", false)):
		return "没放出来(_slam 没被置位)"
	return "big" if big else "normal"


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 33:
		print("  [FAIL] ★分母: 断言只有 %d 条(<33) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 多形态技能形态判据" if _fail == 0 else "FAIL x%d — 多形态技能形态判据" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
