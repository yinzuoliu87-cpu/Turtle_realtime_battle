# -*- coding: utf-8 -*-
"""闯关赛「匹配成功」短音效(2026-10-29, 方案书 docs/plans/20261029c-闯关赛排队时可回主页.md §4.1-5 / U5 · A13)。

用户 10-29「全部今天做完」认可 U5: 配上时不管在哪个页面都盖「匹配成功 · 即将进入对局」遮罩约 1.5 秒后自动进,
  配一个**新做的**短音效 —— 仓库里没有现成的配上音效(assets/audio/sfx/ 原来只有战斗类与工作室开场)。
做法照 tools/build_studio_intro.py 合成芯片音那一段: 逐采样算方波 / 三角波 / 正弦, 指数衰减包络, 0 次生成模型、0 个随机数
  ⇒ 确定性, 重跑逐字节相同(内容没变就不写盘)。

听感(总长 TIMING["end"] 秒, 遮罩 1.5 秒内放完):
  ① 0.00 起: 三个短促方波上行(A5 → C#6 → E6, 每 STEP 秒一个)—— 「找到了」的提示, 与开场标的五声琶音不是同一组音;
  ② CHORD 秒: 低音一下闷击(正弦 110Hz, 很快衰减)+ A 大三和弦长音(三角波 A6 / E6 / C#6)+ 高八度方波泛音(A7, 短)
     —— 「就绪」那一下有分量, 尾巴自然衰减;
  ③ 最后 FADE 秒线性淡出, 不留咔哒。
  峰值归一到 0.80(与开场标同一个余量)。

输出: assets/audio/sfx/queue_found.wav(单声道 16 位 44100Hz)。游戏里由 scripts/scenes/queue_found_overlay.gd 播。

  python tools/build_queue_found_sfx.py
"""
import io
import math
import os
import struct
import sys
import wave

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAV = os.path.join(ROOT, "assets", "audio", "sfx", "queue_found.wav")

SR = 44100
TIMING = {"step": 0.065, "chord": 0.20, "fade": 0.25, "end": 1.15}   # 秒
RISE = [880.0, 1108.73, 1318.51]                                     # A5 C#6 E6
CHORD = [1760.0, 1318.51, 1108.73]                                   # A6 E6 C#6


def synth():
    n = int(SR * TIMING["end"])
    buf = [0.0] * n

    def add(t0, freq, dur, vol, wave_kind="square", decay=12.0):
        i0 = int(round(t0 * SR))
        for i in range(int(dur * SR)):
            if i0 + i >= n:
                break
            t = i / SR
            ph = (freq * t) % 1.0
            if wave_kind == "square":
                s = 1.0 if ph < 0.5 else -1.0
            elif wave_kind == "tri":
                s = 4 * abs(ph - 0.5) - 1
            else:
                s = math.sin(2 * math.pi * ph)
            env = math.exp(-decay * t) * min(1.0, t / 0.004)
            buf[i0 + i] += s * env * vol

    # ① 三个短促上行方波
    for i, f in enumerate(RISE):
        add(i * TIMING["step"], f, 0.12, 0.17, "square", 22.0)
    # ② 闷击 + 和弦长音 + 高八度泛音
    c = TIMING["chord"]
    add(c, 110.0, 0.18, 0.34, "sine", 24.0)
    add(c, CHORD[0], 0.95, 0.30, "tri", 3.6)
    add(c, CHORD[1], 0.95, 0.20, "tri", 3.9)
    add(c, CHORD[2], 0.95, 0.16, "tri", 4.2)
    add(c, CHORD[0] * 2.0, 0.30, 0.07, "square", 11.0)
    # ③ 收尾淡出
    f0 = int((TIMING["end"] - TIMING["fade"]) * SR)
    for i in range(f0, n):
        buf[i] *= 1.0 - (i - f0) / (n - f0)
    peak = max(abs(v) for v in buf) or 1.0
    return [v / peak * 0.80 for v in buf]


def wav_bytes(samples):
    bio = io.BytesIO()
    with wave.open(bio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in samples))
    return bio.getvalue()


def build():
    data = wav_bytes(synth())
    if os.path.exists(WAV) and open(WAV, "rb").read() == data:
        print("ok(未变)", WAV, len(data), "bytes")
        return
    os.makedirs(os.path.dirname(WAV), exist_ok=True)
    with open(WAV, "wb") as f:
        f.write(data)
    print("ok(已写)", WAV, len(data), "bytes")


if __name__ == "__main__":
    build()
