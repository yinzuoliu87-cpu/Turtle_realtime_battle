extends Control

## MatchmakingScene — 匹配动画: 选龟后进入, 匹配几秒 → 显示「我 vs 对手」(头像+ID) → 进 2.5D 战斗.
## 实时版流程: MainMenu → TeamSelect(选龟) → Matchmaking(本场景, 抽对手) → RealtimeBattle3D(战斗).
## 对手 = 后端 ghost 池抽同档快照 (池空 → bot 兜底); 抽到的写 GameState.dual_ghost, 战斗右队读其 leaders.

const W := 1280
const H := 720

## ═══ 2026-08-19 实拍复看(真渲染截图, 搜索态/VS 态各连拍多个时刻)修掉的五件事 ═══
## ① 「匹」字被画成黄色笑脸 emoji —— 见 `_bold_font()` 里的探针记录。
## ② VS 那一屏**整体偏上**: 标题 110、卡片 230..510, 屏幕下方**空了 210px** 而上方只空 110。
## ③ 两张资料卡是"深色圆角矩形 + 3px 细边", 头像**一张有实心底、一张没有**
##    (avatars 尺寸 95×86 ~ 275×222 不等, 不透明面积 46%~93%) ⇒ 左右两边看着不是一套东西。
##    ★不动美术: 给两边套**同一个 portrait-frame**, 差异就从"一边有盒子"变成"画风不同的两张肖像"。
## ④ 对手 ID 直接把后端内部串印在脸上: 实拍「ID autoplay-b2_COH7」, 而自己那张是「#195060」。
## ⑤ 取消键 44px(=24pt)低于 44pt 触控下限, 且挂在**视口坐标**上 ——
##    别的屏(图鉴/背包/排行榜)的返回键都在 1280 设计框里, 只有它贴着真实屏幕边。
const FOUND_Y := 152.0    # ②
const CARD_Y := 236.0
const CARD_W := 370.0
const CARD_H := 316.0
## 头像框边长。卡内竖向账: 18 上留白 + AV_BOX + 12 + 名 36 + 18 + ID 24 = 18+200+78 = 296,
## 而 panel-frame 实测边带 13px ⇒ 内容底 296 < 316-13 = 303。**这条账要算, 不是眼估**。
## (第一版 168: 370 宽的卡里左右各空 101px, 实拍看就是"一张小图钉在大板子中间"。)
const AV_BOX := 200.0
const RADAR_C := Vector2(640.0, 350.0)
## 雷达环最大半径: 圆心 y=350, 取 330 ⇒ 上沿 y=20 / 下沿 680, 不贴屏幕边。
## (原来是圆心 340 + 半径 340 = 上沿正好 y=0, 环压在屏幕顶边上。)
const RADAR_R := 330.0
const FAKE_NAMES := [
	"深海霸主", "龟界传说", "咸鱼翻身", "老司机带带我", "萌新龟龟", "海底捞月", "龟速前进", "一击三连",
	"佛系养龟", "头号玩家", "水深危险", "乌龟跑得快", "退役龟皇", "龟龟不下班", "南极来的", "稳健型选手",
]
const Backend := preload("res://scripts/net/backend.gd")

var content_root: Control
var _font_cache: FontVariation = null
var _dots_lbl: Label = null
var _dots_tween: Tween = null
var _cancelled := false
var _cancel_btn: Button = null   # 跟着设计框走(见 _center)
var _searching := false   # 雷达环循环的闸: _build_vs 里置 false 立即断. 原先靠 is_instance_valid(_dots_lbl) 判断,
                          #   但 queue_free 是延迟的 → 换幕后还会多播一圈残留弧.


func _ready() -> void:
	await get_tree().process_frame
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await get_tree().process_frame
	Audio.play_bgm("menu", 1.0, 0.4)
	_bg()
	content_root = Control.new()
	content_root.size = Vector2(W, H); content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_root)
	_center()
	get_viewport().size_changed.connect(_center)

	_build_cancel_btn()   # 取消键: 误点匹配可中途返回主菜单 (流程审计 F1)
	# V2 异步匹配: 后端抽同档对手快照 (ghost/池空→bot 兜底); 战斗右队读 dual_ghost.leaders (RealtimeBattle3DScene._resolve_right).
	#   排除自己上传的ghost(防匹到自己阵容) + 最近3场对手; vs 卡头像/名取自抽到的对手 profile.
	var _rng := Backend.make_match_rng()   # 单一受控PRNG(切片1): 默认randomize()与线上一致; TURTLE_SEED设时确定→同种子同对手(测试/复现)
	var exclude: Array = ["g_%d" % int(GameState.season_id)]   # ★排除自己ghost(按稳定id·2026-07-18): 原塞season_leaders(宠物id)与ghost_id口径不符=死代码防不住; 玩家自己upload的id=g_<大轮id>
	exclude.append_array(GameState.recent_ghost_ids)   # 排除最近3场对手(防连续同一快照·用户2026-07-15)
	GameState.dual_ghost = Backend.find_opponent(Backend.bracket_for_battles(int(GameState.season_total_battles)), exclude, _rng)
	var _gid := str((GameState.dual_ghost as Dictionary).get("ghost_id", "")) if GameState.dual_ghost is Dictionary else ""
	if _gid != "":
		GameState.recent_ghost_ids.append(_gid)
		while GameState.recent_ghost_ids.size() > 8: GameState.recent_ghost_ids.pop_front()   # 3→8(用户2026-07-18): 配合档窗口~21候选, 循环过大半池才重复(防总撞同一支)
	var opp := _opponent_from_ghost(GameState.dual_ghost)
	GameState.dual_opponent = opp
	_build_searching()
	await get_tree().create_timer(2.2).timeout
	if _cancelled or not is_inside_tree():
		return
	_build_vs(opp)
	await get_tree().create_timer(2.6).timeout
	if _cancelled or not is_inside_tree():
		return
	await _fade_to_black(0.4)       # 硬切→淡出: 进战斗不再"啪"一下换画面
	if _cancelled or not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")


# ---------------------------------------------------------------------------
#  演出小工具 (震屏 / 闪屏 / 冲击波 / 淡出). 全部挂在 self 而非 content_root,
#  因为 _build_searching/_build_vs 会清空 content_root 的子节点。
# ---------------------------------------------------------------------------

## 震屏: 抖 content_root 的 position, 抖完归位到 _center() 的锚点.
func _shake(amount: float, dur: float) -> void:
	if content_root == null:
		return
	var home: Vector2 = content_root.position
	var tw := create_tween()
	var steps := int(dur / 0.04)
	for i in steps:
		var k: float = 1.0 - float(i) / float(maxi(steps, 1))   # 衰减
		var off := Vector2(randf_range(-amount, amount), randf_range(-amount, amount)) * k
		tw.tween_property(content_root, "position", home + off, 0.04)
	tw.tween_property(content_root, "position", home, 0.04)


## 全屏闪白/闪色: 叠一层 ColorRect 快速淡掉.
func _flash(col: Color, dur: float) -> void:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "color:a", 0.0, dur)
	tw.tween_callback(r.queue_free)


## 冲击波圆环: 从 center 扩散并淡出 (纯 Control + draw, 不依赖贴图).
func _shockwave(center: Vector2, col: Color, max_r: float, dur: float) -> void:
	var ring := _RingFx.new()
	ring.col = col
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.center = center
	content_root.add_child(ring)
	var tw := create_tween()
	tw.tween_property(ring, "radius", max_r, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "alpha", 0.0, dur)
	tw.tween_callback(ring.queue_free)


## 淡入黑幕并 await 完成 (换场景前调).
func _fade_to_black(dur: float) -> void:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.color = Color(0, 0, 0, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "color:a", 1.0, dur)
	await tw.finished


## 扩散圆环控件: radius/alpha 由 Tween 推, _draw 里画描边圆.
class _RingFx extends Control:
	var col: Color = Color.WHITE
	var center: Vector2 = Vector2.ZERO
	var radius: float = 0.0:
		set(v): radius = v; queue_redraw()
	var alpha: float = 1.0:
		set(v): alpha = v; queue_redraw()

	func _draw() -> void:
		if radius <= 1.0:
			return
		var c := col
		c.a = alpha
		draw_arc(center, radius, 0.0, TAU, 64, c, maxf(2.0, 9.0 * alpha), true)


func _center() -> void:
	if content_root != null:
		content_root.position = ((get_viewport_rect().size - Vector2(W, H)) / 2.0).round()
	## 取消键跟着设计框一起挪 —— 它虽然挂在 self 上(见下), 位置得和框里的内容同一套坐标,
	## 否则 21:9 上它离屏幕边 28px、而别的东西整体内缩 200px, 两边不是一个体系。
	if is_instance_valid(_cancel_btn) and content_root != null:
		var m: Vector4 = SafeArea.margins(Vector2(get_viewport_rect().size), 18.0)
		_cancel_btn.position = content_root.position + Vector2(maxf(20.0, m.x), maxf(18.0, m.y))


## 取消匹配键 (左上角): 加到 self 而非 content_root → 不被 _build_searching/_build_vs 的清屏移除.
func _build_cancel_btn() -> void:
	var btn := Button.new()
	btn.text = "← 取消"
	btn.add_theme_font_override("font", _bold_font())
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color("#cfe0ee"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	## ★原来是「#16283a 底 + 圆角 10 + 2px 描边」= 网页盒, 且高只有 44px(=24pt)。
	##   44pt 触控下限 = 81px(视口恒 720 高 ↔ iPhone 横屏 390pt ⇒ 1pt = 1.846px)。
	btn.custom_minimum_size = Vector2(140.0, 81.0)
	btn.size = Vector2(140.0, 81.0)
	btn.focus_mode = Control.FOCUS_NONE
	UISkin.button(btn, Color("#9fb6c9"))   # 金属签牌皮(和图鉴/背包/排行榜的返回键同一套)
	btn.pressed.connect(_on_cancel)
	add_child(btn)
	_cancel_btn = btn
	_center()


func _on_cancel() -> void:
	if _cancelled:
		return
	_cancelled = true
	if _dots_tween != null and _dots_tween.is_valid():
		_dots_tween.kill()
	GameState.mode = "single"   # 离开双路 → 中性态; 下次入口会再 reset_dual_lane
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


## 对手资料卡 = 抽到的 ghost 快照 profile (头像取其首领 / 名+ID); profile 缺字段时随机兜底 (老 bot 也有 profile).
func _opponent_from_ghost(ghost: Dictionary) -> Dictionary:
	var prof: Dictionary = ghost.get("profile", {}) if ghost is Dictionary else {}
	var leaders: Array = ghost.get("leaders", []) if ghost is Dictionary else []
	var avatar := str(prof.get("avatar", ""))
	if avatar == "" and not leaders.is_empty():
		avatar = str(leaders[0])
	if avatar == "":
		avatar = "basic"
	var nm := str(prof.get("name", ""))
	if nm == "":
		nm = FAKE_NAMES[randi() % FAKE_NAMES.size()]
	return {"name": nm, "avatar": avatar, "id": _display_id(str(prof.get("id", "")))}


## 玩家看得懂的 ID。
##
## ★由来(2026-08-19 实拍): VS 卡上印着「ID autoplay-b2_COH7」—— 后端内部串直接怼玩家脸上,
##   而同屏自己那张写的是「#195060」。原来只挡了 `""` 和 `"BOT"` 两种, 挡不住别的内部串。
## ★改成**白名单**: 只有已经长成 `#6位数字` 的才原样用, 其余一律折算。
##   折算用 hash 而不是 randi ⇒ **同一个对手每次显示同一个号**(randi 会让同一支队伍每场换号)。
func _display_id(raw: String) -> String:
	if raw.length() == 7 and raw.begins_with("#") and raw.substr(1).is_valid_int():
		return raw
	if raw == "":
		return "#%06d" % (randi() % 1000000)
	return "#%06d" % (absi(hash(raw)) % 1000000)


## 我方资料卡: 头像取本场锁定的首领 (season_leaders[0]), 否则随机.
func _player_profile() -> Dictionary:
	var pid := "basic"
	var leaders: Array = GameState.season_leaders if GameState.season_leaders is Array else []
	if not leaders.is_empty():
		pid = str(leaders[0])
	elif not DataRegistry.launch_pets.is_empty():
		pid = str(DataRegistry.launch_pets[randi() % DataRegistry.launch_pets.size()].get("id", "basic"))
	## ★自己的 ID 也别每场重摇 —— 原来是 randi(), 同一个玩家每场看到一个新号,
	##   而"ID"这个词在玩家眼里就是"我的号码"。按存档里的稳定量折算。
	return {"name": "你", "avatar": pid, "id": _display_id("me_%d" % int(GameState.season_id))}


func _bg() -> void:
	var base := ColorRect.new(); base.set_anchors_preset(Control.PRESET_FULL_RECT); base.color = Color("#0a1622")
	add_child(base)
	var grad := Gradient.new()
	grad.set_offset(0, 0.0); grad.set_color(0, Color(0.04, 0.09, 0.14, 1.0))
	grad.set_offset(1, 1.0); grad.set_color(1, Color(0.02, 0.04, 0.07, 1.0))
	var gt := GradientTexture2D.new(); gt.gradient = grad; gt.fill_from = Vector2(0.5, 0.0); gt.fill_to = Vector2(0.5, 1.0)
	var tr := TextureRect.new(); tr.set_anchors_preset(Control.PRESET_FULL_RECT); tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE; tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)


func _font(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", _bold_font())
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bold_font() -> FontVariation:
	if _font_cache == null:
		var cjk := SystemFont.new()
		cjk.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "WenQuanYi Micro Hei", "sans-serif"])
		cjk.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK 网页/iOS 兜底 (SystemFont 在 web 取不到系统字体→中文乱码)
		## ★`allow_system_fallback` 必须是 false —— 见下面 fallbacks 那段的探针记录。
		cjk.font_weight = 700; cjk.allow_system_fallback = false; cjk.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font_cache = FontVariation.new()
		_font_cache.base_font = load("res://assets/fonts/m6x11.ttf") as FontFile
		## 【2026-08-19 实拍复看修掉的字形串台】——「匹配中」的**「匹」被画成一个黄色笑脸 emoji**。
		##
		## ═══ 现象 ═══
		## 间歇性: SHOT_WAIT=60/200 帧干净, **430 帧起 5/5 必现**; 而且笑脸的内容每次还不一样
		## (有时整张笑脸有眼有嘴, 有时只有半张)。⇒ 跑一次看一眼的检查必漏, 只有连拍多个时刻才逮得到。
		##
		## ═══ 探针(不是推理出来的) ═══
		## ① 标题换成 "PROBE匹配中" 重拍 → 笑脸**跟着「匹」的排版位置一起右移**
		##    ⇒ 不是 🔍 画歪了, 是「匹」这个字自己解析到了**彩色 emoji 字体**的字形。
		## ② 只把打包 Noto SC 提到回退链最前(系统回退仍开着) → **照样出笑脸** ⇒ 顺序不是根因。
		## ③ `cjk.allow_system_fallback = false` → 430/470/480 帧三连**干净** ⇒ 根因在这。
		##
		## ═══ 为什么本屏中招而别的屏没事 ═══
		## 主题 `assets/themes/default_theme.tres` 的 SystemFont **没设 font_weight**;
		## 本屏为了"真 700 粗体"设了 `font_weight = 700` —— 带权重去问系统要"支持「匹」的粗体",
		## Windows 的字体匹配会把彩色 emoji 字体也算进候选。关掉动态系统回退即可, 粗体不受影响
		## (雅黑本身就在 font_names 里, 由它出 700 字重)。
		##
		## ═══ 关掉之后靠什么兜底 ═══
		## 雅黑/苹方(桌面, 真 700) → 打包 Noto SC(web/iOS 取不到系统字体时的中文) →
		## 打包 Noto Emoji(emoji 兜底, 防豆腐块)。实拍确认 🔍 在桌面仍是**彩色**的。
		_font_cache.fallbacks = [
			cjk,
			load("res://assets/fonts/NotoSansSC-Regular.otf") as FontFile,
			load("res://assets/fonts/NotoEmoji-Regular.ttf") as FontFile,
		]
	return _font_cache


func _build_searching() -> void:
	for c in content_root.get_children():
		c.queue_free()
	var title := _font(40, Color("#ffd93d"))
	title.text = "🔍 匹配中"
	title.size = Vector2(W, 56); title.position = Vector2(0, 300); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(title)
	_dots_lbl = _font(40, Color("#ffd93d"))
	## ★点点的 x 原来写死 `W/2 + 96` —— 那是照着当时那条字的宽度目测出来的。
	##   本轮换了字体回退链(见 _bold_font), 字宽跟着变, 写死的偏移就会离题。
	##   改成【量标题实际字宽】再贴到它右边: 换字/改文案都不会错位。
	var tw: float = _bold_font().get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	_dots_lbl.text = ""; _dots_lbl.size = Vector2(60, 56)
	_dots_lbl.position = Vector2(W / 2.0 + tw / 2.0 + 6.0, 300)
	content_root.add_child(_dots_lbl)
	var sub := _font(20, Color("#9fb6c9"))
	sub.text = "正在为你寻找势均力敌的对手..."
	sub.size = Vector2(W, 28); sub.position = Vector2(0, 366); sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(sub)
	# 跳动的点
	_dots_tween = create_tween().set_loops()
	for d in ["", ".", "..", "..."]:
		_dots_tween.tween_callback(func(): if is_instance_valid(_dots_lbl): _dots_lbl.text = d)
		_dots_tween.tween_interval(0.35)
	# 雷达扫描环: 三道错开相位的扩散圆, 一直循环到匹配成功
	_searching = true
	for i in 3:
		_radar_ping(float(i) * 0.5)


## 一发雷达环, 播完自己再排下一发 (整体搜索期循环). _searching 置 false 立即停.
func _radar_ping(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	while _searching and is_inside_tree() and not _cancelled and content_root != null:
		_shockwave(RADAR_C, Color("#ffd93d"), RADAR_R, 1.5)
		await get_tree().create_timer(1.5).timeout


func _build_vs(opp: Dictionary) -> void:
	_searching = false   # 断雷达环
	if _dots_tween != null and _dots_tween.is_valid():
		_dots_tween.kill()
	for c in content_root.get_children():
		c.queue_free()
	# ① 命中瞬间: 绿闪 + 小震 + 一圈绿波 —— 让"找到了"有落点, 不是悄悄换个字
	_flash(Color(0.55, 0.95, 0.62, 0.42), 0.30)
	_shake(7.0, 0.20)
	_shockwave(RADAR_C, Color("#7fd98a"), 520.0, 0.45)
	var found := _font(26, Color("#7fd98a"))
	found.text = "✓ 已匹配到对手!"
	found.size = Vector2(W, 34); found.position = Vector2(0, FOUND_Y); found.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(found)
	found.pivot_offset = Vector2(W / 2.0, 17)
	found.scale = Vector2(1.8, 1.8); found.modulate.a = 0.0
	var ftw := found.create_tween()
	ftw.tween_property(found, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ftw.parallel().tween_property(found, "modulate:a", 1.0, 0.18)
	# ② 两张资料卡对撞滑入 (左=你, 右=对手), 0.5s 后同时到位
	var me := _player_profile()
	_build_card(me, Vector2(170, CARD_Y), Color("#5aa9ff"), -500.0)
	_build_card(opp, Vector2(W - 170 - CARD_W, CARD_Y), Color("#ff6b6b"), 500.0)
	# ③ VS 在两卡到位的同一拍砸下来 → 红闪 + 大震 + 红波, 做出"对撞"的响
	var vs := _font(64, Color("#ff6b6b"))
	vs.text = "VS"; vs.size = Vector2(160, 80)
	vs.position = Vector2(W / 2.0 - 80, CARD_Y + CARD_H / 2.0 - 40.0)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(vs)
	vs.scale = Vector2(3.4, 3.4); vs.modulate.a = 0.0; vs.pivot_offset = Vector2(80, 40)
	var vtw := vs.create_tween()
	vtw.tween_interval(0.42)
	vtw.tween_property(vs, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	vtw.parallel().tween_property(vs, "modulate:a", 1.0, 0.10)
	vtw.tween_callback(func() -> void:
		_flash(Color(1.0, 0.42, 0.42, 0.5), 0.26)
		_shake(15.0, 0.30)
		_shockwave(Vector2(W / 2.0, CARD_Y + CARD_H / 2.0), Color("#ff6b6b"), 480.0, 0.42))
	# 落定后微微回弹, 免得砸完就死板杵着
	vtw.tween_property(vs, "scale", Vector2(1.12, 1.12), 0.12)
	vtw.tween_property(vs, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_card(prof: Dictionary, pos: Vector2, accent: Color, slide_from_dx: float) -> void:
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#10202c"); sb.set_corner_radius_all(14); sb.set_border_width_all(3); sb.border_color = accent
	## 金属大框(背包/图鉴/战绩/排行榜同一张 panel-frame); 阵营色留在 modulate 里。
	## ★modulate 别超 1.3 —— 过了会把框芯冲亮、金属细节糊平(实拍确认过)。
	var ctex := UISkin.nine("panel-frame.png", 20, sb)
	if ctex is StyleBoxTexture:
		(ctex as StyleBoxTexture).modulate_color = UISkin.tint_of(accent)
	card.add_theme_stylebox_override("panel", ctex)
	card.size = Vector2(CARD_W, CARD_H); card.position = pos
	content_root.add_child(card)
	# 头像 —— 统一套一个 portrait 框。
	# ★为什么要框: avatars 的画幅差得离谱(95×86 ~ 275×222, 不透明面积 46%~93%),
	#   实拍 VS 屏里对手那张是**满底的实心方块**、自己那张是**去底的立绘** ——
	#   看着不像同一套 UI。套上同一个框, 差异就退成"两张画风不同的肖像"。
	var frame := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.04, 0.09, 0.14, 0.75); fsb.set_corner_radius_all(10)
	fsb.set_border_width_all(2); fsb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	var ftex := UISkin.nine("portrait-frame.png", 16, fsb)
	if ftex is StyleBoxTexture:
		(ftex as StyleBoxTexture).modulate_color = UISkin.tint_of(accent)
	frame.add_theme_stylebox_override("panel", ftex)
	frame.size = Vector2(AV_BOX, AV_BOX); frame.position = Vector2((CARD_W - AV_BOX) / 2.0, 18)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(frame)
	var avatar_path := "res://assets/sprites/avatars/%s.png" % str(prof.get("avatar", "basic"))
	if ResourceLoader.exists(avatar_path):
		var tr := TextureRect.new(); tr.texture = load(avatar_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.size = Vector2(AV_BOX - 24.0, AV_BOX - 24.0); tr.position = Vector2(12, 12)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tr)
	else:
		var emo := _font(80, Color.WHITE); emo.text = "🐢"
		emo.size = Vector2(AV_BOX, AV_BOX - 20.0); emo.position = Vector2(0, 14)
		emo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; frame.add_child(emo)
	var name_l := _font(28, accent)
	name_l.text = str(prof.get("name", "?")); name_l.size = Vector2(CARD_W, 36)
	name_l.position = Vector2(0, 18 + AV_BOX + 12.0)
	## ghost 名来自玩家自定义 profile, 长度不受控 —— 截断加省略号, 别糊出卡片。
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; card.add_child(name_l)
	var id_l := _font(18, Color("#9fb6c9"))
	id_l.text = "ID %s" % str(prof.get("id", "")); id_l.size = Vector2(CARD_W, 24)
	id_l.position = Vector2(0, 18 + AV_BOX + 54.0)
	id_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; card.add_child(id_l)
	# 滑入动画: EASE_IN 加速冲进来(不是滑进来), 到位后 BACK 回弹一下做"撞停"
	var home_x := pos.x
	card.position.x = home_x + slide_from_dx; card.modulate.a = 0.0
	card.pivot_offset = card.size * 0.5
	var tw := card.create_tween()
	tw.tween_property(card, "position:x", home_x, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(card, "modulate:a", 1.0, 0.30)
	tw.tween_property(card, "scale", Vector2(1.06, 0.94), 0.08)   # 撞停 squash
	tw.tween_property(card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
