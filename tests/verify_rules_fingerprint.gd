extends Node
## verify_rules_fingerprint.gd — 对局规则指纹：**对局结果变了而 `RULES_VER` 没升 ⇒ 红**
## 方案书 docs/plans/20261102-文件管理与发版流程重整.md §4.4 R1。
##
## ══════════════════════════════════════════════════════════════════════
##  为什么要这条门禁
## ══════════════════════════════════════════════════════════════════════
## `scripts/gamedata/phase2_config.gd` 的 `const RULES_VER`：快照池 / 对手池按它分桶、
## 裁判机按它核对 —— **一个版本只要改了对局结果, 它就必须 +1**。原来只靠人记,
## 0.22.7 就漏了（训龟大师不受任何影响 20261031e / 盾羁绊冲击波不给挨打方攒怒气 20261031e /
## 灵物触手动作重做 20261031d 都改了结果, 发版时 RULES_VER 还是 1 ⇒ tag 挪位、TestFlight 作废、
## 裁判机重装、对手池重生成）。
##
## ★现有的确定性金标（`verify_determinism_cross` + `data/determinism_cross.json`）**抓不到**这一类:
##   0.22.7 那三处改动它一条都没变 —— 它跑的是调试场（右队是不动不打的假人）, 15 个场景里
##   只有一局有训龟大师（站在场边、没有任何东西碰到它）, 没有一局两边都有盾羁绊。
##
## ══════════════════════════════════════════════════════════════════════
##  怎么量
## ══════════════════════════════════════════════════════════════════════
## 跑的是**真入口**：服务器裁判 `RefereeRunner.run`（战斗场 RealtimeBattle3D.tscn 原样实例化,
## 双路上路 → 下路 → 必要时终极, 两边都真打, 两边都有训龟大师, 种子来自任务单）——
## 与裁判机 / 手机回放同一条路。每局记三样（全部与机器快慢、渲染无关）:
##   ① **逐 sim 步**全场状态（`ReplayRecorder.fingerprint`: `_t` / 路段状态 / 每个单位的
##      血 / 位置 / 存活 / 护盾 / 龟能, 浮点走位模式）流式进 SHA-256
##   ② 结果单: 胜方 / 比分码 / 各路结果 / 蛋血 / 步数 / 终局指纹 / 开打次数 / 铸币 / 宝箱 / 香火
##   ③ 每一路结束时每个单位的战报数（造成 / 承受 / 治疗 / 护盾 / 击杀 / 暴击 / 物魔真三分 +
##      每件装备的本局统计）—— 只取数字列, 不取名字 / 稀有度 / 立绘路径（改文案、挪美术不该红）
## 每局一个摘要, 五局摘要按顺序再压成一个总指纹, 与 `tests/golden/rules_fingerprint.json` 比。
##
## ══════════════════════════════════════════════════════════════════════
##  覆盖（判据里每一项都配了分母, 缺一样就红）
## ══════════════════════════════════════════════════════════════════════
##   · 28 只龟全部上场（每只至少一次; 技能挑选分散在三个主动技上）
##   · `EquipStats.STATS` 全部装备（96 件, 含 095 圣光护盾 / 096 小木斧 / 093 香火石）都真的挂在场上单位身上
##   · 十条多档羁绊全部打到**顶档**; 盾羁绊在①局**双方都是顶档**（冲击波互打 ⇒ 0.22.7 那处改动在这里）
##   · 灵物触手在③⑤局真的拍出去过（⑤局双方都有）
##   · 训龟大师每局两边都在场; 9 种大师技能全部出现
##   · 召唤物 / 精英小将（一路 0 统领）/ 3 统领同路
##
## ══════════════════════════════════════════════════════════════════════
##  红了怎么办
## ══════════════════════════════════════════════════════════════════════
##   「对局结果变了」⇒ 这是有意的规则改动吗?
##       是 ⇒ `RULES_VER` 要比上个发版 tag 的大（`python tools/release.py bump <版本> --rules changed`,
##            或手动 +1）, 然后 `python tools/rules_fingerprint.py --update` 刷新指纹。
##       不是 ⇒ 你改了不该改结果的东西, 去查（下面会打出是哪一局变了）。
##   「指纹是旧规则版本的」⇒ RULES_VER 动过了而金标没刷: `python tools/rules_fingerprint.py --update`。
##   ★`--update` 自己会核对「指纹变了 ⇒ RULES_VER 必须大于上个 v* tag 的」, 不满足拒绝写。
##
## 打印模式: `RULES_FP_PRINT=1` ⇒ 不与金标比（给 tools/rules_fingerprint.py 取当前指纹用）, 其余判据照跑。
## 每次都会打一行 `RULES_FP_JSON=<json>`（总指纹 + 每局摘要）。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_rules_fingerprint.tscn --quit-after 12000

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const ES := preload("res://scripts/gamedata/equip_stats.gd")
const P2T := preload("res://scripts/gamedata/phase2_types.gd")
const TC := preload("res://scripts/scenes/TrainerConfigScene.gd")
const SC := preload("res://scripts/referee/det_scenarios.gd")
const GOLDEN_PATH := "res://tests/golden/rules_fingerprint.json"
const MID := "5e1f0c2a-7b3d-4e6f-9a1b-2c3d4e5f6a7b"
const PRINT_ENV := "RULES_FP_PRINT"

## 战报行里进指纹的列（只取数字; 名字 / 稀有度 / 立绘路径不进 —— 改文案、挪美术不改对局结果）。
const ROW_KEYS := ["id", "is_summon", "alive", "hp", "maxHp", "_st_dealt", "_st_taken", "_st_heal",
	"_st_crit", "_st_kills", "_st_shield", "_st_phy", "_st_mag", "_st_tru"]
const ROW_EQ_PREFIX := "_st_eq|"

## ══════════════════════════════════════════════════════════════════════
##  场景表（★改这张表 = 换了一局 ⇒ 那一局的摘要必然变; `--update` 按「场景定义摘要」认得出
##    是「新增 / 改了场景」还是「同一个场景结果变了」, 只有后者要求升 RULES_VER）
## ══════════════════════════════════════════════════════════════════════
## 每方: lv 赛季等级 / tr 大师技能 / top bottom 两路统领 / lo 技能挑选(1~3) / eq 6 个单位各自的装备
##   单位顺序 = 统领(top 再 bottom, 按写的顺序) → 上路小将 → 下路小将(每路补到 3 个; 0 统领那一路首个小将是精英)
##   每个单位的装备按位置定星: 第 1 件 3★、第 2 件 2★、第 3 件 1★、第 4 件(只有 095 圣光护盾, 它不占单只 3 件上限)1★
##   x 其它快照字段（香火刻痕 / 宝箱财宝值 / 本周场数 ⇒ 小木斧进度与援军小将成长）
const CASES := [
	## ① 双方顶档盾羁绊 ⇒ 冲击波互打（0.22.7「冲击波不给挨打方攒怒气」只在两边都有盾羁绊时才看得见）
	##   + 剑顶档 / 食物顶档; 两边各两件 095 圣光护盾（9 件盾 = 6 档以上送 2 件）
	##   ★2026-11-04 A 的竹叶龟从上路挪到下路: 战斗中顿帧去掉(方案书 20261104b P3)后上路 2 统领对 1 一边倒碎蛋、整场在第一路就结束,
	##     下路的钻石 / 水晶 / 凤凰和 045/072/081/082 从没上过场(覆盖分母抓到)。统领顺序仍是 石头 / 竹叶 / 钻石 ⇒ 三件统领装备不变, 小将三格只是换路。
	{"tag": "① 双方顶档盾(冲击波互打) · 剑 / 食物", "seed": 7110001,
		"a": {"lv": 9, "tr": "hook", "top": ["stone"], "bottom": ["bamboo", "diamond"],
			"lo": {"stone": 2, "bamboo": 3, "diamond": 1},
			"eq": [["p2eq_014", "p2eq_015", "p2eq_016", "p2eq_095"], ["p2eq_017", "p2eq_018", "p2eq_021"],
				["p2eq_045", "p2eq_081", "p2eq_082", "p2eq_095"], ["p2eq_001", "p2eq_003", "p2eq_005"],
				["p2eq_006", "p2eq_007", "p2eq_009"], ["p2eq_010", "p2eq_083", "p2eq_084"]],
			"x": {"season_total_battles": 6}},
		"b": {"lv": 9, "tr": "magic_stone", "top": ["bubble"], "bottom": ["crystal", "phoenix"],
			"lo": {"bubble": 2, "crystal": 1, "phoenix": 3},
			"eq": [["p2eq_014", "p2eq_015", "p2eq_016", "p2eq_095"], ["p2eq_017", "p2eq_018", "p2eq_021", "p2eq_095"],
				["p2eq_045", "p2eq_081", "p2eq_082"], ["p2eq_002", "p2eq_012", "p2eq_013"],
				["p2eq_036", "p2eq_037", "p2eq_069"], ["p2eq_070", "p2eq_071", "p2eq_072"]],
			"x": {"season_total_battles": 6}}},
	## ② 药水 / 枪 顶档 vs 弓箭 / 剑 顶档 · A 的 3 统领同在上路(下路全是小将, 首个精英) · B 上路 2 / 下路 1
	##   ★2026-11-03 原来 076 / 080 挂在下路单位上, 而上路一边倒碎蛋整场就结束(试了 9 种换路 / 等级 / 训龟大师都碎),
	##     这两件从没上过场(覆盖分母抓到)。挪到上路统领 / 小将身上后上路不再一边倒, 两路都打, 下路的精英小将也上场了。
	{"tag": "② 药水/枪 vs 弓箭/剑 · 3 统领同路 + 精英小将", "seed": 7120002,
		"a": {"lv": 8, "tr": "fury_potion", "top": ["basic", "ninja", "hunter"], "bottom": [],
			"lo": {"basic": 3, "ninja": 2, "hunter": 3},
			"eq": [["p2eq_019", "p2eq_022", "p2eq_080"], ["p2eq_041", "p2eq_042", "p2eq_065"],
				["p2eq_066", "p2eq_067", "p2eq_068"], ["p2eq_048", "p2eq_050", "p2eq_051"],
				["p2eq_052", "p2eq_057", "p2eq_077"], ["p2eq_078", "p2eq_079", "p2eq_028"]],
			"x": {"season_total_battles": 9}},
		"b": {"lv": 8, "tr": "whistle", "top": ["pirate", "dice"], "bottom": ["lightning"],
			"lo": {"pirate": 1, "dice": 3, "lightning": 3},
			"eq": [["p2eq_039", "p2eq_049", "p2eq_054"], ["p2eq_055", "p2eq_056", "p2eq_073"],
				["p2eq_074", "p2eq_075", "p2eq_005"], ["p2eq_001", "p2eq_003", "p2eq_076"],
				["p2eq_006", "p2eq_007", "p2eq_009"], ["p2eq_010", "p2eq_083", "p2eq_084"]],
			"x": {"season_total_battles": 9}}},
	## ③ 灵物顶档(触手) + 096 小木斧 + 遗物 7 件 vs 法器顶档 / 食物 8 件
	{"tag": "③ 灵物触手 + 小木斧 vs 法器/食物", "seed": 7130003,
		"a": {"lv": 10, "tr": "glacier", "top": ["angel"], "bottom": ["ice", "ghost"],
			"lo": {"angel": 2, "ice": 3, "ghost": 1},
			"eq": [["p2eq_025", "p2eq_032", "p2eq_033"], ["p2eq_034", "p2eq_046", "p2eq_060"],
				["p2eq_061", "p2eq_062", "p2eq_063"], ["p2eq_064", "p2eq_096", "p2eq_004"],
				["p2eq_024", "p2eq_044", "p2eq_053"], ["p2eq_058", "p2eq_059", "p2eq_091"]],
			"x": {"season_total_battles": 14}},
		"b": {"lv": 10, "tr": "hunt_order", "top": ["candy", "line"], "bottom": ["lava"],
			"lo": {"candy": 2, "line": 3, "lava": 1},
			"eq": [["p2eq_011", "p2eq_023", "p2eq_026"], ["p2eq_029", "p2eq_030", "p2eq_031"],
				["p2eq_043", "p2eq_088", "p2eq_089"], ["p2eq_090", "p2eq_002", "p2eq_012"],
				["p2eq_013", "p2eq_036", "p2eq_037"], ["p2eq_069", "p2eq_070", "p2eq_071"]],
			"x": {"season_total_battles": 14}}},
	## ④ 奇械顶档 / 药水 8 件 vs 遗物顶档(含 093 香火石, 带刻痕) / 枪 8 件 · 宝箱龟带财宝值
	##   ★2026-11-08 B 的上下路对调(原上路赌徒 / 下路赛博 + 宝箱): RULES_VER 4 删了奇械僵硬 / 易碎与药水斩首后, A 上路被一边倒碎蛋、
	##     整场在第一路就结束, 下路的彩虹 / 赛博 / 宝箱和 047/085/092/093 从没上过场(覆盖分母抓到)。
	{"tag": "④ 奇械/药水 vs 遗物(香火石)/枪 · 宝箱", "seed": 7140004,
		"a": {"lv": 7, "tr": "tame", "top": ["two_head", "fortune"], "bottom": ["rainbow"],
			"lo": {"two_head": 3, "fortune": 2, "rainbow": 1},
			"eq": [["p2eq_008", "p2eq_020", "p2eq_027"], ["p2eq_035", "p2eq_038", "p2eq_040"],
				["p2eq_047", "p2eq_085", "p2eq_086"], ["p2eq_087", "p2eq_019", "p2eq_022"],
				["p2eq_028", "p2eq_041", "p2eq_042"], ["p2eq_065", "p2eq_066", "p2eq_067"]],
			"x": {"season_total_battles": 4}},
		"b": {"lv": 7, "tr": "villager", "top": ["cyber", "chest"], "bottom": ["gambler"],
			"lo": {"gambler": 2, "cyber": 3, "chest": 1},
			"eq": [["p2eq_004", "p2eq_024", "p2eq_044"], ["p2eq_053", "p2eq_058", "p2eq_059"],
				["p2eq_091", "p2eq_092", "p2eq_093"], ["p2eq_094", "p2eq_048", "p2eq_050"],
				["p2eq_051", "p2eq_052", "p2eq_057"], ["p2eq_077", "p2eq_078", "p2eq_079"]],
			"x": {"season_total_battles": 4, "incense_marks": 12, "incense_charge": 2500,
				"chest_treasure_value": 240.0}}},
	## ⑤ 双方灵物顶档(触手对拍) · 弓箭 8 件 vs 剑 8 件 · 龟壳复制 / 命运之轮 / 雷暴
	{"tag": "⑤ 双方灵物触手 · 弓箭 vs 剑 · 复制/命运之轮/雷暴", "seed": 7150005,
		"a": {"lv": 9, "tr": "mage", "top": ["space", "hiding"], "bottom": ["headless"],
			"lo": {"space": 3, "hiding": 3, "headless": 2},
			"eq": [["p2eq_025", "p2eq_032", "p2eq_033"], ["p2eq_034", "p2eq_046", "p2eq_060"],
				["p2eq_061", "p2eq_062", "p2eq_063"], ["p2eq_064", "p2eq_039", "p2eq_049"],
				["p2eq_054", "p2eq_055", "p2eq_056"], ["p2eq_073", "p2eq_074", "p2eq_075"]],
			"x": {"season_total_battles": 11}},
		"b": {"lv": 9, "tr": "hook", "top": ["shell"], "bottom": ["gambler", "lightning"],
			"lo": {"shell": 2, "gambler": 3, "lightning": 2},
			"eq": [["p2eq_025", "p2eq_032", "p2eq_033"], ["p2eq_034", "p2eq_046", "p2eq_060"],
				["p2eq_061", "p2eq_062", "p2eq_063"], ["p2eq_064", "p2eq_001", "p2eq_003"],
				["p2eq_005", "p2eq_006", "p2eq_007"], ["p2eq_009", "p2eq_010", "p2eq_083"]],
			"x": {"season_total_battles": 11}}},
]
## 数值表静态摘要(这几个脚本里的数字 / 表常量整份进指纹)。
## ★2026-11-03 反向验证抓到的洞: 五局里每件装备只放在一个星级上(第几格 = 几星), 另外两个星级的数值改了
##   五局都看不见 —— 「017 一星 hp 200→201」打不红。属性表是规则本身, 改了就该升 RULES_VER, 不必等哪一局用上。
##   只收数字 / 表(不收字符串常量, 改名字 / 文案不该红)。
const TABLE_SCRIPTS := ["res://scripts/gamedata/equip_stats.gd", "res://scripts/gamedata/turtle_stats.gd",
	"res://scripts/gamedata/phase2_minion.gd"]
## 「同一进程再跑一遍必须逐字相同」用哪一局(金标成立的前提; 挑最短的一局, 省时间)
const REPEAT_CASE := 1

var _fail := 0
var _n := 0
var _print_mode := false


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	_print_mode = OS.get_environment(PRINT_ENV) != ""
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_ok("GameState 在场", false)
		_finish()
		return
	gs.test_mode = true
	gs.tutorial_active = false
	gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)   # 钉死绝对周锚点(同 verify_determinism_cross)
	var t_all := Time.get_ticks_msec()

	## ── 静态覆盖: 场景表本身 ──
	_check_table()
	var tb0 := _tables_digest("before")   # 对局前的数值表摘要(与对局后比: 有人原地改常量表就红)

	## ── 跑 ──
	var cov := {"turtles": {}, "equips": {}, "trainer_sk": {}, "summons": {}, "tiers": {},
		"shield_both": false, "slaps": {}, "waves": {}, "final_lanes": 0, "elite": 0}
	var hashes: Array = []
	var per_case: Array = []
	var results: Array = []
	## 调场景表时只跑一局看结果: RULES_FP_ONLY=<下标>(只打印, 不比金标、不查覆盖 ⇒ 结论一律 FAIL)
	var only := int(OS.get_environment("RULES_FP_ONLY")) if OS.get_environment("RULES_FP_ONLY") != "" else -1
	for i in range(CASES.size()):
		if only >= 0 and i != only:
			continue
		var c: Dictionary = CASES[i]
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = await _run_case(c)
		results.append(r)
		hashes.append(str(r["hash"]))
		per_case.append({"tag": str(c["tag"]), "def": _def_digest(c), "hash": str(r["hash"])})
		var res: Dictionary = r["res"]
		print("  [局] %s · %s · %d 步 · 胜方 %s · 各路 %s · %d ms · 摘要 %s" % [str(c["tag"]),
			"ok" if bool(res.get("ok", false)) else "ERR " + str(res.get("error", "")),
			int(res.get("steps", 0)), str(res.get("winner", "?")), str(res.get("lane_results", {})),
			Time.get_ticks_msec() - t0, str(r["hash"]).left(16)])
		_merge_cov(cov, r, c)
		_ok("分母 · %s · 裁判算完(ok) 且真的在打: %d 步 > 600 · 开打 %d 次 ≥ 2 · 逐步指纹 %d 步"
			% [str(c["tag"]), int(res.get("steps", 0)), int(res.get("fights", 0)), int(r["n_steps"])],
			bool(res.get("ok", false)) and int(res.get("steps", 0)) > 600 and int(res.get("fights", 0)) >= 2
			and int(r["n_steps"]) > 600, str(res.get("error", "")))
		_ok("分母 · %s · 两边都有训龟大师(左 %d / 右 %d)" % [str(c["tag"]), int(r["trainers"]["left"]), int(r["trainers"]["right"])],
			int(r["trainers"]["left"]) > 0 and int(r["trainers"]["right"]) > 0)
	if only >= 0:
		print("  egg_hp %s · fights %s" % [str((results[0]["res"] as Dictionary).get("egg_hp", "?")),
			str((results[0]["res"] as Dictionary).get("fights", "?"))])
		_ok("RULES_FP_ONLY 只跑了一局(调表用, 不算通过)", false)
		_finish()
		return

	## ── 同一进程再跑一遍 ⇒ 逐字相同(金标成立的前提; 不成立时下面的「与金标比」是噪声) ──
	var rep: Dictionary = await _run_case(CASES[REPEAT_CASE])
	_ok("★★同一进程再跑一遍「%s」⇒ 摘要逐字相同(金标成立的前提)" % str(CASES[REPEAT_CASE]["tag"]),
		str(rep["hash"]) == str(hashes[REPEAT_CASE]), "%s vs %s" % [str(rep["hash"]).left(16), str(hashes[REPEAT_CASE]).left(16)])
	var uniq := {}
	for h in hashes:
		uniq[str(h)] = true
	_ok("★摘要真的在区分场景: %d 局出了 %d 个不同摘要" % [hashes.size(), uniq.size()], uniq.size() == hashes.size())

	## ── 运行时覆盖(分母) ──
	_check_cov(cov)

	## ── 数值表静态摘要(作为一个「局」进总指纹; 定义摘要固定 ⇒ 它变了 = 规则变了) ──
	var tb := _tables_digest("after")
	_ok("★★数值表打完五局前后逐字相同(没有代码原地改常量表)", str(tb["hash"]) == str(tb0["hash"]),
		"前 %s / 后 %s" % [str(tb0["hash"]).left(16), str(tb["hash"]).left(16)])
	_ok("分母 · 数值表静态摘要收了 %d 个常量(装备 / 龟 / 小将属性表)" % int(tb["n"]), int(tb["n"]) >= 10)
	hashes.append(str(tb["hash"]))
	per_case.append({"tag": "数值表 EquipStats / TurtleStats / 小将", "def": "static-tables", "hash": str(tb["hash"])})

	## ── 总指纹 ──
	var fp := _sha("\n".join(PackedStringArray(hashes)))
	var rv := int(P2.RULES_VER)
	print("RULES_FP_JSON=" + JSON.stringify({"fingerprint": fp, "cases": hashes.size(), "rules_ver": rv, "per_case": per_case}))
	print("  总指纹 %s · %d 局 · RULES_VER = %d · 耗时 %d ms · 帧 %d" % [fp, hashes.size(), rv,
		Time.get_ticks_msec() - t_all, Engine.get_process_frames()])

	if _print_mode:
		print("  (打印模式 %s=1: 不与金标比)" % PRINT_ENV)
	else:
		_check_golden(fp, rv, per_case)
	_finish()


func _finish() -> void:
	print("")
	if _fail == 0:
		if _print_mode:
			print("PRINT OK — 规则指纹 (%d/%d)" % [_n, _n])
		else:
			print("ALL PASS — 规则指纹 (%d/%d)" % [_n, _n])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _n - _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────── 金标 ───────────────────────────────

func _check_golden(fp: String, rv: int, per_case: Array) -> void:
	if not FileAccess.file_exists(GOLDEN_PATH):
		_ok("金标文件在场 %s" % GOLDEN_PATH, false, "先 python tools/rules_fingerprint.py --update")
		return
	var g = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	if not (g is Dictionary):
		_ok("金标文件解得开", false, GOLDEN_PATH)
		return
	var gd: Dictionary = g
	var want := str(gd.get("fingerprint", ""))
	var same := fp == want
	var detail := "实得 %s / 金标 %s" % [fp.left(16), want.left(16)]
	if not same:
		## 指出是哪一局变了: 按「场景定义摘要」对 —— 定义没变而结果变了 = 规则变了; 定义变了 = 场景表改了。
		var old := {}
		for pc in gd.get("per_case", []):
			if pc is Dictionary:
				old[str((pc as Dictionary).get("def", ""))] = str((pc as Dictionary).get("hash", ""))
		var changed: Array = []
		var added: Array = []
		for pc2 in per_case:
			var d := str(pc2["def"])
			if not old.has(d):
				added.append(str(pc2["tag"]))
			elif str(old[d]) != str(pc2["hash"]):
				changed.append(str(pc2["tag"]))
		detail += " · 结果变了的局: %s · 场景表新增/改过的局: %s" % [str(changed), str(added)]
		print("  ★★对局结果变了 —— RULES_VER 要比上个发版 tag 大，然后 tools/rules_fingerprint.py --update 刷新指纹")
	_ok("★★★总指纹 == 金标（对局结果变了 —— RULES_VER 要比上个发版 tag 大，然后 tools/rules_fingerprint.py --update 刷新指纹）",
		same, detail)
	var grv := int(gd.get("rules_ver", -1))
	_ok("★★金标的 rules_ver == 当前 RULES_VER（指纹是旧规则版本的, 刷新: python tools/rules_fingerprint.py --update）",
		grv == rv, "金标 %d / 当前 %d" % [grv, rv])
	_ok("分母 · 金标记的局数 %d == 本次 %d" % [int(gd.get("cases", -1)), per_case.size()],
		int(gd.get("cases", -1)) == per_case.size())


# ─────────────────────────────── 一局 ───────────────────────────────

## 快照: 与 `Backend.build_ghost_snapshot` 同一形状(战斗场读的那几个键), 经 JSON 往返(与服务器上一样)。
func _snap(sd: Dictionary, nm: String) -> Dictionary:
	var top: Array = sd["top"]
	var bottom: Array = sd["bottom"]
	var leaders: Array = top + bottom
	var eqs: Array = sd["eq"]
	var equipped := {}
	var ui := 0
	for p in leaders:
		equipped[str(p)] = _eq_list(eqs[ui])
		ui += 1
	var mins := {"top": [], "bottom": []}
	for lane in ["top", "bottom"]:
		var lead_n: int = (sd[lane] as Array).size()
		for mi in range(3 - lead_n):
			(mins[lane] as Array).append({"role": "front" if mi == 0 else "back",
				"elite": lead_n == 0 and mi == 0, "equips": _eq_list(eqs[ui])})
			ui += 1
	var s := {
		"schema_ver": 2, "ghost_id": "g_rules_fp_" + nm, "is_bot": false,
		"profile": {"name": nm, "avatar": str(leaders[0]), "id": "g_rules_fp_" + nm},
		"leaders": leaders, "lane_assign": {"top": top, "bottom": bottom}, "minions": mins,
		"leader_off": {}, "loadouts": sd["lo"], "equipped": equipped, "pet_levels": {},
		"trainer_skill": str(sd["tr"]), "season_level": int(sd["lv"]),
		"season_total_battles": 0, "chest_treasures_won": [], "chest_treasure_value": 0.0,
		"incense_marks": 0, "incense_charge": 0,
	}
	var x: Dictionary = sd.get("x", {})
	for k in x:
		s[k] = x[k]
	return s


func _eq_list(ids: Array) -> Array:
	var out: Array = []
	for j in range(ids.size()):
		out.append({"id": str(ids[j]), "star": [3, 2, 1, 1][mini(j, 3)]})
	return out


func _job(c: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify({"v": 1, "job_id": 1, "match_id": MID, "mode": "ranked",
		"key": {"rules_fp": str(c["tag"])}, "seed": int(c["seed"]), "client_version": ReplayRecorder.client_version(),
		"level": int(c["a"]["lv"]), "a": _snap(c["a"], "a"), "b": _snap(c["b"], "b")}))


## 跑一局 → {hash, res, n_steps, trainers, 覆盖探针…}。
func _run_case(c: Dictionary) -> Dictionary:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	var pr := {"n": 0, "turtles": {}, "equips": {}, "summons": {}, "elite": 0, "trainers": {"left": 0, "right": 0},
		"tiers": {"left": {}, "right": {}}, "slaps_done": 0, "slaps_cur": 0, "waves": {"left": 0, "right": 0},
		"rage": {}, "rows": [], "exited": false, "dump": null}
	## 查跨进程分叉用: RULES_FP_DUMP=<目录> ⇒ 每步的状态指纹逐行落盘(<目录>/<seed>.txt), 两个进程的文件 diff 出第一步分叉
	var dump_dir := OS.get_environment("RULES_FP_DUMP")
	if dump_dir != "":
		pr["dump"] = FileAccess.open(dump_dir.path_join("%d.txt" % int(c["seed"])), FileAccess.WRITE)
	var res: Dictionary = await RefereeRunner.run(self, _job(c), func(bt) -> void:
		bt.sim_stepped.connect(func() -> void: _on_step(bt, hc, pr))
		bt.tree_exiting.connect(func() -> void: _on_exit(bt, pr)))
	if pr["dump"] != null:
		(pr["dump"] as FileAccess).close()
		pr["dump"] = null
	var step_hash: String = (hc.finish() as PackedByteArray).hex_encode()
	var keep := {}
	for k in ["ok", "error", "winner", "winner_side", "score_code", "lane_results", "egg_hp", "steps", "digest",
			"sim_steps", "fights", "cps", "coins", "coins_b", "chest", "chest_b", "incense", "incense_b"]:
		if res.has(k):
			keep[k] = res[k]
	var body := "steps=%s\nres=%s\nrows=%s" % [step_hash, _canon(keep), _canon(pr["rows"])]
	return {"hash": _sha(body), "res": res, "n_steps": int(pr["n"]), "trainers": pr["trainers"], "pr": pr}


## 每个 sim 步: 全场状态进摘要(①); 顺带收覆盖探针(不进摘要)。
func _on_step(bt, hc: HashingContext, pr: Dictionary) -> void:
	var fp_line := ReplayRecorder.fingerprint(bt)
	hc.update(fp_line.to_utf8_buffer())
	pr["n"] = int(pr["n"]) + 1
	if pr["dump"] != null:
		(pr["dump"] as FileAccess).store_line("%d %s" % [int(pr["n"]), fp_line])
	## 盾冲击波: 某单位的 `_shield_rage` 往下掉 = 刚放过冲击波(累计 −400)。按 _units 下标 + id + 阵营认人(单位字典不能当键)。
	var rg: Dictionary = pr["rage"]
	var i := 0
	for u in bt._units:
		if u is Dictionary and (u as Dictionary).has("_shield_rage"):
			var key := "%d|%s|%s" % [i, str(u.get("id", "")), str(u.get("side", ""))]
			var v: float = float(u["_shield_rage"])
			if rg.has(key) and v < float(rg[key]) - 0.001:
				pr["waves"][str(u.get("side", ""))] = int(pr["waves"].get(str(u.get("side", "")), 0)) + 1
			rg[key] = v
		i += 1
	## 触手拍击(结算了几次): 换路 clear 会清零 ⇒ 掉下来时把上一段加进总数
	var pk = bt._spirit_syn.get("_pk")
	var sl: int = int((pk as Dictionary).get("resolved", 0)) if pk is Dictionary else 0
	if sl < int(pr["slaps_cur"]):
		pr["slaps_done"] = int(pr["slaps_done"]) + int(pr["slaps_cur"])
	pr["slaps_cur"] = sl
	if int(pr["n"]) % 30 != 1:
		return
	for u2 in bt._units:
		if not (u2 is Dictionary):
			continue
		var side := str(u2.get("side", ""))
		var id := str(u2.get("id", ""))
		if bool(u2.get("is_trainer", false)):
			pr["trainers"][side] = int(pr["trainers"].get(side, 0)) + 1
			continue
		if bool(u2.get("is_summon", false)):
			pr["summons"][id] = true
		elif bool(u2.get("_isMinion", false)):
			if bool(u2.get("elite", false)) or bool(u2.get("_elite", false)) or bool(u2.get("is_elite", false)):
				pr["elite"] = int(pr["elite"]) + 1
		elif DataRegistry.pet_by_id.has(id):
			pr["turtles"][id] = true
		for e in u2.get("equips", []):
			if e is Dictionary:
				pr["equips"][str((e as Dictionary).get("id", ""))] = true
	for sd in ["left", "right"]:
		var tiers = bt._synergy._by_side.get(sd, {})
		if tiers is Dictionary:
			for t in tiers:
				pr["tiers"][sd][str(t)] = maxi(int(pr["tiers"][sd].get(str(t), 0)), int(tiers[t]))


## 战斗场退场那一刻(裁判已结算): 各路战报(③)—— 打完的路在 `_st_lane_hist`, 最后一路还在 `_units` 上。
func _on_exit(bt, pr: Dictionary) -> void:
	if bool(pr["exited"]):
		return
	pr["exited"] = true
	var pk = bt._spirit_syn.get("_pk")
	pr["slaps_done"] = int(pr["slaps_done"]) + (int((pk as Dictionary).get("resolved", 0)) if pk is Dictionary else 0)
	pr["slaps_cur"] = 0
	var rows: Array = []
	for snap in bt._st_lane_hist:
		rows.append({"lane": str(snap.get("lane", "")), "left": _rows_of(snap.get("left", [])),
			"right": _rows_of(snap.get("right", []))})
	var last := {"lane": "last", "left": [], "right": []}
	for u in bt._units:
		var sd := str(u.get("side", ""))
		if sd == "left" or sd == "right":
			(last[sd] as Array).append(bt._st_row(u))
	rows.append({"lane": "last", "left": _rows_of(last["left"]), "right": _rows_of(last["right"])})
	pr["rows"] = rows


func _rows_of(src) -> Array:
	var out: Array = []
	if not (src is Array):
		return out
	for r in src:
		if not (r is Dictionary):
			continue
		var o := {}
		for k in ROW_KEYS:
			if (r as Dictionary).has(k):
				o[k] = r[k]
		for k2 in (r as Dictionary).keys():
			if str(k2).begins_with(ROW_EQ_PREFIX):
				o[str(k2)] = r[k2]
		out.append(o)
	return out


# ─────────────────────────────── 覆盖 ───────────────────────────────

## 场景表本身: 28 龟 / 全部装备 / 9 种大师技能 / 每方恰 3 统领、6 个单位的装备、每格 ≤3 件(095 除外)。
func _check_table() -> void:
	var pets := {}
	for p in DataRegistry.launch_pets:
		pets[str((p as Dictionary)["id"])] = true
	var stats_ids: Array = ES.STATS.keys()
	var tr_all := {}
	for s in TC.SKILLS:
		tr_all[str((s as Dictionary).get("id", ""))] = true
	var t_in := {}
	var e_in := {}
	var tr_in := {}
	var bad: Array = []
	for c in CASES:
		for side in ["a", "b"]:
			var sd: Dictionary = c[side]
			var ls: Array = (sd["top"] as Array) + (sd["bottom"] as Array)
			if ls.size() != 3:
				bad.append("%s/%s 统领 %d 只" % [c["tag"], side, ls.size()])
			for p in ls:
				t_in[str(p)] = true
			if (sd["eq"] as Array).size() != 6:
				bad.append("%s/%s 装备 %d 格" % [c["tag"], side, (sd["eq"] as Array).size()])
			for cell in sd["eq"]:
				var n_cap := 0
				for e in cell:
					e_in[str(e)] = true
					if str(e) != "p2eq_095":
						n_cap += 1
					if not ES.STATS.has(str(e)):
						bad.append("%s 不在 EquipStats.STATS" % str(e))
				if n_cap > int(P2.UNIT_EQUIP_CAP):
					bad.append("%s/%s 一格 %d 件 > %d" % [c["tag"], side, n_cap, int(P2.UNIT_EQUIP_CAP)])
			tr_in[str(sd["tr"])] = true
	_ok("分母 · 场景表形状对(每方 3 统领 / 6 个单位 / 每格 ≤ %d 件)" % int(P2.UNIT_EQUIP_CAP), bad.is_empty(), str(bad))
	var t_miss: Array = []
	for p2 in pets:
		if not t_in.has(p2):
			t_miss.append(p2)
	_ok("★分母 · 场景表上场了全部 %d 只龟(缺 %d)" % [pets.size(), t_miss.size()],
		pets.size() >= 28 and t_miss.is_empty(), "缺 %s —— 新龟要进场景表(加一局, 不要改已有的局)" % str(t_miss))
	var e_miss: Array = []
	for e2 in stats_ids:
		if not e_in.has(str(e2)):
			e_miss.append(str(e2))
	_ok("★分母 · 场景表带了 EquipStats.STATS 全部 %d 件装备(缺 %d)" % [stats_ids.size(), e_miss.size()],
		stats_ids.size() >= 96 and e_miss.is_empty(), "缺 %s —— 新装备要进场景表(加一局, 不要改已有的局)" % str(e_miss))
	var tr_miss: Array = []
	for s2 in tr_all:
		if not tr_in.has(s2):
			tr_miss.append(s2)
	_ok("分母 · 场景表用到了全部 %d 种训龟大师技能(缺 %d)" % [tr_all.size(), tr_miss.size()],
		tr_all.size() > 0 and tr_miss.is_empty(), str(tr_miss))


func _merge_cov(cov: Dictionary, r: Dictionary, c: Dictionary) -> void:
	var pr: Dictionary = r["pr"]
	for k in pr["turtles"]:
		cov["turtles"][k] = true
	for k2 in pr["equips"]:
		cov["equips"][k2] = true
	for k3 in pr["summons"]:
		cov["summons"][k3] = true
	cov["elite"] = int(cov["elite"]) + int(pr["elite"])
	for sd in ["left", "right"]:
		for t in pr["tiers"][sd]:
			cov["tiers"][t] = maxi(int(cov["tiers"].get(t, 0)), int(pr["tiers"][sd][t]))
	if int(pr["tiers"]["left"].get("盾", 0)) >= 3 and int(pr["tiers"]["right"].get("盾", 0)) >= 3:
		cov["shield_both"] = true
		cov["waves"] = pr["waves"].duplicate()
	cov["slaps"][str(c["tag"])] = int(pr["slaps_done"]) + int(pr["slaps_cur"])
	if ((r["res"] as Dictionary).get("lane_results", {}) as Dictionary).has("final"):
		cov["final_lanes"] = int(cov["final_lanes"]) + 1
	for side in ["a", "b"]:
		cov["trainer_sk"][str(c[side]["tr"])] = true


func _check_cov(cov: Dictionary) -> void:
	var t_miss: Array = []
	for p in DataRegistry.launch_pets:
		if not cov["turtles"].has(str((p as Dictionary)["id"])):
			t_miss.append(str((p as Dictionary)["id"]))
	_ok("★★分母 · 28 龟全部真的在场上出现过(%d 只, 缺 %s)" % [(cov["turtles"] as Dictionary).size(), str(t_miss)],
		t_miss.is_empty() and (cov["turtles"] as Dictionary).size() >= 28)
	var e_miss: Array = []
	for e in ES.STATS.keys():
		if not cov["equips"].has(str(e)):
			e_miss.append(str(e))
	_ok("★★分母 · 全部 %d 件装备真的挂在场上单位身上(缺 %s)" % [ES.STATS.size(), str(e_miss)],
		e_miss.is_empty() and (cov["equips"] as Dictionary).size() >= 96)
	## 十条多档羁绊全部顶档
	var top_miss: Array = []
	for t in P2T.TYPES:
		var tiers_n: int = ((P2T.TYPES[t] as Dictionary).get("tiers", []) as Array).size()
		if int(cov["tiers"].get(str(t), 0)) < tiers_n:
			top_miss.append("%s(%d/%d)" % [str(t), int(cov["tiers"].get(str(t), 0)), tiers_n])
	_ok("★★分母 · 全部 %d 条羁绊打到过顶档(没到的 %s)" % [P2T.TYPES.size(), str(top_miss)], top_miss.is_empty(),
		str(cov["tiers"]))
	_ok("★★分母 · 有一局双方都是顶档盾羁绊, 且两边都放过冲击波(左 %d / 右 %d) —— 0.22.7「冲击波不给挨打方攒怒气」在这一局"
		% [int(cov["waves"].get("left", 0)), int(cov["waves"].get("right", 0))],
		bool(cov["shield_both"]) and int(cov["waves"].get("left", 0)) > 0 and int(cov["waves"].get("right", 0)) > 0)
	var slap_cases := 0
	for k in cov["slaps"]:
		if int(cov["slaps"][k]) > 0:
			slap_cases += 1
	_ok("★★分母 · 灵物触手真的拍出去过(≥ 2 局有拍击): %s" % str(cov["slaps"]), slap_cases >= 2)
	_ok("分母 · 9 种训龟大师技能都上过场(%d)" % (cov["trainer_sk"] as Dictionary).size(),
		(cov["trainer_sk"] as Dictionary).size() >= 9)
	print("  [覆盖] 召唤物 %d 种 %s · 精英小将采样 %d · 打到终极的局 %d" % [(cov["summons"] as Dictionary).size(),
		str((cov["summons"] as Dictionary).keys()), int(cov["elite"]), int(cov["final_lanes"])])
	_ok("分母 · 召唤物出过场(≥ 3 种)", (cov["summons"] as Dictionary).size() >= 3, str((cov["summons"] as Dictionary).keys()))
	_ok("分母 · 精英小将(0 统领那一路的首个小将)上过场(采样 %d)" % int(cov["elite"]), int(cov["elite"]) > 0)


# ─────────────────────────────── 摘要 ───────────────────────────────

func _sha(s: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(s.to_utf8_buffer())
	return (h.finish() as PackedByteArray).hex_encode()


## 场景定义摘要(不含本机版本号): `--update` 靠它分辨「同一局结果变了」与「场景表改了」。
func _tables_digest(when: String = "") -> Dictionary:
	var parts: PackedStringArray = []
	for path in TABLE_SCRIPTS:
		var cm: Dictionary = (load(path) as Script).get_script_constant_map()
		var ks: Array = cm.keys()
		## ★按字符串排: 键是 StringName, 它的 < 比的是内存地址 ⇒ 裸 sort() 的顺序每个进程不同(11-03 实测摘要跨进程变)
		ks.sort_custom(func(x, y) -> bool: return str(x) < str(y))
		for k in ks:
			var v = cm[k]
			if v is int or v is float or v is Dictionary or v is Array:
				parts.append("%s::%s=%s" % [str(path).get_file(), str(k), _canon(v)])
	var dump_dir := OS.get_environment("RULES_FP_DUMP")
	if dump_dir != "" and when != "":
		var f := FileAccess.open(dump_dir.path_join("tables_%s.txt" % when), FileAccess.WRITE)
		for ln in parts:
			f.store_line(ln)
		f.close()
	return {"hash": _sha("\n".join(parts)), "n": parts.size()}


func _def_digest(c: Dictionary) -> String:
	return _sha(_canon(c)).left(16)


## 规范化成串: 字典按键排序, 浮点走位模式(不经 printf —— 跨平台 .5 舍入方向不同, 见 det_scenarios.fp)。
func _canon(v) -> String:
	if v is Dictionary:
		var ks: Array = (v as Dictionary).keys()
		ks.sort_custom(func(x, y) -> bool: return str(x) < str(y))
		var parts: PackedStringArray = []
		for k in ks:
			parts.append(JSON.stringify(str(k)) + ":" + _canon(v[k]))
		return "{" + ",".join(parts) + "}"
	if v is Array:
		var ps: PackedStringArray = []
		for x in v:
			ps.append(_canon(x))
		return "[" + ",".join(ps) + "]"
	if v is float:
		return "f" + ReplayRecorder.exact(float(v))
	if v is int:
		return str(v)
	if v is bool:
		return "T" if v else "F"
	if v == null:
		return "null"
	if v is Object:
		return "O"   # 对象的 str() 带实例号, 每个进程不同 —— 不许进摘要
	return JSON.stringify(str(v))
