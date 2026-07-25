class_name BambooSystem
extends RefCounted
## 竹龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

# 竹叶强化命中: 敌人身上爆一下大淡绿命中特效(≈上半身大小·一下即散·用户2026-07-11).
func _bamboo_hit_splash(tgt: Dictionary) -> void:
	var tex = VfxTex._make_glow_texture()
	var tw = float(maxi(1, int(tex.get_width())))
	var big: float = (170.0 * battle.WS) / tw          # "很大"≈上半身大小(可调)
	var sp = Sprite3D.new()
	sp.texture = tex
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false; sp.transparent = true
	sp.modulate = Color(0.6, 1.0, 0.62, 0.0)    # 淡绿
	sp.pixel_size = big * 0.55
	sp.position = battle._world_pos(tgt["pos"], float(tgt.get("height", 0.0)) + 0.5)
	battle._world.add_child(sp)
	var t = battle._reg_tween(); t.set_parallel(true)
	t.tween_property(sp, "pixel_size", big, 0.09).set_ease(Tween.EASE_OUT)   # 爆开
	t.tween_property(sp, "modulate:a", 0.9, 0.05)
	t.chain().tween_property(sp, "modulate:a", 0.0, 0.2)                     # 即散
	t.chain().tween_callback(sp.queue_free)

# 全局: 被减速单位行走留短暂泥印(棕色泥渍, 贴地)
func _bamboo_orb_step(t: float, orb: Sprite3D, from_pos: Vector2, to_pos: Vector2, nframes: int, trail: Array) -> void:
	if not is_instance_valid(orb):
		return
	var base: Vector2 = from_pos.lerp(to_pos, t)
	var h: float = 1.0 + 1.5 * 4.0 * t * (1.0 - t)   # 抛物高度弧 (峰+1.5m)
	orb.position = battle._world_pos(base, h)
	if nframes > 1:
		orb.frame = int(t * float(nframes) * 2.0) % nframes
	if t > 0.05 and t < 0.93:
		var seg: int = int(t / 0.046)
		if seg > int(trail[0]):
			trail[0] = seg
			_bamboo_trail_dot(base, h)

func _bamboo_trail_dot(pos2d: Vector2, h: float) -> void:
	var dot = Sprite3D.new()
	dot.texture = VfxTex._make_glow_texture()
	dot.modulate = Color(0.49, 1.0, 0.7, 0.7)   # #7dffb3 绿
	dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dot.shaded = false
	dot.transparent = true
	dot.pixel_size = 0.006
	dot.position = battle._world_pos(pos2d, h)
	battle._world.add_child(dot)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(dot, "modulate:a", 0.0, 0.42)
	tw.tween_property(dot, "scale", Vector3.ONE * 0.3, 0.42)
	tw.chain().tween_callback(dot.queue_free)

func _bamboo_burst_step(t: float, b: Sprite3D, nframes: int) -> void:
	if not is_instance_valid(b):
		return
	if nframes > 1:
		b.frame = mini(nframes - 1, int(t * float(nframes)))
	b.modulate.a = 1.0 - maxf(0.0, (t - 0.6) / 0.4)

# 治疗绿光 (港回合制 _play_heal_glow): 绿光球从身体升起淡出 + 绿脉冲贴地环