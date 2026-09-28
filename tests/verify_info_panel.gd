extends Node
## verify_info_panel.gd — 守卫「局内详情面板」的四项改造(用户 2026-07-21 需求2)
##
##   2a 属性区要显示更多属性(治疗强度/护盾强度/闪避率等)
##   2b 小将的技能描述要能显示
##   2c 面板里所有数值要实时变化(原实现是一次性快照, 作者自己在源码里写了「从不刷新」)
##   2d 点空白处就退出面板, 去掉 ✖ 按钮
##
## ★这些都属于「改坏了不报错、只是界面上少个东西/不动了」, 只能靠测试守。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SRC := "res://scripts/scenes/RealtimeBattle3DScene.gd"

var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame

	_test_stat_rows(s)
	_test_minion_skills(s)
	_test_live_refresh()
	_test_no_close_button()
	_test_placeholder_rendered(s)
	await _test_skill_desc_live(s)

	s.queue_free()
	print("ALL PASS — 详情面板(更多属性/小将技能/实时刷新/点空白关)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 2a. 属性区能显示新增的那些属性
func _test_stat_rows(s) -> void:
	# 造一只带全套新属性的单位
	var u := {
		"atk": 100.0, "def": 20.0, "mr": 15.0, "crit": 0.25, "atk_interval": 1.2,
		"atk_range": 300.0, "move_spd": 80.0, "maxHp": 1000.0, "hp": 600.0,
		"lifesteal": 0.10, "dodge_bonus": 0.15, "heal_amp": 0.30, "shield_amp": 0.25,
		"crit_dmg": 2.0, "armor_pen": 12.0, "magic_pen": 8.0, "reflect": 0.20,
		"tenacity": 0.35, "damage_reduction": 0.12, "damage_amp": 0.18, "echarge_perm": 0.40,
	}
	var rows: Array = s._info_sys._info_stat_rows(u)
	var txt := ""
	for r in rows:
		txt += str((r as Array)[1]) + " | "
	# 用户点名要的三项
	_ok("★属性区含『治疗强度』", txt.contains("治疗强度"), txt)
	_ok("★属性区含『护盾强度』", txt.contains("护盾强度"))
	_ok("★属性区含『闪避』", txt.contains("闪避"))
	# 其余补充项
	for k in ["吸血", "暴伤", "护甲穿透", "魔法穿透", "反伤", "韧性", "减伤", "增伤", "龟能充能"]:
		_ok("属性区含『%s』" % k, txt.contains(k))
	# 核心 7 项恒在
	for k in ["攻击", "护甲", "魔抗", "暴击", "攻速", "射程", "移速"]:
		_ok("核心属性『%s』恒显示" % k, txt.contains(k))

	# ★用户 2026-07-21 第二轮明确「全都要显示啊」→ 裸单位也必须列全, 不能因为是 0 就藏起来。
	#   (第一版做成"有值才显示", 结果没装备的龟看不到治疗强度/护盾强度/闪避那几行。)
	var plain := {"atk": 10.0, "def": 1.0, "mr": 1.0, "crit": 0.0, "atk_interval": 1.0,
				  "atk_range": 100.0, "move_spd": 50.0}
	var rows2: Array = s._info_sys._info_stat_rows(plain)
	var txt2 := ""
	for r in rows2:
		txt2 += str((r as Array)[1]) + " | "
	_ok("★裸单位也把所有属性列全(不因为是0就藏)",
		txt2.contains("治疗强度") and txt2.contains("护盾强度") and txt2.contains("闪避")
		and txt2.contains("反伤") and txt2.contains("韧性"),
		txt2)
	# ★★口径: 治疗/护盾强度是【乘算】(amt *= 1+amp), 基准是 100% 而不是 0
	#   —— 用户指出「治疗和护盾强度不是100%吗」, 原来显示成 +0% 是口径错误。
	_ok("★治疗强度基准 = 100%(乘算口径, 不是 +0%)", txt2.contains("治疗强度 100%"), txt2)
	_ok("★护盾强度基准 = 100%", txt2.contains("护盾强度 100%"))
	_ok("★暴伤基准 = 150%(crit_dmg 默认 1.5)", txt2.contains("暴伤 150%"))
	_ok("★龟能充能基准 = 100%", txt2.contains("龟能充能 100%"))
	# 加算类基准仍是 0
	_ok("加算类(闪避/反伤)基准为 0%", txt2.contains("闪避 0%") and txt2.contains("反伤 0%"))
	_ok("属性行数稳定(裸单位与满属性单位一致=恒显示)",
		rows2.size() == rows.size(), "裸 %d 行 / 满 %d 行" % [rows2.size(), rows.size()])

	# ★不许用 emoji 当图标(本项目已全去 emoji 根治绿块)
	var bad_icon := 0
	for r in rows:
		var ic := str((r as Array)[0])
		if ic != "" and not ic.begins_with("res://"):
			bad_icon += 1
	_ok("★图标只用真图片或留空, 不用 emoji", bad_icon == 0, "非法图标 %d 个" % bad_icon)


## 2b. 小将技能描述
func _test_minion_skills(s) -> void:
	## ★2026-08-20 改源: 小将文案原来在 `RTScene.MINION_SKILL_DESC`, 那是图鉴那张表的**第二份手抄**
	##   (且已漂: 那份连铁锤伤害数字都没有)。现在统一走 `MinionCodex.skill_desc()`。
	##   判据不变 —— 还是问"三个 type 各自取不取得到一段够长的文案"。
	var got := 0
	for k in ["minionBodysurf", "minionRocket", "eliteHammer"]:
		var d = MinionCodex.skill_desc(k)
		var okd: bool = d is Dictionary and str((d as Dictionary).get("desc", "")).length() > 10
		if okd:
			got += 1
		_ok("小将技能『%s』有文案" % k, okd)
	_ok("小将技能文案表存在", got >= 3, "%d 条" % got)

	# ★真正走一遍面板取条目的路径: 小将 pets.json 里没有条目, 必须靠这张表兜底
	var minion := {"id": "__minion__", "side": "left", "active_skills": ["minionRocket"]}
	var ents: Array = s._info_sys._panel_skill_entries(minion)
	_ok("★小将能取到技能条目(原来这里是空的→技能区整块不渲染)", ents.size() >= 1,
		"取到 %d 条" % ents.size())
	if ents.size() > 0:
		var e: Dictionary = ents[0]
		_ok("小将技能条目有名字与描述",
			str(e.get("name", "")) != "" and str(e.get("desc", "")).length() > 10,
			"%s: %s" % [e.get("name", ""), str(e.get("desc", "")).substr(0, 30)])


## 2c. 实时刷新
func _test_live_refresh() -> void:
	var src := _src()
	_ok("★有 _refresh_info_panel(动态刷新函数)", src.contains("func _refresh_info_panel"))
	# 必须挂在每帧调用的 _update_team_panels 里。
	# ★函数体要【精确取到下一个顶层 func 为止】—— 我第一版用 substr(idx, 3000) 取固定窗口,
	#   把后面 `func _refresh_info_panel` 的【定义】也框了进去, 于是把挂钩删掉测试照样绿(假通过)。
	#   这个假通过是靠"故意改坏"才发现的, 所以反向验证不能省。
	var body := _func_body(src, "_update_team_panels")
	var hooked := body.contains("_refresh_info_panel()")
	_ok("★_refresh_info_panel 挂在每帧的 _update_team_panels 里", hooked,
		"" if hooked else "没挂上=面板还是静态快照(函数体 %d 字符)" % body.length())
	_ok("★取到的函数体不含它自己的定义(证明边界没框过头)",
		not body.contains("func _refresh_info_panel"))
	# 刷新要改已存在节点, 不是每帧重建(重建会打断滚动+每帧分配节点)
	_ok("刷新持有 HP 条/龟能条/属性行的节点引用",
		src.contains("_info_hp_bar") and src.contains("_info_en_bar") and src.contains("_info_stat_labels"))
	# 源码里那句「一次性快照, 从不刷新」的旧注释不该再留着误导人
	_ok("★旧注释『一次性快照, 从不刷新』已清除(否则会误导后来人)",
		not src.contains("详情面板整体是一次性快照"))

	# ★★用户点名的「下面的技能伤害数值」也要实时 —— 这块第一版整个漏了:
	#   面板直接贴 pets.json 原文, 于是 {N:0.7*ATK} / {{ATK}} 这类【占位符原样漏到界面上】。
	#   图鉴一直走 SkillText 渲染, 战斗面板没接。
	_ok("★战斗场接入了 SkillText 模板渲染器", src.contains("const SkillText := preload"))
	_ok("★有 _render_skill_text(把占位符按当前属性算成数字)",
		src.contains("func _render_skill_text"))
	var rb := _func_body(src, "_refresh_info_panel")
	## ★★这里原来有两条判据: `rb.contains("_info_skill_lbls")` 与
	##   `rb.contains("_info_passive_tpl")` —— **grep 变量名在不在**。
	##   而那个名字在、行为死: `_info_skill_lbls` 全仓唯一的 append 写的是 `"lbl": null`,
	##   于是刷新循环每一条都在第一行 continue; `_info_passive_lbl/_tpl` 更是**零写入点**
	##   (write_orphan_audit 判成孤儿字段)。探针实测 ATK 40→80、屏上「造成 40 物理伤害」
	##   一个字没动, 这两条却是 PASS —— 判据不但没抓住 bug, 还把那段死代码焊在原地。
	##   ⇒ 已整条搬到 `_test_skill_desc_live()`(量屏幕节点, 不 grep 名字)。
	_ok("★刷新函数里仍有技能描述那一段(行为判据在 _test_skill_desc_live)",
		rb.contains("_skill_body_text"), "刷新函数体 %d 字符" % rb.length())
	# ★「当前状态」chips(护盾/灼烧/眩晕/怒气…)在战斗中变得最频繁, 原来也是建一次就不动
	_ok("★状态 chips 纳入刷新(护盾/灼烧/眩晕会跟着变)", rb.contains("_info_status_box"),
		"" if rb.contains("_info_status_box") else "状态区还是死的")
	_ok("★状态用签名节流(不每帧无脑重建节点→不闪不掉帧)",
		src.contains("func _status_signature") and rb.contains("_info_status_sig"))
	# 面板取技能条目时必须渲染, 不能再直接 _strip_html 原文
	var pe := _func_body(src, "_panel_skill_entries")
	_ok("★技能条目走模板渲染(不再原样贴 pets.json)",
		pe.contains("_render_skill_text"), "仍在直接 _strip_html 原文 = 占位符会漏出来")


## ★★2c-bis【行为级】: 屏幕上的技能/被动【伤害数字】真的跟着属性变 (2026-09-28)
##
## 判据落在**面板节点树里取回来的那段字**, 不碰源码字符串、也不碰取数函数的返回值。
## 链条是: 取数函数算对了 → 每帧有人调刷新 → 刷新真的写进屏上那个节点 → 玩家看见。
## 上一版判据只站在这条链的第 0 环(源码里有没有那个变量名), 于是整条链断了照样全绿。
##
## 三层分母, 缺一条这测试就是空检查:
##   ① 描述框那个 RichTextLabel 真的在场、真的有字(不是读了个空字符串在比空)
##   ② 那段字里抠得出数字(抠不到 ⇒ 后面比的全是 0)
##   ③ ★「改之前和改之后【本来就该】不同」—— 每个槽先用取数函数独立算一遍
##      "ATK 翻倍会不会改变这段文案"。不受 ATK 影响的样本**不计入证据**:
##      竹叶龟的治疗技(数值全按最大生命算)就是这种, 拿它当样本判据永远绿。
## ★另加一条**反向分母**: 只调刷新、不改属性 ⇒ 屏上的字不许变。
##   没有它的话"字变了"可能只是"刷新把别的东西写了进去"。
## ★驱动用的是产品每帧真正调的那一个(`_update_team_panels`, 见 battle_render:580),
##   不是直接调 `_refresh_info_panel` —— 免得量的是我自己的钩子。
func _test_skill_desc_live(s) -> void:
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	## ★样本挑「小龟」: 它三个槽(被动 不屈 / 普攻 攻击 / 技能 打击)**全部**含 ATK 项
	##   ⇒ 被动与主动技一次都覆盖到(被动那条原来是靠孤儿字段假装覆盖的)。
	var u: Dictionary = s._spawn._make_unit("basic", "left", c)
	s._units.clear()
	s._units.append(u)
	s._edit_mode = false
	s._over = false
	s.set_process(false)          # 全同步: 每一步刷新都由本测试显式驱动
	s._hud._show_unit_info_panel(u)
	for _i in range(4):
		await get_tree().process_frame

	var ents: Array = s._info_sys._skill_bar_entries(u)
	var slots: Array = []
	_collect_slots(s._info_panel, slots)
	_ok("★分母: 技能栏槽数 == 条目数(对不上 ⇒ 下面按下标取 tpl 会张冠李戴)",
		slots.size() == ents.size() and slots.size() >= 3,
		"槽 %d / 条目 %d" % [slots.size(), ents.size()])
	_ok("★分母: 登记表条数也一致", s._info_skill_lbls.size() == slots.size(),
		"登记 %d 条" % s._info_skill_lbls.size())
	if slots.size() != ents.size() or slots.is_empty():
		return

	## ★★分母③自己的自证: 「这段文案本来就该随 ATK 变吗」这个判法必须**能分开**两种样本。
	##   要是它恒为真, 下面的 `n_dep` 就是个橡皮图章 —— 拿一条跟 ATK 无关的技能当样本,
	##   判据会永远绿(竹叶龟的治疗技就是这种: 数值全按最大生命算, 攻击力翻倍它一个数不动)。
	##   用两条**合成模板**验, 不依赖任何龟的数据, 也不会随 pets.json 改动而失效。
	var _a0: float = float(u.get("atk", 0.0))
	var _dep_lo: String = s._info_sys._skill_body_text(u, {}, "造成 {N:1.0*ATK} 点伤害")
	var _ind_lo: String = s._info_sys._skill_body_text(u, {}, "持续 3 秒")
	u["atk"] = _a0 * 2.0
	var _dep_hi: String = s._info_sys._skill_body_text(u, {}, "造成 {N:1.0*ATK} 点伤害")
	var _ind_hi: String = s._info_sys._skill_body_text(u, {}, "持续 3 秒")
	u["atk"] = _a0
	_ok("★分母③自证(正): 含 ATK 的模板 —— ATK 翻倍后判法说「会变」",
		_dep_lo != _dep_hi and _dep_lo != "", "%s → %s" % [_dep_lo, _dep_hi])
	_ok("★分母③自证(反): 不含 ATK 的模板 —— 判法必须说「不会变」(恒真就是橡皮图章)",
		_ind_lo == _ind_hi and _ind_lo != "", "%s → %s" % [_ind_lo, _ind_hi])

	var n_dep := 0        # 文案本来就随 ATK 变的槽数 = 真正能当证据的样本数
	var n_changed := 0
	var passive_proved := false
	for i in range(slots.size()):
		var ent: Dictionary = ents[i]
		var sk = ent.get("sk", {})
		var tpl := str(ent.get("tpl", ""))
		var nm := str(ent.get("name", ""))
		var is_passive: bool = nm.begins_with("被动 · ")
		## ── 分母③: 这段文案【本来就该】随 ATK 变吗? 走取数函数独立算, 不碰屏幕 ──
		var atk0: float = float(u.get("atk", 0.0))
		var lo: String = s._info_sys._skill_body_text(u, sk, tpl)
		u["atk"] = atk0 * 2.0
		var hi: String = s._info_sys._skill_body_text(u, sk, tpl)
		u["atk"] = atk0
		var dep: bool = (lo != hi and lo != "")
		## ── 走产品自己的入口: 给槽喂一次真左键点击, 不去调 _show_detail ──
		_click(slots[i])
		for _j in range(2):
			await get_tree().process_frame
		var before := _overlay_text(s)
		_ok("★分母: 槽 %d「%s」的描述框在屏上且有字" % [i, nm], before.length() > 5,
			before.substr(0, 40))
		_ok("★分母: 点开后【这一条】的 lbl 登记上了且只有这一条(原来永远是 null)",
			s._info_skill_lbls[i].get("lbl", null) != null and _reg_n(s) == 1,
			"非 null 条数 %d" % _reg_n(s))
		## ── 反向分母: 只刷新不改属性 ⇒ 字不许变 ──
		s._info_sys._update_team_panels()
		s._info_sys._update_team_panels()
		_ok("★分母(反向): 只刷新不改属性 ⇒ 屏上的字不变(变了说明下面测不到东西)",
			_overlay_text(s) == before, "刷新后 %s" % _overlay_text(s).substr(0, 40))
		if not dep:
			## 不含 ATK 项的样本: 不计入证据, 但要证明它确实没变(否则是别的东西在乱写)
			s._damage._buff(u, "atk", 1.0, true, 9999.0)
			s._info_sys._update_team_panels()
			_ok("样本「%s」不含 ATK 项 ⇒ 不计入证据; 改 ATK 后它确实不变" % nm,
				_overlay_text(s) == before)
			(u["buffs"] as Array).clear()
			s._recalc_stats(u)
			s._info_sys._update_team_panels()
			_click(slots[i])
			await get_tree().process_frame
			continue
		n_dep += 1
		var n0: Array = _nums_in(before)
		_ok("★分母: 槽 %d 的描述里抠得出数字(0 个 = 空检查)" % i, n0.size() >= 1,
			"抠到 %d 个数" % n0.size())
		## ── 用产品自己的 buff 入口把攻击力翻倍(_damage._buff → _recalc_stats) ──
		s._damage._buff(u, "atk", 1.0, true, 9999.0)
		_ok("★分母: _damage._buff 真把 atk 翻上去了", float(u.get("atk", 0.0)) > atk0 * 1.9,
			"%.1f → %.1f" % [atk0, float(u.get("atk", 0.0))])
		s._info_sys._update_team_panels()
		var after := _overlay_text(s)
		var okc: bool = (after != before and after != "")
		if okc:
			n_changed += 1
			if is_passive:
				passive_proved = true
		_ok("★★槽 %d「%s」: 攻击力翻倍后【屏幕上那段字】跟着变" % [i, nm], okc,
			"%s → %s" % [before.substr(0, 44), after.substr(0, 44)])
		## ★两边都是**纯文本**(_render_skill_text 里 _strip_html 过), 所以能逐字比。
		##   哪天描述改成带 BBCode 的, 这条会红在"字不一样"上 —— 那时要改的是比法,
		##   不是把这条删掉(它拦的是"字变了但不是刷新写的"那一类)。
		var want: String = s._info_sys._skill_body_text(u, sk, tpl)
		_ok("★★屏上印的就是取数函数现算的那段(不是别处写进去的东西)", after == want,
			"屏 %s ┃ 现算 %s" % [after.substr(0, 40), want.substr(0, 40)])
		## 方向: 同位的数只许涨不许跌, 且至少有一个真的涨了。
		## ★不能只看"第一个数" —— 被动那段第一个数是稀有度加成 +20%, 它跟 ATK 无关,
		##   拿它当方向判据会把一条**修好了的**功能判成红(第一版就是这么写的)。
		var n1: Array = _nums_in(after)
		var up := 0
		var down := 0
		if n0.size() == n1.size():
			for k in range(n0.size()):
				if float(n1[k]) > float(n0[k]) + 0.0001:
					up += 1
				elif float(n1[k]) < float(n0[k]) - 0.0001:
					down += 1
		_ok("★方向对: 攻击力涨 ⇒ 描述里的数只涨不跌, 且至少一个真涨了",
			n0.size() == n1.size() and up >= 1 and down == 0,
			"同位 %d 个数: 涨 %d 跌 %d" % [n0.size(), up, down])
		## ── 反面: buff 撤掉 ⇒ 字跌回原样(只涨不落 = 改过一次就钉住, 不算实时) ──
		(u["buffs"] as Array).clear()
		s._recalc_stats(u)
		s._info_sys._update_team_panels()
		_ok("★反面: buff 撤掉后屏上的字跌回原样(不是单向钉死)",
			_overlay_text(s) == before, _overlay_text(s).substr(0, 44))
		_click(slots[i])   # 收起, 下一个槽从干净状态起
		await get_tree().process_frame

	_ok("★★★分母总账: 至少 2 个槽的文案本来就该随 ATK 变(样本不含 ATK ⇒ 判据恒绿)",
		n_dep >= 2, "含 ATK 项的槽 %d 个" % n_dep)
	_ok("★★★每一个该变的槽都真的变了", n_changed == n_dep, "%d / %d" % [n_changed, n_dep])
	_ok("★★★【被动】那一槽也在证据里(原 `_info_passive_tpl` 那条测的是零写入点的孤儿字段)",
		passive_proved)
	print("  (技能描述实时性: 用掉 %d 帧, 默认预算 500)" % Engine.get_process_frames())


## 技能栏的槽 = 88×88 且自己接了 gui_input 的 PanelContainer(装备槽不接 gui_input)。
func _collect_slots(n: Node, out: Array) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n is PanelContainer and not (n as Control).gui_input.get_connections().is_empty():
		var cm: Vector2 = (n as Control).custom_minimum_size
		if int(cm.x) == 88 and int(cm.y) == 88:
			out.append(n)
	for ch in n.get_children():
		_collect_slots(ch, out)


## 描述框里【屏幕上】那段字。浮层没开 / 没有 RichTextLabel 都返回空串 ——
## 返回空串而不是抛错, 是为了让上面的分母断言把"读不到"照出来。
func _overlay_text(s) -> String:
	if s._info_panel == null or not is_instance_valid(s._info_panel):
		return ""
	var ov = s._info_panel.get_node_or_null("DetailOverlay")
	if ov == null or not ov.visible:
		return ""
	var bd = ov.get_node_or_null("Box/Body")
	if bd == null:
		return ""
	for ch in bd.get_children():
		if ch is RichTextLabel:
			return str((ch as RichTextLabel).get_parsed_text())
	return ""


## 登记表里 lbl 非 null 的条数 —— 描述框全场只有一个, 所以正常只该是 0 或 1。
func _reg_n(s) -> int:
	var k := 0
	for e in s._info_skill_lbls:
		if (e as Dictionary).get("lbl", null) != null:
			k += 1
	return k


## 一段字里的所有数(按出现顺序)。给"同位比大小"用。
func _nums_in(t: String) -> Array:
	var out: Array = []
	var cur := ""
	for i in range(t.length()):
		var ch := t[i]
		if (ch >= "0" and ch <= "9") or (ch == "." and cur != ""):
			cur += ch
		elif cur != "":
			out.append(cur.to_float())
			cur = ""
	if cur != "":
		out.append(cur.to_float())
	return out


## 喂一次真的左键点击 —— 走产品自己的 gui_input 回调, 不去调内部函数。
func _click(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	c.gui_input.emit(ev)

## 2d. 去掉 ✖ + 点空白关
func _test_no_close_button() -> void:
	var src := _src()
	var has_btn := src.contains("close_btn")
	_ok("★面板不再有 ✖ 关闭按钮", not has_btn, "仍有 close_btn" if has_btn else "")
	# 点空白关闭的逻辑要在(普通战斗 + 放置阶段 都要能关)
	var n_close := src.count("_close_info_panel()")
	_ok("点空白/ESC 关闭逻辑仍在", n_close >= 3, "_close_info_panel 调用 %d 处" % n_close)
	# ★要在 _unhandled_input 里面找那处放置阶段早退 —— 全文搜 `_dl_state == "place"`
	#   会命中别处(第一次我就这么搜错了, 报了假 FAIL)。
	# ★字符窗口两头都是坑, 2026-07-22 一天之内两个方向都踩了:
	#   窗口太小 → substr(ui,4000) 再 substr(pl,700) 实际只剩 255 字符, 把 _close_info_panel()
	#              切在窗口外 → 假 FAIL(我差点据此去"修"一个根本没坏的功能);
	#   窗口太大 → 放开成 substr(pl) 取到函数尾, 而 _unhandled_input 里 _close_info_panel()
	#              共 3 处, 后面普通战斗分支那处顶包 → 把放置分支的调用删掉照样绿(实测过), 断言变哑。
	#   所以必须【按缩进精确切出这一个分支】, 且下面留了一条自检不许再放宽。
	var ui_body := _func_body(src, "_unhandled_input")
	var pl_body := _branch_body(ui_body, "_dl_state == \"place\"")
	_ok("★放置阶段也能点空白关面板(这条早退曾把它挡掉)",
		pl_body.contains("_close_info_panel()"),
		"放置阶段仍只能靠 ESC 关(切出的分支 %d 字符)" % pl_body.length())
	# ★自检: 切出来的必须【只是这一个分支】。放置分支自己以 _dl_handle_place_input 收尾,
	#   若切片漏到了后面的普通战斗分支, 就会把 unproject/_open_info_panel 那些一起框进来。
	_ok("切片没漏到隔壁分支(否则上一条会变成恒真的哑断言)",
		pl_body.contains("_dl_handle_place_input") and not pl_body.contains("_open_info_panel"),
		"切出 %d 字符, 含隔壁分支内容" % pl_body.length())


## 按【缩进】切出 anchor 所在的那一个分支: 从含 anchor 的行起, 到下一条缩进
## ≤ 该行缩进的非空行为止。字符数窗口切不准分支边界(小了漏内容、大了框进隔壁)。
func _branch_body(body: String, anchor: String) -> String:
	var lines := body.split("\n")
	var start := -1
	var base := 0
	var out := ""
	for i in lines.size():
		var l := str(lines[i])
		if start < 0:
			if l.contains(anchor):
				start = i
				base = l.length() - l.lstrip("\t").length()
				out = l + "\n"
			continue
		var stripped := l.strip_edges()
		if stripped != "" and (l.length() - l.lstrip("\t").length()) <= base:
			break
		out += l + "\n"
	return out


## 精确取某个顶层函数的函数体(从它的 func 行到【下一个顶层 func】为止)。
## 用固定字符窗口截会把后面别的函数框进来 → 断言变恒真。
## ★行为级: 真渲染一段带占位符的模板, 出来的必须是【数字】而不是 {N:...}
## 用户 2026-07-21 在面板截图里直接看到了 "{N:0.7*ATK}" 和 "{{ATK}}" 漏在界面上。
func _test_placeholder_rendered(s) -> void:
	var u := {"atk": 100.0, "maxHp": 1000.0, "hp": 1000.0, "def": 10.0, "mr": 10.0,
			  "crit": 0.0, "level": 1, "id": "basic"}
	var tpl := "造成 {N:0.7*ATK} 点物理伤害"
	var out: String = s._render._render_skill_text(tpl, u, {})
	_ok("★占位符被算成数字(不再原样漏到界面)",
		not out.contains("{N:") and not out.contains("{{"), "渲染结果: %s" % out)
	# ATK=100 → 0.7*ATK = 70, 结果里应出现 70
	_ok("★算出来的数值正确(ATK=100 → 0.7×ATK=70)", out.contains("70"), "渲染结果: %s" % out)
	# 属性变了, 渲染结果要跟着变(这就是"实时"的本质)
	u["atk"] = 200.0
	var out2: String = s._render._render_skill_text(tpl, u, {})
	_ok("★★属性变化后重渲染的数字跟着变(ATK翻倍→140)",
		out2.contains("140") and out2 != out, "ATK=200 渲染: %s" % out2)


func _func_body(src: String, fname: String) -> String:
	var lines := src.split("\n")
	var out := ""
	var inside := false
	for line in lines:
		if line.begins_with("func " + fname + "("):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out


func _src() -> String:
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	var g := FileAccess.open("res://scripts/scenes/battle/info_panel.gd", FileAccess.READ)   # 面板函数已抽到 InfoPanel(2026-07-25)
	if g != null:
		s += "
" + g.get_as_text(); g.close()
	s += "\n" + FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_render.gd")   # _render_skill_text 已抽到 BattleRender(2026-07-26)
	return s
