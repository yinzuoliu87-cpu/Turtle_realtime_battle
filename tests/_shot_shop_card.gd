extends Node
## DEV 工具(不是门禁): 商店说明卡实拍 —— 把指定装备摆上货架第 0 格、点开, 存图。
## SHOT_CLICK_SUMMON=1 再点说明里第一个召唤物名字, 拍换出来的召唤物小卡(11-27)。
## 跑法(窗口只开右屏):
##   SHOT_DIR=<目录> SHOT_IDS=p2eq_096,p2eq_084,p2eq_004 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " APPDATA=<单独目录> \
##   WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_shop_card.tscn
## ★不能 --headless: 无头拿不到视口纹理。


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await _frames(2)
	GameState.test_mode = true
	GameState.meta_deepsea_coins = 99
	var dir := OS.get_environment("SHOT_DIR")
	## SHOT_IDS=all: 全部装备逐件过一遍, 只数哪几件的说明卡要出滚动条(不存图, 可 --headless)
	var ids: Array = Array(OS.get_environment("SHOT_IDS").split(","))
	var count_only: bool = ids == ["all"]
	if count_only:
		ids = DataRegistry.phase2_equipment_by_id.keys()
	var scrolled: Array = []
	for eid in ids:
		var sc = load("res://scenes/Shop.tscn").instantiate()
		add_child(sc)
		var _w := 0
		while (sc._offer as Array).is_empty() and _w < 180:
			await get_tree().process_frame
			_w += 1
		await _frames(10)
		var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
		if (sc._offer as Array).is_empty():
			sc._offer.append(edef)
		else:
			sc._offer[0] = edef
		sc._sel = 0
		sc._rebuild()
		await _frames(30)
		var scroll = sc.find_child("CardBodyScroll", true, false)
		if count_only:
			if scroll != null:
				scrolled.append("%s %s" % [eid, str(edef.get("name", ""))])
		else:
			await RenderingServer.frame_post_draw
			var path := "%s/shop_%s.png" % [dir, eid]
			get_viewport().get_texture().get_image().save_png(path)
			print("[SHOT] ", path, "  滚动框=", scroll != null)
			## SHOT_CLICK_SUMMON=1: 再点说明里第一个召唤物名字(图鉴角色栏 11-27 名字链接), 拍换出来的召唤物小卡
			if OS.get_environment("SHOT_CLICK_SUMMON") == "1":
				var body = (sc._insp.live as Dictionary).get("body", null)
				var m := RegEx.create_from_string("\\[url=summon:([a-z_]+)\\]").search(str(body.text) if body is RichTextLabel else "")
				print("[LINK] ", eid, " → ", m.get_string(1) if m != null else "(无链接)")
				if m != null:
					(body as RichTextLabel).meta_clicked.emit("summon:" + m.get_string(1))
					await _frames(20)
					await RenderingServer.frame_post_draw
					var p2 := "%s/shop_%s_summon.png" % [dir, eid]
					get_viewport().get_texture().get_image().save_png(p2)
					print("[SHOT] ", p2)
		sc.queue_free()
		await _frames(3)
	if count_only:
		print("[COUNT] 共 %d 件, 要滚动的 %d 件: %s" % [ids.size(), scrolled.size(), str(scrolled)])
	get_tree().quit()
