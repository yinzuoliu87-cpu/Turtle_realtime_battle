extends Node
## verify_ui_layout.gd — UI 双端适配门禁 (用户 2026-08-01:「pc端做一板，手机端做一板」)
##
## 每屏 × 四个真实比例, 焊死三件事:
##   ① 不溢出   —— 没有可见 Control 跑到视口外
##   ② 内容居中 —— 内容层(UIFrame 的 DesignFrame / 场景自己的 content_root)精确居中于真实视口
##   ③ 能点得着 —— 可点元素短边 ≥ TAP_MIN
##
## ═══ ② 为什么断言"内容层位置"而不是统计节点 ═══
## 我先后试过两版统计, 都不成立, 记在这里免得下一个人再走一遍:
##   · 【包围盒中心】: 一个贴边的返回键就能把整个盒子带偏 —— "内容没居中"和
##     "chrome 正确贴边"混成同一个数字。
##   · 【逐节点配对 delta】: 本项目三种布局哲学并存(1280×720 设计框 / 选龟那种按视口等比缩放 /
##     贴边 chrome), 同一个统计量在三者上含义不同, 阈值怎么调都有一类被误判。
## 内容层位置是【无歧义】的: 它要么等于 (视口-设计)/2, 要么不等。这条也正好是本次修的东西 ——
## 排行榜/战绩/设置/商店/背包/训龟大师原先【根本没有内容层】, 直接按设计坐标画在视口 (0,0),
## 21:9 下内容整体坐在中心左边 200px(审计器实测)。
##
## ═══ 为什么用 SubViewport 而不是开真窗口 ═══
## 真窗口要 --resolution 起进程, 一屏一比例 = 40 次启动, 进不了门禁。
## SubViewport 可直接设 size, 场景里 get_viewport().get_visible_rect() 读到的就是它 ——
## 与真窗口同一条取值路径, 也是唯一能在无头 CI 里跑的办法。
##
## ═══ ③ 阈值口径(单位: 视口像素, 不是 pt) ═══
## iPhone 14 横屏 844×390pt, 视口高恒 720 → 1pt = 1.846 视口像素 ⇒ HIG 的 44pt = 81 像素。
## 全项目按 1280×720 设计, 把每个键都做到 81 像素高 = 重画所有界面, 不在本次范围。
## 门禁卡【严重档 40 像素(≈22pt)】: 低于它手指基本点不中。44pt 完整达标记在方案书未决点。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_ui_layout.tscn

const TAP_MIN := 40.0        # 可点元素短边下限(视口像素 ≈ 22pt)
const OVER_TOL := 4.0        # 溢出容差: 自动尺寸 Label 宽度依赖字体度量, 卡 1px 会跨平台偶发红
const CENTER_TOL := 1.5      # 内容层位置容差 —— 位置是 round() 出来的, 只留取整误差

## 四个真实设备比例(视口尺寸)。stretch=canvas_items+expand:
##   窗口比 16:9 宽 → 锁高 720 宽变大;  比 16:9 窄 → 锁宽 1280 高变大 ⇒ 视口宽恒 ≥1280。
const VIEWS := [
	[1280, 720],    # 16:9 设计基准 / 多数 PC
	[1560, 720],    # 19.5:9 iPhone 横屏
	[1680, 720],    # 21:9 带鱼屏
	[1280, 960],    # 4:3 iPad
]

## 这两屏【不走 1280×720 设计框】, 而是整屏按视口等比缩放(自带 _sp()/_sf() 缩放系数 +
## size_changed 重排)。对它们问"内容层在哪"没有意义 → ② 豁免, 由 ①(不溢出) ③(热区) 兜住。
const SCALING_SCREENS := ["TeamSelect", "Codex"]

## 🛠 调试场键只在 debug 构建出现(正式包没有), 不卡它的热区。
const TAP_EXEMPT := ["🛠 调试场"]

const SCREENS := ["MainMenu", "Shop", "Inventory", "Codex", "Leaderboard",
	"Record", "Settings", "TrainerConfig", "Matchmaking", "TeamSelect"]

var _n := 0
var _fail := 0


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
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	# ★商店在 season_total_battles<=0 时走【上锁屏】(只有背景+一句话+返回键) —— 那时量到的不是商店。
	#   给它一场战斗数, 测的才是真货架。(test_mode 已开, 不写盘。)
	gs.season_total_battles = maxi(1, int(gs.season_total_battles))
	print("=== UI 双端适配 (每屏 × %d 比例) ===" % VIEWS.size())

	var measured := 0
	for scn in SCREENS:
		var path := "res://scenes/%s.tscn" % scn
		if not ResourceLoader.exists(path):
			_ok("场景存在 %s" % scn, false, "缺 " + path)
			continue
		var over_total := 0
		var over_detail := ""
		var tiny_worst := ""
		var center_bad := ""
		var tab_bad := ""
		var nodes_min := 999999
		for v in VIEWS:
			var w: int = int(v[0])
			var h: int = int(v[1])
			var res: Dictionary = await _measure(path, w, h)
			measured += 1
			over_total += int(res["over"])
			if over_detail == "" and str(res.get("worst", "")) != "":
				over_detail = str(res["worst"])
			if tiny_worst == "" and str(res["tiny"]) != "":
				tiny_worst = str(res["tiny"])
			nodes_min = mini(nodes_min, int(res["n"]))
			# 图鉴页签行必须居中于【真实视口】(它挂在全宽锚的 TabBar 上)
			var toff = res.get("tab_off", null)
			if tab_bad == "" and toff != null and absf(float(toff)) > 8.0:
				tab_bad = "@%dx%d 页签行中心偏离视口中心 %.0fpx" % [w, h, float(toff)]
			if center_bad == "" and not (scn in SCALING_SCREENS):
				var got = res.get("frame", null)
				if got == null:
					center_bad = "@%dx%d 找不到内容层(该屏没套 UIFrame / 没有 content_root)" % [w, h]
				else:
					var want := Vector2(roundf((float(w) - 1280.0) * 0.5), roundf((float(h) - 720.0) * 0.5))
					if (got as Vector2).distance_to(want) > CENTER_TOL:
						center_bad = "@%dx%d 内容层在 %s, 应在 %s" % [w, h, str(got), str(want)]

		# ★分母: 场景没建起来时后面全是空检查。门槛 3 而不是 5 —— 匹配屏本来就只有
		#   "搜索中"文字 + 转圈 + 取消键这几件(实测 4 个), 卡 5 会把正常情况判成红。
		_ok("★分母 %s 每个比例都量到 ≥3 个可见元素" % scn, nodes_min >= 3, "最少那次 %d 个" % nodes_min)
		_ok("① %s 四个比例都不溢出视口" % scn, over_total == 0,
			"溢出 %d 个; 最严重: %s" % [over_total, over_detail])
		if scn in SCALING_SCREENS:
			_ok("② %s 按视口等比缩放(不走设计框) —— ② 豁免, 由 ①③ 兜住" % scn, true)
		else:
			_ok("② %s 内容层精确居中于真实视口(四个比例)" % scn, center_bad == "", center_bad)
		_ok("③ %s 没有短边 <%dpx 的可点元素" % [scn, int(TAP_MIN)], tiny_worst == "", tiny_worst)
		if scn == "Codex":
			_ok("②b 图鉴页签行居中于真实视口(补 SCALING 豁免留下的洞)", tab_bad == "", tab_bad)

	_ok("★分母: 真的量到了 %d 组(屏×比例)" % measured, measured >= SCREENS.size() * VIEWS.size(),
		"measured=%d" % measured)
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — UI 双端适配" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 在指定视口尺寸下实例化一屏, 量真实 get_global_rect()。
func _measure(path: String, w: int, h: int) -> Dictionary:
	var sv := SubViewport.new()
	sv.size = Vector2i(w, h)
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED   # 只要布局, 不要渲染开销
	add_child(sv)
	var inst = (load(path) as PackedScene).instantiate()
	sv.add_child(inst)
	# 等界面建完 + 入场 tween 落定。★90 帧不够: 主菜单左栏键从 x=-560 滑入, 延迟 0.5+0.08i 秒,
	#   抓早了会把"滑到一半"当成"按钮跑到屏外"(2026-08-01 我就这样误判过一次)。
	for _i in range(150):
		await get_tree().process_frame

	var vp := Vector2(float(w), float(h))
	var area: float = vp.x * vp.y
	var nodes: Array = []
	_walk(inst, nodes)
	var over := 0
	var over_worst := ""
	var over_max := 0.0
	var tiny := ""
	var counted := 0
	for c in nodes:
		var r: Rect2 = (c as Control).get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		if r.size.x * r.size.y >= area * 0.95:
			continue                                  # 满铺背景/遮罩: 本来就该铺满整窗
		if c is UIFrame:
			continue                                  # UIFrame 的骨架不是内容(按类型认, 名字可能被 Godot 改)
		if _in_clipped(c, inst):
			continue                                  # 滚动/裁剪区里的条目"超出"是滚动, 不是溢出
		counted += 1
		var out_by: float = maxf(maxf(-r.position.x, -r.position.y), maxf(r.end.x - vp.x, r.end.y - vp.y))
		if out_by > OVER_TOL:
			over += 1
			if over_worst == "" or out_by > over_max:
				over_max = out_by
				over_worst = "%s(%s) 超出 %.0fpx @%dx%d 尺寸%.0fx%.0f" % [
					String(inst.get_path_to(c)), c.get_class(), out_by, w, h, r.size.x, r.size.y]
		if tiny == "" and _clickable(c) and minf(r.size.x, r.size.y) < TAP_MIN:
			var t: String = _btn_text(c)
			if not (t in TAP_EXEMPT):
				tiny = "%s(%s) %.0f×%.0f @%dx%d" % [String(inst.get_path_to(c)), t, r.size.x, r.size.y, w, h]

	# 图鉴页签行的水平中心(相对视口中心)。★为什么单挑它出来:
	#   图鉴走"按视口缩放"路线, ② 对它豁免 —— 而反向验证发现, 把页签的 start_x 改回写死 1280
	#   (那正是我这次修掉的 bug), 门禁【一条都不红】。豁免出来的洞就得用针对性断言补上,
	#   否则"豁免"= 那一屏从此没人守(memory: fb-verify-must-run-the-real-path)。
	var tab_off = null
	var tb := inst.get_node_or_null("UI/TabBar")
	if tb != null:
		var lo := INF
		var hi := -INF
		for ch in tb.get_children():
			if ch is Control and (ch as Control).visible:
				var rr: Rect2 = (ch as Control).get_global_rect()
				lo = minf(lo, rr.position.x); hi = maxf(hi, rr.end.x)
		if lo < INF:
			tab_off = (lo + hi) * 0.5 - vp.x * 0.5

	# 内容层: UIFrame 建的 DesignFrame, 或场景自己的 content_root(主菜单/匹配是这种)
	var frame_pos = null
	for ch in inst.get_children():
		if ch is UIFrame:
			frame_pos = (ch as Control).position
			break
	if frame_pos == null:
		var cr = inst.get("content_root")
		if cr != null and is_instance_valid(cr) and cr is Control:
			frame_pos = (cr as Control).position

	sv.queue_free()
	await get_tree().process_frame
	return {"over": over, "n": counted, "tiny": tiny, "worst": over_worst, "frame": frame_pos, "tab_off": tab_off}


func _walk(n: Node, out: Array) -> void:
	if n is Control:
		var c := n as Control
		if c.visible and not (c is Container) and not (c is MarginContainer):
			out.append(c)
	for ch in n.get_children():
		_walk(ch, out)


func _in_clipped(c: Control, root: Node) -> bool:
	var p := c.get_parent()
	while p != null and p != root:
		if p is ScrollContainer:
			return true
		if p is Control and (p as Control).clip_contents:
			return true
		p = p.get_parent()
	return false


func _btn_text(c: Control) -> String:
	if c is Button:
		var t: String = (c as Button).text
		return t if t != "" else c.get_class()
	return c.get_class()


func _clickable(c: Control) -> bool:
	if c is BaseButton:
		return true
	return c.mouse_filter == Control.MOUSE_FILTER_STOP and c.has_signal("gui_input") \
		and c.get_signal_connection_list("gui_input").size() > 0
