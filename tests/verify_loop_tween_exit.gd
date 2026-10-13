extends Node
## verify_loop_tween_exit.gd — 换场景时界面上的循环 tween 必须先停(2026-10-13 内测)
##
## 由来: 内测报错表 `Condition "!is_inside_tree()" is true` @ can_process(iOS 排行榜 5 次、iOS / 安卓选龟页),
##   只有引擎栈: 旧场景移出树后、释放前, 绑在它上面的循环 tween 照样被 SceneTree 推进。
## 判据(对每个有循环 tween 的界面): 放进树等它建好 ⇒ 引擎在推的 tween 比放之前多(分母);
##   移出树后下一拍 ⇒ 引擎在推的 tween 回到放之前的数(循环的都停了)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_loop_tween_exit.tscn

const SCENES := [
	"res://scenes/Leaderboard.tscn",
	"res://scenes/TeamSelect.tscn",
	"res://scenes/Codex.tscn",
	"res://scenes/Settings.tscn",
	"res://scenes/Shop.tscn",
	"res://scenes/Record.tscn",
]

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _live() -> int:
	var k := 0
	for t in get_tree().get_processed_tweens():
		if t != null and t.is_valid() and t.is_running():
			k += 1
	return k


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		if not (gs.season_leaders is Array) or (gs.season_leaders as Array).size() < 3:
			gs.season_leaders = ["basic", "stone", "bamboo"]
		gs.season_total_battles = maxi(1, int(gs.season_total_battles))   # 商店打完第一场才开
	print("=== 换场景时循环 tween 先停 ===")
	var grew := 0
	for path in SCENES:
		if not ResourceLoader.exists(path):
			_ok("场景存在 " + path, false)
			continue
		var base := _live()
		var sc: Node = (load(path) as PackedScene).instantiate()
		add_child(sc)
		## 按真实时间等 3 秒: 一次性的入场 / 提示 tween(选龟页提示条 0.2+1.8+0.2 秒)先走完, 只剩循环的
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 3000:
			await get_tree().process_frame
		var mid := _live()
		if mid > base:
			grew += 1
		remove_child(sc)                    # 模拟换场景: 先移出树, 稍后才释放
		await get_tree().process_frame
		await get_tree().process_frame
		var after := _live()
		_ok("%s: 移出树后引擎不再推它的 tween(放前 %d / 在树 %d / 移出 %d)" % [path.get_file(), base, mid, after], after <= base,
			"还剩 %d 个在推" % (after - base))
		sc.queue_free()
		await get_tree().process_frame
	_ok("分母: 至少 3 个界面在树上时真的建了循环 tween", grew >= 3, "grew=%d" % grew)
	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 换场景时循环 tween 先停 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)
