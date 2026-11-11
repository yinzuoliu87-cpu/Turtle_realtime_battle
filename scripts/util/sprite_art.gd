extends RefCounted
## 人物图像素 ↔ 世界坐标(2026-11-11)。
## 用户 11-11:「他射出这个锁链的时候，请问锁链有…从手上射出来吗？你自己没看吗？」——
##   原来链子手端按「沿地面朝目标前推 N 码、离地 M 米」算, 但人物图是正对镜头的公告板: 目标在斜下方时, 世界里的「前方」
##   投到屏幕上是往下, 而图上的拳头是水平伸出去的 ⇒ 链子从拳头下面一截冒出来。改成按人物图当前这一格上拳头那个像素算。
## 用户 11-11:「踩到对面的时候…应该踩在他身上…在他体型的上方」—— 踩人高度 = 目标当前这一格本体顶部。
##
## 公告板精灵: 轴 = 相机的右 / 上; Sprite3D 默认 centered, offset 以像素计、y 向上 ⇒ 帧内第 py 行落在本地 y = offset.y + fh/2 - py;
##   flip_h 绕帧中线左右镜像。帧条按 hframes / vframes 切(单位人物图都是帧条)。
## 无头(裁判机录直播)也读得到贴图像素(11-11 实测 whip.png 2112×192), 两边算出来一样; height 不进逐步指纹
##   (ReplayRecorder.fingerprint 只收 hp / pos / alive / shield / energy), 所以只动画面, 不改对局结果。
## 用法: const SpriteArt := preload("res://scripts/util/sprite_art.gd")(不注册全局类名)

static var _img_cache := {}      # 贴图路径 → Image
static var _top_cache := {}      # "路径#帧" → 本体顶部那一行(帧内坐标)


static func _spr(u: Dictionary) -> Sprite3D:
	var s = u.get("sprite", null)
	if s is Sprite3D and is_instance_valid(s) and (s as Sprite3D).texture != null:
		return s
	return null


## 单位当前这一格上第 (art.x, art.y) 个像素(帧内坐标, 左上角 = 0)在世界里的位置; 没有人物图 ⇒ fallback
static func point(b, u: Dictionary, art: Vector2, fallback: Vector3) -> Vector3:
	var s := _spr(u)
	if s == null or b == null or b._vfx == null:
		return fallback
	var fw: float = float(s.texture.get_width()) / float(maxi(1, s.hframes))
	var fh: float = float(s.texture.get_height()) / float(maxi(1, s.vframes))
	var lx: float = (art.x - fw * 0.5) * (-1.0 if s.flip_h else 1.0) + s.offset.x
	var ly: float = s.offset.y + fh * 0.5 - art.y
	var cb: Basis = b._vfx.cam_basis()
	## 人物图原点(脚底)按单位的战斗坐标推, 不读精灵节点位置: 一帧里先跑战斗推进、后跑画面(battle_render 才把精灵摆到 pos / height),
	##   读节点会晚一帧; 无头门禁只推战斗不跑画面时节点根本不动(verify_minion_pull_speed 量出来手端停在原地)。不含待机起伏(几毫米)。
	var o: Vector3 = s.global_position
	if u.has("pos"):
		o = b._world_pos(u["pos"], float(u.get("height", 0.0)) + float(b.GROUND_LIFT))
	return o + (cb.x.normalized() * lx * s.scale.x + cb.y.normalized() * ly * s.scale.y) * s.pixel_size


## 单位当前这一格本体顶部离脚底多高(米): 帧中间 30% 宽那一条里最上面的不透明像素 ——
##   踩人要站在背上, 不是站在探出去的头 / 尾巴上。按基准缩放算(不跟受击压扁晃)。读不到 ⇒ fallback
static func top_m(u: Dictionary, fallback: float) -> float:
	var s := _spr(u)
	if s == null:
		return fallback
	var tex: Texture2D = s.texture
	var hf: int = maxi(1, s.hframes)
	var fw: int = tex.get_width() / hf
	var fh: int = tex.get_height() / maxi(1, s.vframes)
	var key := "%s#%d" % [tex.resource_path, s.frame]
	var top: int = -1
	if _top_cache.has(key):
		top = int(_top_cache[key])
	else:
		var im: Image = _img(tex)
		if im == null:
			return fallback
		var fx: int = (s.frame % hf) * fw
		var fy: int = (s.frame / hf) * fh
		for y in range(fh):
			for x in range(int(fw * 0.35), int(fw * 0.65)):
				if im.get_pixel(fx + x, fy + y).a > 0.5:
					top = y
					break
			if top >= 0:
				break
		_top_cache[key] = top
	if top < 0:
		return fallback
	var sy: float = s.scale.y
	var bs = u.get("spr_base_scale", null)
	if bs is Vector3:
		sy = (bs as Vector3).y
	return maxf(0.0, (s.offset.y + float(fh) * 0.5 - float(top)) * s.pixel_size * sy)


static func _img(tex: Texture2D) -> Image:
	var k: String = tex.resource_path
	if _img_cache.has(k):
		return _img_cache[k]
	var im: Image = tex.get_image()
	if im == null or im.is_empty():
		return null
	if im.is_compressed():
		im.decompress()
	if k != "":
		_img_cache[k] = im
	return im
