class_name PullRopeVfx
extends RefCounted
## 「射链 → 顺着链子把自己拽过去」的链子演出(近战小将人体浪板 / 精英小将铁锁共用这套做法, 各用各的图)。只管画面, sim 不读。
##
## 用户 11-08:「近战小将的这个动画和特效，我们检查一下…放出那个绳索拉向对面」「精英小将也是的…就要慢慢…飞过去」。
## 逐帧查(11-08): 两个小将的链子都在拉人开始前 / 拉到一半就淡掉了(近战射出 0.42 秒消失、拉人第 1.28 秒才开始;
##   精英链节 0.5 秒淡掉、拉人到 0.66 ~ 1.1 秒才结束), 链子两端也不跟着动 ⇒ 看起来是凭空飞过去。
## 做法: 沿「射出点 → 目标」摆一节节小图(不是每帧现画的线: 直播录不进流, memory fb-no-immediatemesh-vfx-stream),
##   射出时由近到远依次亮起; 拉的途中按拉人进度把已经经过的那几节收掉(reel); 拉完 / 作废时 release。
##   兜底: 每节自带一条「hold_sec 后淡出释放」的补间, 中途换路、单位没了也不会留在场上。
## 补间一律走 battle._reg_tween()(跟 sim 步走, 与拉人那条补间同一个钟, 收链与位移对得上)。


## 沿线摆链节。tex: 链节图(横向一节); thick_px: 链子在场上的粗细(像素码); spacing: 相邻两节间距(码);
## grow_sec: 由近到远亮完的时长; hold_sec: 兜底寿命(超过就自己淡出释放)。返回链节节点数组(由近到远)。
static func shoot(battle, from2d: Vector2, fromh: float, to2d: Vector2, toh: float, tex: Texture2D,
		thick_px: float, spacing: float, grow_sec: float, hold_sec: float, max_links: int = 60) -> Array:
	var out: Array = []
	if tex == null or battle == null:
		return out
	var d: float = DetMath.dist(from2d, to2d)
	var n: int = clampi(int(ceil(d / maxf(1.0, spacing))), 3, max_links)
	var ang: float = DetMath.datan2(-(to2d - from2d).y, (to2d - from2d).x)
	var ps: float = (thick_px * battle.WS) / float(maxi(1, tex.get_height()))
	var sbasis = _screen_basis(battle, from2d, fromh, to2d, toh)   # 链节沿屏幕上的链方向摆(全朝镜头的公告板会丢掉节点自转, 11-11 查出斜链每节都是水平的)
	for i in range(n):
		var f: float = (float(i) + 0.5) / float(n)
		var lk := Sprite3D.new()
		lk.texture = tex
		lk.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lk.shaded = false
		lk.transparent = true
		lk.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		lk.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		lk.pixel_size = ps
		lk.position = battle._world_pos(DetMath.vlerp(from2d, to2d, f), lerpf(fromh, toh, f))
		lk.rotation.z = ang
		lk.modulate = Color(1, 1, 1, 0.0)
		lk.set_meta("rope_f", f)
		battle._world.add_child(lk)
		if sbasis is Basis:
			lk.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			var tf: Transform3D = lk.global_transform
			tf.basis = sbasis
			lk.global_transform = tf
		var tw = battle._reg_tween()
		tw.bind_node(lk)                 # 节点先被 release 释放时, 这条兜底补间跟着失效(CLAUDE.md §6)
		tw.tween_interval(grow_sec * f)
		tw.tween_property(lk, "modulate:a", 1.0, 0.03)
		tw.tween_interval(maxf(0.0, hold_sec - grow_sec * f))
		tw.tween_property(lk, "modulate:a", 0.0, 0.12)
		tw.tween_callback(lk.queue_free)
		out.append(lk)
	return out


## 链子在屏幕上的朝向: 镜头基 × 绕视线转到「射出点 → 目标」的屏幕角(镜头还没好 ⇒ null, 退回朝镜头的公告板)
static func _screen_basis(battle, from2d: Vector2, fromh: float, to2d: Vector2, toh: float):
	var cam = battle._cam
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return null
	var a2: Vector2 = cam.unproject_position(battle._world_pos(to2d, toh)) - cam.unproject_position(battle._world_pos(from2d, fromh))
	if DetMath.vlen(a2) < 0.5:
		return null
	return battle._vfx.cam_basis() * Basis(Vector3(0, 0, 1), DetMath.datan2(-a2.y, a2.x))


## 拉人进度 frac(0 = 还在射出点, 1 = 到目标): 已经经过的链节收掉(由近到远)。
static func reel(links: Array, frac: float) -> void:
	for lk in links:
		if is_instance_valid(lk) and float(lk.get_meta("rope_f", 1.0)) <= frac:
			lk.visible = false


## 拉完 / 作废: 剩下的链节一起淡出释放。
static func release(battle, links: Array, fade_sec: float = 0.12) -> void:
	for lk in links:
		if not is_instance_valid(lk):
			continue
		var tw = battle._reg_tween()
		tw.bind_node(lk)
		tw.tween_property(lk, "modulate:a", 0.0, fade_sec)
		tw.tween_callback(lk.queue_free)
	links.clear()
