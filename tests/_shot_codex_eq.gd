extends Node
## DEV 工具(不是门禁): 图鉴装备页逐件拍(看底部「所属羁绊」块; 11-27 统一成「(N) 一句」写法)。
## 跑法: SHOT_DIR=<目录> EQ_IDS=p2eq_052,p2eq_093 TURTLE_SUPABASE=" " APPDATA=<单独目录> WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_codex_eq.tscn
## ★不能 --headless: 无头拿不到视口纹理。


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await _frames(2)
	get_node("/root/GameState").test_mode = true
	var c = load("res://scenes/Codex.tscn").instantiate()
	add_child(c)
	await get_tree().create_timer(2.5).timeout   # 图鉴打开有一段淡入(按时间等: 帧跑得快)
	c._switch_tab("equips")
	await _frames(6)
	var k := 0
	for eid in OS.get_environment("EQ_IDS").split(",", false):
		for i in range(c._items.size()):
			var it = c._items[i]
			if it is Dictionary and str(it.get("id", "")) == eid:
				c._select(i)
		await get_tree().create_timer(0.8).timeout   # 切页签 / 选条目也有滑入
		## SCROLL_BOTTOM=1: 详情滚到底再拍(看羁绊块); 默认拍顶上(效果文案)
		if OS.get_environment("SCROLL_BOTTOM") == "1":
			for ch in c.find_children("*", "ScrollContainer", true, false):
				(ch as ScrollContainer).scroll_vertical = 100000
			await _frames(4)
		await RenderingServer.frame_post_draw
		var path := "%s/eq_%d.png" % [OS.get_environment("SHOT_DIR"), k]
		get_viewport().get_texture().get_image().save_png(path)
		print("[SHOT] ", path)
		## SHOT_CLICK_SUMMON=1: 点效果文案里第一个召唤物名字(11-27 名字链接), 拍跳过去的角色页
		if OS.get_environment("SHOT_CLICK_SUMMON") == "1":
			var re := RegEx.create_from_string("\\[url=summon:([a-z_]+)\\]")
			for rt in c.find_children("*", "RichTextLabel", true, false):
				if (rt as Node).has_meta("codex_eq_effect"):
					var m := re.search((rt as RichTextLabel).text)
					print("[LINK] ", eid, " → ", m.get_string(1) if m != null else "(无链接)")
					if m != null:
						(rt as RichTextLabel).meta_clicked.emit("summon:" + m.get_string(1))
						await get_tree().create_timer(1.5).timeout
						print("[JUMP] 当前页签=", c.current_tab, " 选中=", str(c._items[c._sel_idx]) if "_sel_idx" in c else "?")
						await RenderingServer.frame_post_draw
						var p2 := "%s/eq_%d_jump.png" % [OS.get_environment("SHOT_DIR"), k]
						get_viewport().get_texture().get_image().save_png(p2)
						print("[SHOT] ", p2)
					break
		k += 1
	get_tree().quit()
