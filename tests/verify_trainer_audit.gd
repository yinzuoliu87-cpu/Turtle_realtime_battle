extends Node
## verify_trainer_audit.gd — 训龟大师 7 技审核结论的门禁 (用户 2026-07-30 需求3)
##
## 需求原文:「训龟大师的每一个技能效果和特效需要审核一边」
## 审核报告: docs/审核-训龟大师7技-20260730.md
## 方案书:   docs/plans/20260730b-局内HUD改造+大师审核+地图提升.md §4.3
##
## ★这个门禁守的不是"数值对不对"(那是 verify_trainer_desc / verify_trainer_magicstone
##   / verify_trainer_hunt_tame / verify_hook 的活), 而是【审核出来的那两类基础设施问题
##   不许回来】:
##
##   ① 死常量不许回来 —— HOOK_VULN_MULT 原本在游戏代码里【零读者】, 真实行为是
##      _mitigate_incoming 里硬编码的 1.25; 而 verify_trainer_desc 拿这个死常量去推
##      文案该写什么。两个 1.25 只是碰巧相等 → 改常量会让门禁要求一个错的文案并判它正确。
##      本组断言那两处【真的读常量】, 谁改回字面量就红。
##   ② 裸字面量不许回来 —— trainer_system.gd 原本一个 const 都没有, 数值全散在函数里,
##      导致怒火药水/口哨/冰川的实质数值【门禁一个都不查】(只查了射程和 CD)。
##      本组断言那 15 个常量在位【且真的被对应函数用上】。
##
##   ③ 顺带守住"7 技一个不少 + 每技有演出函数 + 图标素材在位" —— 这是特效审核那半边。
##      ★注意判据限度: 这是【静态检查】, 不等于"屏幕上真的看得见"
##      (memory project-vfx-library-rich: 美术断言要查素材真进了 _world)。逐技目视另做。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_trainer_audit.tscn

const RB_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"
const TS_PATH := "res://scripts/systems/trainer/trainer_system.gd"
const CFG_PATH := "res://scripts/scenes/TrainerConfigScene.gd"
const BAL_PATH := "res://scripts/scenes/battle/battle_ballistics.gd"

## 每技一条实现链(与 tools/pet_code_scope.py 的 TRAINER_SKILLS 对齐)。
## ★两边必须一致 —— 下面 ④ 组直接读那个 py 文件比对, 免得一边改了另一边不知道。
const CHAINS := {
	"magic_stone": ["_tick_trainer_attacks", "_fire_trainer_rock", "_trainer_magicstone_onhit"],
	"hook":        ["_cast_hook", "_hook_grab", "_tick_hooks"],
	"fury_potion": ["_cast_fury_potion", "_fury_apply_buffs"],
	"whistle":     ["_cast_whistle", "_whistle_temphp", "_apply_temp_maxhp",
					"_whistle_spirit_wave", "_tick_wave_flights", "_wave_apply",
					"_whistle_berserk", "_whistle_berserk_on"],
	"glacier":     ["_cast_glacier", "_tick_glaciers"],
	"hunt_order":  ["_cast_hunt_order", "_hunt_mark", "_tick_hunt_taunt"],
	"tame":        ["_cast_tame", "_tame_mark", "_tick_tame_decay"],
}

## 每技的演出函数(至少一个) + 图标常量里的素材
const DRAMATIZE := {
	"magic_stone": ["_fire_trainer_rock"],
	# ★钩锁改真 skillshot 后, 演出在飞行推进里(钩头节点逐帧更新), 不再有独立的 dramatize 函数。
	#   ★教训: 原来这里断言 "_hook_dramatize 存在" —— 而那个函数已经【没人调了】,
	#     断言照样绿。「断言函数存在」守不住「这个函数还有没有人用」。
	"hook":        ["_hook_head_node", "_tick_hook_flights", "_hook_hit_fx"],
	"fury_potion": ["_fury_dramatize"],
	# ★_whistle_spirit_dramatize 已删(口哨②改真 skillshot 后是死代码) —— 演出现在是
	#   小龟召出(_spawn_spirit_turtle) + 蓄力光(_wave_charge_fx) + 气波节点(_wave_build_node)。
	"whistle":     ["_whistle_note", "_spawn_spirit_turtle", "_wave_charge_fx", "_wave_build_node"],
	"glacier":     ["_glacier_dramatize"],
	"hunt_order":  ["_hunt_dramatize"],
	"tame":        ["_tame_dramatize"],
}

## trainer_system.gd 必须有这些常量, 且【必须在对应函数体里被用到】
## (只有常量在位不算 —— 定义了不用正是 HOOK_VULN_MULT 那个坑的形态)
const TS_CONSTS_USED := {
	"MS_HASTE_PER_STACK": "_tick_trainer_attacks",
	"FURY_RADIUS":        "_fury_apply_buffs",
	"FURY_SEC":           "_fury_apply_buffs",
	"FURY_HASTE":         "_fury_apply_buffs",
	"FURY_MOVE":          "_fury_apply_buffs",
	"FURY_ECHARGE":       "_fury_apply_buffs",
	"WHISTLE_TEMPHP":     "_whistle_temphp",
	"WHISTLE_TEMPHP_SEC": "_whistle_temphp",
	# ★2026-07-30 口哨②改真 skillshot: 伤害/击飞/削甲从"出手即结算"搬到【命中才结算】的
	#   _wave_apply 里(_whistle_spirit_wave 现在只定方向+召小龟+登记飞行)。
	"WHISTLE_WAVE_DMG":      "_wave_apply",
	"WHISTLE_WAVE_MAXHP_PCT": "_wave_apply",
	"WHISTLE_WAVE_KB":       "_wave_apply",
	"WHISTLE_SHRED_SEC":     "_wave_apply",
	"WHISTLE_BERSERK_ATK": "_whistle_berserk_on",
	"WHISTLE_BERSERK_LS":  "_whistle_berserk_on",
	"WHISTLE_BERSERK_SEC": "_whistle_berserk_on",
	"GLACIER_SLOW_MAG":    "_tick_glaciers",
}

var _fail := 0
var _n := 0
var _src := {}


func _ready() -> void:
	print("=== 训龟大师 7 技审核门禁 ===")
	for p in [RB_PATH, TS_PATH, CFG_PATH, BAL_PATH]:
		_src[p] = FileAccess.get_file_as_string(p)
	var tot := 0
	for v in _src.values():
		tot += str(v).length()
	print("  ★分母: 读到 %d 份源码 / %d 字符" % [_src.size(), tot])
	_chk("★分母: 四份源码都非空", _src.size() == 4 and tot > 200000)

	_dead_const()
	_no_bare_literals()
	_skills_and_vfx()
	_chain_sync()

	print("  ★分母: 本门禁共 %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 训龟大师 7 技审核门禁")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


## ① 死常量不许回来: 两处易伤倍率必须【读常量】而不是硬编码字面量
func _dead_const() -> void:
	print("  ── ① 易伤倍率必须读常量(不许回退成硬编码) ──")
	var rb: String = _src[RB_PATH]
	_chk("① HOOK_VULN_MULT 常量在位", rb.contains("const HOOK_VULN_MULT :="))
	_chk("① GLACIER_VULN_MULT 常量在位", rb.contains("const GLACIER_VULN_MULT :="))
	# ★核心: _mitigate_incoming 里必须是 d *= 常量名
	_chk("① ★钩锁易伤读的是常量(d *= HOOK_VULN_MULT)", rb.contains("d *= HOOK_VULN_MULT"))
	_chk("① ★冰川易伤读的是常量(d *= GLACIER_VULN_MULT)", rb.contains("d *= GLACIER_VULN_MULT"))
	# ★反面: 那两处【易伤判定紧跟着的那一行】不许回退成字面量。
	#   ★不能写成"全文件不许出现 d *= 1.2" —— 我第一版就这么写, 结果抓到的是
	#   【装备·靶向器055】那行 `d *= 1.2`(另一个功能, 不在本次审核范围)。
	#   顺带说明: 同一个反模式在装备域也存在(靶向器的 +20% 也是硬编码), 见审核报告。
	#   所以判据要【定位到各自的判定行之后】, 不是全文件扫。
	_chk("① ★钩锁易伤那一行不是字面量", not _after(rb, 'hook_vuln_until", 0.0)', 90).contains("d *= 1.2"))
	_chk("① ★冰川易伤那一行不是字面量",
		not _after(rb, 'glacier_vuln_until", 0.0)', 90).contains("d *= 1."))
	_chk("① 口哨削甲读的是常量(不是裸 0.7)", rb.contains("WHISTLE_SHRED_MULT if _t <"))
	_chk("① 冰川区域三项读常量(长度/宽度/持续)",
		rb.contains('"len": GLACIER_LEN') and rb.contains('"width": GLACIER_WIDTH')
		and rb.contains("_t + GLACIER_SEC"))


## ② 裸字面量不许回来: 15 个常量在位【且真的被对应函数用上】
func _no_bare_literals() -> void:
	print("  ── ② trainer_system 的 15 个常量在位且被真用上 ──")
	var ts: String = _src[TS_PATH]
	for cname in TS_CONSTS_USED.keys():
		_chk("② 常量 %s 在位" % cname, ts.contains("const %s :=" % cname))
	for cname in TS_CONSTS_USED.keys():
		var fname: String = str(TS_CONSTS_USED[cname])
		var body := _func_body(ts, fname)
		_chk("② ★%s 真的被 %s() 用上(定义了不用=死常量)" % [cname, fname],
			body != "" and body.contains(cname),
			"函数体 %d 字符" % body.length())


## ③ 7 技一个不少 + 每技有演出函数 + 图标素材在位
func _skills_and_vfx() -> void:
	print("  ── ③ 7 技齐全 + 演出函数 + 图标素材 ──")
	var cfg: String = _src[CFG_PATH]
	var all_src: String = ""
	for v in _src.values():
		all_src += str(v)
	_chk("③ ★分母: 审核覆盖 7 个技能", CHAINS.size() == 7)
	for sid in CHAINS.keys():
		# 配置页有它的卡 + desc 非空
		var key := '{"id": "%s"' % sid
		_chk("③ %s 在配置页有卡片" % sid, cfg.contains(key))
		var i := cfg.find(key)
		var seg := cfg.substr(i, 900) if i >= 0 else ""
		_chk("③ %s 有 desc 文案" % sid, seg.contains('"desc":'))
		# 图标素材真的在磁盘上
		var m := seg.find('"icon": "')
		var icon := ""
		if m >= 0:
			var rest := seg.substr(m + 9, 200)
			icon = rest.substr(0, rest.find('"'))
		_chk("③ %s 图标素材在位: %s" % [sid, icon],
			icon != "" and FileAccess.file_exists(icon), icon)
		# 演出函数
		var ds: Array = DRAMATIZE[sid]
		var got := 0
		for d in ds:
			if all_src.contains("func %s(" % d):
				got += 1
		_chk("③ %s 的 %d 个演出函数都在" % [sid, ds.size()], got == ds.size(),
			"找到 %d/%d" % [got, ds.size()])
		# 实现链每一环都在(链上函数失踪当场抓 —— 它抓到过我把 _tick_hunt_taunt 写反)
		var chain: Array = CHAINS[sid]
		var ok := 0
		for f in chain:
			if all_src.contains("func %s(" % f):
				ok += 1
		_chk("③ %s 实现链 %d 环全在位" % [sid, chain.size()], ok == chain.size(),
			"在位 %d/%d" % [ok, chain.size()])


## ④ 与 tools/pet_code_scope.py 的 TRAINER_SKILLS 对齐(免得一边改了另一边不知道)
func _chain_sync() -> void:
	print("  ── ④ 与 pet_code_scope.py 的链表对齐 ──")
	var py := FileAccess.get_file_as_string("res://tools/pet_code_scope.py")
	_chk("④ ★分母: 读到 pet_code_scope.py", py.length() > 3000)
	_chk("④ py 里有 TRAINER_SKILLS 表", py.contains("TRAINER_SKILLS = {"))
	for sid in CHAINS.keys():
		_chk("④ py 表里有 %s" % sid, py.contains("'%s':" % sid))
		for f in CHAINS[sid]:
			_chk("④ py 链里有 %s (%s)" % [f, sid], py.contains("'%s'" % f))
	_chk("④ py 有跨文件常量展开(expand_cross·大师数值全是 battle.CONST 形式)",
		py.contains("def expand_cross("))

	# ★死演出函数不许回来(反向断言): 钩锁的旧 tween 演出已删, 若有人加回来,
	#   VFXPREVIEW 又可能指过去 → 又会出现"目视确认的是旧实现"这种无效验证。
	var ts_src := FileAccess.get_file_as_string(TS_PATH)
	_chk("④ ★旧的 _hook_dramatize 已删(它曾让目视验证指向死代码)",
		not ts_src.contains("func _hook_dramatize("))
	_chk("④ ★旧的 _hook_dramatize_miss 已删", not ts_src.contains("func _hook_dramatize_miss("))
	_chk("④ ★旧的 _whistle_spirit_dramatize 已删(口哨②改真 skillshot 后是死代码)",
		not ts_src.contains("func _whistle_spirit_dramatize("))
	var vfx_src := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_vfx.gd")
	# ★六个主动技必须都走玩家真入口 _cast_active(经 _cast_real 装 _tr_active 再分派),
	#   不许任何一技直接点自己的演出函数 —— 那正是"目视验证指向死代码"的成因。
	_chk("④ ★VFXPREVIEW 经 _cast_real 走真入口 _cast_active",
		vfx_src.contains("battle._trainer_sys._cast_active(tr, aim)")
		and vfx_src.contains('tr["_tr_active"] = sid'))
	for sid in ["hook", "fury_potion", "whistle", "glacier", "hunt_order", "tame"]:
		_chk("④ ★预览 %s 走真入口(不是直点演出函数)" % sid,
			vfx_src.contains('_cast_real(tr, "%s"' % sid))
	_chk("④ ★_cast_real 打印施放成功/被拒(否则分不清'没施放'与'看不见')",
		vfx_src.contains("★被拒(未施放)"))


## 取 needle 之后的 n 个字符。找不到返回空串 —— 空串不含任何东西, 所以
## "not _after(...).contains(X)" 在找不到锚点时会【假通过】。因此上面 ① 组
## 同时有正面断言(必须含常量名), 两面夹住才不会因为锚点找不到而静默变绿。
func _after(s: String, needle: String, n: int) -> String:
	var i := s.find(needle)
	if i < 0:
		return ""
	return s.substr(i, n)


## 取函数体(到下一个 func 为止)。取不到返回空串 —— 调用方要把空串当失败。
func _func_body(s: String, fname: String) -> String:
	var i := s.find("func %s(" % fname)
	if i < 0:
		return ""
	var j := s.find("\nfunc ", i + 1)
	return s.substr(i, (j - i) if j > i else (s.length() - i))


func _chk(name: String, ok: bool, detail: String = "") -> void:
	_n += 1
	if ok:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])
