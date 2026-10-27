extends Node
## verify_card_buttons.gd — 卡片 / 弹框里不许用木牌按钮(2026-10-23)
##
## 由来: 用户 2026-10-22「为什么还在用这个木头按钮？我说了无数遍啊」—— 商店 / 背包当时改成了 `UISkin.card_button`
##   (深棕底 + 黄铜细边, 与「购买」同一种), 但教程选择框、首启起名框、设置页三个弹框、结算屏、回放操作条
##   还在用 `UISkin.button()`(大尺寸就是带铆钉的木牌 `menu/frame-rect.png`)。2026-10-23 一次改完 14 处。
## ★2026-10-27 改正(docs/plans/20261027-UI美术规矩.md §4.6-6): 用户 10-22 那句说的是商店 / 背包的弹出层与操作条,
##   主会话把它扩到了「所有操作条」, 回放操作条因此套成三颗棕底文字大框。用户 10-27 问「回放也要用这个大的这个框框按钮吗？」
##   ⇒ **叠在战斗画面上的控制键**(回放 / 观战 / 排队等待)用为这几屏新画的小方形像素图标键(PixelKey), 不用 card_button
##   也不用木牌; 回放的「退出确认框」属于弹框, 框里的按钮仍是 card_button(下面 CONVERTED 那一条量的就是它)。
## 判据:
##   ① 全仓 `UISkin.button(` 调用点只许出现在登记过理由的文件里, 且每个文件的处数与登记一致
##      (新写一个弹框顺手用了 `UISkin.button` ⇒ 这里红; 真要用就来这里写理由)
##   ② 改过的那几个文件里真有 `UISkin.card_button(`(分母: 改动真的落地了)
##   ③ 实建: 教程选择框两颗按钮 / 结算屏主按钮的皮 = card_button 的 StyleBoxFlat, 不是贴图框
##   ④ 叠在画面上的控制键: 回放条 / 观赛退出 / 排队取消都走 PixelKey(新画的键底座), 那几处不调 card_button
##      (运行时的皮逐字节量在 verify_replay_controls ⑨ 与 verify_replay_queue_art)
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_card_buttons.tscn

const SettleScreenS := preload("res://scripts/scenes/battle/settle_screen.gd")

## 还允许用 `UISkin.button` 的地方: 文件 → [处数, 理由]
const ALLOW := {
	"res://scripts/scenes/FirstLaunchScene.gd": [1, "首启右上「跳过」: 整屏角钮, 不在卡片里"],
	"res://scripts/scenes/tutorial_chrome.gd": [1, "教程右上「跳过教程」: 整屏角钮(金属签牌)"],
	"res://scripts/scenes/battle/dmg_stats_panel.gd": [2, "战中「战报」浮层的页签与 ×: 金属小签牌(战斗界面那套冷色金属), 不是木牌"],
	"res://scripts/scenes/settings/time_travel_panel.gd": [2, "调试面板, 只在开发包里有"],
}
## 改成 card_button 的文件 → 至少几处
const CONVERTED := {
	"res://scripts/scenes/tutorial_choice.gd": 2,
	"res://scripts/scenes/FirstLaunchScene.gd": 2,
	"res://scripts/scenes/SettingsScene.gd": 6,
	"res://scripts/scenes/battle/settle_screen.gd": 2,
	"res://scripts/scenes/battle/replay_controls.gd": 1,     # 回放「退出确认框」里的两颗按钮(弹框); 操作条的键见 ④
}
## ④ 叠在画面上的控制键: 文件 → 必须出现的 PixelKey 建键调用(且这几行不许调 card_button / button)
const OVERLAY_KEYS := {
	"res://scripts/scenes/battle/replay_controls.gd": ["_key(N_EXIT,", "_key(N_SPEED,", "_key(N_PAUSE,", "_key(N_LIVE_EXIT,",
		"PixelKey.icon_key("],
	"res://scripts/scenes/queue_wait_view.gd": ["PixelKey.skin(bt, KEY_RED, KEY_RED_DOWN"],
}

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	print("=== 卡片 / 弹框 / 操作条里不许用木牌按钮 ===")
	var calls := {}
	var cards := {}
	var files: Array = _gd_files("res://scripts") + _gd_files("res://autoload")
	for f in files:
		for line in FileAccess.get_file_as_string(f).split("\n"):
			var t := line.strip_edges()
			if t.begins_with("#"):
				continue
			if t.find("UISkin.button(") >= 0:
				calls[f] = int(calls.get(f, 0)) + 1
			if t.find("UISkin.card_button(") >= 0:
				cards[f] = int(cards.get(f, 0)) + 1
	_ok("① 分母: 扫了 %d 个 .gd" % files.size(), files.size() >= 100, str(files.size()))
	var bad: Array = []
	for f in calls:
		if not ALLOW.has(f):
			bad.append("%s ×%d(没登记理由)" % [f, calls[f]])
		elif int(calls[f]) != int(ALLOW[f][0]):
			bad.append("%s ×%d(登记的是 %d 处)" % [f, calls[f], ALLOW[f][0]])
	_ok("★★① `UISkin.button(` 只出现在登记过理由的整屏角钮 / 战斗浮层 / 调试面板里", bad.is_empty(), str(bad))
	var gone: Array = []
	for f in ALLOW:
		if not calls.has(f):
			gone.append(f)
	_ok("① 登记表没有过期条目(登记了却已经不用的)", gone.is_empty(), str(gone))
	var miss: Array = []
	for f in CONVERTED:
		if int(cards.get(f, 0)) < int(CONVERTED[f]):
			miss.append("%s card_button ×%d < %d" % [f, int(cards.get(f, 0)), CONVERTED[f]])
	_ok("② 改过的 5 个文件里真有 `UISkin.card_button(`", miss.is_empty(), str(miss))
	var ov_bad: Array = []
	for f in OVERLAY_KEYS:
		var src := FileAccess.get_file_as_string(f)
		for want in OVERLAY_KEYS[f]:
			if src.find(want) < 0:
				ov_bad.append("%s 缺 %s" % [f.get_file(), want])
	var qv := FileAccess.get_file_as_string("res://scripts/scenes/queue_wait_view.gd")
	if qv.find("UISkin.card_button(") >= 0 or qv.find("UISkin.button(") >= 0:
		ov_bad.append("queue_wait_view.gd 里出现了 card_button / button")
	_ok("★④ 叠在画面上的控制键(回放条 / 观赛退出 / 排队取消)走 PixelKey 新画键底座, 不用 card_button / 木牌(分母 %d 个文件)" % OVERLAY_KEYS.size(),
		ov_bad.is_empty(), str(ov_bad))

	## ③ 实建
	var host := Control.new()
	add_child(host)
	var ov: Control = TutorialChoice.open(host, true)
	await get_tree().process_frame
	var btns: Array = []
	_collect_buttons(ov, btns)
	_ok("③ 分母: 教程选择框里有 2 颗按钮", btns.size() == 2, str(btns.size()))
	for b in btns:
		_ok("★③ 教程选择框「%s」= card_button 皮" % (b as Button).text, _is_card(b as Button), _skin_of(b as Button))
	var rb := Button.new()
	rb.text = "返回主菜单"
	SettleScreenS.dress_btn(rb, Color("#e8f0f6"))
	_ok("★③ 结算屏主按钮(dress_btn)= card_button 皮", _is_card(rb), _skin_of(rb))
	rb.free()
	host.queue_free()

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 卡片 / 弹框 / 操作条按钮" if _fail == 0 and _n >= 8 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


## card_button 的皮: 正常态是 StyleBoxFlat、底色 #6a3f1c、黄铜边(UISkin.card_button)
func _is_card(b: Button) -> bool:
	var sb := b.get_theme_stylebox("normal")
	return sb is StyleBoxFlat and (sb as StyleBoxFlat).bg_color.is_equal_approx(Color("#6a3f1c"))


func _skin_of(b: Button) -> String:
	var sb := b.get_theme_stylebox("normal")
	if sb is StyleBoxTexture:
		var tx := (sb as StyleBoxTexture).texture
		return "StyleBoxTexture " + (tx.resource_path if tx != null else "?")
	return str(sb)


func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for ch in n.get_children():
		_collect_buttons(ch, out)


func _gd_files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_gd_files(dir.path_join(sub)))
	return out
