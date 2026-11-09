extends Node
## verify_pet_ui_idle.gd — 界面立绘逐帧待机(2026-11-09 用户「变脸龟没有待机动画吗」)。
##
## 由来: 28 只里只有变脸龟在 pets.json 没登记逐帧待机图, 选龟卡 / 选龟详情 / 图鉴 / 统领卡 / 冠军页只能退回整张缩放「呼吸」;
##   战斗里它其实有两套 8 帧待机。修法 = scripts/gamedata/pet_ui_idle.gd 只给界面换成那两套(帧表 tools/assetgen/build_two_head_ui_idle.py)。
## 判据量在【真建出来的界面节点】上, 跑一段时间看帧有没有在换(不数我插的调用):
##   ① 分母 28 只; 统领卡立绘(UnitCardArt.portrait_anim, 选龟页网格 / 已选槽 / 决赛日卡)1.5 秒里换过 ≥ 3 个不同帧 —— 28 只全都是
##   ② 选龟详情大立绘(真开选龟页点变脸龟详情; detail_panel 先过 PetUiIdle 再交 _apply_pet_idle_texture)1.5 秒里换过 ≥ 3 帧
##   ③ 图鉴近战形态页取的是近战那套; 冠军页(ChampionUi.body)8 帧
##   ④ 界面那套第 0 帧的不透明部分逐像素 = 原静态立绘(界面大小 / 站位不变)
##   ⑤ 战斗不受影响: DataRegistry 里变脸龟仍是静态图、没有 sprite{}; 其余 27 只 PetUiIdle.of 原样返回同一个字典
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_pet_ui_idle.tscn

const TS := "res://scenes/TeamSelect.tscn"
const FormVariants := preload("res://scripts/scenes/codex/form_variants.gd")
const SAMPLE := 90                 # 1.5 秒(60 帧 / 秒)

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 跑 SAMPLE 帧, 数 AtlasTexture 取到过几个不同的区域(= 换过几帧)
func _distinct_regions(tr: TextureRect) -> int:
	var seen := {}
	for _i in range(SAMPLE):
		await get_tree().process_frame
		if is_instance_valid(tr) and tr.texture is AtlasTexture:
			seen[(tr.texture as AtlasTexture).region.position] = true
	return seen.size()


func _used_img(path: String, rect: Rect2i) -> Image:
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var sub := img.get_region(rect)
	return sub.get_region(sub.get_used_rect())


func _ready() -> void:
	await get_tree().process_frame
	var host := Control.new()
	host.size = Vector2(1600, 900)
	add_child(host)

	## ① 统领卡立绘: 28 只全都逐帧
	var pids: Array = []
	for p in DataRegistry.all_pets:
		pids.append(str((p as Dictionary).get("id", "")))
	_ok("★分母: 28 只龟", pids.size() == 28, "%d 只" % pids.size())
	var still: Array = []
	var th_path := ""
	for pid in pids:
		var por: Control = UnitCardArt.portrait_anim(pid, Rect2(Vector2(8, 4), Vector2(134, 136)), 140.0, true)
		if por == null:
			still.append(pid + "(没建出来)")
			continue
		host.add_child(por)
		var body := por.get_node_or_null("Body") as TextureRect
		var n: int = await _distinct_regions(body) if body != null else 0
		if n < 3:
			still.append("%s(%d 帧)" % [pid, n])
		if pid == "two_head" and body != null and body.texture is AtlasTexture:
			th_path = (body.texture as AtlasTexture).atlas.resource_path
		por.queue_free()
	_ok("★★① 统领卡立绘 28 只在 1.5 秒里都换过 ≥ 3 帧(逐帧待机, 不是整张缩放呼吸)", pids.size() == 28 and still.is_empty(), "不动的: %s" % str(still))
	_ok("★① 变脸龟统领卡取的是界面那套远程待机", th_path.ends_with(str(PetUiIdle.BY_IMG["pets/two_head.png"])), th_path)

	## ② 选龟详情大立绘: 真开选龟页、点变脸龟的详情, 量详情里那张大立绘
	host.queue_free()
	var ts = (load(TS) as PackedScene).instantiate()
	add_child(ts)
	for _i in range(20):
		await get_tree().process_frame
	ts._set_detail_pet("two_head")
	for _i in range(3):
		await get_tree().process_frame
	var big: TextureRect = null
	for n in (ts._dt_portrait as Node).find_children("*", "TextureRect", true, false):
		var t: Texture2D = (n as TextureRect).texture
		if t is AtlasTexture and (t as AtlasTexture).atlas != null and str((t as AtlasTexture).atlas.resource_path).contains("two_head"):
			big = n
	var nd: int = await _distinct_regions(big) if big != null else 0
	_ok("★★② 选龟详情大立绘: 变脸龟 1.5 秒里换过 ≥ 3 帧", big != null and nd >= 3,
		"%s · %d 帧" % [str((big.texture as AtlasTexture).atlas.resource_path) if big != null else "没找到逐帧立绘", nd])
	ts.queue_free()
	for _i in range(3):
		await get_tree().process_frame
	host = Control.new()
	host.size = Vector2(1600, 900)
	add_child(host)

	## ③ 图鉴近战形态页 / 冠军页
	var th: Dictionary = DataRegistry.pet_by_id["two_head"]
	var melee: Dictionary = PetUiIdle.of(FormVariants.portrait_pet(th, true))
	_ok("★③ 图鉴近战形态页取近战那套待机(8 帧)", str(melee.get("img", "")) == str(PetUiIdle.BY_IMG["pets/two_head_melee.png"])
		and int((melee.get("sprite", {}) as Dictionary).get("frames", 0)) == 8, str(melee.get("img", "")))
	var holder: Control = ChampionUi.body(host, Vector2(400, 400), 100.0, "two_head")
	var spr := holder.get_node_or_null("Body") as Sprite2D if holder != null else null
	_ok("★③ 冠军页立绘 8 帧(ChampionUi.body)", holder != null and int(holder.get_meta("idle_n", 0)) == 8 and spr != null and spr.hframes == 8,
		"idle_n %d" % (int(holder.get_meta("idle_n", 0)) if holder != null else -1))

	## ④ 第 0 帧不透明部分 = 原静态立绘
	for pair in [["pets/two_head.png", "远程"], ["pets/two_head_melee.png", "近战"]]:
		var ui_path: String = "res://assets/sprites/" + str(PetUiIdle.BY_IMG[pair[0]])
		var sp: Dictionary = PetUiIdle.SPRITE
		var a := _used_img(ui_path, Rect2i(0, 0, int(sp["frameW"]), int(sp["frameH"])))
		var st_tex := load("res://assets/sprites/" + str(pair[0])) as Texture2D
		var b := _used_img("res://assets/sprites/" + str(pair[0]), Rect2i(Vector2i.ZERO, Vector2i(st_tex.get_size())))
		var same: bool = a.get_size() == b.get_size()
		if same:
			for y in range(a.get_height()):
				for x in range(a.get_width()):
					if a.get_pixel(x, y) != b.get_pixel(x, y):
						same = false
		_ok("★★④ %s: 界面待机第 0 帧不透明部分逐像素 = 原静态立绘(大小 / 站位不变)" % pair[1], same, "%s vs %s" % [str(a.get_size()), str(b.get_size())])
		var t := load(ui_path) as Texture2D
		_ok("★④ %s: 帧表 8 帧 × %d×%d" % [pair[1], int(sp["frameW"]), int(sp["frameH"])],
			t.get_width() == 8 * int(sp["frameW"]) and t.get_height() == int(sp["frameH"]), str(t.get_size()))

	## ⑤ 战斗不受影响
	_ok("★★⑤ 战斗读的 pets.json 不动: 变脸龟仍是静态图、没有 sprite{}", str(th.get("img", "")) == "pets/two_head.png" and not th.has("sprite"))
	var changed: Array = []
	for pid in pids:
		if pid != "two_head" and not is_same(PetUiIdle.of(DataRegistry.pet_by_id[pid]), DataRegistry.pet_by_id[pid]):
			changed.append(pid)
	_ok("★⑤ 其余 27 只 PetUiIdle.of 原样返回(只补没登记逐帧图的)", changed.is_empty(), str(changed))

	print("verify_pet_ui_idle: %d / %d" % [_n - _fail, _n])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
