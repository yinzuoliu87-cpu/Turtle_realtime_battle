extends Node
## _shot_queue_wait.gd — 闯关排队等待屏实拍(2026-10-27): 等待中两张(剪影换组前 / 后, 扫描亮带位置不同)+ 正在退出一张。
##   等待屏盖满整屏(在匹配屏之上), 直接建它与在匹配屏里看到的是同一幅画面; 快照用 RefereeWatch.my_snapshot()(进队交上去的同一个构造)。
## ⚠ 要开窗口才拍得到(无头模式不出画面)。用户 10-27「停，别弹窗」之后**先不跑**, 等用户方便时:
##   SHOT_OUT=<目录> SHOT_TAG=phone QUIET=1 <godot> --position 2000,80 --resolution 1560x720 --path . res://tests/_shot_queue_wait.tscn
##   SHOT_OUT=<目录> SHOT_TAG=ipad  QUIET=1 <godot> --position 2000,80 --resolution 1280x960 --path . res://tests/_shot_queue_wait.tscn

const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

var _dir := "user://"
var _tag := "x"


func _shot(name: String) -> void:
	for _i in range(3):
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_dir, name, _tag])
	print("shot ", name)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_dir = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "user://"
	_tag = OS.get_environment("SHOT_TAG") if OS.has_environment("SHOT_TAG") else "x"
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true                                  # 不写真存档
	gs.season_leaders = ["phoenix", "pirate", "ninja"]
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "phoenix", "equips": []}, {"kind": "leader", "slot": 1, "id": "pirate", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 2, "id": "ninja", "equips": []}, {"kind": "minion", "role": "front", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var snap := RW.my_snapshot()
	var vp := Vector2(get_viewport().get_visible_rect().size)
	var host := Control.new()
	host.size = vp
	add_child(host)
	var v: QueueWaitView = QueueWaitView.new()
	host.add_child(v)
	v.build(snap, Vector2i(2, 1), int(P2C.GAUNTLET_WINS_IN), int(P2C.GAUNTLET_LOSSES_OUT))
	v.set_cell_text(RW.queue_cell_text(2, 1))
	v.set_cancel(RW.TXT_QUEUE_CANCEL, false)
	v.waited_lb.text = RW.queue_waited_text(64)
	v.relayout(vp, ((vp - Vector2(QueueWaitView.FW, QueueWaitView.FH)) / 2.0).round())
	var tk := v.get_node_or_null("QueueAnim") as Timer
	if tk != null:
		tk.stop()                                        # 手动走帧, 两张图的帧号确定
	for _i in range(20):
		await get_tree().process_frame
	await _shot("queue_wait_f0")
	v._step()
	v._step()
	v._step()
	await _shot("queue_wait_f3")
	v.set_cancel(RW.TXT_QUEUE_CANCELLING, true)
	await _shot("queue_cancelling")
	get_tree().quit(0)
