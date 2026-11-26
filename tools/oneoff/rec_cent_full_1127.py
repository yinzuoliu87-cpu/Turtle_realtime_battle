"""rec_cent_full_1127.py —— 录像台加 cent_full(百夫长单独审: 只出百夫长自己, 敌人散满全场看「全场击飞」)
用户 11-27「这么多问题，你自己先看一下…我有没有说过，它是全屏击飞的」: 原 sp_cent 携带者带 10 件长矛, 计时类件一直刷屏, 敌人全挤在落点旁边。
REC_SPEAR_TIER=<n> 开打后每帧把我方长矛羁绊档设成 n(携带者不带件 ⇒ 少了每星 +3% 生命 / 攻击, 只影响数值不影响动作特效)
REC_CENT_KILL=<秒> 到点给百夫长一下致命真伤(看倒下)。一次性; 原行尾二进制读写。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, "tests", "_rec_eq_stage.gd")
raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
a = '\t\t"sp_cent": ['
assert s.count(a) == 1
spots = [(0, -280), (0, 280), (320, -150), (320, 150), (640, -280), (640, 280), (700, 0)]
dum = " + ".join('[_u("__minion__", "right", Vector2(%d, %d), {"minion": true, "role": "front", "level": 1, "plain": true, "hp": 30000.0, "killable": false, "ai": false})]' % xy for xy in spots)
b = ('\t\t## 百夫长单独审(11-27): 我方只有一只不动的友军, 长矛档由 REC_SPEAR_TIER 给; 7 个靶子散满全场(上下边 / 中线 / 对面后排)\n'
     '\t\t"cent_full": [[_u("basic", "left", Vector2(-620, 0), {"idle": true, "killable": false, "plain": true})] + ' + dum + ', 30.0],\n' + a)
s = s.replace(a, b)
c = '\tif OS.has_environment("REC_NODE_PROBE") and'
assert s.count(c) == 1
d = ('\tif OS.has_environment("REC_SPEAR_TIER") and _started:   # 百夫长单独审(11-27): 直接给档, 携带者不带件 ⇒ 没有 10 件长矛刷屏\n'
     '\t\tif not _b._synergy._by_side.has("left"):\n'
     '\t\t\t_b._synergy._by_side["left"] = {}\n'
     '\t\t_b._synergy._by_side["left"]["长矛"] = int(OS.get_environment("REC_SPEAR_TIER"))\n'
     '\tif OS.has_environment("REC_CENT_KILL") and _el > float(OS.get_environment("REC_CENT_KILL")) and not _seen.has("cent_kill"):\n'
     '\t\tfor uu in _b._units:\n'
     '\t\t\tif uu is Dictionary and str(uu.get("id", "")) == "_summon_centurion" and bool(uu.get("alive", false)):\n'
     '\t\t\t\t_seen["cent_kill"] = 1\n'
     '\t\t\t\t_b._damage._apply_damage(uu, int(float(uu["hp"]) + float(uu.get("shield", 0.0)) + 10.0), Color.WHITE)\n'
     + c)
s = s.replace(c, d)
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
