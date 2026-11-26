"""cent_global_knock_vfx_1127.py —— 百夫长登场「全场击飞」演出(用户 11-27「我有没有说过，它是全屏击飞的，登场的这个击飞」)
结算本来就是全场(_land 对 _enemies_of 每个人打伤害 + 击飞, 录像台 7 个散满全场的靶子全中), 但画面只有落点一圈裂坑 ⇒ 读成「身边小范围」。
落地同一步(结算同一步, 不做往外走的波, 免得画面先于 / 晚于结算):
  · 每个被击飞的敌人脚下炸开裂地爆 spear-cent-erupt(金色地裂 + 光柱 + 土块崩起 + 尘烟)
  · 从落点到每个敌人一道贴地地裂 spear-cent-crack(固定长度一段, 沿地面首尾相接铺过去; 段数随距离, 不拉伸变形)
素材: tools/assetgen/pack_spear_chip_art.py 头注(PixelLab 特效工作台自写图层)。一次性; 原行尾二进制读写。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, "scripts", "scenes", "battle", "spear_eq_vfx.gd")
raw = open(p, "rb").read()
nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")

a = ("\t_strip(V + \"spear-cent-impact.png\", 8, battle._world_pos(Vector2(p[\"pos\"]), 0.07), d_m, 14.0, false, 8.0 / 14.0, true, null, 0.0)\n"
     "\tbattle._shake(battle.JUICE_SHAKE_HEAVY)\n")
assert s.count(a) == 1
b = a + (
    "\t## 全场击飞(11-27 用户「它是全屏击飞的」): 结算同一步, 每个敌人脚下裂地爆 + 落点到每个敌人一道贴地地裂(与 _land 同一个 _enemies_of)\n"
    "\tfor o in battle._targeting._enemies_of(p):\n"
    "\t\tif not (o is Dictionary) or not o.get(\"alive\", false):\n"
    "\t\t\tcontinue\n"
    "\t\tvar er := _strip(V + \"spear-cent-erupt.png\", 10, battle._world_pos(Vector2(o[\"pos\"]), 0.0), ERUPT_H, 16.0, false, 10.0 / 16.0, false, null, 0.0)\n"
    "\t\tif er != null:\n"
    "\t\t\ter.offset = Vector2(0.0, ERUPT_ROW - ERUPT_FH * 0.5)   # 帧里地面点那一行压在敌人脚下(原 _strip 是底边着地)\n"
    "\t\t_ground_crack(Vector2(p[\"pos\"]), Vector2(o[\"pos\"]))\n"
    "\n"
    "\n"
    "const ERUPT_H := 2.4        # 裂地爆整帧高(米; 帧 134×92, 敌方小将约 1.3 米宽)\n"
    "const ERUPT_FH := 92.0      # 帧高(像素)\n"
    "const ERUPT_ROW := 58.0     # 帧里地面点所在行(打包时由工作台锚点量出)\n"
    "const CRACK_W := 0.55       # 贴地地裂宽(米); 一段帧 128×28\n"
    "\n"
    "\n"
    "## 从 a 到 b 沿地面铺地裂: 一段 128×28 的帧条首尾相接, 段数 = 距离 / 段长取整, 每段等长(只差几成, 不拉伸像素)\n"
    "func _ground_crack(a: Vector2, b: Vector2) -> void:\n"
    "\tif not _ok() or not ResourceLoader.exists(V + \"spear-cent-crack.png\"):\n"
    "\t\treturn\n"
    "\tvar d: Vector2 = b - a\n"
    "\tvar dist_m: float = d.length() * float(battle.WS)\n"
    "\tif dist_m < 0.5:\n"
    "\t\treturn\n"
    "\tvar seg0: float = CRACK_W * 128.0 / 28.0\n"
    "\tvar n: int = maxi(1, int(round(dist_m / seg0)))\n"
    "\tvar seg: float = dist_m / float(n)\n"
    "\tvar t: Texture2D = load(V + \"spear-cent-crack.png\")\n"
    "\tvar w3: Vector3 = battle._world_pos(b, 0.0) - battle._world_pos(a, 0.0)\n"
    "\tvar ang: float = atan2(-w3.z, w3.x)\n"
    "\tfor i in range(n):\n"
    "\t\tvar s := Sprite3D.new()\n"
    "\t\ts.texture = t\n"
    "\t\ts.hframes = 8\n"
    "\t\ts.shaded = false\n"
    "\t\ts.transparent = true\n"
    "\t\ts.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST\n"
    "\t\ts.billboard = BaseMaterial3D.BILLBOARD_DISABLED\n"
    "\t\ts.axis = Vector3.AXIS_Y\n"
    "\t\ts.no_depth_test = false\n"
    "\t\ts.render_priority = -1   # 贴地的先画, 单位压在上面(同 _strip flat)\n"
    "\t\ts.pixel_size = seg / 128.0\n"
    "\t\ts.flip_v = (i % 2) == 1   # 隔段上下翻: 同一段裂纹不连着重复\n"
    "\t\ts.position = battle._world_pos(a + d * ((float(i) + 0.5) / float(n)), 0.06)\n"
    "\t\ts.rotation.y = ang\n"
    "\t\tbattle._world.add_child(s)\n"
    "\t\t_mfx.append({\"node\": s, \"nf\": 8, \"fps\": 16.0, \"t\": 0.0, \"life\": 0.5, \"loop\": false, \"follow\": null, \"h\": 0.0})\n"
)
s = s.replace(a, b)
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
