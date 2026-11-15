# -*- coding: utf-8 -*-
"""把录像台打出来的 [SFX] 行按时刻混进成片(2026-11-15, 三路开场录像用)。

录制一律静音(godot-quiet.sh 压主总线, 不在用户电脑上外放); 录像台把每一声的触发时刻打成
  [SFX] <视频秒> <音效名> <音量> <音高>
这里取 assets/audio/sfx/v2/<名>__1.wav(没有就 <名>.wav), 按时刻 adelay、按音量 / 音高调好, amix 成一条音轨贴进视频。
没做游戏里的总线效果(压限 / 混响), 只是同一批音效文件在同一时刻响。

  python tools/oneoff/mix_rec_sfx.py <录像台日志> <无声视频> <输出 mp4>
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FF = os.environ.get("FFMPEG", "D:/oopz/ffmpeg.exe")
SFX = os.path.join(ROOT, "assets", "audio", "sfx", "v2")


def main() -> None:
    log, vid, out = sys.argv[1], sys.argv[2], sys.argv[3]
    evs = []
    for ln in open(log, encoding="utf-8", errors="replace"):
        m = re.match(r"\[SFX\] ([\d.]+) (\S+) ([\d.]+) ([\d.]+)", ln.strip())
        if m:
            evs.append((float(m.group(1)), m.group(2), float(m.group(3)), float(m.group(4))))
    ins, flt = [], []
    for i, (t, name, vol, pitch) in enumerate(evs):
        p = os.path.join(SFX, name + "__1.wav")
        if not os.path.exists(p):
            p = os.path.join(SFX, name + ".wav")
        if not os.path.exists(p):
            print("缺音效文件:", name)
            continue
        ins += ["-i", p]
        k = len(ins) // 2
        ms = max(0, int(round(t * 1000)))
        flt.append("[%d:a]aresample=48000,asetrate=%d,aresample=48000,volume=%.3f,adelay=%d|%d[s%d]" % (k, int(48000 * pitch), vol, ms, ms, k))
    n = len(flt)
    if n == 0:
        raise SystemExit("日志里没有 [SFX] 行")
    mix = "".join("[s%d]" % (i + 1) for i in range(n)) + "amix=inputs=%d:normalize=0:dropout_transition=0[a]" % n
    cmd = [FF, "-loglevel", "error", "-y", "-i", vid] + ins + ["-filter_complex", ";".join(flt + [mix]), "-map", "0:v", "-map", "[a]",
           "-c:v", "libx264", "-preset", "slow", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", out]
    subprocess.run(cmd, check=True)
    print("ok: %d 声 → %s" % (n, out))


if __name__ == "__main__":
    main()
