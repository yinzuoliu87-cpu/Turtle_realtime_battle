class_name LightningStormVfx
extends RefCounted
## 闪电龟·雷暴的演出(2026-11-05 重做)。只管画面: 不碰 sim、不用对局随机流、不往单位字典写东西。
## 由来: 用户 11-05 夜「闪电龟的技能清楚，清楚在哪里？你为什么觉得清楚？」—— 实查「风暴云」是技能图标 lightning-2.png(云 + 黄色 ⚡ 符号),
##   落雷是图标 lightning-0.png 竖着放, 爆点是图标 lightning-3.png: 往敌人头上盖表情图标, 不是闪电。
## 参考 LoL 凯南 R(官网演示 0085_R1): 从天上劈下细长、带分叉、白芯蓝边的锯齿闪电, 一闪一灭(两次闪烁), 落点一团白蓝电光。
##   风暴云保留(用户 07-15 定「敌方阵型上空高处的大风暴云下雷」), 但换成真的暗风暴云, 每道雷劈下时云里打一下闪。
## 素材: tools/assetgen/build_lightning_storm.py(lightning-bolt-6.png 六种闪电 / lightning-storm-cloud.png 暗云 + 打闪两格, 硬边像素)。

const BOLT := "res://assets/sprites/vfx/lightning-bolt-6.png"
const CLOUD := "res://assets/sprites/vfx/lightning-storm-cloud.png"
const CLOUD_W := 5.8            # 云宽(世界单位)
static var _rng := RandomNumberGenerator.new()
static var _cloud: Sprite3D = null


## 风暴云(放技能时调): 敌阵上空, 0.22 秒淡入。返回云节点(收尾仍由 battle._barrage_cloud_fade 淡出)。
static func cloud(battle, center: Vector2, h: float) -> Sprite3D:
	var tex: Texture2D = load(CLOUD)
	var s := Sprite3D.new()
	if tex != null:   # 素材没导入时只留一个空节点(收尾的淡出照常), 不报错
		s.texture = tex
		s.hframes = 2
		s.pixel_size = CLOUD_W / float(maxi(1, tex.get_width() / 2))
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.position = battle._world_pos(center, h)
	s.modulate = Color(1, 1, 1, 0.0)
	battle._world.add_child(s)
	var tw = battle._reg_tween().bind_node(s)
	tw.tween_property(s, "modulate:a", 1.0, 0.22)
	_cloud = s
	return s


## 一道落雷: 从云底劈到落点(竖直闪电, 六种随机), 闪两下再消; 落点电光星 + 电火花; 云里打一下闪。
static func bolt(battle, pos2d: Vector2, h: float) -> void:
	var tex: Texture2D = load(BOLT)
	if tex != null:
		var s := Sprite3D.new()
		s.texture = tex
		s.hframes = 6
		s.frame = _rng.randi() % 6
		s.flip_h = _rng.randf() < 0.5
		s.scale = Vector3(1.5, 1.0, 1.0)   # 横向加粗 1.5 倍(实拍 1 倍偏细)
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false; s.transparent = true
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.pixel_size = h / float(maxi(1, tex.get_height()))
		s.position = battle._world_pos(pos2d, h * 0.5)
		battle._world.add_child(s)
		var tw = battle._reg_tween().bind_node(s)
		tw.tween_interval(0.05)                                   # 亮 → 暗一下 → 再亮(真闪电的「回击」闪烁) → 消
		tw.tween_property(s, "modulate:a", 0.25, 0.03)
		tw.tween_property(s, "modulate:a", 1.0, 0.02)
		tw.tween_interval(0.04)
		tw.tween_property(s, "modulate:a", 0.0, 0.12)
		tw.tween_callback(s.queue_free)
	## 落点电光: 四角电光星(白蓝)一下涨开再收
	var st := Sprite3D.new()
	st.texture = VfxTex._make_star_texture()
	st.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	st.shaded = false; st.transparent = true
	st.modulate = Color(0.8, 0.95, 1.0, 1.0)
	st.pixel_size = 0.03
	st.scale = Vector3(0.4, 0.4, 0.4)
	st.position = battle._world_pos(pos2d, 0.35)
	battle._world.add_child(st)
	var ts = battle._reg_tween().bind_node(st)
	ts.tween_property(st, "scale", Vector3(1.5, 1.5, 1.5), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ts.tween_property(st, "modulate:a", 0.0, 0.16)
	ts.tween_callback(st.queue_free)
	BuffVfx.burst(battle, pos2d, Color(0.55, 0.88, 1.0), 6)   # 电火花往上溅
	## 云里打闪: 切到打闪那一格 0.07 秒
	if _cloud != null and is_instance_valid(_cloud) and _cloud.hframes == 2:
		var c := _cloud
		c.frame = 1
		var tc = battle._reg_tween().bind_node(c)
		tc.tween_interval(0.07)
		tc.tween_callback(func() -> void:
			if is_instance_valid(c): c.frame = 0)
