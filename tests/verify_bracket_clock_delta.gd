extends Node
## verify_bracket_clock_delta.gd —— 对阵图倒计时/购物窗只用【本机时钟的时间差】(2026-10-11 全项目通读·赛制第 6 条)
##
## ★读码发现: `recv_at` 记的是收包那一刻的**原始系统钟**, 而对阵图传进 `finals_left_of` / `finals_shop_*_of`
##   的「现在」是 `_clock()` = 原始钟 + 服务器偏移(或时间穿越偏移) ⇒ 时间差里多出一整个偏移:
##   手机钟偏 10 分钟 ⇒ 倒计时差 10 分钟、购物窗早关/晚关; 时间穿越时倒计时恒 0。
## ★判据: ① 在有服务器偏移时, 用「原始钟」算的剩余秒 = 服务端给的剩余秒(没过多久); 用「纠正后的钟」算就错了(分母)
##   ② 对阵图两处调用都传 `_delta_now()`(原始钟), 不再传 `_clock()`。

const SB := preload("res://scripts/net/supabase.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 对阵图时间差只用本机钟 ===")
	var raw: int = int(Time.get_unix_time_from_system())
	var v := {"left": 300, "recv_at": raw, "srv_now": raw + 600, "round_at": raw + 600 - 60}
	var keep_off: int = P2.server_offset_sec
	var keep_known: bool = P2.server_offset_known
	P2.server_offset()
	P2.server_offset_sec = 600
	P2.server_offset_known = true
	var wrong: int = SB.finals_left_of(v, P2.now_utc())
	var right: int = SB.finals_left_of(v, raw)
	_ok("★分母: 有 600 秒服务器偏移时, 拿纠正后的钟算会错(剩 %d 秒而不是 300)" % wrong, wrong != 300, "%d" % wrong)
	_ok("★用原始钟算 = 300(刚收到包, 没过时间)", right == 300, "%d" % right)
	P2.server_offset_sec = keep_off
	P2.server_offset_known = keep_known

	var src := FileAccess.get_file_as_string("res://scripts/scenes/BracketMapScene.gd")
	var bad := 0
	var good := 0
	for line in src.split(String.chr(10)):
		if line.contains("_SB.finals_left_of(") or line.contains("_SB.finals_shop_open_of(") or line.contains("_SB.finals_shop_left_of("):
			if line.contains("_clock()") or line.contains("now_l"):
				bad += 1
			if line.contains("_delta_now()"):
				good += 1
	_ok("★★对阵图: 倒计时/购物窗的三个调用都传 _delta_now()(原始钟), 不传 _clock()", bad == 0 and good >= 2,
		"传 _clock/now_l 的 %d 处, 传 _delta_now 的 %d 处" % [bad, good])

	# ── 同一条的另一半: 「拿不到对手」的原因不许在同一帧被倒计时盖掉 ──
	##   两句共用 `_tip`; 每拍先写对手原因、拍尾 `_sync_tip()` 又无条件写倒计时 ⇒ 玩家永远看不到原因。
	var MAP = load("res://scripts/scenes/BracketMapScene.gd")
	var m = MAP.new()
	m._injected = true
	m._tip = Label.new()
	m._tip.text = "这一轮的对手你已经看过了"
	m.set("_opp_tip_text", "这一轮的对手你已经看过了")
	m._bucket = {"left": 300, "recv_at": raw, "size": 2, "round": 1, "me": 0}
	m._now_override = raw
	m._sync_tip()
	_ok("★★对手原因在屏上时, 倒计时不盖掉它", str(m._tip.text) == "这一轮的对手你已经看过了", str(m._tip.text))
	m._tip.free()
	m.free()

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
