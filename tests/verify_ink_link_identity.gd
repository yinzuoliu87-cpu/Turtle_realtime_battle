extends Node
## verify_ink_link_identity.gd —— 线条龟「连笔」摘链要按【同一个单位】认, 不许用 `==` 比字典(2026-10-11 全项目通读第九条)
##
## ★CLAUDE.md §3.2: 单位字典之间互相引用成环, `==` 会递归比较整个字典 ⇒ 可能无限递归卡死;
##   而且内容碰巧相同的两个**不同**单位会被当成同一个 ⇒ 摘错链。
## ★判据: 两只内容完全相同、但不是同一个对象的单位 —— 摘 B 的链不许把 A 的链也摘掉;
##   单位之间互相引用成环时摘链不许报错。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 连笔摘链按身份认 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var a := {"id": "x", "hp": 1.0}
	var b := {"id": "x", "hp": 1.0}       # 内容与 a 完全相同, 但不是同一个对象
	var c := {"id": "y", "hp": 2.0}
	s._ink_links.clear()
	s._ink_links.append({"a": a, "b": c, "spr": null})
	s._drop_ink_link_of(b)
	_ok("★★摘 b 的链(b 与 a 内容相同但不是同一只) ⇒ a 的链还在", s._ink_links.size() == 1,
		"剩 %d 条" % s._ink_links.size())
	s._drop_ink_link_of(a)
	_ok("★对照: 摘 a 本人的链 ⇒ 摘掉了", s._ink_links.is_empty(), "剩 %d 条" % s._ink_links.size())

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
