extends Node
## _probe_cjk_wrap —— 导出包里中文能不能按字断行(2026-10-10 用户截图: 手机上图鉴说明只在空格处折行)。探针, 不进门禁。
## 打印 文字引擎名 / 行数 / 每行首尾几个字, 写到 user://cjk_wrap.txt 后退出。

const TXT := "每道气波随机朝向 1 名存活敌人，沿直线缓慢飞行，命中路径上的第一个敌人或龟蛋时结算，造成（40%×攻击力(52) = 21）物理伤害，此伤害同样受不屈的稀有度增伤加成。气波可被阻挡，可穿过障碍物，不会被友军阻挡。"

func _ready() -> void:
	var rt := RichTextLabel.new()
	rt.fit_content = true
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.size = Vector2(400, 10)
	rt.custom_minimum_size = Vector2(400, 0)
	rt.add_theme_font_size_override("normal_font_size", 18)
	rt.text = TXT
	add_child(rt)
	await get_tree().process_frame
	await get_tree().process_frame
	var ts := TextServerManager.get_primary_interface()
	var out := "ts=%s lines=%d\n" % [ts.get_name(), rt.get_line_count()]
	for i in range(rt.get_line_count()):
		var r: Vector2i = rt.get_line_range(i)
		out += "  [%d] %s\n" % [i, TXT.substr(r.x, r.y - r.x)]
	print(out)
	var f := FileAccess.open("user://cjk_wrap.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(out)
		f.close()
	get_tree().quit()
