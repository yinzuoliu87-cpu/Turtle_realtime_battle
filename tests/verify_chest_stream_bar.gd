extends Node
## verify_chest_stream_bar.gd —— 宝箱龟「财宝」进度条在看直播时也画出来(2026-11-20)。
## 用户 11-20(看了调试场截图里的「财宝 已开 0/5，下一箱：第 1 箱」):「这个描述是？而且我在玩的时候没看到进度条啊」。
##   查实: info_panel 在播状态流(ReplayRecorder.mode == "stream")时整条不画 —— 本场宝箱账挂在 ChestSystem 上、
##   不在单位字典里, 流里没有财宝值; 而积分赛 / 周末 11-03 起全是看服务器直播 ⇒ 玩家从来看不到这条。
## 改法: 服务器算的那一端每步把账镜像到单位上(chest_system `_chest_value` / `_chest_open_n`), 录流器 UKEYS_INFO 带上,
##   面板播流时读它们(`InfoPanel.chest_progress`); 旧裁判机不发 ⇒ 照旧不画。结论句改成「攒满开第 N 箱（共 5 箱）」。
## 判据:
##   ① 本机跑: 进账后 tick 一次, 单位身上的镜像 == 本场宝箱账(值 / 已开数)
##   ② 录流器真的发这两个字段
##   ③ 本机面板: 财宝条 当前 / 下一箱阈值 / 新结论句
##   ④ 播流 + 流里带了: 面板按流里的值画(已开 1 ⇒ 分母第 2 箱阈值、结论句第 2 箱)
##   ⑤ 播流 + 流里没带(旧裁判机): 不画(不许拿空账的 0 冒充)
## 反向验证(11-20): 去掉 tick 里的镜像 ⇒ ① 红; 名单去掉两个字段 ⇒ ② 红; 面板播流仍不画 ⇒ ④ 红。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SR := preload("res://scripts/systems/stream/stream_recorder.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if cond else "FAIL", name, detail])


func _bar(s, u: Dictionary) -> Dictionary:
	for r in s._info_sys._resource_bars(u):
		if str((r as Dictionary).get("name", "")) == "财宝":
			return r
	return {}


func _ready() -> void:
	OS.set_environment("SHIP", "1")          # 走两侧宝箱账(真对局那条路), 不走评审台的单位自算
	await get_tree().process_frame
	print("=== 宝箱龟财宝条: 看直播也画 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._units.clear()
	s._edit_mode = false
	s._over = false
	s.set_process(false)
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var th: Array = s._CHEST_THRESH

	## ── ① 本机: 镜像 == 账 ──
	var u: Dictionary = s._spawn._make_unit("chest", "left", c)
	s._units.append(u)
	_ok("分母: 走的是两侧宝箱账(不是单位自算)", not s._chest_sys._per_unit(u))
	s._chest_sys.note_damage(u, 1234)
	s._chest_sys._chest_treasure_tick(u)
	var tp: Dictionary = s._chest_sys.treasure_progress(u)
	_ok("分母: 账上进了 1234", is_equal_approx(float(tp["value"]), 1234.0), str(tp))
	_ok("① tick 后单位身上的镜像 == 账(值 / 已开数)",
		u.has("_chest_value") and is_equal_approx(float(u.get("_chest_value", -1.0)), float(tp["value"]))
			and int(u.get("_chest_open_n", -1)) == int(tp["opened"]),
		"镜像 %s / %s" % [str(u.get("_chest_value", "无")), str(u.get("_chest_open_n", "无"))])

	## ── ② 录流器名单 ──
	_ok("② 录流器发 _chest_value / _chest_open_n", SR.UKEYS_INFO.has("_chest_value") and SR.UKEYS_INFO.has("_chest_open_n"))

	## ── ③ 本机面板 ──
	var b0: Dictionary = _bar(s, u)
	_ok("③ 本机面板有财宝条: 1234 / 第 1 箱阈值", not b0.is_empty() and int(b0.get("cur", -1)) == 1234
		and is_equal_approx(float(b0.get("cap", -1.0)), float(th[0])), str(b0))
	_ok("③ 结论句「攒满开第 1 箱（共 %d 箱）」" % th.size(), str(b0.get("hint", "")) == "攒满开第 1 箱（共 %d 箱）" % th.size(),
		str(b0.get("hint", "")))

	## ── ④⑤ 播流 ──
	var mode0: String = str(s._replay.mode)
	s._replay.mode = "stream"
	var v: Dictionary = s._spawn._make_unit("chest", "right", c)
	v["_chest_value"] = 4200.0
	v["_chest_open_n"] = 1
	var b1: Dictionary = _bar(s, v)
	_ok("④ 播流 + 流里带了: 按流里的值画(4200 / 第 2 箱阈值)", not b1.is_empty() and int(b1.get("cur", -1)) == 4200
		and is_equal_approx(float(b1.get("cap", -1.0)), float(th[1])), str(b1))
	_ok("④ 结论句跟着已开数走「攒满开第 2 箱」", str(b1.get("hint", "")).begins_with("攒满开第 2 箱"), str(b1.get("hint", "")))
	var w: Dictionary = s._spawn._make_unit("chest", "right", c)
	_ok("⑤ 播流 + 流里没带(旧裁判机): 不画", _bar(s, w).is_empty(), str(_bar(s, w)))
	s._replay.mode = mode0

	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fail == 0 and _n >= 9 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
