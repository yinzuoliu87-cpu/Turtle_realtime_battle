extends Node
## verify_info_panel_stats.gd — 局内详情面板的属性读数 (2026-08-10)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 用户 2026-08-10「攻速这个属性, 我都没看到战斗内的实时变化,
##          而且应该是多少下每秒」
## ══════════════════════════════════════════════════════════════════
## 查证: `info_panel.gd` 显示的是 **`atk_interval`（攻击间隔·秒）却标着"攻速"**。
##   ⇒ 语义整个反了: 加攻速时 `atk_interval` **变小**, 数字跟着变小,
##     玩家读起来像被削弱, 自然"看不到实时变化"(变了, 但方向是反的)。
##   ⇒ 而图鉴一直显示 `0.94 次/秒` ⇒ **同一个属性两处两个口径**。
##
## 这条门禁守两件事:
##   ① 单位是【次/秒】, 不是秒
##   ② **攻速变快时显示的数字必须变大** ← 方向对不对是这条的核心
##      (只断言"有这一行"守不住方向; 而方向错正是用户看到的那个现象)
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_info_panel_stats.tscn --quit-after 1500

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 从属性行里挑出【攻速】那一格的文本。
func _aspd_text(u: Dictionary) -> String:
	for row in _s._info_sys._info_stat_rows(u):
		var t: String = str(row[1])
		if t.begins_with("攻速"):
			return t
	return ""


func _ready() -> void:
	await get_tree().process_frame
	print("=== 局内详情面板: 攻速读数 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	var u: Dictionary = _s._spawn._make_unit("basic", "left",
		_s.ARENA.position + _s.ARENA.size * 0.5)
	u["atk_interval"] = 1.0
	var t1: String = _aspd_text(u)
	_ok("★分母: 属性行里找得到【攻速】那一格", t1 != "", "实得 '%s'" % t1)
	if t1 == "":
		print("FAIL x1"); get_tree().quit(1); return

	# ── ① 印的是【速率】不是【间隔】 ────────────────────────────────
	## ★★2026-09-28 换判据。原来这条是 `t1.find("次/秒") >= 0` —— 抄的是**单位那几个字**。
	##   今天按用户"去工程单位"的要求把它改成「攻速 每秒 N 下」(`X/Y` 是规格表写单位的写法),
	##   这条当场红, 而它红的**不是缺陷** —— 判据钉的是文案不是事实。
	## ⇒ 改成量这一行的**语义**, 用一个【速率与间隔数值不同】的样本把两者分开:
	##     间隔 1.25 秒 ⇒ 速率 0.8。印 0.8 = 速率(对); 印 1.25 = 间隔(就是 2026-08-10 那个 bug)。
	##   原判据在 atk_interval = 1.0 时**根本分不开**这两者(1 和 1 一样), 靠的全是那几个字;
	##   新判据不认字, 只认数, 顺带守"单位里点明了每秒"(带「秒」字)而不钉是哪几个字。
	u["atk_interval"] = 1.25
	var t_rate: String = _aspd_text(u)
	var want_rate: String = _s._fmt_num(_s.aspd_mult(u) / 1.25)
	_ok("★分母: 这个样本下速率(%s)与间隔(1.25)数值确实不同, 两者分得开" % want_rate,
		want_rate != "1.25", "速率 %s / 间隔 1.25" % want_rate)
	_ok("① ★印的是【速率】不是【间隔】(间隔 1.25 秒 ⇒ 该印 %s)" % want_rate,
		t_rate.find(want_rate) >= 0 and t_rate.find("1.25") < 0, "实得 '%s'" % t_rate)
	_ok("① 单位里点明了【每秒】(带「秒」字, 不钉是哪几个字)",
		t_rate.find("秒") >= 0, "实得 '%s'" % t_rate)
	u["atk_interval"] = 1.0
	t1 = _aspd_text(u)

	# ── ② 间隔 1.0 秒 ⇒ 1 次/秒 ─────────────────────────────────
	_ok("② 间隔 1.00 秒 ⇒ 显示 1 次/秒", t1.find("1") >= 0, "实得 '%s'" % t1)

	# ── ③ ★方向: 攻速【变快】时显示的数字必须【变大】 ───────────
	#    这一条才是用户看到的那个现象的根 —— 原来显示间隔, 变快时数字反而变小。
	var n1: float = _num_in(t1)
	u["atk_interval"] = 0.5          # 攻速翻倍
	var t2: String = _aspd_text(u)
	var n2: float = _num_in(t2)
	_ok("③ ★★攻速翻倍(间隔 1.00→0.50) ⇒ 显示的数字必须【变大】",
		n2 > n1 + 0.4, "1.00 秒时 '%s'(%.2f) → 0.50 秒时 '%s'(%.2f)" % [t1, n1, t2, n2])
	_ok("③ ★而且是**翻倍**关系(1 次/秒 → 2 次/秒), 不只是变大了一点",
		absf(n2 - n1 * 2.0) < 0.25, "%.2f vs %.2f×2" % [n2, n1])

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 详情面板属性读数" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 从 "攻速 2 次/秒" 里抠出那个数
func _num_in(t: String) -> float:
	var re := RegEx.new()
	re.compile("[0-9]+(\\.[0-9]+)?")
	var m := re.search(t)
	return float(m.get_string()) if m != null else -1.0
