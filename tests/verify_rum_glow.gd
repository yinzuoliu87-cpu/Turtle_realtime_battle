extends Node
## verify_rum_glow.gd — 海盗·朗姆酒【暖色酒气护光】真的画出来了 (2026-08-26)
##
## ★由来: `pirate_system.gd:60` 写 `rum_glow_until`, 而 2026-08-26 之前**全仓零处读它** ——
##   写了没人消费的标记(memory [[fb-write-without-reader-and-fake-gates]])。
##   两处评审台注释却写着「看到暖色酒气护光」⇒ "看不见"会被当成【我环境没配对】,
##   而不是【效果压根没做】。这一晚扫「写了但没人读的字段」时才捞出来。
##
## ★判据必须量【渲染后的 Sprite3D.modulate】, 不是量我自己插的标记, 也不是量常量表 ——
##   memory [[fb-gate-must-measure-requirement-not-my-hook]]: 断言自己插的钩子 = 插一行数一行必绿。
##   这里量的是玩家眼睛真正看到的那个颜色。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_rum_glow.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RENDER := preload("res://scripts/scenes/battle/battle_render.gd")
const PIRATE := preload("res://scripts/systems/skills/pirate_system.gd")

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 拿到某只龟的立绘节点(渲染层每帧往它写 modulate)。
func _spr(u: Dictionary):
	var n = u.get("sprite", null)
	return n if (n != null and is_instance_valid(n)) else null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 海盗·朗姆酒暖色护光 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(40):
		await get_tree().process_frame

	## 找一只场上的龟当载体 —— 护光是**渲染层按旗子画**的, 不挑龟种。
	var u = null
	for uu in _s._units:
		if bool(uu.get("alive", false)) and _spr(uu) != null:
			u = uu
			break
	_ok("★分母: 场上有一只带立绘的活龟当载体", u != null)
	if u == null:
		_done()
		return

	## ── ① 没喝酒时: 不该有暖色 ──────────────────────────────
	u["rum_glow_until"] = 0.0
	u["_body_tint"] = Color.WHITE
	u["flash_t"] = 0.0
	await _settle()
	var c_off: Color = _spr(u).modulate
	_ok("★分母① 没喝酒时立绘是本色(不偏暖)",
		absf(c_off.r - c_off.b) < 0.05,
		"modulate r=%.3f g=%.3f b=%.3f" % [c_off.r, c_off.g, c_off.b])

	## ── ② 喝酒中: 必须真的偏暖 ──────────────────────────────
	## ★用产品自己的时长常量, 不手抄一个数。
	u["rum_glow_until"] = _s._t + PIRATE.RUM_SEC
	await _settle()
	var c_on: Color = _spr(u).modulate
	_ok("★★② 喝酒中立绘【变暖】了(红明显高于蓝)",
		c_on.r - c_on.b > 0.15,
		"r=%.3f g=%.3f b=%.3f (r-b=%.3f)" % [c_on.r, c_on.g, c_on.b, c_on.r - c_on.b])
	_ok("★★② 而且是【相对没喝酒时】变的(不是这只龟本来就偏暖)",
		(c_on.r - c_on.b) - (c_off.r - c_off.b) > 0.15,
		"喝前 r-b=%.3f → 喝后 r-b=%.3f" % [c_off.r - c_off.b, c_on.r - c_on.b])
	## ★不能亮到看不清龟: 暖色只是罩一层, 不是把龟涂成一块橙色。
	_ok("★② 但没盖死本体(蓝通道仍 > 0.3, 龟还看得清)", c_on.b > 0.3, "b=%.3f" % c_on.b)

	## ── ③ 防【淡出病】: 前 70% 必须还是满亮的 ─────────────────
	## memory [[fb-vfx-defect-families]]: 短命特效一出生就线性淡出 ⇒ 实拍读成土棕/灰。
	## 判据: 把剩余时间设成"刚过一半", 此刻的暖度应与刚喝下时**几乎一样**。
	u["rum_glow_until"] = _s._t + PIRATE.RUM_SEC * 0.5
	await _settle()
	var c_mid: Color = _spr(u).modulate
	_ok("★★③ 过半时仍是满亮(不是一出生就线性淡出)",
		absf((c_mid.r - c_mid.b) - (c_on.r - c_on.b)) < 0.10,
		"刚喝 r-b=%.3f → 过半 r-b=%.3f" % [c_on.r - c_on.b, c_mid.r - c_mid.b])

	## ── ④ 尾声要收 ─────────────────────────────────────────
	u["rum_glow_until"] = _s._t + PIRATE.RUM_SEC * RENDER.RUM_GLOW_FADE * 0.15
	await _settle()
	var c_end: Color = _spr(u).modulate
	_ok("★★④ 快结束时【明显收了】(暖度掉到满亮的一半以下)",
		(c_end.r - c_end.b) < (c_on.r - c_on.b) * 0.5,
		"满亮 r-b=%.3f → 尾声 r-b=%.3f" % [c_on.r - c_on.b, c_end.r - c_end.b])

	## ── ⑤ 到点必须【干净地】没有 ──────────────────────────────
	## 这条守的是"会不会残留" —— 因为实现是渲染层直接读旗子、不写常驻状态,
	## 时间一过自然归零; 若有人改成写 `_body_tint`, 忘了清就会在这里红。
	u["rum_glow_until"] = 0.0
	await _settle()
	var c_after: Color = _spr(u).modulate
	_ok("★★⑤ 到点后回到本色, 零残留",
		absf(c_after.r - c_off.r) < 0.02 and absf(c_after.b - c_off.b) < 0.02,
		"r=%.3f b=%.3f (对照 r=%.3f b=%.3f)" % [c_after.r, c_after.b, c_off.r, c_off.b])

	## ── ⑥ 技能真的会写这个旗子(端到端) ────────────────────────
	## ★上面五条量的都是"旗子 → 画面"。这条量"技能 → 旗子", 两截接起来才是完整的账。
	##   只验前半截的话, 把 `pirate_system` 里那一行删掉照样全绿。
	var u2 = null
	for uu in _s._units:
		if bool(uu.get("alive", false)):
			u2 = uu
			break
	u2["rum_glow_until"] = 0.0
	u2["atk"] = 100.0
	u2["maxHp"] = 1000.0
	u2["hp"] = 500.0
	_s._pirate_sys._sk_pirate_rum(u2)
	_ok("★★⑥ 放朗姆酒【真的会把旗子点起来】(技能→旗子这一截)",
		float(u2.get("rum_glow_until", 0.0)) > _s._t,
		"rum_glow_until=%.2f  当前 _t=%.2f" % [float(u2.get("rum_glow_until", 0.0)), _s._t])
	_ok("★⑥ 点亮时长 = PirateSystem.RUM_SEC(%.1f 秒)" % PIRATE.RUM_SEC,
		absf(float(u2.get("rum_glow_until", 0.0)) - (_s._t + PIRATE.RUM_SEC)) < 0.2,
		"实得 %.2f 秒" % (float(u2.get("rum_glow_until", 0.0)) - _s._t))

	## ⑦ 渲染层的时长常量必须与技能一致 —— 两处各写一个数就会漂。
	_ok("★⑦ 渲染层 RUM_GLOW_SEC(%.1f) == PirateSystem.RUM_SEC(%.1f)"
		% [RENDER.RUM_GLOW_SEC, PIRATE.RUM_SEC],
		absf(RENDER.RUM_GLOW_SEC - PIRATE.RUM_SEC) < 0.01)
	_done()


## 等渲染层至少完整跑一帧(它在 Phase4 写 modulate)。
func _settle() -> void:
	for _i in range(4):
		await get_tree().process_frame


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 10:
		print("  [FAIL] ★分母: 断言只有 %d 条(<10) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 朗姆酒暖色护光" if _fail == 0 else "FAIL x%d — 朗姆酒暖色护光" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
