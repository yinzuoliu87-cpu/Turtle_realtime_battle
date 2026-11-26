"""cent_action_px_1127.py —— 百夫长普攻 / 倒下帧条沿用待机像素尺寸(原来走通用「身高 / 帧高」归一 ⇒ 只有 60% 大, 一出手人就缩一半)
探针实测(录像台 cent_full + REC_CENT_PROBE): 待机 / 走路 / 举盾 / 掷矛 px=0.02612, 普攻 px=0.01563。六张帧条都是 128 方帧、同一条贴地线。
同 107 武士刀小将的做法(battle_vfx._play_action 里的 _art_px)。一次性; 原行尾二进制读写。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, "scripts", "scenes", "battle", "battle_vfx.gd")
raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
a = '\tif kind == "attack" and id == "ninja":\n'
assert s.count(a) == 1
b = ('\tif (kind == "attack" or kind == "death") and id == "_summon_centurion":   # 长矛羁绊百夫长(11-27 自查): 六张帧条同 128 方帧同贴地线 ⇒ 沿用待机像素尺寸(含放大 1.3), 原来普攻 / 倒下按通用归一只有 60% 大\n'
     '\t\tu["_art_px"] = float(u.get("idle_px", battle.PIXEL_SIZE)); u["_art_offy"] = float(u.get("idle_offy", 64.0))\n'
     + a)
s = s.replace(a, b)
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
