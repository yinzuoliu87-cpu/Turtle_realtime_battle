"""batch_detmath_1127.py —— 面具 / 长矛 / 筹码批预检: sim 路径裸调数学函数改走 DetMath(det_math_lint; 跨平台确定性)
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
        assert s.count(a) == n, (rel, a[:60], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


patch("scripts/scenes/battle/otherworld_stage.gd", [
    ("Vector3(cos(r) * aw * 0.46, 0.0, sin(r) * ah * 0.44)", "Vector3(DetMath.dcos(r) * aw * 0.46, 0.0, DetMath.dsin(r) * ah * 0.44)", 1),
    ("Vector3(cos(r2) * aw * 0.49, 0.0, sin(r2) * ah * 0.49)", "Vector3(DetMath.dcos(r2) * aw * 0.49, 0.0, DetMath.dsin(r2) * ah * 0.49)", 1),
])
patch("scripts/systems/equip/eq_mask_batch.gd", [
    ('L["dir"] = dv.normalized() if dv.length() > 1.0 else', 'L["dir"] = DetMath.norm(dv) if DetMath.vlen(dv) > 1.0 else', 1),
    ("var q: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(o[\"pos\"]), a, b)\n\t\t\t\t\tif DetMath.dist(q, Vector2(o[\"pos\"])) <= LION_W",
     "var q: Vector2 = DetMath.seg_closest(Vector2(o[\"pos\"]), a, b)\n\t\t\t\t\tif DetMath.dist(q, Vector2(o[\"pos\"])) <= LION_W", 1),
    ("or b.distance_to(a) < step * 0.5:", "or DetMath.dist(b, a) < step * 0.5:", 1),
])
patch("scripts/systems/equip/eq_spear_batch.gd", [
    ("var along: float = rel.dot(dir)\n\t\t\tvar half: float = float(o.get(\"col_size\", 22.0)) * 0.5\n\t\t\tif along < r0 - half",
     "var along: float = DetMath.dot(rel, dir)\n\t\t\tvar half: float = float(o.get(\"col_size\", 22.0)) * 0.5\n\t\t\tif along < r0 - half", 1),
    ("if absf(rel.dot(Vector2(-dir.y, dir.x))) > BAMBOO_W + half:", "if absf(DetMath.dot(rel, Vector2(-dir.y, dir.x))) > BAMBOO_W + half:", 1),
    ("DetMath.norm(rel).dot(Vector2(w[\"dir\"])) < SHSP_WAVE_ARC", "DetMath.dot(DetMath.norm(rel), Vector2(w[\"dir\"])) < SHSP_WAVE_ARC", 1),
    ("DetMath.norm(rel).dot(fdir) < HALB_ARC", "DetMath.dot(DetMath.norm(rel), fdir) < HALB_ARC", 1),
    ("DetMath.norm(rel).dot(dir) >= SHSP_WAVE_ARC", "DetMath.dot(DetMath.norm(rel), dir) >= SHSP_WAVE_ARC", 1),
    ("c + Vector2(cos(ang), sin(ang)) * rr", "c + Vector2(DetMath.dcos(ang), DetMath.dsin(ang)) * rr", 1),
])
patch("scripts/systems/equip/spear_synergy_system.gd", [
    ("Geometry2D.get_closest_point_to_segment(Vector2(o[\"pos\"]), a, b)", "DetMath.seg_closest(Vector2(o[\"pos\"]), a, b)", 3),
    ("(Vector2(o[\"pos\"]) - Vector2(w[\"t0\"])).dot(dir) <= 0.0", "DetMath.dot(Vector2(o[\"pos\"]) - Vector2(w[\"t0\"]), dir) <= 0.0", 1),
])
patch("scripts/scenes/battle/spear_eq_vfx.gd", [
    ("1.0 + 0.08 * sin(PI * clampf(t / 0.24, 0.0, 1.0))", "1.0 + 0.08 * DetMath.dsin(PI * clampf(t / 0.24, 0.0, 1.0))", 1),
])
print("ok")
