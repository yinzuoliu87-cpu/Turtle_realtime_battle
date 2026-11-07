"""糖果龟全动作成片(和钻石龟同格式)"""
import glob
import sys

from PIL import Image

sys.path.insert(0, "C:/Users/Louis/AppData/Local/Temp/claude/5a6586b023f62759/a1c0e931-7a92-4ec5-b358-31af224163c8/scratchpad")
import reel

sys.stdout.reconfigure(encoding="utf-8")
D = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/candy_sample/"


def seq(d):
    return [Image.open(p).convert("RGBA") for p in sorted(glob.glob(D + d + "/f_*.png"))]


idle = seq("idle_final")
death = seq("death_final")
hold = death[-1]
fade = [death[-1], death[-1]]
for a in (0.85, 0.7, 0.55, 0.4, 0.25, 0.1):
    c = hold.copy()
    c.putalpha(c.getchannel("A").point(lambda v, a=a: int(v * a)))
    fade.append(c)
clips = [
    {"name": "待机", "note": "每帧 0.125 秒 · 约 1 秒一轮", "frames": idle, "fps": 8, "ox": 0, "ground": 123, "loop": True},
    {"name": "走路", "note": "每帧 0.083 秒 · 0.67 秒一轮", "frames": seq("walk_final"), "fps": 12, "ox": 0, "ground": 123, "loop": True},
    {"name": "普攻 · 横扫大锤", "note": "攻速 0.65 · 每帧 0.10 秒 · 起手 0.40 秒命中 · 动作 1.1 秒 · 每 1.54 秒打一次", "frames": seq("swing_new"), "fps": 10, "ox": 80, "ground": 135, "idle_gap": 0.54},
    {"name": "技能 · 糖果锤", "note": "每帧 0.068 秒 · 全程 1.9 秒 · 起手 0.61 秒命中", "frames": seq("q_vfx3"), "fps": 14.7, "ox": 60, "ground": 123},
    {"name": "技能 · 糖衣炮弹", "note": "每帧 0.085 秒 · 全程 1.62 秒 · 起手 0.34 秒开第一炮", "frames": seq("barrage_vfx"), "fps": 4 / 0.34, "ox": 40, "ground": 213},
    {"name": "技能 · 糖果炸弹", "note": "每帧 0.068 秒 · 全程 0.61 秒 · 起手 0.34 秒炸弹落地", "frames": seq("bomb_vfx"), "fps": 5 / 0.34, "ox": 40, "ground": 153},
    {"name": "被动 · 甜蜜吸取", "note": "每帧 0.083 秒 · 全程 1.5 秒 · 游戏里糖粒在第 0.58~1.04 秒飞到", "frames": seq("drain_final"), "fps": 12, "ox": 0, "ground": 123},
    {"name": "阵亡", "note": "6 帧 · 每帧 0.067 秒 · 第 0.55 秒开始淡出，0.4 秒淡完", "frames": death + fade, "fps": 15, "ox": 0, "ground": 123},
]
reel.render(clips, "糖果龟 · 全部动作（未接入游戏）", D + "糖果龟_全动作.mp4", idle=idle, idle_ox=0, idle_ground=123)
