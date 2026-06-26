extends Node
## PreloadCache — 资源预热 (1:1 PoC BootScene 预载全资源, 消除切场景卡顿 #13)。
##   病根: 进选龟同步 load() 28 立绘 / 进战斗 load 技能图标+sprite → 冷加载卡帧。
##   Godot load() 默认缓存(CACHE_MODE_REUSE): 启动后台 threaded 预载入缓存后,
##   各场景的 load() 命中缓存 = 不再冷加载卡帧。headless 自测不渲染, 跳过。

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# 让首屏菜单先渲两帧, 再在后台预热(不抢首屏)
	await get_tree().process_frame
	await get_tree().process_frame
	_warm_cache()


## 缩放好的 512² menu-bg-tile 纹理 — resize 只做一次并缓存.
##   病根: 10 个场景每次进入都 load(1946²).resize(512²,LANCZOS) 在主线程, 几十ms → 切场景卡顿(用户报"进图鉴/其它页卡一下").
##   解法: 全局缓存一次缩放结果, 各场景复用 PreloadCache.menu_bg_tile_tex() 不再重缩.
var _menu_bg_tex: ImageTexture = null
func menu_bg_tile_tex() -> ImageTexture:
	if _menu_bg_tex == null:
		if not ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
			return null
		var ti: Image = load("res://assets/sprites/menu/menu-bg-tile.png").get_image()
		ti.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		_menu_bg_tex = ImageTexture.create_from_image(ti)
	return _menu_bg_tex


func _warm_cache() -> void:
	if not is_instance_valid(DataRegistry) or DataRegistry.all_pets.is_empty():
		return
	menu_bg_tile_tex()   # 启动时预缩一次(菜单空闲期付掉), 之后各场景复用无卡顿
	var seen: Dictionary = {}   # 当 set 用, 去重
	for pet in DataRegistry.all_pets:
		var id: String = str(pet.get("id", ""))
		seen["res://assets/sprites/avatars/%s.png" % id] = true
		# 全身立绘 (图鉴详情 _add_pet_portrait 用大 spritesheet; 原只 warm 头像 → 点龟冷加载大 sheet 卡一下, 用户报)
		var pimg: String = str(pet.get("img", ""))
		if pimg.ends_with(".png"):
			seen["res://assets/sprites/%s" % pimg] = true
		# 羁绊标签 (图鉴龟详情 tag 区 + 羁绊 tab + 选龟 chip)
		var tags = pet.get("tags", [])
		if tags is Array:
			for tg in tags:
				seen["res://assets/sprites/tags/%s标签.png" % str(tg)] = true
		var pool = pet.get("skillPool", [])
		if pool is Array:
			for sk in pool:
				if sk is Dictionary:
					var ic: String = str(sk.get("icon", ""))
					if ic.ends_with(".png"):
						seen["res://assets/sprites/%s" % ic] = true
		# 被动图标
		var p = pet.get("passive", null)
		if p is Dictionary:
			var pic: String = DataRegistry.passive_icons.get(p.get("type", ""), "")
			if pic.ends_with(".png"):
				seen["res://assets/sprites/%s" % pic] = true
	# 装备图标 (图鉴装备详情/装备格; 原点装备冷加载 120px 图卡一下, 用户报)
	for eq in DataRegistry.all_equipment:
		var eic: String = str(eq.get("icon", ""))
		if eic.ends_with(".png"):
			seen["res://assets/sprites/%s" % eic] = true
	# 属性图标 (图鉴/信息面板 stat 行)
	for stk in ["hp", "atk", "def", "mr"]:
		seen["res://assets/sprites/stats/%s-icon.png" % stk] = true
	seen["res://assets/sprites/bg/select-bg.png"] = true
	# 后台 threaded 请求(不阻塞; 缓存随后填充)
	for path in seen:
		if ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path)
