extends Node
## verify_lane_flash_cut.gd —— 换路幕布: 闪白处硬切 + 切磋点幕布不跳(2026-11-18)。
## 用户 11-18:
##   「进入上路战场…那边闪白，从闪白跳到那个双方角色对立的那个。中间过渡有点不自然」
##     录帧量出: 闪白最亮那帧亮度 194, 下一帧掉到 106 —— 新幕整块 modulate 从 0.32 淡入, 它底下几层整屏的图各自乘 0.32 叠上去,
##     一帧就盖掉旧幕八成, 新幕自己那层白只剩 0.72×0.32 ⇒ 白光塌掉、露出暗底。修后同一段 186 → 167 → 151 → … 每帧匀速褪。
##   「切磋的时候，按来说是不是已经不可以点击去跳过了那些页面啥的，不可以去点击」
##     积分赛 / 闯关 / 决赛看服务器直播, 幕布本来就点不动; 切磋在本机算, 原来点一下就跳到下一幕。
## 实现: dual_lane_flow.FLASH_CUT_MIN / _flash_cut(出幕时旧幕停在闪白上 ⇒ 同一帧进来的新幕满不透明出场、旧幕当帧拿掉)
##       + _dl_present_click 第一行 Spar.is_active() 就返回。
## 判据(真战斗场 + App Store 截图台那份真实阵容, 无头):
##   ① 开场地图 → 上路对阵: 换幕前一帧旧幕闪白 ≥ 0.5(分母); 换幕那一帧新幕 modulate = 1、新幕闪白 ≥ 0.6、旧幕已拿掉(排队删除 / 已删)
##   ② 对阵 → 开打(旧幕没在闪白): 照旧交叉淡化 —— 下一帧旧幕还在、透明度在 0~1 之间
##   ③ 旧幕停在闪白上但同一帧没有新幕进来(2:0 横扫后直接结算): 旧幕照常淡出(下一帧还在、0 < a < 1); 隔帧再进的新幕照常从 0 淡入
##   ④ 切磋时点幕布: 状态不变、幕布还是那一块; 不在切磋时同样点一下 ⇒ 幕布被点掉(证明点击这条路是通的, 不是空检查)
## 反向验证(11-18): 出幕不记 _flash_cut ⇒ ① 红; 出幕一律当帧删 ⇒ ②③ 红; 去掉 Spar 那一行 ⇒ ④ 红。

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
const LMI := preload("res://scripts/scenes/battle/lane_map_intro.gd")

var _n := 0
var _fail := 0
var _b = null


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, d])


func _gone(n) -> bool:
	return n == null or not is_instance_valid(n) or (n as Node).is_queued_for_deletion()


func _ready() -> void:
	await get_tree().process_frame
	print("=== 换路幕布: 闪白处硬切 / 切磋点幕布不跳 ===")
	get_window().size = Vector2i(1560, 720)
	await get_tree().process_frame
	load("res://tests/_setup_appstore.gd").run()
	GameState.dual_active = true
	await get_tree().process_frame
	_b = load(BATTLE_SCENE).instantiate()
	add_child(_b)
	var flow = _b._dl_sys

	## ── ① 开场地图 → 上路对阵 ──
	var ok_ov := false
	for _i in 600:
		if str(_b._dl_state) == "overview" and _b._dl_present_root != null:
			ok_ov = true
			break
		await get_tree().process_frame
	_ok("分母: 进场就是开场地图幕", ok_ov, str(_b._dl_state))
	var old_root = _b._dl_present_root
	var last_fl := 0.0
	var switched := false
	for _i in 6000:
		await get_tree().process_frame
		if str(_b._dl_state) != "overview":
			switched = true
			break
		last_fl = LMI.flash_alpha_of(old_root)
	_ok("分母: 开场地图幕自己走到下一幕(%s)" % str(_b._dl_state), switched and str(_b._dl_state) == "preview")
	_ok("① 换幕前一帧旧幕停在闪白上(%.2f ≥ 0.5)" % last_fl, last_fl >= 0.5)
	var new_root = _b._dl_present_root
	var new_a: float = (new_root as Control).modulate.a if new_root != null else -1.0
	var new_fl: float = LMI.flash_alpha_of(new_root)
	_ok("① ★换幕那一帧新幕满不透明出场(modulate %.2f = 1)" % new_a, is_equal_approx(new_a, 1.0))
	_ok("① 新幕开头那层白接住旧幕(%.2f ≥ 0.6)" % new_fl, new_fl >= 0.6)
	_ok("① ★旧幕当帧拿掉(不交叉淡化)", _gone(old_root))

	## ── ② 对阵 → 开打: 旧幕没在闪白 ⇒ 照旧交叉淡化 ──
	var pv_root = _b._dl_present_root
	var left_pv := false
	var pv_fl := -1.0
	for _i in 6000:
		pv_fl = LMI.flash_alpha_of(pv_root)
		await get_tree().process_frame
		if str(_b._dl_state) != "preview":
			left_pv = true
			break
	_ok("分母: 对阵幕自己走完(%s), 走之前闪白 %.2f < 0.5" % [str(_b._dl_state), pv_fl], left_pv and pv_fl < 0.5)
	await get_tree().process_frame
	var pv_a: float = (pv_root as Control).modulate.a if not _gone(pv_root) else -1.0
	_ok("② 没闪白的换幕照旧淡出: 下一帧旧幕还在、透明度 %.3f 在 0~1 之间" % pv_a, not _gone(pv_root) and pv_a > 0.0 and pv_a < 1.0)

	## ── ③ 停在闪白上、但同一帧没有新幕(2:0 横扫后直接结算) ──
	flow._dl_enter_present("overview")
	var lone = _b._dl_present_root
	## 等它自己那 0.28 秒淡入走完(两条透明度动画别叠在一起量)
	for _i in 600:
		await get_tree().process_frame
		if lone == null or (lone as Control).modulate.a >= 0.999:
			break
	var lone_it = lone.get_meta(LMI.INTRO_META) if lone != null and lone.has_meta(LMI.INTRO_META) else null
	_ok("分母: 手动建的开场地图幕挂着演出对象", lone_it != null)
	if lone_it != null:
		(lone as Control).modulate.a = 1.0
		lone_it.pose(5.0)
		var lone_fl: float = LMI.flash_alpha_of(lone)
		_ok("分母: 摆到 5.0 秒闪白 %.2f ≥ 0.5" % lone_fl, lone_fl >= 0.5)
		flow._dl_clear_present_overlay()
		await get_tree().process_frame
		var la: float = (lone as Control).modulate.a if not _gone(lone) else -1.0
		_ok("③ ★同一帧没有新幕 ⇒ 旧幕照常淡出(下一帧还在、透明度 %.3f)" % la, not _gone(lone) and la > 0.0 and la < 1.0)
		flow._dl_enter_present("preview")
		var late = _b._dl_present_root
		var late_a: float = (late as Control).modulate.a if late != null else -1.0
		_ok("③ 隔帧再进的新幕照常从 0 淡入(进场时 %.2f)" % late_a, late_a >= 0.0 and late_a < 0.05)

	## ── ④ 切磋时点幕布不跳 ──
	for _i in 30:
		await get_tree().process_frame
	var st0 := str(_b._dl_state)
	var r0 = _b._dl_present_root
	_ok("分母: 此刻有一块对阵幕(%s)" % st0, st0 == "preview" and r0 != null)
	var was_spar: bool = Spar.active
	Spar.active = true
	flow._dl_present_click()
	await get_tree().process_frame
	_ok("④ ★切磋时点幕布: 状态不变(%s)、还是那一块幕" % str(_b._dl_state), str(_b._dl_state) == st0 and is_same(_b._dl_present_root, r0))
	Spar.active = was_spar
	flow._dl_present_click()
	await get_tree().process_frame
	_ok("④ 不在切磋时点一下 ⇒ 幕布被点掉(%s → %s)" % [st0, str(_b._dl_state)], str(_b._dl_state) != st0 and not is_same(_b._dl_present_root, r0))

	_finish()


func _finish() -> void:
	Spar.active = false
	print("[分母] 判据 %d 条 · 用了 %d 帧" % [_n, Engine.get_process_frames()])
	if _fail == 0 and _n >= 12:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)
