"""knockdown_tilt_1126.py —— 145 永恒之枪「插倒」方案 A(用户 11-26 晚定): 立绘在屏幕平面内往后倒、滑行、躺一下、弹起
立绘 shader 自己用相机右 / 上向量拼朝镜头矩阵 ⇒ 加 uniform tilt(弧度, 默认 0 = 和原来逐字节同一个矩阵), 把右 / 上两列一起转 ⇒ 绕脚底(本地原点)在屏幕平面里倒。
角度由 sim 在单位上记 _kd_t0(开始时刻)/ _kd_dir(往哪边倒), 渲染按 battle._t 算(进直播流, 播放端同样倒)。
一次性; 原行尾二进制读写, 每处替换次数核对。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b, n in pairs:
        assert s.count(a) == n, (rel, a[:70], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


patch("scripts/scenes/RealtimeBattle3DScene.gd", [
    ("""uniform float vframes = 1.0;      // ★sprite-sheet 的行数 (网格图必须传, 否则底淡算错)
""", """uniform float vframes = 1.0;      // ★sprite-sheet 的行数 (网格图必须传, 否则底淡算错)
uniform float tilt = 0.0;         // 屏幕平面内绕脚底侧转(弧度, 正 = 头往画面右倒; 145 插倒 11-26)
""", 1),
    ("""	MODELVIEW_MATRIX[2] *= scl.z;
}
""", """	MODELVIEW_MATRIX[2] *= scl.z;
	vec4 rr = MODELVIEW_MATRIX[0]; vec4 uu = MODELVIEW_MATRIX[1];
	MODELVIEW_MATRIX[0] = rr * cos(tilt) - uu * sin(tilt) * scl.x / max(scl.y, 0.0001);
	MODELVIEW_MATRIX[1] = uu * cos(tilt) + rr * sin(tilt) * scl.y / max(scl.x, 0.0001);
}
""", 1),
])

patch("scripts/systems/equip/eq_spear_batch.gd", [
    ("""			battle._damage._stun(tg, ETERNAL_STUN, "eternal_pin")
""", """			battle._damage._stun(tg, ETERNAL_STUN, "eternal_pin")
			tg["_kd_t0"] = float(battle._t)                      # 插倒(方案 A): 渲染按它把立绘往后倒、滑完躺一下再弹起
			tg["_kd_dir"] = 1.0 if dir.x >= 0.0 else -1.0         # 往滑行方向倒(背离来枪)
""", 1),
])

patch("scripts/systems/stream/stream_recorder.gd", [
    ('"phys_shield", "_spearShieldVal",', '"phys_shield", "_spearShieldVal", "_kd_t0", "_kd_dir",', 1),
])

R = "scripts/scenes/battle/battle_render.gd"
patch(R, [
    ("""func _update_world_transforms() -> void:
""", """## 145 插倒(方案 A, 用户 11-26 晚): 0.08 秒倒到 KD_DEG → 滑行 + 躺到 KD_HOLD → KD_RISE 秒弹回(总长 < 眩晕 1 秒)
const KD_DEG := 70.0
const KD_FALL := 0.08
const KD_HOLD := 0.8
const KD_RISE := 0.15
static func knockdown_tilt(u: Dictionary, t: float) -> float:
	var t0: float = float(u.get("_kd_t0", -1.0))
	if t0 < 0.0:
		return 0.0
	var e: float = t - t0
	if e < 0.0 or e >= KD_HOLD + KD_RISE:
		return 0.0
	var k: float = clampf(e / KD_FALL, 0.0, 1.0) if e < KD_HOLD else 1.0 - clampf((e - KD_HOLD) / KD_RISE, 0.0, 1.0)
	k = 1.0 - (1.0 - k) * (1.0 - k)   # 倒得快、收得软
	return deg_to_rad(KD_DEG) * k * float(u.get("_kd_dir", 1.0))


func _update_world_transforms() -> void:
""", 1),
])
patch(R, [
    ("""		spr.scale = Vector3(bs.x * sq.x * gm * dvs, bs.y * sq.y * gm * dvs, bs.z)
""", """		spr.scale = Vector3(bs.x * sq.x * gm * dvs, bs.y * sq.y * gm * dvs, bs.z)
		var _kdm = spr.material_override
		if _kdm is ShaderMaterial:
			var _kdt: float = knockdown_tilt(u, float(battle._t))
			if _kdt != 0.0 or u.has("_kd_t0"):
				(_kdm as ShaderMaterial).set_shader_parameter("tilt", _kdt)   # 145 插倒(方案 A)
""", 1),
])
print("ok")
