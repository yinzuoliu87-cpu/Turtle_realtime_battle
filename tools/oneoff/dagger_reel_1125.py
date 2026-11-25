"""dagger_reel_1125.py —— 把录像台的匕首批各段剪成一条验收合集(每段左上角写这一段看什么; 慢放段写明倍速)

    python tools/oneoff/dagger_reel_1125.py      ⇒ .out/dagger_rec/匕首批验收合集.mp4
"""
import os, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
D = os.path.join(ROOT, ".out", "dagger_rec")
FF = os.environ.get("FF", "D:/oopz/ffmpeg.exe")
FONT = "C\\:/Windows/Fonts/msyh.ttc"

## (录像, 起秒, 时长, 倍速, 说明)
SEG = [
    ("assassin", 0.4, 2.4, 1.0, "羁绊【刺杀】二档: 开打全队头顶暗红星芒 → 下一下普攻必暴击、猩红长斩线(同时出折叠小刀刀口 / 毒牙咬合)"),
    ("assassin", 0.55, 1.2, 0.35, "同上 0.35 倍慢放"),
    ("assassin", 10.4, 1.8, 1.0, "【刺杀】二档第 10 秒再挂一次"),
    ("fold", 0.6, 1.6, 0.5, "108 折叠小刀: 每路第一下普攻的刀口 + 流血(0.5 倍)"),
    ("knife", 6.3, 1.4, 1.0, "109 柳叶飞刀: 每 6 秒射向最远的敌人, 只打中途经的第一个(魔法伤害)"),
    ("kunai", 5.4, 1.4, 1.0, "110 苦无: 每 5 秒连掷 5 枚打随机敌人, 每中一枚携带者回血(青绿)"),
    ("fang", 0.7, 1.6, 0.5, "111 毒牙匕首: 暴击时蛇颚咬一口叠中毒(这条同时带 116, 身上插黑曜石)(0.5 倍)"),
    ("kris", 7.3, 3.6, 1.0, "113 弯匕: 击杀后 3 秒攻速暴涨, 身上金色风纹"),
    ("ritual", 3.9, 1.8, 1.0, "114 仪式匕首: 10% 血斩杀(猩红镰月) → 刻血契(血气流进携带者 + 「血契 N」)"),
    ("ritual", 4.1, 0.9, 0.35, "同上 0.35 倍慢放"),
    ("obs", 8.4, 2.6, 1.0, "116 黑曜石匕首: 暴击插一把(插在身上跟着走) → 够杀时全部拔出(黑玻璃碎开)"),
    ("ninja_show", 0.4, 2.8, 1.0, "115 暗影忍者: 化烟 → 闪到目标身后现身 → 背刺(第 3 帧插中 = 结算) → 半透明潜伏 1.5 秒"),
    ("ninja_show", 0.95, 0.9, 0.3, "同上 0.3 倍慢放"),
    ("ninja", 18.1, 4.2, 1.0, "115 半血分出影子(暗紫) → 影袭时两名忍者各掷一枚手里剑, 路径上的敌人吃魔法伤害"),
]


def main():
    parts = []
    for i, (c, t0, dur, sp, txt) in enumerate(SEG):
        out = os.path.join(D, "_seg%02d.mp4" % i)
        label = txt.replace(":", "\\:").replace("'", "").replace("%", "％")
        vf = "setpts=%g*PTS,drawbox=x=0:y=0:w=iw:h=46:color=black@0.6:t=fill,drawtext=fontfile='%s':text='%s':x=14:y=10:fontsize=22:fontcolor=white" % (1.0 / sp, FONT, label)
        subprocess.run([FF, "-y", "-loglevel", "error", "-ss", str(t0), "-t", str(dur), "-i", os.path.join(D, c + ".mp4"),
                        "-vf", vf, "-an", "-r", "30", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", out], check=True)
        parts.append(out)
    lst = os.path.join(D, "_reel.txt")
    with open(lst, "w", encoding="utf-8") as f:
        for p in parts:
            f.write("file '%s'\n" % p.replace("\\", "/"))
    final = os.path.join(D, "匕首批验收合集.mp4")
    subprocess.run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
    for p in parts:
        os.remove(p)
    os.remove(lst)
    print(final)


if __name__ == "__main__":
    main()
