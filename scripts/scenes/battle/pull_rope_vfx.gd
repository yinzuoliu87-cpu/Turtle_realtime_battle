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
		var tw = battle._reg_tween()
		tw.bind_node(lk)                 # 节点先被 release 释放时, 这条兜底补间跟着失效(CLAUDE.md §6)
		tw.tween_interval(grow_sec * f)
		tw.tween_property(lk, "modulate:a", 1.0, 0.03)
		tw.tween_interval(maxf(0.0, hold_sec - grow_sec * f))
		tw.tween_property(lk, "modulate:a", 0.0, 0.12)
		tw.tween_callback(lk.queue_free)
		out.append(lk)
	return out


## 精英小将铁锁的链节(原写在主文件 _tick_elite_whip 里, 11-08 搬来; 摆法逐字未改: 每 55 码一节、5 ~ 14 节、20 码高、
## 每节晚 0.01 秒亮起)。只改了寿命: 原来亮起后只留 0.3 秒(拉人到一半链子就没了), 现在留 hold_sec, 途中由 reel 逐段收。
static func elite_links(battle, from5: Vector2, to5: Vector2, ctex: Texture2D, hold_sec: float) -> Array:
	var out: Array = []
	if ctex == null:
		return out
	var d: float = DetMath.dist(to5, from5)
	var links: int = clampi(int(d / 55.0), 5, 14)
	for i in range(links):
		var lp: Vector2 = DetMath.vlerp(from5, to5, float(i + 1) / float(links))
		var lk := Sprite3D.new()
		lk.texture = ctex
		lk.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lk.shaded = false; lk.transparent = true
		lk.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		lk.pixel_size = (20.0 * battle.WS) / float(maxi(1, ctex.get_height()))
		lk.position = battle._world_pos(lp, 0.8)
		lk.rotation.z = DetMath.datan2(-(to5 - from5).y, (to5 - from5).x)
		lk.modulate = Color(1, 1, 1, 0.0)
		lk.set_meta("rope_f", float(i + 1) / float(links))
		battle._world.add_child(lk)
		out.append(lk)
		var lt = battle._reg_tween()
		lt.bind_node(lk)
		lt.tween_interval(0.01 * float(i))
		lt.tween_property(lk, "modulate:a", 1.0, 0.03)
		lt.tween_interval(maxf(0.0, hold_sec - 0.01 * float(i)))
		lt.tween_property(lk, "modulate:a", 0.0, 0.1)
		lt.tween_callback(lk.queue_free)
	return out


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
