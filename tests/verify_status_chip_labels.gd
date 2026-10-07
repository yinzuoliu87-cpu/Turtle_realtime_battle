extends Node
## verify_status_chip_labels.gd — 信息面板状态签: 恐惧写「恐惧」、冰寒有签(2026-10-07)
##
## 原来两处漏:
##   · 无头骑士的恐吓走 `_stun` 结算 ⇒ 面板只认 stun_until ⇒ 中了恐惧写成「眩晕」。
##   · 冰寒存在 spd_dbf_until(028 冰瓶 / 寒冰光环 / 竹子 / 糖果弹幕…), 面板计时表里没有这一项 ⇒ 一个字都不显示。
## 判据走真入口: 真放一次 `_sk_headless_fear`, 再用面板自己的 `_info_status_chips` 画出来读字;
##   刷新靠 `_status_signature` —— 签名不变面板不重画, 所以签名也要跟着变。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const InfoPanel := preload("res://scripts/scenes/battle/info_panel.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _texts(n: Node, out: Array) -> void:
	if n is Label:
		out.append(str((n as Label).text))
	for ch in n.get_children():
		_texts(ch, out)


func _chips(ip, u: Dictionary) -> String:
	var vb := VBoxContainer.new()
	add_child(vb)
	ip._info_status_chips(vb, u)
	var arr: Array = []
	_texts(vb, arr)
	vb.queue_free()
	return " | ".join(PackedStringArray(arr))


func _ready() -> void:
	await get_tree().process_frame
	print("=== 信息面板状态签: 恐惧 / 冰寒 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var ip = InfoPanel.new(s)
	var knight: Dictionary = s._spawn._make_unit("headless", "left", c)
	var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(60, 0))
	var foe2: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(4000, 0))
	s._units.clear()
	s._units.append(knight)
	s._units.append(foe)
	s._units.append(foe2)
	s._edit_mode = false
	s._over = false

	# ── 分母: 普通眩晕仍写「眩晕」 ──
	var plain: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(0, 300))
	s._damage._stun(plain, 2.0, "test")
	var t0 := _chips(ip, plain)
	_ok("★分母: 普通眩晕的签写「眩晕」", t0.find("眩晕") >= 0, t0)
	_ok("★分母: 普通眩晕不写「恐惧」", t0.find("恐惧") < 0, t0)

	# ── ① 恐惧 ──
	var sig0: String = s._status_signature(foe)
	s._headless_sys._sk_headless_fear(knight)
	_ok("★分母: 恐吓真的控住了范围内的敌人", s._t < float(foe.get("stun_until", 0.0)),
		"stun_until=%.2f t=%.2f" % [float(foe.get("stun_until", 0.0)), s._t])
	var t1 := _chips(ip, foe)
	_ok("★★中了恐惧, 面板写「恐惧」", t1.find("恐惧") >= 0, t1)
	_ok("★★而且不再写成「眩晕」", t1.find("眩晕") < 0, t1)
	_ok("★面板刷新签名跟着变(否则面板不重画)", s._status_signature(foe) != sig0)
	_ok("★范围外的敌人没被标恐惧", float(foe2.get("fear_until", 0.0)) <= s._t)

	# ── ② 恐惧期间又吃了更长的眩晕: 两个都列 ──
	foe["stun_until"] = float(foe["fear_until"]) + 3.0
	var t2 := _chips(ip, foe)
	_ok("★更长的眩晕接在恐惧后面: 恐惧与眩晕都列出", t2.find("恐惧") >= 0 and t2.find("眩晕") >= 0, t2)

	# ── ③ 冰寒 ──
	var sig1: String = s._status_signature(foe2)
	var t3a := _chips(ip, foe2)
	_ok("★分母: 没中冰寒时没有「冰寒」签", t3a.find("冰寒") < 0, t3a)
	foe2["spd_move_mult"] = 0.8
	foe2["spd_dbf_until"] = s._t + 5.0
	var t3 := _chips(ip, foe2)
	_ok("★★中了冰寒, 面板有「冰寒」签且带剩余秒数", t3.find("冰寒 5.0s") >= 0 or t3.find("冰寒 4.9s") >= 0, t3)
	_ok("★面板刷新签名跟着变", s._status_signature(foe2) != sig1)

	print("--- %d 条, 失败 %d ---" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)
