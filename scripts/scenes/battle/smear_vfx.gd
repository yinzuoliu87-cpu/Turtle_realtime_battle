class_name SmearVfx
extends RefCounted
## 弧形刀光(月牙拖影)。2026-11-05 孤注一掷重做 —— 用户:「孤注一掷这个问题是你整个镰刀都是一个平滑运动，这是确定是你学到的东西吗？这个得改呀」。
## 参考 LoL 德莱厄斯 Q 逐帧(docs/studies/20261105-镰刀参考-德莱厄斯Q逐帧.md):
##   挥出后约 0.1 秒扫过并命中(先快后慢); 刀后一条【连续】月牙刀光, 刀头最宽最亮、往后变细变淡; 扫完约 0.2 秒收掉。
##   我们原来是一张镰刀图 0.4 秒匀速转 120°, 每帧留一张分开的红色复制图(梳子状), 伤害数字第 0 帧就跳完 —— 刀和伤害对不上。
## ★画法: 逐帧烤好的帧表(tools/assetgen/build_scythe_smear.py), 贴地躺平, pixel_size 恒定只切帧, 帧推进挂 _anim_fx 走游戏时钟。
##   第一版用 ImmediateMesh 每帧现画 —— 直播(S3)录不进流(verify_stream_coverage「新出处」, CI 11-05 红) ⇒ 换成帧表。
## 只是演出: 不读写任何对局状态。

## 先快后慢(三次缓出): 前一半时间就扫过约 87% 的角度。帧表与镰刀转动用同一条曲线。
static func ease_out(x: float) -> float:
	var c: float = clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c) * (1.0 - c)

## 缓出的反函数: 刀头扫到进度 s(0~1) 的那一刻 / 扫掠时长。用来让命中斩痕正好落在刀经过敌人的那一帧。
static func time_at(s: float) -> float:
	return 1.0 - pow(1.0 - clampf(s, 0.0, 1.0), 1.0 / 3.0)

## 播一张月牙帧表: 画布中心 = origin2d, 画布 +X = base_ang 方向, 外缘(画布半径 - 2 像素) = r_out 码。
static func play_sheet(battle, path: String, frames: int, fps: float, origin2d: Vector2, base_ang: float, r_out: float, height: float = 0.06) -> Sprite3D:
	var tex: Texture2D = battle._sheet(path)
	if tex == null:
		return null
	var cell: float = float(tex.get_height())
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = frames
	s.frame = 0
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = (r_out * battle.WS) / (cell * 0.5 - 2.0)
	s.position = battle._world_pos(origin2d, height)
	s.rotation = Vector3(0.0, -base_ang, 0.0)
	battle._world.add_child(s)
	battle._anim_fx.append({"spr": s, "t0": battle._t, "fps": fps, "n": frames})
	return s
