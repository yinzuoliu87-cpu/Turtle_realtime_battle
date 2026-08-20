extends Node
## verify_code_const_token.gd — {C:类名.常量名} 占位符
##
## 由来(2026-08-20, 用户「怎么根除」): 玩家文案里 **2487 个数字是手抄代码的**, 只有 220 个是占位符。
## 手抄的每一个在写下那天都是对的, 原件一改就烂 —— 这是本项目反复出现的头号病。
## 已有的 {N:1.5*ATK} 只能算单位属性和本条技能自己的 json 字段, 而 json 字段本身又是代码常量的手抄
## (实测已有 10 条对不上)。{C:...} 补上"文案直接引用代码常量"这一环, 中间不经任何副本。

const ST := preload("res://scripts/util/skill_text.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	print("=== {C:类名.常量名} ===")
	# ① 取标量: 毒雾寿命(逻辑侧唯一的那一份)
	var fog := ST.const_of("VenomDroneSystem.FOG_LIFE")
	_ok("① 取得到标量常量", fog == "6", "FOG_LIFE → %s" % fog)
	# ★分母: 它必须真的等于代码里那个值, 不是碰巧
	_ok("★分母: 与代码常量本体一致", float(fog) == VenomDroneSystem.FOG_LIFE,
		"渲染 %s / 代码 %.1f" % [fog, VenomDroneSystem.FOG_LIFE])

	# ② 数组按三档惯例渲染
	var st := ST.const_of("VenomDroneSystem.POISON_STACKS")
	_ok("② 数组渲染成三档 a/b/c", st == "3/5/8", "POISON_STACKS → %s" % st)

	# ③ 整数不拖 .0
	_ok("③ 6.0 渲染成 6 不是 6.0", not fog.contains("."), fog)

	# ④ ★取不到时原样吐回, **不静默变成 0** —— 静默归零是最难查的一类错
	_ok("④ 类名不存在 → 原样吐回", ST.const_of("NoSuchClass.X") == "{C:NoSuchClass.X}",
		ST.const_of("NoSuchClass.X"))
	_ok("④ 常量不存在 → 原样吐回",
		ST.const_of("VenomDroneSystem.NO_SUCH") == "{C:VenomDroneSystem.NO_SUCH}",
		ST.const_of("VenomDroneSystem.NO_SUCH"))

	# ⑤ 走真渲染管线(不是只测解析函数)
	var out := ST.render_plain("毒雾持续 {C:VenomDroneSystem.FOG_LIFE} 秒", {}, {})
	_ok("⑤ 真渲染管线里展开", out == "毒雾持续 6 秒", out)
	var out2 := ST.render_plain("每 0.25 秒叠 {C:VenomDroneSystem.POISON_STACKS} 层", {}, {})
	_ok("⑤ 三档在真管线里", out2 == "每 0.25 秒叠 3/5/8 层", out2)

	# ⑥ ★反面: 改了代码常量, 渲染结果必须跟着变 —— 这是本机制存在的全部理由
	#    (不能改真常量, 所以拿另一个已知常量做对照: 两个不同常量必须渲染出不同的值)
	var a := ST.const_of("VenomDroneSystem.FOG_LIFE")
	var b := ST.const_of("VenomDroneSystem.OVERSHOOT")
	_ok("⑥ 不同常量渲染出不同值(不是写死的)", a != b, "%s vs %s" % [a, b])

	## ⑦ ★★真数据 × 真入口: 全量扫 data/*.json, 断言【玩家最终看到的字里没有残留 {C:】
	##
	## 由来(2026-08-20 当场踩到): 我给 RealtimeBattle3DScene.gd 加了 class_name 好让文案引用
	## BUFF_SEC。python 侧的 tools/text_golden.py 说"渲染成 5 秒, 一字不差", 而**真引擎里**
	## 全局类缓存没刷新 ⇒ const_of 解析失败 ⇒ 原样吐回 ⇒ 玩家在图鉴上看到字面的
	## 「{C:RealtimeBattle3DScene.BUFF_SEC}」。python 那套是**重写的渲染器**, 它绿不代表引擎绿。
	##
	## ★这个机制是 fail-open 的(解析不到就静默留原文), 所以必须有人盯着出口。
	##   判据落在**玩家看到的成品字符串**上, 不落在"解析函数返回了什么"。
	var n_seg := 0
	var n_ctok := 0
	var leaked: Array = []
	for jf in ["res://data/pets.json", "res://data/phase2-equipment.json"]:
		var fh := FileAccess.open(jf, FileAccess.READ)
		if fh == null:
			continue
		var root = JSON.parse_string(fh.get_as_text())
		fh.close()
		var stack: Array = [root]
		while not stack.is_empty():
			var node = stack.pop_back()
			if node is Array:
				for e in node:
					stack.append(e)
			elif node is Dictionary:
				for k in node.keys():
					var v = node[k]
					if v is String:
						n_seg += 1
						if not (v as String).contains("{C:"):
							continue
						n_ctok += 1
						## 走玩家真正会经过的两个出口, 不是内部函数
						var ctx := {"atk": 100.0, "def": 50.0, "mr": 30.0, "maxHp": 1000.0, "spd": 100.0}
						var r1 := ST.render_bbcode(v, ctx, node, 17)
						var r2 := ST.render_plain(v, ctx, node)
						if r1.contains("{C:") or r2.contains("{C:"):
							leaked.append(str(node.get("name", k)) + "." + str(k))
					else:
						stack.append(v)
	## ★分母断言: 数据里必须真的有 {C:} 可扫, 否则这条是【空检查】而不是通过
	_ok("⑦ 分母: 数据里确实有 {C:} 段可验", n_ctok > 0,
		"扫了 %d 段字符串, 含 {C: 的 %d 段" % [n_seg, n_ctok])
	_ok("⑦ ★玩家看到的字里没有残留 {C:", leaked.is_empty(),
		("全部展开(%d 段)" % n_ctok) if leaked.is_empty() else ("残留: " + ", ".join(leaked)))
	## ⑧ 反向验证: 故意喂一个解析不到的引用, 出口必须把它原样留下(=⑦ 一定抓得到)
	var bogus := ST.render_plain("时长 {C:NoSuchClass.NO_SUCH} 秒", {}, {})
	_ok("⑧ 反向: 假引用会被 ⑦ 的判据抓到", bogus.contains("{C:"), bogus)

	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 代码常量占位符" if _fail == 0 else "FAIL")
	get_tree().quit(0 if _fail == 0 else 1)
