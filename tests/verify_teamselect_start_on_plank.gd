extends Node
## verify_teamselect_start_on_plank.gd — 选龟页「出战」字必须落在背景烤好的绿牌上(2026-10-13 内测反馈)
##
## 玩家 b250de29(iPhone15,4 · v0.19.570):「选龟页开始按钮偏移」。
## 绿牌烤在 select-bg.png 上(跟舞台走), 字是一个透明 Button。旧代码把 Button 按安全区夹进来
##   (底部手势条) + 绕中心撑到触控下限后再夹一次 ⇒ 字被推离绿牌; 绿牌不动。
## 判据(iPhone 15 横屏: 视口 1561×720, 安全区 左/右 108 · 下 38.5 逻辑px):
##   ① ★按钮中心落在绿牌(设计区 "start" 经同一舞台变换)里, 竖向偏差 ≤ 4px
##   ② 按钮整个在屏幕内
##   ③ 绿牌下沿尽量避开手势条: 不低于「屏底 − 手势条」超过 8px
##   ④ 顶上返回键仍在安全边距内(舞台上移不许把它顶出去)
##   ⑤ 对照: 桌面(无安全区)1280×720 下同样贴牌
##   ⑥ (2026-10-23) 「撤下」没东西可撤时置灰: 空队灰 → 上阵一只亮 → 撤下之后又灰(原来空着也亮, 点了没反应)

const TS := "res://scenes/TeamSelect.tscn"

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _measure(tag: String, vp: Vector2i, ins: Vector4) -> void:
	get_tree().root.size = vp
	SafeArea.override_insets = ins
	await get_tree().process_frame
	var ts = load(TS).instantiate()
	add_child(ts)
	for _i in range(40):
		await get_tree().process_frame
	var btn: Control = ts._start_btn
	var plank: Rect2 = ts._rect("start")
	var br := Rect2(btn.position, btn.size)
	var vpf := Vector2(vp)
	print("  [实测] %s 绿牌 %s  按钮 %s" % [tag, str(plank), str(br)])
	var dc: Vector2 = br.get_center() - plank.get_center()
	_ok("① ★%s 按钮中心落在绿牌上(偏 %.1f, %.1f)" % [tag, dc.x, dc.y], plank.has_point(br.get_center()) and absf(dc.y) <= 4.0 and absf(dc.x) <= 4.0)
	_ok("② %s 按钮整个在屏幕内" % tag, br.position.x >= 0.0 and br.position.y >= 0.0 and br.end.x <= vpf.x + 0.5 and br.end.y <= vpf.y + 0.5, str(br))
	_ok("③ %s 绿牌下沿离开手势条(≤ 8px 侵入)" % tag, plank.end.y <= vpf.y - ins.w + 8.0, "下沿 %.1f / 手势条上沿 %.1f" % [plank.end.y, vpf.y - ins.w])
	var top_ok := true
	for c in ts._edge_btns:
		if is_instance_valid(c) and (c as Control).visible and c != btn:
			top_ok = top_ok and (c as Control).position.y >= ins.y + 6.0 - 0.5
	_ok("④ %s 顶上贴边按钮仍在安全边距内" % tag, top_ok)
	if tag == "桌面":
		await _check_clear(ts)
	ts.queue_free()
	await get_tree().process_frame


func _check_clear(ts) -> void:
	_ok("⑥ 分母: 「撤下」键在、本大轮没锁(新存档)", ts._clear_btn != null and not ts._roster_locked,
		"locked=%s" % str(ts._roster_locked))
	if ts._clear_btn == null or ts._roster_locked:
		return
	ts.team = [null, null, null]
	ts._refresh_after_team()
	_ok("★⑥ 一只都没上阵 ⇒「撤下」置灰", ts._clear_btn.disabled)
	var pid: String = str(ts.detail_pet_id)
	ts._on_pick_pet(pid)
	await get_tree().process_frame
	var placed := 0
	for t in ts.team:
		if t != null:
			placed += 1
	_ok("⑥ 分母: 点了一只真的上阵了(%s)" % pid, placed == 1, str(ts.team))
	_ok("★⑥ 上阵一只 ⇒「撤下」亮起", not ts._clear_btn.disabled)
	ts._on_clear_all()
	_ok("★⑥ 撤下之后 ⇒ 又置灰", ts._clear_btn.disabled)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 选龟页「出战」贴绿牌 ===")
	await _measure("iPhone15", Vector2i(1561, 720), Vector4(108.0, 0.0, 108.0, 38.5))
	await _measure("桌面", Vector2i(1280, 720), Vector4(0, 0, 0, 0))
	SafeArea.override_insets = Vector4(-1, -1, -1, -1)
	get_tree().root.size = Vector2i(1280, 720)
	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 选龟页「出战」贴绿牌 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)
