extends Node
## verify_stream_anim_timing.gd —— 看直播时立绘换帧的时刻不再挤在 33ms 的采样点上 · 训龟大师投掷不闪帧(2026-11-20)。
## 用户 11-20「人物角色的那个动画啥的，感觉有时候一抽一抽的，不知道怎么回事」(Windows 239Hz 屏, 积分赛看直播)。
##   实测(tests/probes/_probe_motion_jitter.gd, 真窗口按真实时间播): 本机打时立绘帧停留在 60~100ms 连续铺开,
##   看直播时挤在 67 / 100 / 133ms —— 服务器每 2 步(33ms)跑一次渲染步、帧号到采样点才换 ⇒ 一个 12 帧/秒的动作变成 67、100、67、100 交替;
##   训龟大师投掷 7 帧按 11 帧/秒走要 0.64 秒, 扔一下比这短 ⇒ 最后一帧只露几毫秒下一扔就开始(本机打也一样)。
## 改法: ① 录流器的渲染步把立绘帧推进分 StreamRecorder.ANIM_SUB 小段, 换帧落在第几段随帧号发 `@fat`; 播放端插值时到那一刻就换
##   (StreamMirror.lerp_to `_pre_frame`; 只看紧挨着的下一个采样、中间夹 keyframe 不提前)
##   ② 每帧最短停 1 步(StreamMirror.observe_frames: 不论谁改的帧号都记下时刻 —— 出招起手播放端自己重置成 0 那一下也算)
##   ③ 训龟大师按这一扔的整段时长平均分 7 帧(battle_render._update_trainer_anim)
## 判据(无头: 帧号不靠渲染; 播放头手推, 每帧 1/240 秒 ≈ 用户的 239Hz 屏; heavy 局: 训龟大师连扔):
##   ① 分母: 龟的立绘帧停留样本 ≥ 300; 训龟大师换帧 ≥ 30
##   ② ★落在 33.3ms 整数倍(±2ms)上的停留占比 ≤ GRID_MAX(修前实测见 PRE_NOTE)
##   ③ ★所有单位都没有只停 1 个渲染帧就换掉的闪帧
## 反向验证(11-20): ANIM_SUB 改回 1 ⇒ ② 红(0.98); 不调 observe_frames ⇒ ③ 红(出招起手第 0 帧只露 4ms);
##   训龟大师改回按帧率分帧 ⇒ ③ 红(最后一帧 4ms)。曾试过的「训龟大师帧号只由客户端算」「扔完停一个采样」两处反向验证不红 ⇒ 没留。

const SP := preload("res://tests/_stream_play.gd")
const J := preload("res://tests/_stream_jobs.gd")
const DT := 1.0 / 240.0
const GRID := 1000.0 / 30.0
const GRID_TOL := 2.0
const GRID_MAX := 0.45
const PRE_NOTE := "修前播流实测 0.98(ANIM_SUB=1 变异)"

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if cond else "FAIL", name, detail])


func _ready() -> void:
	print("=== verify_stream_anim_timing ===")
	var gs = get_node_or_null("/root/GameState")
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var nat: Dictionary = await SP.record_referee_shared(self, J.heavy())   # heavy: 真实快照对局, 训龟大师连扔(镜像局里它不连扔 ⇒ ③ 照不到)
	var res: Dictionary = nat["res"]
	var chunks: Array = res.get("stream_chunks", [])
	_ok("分母: 录到流", chunks.size() > 30, "%d 块" % chunks.size())
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	ReplayRecorder.pending_play = {}
	ReplayRecorder.play_names = {}
	gs.dual_lineup = {}
	gs.dual_ghost = {}
	StreamPlayer.pending = {"source": StreamSource.Mem.new(chunks, res.get("stream", {})), "seed": int(nat["seed"]), "no_curtain": true}
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(b)
	StreamPlayer.pending = {}
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	var t := 0.0
	var last := {}          # 单位 idx → [帧号, 起始 t, 贴图]
	var holds: Array = []
	var flashes: Array = []
	var tr_changes := 0
	var guard := 0
	p.advance(0.0)
	while p.state != "ended" and p.state != "error" and guard < 300000:
		guard += 1
		p.advance(DT)
		t += DT
		if str(b._dl_state) != "fight":
			last.clear()
			continue
		for i in p.units:
			var u: Dictionary = p.units[i]
			var spr = u.get("sprite")
			if not bool(u.get("alive", false)) or not (spr is Sprite3D) or not is_instance_valid(spr):
				last.erase(i)
				continue
			var fr: int = (spr as Sprite3D).frame
			var tex = (spr as Sprite3D).texture
			if not last.has(i):
				last[i] = [fr, t, tex, []]
				continue
			var pv: Array = last[i]
			if fr != int(pv[0]) or tex != pv[2]:
				var held := (t - float(pv[1])) * 1000.0
				var hist: Array = pv[3]
				hist.append("步%d:%d" % [p.cur_step, fr])
				if hist.size() > 6:
					hist.pop_front()
				if bool(u.get("is_trainer", false)) and tex == pv[2]:
					tr_changes += 1
				if tex == pv[2]:
					if held < DT * 1000.0 * 1.5:
						flashes.append("%s %d→%d 停 %.1fms 动作=%s 近几次换帧 %s" % [str(u.get("id", "?")), int(pv[0]), fr, held, str(u.get("anim_action", "")), str(hist)])
					elif not bool(u.get("is_trainer", false)):
						holds.append(held)
				last[i] = [fr, t, tex, hist]
		if guard % 240 == 0:
			await get_tree().process_frame
	var on_grid := 0
	for h in holds:
		var k := roundf(float(h) / GRID)
		if k >= 1.0 and absf(float(h) - k * GRID) <= GRID_TOL:
			on_grid += 1
	var frac := float(on_grid) / maxf(1.0, float(holds.size()))
	_ok("① 分母: 龟的立绘帧停留样本 %d 个(交战段)" % holds.size(), holds.size() >= 300)
	_ok("② ★停留落在 33.3ms 整数倍(±%.0fms)上的占比 %.2f ≤ %.2f(%s)" % [GRID_TOL, frac, GRID_MAX, PRE_NOTE], frac <= GRID_MAX)
	_ok("③ 分母: 训龟大师在交战段换帧 %d 次(它连扔才会撞上闪帧)" % tr_changes, tr_changes >= 30)
	_ok("③ ★没有只停 1 个渲染帧就换掉的闪帧(训龟大师投掷曾每 5 秒一次)", flashes.is_empty(), str(flashes.slice(0, 6)))
	b.queue_free()
	await get_tree().process_frame
	ReplayRecorder.end_play()
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
