extends Node
## verify_timestop_lanes.gd — 059 沙漏【每个战场各一次】+ 演出层 + 空间扭曲 的门禁
##
## ══════════════════════════════════════════════════════════════════════
##  由来(2026-09-16 用户实测)
## ══════════════════════════════════════════════════════════════════════
## 「我实测发现沙漏有严重bug，需要对上战场，下战场，终极战场进行细节观测，以及空间扭曲特效不见了」
##
## 探针 `tests/_probe_timestop_lanes.gd` 在真实对局里量出来四条(方案书 docs/plans/20260916-059沙漏三战场修复.md):
##   A `_ts_fired` 永不重置 ⇒ 下路与终极战场【零蓄力零定格】(下路带 059 打满 52.8 秒, 终极 36.9 秒, 全是 0)
##   B 换路清了 `_ts_charge_casters` 却没清 `_ts_charging`/`_ts_charge_t` ⇒ 蓄力中换路 = 下一路白蓄 1 秒再被吞
##   C 换路把演出叠加层 `visible=false` 而全仓没人写回 ⇒ 修好 A 之后会变成「有定格没画面」
##   D 移动端 shader 分支里 warp/warp_r/zoom_blur 声明了但 fragment 一次没用 ⇒ iOS 上从来没有空间扭曲
##
## ══════════════════════════════════════════════════════════════════════
##  本文件的规矩
## ══════════════════════════════════════════════════════════════════════
## · **每条配一个分母断言**。这一类 bug 的判据特别容易变成恒真式:
##   比如「定格期间演出层没被隐藏」在修之前也是 0 —— 因为那时压根不定格, 循环根本不执行。
##   所以先证明"改之前的状态确实是坏的", 再证明"产品把它改好了"。
## · **判据里的秒数一律写死**(10.0 / 20.0), 不引 `TS_START_T` / `TS_DUR[2]` ——
##   拿被测常量当尺子, 常量被改坏时门禁跟着一起错, 等于没量。
## · **同步量**: 全部在一帧内调产品函数并当场断言, 不 await。跨一个帧就把"时间过去了"
##   算进判据, 冷却/计时这类单调量会让改坏了也全绿(memory fb-gate-tautological-when-it-spans-a-frame)。
## · 换路走**真入口** `_dl_next_lane()` —— 重置写在 `_dl_clear_units()` 里, 直接调它只能证明
##   函数本身好使, 证明不了换路时真有人调(memory fb-verify-must-run-the-real-path)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 059 沙漏: 每个战场各一次 / 演出层 / 空间扭曲 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	_t_lane_reset()
	_t_lane_t0()
	_t_empty_casters_not_charged()
	_t_overlay_visible()
	_t_warp_shader()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 059 沙漏三战场" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 造一个带 059 的活单位并放进场。★不复用别处的合成单位工具: 这里需要它的 `equips` 真的被
## `_unit_hourglass_star()` 读到, 而那个函数读的就是 `u["equips"]` 里的 id/star。
func _mk59(star: int, side: String = "left") -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", side, c + Vector2(-200.0 if side == "left" else 200.0, 0.0))
	u["maxHp"] = 100000.0
	u["hp"] = 100000.0
	u["alive"] = true
	u["equips"] = [{"id": "p2eq_059", "star": star}]
	u["eq_state"] = {"p2eq_059": {}}
	_s._units.append(u)
	return u


# ─────────────────────────────────────────────────────────────
# ① 换路重置: 触发闸门 + 蓄力状态, 一个都不许留到下一路
#    (A 与 B 两条缺陷都落在这里)
# ─────────────────────────────────────────────────────────────
func _t_lane_reset() -> void:
	print("── ① 换路重置(每个战场各一次) ──")
	var ts = _s._timestop
	_s._units.clear()
	var u: Dictionary = _mk59(3)
	# 摆成"上一路正在蓄力、而且已经用掉了本路名额"的样子
	ts._ts_fired = true
	ts._ts_charging = true
	ts._ts_charge_t = 0.7
	ts._ts_charge_casters = [u]
	ts._ts_maxstar = 3
	_ok("① ★分母: 换路【之前】确实是「已触发 + 蓄力中」",
		ts._ts_fired and ts._ts_charging and ts._ts_charge_t > 0.5 and (ts._ts_charge_casters as Array).size() == 1,
		"fired=%s charging=%s charge_t=%.2f casters=%d" % [str(ts._ts_fired), str(ts._ts_charging),
		float(ts._ts_charge_t), (ts._ts_charge_casters as Array).size()])

	_s._dl_sys._dl_next_lane("top")   # ★真入口: 清场 + 重置 + 重建下一路

	_ok("① 换路后 _ts_fired 归 false(否则下路/终极永远不触发 = 用户报的主症状)",
		ts._ts_fired == false, "fired=%s" % str(ts._ts_fired))
	_ok("① 换路后 _ts_charging 归 false(残留会让下一路白蓄 1 秒再被空 casters 吞掉)",
		ts._ts_charging == false, "charging=%s" % str(ts._ts_charging))
	_ok("① 换路后 _ts_charge_t 归 0", absf(float(ts._ts_charge_t)) < 0.0001,
		"charge_t=%.4f" % float(ts._ts_charge_t))
	_ok("① 换路后 _ts_charge_casters 清空", (ts._ts_charge_casters as Array).is_empty(),
		"casters=%d" % (ts._ts_charge_casters as Array).size())


# ─────────────────────────────────────────────────────────────
# ② 「登场 10 秒后」按【本战场】算, 不是按全局时钟
#    —— 全局 `_t` 跨路累加不重置(CLAUDE.md §3.4), 只清 `_ts_fired` 会让下路第一帧就放
# ─────────────────────────────────────────────────────────────
func _t_lane_t0() -> void:
	print("── ② 「第 10 秒」按本战场算 ──")
	var ts = _s._timestop
	_s._units.clear()
	var u: Dictionary = _mk59(3)
	ts._ts_fired = false
	ts._ts_charging = false
	ts._ts_active = []
	_ok("② ★分母: 这只龟确实被认成 3★ 沙漏携带者", ts._unit_hourglass_star(u) == 3,
		"star=%d" % ts._unit_hourglass_star(u))

	# 场景: 已经打到全局第 100 秒, 但【本路】才刚开打(本路已打 0 秒) → 不许触发
	_s._t = 100.0
	_s._sd_t0 = 100.0
	ts._ts_update_trigger(1.0 / 60.0)
	_ok("② 本路才打了 0 秒(全局已 100 秒) → 不触发", ts._ts_charging == false and ts._ts_fired == false,
		"charging=%s fired=%s" % [str(ts._ts_charging), str(ts._ts_fired)])

	# 场景: 本路已打 11 秒(> 10) → 该触发了。★11 和 10 都写死, 不引 TS_START_T
	_s._sd_t0 = 89.0
	ts._ts_update_trigger(1.0 / 60.0)
	_ok("② 本路已打 11 秒 → 开始蓄力", ts._ts_charging == true and ts._ts_fired == true,
		"charging=%s fired=%s 本路已打 %.1f 秒" % [str(ts._ts_charging), str(ts._ts_fired), _s._t - _s._sd_t0])

	# 蓄力跑满 → 真释放, 定格时长按 3★ = 20 秒(★写死 20.0, 不引 TS_DUR[2])
	ts._ts_charge_t = 0.0
	ts._ts_update_trigger(1.0 / 60.0)
	_ok("② 蓄力满 → 真的定格了", (ts._ts_active as Array).size() >= 1,
		"active=%d" % (ts._ts_active as Array).size())
	_ok("② 3★ 定格时长 = 20 秒", absf(float(ts._ts_remaining) - 20.0) < 0.0001,
		"remaining=%.4f total=%.4f" % [float(ts._ts_remaining), float(ts._ts_total)])
	ts._end_timestop()


# ─────────────────────────────────────────────────────────────
# ③ 没人放得出来 ≠ 这一路已经用掉了
# ─────────────────────────────────────────────────────────────
func _t_empty_casters_not_charged() -> void:
	print("── ③ 释放被吞时不记账 ──")
	var ts = _s._timestop
	_s._units.clear()
	var dead: Dictionary = _mk59(3)
	dead["alive"] = false            # 蓄力那 1 秒里死了 / 或换路把 casters 清了
	ts._ts_fired = true
	ts._ts_charging = false
	ts._ts_charge_casters = [dead]
	ts._ts_active = []
	_ok("③ ★分母: 释放之前确实记着「本路已触发」", ts._ts_fired == true, "fired=%s" % str(ts._ts_fired))

	ts._ts_fire()

	_ok("③ 没人能放 → 不定格", (ts._ts_active as Array).is_empty(),
		"active=%d" % (ts._ts_active as Array).size())
	_ok("③ 没放出来就不该记成「本路已用掉」", ts._ts_fired == false, "fired=%s" % str(ts._ts_fired))


# ─────────────────────────────────────────────────────────────
# ④ 演出叠加层: 被换路隐藏过之后, 下一次定格必须自己把它打开
#    ★分母是关键 —— 不先手动置 false, 这条就是恒真式(新建的层本来就可见)
# ─────────────────────────────────────────────────────────────
func _t_overlay_visible() -> void:
	print("── ④ 演出层(灰世界/能量波/空间扭曲/反色闪都挂在这两层) ──")
	var ts = _s._timestop
	_s._units.clear()
	var u: Dictionary = _mk59(3)
	ts._ts_ensure_overlay()
	_ok("④ ★分母: 两层都建出来了", is_instance_valid(ts._ts_overlay) and is_instance_valid(ts._ts_flash_overlay))
	# 复现换路清场干的事(dual_lane_flow._dl_clear_units)
	ts._ts_overlay.visible = false
	ts._ts_flash_overlay.visible = false
	_ok("④ ★分母: 先按换路清场的样子把两层隐藏掉",
		ts._ts_overlay.visible == false and ts._ts_flash_overlay.visible == false,
		"overlay=%s flash=%s" % [str(ts._ts_overlay.visible), str(ts._ts_flash_overlay.visible)])

	ts._ts_active = [u]
	ts._ts_visual_start()

	_ok("④ 定格演出开始时自己把灰世界层打开(否则「有定格没画面」)", ts._ts_overlay.visible == true,
		"overlay.visible=%s" % str(ts._ts_overlay.visible))
	_ok("④ 反色闪层同上", ts._ts_flash_overlay.visible == true,
		"flash.visible=%s" % str(ts._ts_flash_overlay.visible))
	ts._ts_active = []
	ts._ts_clear_visual_nodes()


# ─────────────────────────────────────────────────────────────
# ⑤ 空间扭曲: 参数得真的在 fragment 里被用上, 而且不能靠读屏
#    ★量的是【产品真函数造出来的那份 ShaderMaterial】, 不是扫源码字符串
# ─────────────────────────────────────────────────────────────
func _t_warp_shader() -> void:
	print("── ⑤ 空间扭曲(D: iOS 上一直没有) ──")
	var ts = _s._timestop
	ts._ts_ensure_overlay()
	var mat: ShaderMaterial = ts._ts_rect.material if is_instance_valid(ts._ts_rect) else null
	_ok("⑤ ★分母: 真函数造出了带 shader 的材质", mat != null and mat.shader != null)
	if mat == null or mat.shader == null:
		return
	var code: String = mat.shader.code
	var i: int = code.find("void fragment(){")
	var body: String = code.substr(i) if i >= 0 else ""
	_ok("⑤ ★分母: 取到了 fragment 体", body.length() > 200, "fragment 体 %d 字符" % body.length())
	# D 的形状就是「uniform 声明了, fragment 里一次都没用」—— 所以必须量 fragment 体内的使用次数。
	# ★`warp` 要**减掉 `warp_r` 里那半截**: 直接 count("warp") 会把 `warp_r` 也数进去,
	#   于是把 `* warp *` 整个删掉(正是 D 的形状)它还剩 1 次 ⇒ 判据宽一格就放过了真 bug。
	var warp_alone: int = body.count("warp") - body.count("warp_r")
	_ok("⑤ fragment 里真的用到了 warp 本身(不含 warp_r)", warp_alone >= 1,
		"warp 独立出现 %d 次(warp 总 %d - warp_r %d)" % [warp_alone, body.count("warp"), body.count("warp_r")])
	for k in ["warp_r", "zoom_blur"]:
		_ok("⑤ fragment 里真的用到了 %s" % k, body.count(k) >= 1,
			"%s 在 fragment 体里出现 %d 次" % [k, body.count(k)])
	_ok("⑤ 不再靠读屏(hint_screen_texture 在 gl_compatibility 移动端会整屏黑)",
		not code.contains("hint_screen_texture"))
	_ok("⑤ 世界纹理喂进去了(null 的话画面会全黑)",
		mat.get_shader_parameter("world_tex") != null,
		"world_tex=%s" % str(mat.get_shader_parameter("world_tex")))
