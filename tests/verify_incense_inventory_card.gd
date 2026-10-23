extends Node
## verify_incense_inventory_card.gd — 093 香火石: 背包里说明卡显示当前刻痕 / 充能(2026-10-23 · 方案书 20261023-香火石四个问题 4)。
##
## 缺口: 刻痕 / 充能是跨对局养成的, 但背包 / 羁绊面板 / 图鉴都不读它们, 只有进了对局、装备格上才看得到。
## 判据(真背包场景, 点背包格的真处理函数 `_on_bench_click`):
##   ① 选中香火石 ⇒ 说明卡上有「刻痕 N / 300 · 充能 N / 4000」, 数字 = 存档里的
##   ② 刻痕满 300 ⇒ 写「（已满）」, 不再显示充能
##   ③ 反面: 别的装备的说明卡上没有这一行

const Inc := preload("res://scripts/systems/equip/incense_stone_system.gd")
const KEYS := ["season_leaders", "persistent_bench", "incense_marks", "incense_charge", "candy_jar_count",
	"tutorial_active", "test_mode"]

var _n := 0
var _fail := 0
var _bak := {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	for k in KEYS:
		var v = GameState.get(k)
		_bak[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	GameState.test_mode = true
	GameState.tutorial_active = false
	GameState.season_leaders = ["basic", "stone", "ninja"]
	GameState.candy_jar_count = 0
	GameState.persistent_bench = [{"id": Inc.EID, "star": 2}, {"id": "p2eq_004", "star": 1}]
	print("=== 093 香火石: 背包说明卡的刻痕 / 充能 ===")

	var t1 := await _card_text(0, 51, 2712)
	var want1 := "刻痕 51 / %d · 充能 2712 / %d" % [Inc.MARK_CAP, Inc.PER_MARK]
	_ok("★分母: 选中香火石后说明卡打开了(标题是香火石)", t1.find("香火石") >= 0, t1.left(60))
	_ok("★★① 说明卡上有当前刻痕与充能(数字 = 存档里的 51 / 2712)", t1.find(want1) >= 0, "要找「%s」" % want1)

	var t2 := await _card_text(0, Inc.MARK_CAP, 4000)
	_ok("★★② 刻痕满 %d ⇒「（已满）」、不再写充能" % Inc.MARK_CAP,
		t2.find("刻痕 %d / %d（已满）" % [Inc.MARK_CAP, Inc.MARK_CAP]) >= 0 and t2.find("充能") < 0, t2.right(60))

	var t3 := await _card_text(1, 51, 2712)
	_ok("★分母: 第二件装备的说明卡也打开了", t3 != "", t3.left(40))
	_ok("★③ 反面: 别的装备的说明卡上没有刻痕那一行", t3.find("刻痕 51") < 0)

	for k in KEYS:
		GameState.set(k, _bak[k])
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 香火石背包说明卡" if _fail == 0 and _n >= 5 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 新建一个背包场景, 摆好存档里的刻痕 / 充能, 点第 idx 件(真处理函数), 读说明卡上全部文字。
func _card_text(idx: int, marks: int, charge: int) -> String:
	GameState.incense_marks = marks
	GameState.incense_charge = charge
	var inv = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv)
	for _i in range(8):
		await get_tree().process_frame
	inv._on_bench_click(idx)
	for _i in range(4):
		await get_tree().process_frame
	var card: Node = inv.find_child("ItemInspectCard", true, false)
	var out := ""
	if card != null:
		out = _all_text(card)
	inv.queue_free()
	for _i in range(2):
		await get_tree().process_frame
	return out


func _all_text(n: Node) -> String:
	var s := ""
	if n is RichTextLabel:
		s += (n as RichTextLabel).get_parsed_text() + "\n"
	elif n is Label:
		s += (n as Label).text + "\n"
	for c in n.get_children():
		s += _all_text(c)
	return s
