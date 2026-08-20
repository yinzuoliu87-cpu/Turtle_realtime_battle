extends Node
## verify_lane_clear_wired.gd — 有"换路撤场"函数的系统, 必须真的被接进换路清场
##
## ★由来(2026-08-20): 五个系统的 `clear_all()` 注释白纸黑字写着自己是"换路撤场"用的, 还写明了漏调的后果 ——
##   · eq_arcane_batch 「漏了就会把上一路的碑带进下一路, 攻速增量永远收不回来 = 每换一路白涨一次」
##   · eq_relic_batch  「漏了就会把上一路的碑(和它的 +35% 增伤 / +50 双抗)带进下一路」
##   · eq_gun_batch / eq_blade_batch 「留着就是悬空引用, 下一路会对着上一路的字典结算」
##   **而它们从来没有被调用过。** 作者写好了清理、写明了后果、没人接线。
##
## ★为什么要门禁: dual_lane_flow 里那是一张**手写名单**, 它自己的注释就写着"明天还要接着实装剩下 17 件,
##   那时可能又多几路" —— 手写名单必漂。让"漏了"变成红灯, 这个形状才算焊死。
##
## ★判据: 扫 `scripts/systems/` 里所有定义了 `clear_all()` 的类, 每个必须满足二选一 ——
##   ① 它的 battle 成员名出现在 dual_lane_flow.gd 里
##   ② 在下面 EXEMPT 里显式登记, 并写清楚**为什么不清**
##   不许有第三种状态(既没接线也没登记)。

## 故意不清的, 每条必须有理由
const EXEMPT := {
	"IncenseStoneSystem": "香火石是**跨对局养成**、要落存档的; 换路清了就把玩家的进度抹了",
}

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	print("=== 换路撤场接线 ===")
	var dl := FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd")
	_ok("★分母: 换路流程文件读得到", dl.length() > 5000, "%d 字" % dl.length())

	# battle / equip_system 里 类名 → 成员名
	var member := {}
	for src_path in ["res://scripts/scenes/RealtimeBattle3DScene.gd",
			"res://scripts/systems/equip/equip_system.gd"]:
		var src := FileAccess.get_file_as_string(src_path)
		## 正则里一律不写反斜杠(用字符类) —— heredoc 会把双反斜杠吃成单个, GDScript 直接 Parse Error。
		##   这里用 [_a-zA-Z0-9]+ 之类的字符类, 完全不写反斜杠, 一劳永逸。
		var re := RegEx.create_from_string("(_[a-zA-Z0-9_]+)[ ]*(:=|=)[ ]*([A-Za-z0-9_]+)[.]new[(]")
		## ★还有第二种写法: `const VENOM_DRONE := preload("…eq_venom_drone.gd")` + `_venom = VENOM_DRONE.new(b)`
		##   —— 类名根本不出现在赋值处。只认第一种会把**已经接好线的** VenomDroneSystem 判成漏接。
		##   (判据窄一格就放过真 bug、宽一格就造假 bug, 这次是窄。)
		var pre := RegEx.create_from_string('const[ ]+([A-Z_0-9]+)[ ]*:?=[ ]*preload[(]"([^"]+)"[)]')
		var path_of := {}
		for pm in pre.search_all(src):
			path_of[pm.get_string(1)] = pm.get_string(2)
		var re2 := RegEx.create_from_string("(_[a-zA-Z0-9_]+)[ ]*=[ ]*([A-Z_0-9]+)[.]new[(]")
		for m2 in re2.search_all(src):
			var pth: String = str(path_of.get(m2.get_string(2), ""))
			if pth == "" or not ResourceLoader.exists(pth):
				continue
			var _re_cls := RegEx.create_from_string("(?m)^class_name[ ]+([A-Za-z0-9_]+)")
			var cm2 := _re_cls.search(FileAccess.get_file_as_string(pth))
			if cm2 != null and not member.has(cm2.get_string(1)):
				member[cm2.get_string(1)] = m2.get_string(1)
		for m in re.search_all(src):
			if not member.has(m.get_string(3)):
				member[m.get_string(3)] = m.get_string(1)

	## 抠出 `for _sysref in [ ... ]:` 那段数组文本 —— 判据只在它里面找
	var list_txt := ""
	var _li := dl.find("for _sysref in [")
	if _li >= 0:
		var _le := dl.find("]:", _li)
		list_txt = dl.substr(_li, maxi(0, _le - _li))
	_ok("★分母: 抠到了换路清场名单", list_txt.length() > 60, "%d 字" % list_txt.length())
	var scanned := 0
	var unwired: PackedStringArray = []
	var dir := DirAccess.open("res://scripts/systems")
	var files := _all_gd("res://scripts/systems")
	for f in files:
		var s := FileAccess.get_file_as_string(f)
		if not s.contains("func clear_all()"):
			continue
		var _rc := RegEx.create_from_string("(?m)^class_name[ ]+([A-Za-z0-9_]+)")
		var cm := _rc.search(s)
		if cm == null:
			continue
		var cls := cm.get_string(1)
		scanned += 1
		if EXEMPT.has(cls):
			continue
		## ★★判据必须卡"在不在清场名单里", 不是"这个名字在文件里出现过" ——
		##   第一版写成 dl.contains(mem), 反向验证时把 _relic_sys 从名单里删掉**门禁照样绿**,
		##   因为它在文件别处(注释/其它调用)也出现。宽一格 = 假门禁。
		##   现在只认两种真接线: ① 出现在 `for _sysref in [...]` 那个数组里 ② 有 `X.clear_all()`/`X.clear()` 的显式调用。
		var mem: String = str(member.get(cls, ""))
		if mem != "" and (list_txt.contains(mem) or dl.contains(mem + ".clear")):
			continue
		unwired.append("%s(%s)" % [cls, mem if mem != "" else "找不到成员名"])

	_ok("★分母: 扫到带 clear_all 的系统 (N=%d)" % scanned, scanned >= 8,
		"太少 = 扫描失效, 不是真的没有")
	_ok("★有换路撤场函数的系统都接进了换路清场", unwired.is_empty(), str(unwired))
	var _why_ok := true
	for _v in EXEMPT.values():
		if str(_v).length() <= 10:
			_why_ok = false
	_ok("★豁免都写了理由", _why_ok, "%d 条豁免" % EXEMPT.size())

	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 换路撤场接线" if _fail == 0 else "FAIL")
	get_tree().quit(0 if _fail == 0 else 1)


func _all_gd(root: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p := root + "/" + n
		if d.current_is_dir():
			out.append_array(_all_gd(p))
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	return out
