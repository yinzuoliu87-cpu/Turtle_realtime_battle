extends Node
## verify_bracket_not_seated.gd — 周日分组之前不许对晋级者说「人太少、下周再来」(2026-10-04 周日实操)
## 现象: 06:52 UTC 6 个晋级号进对阵图, 全部看到「本周只有 6 人晋级 · 人太少, 决赛日没开起来; 你的晋级算数, 下周再来」。
## 根因: 服务端 finals_view 对「报了名但还没分组」一律回 too_few, 不看现在是不是还没到 08:00 UTC 分组。
## ★走真函数: BracketMapScene._empty_text(), 注入服务端那份回包 + 时钟。

const MAP := preload("res://scripts/scenes/BracketMapScene.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _say(ts: int) -> String:
	var m = MAP.new()
	m._injected = true
	m._bucket = {"reason": "too_few", "entered": 6}
	m._now_override = ts
	var s := str(m._empty_text())
	m.free()
	return s


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周日分组前不劝退 ===")
	var sun0: int = P2.week_anchor_utc(int(Time.get_unix_time_from_system())) + 6 * 86400
	var before := _say(sun0 + 7 * 3600)             # 07:00 UTC
	_ok("★★分组前(07:00 UTC)不说「人太少/下周再来」", before.find("下周再来") < 0 and before.find("人太少") < 0, before)
	_ok("★★分组前说清什么时候开打", before.find("还没分组") >= 0 and before.find(P2.local_hhmm(sun0 + P2.FINALS_SEAT_HOUR_UTC * 3600)) >= 0, before)
	var m = MAP.new()
	m._injected = true
	m._bucket = {"reason": "not_seated", "entered": 6}
	m._now_override = sun0 + 10 * 3600            # 就算时钟已过分组点, 服务端说没分组就是没分组
	var ns := str(m._empty_text())
	m.free()
	_ok("★★服务端回 not_seated ⇒ 说「还没分组」", ns.find("还没分组") >= 0 and ns.find("下周再来") < 0, ns)
	var SBn = load("res://scripts/net/supabase.gd")
	var pv: Dictionary = SBn.parse_finals(true, 200, '{"ok":false,"reason":"not_seated","entered":6}', "uid-me", 1)
	_ok("★★回包解析把 not_seated 带出来(不吞成空字典)", str(pv.get("reason", "")) == "not_seated" and int(pv.get("entered", 0)) == 6, str(pv))
	var after := _say(sun0 + 10 * 3600)             # 10:00 UTC, 分组早就跑过了
	_ok("★分母: 分组之后真没开起来时仍然说「人太少」", after.find("人太少") >= 0, after)
	## ★2026-10-04 用户拍板「改成『8 分 43 秒后』」: 原来 `8:43` 读起来像钟点。
	_ok("倒计时 523 秒 ⇒ 「8 分 43 秒」", MAP.countdown_text(523) == "8 分 43 秒", MAP.countdown_text(523))
	_ok("不足 1 分钟只写秒", MAP.countdown_text(43) == "43 秒", MAP.countdown_text(43))
	var _sh := str(MAP.shop_tip(true, 523, true))
	_ok("★备战购物那一行也不再是 m:ss", _sh.find(":") < 0 and _sh.find("8 分 43 秒") >= 0, _sh)
	var _src := FileAccess.get_file_as_string("res://scripts/scenes/BracketMapScene.gd")
	var _i0 := _src.find("func _sync_tip")
	var _i1 := _src.find("\nfunc ", _i0 + 10)
	var _body := _src.substr(_i0, (_i1 if _i1 > 0 else _src.length()) - _i0)
	_ok("★分母: 找到 _sync_tip", _i0 >= 0 and _body.length() > 50)
	_ok("★★对阵图顶上那行走 countdown_text, 不再拼 %d:%02d", _body.find("countdown_text(") >= 0 and _body.find("%d:%02d") < 0)
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 分组前不劝退" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
