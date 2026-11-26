"""cent_island_crack_1127.py —— 百夫长登场「整座岛的地面一起裂开」(用户 11-27「不是…每个敌人脚下的地裂爆啊…应该是整个地面都出现全部地裂呀」
「肯定是整个岛都是被这个地面就冲击起来的呀」), 取代 274859e8 的「每人脚下裂地爆 + 落点到每个敌人一道连线」。
  · 落地同一步: 从落点往四面八方 12 条主裂缝一直裂到岛边(ArenaShape 判在不在岛上), 每条随机分出岔缝; 不按敌人位置走
  · 全部同一刻出现(不做往外蔓延 —— 击飞是同一步结算, 画面不能晚于结算), 之后金光褪去、暗缝合上(帧条 8 帧 @8 = 1 秒)
  · 碰到岛边的最后一段按剩余长度缩短、变细收尾; 随机数 = 本地 RandomNumberGenerator 按落点播种(纯演出, 不碰对局随机流)
  · 删掉裂地爆(spear-cent-erupt)素材、打包项与常量
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def rw(rel, fn):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    s = fn(s)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


NEW = '''\t_island_cracks(Vector2(p["pos"]))   # 整座岛的地面一起裂开(11-27 用户「应该是整个地面都出现全部地裂呀」)


## 登场砸地 = 整座岛的地面一起裂开: 从落点往四面八方 ISLAND_RAYS 条主裂缝一直裂到岛边, 每条随机分出岔缝; 不按敌人位置走。
##   与击飞同一步全部出现(不做往外蔓延, 画面不晚于结算), 之后金光褪去、暗缝合上(帧条 8 帧 @8 = 1 秒)。
##   一段裂缝帧 128×28(两端等高可拼), 宽 w 米 ⇒ 一段长 w × 128 / 28 米; 碰到岛边的最后一段按剩余长度缩短、变细收尾。
##   随机数用本地的(按落点播种): 纯演出, 不碰对局随机流。
const ISLAND_RAYS := 12
const CRACK_MAIN_W := 0.85   # 主裂缝宽(米)
const CRACK_BR_W := 0.5      # 岔缝宽(米)
const CRACK_FPS := 8.0


func _island_cracks(c: Vector2) -> void:
	if not _ok() or not ResourceLoader.exists(V + "spear-cent-crack.png"):
		return
	var t: Texture2D = load(V + "spear-cent-crack.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(c.x) * 131.0 + absf(c.y) * 7.0) + 1
	for i in range(ISLAND_RAYS):
		var base: float = TAU * float(i) / float(ISLAND_RAYS) + rng.randf_range(-0.15, 0.15)
		_crack_ray(t, rng, c, base, CRACK_MAIN_W, 12, true)


func _crack_ray(t: Texture2D, rng: RandomNumberGenerator, start: Vector2, base: float, w: float, max_n: int, branch: bool) -> void:
	var pos: Vector2 = start
	var seg_px: float = w * 128.0 / 28.0 / float(battle.WS)
	for k in range(max_n):
		var ang: float = base + rng.randf_range(-0.35, 0.35)
		var dir := Vector2(cos(ang), sin(ang))
		var nxt: Vector2 = pos + dir * seg_px
		if not ArenaShape.in_rect_shape(nxt, battle.ARENA, 6.0):
			for f in [0.7, 0.45, 0.25]:   # 岛边: 最后一段缩短变细收尾
				var q: Vector2 = pos + dir * seg_px * f
				if ArenaShape.in_rect_shape(q, battle.ARENA, 6.0):
					_crack_piece(t, rng, pos, q, w * f)
					break
			return
		_crack_piece(t, rng, pos, nxt, w)
		if branch and rng.randf() < 0.4:
			var side: float = 1.0 if rng.randf() < 0.5 else -1.0
			_crack_ray(t, rng, nxt, ang + side * rng.randf_range(0.5, 0.95), CRACK_BR_W, 3, false)
		pos = nxt


## 一段裂缝: 贴地帧条, 宽 w 米(一段长 = w × 128 / 28), 从 a 铺到 b
func _crack_piece(t: Texture2D, rng: RandomNumberGenerator, a: Vector2, b: Vector2, w: float) -> void:
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = 8
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.no_depth_test = false
	s.render_priority = -1   # 贴地的先画, 单位压在上面(同 _strip flat)
	s.pixel_size = w / 28.0
	s.flip_v = rng.randf() < 0.5   # 同一段裂纹不连着重复
	var w3: Vector3 = battle._world_pos(b, 0.0) - battle._world_pos(a, 0.0)
	s.position = battle._world_pos((a + b) * 0.5, 0.06)
	s.rotation.y = atan2(-w3.z, w3.x)
	battle._world.add_child(s)
	_mfx.append({"node": s, "nf": 8, "fps": CRACK_FPS, "t": 0.0, "life": 8.0 / CRACK_FPS, "loop": false, "follow": null, "h": 0.0})
'''


def gd(s):
    i = s.index("\t## 全场击飞(11-27 用户「它是全屏击飞的」)")
    j = s.index('\t\t_mfx.append({"node": s, "nf": 8, "fps": 16.0, "t": 0.0, "life": 0.5, "loop": false, "follow": null, "h": 0.0})\n', i)
    j = s.index("\n", j) + 1
    return s[:i] + NEW + s[j:]


rw("scripts/scenes/battle/spear_eq_vfx.gd", gd)


def pk(s):
    a = '    for src, dst, centre in [("centurion-ground-erupt", "spear-cent-erupt", True), ("centurion-crack-segment", "spear-cent-crack", False),\n'
    assert s.count(a) == 1
    s = s.replace(a, '    for src, dst, centre in [("centurion-crack-segment", "spear-cent-crack", False),\n')
    a = "    ai_src/cent_vfx/centurion-ground-erupt(.json): 每个被击飞的敌人脚下的裂地爆(贴地闪电形状画金色地裂 + 贴地光 + 短金光柱 + 土块碎石 + 尘烟 + 火星, 10 帧);\n"
    assert s.count(a) == 1
    s = s.replace(a, "    (centurion-ground-erupt 每人脚下裂地爆: 用户 11-27 否掉「哪有说什么对每个敌人脚下的地裂爆」, 不再打包, 源留在 ai_src)\n")
    a = "    ai_src/cent_vfx/centurion-crack-segment(.json): 俯视、两端等高可首尾拼接的一段地裂(暗缝 + 金色裂光, 8 帧), 引擎里贴地从落点铺到每个敌人。\n"
    assert s.count(a) == 1
    return s.replace(a, "    ai_src/cent_vfx/centurion-crack-segment(.json): 俯视、两端等高可首尾拼接的一段地裂(暗缝 + 金色裂光, 8 帧), 引擎里从落点往四面八方铺满整座岛。\n")


rw("tools/assetgen/pack_spear_chip_art.py", pk)
for f in ["assets/sprites/vfx/spear-cent-erupt.png", "assets/sprites/vfx/spear-cent-erupt.png.import"]:
    p = os.path.join(ROOT, f)
    if os.path.exists(p):
        os.remove(p)
print("ok")
