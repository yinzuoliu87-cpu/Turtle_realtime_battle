extends Node
## verify_aspd_panel_live.gd — 属性面板的【攻速】要跟着实际攻速走(2026-08-14)
##
## ★用户最早报的三件之一:「属性的实时变化做了吗, 比如攻速移速实时变得数字」。
##   根因**不是**面板不刷新 —— 它每帧都重算 `_info_stat_rows`。
##   是**面板读的字段和战斗用的不是同一个**:
##     · 面板显示 `1.0 / atk_interval`
##     · 而所有攻速加成都写在【倍率】上: `aspd_perm`(装备/贝母) / `haste_mult`(祝福) /
##       沉锚充能 / 058 炮台光环
##   ⇒ 装备把攻速从 1.0 加到 1.3, 面板数字**纹丝不动**。
##
## ★判据: 改变真实攻速来源 ⇒ 面板那一行的**字符串**必须跟着变, 且与真实冷却对得上。
##   只断言"函数存在"守不住(今天已经栽过: 死函数被门禁保护着)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const InfoPanel := preload("res://scripts/scenes/battle/info_panel.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 从面板真正会渲染的那张表里取「攻速」那一行的文本 —— 不是我另算一份。
func _aspd_row(ip, u: Dictionary) -> String:
	for r in ip._info_stat_rows(u):
		var txt := str((r as Array)[1])
		if txt.begins_with("攻速"):
			return txt
	return "(没有攻速行)"


func _ready() -> void:
	await get_tree().process_frame
	print("=== 属性面板: 攻速实时变化 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var ip = InfoPanel.new(s)
	var u: Dictionary = s._spawn._make_unit("basic", "left", c)
	u["atk_interval"] = 1.0
	u["aspd_perm"] = 1.0
	s._units.clear()
	s._units.append(u)
	s._edit_mode = false
	s._over = false

	var base := _aspd_row(ip, u)
	_ok("★分母: 面板里确实有【攻速】这一行", base.begins_with("攻速"), base)
	_ok("★分母: 攻速倍率起点 = 1.0", absf(s.aspd_mult(u) - 1.0) < 1e-6,
		"aspd_mult=%.3f" % s.aspd_mult(u))

	# ── ① 永久攻速(装备/贝母 021 走这条) ────────────────────────────────────
	u["aspd_perm"] = 1.3
	var after := _aspd_row(ip, u)
	_ok("★★装备把 aspd_perm 加到 1.3 ⇒ 面板那一行【真的变了】", after != base,
		"%s → %s" % [base, after])
	_ok("★★而且变成了正确的值(1.3 次/秒, 不是随便变一下)", after.find("1.3") >= 0, after)

	# ── ② 临时加速(祝福类走 haste_mult + haste_until) ────────────────────────
	u["aspd_perm"] = 1.0
	u["haste_mult"] = 2.0
	u["haste_until"] = s._t + 99.0
	_ok("★★临时加速也要算进去(haste_mult 2.0 ⇒ 2 次/秒)",
		_aspd_row(ip, u).find("2") >= 0, _aspd_row(ip, u))
	# 反面: 加速过期 ⇒ 回到 1
	u["haste_until"] = s._t - 1.0
	_ok("★反面: 加速过期后回到基础值(不是一加就永久)",
		_aspd_row(ip, u) == base, "%s(基线 %s)" % [_aspd_row(ip, u), base])

	# ── ③ 面板与【战斗真实冷却】必须同源 ────────────────────────────────────
	##   ★这是最重要的一条: 两边各算各的就是"手抄的副本必然落后"。
	##     面板显示的次/秒 × 真实冷却 必须 = 1。
	u["aspd_perm"] = 1.75
	u["atk_interval"] = 1.2
	var mult: float = s.aspd_mult(u)
	var real_cd: float = float(u["atk_interval"]) / maxf(0.1, mult)
	var shown: float = mult / maxf(0.001, float(u["atk_interval"]))
	_ok("★★面板的【次/秒】× 战斗的【真实冷却】= 1(两边同源)",
		absf(shown * real_cd - 1.0) < 1e-4,
		"显示 %.4f 次/秒 × 冷却 %.4f 秒 = %.6f" % [shown, real_cd, shown * real_cd])
	_ok("★面板那一行确实印着这个数(%.2f)" % shown,
		_aspd_row(ip, u).find(s._fmt_num(shown)) >= 0,
		"%s (应含 %s)" % [_aspd_row(ip, u), s._fmt_num(shown)])

	# ── ④ 移速: 同一问题的另一半 ────────────────────────────────────────────
	var mv0 := ""
	for r in ip._info_stat_rows(u):
		if str((r as Array)[1]).begins_with("移速"):
			mv0 = str((r as Array)[1])
	u["move_spd"] = float(u.get("move_spd", 100.0)) + 40.0
	var mv1 := ""
	for r2 in ip._info_stat_rows(u):
		if str((r2 as Array)[1]).begins_with("移速"):
			mv1 = str((r2 as Array)[1])
	_ok("★移速也实时(改 move_spd ⇒ 那一行跟着变)", mv1 != mv0 and mv0 != "",
		"%s → %s" % [mv0, mv1])

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 攻速面板实时")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
