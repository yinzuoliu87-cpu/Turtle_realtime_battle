extends Node
## verify_finals_day_recap.gd — 周日收盘补看(方案书 docs/plans/20261031c-周日赛事界面重做.md 块 M ⑧ · G21 / 7-3 / C-7 / 5-6)
##
## 由来: 彩排里冠军杯赛决出时不在场的人, 下次打开主菜单什么都看不到(冠军是谁 / 我第几 / 我的几场)。
##   商业游戏(Township 回来先快进那一刻 / CSR2 完成 → 最终排名 → 领奖连播 / Duel Links「结果已出」)的共同做法:
##   没守到最后的人下次打开先补那一刻 —— 冠军 → 最终名次(前三 + 你排第几)→ 我的几轮(可重看); 只弹一次。
##   改法: scripts/ui/finals_day_recap.gd(主菜单开屏 `MenuFinalsDay.start` → `maybe_show`)。
##
## ① 窗口: 周日冠军杯赛开赛(FINALS_START_HOUR_UTC)之后补本周、周一补上周; 开赛前 / 周二起不补。
## ② 冠军杯赛还没决出(决赛还在开播 = 结果已在服务端也不算)⇒ 不弹(不剧透)。
## ③ 全屏三拍(竞技场背景压暗 + 光束, 与冠军仪式一套): 冠军(奖杯砸下 + 头像放大进冠军框 +「冠军杯赛冠军」大字盖章 + 金缎带名字)
##    → 最终名次(领奖台 3 → 2 → 1 依次落下头像与名字 + 「你的名次」高亮、数字滚到位) → 我的比赛(每轮一张横条牌: 轮次 · 对手头像与名字 ·
##    比分滚动 · 胜 / 负章盖下 · 「重看」)。按时间算状态: 拨到某一刻量那一刻的样子; 点屏 = 先到这一拍终态, 终态再点 = 下一拍。
## ④ 「重看」⇒ 开那一场的回放、看完回主菜单; 「关闭」⇒ 收起。
## ⑤ 只弹一次(按周记在 user://); 没进决赛日的人只有两拍、没有「你的名次」。
## ⑥ ★不预告下一场比赛(用户 10-31「为什么在这儿提示新的比赛」): 三拍里一个字都不提下周 / 周二 / 周六 / 闯关赛 / 积分赛。
##
## 跑法: bash godot-quiet.sh res://tests/verify_finals_day_recap.tscn --quit-after 3000

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const M := preload("res://scripts/ui/finals_day_model.gd")
const F := preload("res://scripts/ui/finals_day_feed.gd")
const RC := preload("res://scripts/ui/finals_day_recap.gd")
const W := preload("res://scripts/ui/finals_day_watch.gd")
const FX := preload("res://tests/_finals_day_fixture.gd")

const MON := 1789344000
const SUN := MON + 6 * 86400
const H := 3600

var _n := 0
var _fail := 0
var fx
var host: Control


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  %s %s%s" % ["[PASS]" if cond else "[FAIL]", nm, ("   " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周日收盘补看: 冠军 → 名次 → 我的比赛 ===")
	GameState.test_mode = true
	fx = FX.new(MON)
	host = Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	_wipe()
	_t_window()
	await _t_flow()
	await _t_spectator()
	_wipe()
	F.override = {}
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _wipe() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RC.SEEN_PATH))


func _recap() -> Node:
	var r = host.get_node_or_null(RC.NODE_NAME)
	return r if r != null and not r.is_queued_for_deletion() else null


func _txt(root: Node, nm: String) -> String:
	var n := root.find_child(nm, true, false) if root != null else null
	return str((n as Label).text) if n is Label else "<无 %s>" % nm


# ───────────────────────────── ① ② ─────────────────────────────

func _t_window() -> void:
	print("--- ① 窗口 / ② 不剧透 ---")
	var cup := SUN + int(P2.FINALS_START_HOUR_UTC) * H
	for c in [["周日 冠军杯赛开赛前 1 小时", cup - H, 0], ["周日 冠军杯赛开赛后半小时", cup + 1800, MON], ["周日 23:00", SUN + 23 * H, MON],
			["周一 09:00", SUN + 86400 + 9 * H, MON], ["周二 09:00", SUN + 2 * 86400 + 9 * H, 0], ["周六 12:00", MON + 5 * 86400 + 12 * H, 0]]:
		_ok("① [%s] 补看窗口 = %s" % [c[0], "本周" if int(c[2]) > 0 else "不补"], RC.window_week(int(c[1])) == int(c[2]), str(RC.window_week(int(c[1]))))
	var final_slot: Array = fx.timeline(6, cup, {})[2]["slots"]["3-0"]
	var t_live: int = int(final_slot[0]) + 30
	F.override = fx.feeds(t_live)
	_ok("② ★分母: 决赛开播中, 服务端回包里决赛结果已经在 done 里", ((F.override["cup"] as Dictionary).get("done", {}) as Dictionary).has("3-0"))
	_ok("② ★决赛还在开播 ⇒ 不弹(结果没揭晓不算决出)", not RC.maybe_show(host, t_live) and _recap() == null)
	_ok("② 名次表此刻也是空的", M.standings(F.override["groups"], F.override["cup"], t_live).is_empty())


# ───────────────────────────── ③ ④ ⑤ ─────────────────────────────

func _node(rc: Node, nm: String) -> Node:
	return rc.find_child(nm, true, false) if rc != null else null


## 三拍里所有字(门禁扫「下一场比赛」那几个词)。
const NEXT_WORDS := ["下周", "周二", "周六", "闯关赛", "积分赛", "大轮"]
func _next_words(rc: Node) -> Array:
	var out: Array = []
	for l in rc.find_children("*", "Label", true, false):
		for w in NEXT_WORDS:
			if str((l as Label).text).find(w) >= 0:
				out.append(str((l as Label).text))
	return out


func _t_flow() -> void:
	print("--- ③ 三拍 / ④ 重看与关闭 / ⑤ 只弹一次 ---")
	fx.me_in = true
	var t := SUN + 21 * H + 1800
	F.override = fx.feeds(t)
	F.avatars[MON] = {"#T000": "basic", "#T201": "bamboo"}
	GameState.account_id = "acc-2-2"
	_ok("③ ★分母: 周日 21:30 没看过 ⇒ 弹", RC.maybe_show(host, t) and _recap() != null)
	var rc = _recap()
	if rc == null:
		return
	await get_tree().process_frame
	_ok("⑤ 一弹就记「看过了」", RC.seen(MON))
	_ok("③ 全屏: 竞技场背景(压暗)+ 光束层 + 白闪层, 整屏吃点击", _node(rc, "ArenaBg") != null and (_node(rc, "ArenaBg") as CanvasItem).modulate.r < 0.6
		and rc._fx != null and (rc._root as Control).mouse_filter == Control.MOUSE_FILTER_STOP
		and (rc._root as Control).size == get_viewport().get_visible_rect().size)
	## ── 第 1 拍: 拨到 0.3 秒(奖杯还在半空)/ 终态
	var tro := _node(rc, "RecapTrophy") as Control
	var cup_t := _node(rc, "RecapCupTitle") as Control
	var fr := _node(rc, "RecapChampFrame") as Control
	var rib := _node(rc, "RecapChampRibbon") as Control
	rc.t = 0.3
	rc._apply(0.3)
	var y_mid := tro.position.y
	var fr_mid := fr.scale.x
	var title_mid := cup_t.modulate.a
	rc.tap()
	_ok("③ ★第 1 拍 0.3 秒时: 奖杯还在半空、冠军框还没放大、大字还没盖下来", y_mid < tro.position.y - 100.0 and fr_mid < 0.2 and title_mid < 0.1,
		"奖杯 y %.0f → %.0f · 框 %.2f · 大字 %.2f" % [y_mid, tro.position.y, fr_mid, title_mid])
	_ok("③ ★点屏 ⇒ 先跳到这一拍终态(还是第 1 拍): 奖杯落地、框放大到 1、大字盖到 1 倍、缎带展开", int(rc.beat) == 0
		and absf(fr.scale.x - 1.0) < 0.01 and absf(cup_t.scale.x - 1.0) < 0.01 and cup_t.modulate.a > 0.99 and absf(rib.scale.x - 1.0) < 0.01)
	_ok("③ 第 1 拍内容: 「冠军杯赛冠军」像素大字 + 奖杯 + 冠军头像(他的真头像)+ 金缎带写「小辉同学」+ 规模一行",
		cup_t != null and str((cup_t as TextureRect).texture.resource_path).ends_with("bt-cup-champ.png")
		and str((_node(rc, "RecapChampFace") as TextureRect).texture.resource_path).ends_with("basic.png")
		and str((rib.get_node("Text") as Label).text) == "小辉同学" and _txt(rc, "RecapScale") == "本周决赛日 24 人参赛，分为 6 组",
		"%s / %s" % [str((rib.get_node("Text") as Label).text), _txt(rc, "RecapScale")])
	var rl: Label = rib.get_node("Text")
	_ok("③ 缎带字读得清: 浅字 + 近黑描边(描边 ≥ 字号/3)、字号 ≥ 36", rl.get_theme_color("font_color").get_luminance() > 0.8
		and rl.get_theme_color("font_outline_color").get_luminance() < 0.1 and rl.get_theme_constant("outline_size") >= rl.get_theme_font_size("font_size") / 3
		and rl.get_theme_font_size("font_size") >= 36)
	var dots := 0
	for c in rc._root.get_children():
		if str(c.name).begins_with("RecapDot"):
			dots += 1
	_ok("③ 分页点 3 个(冠军 / 名次 / 我的比赛), 第 1 个亮", dots == 3 and (rc._root.get_node("RecapDot0") as ColorRect).color == RC.GOLD)
	## 前两拍自己往下走: 推到 4.5 秒
	for _i in range(46):
		rc._process(0.1)
	_ok("③ ★第 1 拍停够自己走到第 2 拍", int(rc.beat) == 1, str(rc.beat))
	## ── 第 2 拍: 领奖台
	rc.t = 0.5
	rc._apply(0.5)
	var p1 := _node(rc, "RecapP1_0") as Control
	var p3 := _node(rc, "RecapP3_0") as Control
	var p1_mid := p1.position.y
	var p3_mid := p3.position.y
	rc.tap()
	_ok("③ ★0.5 秒时第 3 名已在落、第 1 名还在天上; 点屏 ⇒ 都落到台上", p1_mid < p1.position.y - 150.0 and p3_mid < p3.position.y and int(rc.beat) == 1,
		"第 1 名 y %.0f → %.0f / 第 3 名 %.0f → %.0f" % [p1_mid, p1.position.y, p3_mid, p3.position.y])
	var pod := _node(rc, "RecapPodium") as Control
	_ok("③ 领奖台在场; 第 1 名站最高那块、第 2 名左、第 3 名右", pod != null and p1.position.y < (_node(rc, "RecapP2_0") as Control).position.y
		and (_node(rc, "RecapP2_0") as Control).position.x < p1.position.x and p3.position.x > p1.position.x)
	_ok("③ 第 2 拍: 第 1 名 小辉同学 / 第 2 名 头发多多 / 并列第 3 名 nana、吃货一枚(两人同站一块)",
		_txt(rc, "RecapRank1") == "小辉同学" and _txt(rc, "RecapRankT1") == "第 1 名" and _txt(rc, "RecapRank2") == "头发多多"
		and _txt(rc, "RecapRank3") == "nana、吃货一枚" and _txt(rc, "RecapRankT3") == "并列第 3 名" and _node(rc, "RecapP3_1") != null,
		"%s | %s | %s %s" % [_txt(rc, "RecapRank1"), _txt(rc, "RecapRank2"), _txt(rc, "RecapRankT3"), _txt(rc, "RecapRank3")])
	_ok("③ ★「你的名次：并列第 3 名」单独一行高亮(终态)", _txt(rc, "RecapYou") == "你的名次：并列第 3 名" and _node(rc, "RecapYouPlate") != null, _txt(rc, "RecapYou"))
	rc.t = 2.2
	rc._apply(2.2)
	var rolling := _txt(rc, "RecapYou")
	rc.t = 2.9
	rc._apply(2.9)
	_ok("③ ★名次数字是滚到位的(2.2 秒时还在滚: 「%s」)" % rolling, rolling != "你的名次：并列第 3 名" and rolling.begins_with("你的名次：并列第 ")
		and _txt(rc, "RecapYou") == "你的名次：并列第 3 名")
	## 点屏 = 下一拍(第 2 拍已是终态)
	rc.tap()
	await get_tree().process_frame
	_ok("③ ★终态再点 ⇒ 第 3 拍「我的比赛」", int(rc.beat) == 2 and _txt(rc, "RecapHead") == "我的比赛")
	rc.t = 0.2
	rc._apply(0.2)
	var row3 := _node(rc, "RecapRow3") as Control
	var row3_x := row3.position.x
	var st0 := (_node(row3, "RecapStamp") as Control).scale.x
	rc.tap()
	_ok("③ ★横条牌从右边依次滑进来、胜负章从大盖到 1 倍(点屏到终态)", row3_x > row3.position.x + 200.0 and st0 > 2.0
		and absf((_node(row3, "RecapStamp") as Control).scale.x - 1.0) < 0.01, "x %.0f → %.0f · 章 %.2f" % [row3_x, row3.position.x, st0])
	var rows: Array = []
	var res: Array = []
	var scores: Array = []
	for k in range(4):
		var rw := _node(rc, "RecapRow%d" % k)
		rows.append("%s %s" % [_txt(rw, "RecapMatch"), _txt(rw, "RecapOppName")])
		res.append("胜" if bool((_node(rw, "RecapStamp") as Node).get_meta("won")) else "负")
		scores.append(_txt(rw, "RecapScore"))
	var cg := ChampionData.group_name(FX.MY_GROUP)
	## ★2026-11-01 文案改写(方案书 20261101e, 用户「一定要按照商业游戏的口吻」): 「C 组 · 半决赛」→「C 组半决赛」/「冠军杯赛 1/4 决赛」(M.stage_line, 一个名词短语)
	var want := ["%s 对 Kiki" % M.stage_line(fx.my_group(SUN + 86400), 1), "%s 对 老王不在" % M.stage_line(fx.my_group(SUN + 86400), 2),
		"%s 对 Rex" % M.stage_line(fx.cup(SUN + 86400), 1), "%s 对 头发多多" % M.stage_line(fx.cup(SUN + 86400), 2)]
	_ok("③ 场次名是一个名词短语(「%s」, 没有「·」)" % str(want[2]), str(want[0]) == "%s半决赛 对 Kiki" % cg
		and str(want[2]) == "%s 1/4 决赛 对 Rex" % P2.STAGE_CUP)
	_ok("③ ★我打过的 4 场按先后、对手对、胜负章对(胜 胜 胜 负)", rows == want and res == ["胜", "胜", "胜", "负"] and _node(rc, "RecapRow4") == null,
		"%s %s" % [str(rows), str(res)])
	_ok("③ ★比分按我这一侧摆、来自服务端比分码(2:1 / 2:1 / 2:1 / 0:2)", scores == ["2 : 1", "2 : 1", "2 : 1", "0 : 2"], str(scores))
	_ok("③ 对手头像是他的真头像(Kiki = bamboo)", str(((_node(_node(rc, "RecapRow0"), "RecapOpp") as Control).get_node("Face") as TextureRect).texture.resource_path).ends_with("bamboo.png"))
	var rb := rc.find_children("RecapReplay", "Button", true, false)
	_ok("③ 每场一颗「重看」(卡片动作钮 card_button、触摸线 81)", rb.size() == 4 and (rb[0] as Button).custom_minimum_size.y >= 81.0
		and ((rb[0] as Button).get_theme_stylebox("normal") as StyleBoxFlat).bg_color == Color("#6a3f1c"))
	_ok("③ 最后一拍不再自己往下走、也不再显示「点击继续」", not rc._hint.visible)
	for _i in range(60):
		rc._process(0.1)
	_ok("③ 推 6 秒还停在第 3 拍", int(rc.beat) == 2)
	var vr := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var out_of := []
	for c in rc.find_children("*", "Control", true, false):
		var cc := c as Control
		if cc.is_visible_in_tree() and (cc is Button or str(cc.name).begins_with("RecapRow")) and not vr.encloses(cc.get_global_rect().grow(-1)):
			out_of.append(str(cc.name))
	_ok("③ 第 3 拍每张牌 / 每颗键都在屏内", out_of.is_empty(), str(out_of))
	W.last_ask = {}
	(rb[3] as Button).pressed.emit()
	_ok("④ ★「重看」⇒ 开那一场(冠军杯赛 2-1)的回放、看完回主菜单", str(W.last_ask.get("how", "")) == "replay"
		and int(W.last_ask.get("bucket", -1)) == int(P2.FINALS_CUP_BUCKET) and int(W.last_ask.get("round", 0)) == 2
		and str(W.last_ask.get("back", "")) == RC.MENU_SCENE, str(W.last_ask))
	_ok("⑥ ★三拍里一个字都不预告下一场比赛", _next_words(rc).is_empty(), str(_next_words(rc)))
	var cl := rc.find_child("RecapClose", true, false) as Button
	cl.pressed.emit()
	await get_tree().process_frame
	_ok("④ 「关闭」⇒ 收起", _recap() == null)
	_ok("⑤ ★同一周再开主菜单 ⇒ 不再弹", not RC.maybe_show(host, t + 600) and _recap() == null)
	_ok("⑤ 周一再开 ⇒ 也不弹(同一周)", not RC.maybe_show(host, SUN + 86400 + 9 * H) and _recap() == null)
	GameState.account_id = ""
	F.avatars.erase(MON)


func _t_spectator() -> void:
	print("--- ⑤ 没进决赛日的人 ---")
	_wipe()
	fx.me_in = false
	var t := SUN + 86400 + 9 * H                    # 周一早上(上周日没守到)
	F.override = fx.feeds(SUN + 22 * H)
	_ok("⑤ ★分母: 周一早上补上周", RC.maybe_show(host, t) and _recap() != null)
	var rc = _recap()
	if rc == null:
		return
	await get_tree().process_frame
	rc._go(1)
	rc.tap()
	await get_tree().process_frame
	_ok("⑤ 观众只有两拍: 第 2 拍就是最后一拍(有「关闭」、没有「点击继续」)", rc._last() == 1 and rc.find_child("RecapClose", true, false) != null
		and not rc._hint.visible)
	_ok("⑤ ★观众没有「你的名次」那一行", rc.find_child("RecapYou", true, false) == null and rc.find_child("RecapYouPlate", true, false) == null)
	_ok("⑥ ★观众这两拍也不预告下一场比赛", _next_words(rc).is_empty(), str(_next_words(rc)))
	rc._go(2)
	_ok("⑤ 走不到第 3 拍", int(rc.beat) == 1)
	rc.close()
	fx.me_in = true
