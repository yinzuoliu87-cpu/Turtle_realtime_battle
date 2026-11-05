class_name BuffVfx
extends RefCounted
## 增益类技能的通用演出(2026-11-05)。
## 由来: 11-05 审核片逐段审 —— 烈焰暴走 / 强化随从 / 虚化 / 朗姆酒 / 灵魂打击 / 隐蔽 / 岩石护盾 / 坚不可摧 这些「给自己或队友加东西」的技能,
##   放出后只有脚下一个小环, 持续期间身上什么都看不出来, 和普攻分不开(方案书 20261104b R4「技能要比普攻更大更亮」)。
## 做法(TFT / LoL 增益的通行读法: 放出那一下一次性爆亮 + 持续期间身上一直有东西在动, 一眼看出「他身上挂着增益」):
##   ① 放出: 脚下一个地面环(共享环, 已烤好) + 身上往上喷一把主题色像素火星(峰值)
##   ② 持续: 每 MOTE_GAP 秒从脚边飘起一颗火星, 0.6 秒升高淡出(持续层: 小、稀、不刺眼)
## ★像素画: 火星用 6 像素实心块(_make_pixel_block_tex, 硬边), 不用软光圆(用户否过「程序生成的圆」)。
## ★随机数: 自己的 RandomNumberGenerator, 只给演出用, 不碰对局随机流 / 演出随机流(_juice_rng)。

const MOTE_GAP := 0.11          # 持续期火星间隔(秒)·0.16 实拍太稀
const BURST_MOTES := 16         # 放出瞬间那一把
const MOTE_PS := 0.030          # 小火星 pixel_size(6 像素块 ≈ 7.5 码; 0.020 实拍只有 5 屏幕像素, 看不清)
const MOTE_PS_BIG := 0.044      # 亮火星(约三成, 往白里提)

static var _rng := RandomNumberGenerator.new()

## col: 主题色; dur: 持续秒数(≤0 = 只有放出那一下); ring_r: 地面环半径(≤0 不画环)
static func activate(battle, u: Dictionary, col: Color, dur: float, ring_r: float = 62.0) -> void:
	if not u.has("pos"):
		return
	if ring_r > 0.0:
		battle._skill_ring(u["pos"], Color(col.r, col.g, col.b, 0.75), ring_r)
	for i in range(BURST_MOTES):
		_mote(battle, u["pos"], col, true)
	if dur <= 0.0:
		return
	var holder := Node3D.new()
	battle._world.add_child(holder)
	var n: int = maxi(1, int(dur / MOTE_GAP))
	var tw = battle._reg_tween().bind_node(holder)
	tw.set_loops(n)
	tw.tween_interval(MOTE_GAP)
	tw.tween_callback(func() -> void:
		if u.get("alive", false) and u.has("pos"):
			_mote(battle, u["pos"], col, false))
	var tk = battle._reg_tween().bind_node(holder)
	tk.tween_interval(dur)
	tk.tween_callback(holder.queue_free)

static func _mote(battle, pos2d: Vector2, col: Color, burst: bool) -> void:
	var s := Sprite3D.new()
	s.texture = VfxTex._make_pixel_block_tex()
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false; s.transparent = true
	var big: bool = _rng.randf() < 0.3
	s.pixel_size = MOTE_PS_BIG if big else MOTE_PS
	var c: Color = col.lerp(Color(1, 1, 1), 0.55) if big else col
	c.a = 1.0
	s.modulate = c
	var spread: float = 34.0 if burst else 26.0
	var off := Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread * 0.4, spread * 0.4))
	var h0: float = _rng.randf_range(0.1, 0.5) if burst else _rng.randf_range(0.05, 0.3)
	s.position = battle._world_pos(pos2d + off, h0)
	battle._world.add_child(s)
	var rise: float = _rng.randf_range(1.0, 1.7) if burst else _rng.randf_range(0.6, 1.0)
	var t: float = _rng.randf_range(0.35, 0.5) if burst else 0.6
	var tw = battle._reg_tween().bind_node(s)
	tw.tween_property(s, "position:y", s.position.y + rise, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(s, "modulate:a", 0.0, t * 0.4).set_delay(t * 0.6)   # 先满亮 60% 再收(不一出生就淡)
	tw.tween_callback(s.queue_free)
