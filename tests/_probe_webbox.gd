extends Node
## _probe_webbox.gd — 各屏幕的【网页盒】与【九宫格贴图】清点(2026-08-17, 只量不判)
##
## 由来: 战斗信息面板今晚全部换成金属九宫格框了。要问一句 ——
## **别的屏幕呢?** 如果只有战斗面板是金属、其余全是网页盒, 那是我制造的新不一致。
## 先量再说, 不改任何东西。
##
## 判据(与 verify_info_panel_fits 同一条, 免得两套口径):
##   网页盒 = StyleBoxFlat 且【四边都有边框】且【底色半透明(a<0.95)】
##   —— 单边描边(比如血条填充的顶部高光)不算, 不透明的实心盒也不算。
##
## 跑法: <godot> --headless --path . res://tests/_probe_webbox.tscn --quit-after 12000

const SCENES: Array = [
	"res://scenes/MainMenu.tscn",
	"res://scenes/Shop.tscn",
	"res://scenes/Inventory.tscn",
	"res://scenes/Codex.tscn",
	"res://scenes/TeamSelect.tscn",
	"res://scenes/Settings.tscn",
	"res://scenes/Record.tscn",
]


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	print("=== 各屏幕: 网页盒 / 圆角盒 / 九宫格贴图 ===")
	for path in SCENES:
		if not ResourceLoader.exists(str(path)):
			print("  !! 场景不存在: %s" % path)
			continue
		var ps: PackedScene = load(str(path))
		if ps == null:
			continue
		var inst = ps.instantiate()
		add_child(inst)
		for _i in range(12):
			await get_tree().process_frame
		var n_box := 0      # 扫到的 stylebox 总数(分母)
		var n_web := 0      # 网页盒
		var n_round := 0    # 圆角盒
		var texs: Dictionary = {}
		var st: Array = [inst]
		while not st.is_empty():
			var n: Node = st.pop_back()
			if n is NinePatchRect and (n as NinePatchRect).texture != null:
				texs[(n as NinePatchRect).texture.resource_path.get_file()] = true
			if n is Control:
				for slot in ["panel", "normal", "background", "fill"]:
					if not (n as Control).has_theme_stylebox_override(slot):
						continue
					var sb = (n as Control).get_theme_stylebox(slot)
					n_box += 1
					if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
						texs[(sb as StyleBoxTexture).texture.resource_path.get_file()] = true
					elif sb is StyleBoxFlat:
						var f := sb as StyleBoxFlat
						if f.corner_radius_top_left > 0:
							n_round += 1
						if f.border_width_top > 0 and f.border_width_bottom > 0 \
								and f.border_width_left > 0 and f.border_width_right > 0 \
								and f.bg_color.a < 0.95:
							n_web += 1
			for c in n.get_children():
				st.append(c)
		print("  %-18s stylebox %3d 个 · 网页盒 %2d · 圆角盒 %2d · 九宫格贴图 %d 种 %s"
			% [str(path).get_file(), n_box, n_web, n_round, texs.size(), str(texs.keys()).substr(0, 60)])
		inst.queue_free()
		await get_tree().process_frame
	print("PROBE DONE")
	get_tree().quit(0)
