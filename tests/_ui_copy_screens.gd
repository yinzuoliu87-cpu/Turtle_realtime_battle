extends RefCounted
## _ui_copy_screens.gd —— 全游戏「玩家看得见的字」走查用的屏清单(2026-11-01 · 方案书 docs/plans/20261101f-全游戏文案按商业口吻.md)。
## 门禁 `verify_ui_copy.gd` 与走查台 `_shot_ui_copy.gd` 共用这一份(同一屏、同一种状态、同一把版面尺), 不是测试本身。
## 用户 2026-11-01:「切记你的所有语句，一定要按照商业游戏的口吻去来，一定要按照规则来，不要乱乱用这种语句。」
##
## 每一屏 = 名字 → 场景 + 时刻 + 存档状态(+ 实例化后的一步操作, 如打开弹窗 / 切页签)。
## ★决赛日(周日 17:30 起的对阵图 / 主菜单决赛日卡)不在这里: 那一路由 verify_finals_copy 逐句扫。
## ★不连任何服务器: 账号那几屏只在进程里把后端「配上」(假地址, 与 _shot_settings / verify_ios_ui 同一做法), 一个请求都不发出去。

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SB := preload("res://scripts/net/supabase.gd")
const ACCT_DEL := preload("res://scripts/scenes/settings/account_delete_dialog.gd")

const MON := 1789344000                  # 2026-09-14 周一 00:00 UTC(与决赛日门禁同一周)
const D := 86400
const H := 3600

## 改动过的存档字段(门禁跑完逐个还原)
const KEYS := ["promoted", "season_wins", "gauntlet_wins", "gauntlet_losses", "season_total_battles", "test_mode", "hearts",
	"nickname", "first_tips_seen", "onboarded", "ranked_used", "season_leaders", "coins", "tutorial_active", "account_id",
	"account_email"]

## [名字, 场景, 时刻(相对本周一), 状态]
const SCREENS := [
	["menu_tue", "MainMenu", D + 10 * H, "ranked"],
	["menu_tue_dead", "MainMenu", D + 10 * H, "dead"],
	["menu_mon", "MainMenu", 10 * H, "ranked"],
	["menu_fri_lock", "MainMenu", 4 * D + 22 * H + 55 * 60, "ranked"],
	["menu_sat_run", "MainMenu", 5 * D + 12 * H, "sat_run"],
	["menu_sat_in", "MainMenu", 5 * D + 12 * H, "sat_in"],
	["menu_sat_out", "MainMenu", 5 * D + 12 * H, "sat_out"],
	["menu_sat_plain", "MainMenu", 5 * D + 12 * H, "plain"],
	["teamselect", "TeamSelect", D + 10 * H, "ranked"],
	["shop", "Shop", D + 10 * H, "ranked"],
	["inventory", "Inventory", D + 10 * H, "ranked"],
	["codex", "Codex", D + 10 * H, "ranked"],
	["codex_equip", "Codex", D + 10 * H, "ranked"],
	["codex_synergy", "Codex", D + 10 * H, "ranked"],
	["codex_status", "Codex", D + 10 * H, "ranked"],
	["leaderboard", "Leaderboard", D + 10 * H, "ranked"],
	["friends", "Friends", D + 10 * H, "ranked"],
	["record", "Record", D + 10 * H, "ranked"],
	["gauntletboard", "GauntletBoard", 5 * D + 12 * H, "sat_run"],
	["trainerconfig", "TrainerConfig", D + 10 * H, "ranked"],
	["firstlaunch", "FirstLaunch", D + 10 * H, "fresh"],
	["settings", "Settings", D + 10 * H, "ranked"],
	["settings_unbound", "Settings", D + 10 * H, "acct_unbound"],
	["settings_bound", "Settings", D + 10 * H, "acct_bound"],
	["settings_conflict", "Settings", D + 10 * H, "acct_conflict"],
	["settings_delete", "Settings", D + 10 * H, "acct_bound"],
]

static var _key0 = null


static func names() -> Array:
	var out: Array = []
	for s in SCREENS:
		out.append(str(s[0]))
	return out


static func spec(name: String) -> Array:
	for s in SCREENS:
		if str(s[0]) == name:
			return s
	return []


static func ts_of(name: String) -> int:
	return MON + int(spec(name)[2])


static func _gs():
	return (Engine.get_main_loop() as SceneTree).root.get_node("/root/GameState")


## 存档状态。
static func setup(name: String) -> void:
	var st := str(spec(name)[3])
	var gs = _gs()
	gs.test_mode = true
	gs.tutorial_active = false
	gs.hearts = int(P2.HEARTS_MAX)
	gs.season_total_battles = 7
	gs.ranked_used = 7
	gs.nickname = "吃货一枚"
	gs.onboarded = st != "fresh"
	gs.first_tips_seen = {} if st == "fresh" else {"finals_day": true, "gauntlet_day": true, "start_battle": true,
		"first_week": true}
	gs.season_leaders = ["ninja", "stone", "basic"]
	gs.coins = 120
	gs.promoted = st in ["sat_run", "sat_in", "sat_out"]
	gs.season_wins = int(P2.PROMOTE_WINS) if gs.promoted else 4
	gs.gauntlet_wins = 0
	gs.gauntlet_losses = 0
	match st:
		"dead":
			gs.hearts = 0
		"sat_run":
			gs.gauntlet_wins = 2
			gs.gauntlet_losses = 1
		"sat_in":
			gs.gauntlet_wins = int(P2.GAUNTLET_WINS_IN)
			gs.gauntlet_losses = 1
		"sat_out":
			gs.gauntlet_wins = 1
			gs.gauntlet_losses = int(P2.GAUNTLET_LOSSES_OUT)
		"fresh":
			gs.season_total_battles = 0
			gs.ranked_used = 0
			gs.nickname = ""
	_backend(st.begins_with("acct_"), st)


## 账号几屏: 进程里把后端配上(假地址, 不发请求); 其余屏一律拆掉(与门禁默认环境一致)。
static func _backend(on: bool, st: String) -> void:
	var gs = _gs()
	if _key0 == null:
		_key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	SB._session_lost = false
	## 存档冲突是进程级状态: 「设置·冲突」那屏造出来之后, 后面每一屏(含另一比例的主菜单)都会挂着冲突提示 ⇒ 每屏重置
	SB._save_conflict_rev = -1
	if on:
		OS.set_environment(SB.ENV_URL, "https://example.invalid")
		ProjectSettings.set_setting(SB.SETTING_KEY, "sb_publishable_forshot")
		gs.account_id = "ae08e589-1111-2222-3333-444455556666"
		gs.account_email = "" if st == "acct_unbound" else "lisa.chen@example.com"
		if st == "acct_conflict":
			SB.apply_push_response(true, 200, '{"ok": false, "reason": "conflict", "rev": 7}', "")
	else:
		OS.set_environment(SB.ENV_URL, " ")
		ProjectSettings.set_setting(SB.SETTING_KEY, _key0)
		gs.account_id = ""
		gs.account_email = ""


## 收尾: 拆掉后端(门禁 / 走查台跑完调)。
static func teardown() -> void:
	_backend(false, "")
	P2.now_override_ts = 0


static func make(name: String) -> Node:
	var sp := spec(name)
	P2.now_override_ts = ts_of(name)
	StudioIntro.played = true
	var n: Node = (load("res://scenes/%s.tscn" % str(sp[1])) as PackedScene).instantiate()
	if n.get("clock_override_ts") != null:
		n.set("clock_override_ts", ts_of(name))
	return n


## 实例化之后的一步(打开弹窗 / 切页签)。
static func post(name: String, n: Node) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	match name:
		## ★页签 id 是 CodexScene.TABS 里那个(equips / synergies) —— 原来写成 equip / synergy, 图鉴照单清空列表、
		##   一行都不加 ⇒ 这两屏一直拍的是空列表, 文案门禁在这两页是空跑(2026-11-01 实拍才看出来)。
		"codex_equip":
			n._switch_tab("equips")
		"codex_synergy":
			n._switch_tab("synergies")
		"codex_status":
			n._switch_tab("status")
		"settings_delete":
			modal = ACCT_DEL.open(n as Control, "lisa.chen@example.com", func() -> void: pass)
	await tree.process_frame


## 这一屏开着的弹窗(没有 = null)。弹窗盖住的页面字不和弹窗里的字比重叠(被压暗遮住, 本来就在下面)。
static var modal: Node = null


## 版面比重叠时只看哪一棵子树里的字("" = 整屏)。
static func overlap_scope() -> String:
	if modal != null and is_instance_valid(modal) and modal.is_inside_tree():
		return str(modal.get_path())
	return ""


## 等入场动画落位: tween 走的是真实时间(不受帧数影响), 无头一帧 ~1 毫秒 ⇒ 按墙钟等, 不按帧数等
##   (主菜单左栏键延迟 0.5+0.08i 秒 + 0.42 秒行程才落位; 按 60 帧等量到的是滑到一半的坐标)。
static func settle(sec: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await tree.process_frame


## 拿掉一屏。
static func drop(n: Node) -> void:
	modal = null
	if n != null and is_instance_valid(n):
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()


# ══════════════════════════════ 版面尺(无头也量得到) ══════════════════════════════

## ① 开了 clip_text 的 Label 字宽 > 框宽(被截); ② 字出了屏; ③ 两句字互相压住(按**字本身占的范围**算, 不按控件框)。
static func layout_issues(root: Node, items: Array, vp: Rect2) -> Array:
	var out: Array = []
	_clipped(root, out)
	var ext: Array = []
	for it in items:
		ext.append(text_extent(it))
	for i in range(items.size()):
		var r: Rect2 = ext[i]
		if r.position.x < vp.position.x - 2 or r.end.x > vp.end.x + 2 or r.position.y < vp.position.y - 2 or r.end.y > vp.end.y + 2:
			out.append("出屏 %s「%s」" % [str(items[i]["path"]).get_file(), _one(str(items[i]["text"]))])
	var scope := overlap_scope()
	for i in range(items.size()):
		for j in range(i + 1, items.size()):
			var pa := str(items[i]["path"])
			var pb := str(items[j]["path"])
			if pa.begins_with(pb) or pb.begins_with(pa):
				continue
			if scope != "" and not (pa.begins_with(scope) and pb.begins_with(scope)):
				continue
			## RichTextLabel: 只有 fit_content 的才进比对 —— 它的框跟着内容走(进树即按内容定高), 框就是字占的范围;
			##   不撑高的那种框是外面给的, 量不出字到哪 ⇒ 仍跳过(字照样过文案判据)。
			## ★2026-11-01 之前一律跳过 ⇒ 图鉴状态页「两行说明压住『来源』」量到了两个矩形却没报(实拍才看出来)。
			if not (_rtl_measurable(items[i]) and _rtl_measurable(items[j])):
				continue
			var ov := (ext[i] as Rect2).intersection(ext[j] as Rect2)
			if ov.size.x > 1.5 and ov.size.y > 1.5:   # 窄字形(「i」只有 3px 宽)也要算
				out.append("重叠 「%s」×「%s」" % [_one(str(items[i]["text"])).left(30), _one(str(items[j]["text"])).left(30)])
	return out


## 一句字能不能拿框比重叠: Label / Button 恒能(text_extent 量字形); RichTextLabel 只有 fit_content 的能。
static func _rtl_measurable(it: Dictionary) -> bool:
	if str(it["cls"]) != "RichTextLabel":
		return true
	var c = (Engine.get_main_loop() as SceneTree).root.get_node_or_null(NodePath(str(it["path"])))
	return c is RichTextLabel and (c as RichTextLabel).fit_content


## 一句字在屏上真正占的矩形(Label / Button: 量字宽 + 字号高 + 对齐; RichTextLabel: 内容宽高; 其余: 控件框)。
## ★一律夹在控件框里: 量的是「字和字有没有压住」, 不是行距留白(字体的行高比字形高, 拿行高量会把上下贴着的两行全判成重叠)。
static func text_extent(it: Dictionary) -> Rect2:
	var r: Rect2 = it["rect"]
	var c = (Engine.get_main_loop() as SceneTree).root.get_node_or_null(NodePath(str(it["path"])))
	if c == null:
		return r
	var ctl := c as Control
	var sx := r.size.x / maxf(1.0, ctl.size.x)
	var sy := r.size.y / maxf(1.0, ctl.size.y)
	if not (c is Label or c is Button):
		return r
	var txt := str(it["text"])
	var fnt: Font = ctl.get_theme_font("font")
	var fs: int = ctl.get_theme_font_size("font_size")
	if c is Label and (c as Label).label_settings != null:
		var ls := (c as Label).label_settings
		if ls.font != null:
			fnt = ls.font
		fs = ls.font_size
	if fnt == null:
		return r
	var lines := txt.split("\n")
	var w := 0.0
	for ln in lines:
		w = maxf(w, fnt.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var h := float(fs) * float(lines.size()) + 4.0 * float(lines.size() - 1)
	if c is Label and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
		## 自动换行: 宽 = 框宽, 高 = 实际行数 × 行高(框可能被最小尺寸撑得很高, 字只占上面几行)
		w = ctl.size.x
		h = float((c as Label).get_line_count()) * float((c as Label).get_line_height())
	w = minf(w * sx, r.size.x)
	h = minf(h * sy, r.size.y)
	var ha := HORIZONTAL_ALIGNMENT_CENTER
	var va := VERTICAL_ALIGNMENT_CENTER
	if c is Label:
		ha = (c as Label).horizontal_alignment
		va = (c as Label).vertical_alignment
	elif c is Button:
		ha = (c as Button).alignment
	var x := r.position.x
	if ha == HORIZONTAL_ALIGNMENT_CENTER:
		x = r.position.x + (r.size.x - w) * 0.5
	elif ha == HORIZONTAL_ALIGNMENT_RIGHT:
		x = r.end.x - w
	var y := r.position.y
	if va == VERTICAL_ALIGNMENT_CENTER:
		y = r.position.y + (r.size.y - h) * 0.5
	elif va == VERTICAL_ALIGNMENT_BOTTOM:
		y = r.end.y - h
	return Rect2(x, y, w, h)


static func _one(t: String) -> String:
	return t.replace("\n", "⏎")


static func _clipped(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label:
		var lb := n as Label
		if lb.text.strip_edges() != "" and lb.autowrap_mode == TextServer.AUTOWRAP_OFF and lb.clip_text \
				and lb.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			var fnt := lb.get_theme_font("font")
			var fs := lb.get_theme_font_size("font_size")
			var w := 0.0
			for line in lb.text.split("\n"):
				w = maxf(w, fnt.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
			if w > lb.size.x + 2.0:
				out.append("被截 %s 字宽 %d > 框宽 %d「%s」" % [lb.name, int(w), int(lb.size.x), _one(lb.text)])
	for c in n.get_children():
		_clipped(c, out)
