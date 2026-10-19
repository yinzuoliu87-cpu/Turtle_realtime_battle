class_name DeviceSelfcheck
extends RefCounted
## 设备确定性自检(诊断用)—— 设置页版本号连点 5 次打开(`scripts/scenes/settings/selfcheck_panel.gd`)。
## 方案书 docs/plans/20261019-服务器裁判.md「设备自检（诊断用）」一节。
##
## ★做什么: 在这台设备上依次跑 `verify_determinism_cross` 那同一张 15 个场景的表(`DetScenarios.all()`),
##   同一个建场(`DetScenarios.run`)、同一个逐步指纹(`DetScenarios.fp`), 摘要与同一份金标
##   (`data/determinism_cross.json`, 在 Windows / Linux x86 上钉的)逐条比 ⇒ 这台设备(尤其 iPhone ARM)
##   算出来的与服务器(x86 Linux)是不是逐位一样。
## ★只用于诊断: 结果上报一条(`ErrorReporter.report`, kind = selfcheck), 不写存档、不作为任何功能的开关。
##   (用户 10-19 否决了「手机本地先播、服务器落账」:「万一对不上？不能啊，一点概率都不能出现啊」⇒ 对局一律等服务器。)
## ★不碰玩家的东西: 跑之前把 GameState 整份备份、换成全新默认值(门禁那台机器开局时的样子; 玩家的等级 / 装备 / 技能选择
##   会改战斗数值, 不换就不是在比同一局), 跑完逐个还原; `test_mode` 期间任何存盘空转。
##   调试场静态开关 `DEBUG_EDIT`、环境变量 `TURTLE_SEED`、调试场摆位文件、音效静音、背景音乐一并还原。

const GOLDEN_PATH := "res://data/determinism_cross.json"
const BATTLE_SCRIPT := "res://scripts/scenes/RealtimeBattle3DScene.gd"
## 调试场开打时会把摆位写进这个文件(`battle_debug_arena._edit_save_setup`)⇒ 跑前读下来、跑后原样写回。
const DEBUG_SETUP := "user://debug_setup.json"
const REPORT_KIND := "selfcheck"
const REPORT_TAG := "[SelfCheck]"

signal progressed(done: int, total: int, tag: String, ok: bool)

var cancelled := false
var running := false
## 每个场景一条 {tag, ok, digest, want}(取消时只有已跑完的)。
var results: Array = []
var elapsed_ms := 0


## 金标 {场景名: 摘要}。读不到 = {}(每一条都会判不一致)。
static func load_golden() -> Dictionary:
	if not FileAccess.file_exists(GOLDEN_PATH):
		return {}
	var p = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	return p if p is Dictionary else {}


static func scenarios() -> Array:
	return DetScenarios.all()


## 场景名开头的圈号(「⑧ 雷暴/…」→「⑧」)—— 屏上只写它, 全名在上报里。
static func short_tag(tag: String) -> String:
	return tag.get_slice(" ", 0)


func cancel() -> void:
	cancelled = true


## 跑完整一轮。`host` = 挂战斗场的节点(要在树里; 设置页传一个不渲染的 SubViewport)。
## 返回 `summary()`。
func run(host: Node) -> Dictionary:
	running = true
	cancelled = false
	results = []
	var t0 := Time.get_ticks_msec()
	var gs = host.get_node_or_null("/root/GameState")
	var golden := load_golden()
	var scs := scenarios()
	var rb = load(BATTLE_SCRIPT)
	## ── 现场 ──
	var backup: Dictionary = ReplayRecorder.capture_all()
	var tm0 := bool(gs.test_mode) if gs != null else false
	var dbg0 := bool(rb.DEBUG_EDIT)
	var seed0 := OS.get_environment("TURTLE_SEED")
	var had_setup := FileAccess.file_exists(DEBUG_SETUP)
	var setup0 := FileAccess.get_file_as_bytes(DEBUG_SETUP) if had_setup else PackedByteArray()
	var au := host.get_node_or_null("/root/Audio")
	var mute0 := false
	var bgm0 := ""
	var bgm_vol0 := 0.45
	if au != null:
		mute0 = bool(au.mute_sfx)
		bgm0 = str(au.get("_current_bgm"))
		bgm_vol0 = float(au.get("_current_base_vol"))
		au.mute_sfx = true
	if gs != null:
		_reset_to_defaults(gs)
		gs.test_mode = true
		gs.week_anchor_ts = int(DetScenarios.PIN_WEEK_ANCHOR)   # 与 verify_determinism_cross 同一个钉死的周
	## ── 逐个场景 ──
	var stop := func() -> bool:
		_quiet(host)
		return cancelled
	for i in range(scs.size()):
		if cancelled:
			break
		var sc: Dictionary = scs[i]
		var tag := str(sc["tag"])
		OS.set_environment("TURTLE_SEED", str(sc["seed"]))   # det 模式: 每帧恰一步(与门禁同一个开关)
		var r: Array = await DetScenarios.run(host, sc, stop)
		if cancelled:
			break                                            # 跑了一半的不判
		var dig := str(r[0])
		var want := str(golden.get(tag, ""))
		var ok := want != "" and dig == want
		results.append({"tag": tag, "ok": ok, "digest": dig, "want": want})
		progressed.emit(i + 1, scs.size(), tag, ok)
	## ── 还原 ──
	if seed0 != "":
		OS.set_environment("TURTLE_SEED", seed0)
	else:
		OS.unset_environment("TURTLE_SEED")
	rb.DEBUG_EDIT = dbg0
	if gs != null:
		for n in backup:
			var v = backup[n]
			gs.set(str(n), v.duplicate(true) if (v is Array or v is Dictionary) else v)
		gs.test_mode = tm0
	if had_setup:
		var f := FileAccess.open(DEBUG_SETUP, FileAccess.WRITE)
		if f != null:
			f.store_buffer(setup0)
			f.close()
	elif FileAccess.file_exists(DEBUG_SETUP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DEBUG_SETUP))
	if au != null:
		au.mute_sfx = mute0
		if bgm0 != "" and str(au.get("_current_bgm")) != bgm0:
			au.play_bgm(bgm0, 0.5, bgm_vol0)
		elif bgm0 == "" and str(au.get("_current_bgm")) != "":
			au.stop_bgm()
	elapsed_ms = Time.get_ticks_msec() - t0
	running = false
	return summary()


## {passed, total, failed: [场景名], cancelled, plat, arch, version, engine, elapsed_ms}
func summary() -> Dictionary:
	var passed := 0
	var failed: Array = []
	for r in results:
		if bool((r as Dictionary)["ok"]):
			passed += 1
		else:
			failed.append(str((r as Dictionary)["tag"]))
	return {"passed": passed, "total": scenarios().size(), "failed": failed, "cancelled": cancelled,
		"plat": OS.get_name(), "arch": Engine.get_architecture_name(),
		"version": ReplayRecorder.client_version(),
		"engine": str(Engine.get_version_info().get("string", "")), "elapsed_ms": elapsed_ms}


## 结论一句话(屏上): 「15/15 一致」/「13/15 一致 · 不一致 ③ ⑧」。
static func result_line(s: Dictionary) -> String:
	var line := "%d/%d 一致" % [int(s.get("passed", 0)), int(s.get("total", 0))]
	var fl: Array = s.get("failed", [])
	if not fl.is_empty():
		var short: Array = []
		for t in fl:
			short.append(short_tag(str(t)))
		line += " · 不一致 " + " ".join(short)
	return line


## 上报一条(诊断)。取消的不报。返回 true = 进了上报队列。
static func report(s: Dictionary, rows: Array) -> bool:
	if bool(s.get("cancelled", false)):
		return false
	var msg := "%s %d/%d 一致 · v%s · %s · %s" % [REPORT_TAG, int(s.get("passed", 0)), int(s.get("total", 0)),
		str(s.get("version", "")), str(s.get("plat", "")), str(s.get("arch", ""))]
	var lines: Array = ["engine %s · %d ms" % [str(s.get("engine", "")), int(s.get("elapsed_ms", 0))]]
	for r in rows:
		var d: Dictionary = r
		lines.append("%s %s %s / %s" % ["OK" if bool(d["ok"]) else "DIFF", str(d["tag"]),
			str(d["digest"]).left(16), str(d["want"]).left(16)])
	var key := "%s|%s|%s|%d|%s" % [str(s.get("version", "")), str(s.get("plat", "")), str(s.get("arch", "")),
		int(s.get("passed", 0)), ",".join(s.get("failed", []))]
	return ErrorReporter.report(REPORT_KIND, msg, "\n".join(lines), key)


## GameState 换成全新默认值(脚本里写的初值; 只换备份覆盖得到的那些变量 ⇒ 跑完都能还原)。
static func _reset_to_defaults(gs: Node) -> void:
	var fresh: Object = (gs.get_script() as Script).new()
	for n in ReplayRecorder.capture_all():
		var v = fresh.get(str(n))
		gs.set(str(n), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	if fresh is Node:
		(fresh as Node).free()


## 战斗场里那块 3D 子视口不画(结果与渲染无关; 只省手机的时间)。每帧被 `DetScenarios.run` 的 stop 回调问一次。
static func _quiet(host: Node) -> void:
	for c in host.get_children():
		var sub = c.get("_sub")
		if is_instance_valid(sub) and sub is SubViewport \
				and (sub as SubViewport).render_target_update_mode != SubViewport.UPDATE_DISABLED:
			(sub as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
