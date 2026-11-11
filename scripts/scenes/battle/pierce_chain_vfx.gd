class_name PierceChainVfx
extends RefCounted
const SpriteArt := preload("res://scripts/util/sprite_art.gd")
## 穿刺铁链演出(近战小将人体浪板; 精英铁锁后续换用)。只管画面, sim 不读: 两端每帧从单位的 pos / height 推。
## 用户 11-11:「不能说直接去把它拉伸吧」「我们的链头应该是那种尖的穿刺，就像一个尖的链头穿刺过敌人的身体」
##   「当他把自己拽过去的时候，这个铁链的尖头在哪里？」; 逐帧参考 docs/studies/20261111-链子穿刺拉人参考-锤石Q与天蝎绳镖逐帧.md:
##   ① 节铺不拉伸: 两种链环交替(a 正面环 / b 侧面环), 按长度增减节数(按需创建)
##   ② 链头(近战 = 手上那个三刺头原图)先飞, 链子从手腕一节节跟出; 飞行时叠一道越飞越小的横向波, 到达那刻绷直
##   ③ 扎穿: 尖端越过目标胸口 pierce_out 米(从背后透出); 拉人时链头钉住不动, 人往前飞 ⇒ 链子从手腕那端自然变短
##   ④ retract(): 撞上前把刺头拔出收回手腕(踩上去那一帧人物图手上已是三刺, 不能同时有两个)
## 链节 / 链头是一节节 Sprite3D(直播录得进流), 链节带 rope_f 标记(0 = 手, 1 = 链头; verify_minion_pull_speed 数它)。
## 补间走 battle._reg_tween()(跟 sim 步走, 与拉人位移同一个钟)。

const WAVE_AMP := 0.15        # 飞行时波浪最大振幅(米)。11-11 实录: 0.45 时链环被甩散、看着不连在手上 ⇒ 0.15
const WAVE_CYCLES := 1.6      # 整条链上同时有几个波
const WAVE_SPEED := 9.0       # 波往链头传的速度(相位 / 秒)
const OVERLAP_PX := 2.0       # 相邻两节压几像素(首尾相接)
const MAX_LINKS := 400        # 射程 2000 码 ≈ 48 米 / 每节 0.15 米 ≈ 320 节
const PRE_SAG := 0.25         # 出手前那节链的下垂(米): 中间往下坠, 碰到地面就平躺(不是一根硬棍)
const GROUND_Y := 0.05        # 链节最低贴到离地多少米(再低会被地面挡掉半截)

var battle
var _from: Callable           # () -> Vector3 手腕世界坐标
var _to: Callable             # () -> Vector3 目标胸口世界坐标
var _fly_sec := 0.1
var _px := 0.015
var _pierce := 0.6
var _links: Array = []
var _head: Sprite3D = null
var _tex: Array = []
var _done := false
var _t := 0.0
var _tick_t := 0.0             # 补间最近一次给的时刻(画面阶段重摆用同一个时刻)
var _closing := false          # 收尾中: 剩下的链子正收回手上
var _ret_t0 := -1.0           # 开始收回的时刻(_t 口径); < 0 = 没在收
var _ret_sec := 0.1
## 出手前阶段(精英铁锁后甩, 11-11): _pre 秒内链头拖在 _pre_tip(身后地面), 链子一头连 _pre_hand; 之后照常飞
var _pre := 0.0
var _pre_hand: Callable
var _pre_tip: Callable


## kind = 贴图前缀(<kind>-link-a.png / -link-b.png / -head.png); px_m = 每像素米数(与人物图同一个, 不出现粗细两种像素);
## head_left = 链头图的尖朝左(近战三刺头原图朝左)⇒ 翻过来; fly_sec 链头飞到目标的秒数; life_sec 兜底寿命。
static func fire(b, kind: String, px_m: float, head_left: bool, from_fn: Callable, to_fn: Callable, fly_sec: float, pierce_out: float, life_sec: float,
		pre_sec: float = 0.0, pre_hand: Callable = Callable(), pre_tip: Callable = Callable()) -> PierceChainVfx:
	var c := PierceChainVfx.new()
	c._pre = pre_sec if pre_hand.is_valid() and pre_tip.is_valid() else 0.0
	c._pre_hand = pre_hand
	c._pre_tip = pre_tip
	c.battle = b
	c._from = from_fn
	c._to = to_fn
	c._fly_sec = maxf(0.02, fly_sec)
	c._px = px_m
	c._pierce = pierce_out
	var ta: Texture2D = load("res://assets/sprites/vfx/%s-link-a.png" % kind)
	var tb: Texture2D = load("res://assets/sprites/vfx/%s-link-b.png" % kind)
	var th: Texture2D = load("res://assets/sprites/vfx/%s-head.png" % kind)
	if ta == null or tb == null or th == null or b == null or b._world == null:
		c._done = true
		return c
	c._tex = [ta, tb]
	c._head = c._sprite(th)
	c._head.flip_h = head_left
	var tw = b._reg_tween()
	tw.bind_node(c._head)
	tw.tween_method(c._tick, 0.0, life_sec, life_sec)
	tw.tween_callback(c.release)
	c._tick(0.0)
	if not RenderingServer.frame_pre_draw.is_connected(c._on_pre_draw):
		RenderingServer.frame_pre_draw.connect(c._on_pre_draw)
	return c


func _sprite(tex: Texture2D) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 沿屏幕上的链方向手动摆(全朝镜头的公告板会丢掉节点自转)
	s.shaded = false
	s.transparent = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.pixel_size = _px
	battle._world.add_child(s)
	return s


func _link(i: int) -> Sprite3D:
	while _links.size() <= i:
		var lk := _sprite(_tex[_links.size() % 2])
		lk.visible = false
		lk.set_meta("rope_f", 0.0)
		_links.append(lk)
	return _links[i]


## 撞上前把刺头拔出、sec 秒内收回手腕, 收完释放
func retract(sec: float = 0.1) -> void:
	if _done or _ret_t0 >= 0.0:
		return
	_ret_t0 = _t
	_ret_sec = maxf(0.02, sec)


## 每帧: 手腕 → 链头(飞行中按进度、到达后钉在目标上、收回时退回手腕)摆链节
func _tick(t: float) -> void:
	_tick_t = t
	_t = t - _pre                 # 出手时刻起算(retract 记的也是这个口径)
	if _done or not is_instance_valid(_head):
		return
	if _t < 0.0:                  # 出手前: 链头拖在身后地面, 一头连身后的拳头, 不波动
		var q: float = clampf(t / maxf(0.001, _pre), 0.0, 1.0)
		var ph: Vector3 = _pre_hand.call(q)
		var pt: Vector3 = _pre_tip.call(q)
		_lay(ph, pt, 0.0, t, (pt - ph).normalized(), PRE_SAG)
		return
	t = _t
	var a: Vector3 = _from.call()
	var tgt: Vector3 = _to.call()
	var dir: Vector3 = tgt - a
	var full: float = dir.length()
	if full < 0.05:
		return
	dir /= full
	var fly: float = clampf(t / _fly_sec, 0.0, 1.0)
	var tip_end: Vector3 = tgt + dir * _pierce                       # 扎穿后尖端的位置(从背后透出)
	var tip: Vector3 = a + (tip_end - a) * fly
	if _ret_t0 >= 0.0:
		var r: float = clampf((t - _ret_t0) / _ret_sec, 0.0, 1.0)
		tip = tip_end + (a - tip_end) * r
		if r >= 1.0:
			release(0.0)
			return
	_lay(a, tip, WAVE_AMP * (1.0 - fly) * (1.0 - fly), t, dir)   # 越接近目标波越小, 到达那刻 0 = 绷直


## 从手 a 到链头尖 tip 摆一串链节 + 链头(wave = 横向波浪振幅, 米; dir = 手与链头重合时的朝向; sag = 中间下垂米数)
func _lay(a: Vector3, tip: Vector3, wave: float, t: float, dir: Vector3, sag: float = 0.0) -> void:
	var head_len: float = float(_head.texture.get_width()) * _px
	var hd: Vector3 = tip - a
	var hl: float = hd.length()
	if hl < 0.001:
		hd = dir
	else:
		hd /= hl
	var tail: Vector3 = tip - hd * head_len                           # 链头尾端 = 链子末端
	var chain_len: float = maxf(0.0, (tail - a).dot(hd))
	var cb: Basis = battle._vfx.cam_basis()
	var side: Vector3 = cb.z.cross(hd).normalized()
	var step: float = (float(_tex[0].get_width()) - OVERLAP_PX) * _px
	var n: int = mini(MAX_LINKS, int(floor(chain_len / step)))
	## 从链头这端往手这端排: 人往前飞时手这端的节先没(收链)
	for i in range(maxi(n, _links.size())):
		var lk: Sprite3D = _link(i) if i < n else _links[i]
		if not is_instance_valid(lk):
			continue
		if i >= n:
			lk.visible = false
			continue
		var d_from_tail: float = (float(i) + 0.5) * step
		var s: float = clampf(1.0 - d_from_tail / maxf(0.001, chain_len), 0.0, 1.0)   # 0 = 手, 1 = 链头
		var ph: float = TAU * s * WAVE_CYCLES - t * WAVE_SPEED
		var off: float = wave * DetMath.dsin(PI * s) * DetMath.dsin(ph)
		var p: Vector3 = tail - hd * d_from_tail + side * off
		var tan: Vector3 = hd * 0.1 + side * (wave * DetMath.dsin(PI * s) * 0.6 * DetMath.dcos(ph))
		if sag > 0.0:                                                  # 下垂: 中间坠下, 贴地那段平躺
			var sy: float = p.y - sag * DetMath.dsin(PI * s)
			tan.y -= 0.1 * sag * PI * DetMath.dcos(PI * s) / maxf(0.001, chain_len)
			if sy <= GROUND_Y:
				sy = GROUND_Y
				tan.y = 0.0
			p.y = sy
		lk.visible = true
		lk.set_meta("rope_f", s)
		lk.global_position = p
		_orient(lk, p, p + tan)
	_head.global_position = tip - hd * head_len * 0.5
	_head.set_meta("chain_hand", a)                 # 门禁 verify_chain_from_hand 读: 这一刻链子手端在哪
	_orient(_head, a, tip)


## 画面已摆好人物图、开画之前再摆一次(11-11): 手端贴画面上真显示的那一格、那个位置的拳头 ——
##   战斗推进时算的是战斗坐标, 画面按「上一步 ↔ 这一步」插值摆人物图, 被拽飞得快时差一截。无头(不画)时不触发, 推进时那一版就是最终版。
func _on_pre_draw() -> void:
	if _done:
		return
	if not is_instance_valid(battle) or not is_instance_valid(_head):
		release(0.0)
		return
	SpriteArt.render_phase = true
	_tick(_tick_t)
	SpriteArt.render_phase = false


## 精灵沿屏幕上 p0 → p1 的方向摆(镜头基 × 绕视线转)
func _orient(s: Sprite3D, p0: Vector3, p1: Vector3) -> void:
	var cam = battle._cam
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return
	var a2: Vector2 = cam.unproject_position(p1) - cam.unproject_position(p0)
	if a2.length() < 0.01:
		return
	var tf: Transform3D = s.global_transform
	tf.basis = battle._vfx.cam_basis() * Basis(Vector3(0, 0, 1), DetMath.datan2(-a2.y, a2.x))
	s.global_transform = tf


## 拉完 / 作废: 剩下的链子 fade_sec 秒内收回手上再释放(fade_sec = 0 ⇒ 立刻释放)。
## ★11-11 不再原地淡出: 拽人结束时链子常常还没收完, 原地淡出那 0.12 秒链子停着、人在动 ⇒ 脱开拳头(门禁 verify_chain_from_hand 量出 9.9 像素)。
##   收回期间照样每帧(含开画前重摆)贴拳头。
func release(fade_sec: float = 0.12) -> void:
	if _done:
		return
	if fade_sec > 0.0 and is_instance_valid(battle) and is_instance_valid(_head):
		if _closing:
			return
		_closing = true
		if _ret_t0 < 0.0:
			_ret_t0 = maxf(0.0, _t)
			_ret_sec = maxf(0.02, fade_sec)
		var tc = battle._reg_tween()
		tc.bind_node(_head)
		tc.tween_method(_tick, _tick_t, _tick_t + fade_sec + 0.02, fade_sec + 0.02)
		tc.tween_callback(release.bind(0.0))
		return
	_done = true
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)
	for s in _links + [_head]:
		if not is_instance_valid(s):
			continue
		if fade_sec <= 0.0:
			s.queue_free()
			continue
		var tw = battle._reg_tween()
		tw.bind_node(s)
		tw.tween_property(s, "modulate:a", 0.0, fade_sec)
		tw.tween_callback(s.queue_free)
	_links.clear()
