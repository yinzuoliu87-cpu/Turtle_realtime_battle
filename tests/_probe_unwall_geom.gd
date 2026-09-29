extends Node
## DEV 探针: 拆墙之后那一屏(【绑定屏】)的参考表几何 + 渲染说明行数。
##
## 由来: 方案书 `docs/plans/20260929b-取消强制绑定.md` §6 最后一条 ——
##   「拆完重量一次参考差分」。而 `tools/login_screen_audit.py` 的 `ours` 条目里
##   每个矩形都标着 `prov: "probe"`: **那些数不是从截图量的, 是探针打出来的**
##   (参考图没有探针, 只能从像素量; 这条不对称写在那个脚本的 LIMITS 里)。
##   ⇒ 换了版式就得重打一遍, 手改 JSON 里的数字 = 编数。
##
## 口径与 `tests/_probe_wall_hit.gd` / `_probe_wall_lines.gd` 一致:
##   · 几何: w = %屏宽, h = %屏高, cy = 中心的 %屏高(参考表就是这个口径, 与分辨率无关)
##   · 说明行数: **渲染出来**的行数(`get_line_count()`), 不是源码行数 ——
##     一条串在窄屏上会折成两行, 照源码填就是编数。
##   · 排除标题 / 页脚步骤提示 / 版本号戳; 字段自带的说明行(「起个名字…」)算在内。
##
## ★这一屏现在**不会自己弹**(墙拆了) ⇒ 用产品自己的入口 `open_bind_on_entry`
##   把它打开(那就是主菜单那句「进度没备份」按下去走的那一条), 不另开后门。
##
## 跑法: <godot> --headless --path . res://tests/_probe_unwall_geom.tscn --quit-after 400

const SET := preload("res://scripts/scenes/SettingsScene.gd")

const VP := Vector2(1280.0, 720.0)


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.content_scale_size = Vector2i(VP)
	get_tree().root.size = Vector2i(VP)
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.account_email = ""
		gs.account_id = "uid-probe"
	SET.open_bind_on_entry = true
	var st := preload("res://scenes/Settings.tscn").instantiate()
	## ★注入点也开着: 门禁进程 `TURTLE_SUPABASE=" "` ⇒ 账号那一层是停用的,
	##   不注入的话 `_acct_on()` 为假, 这一屏的账号行/条件全不成立。
	st.acct_override = 1
	get_tree().root.add_child(st)
	for _i in range(20):
		await get_tree().process_frame
	if st.get("_email_layer") == null:
		print("[探针] 绑定屏没立起来 —— 这一轮不算数(分母为 0)")
		get_tree().quit()
		return
	st._email_set_step(1)
	for _i2 in range(4):
		await get_tree().process_frame

	print("")
	print("══════ 绑定屏 · 第一步 · %dx%d ══════" % [int(VP.x), int(VP.y)])
	var box: Control = st._email_box
	print("  框: %s" % str(box.get_global_rect()))

	# ── ① 可点元素 → 参考表口径 ──
	var hot: Array = []
	_walk_hot(st._email_layer, hot)
	hot.sort_custom(func(a, b):
		var ra: Rect2 = (a as Control).get_global_rect()
		var rb: Rect2 = (b as Control).get_global_rect()
		if absf(ra.position.y - rb.position.y) > 1.0:
			return ra.position.y < rb.position.y
		return ra.position.x < rb.position.x)
	print("  可点元素 %d 个:" % hot.size())
	var rows: Array = []
	for i in range(hot.size()):
		var c := hot[i] as Control
		var r: Rect2 = c.get_global_rect()
		var w_pct: float = r.size.x / VP.x * 100.0
		var h_pct: float = r.size.y / VP.y * 100.0
		var cy_pct: float = (r.position.y + r.size.y * 0.5) / VP.y * 100.0
		print("   [%d] %-14s %s  w=%.4f%%W  h=%.4f%%H  cy=%.4f%%H"
			% [i, _label_of(c), str(r), w_pct, h_pct, cy_pct])
		rows.append({"name": _label_of(c), "w": w_pct, "h": h_pct, "cy": cy_pct})
	## ★竖向堆叠(stack)= 水平投影有重叠的那些 —— 并排的两个钮竖向间隙是 0,
	##   而那不是「挤在一起」(手指左右还分得开), 参考表也是这个口径。
	var stack: Array = []
	for i in range(hot.size()):
		var ri: Rect2 = (hot[i] as Control).get_global_rect()
		var widest := true
		for j in range(hot.size()):
			if j == i:
				continue
			var rj: Rect2 = (hot[j] as Control).get_global_rect()
			if absf(ri.position.y - rj.position.y) <= 1.0 and rj.position.x < ri.position.x:
				widest = false
		if widest:
			stack.append(i)
	print("  竖向堆叠(每行取最左那个): %s" % str(stack))
	print("  === JSON(controls / stack) ===")
	var parts: PackedStringArray = []
	for r2 in rows:
		var d := r2 as Dictionary
		parts.append('{"name": "%s", "w": %.6f, "h": %.6f, "cy": %.6f, "prov": "probe"}'
			% [str(d["name"]), float(d["w"]), float(d["h"]), float(d["cy"])])
	print('  "controls": [%s],' % ", ".join(parts))
	print('  "stack": %s,' % str(stack))

	# ── ② 出口: 有没有「关闭」 ──
	var has_exit := false
	for c in hot:
		if c is Button and str((c as Button).text) == "关闭":
			has_exit = true
	print('  "exit": "%s",   ← 参考表那一维「有没有出口」' % ("关闭" if has_exit else "none"))

	# ── ③ 渲染说明行数 ──
	var labels: Array = []
	_walk_labels(st._email_layer, labels)
	var total := 0
	print("  说明性 Label(排除标题/页脚提示/版本号戳):")
	for l in labels:
		var n: int = (l as Label).get_line_count()
		total += n
		print("   %d 行 | %s" % [n, str((l as Label).text).replace("\n", "⏎")])
	print('  "explain_lines": %d,' % total)
	print('  "n_text_fields": %d,' % _count_edits(hot))
	st.queue_free()
	await get_tree().process_frame
	get_tree().quit()


func _walk_hot(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree() \
				and (c is BaseButton or c is LineEdit or c is TextEdit or c is Range):
			out.append(c)
		_walk_hot(c, out)


## 说明性文字 = 可见 Label 且不是标题 / 页脚步骤提示 / 版本号戳。
## ★三个排除项各有出处, 不是我现场挑的: 标题走 `login_wall_head()`;
##   页脚那句由 `_email_status` 画(「填邮箱 → 发验证码 → …」); 版本号戳名字带 `WallVer`。
func _walk_labels(n: Node, out: Array) -> void:
	var head := ""
	var p2c = load("res://scripts/gamedata/phase2_config.gd")
	if p2c != null:
		head = str(p2c.login_wall_head())
	for c in n.get_children():
		if c is Label and (c as Label).visible:
			var t := str((c as Label).text).strip_edges()
			var nm := str((c as Node).name)
			if t != "" and t != head and not nm.ends_with("WallVer") \
					and c != n.get_parent() and not _is_status(c, t):
				out.append(c)
		_walk_labels(c, out)


func _is_status(_c: Node, t: String) -> bool:
	## 页脚那一行是状态机画的步骤提示 —— 认它的原话(产品里就这一句)。
	return t.find("填邮箱") >= 0 and t.find("发验证码") >= 0


func _count_edits(hot: Array) -> int:
	var k := 0
	for c in hot:
		if c is LineEdit:
			k += 1
	return k


func _label_of(c: Control) -> String:
	if c is Button:
		return str((c as Button).text)
	if c is LineEdit:
		return "框「%s」" % str((c as LineEdit).placeholder_text)
	return str(c.name)
