p = "tests/_rec_eq_stage.gd"
raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
a = '\t\t"ch_brown": ['
assert s.count(a) == 1
b = ('\t\t## 倒地姿势(11-27): 只放一只靶子(三只会围上来挡住携带者), 看倒下 → 趴着 → 起身\n'
     '\t\t"rv_ven1": [[_me(Vector2(-60, 0), _eq([134], 1), {"hp": 1500.0, "killable": true}), _me(Vector2(-460, 180), [], {"idle": true})] + _dummies(90, 1, true, 30000.0, 400.0), 12.0],\n'
     '\t\t"rv_brown1": [[_me(Vector2(-60, 0), _eq([154], 1), {"hp": 300.0, "killable": true}), _me(Vector2(-460, 180), [], {"idle": true})] + _dummies(90, 1, true, 30000.0, 300.0), 12.0],\n'
     + a)
s = s.replace(a, b)
c = '\tif OS.has_environment("REC_ANIM_PROBE") and'
assert s.count(c) == 1
d = ('\tif OS.has_environment("REC_POSE_PROBE"):   # 倒地复活(11-27): 每帧打携带者的帧条 / 帧号 / 透明度\n'
     '\t\tfor uu in _b._units:\n'
     '\t\t\tif uu is Dictionary and bool(uu.get("_downed_pose", false)) and is_instance_valid(uu.get("sprite", null)):\n'
     '\t\t\t\tvar ps = uu["sprite"]\n'
     '\t\t\t\tvar ptx = (uu.get("anim_sd", {}) as Dictionary).get("tex", null)\n'
     '\t\t\t\tprint("[POSE] %.2f %s %s f=%d a=%.2f hp=%d" % [_el, str(uu.get("id", "")), (ptx as Texture2D).resource_path.get_file() if ptx != null else "无", int(ps.frame), float(ps.modulate.a), int(uu.get("hp", 0))])\n'
     + c)
s = s.replace(c, d)
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
