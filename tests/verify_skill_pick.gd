extends Node
## verify_skill_pick.gd — 选龟页技能选择: 点了要真选中【并且真高亮】(用户 2026-07-28 报的 bug)
##
## 抓到过什么: skill_picker._toggle_skill 里写着 host._refresh_slots(), 而该函数在上帝文件拆分时
## 搬到了 roster_slots.gd → 运行时 "Nonexistent function" 炸在第一行, 后面重建图标的
## _refresh_detail() 根本不执行。表现是【数据改了但界面不高亮】—— GDScript 动态派发,
## 编译期查不出来, 只能靠这种"真点一下再看界面状态"的测试。
##
## 只回答四个问题, 打真数字:
##   ① 点击到底有没有改到 GameState.loadouts?
##   ② 改了之后重建出来的图标, 被选中那个的边框色是不是金色 #ffd86b?
##   ③ pressed 信号接了几个回调? (接两个 → 除了切换还会弹窗, 弹窗可能盖住高亮)
##   ④ 重建后旧按钮清干净了吗? (queue_free 是延迟的, 可能同时存在两批图标)
##
## ★进门禁。跑法(必须 headless, 本机开窗口会蓝屏):
##   <godot> --headless --audio-driver Dummy --path . res://tests/verify_skill_pick.tscn

## ★必须实例化 .tscn 而不是 new() 脚本 —— TeamSelectScene 有 @onready 节点路径("UI/Root"),
## 裸 new() 会全是 "Node not found" 然后 _detail_bottom 是 null。
const TSS := preload("res://scenes/TeamSelect.tscn")

var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	var dr = get_node_or_null("/root/DataRegistry")
	if gs == null or dr == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true

	print("=== 选龟页技能选择 探针 ===")
	var scene = TSS.instantiate()
	add_child(scene)
	for _i in range(8):
		await get_tree().process_frame

	var pid := "ice"
	scene.detail_pet_id = pid
	gs.loadouts[pid] = 1          # 起始: 选 1 号候选
	scene._detail._refresh_detail()
	await get_tree().process_frame

	var btns := _skill_buttons(scene)
	print("  技能图标数 = %d (期望 4: 普攻 + 3 候选)" % btns.size())
	if btns.size() != 4:
		print("  [FAIL] 图标数不对 —— 后面的判断没意义"); _fail += 1; _done(scene); return

	# ── ③ 每个按钮 pressed 接了几个回调 ──
	for i in range(btns.size()):
		var b: Button = btns[i]
		print("     [%d] pressed 回调 %d 个 · disabled=%s" % [i, b.pressed.get_connections().size(), b.disabled])

	# ── ① 点 idx=2 ──
	var before = gs.loadouts.get(pid, null)
	print("")
	print("  ① 点击前 loadouts[%s] = %s" % [pid, str(before)])
	btns[2].emit_signal("pressed")
	await get_tree().process_frame
	var after = gs.loadouts.get(pid, null)
	print("     点击 idx=2 后 loadouts[%s] = %s" % [pid, str(after)])
	_chk("① 点击真的改了 loadouts", int(after) == 2)

	# ── ④ 重建后按钮数 ──
	await get_tree().process_frame
	var btns2 := _skill_buttons(scene)
	print("")
	print("  ④ 重建后技能图标数 = %d" % btns2.size())
	_chk("④ 重建后仍是 4 个(没堆叠两批)", btns2.size() == 4)

	# ── ② 选中那个"看起来"是不是被点亮了 ──
	## ★判据换过一次(2026-08-19): 原来直接读 StyleBoxFlat.border_color 比对 #ffd86b。
	##   技能图标换成九宫贴图框之后, StyleBoxTexture **没有 border_color** —— 老判据会
	##   一律拿到透明黑, 于是"选中态"整条断言变成永假。它红了是对的, 不是误报。
	##   新判据不认表征、只认"点亮"这件事本身: 取该态的着色(贴图取 modulate_color /
	##   纯色取 border_color), 要求选中项**又暖又亮**, 且明显亮过没选中的那个。
	if btns2.size() == 4:
		print("")
		var tints: Array[Color] = []
		for i in range(btns2.size()):
			tints.append(_tint_of(btns2[i].get_theme_stylebox("normal")))
			print("     [%d] 着色 %s  亮度 %.2f" % [i, tints[i].to_html(false), _lum(tints[i])])
		var sel := tints[2]
		var oth := tints[1]
		var warm: bool = sel.r > sel.b + 0.4                      # 金 = 红远多于蓝
		var brighter: bool = _lum(sel) > _lum(oth) * 1.4          # 且确实比没选的亮
		_chk("② idx=2 被点亮成暖金(选中态)", warm and brighter)
		_chk("② idx=1 不再点亮(已让出选中)", not (oth.r > oth.b + 0.4 and _lum(oth) > _lum(sel) * 1.4))

	_done(scene)


func _skill_buttons(scene) -> Array:
	## 技能图标 = _detail_bottom 里 GridContainer 的 Button 子节点
	var out: Array = []
	var bottom = scene._detail_bottom
	if bottom == null:
		return out
	var stack: Array = [bottom]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GridContainer:
			for c in n.get_children():
				if c is Button and is_instance_valid(c) and not c.is_queued_for_deletion():
					out.append(c)
		for c in n.get_children():
			stack.append(c)
	return out


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])


func _done(scene) -> void:
	scene.queue_free()
	await get_tree().process_frame
	print("")
	print("  ALL PASS" if _fail == 0 else "  ★ %d 项 FAIL" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 取一个 StyleBox 的"着色" —— 贴图框用 modulate_color, 纯色框用 border_color。
## 两种表征都归到同一把尺子上, 以后再换皮不用再改判据。
func _tint_of(sb) -> Color:
	if sb is StyleBoxTexture:
		return (sb as StyleBoxTexture).modulate_color
	if sb is StyleBoxFlat:
		return (sb as StyleBoxFlat).border_color
	return Color(0, 0, 0, 0)


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
