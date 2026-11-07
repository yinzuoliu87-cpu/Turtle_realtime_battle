"""seq_raw/<龟>/<中文段名>/ → tools/assetgen/pet_seq/<id>/<段名>/ + seq.json; 拆段规则见 SPECIAL"""
import glob
import json
import os
import shutil
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
ROOT = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/"
RAW = ROOT + ".out/review/seq_raw/"
OUT = ROOT + "tools/assetgen/pet_seq/"
SK = {
    "diamond": {"坚不可摧": "diamondFortify", "钻石滚球": "diamondPowerball", "钻石冲撞": "diamondSmash"},
    "dice": {"孤注一掷": "diceAllIn", "命运骰子": "diceFate", "稳定骰子": "diceFlashStrike"},
    "gambler": {"万能牌": "gamblerDraw", "赌注": "gamblerBet", "命运之轮": "gamblerFateWheel"},
    "hunter": {"精准射击": "hunterShot", "隐蔽": "hunterStealth", "狩猎弹幕": "hunterBarrage"},
    "pirate": {"火炮齐射": "pirateCannonBarrage", "朗姆酒": "pirateRum", "海盗船": "pirateShipPassive"},
    "candy": {"糖果锤": "candyHammer", "糖衣炮弹": "candyBarrage", "糖果炸弹": "candyBomb"},
    "bubble": {"泡泡盾": "bubbleShield", "泡泡束缚": "bubbleBind", "泡泡爆破": "bubbleBurst"},
    "line": {"连笔": "lineLink", "画龙点睛": "lineFinish", "墨水炸弹": "lineInkBomb"},
    "cyber": {"能量大炮": "cyberBeam", "侵入": "cyberHijack", "智能AI": "cyberSmartAI"},
    "crystal": {"水晶壁垒": "crystalBarrier", "碎晶爆破": "crystalBurst", "水晶球": "crystalBall"},
    "chest": {"清点财宝": "chestCount", "财宝风暴": "chestStorm", "财宝炮击": "chestCannon"},
    "space": {"虫洞": "starWormhole", "星波": "starWave", "扭曲空间": "starGravityWarp"},
    "hiding": {"缩头": "hidingShrink", "防御": "hidingDefend", "强化随从": "hidingBuffSummon"},
    "headless": {"恐吓": "headlessFear", "万千触须": "headlessTendrils", "灵魂打击": "headlessSoulStrike"},
}
FORM = {"接瓶": "drink", "甜蜜吸取": "drain", "钻石结构_登场": "enter", "闪避": "dodge", "处决": "execute", "多重打击": "multi", "登场": "enter", "霰弹": "shot"}
RAWNAME = {"dice": "dice3"}


def seq(tid, zh):
    return [Image.open(p).convert("RGBA") for p in sorted(glob.glob(RAW + RAWNAME.get(tid, tid) + "/" + zh + "/f_*.png"))]


def put(tid, seg, frames, meta, m):
    d = OUT + tid + "/" + seg + "/"
    os.makedirs(d, exist_ok=True)
    for i, im in enumerate(frames):
        im.save(d + "f_%02d.png" % i, optimize=False)
    meta[seg] = {"ox": m["ox"], "ground": m["ground"], "rel": m.get("rel", -1), "fps": m["fps"], "cancel": m.get("cancel", -1)}


## 真生效比 _cast_skill 晚的技能: {技能: (插几帧蓄力循环, 第几帧起可被走路 / 普攻打断)}
HOLD = {"chestCannon": (4, 11), "starWormhole": (3, 10), "crystalBall": (2, 9)}


def charge(fr, n):
    return fr[:5] + [fr[3] if i % 2 == 0 else fr[4] for i in range(n)] + fr[5:]


def bob(im, m):
    """持续状态的 1 像素起伏"""
    st = Image.new("RGBA", im.size, (0, 0, 0, 0))
    st.paste(im, (0, -1))
    return [im, im, st, st]


def run(tid):
    mp = json.load(open(RAW + RAWNAME.get(tid, tid) + "/meta.json", encoding="utf-8"))
    shutil.rmtree(OUT + tid, ignore_errors=True)
    meta = {}
    for zh, m in mp.items():
        fr = seq(tid, zh)
        if zh == "待机":
            put(tid, "idle", fr, meta, m)
        elif zh == "走路":
            put(tid, "run", fr, meta, m)
        elif zh == "阵亡":
            put(tid, "death", fr, meta, m)
        elif zh.startswith("普攻"):
            put(tid, "attack", fr, meta, m)
        elif zh.startswith("技能_"):
            name = zh[3:]
            sk = SK[tid][name]
            if sk in HOLD:                 # 真生效比释放晚: 释放姿势之后蓄力循环 n 帧, 第 5 帧(gen 姿势)落在生效时刻
                n, can = HOLD[sk]
                put(tid, "cast_" + sk, charge(fr, n), meta, dict(m, cancel=can))
            elif sk == "cyberBeam":        # 蓄力 0.9 秒才发射(cyb:92): 炮口能量球循环, 第 15 帧开火
                loop = [(fr[4], fr[5], fr[4], fr[3])[i % 4] for i in range(11)]
                put(tid, "cast_" + sk, fr[:4] + loop + fr[6:], meta, dict(m, cancel=17))
            elif sk == "starGravityWarp":  # 奇点 1.24 秒才爆发(star:199): 举杖撑住, 第 19 帧挥下
                loop = [(fr[4], fr[5])[i % 2] for i in range(15)]
                put(tid, "cast_" + sk, fr[:4] + loop + fr[6:], meta, dict(m, cancel=21))
            elif sk == "diamondSmash":     # 蓄力 0.5 秒撞击(dia:136): 撞击落到第 10 帧
                put(tid, "cast_" + sk, fr[:8] + [fr[7]] + fr[8:], meta, dict(m, cancel=11))
            elif sk == "headlessSoulStrike":   # 放技能只是充能; 第 3 下后才挥镰(head:260): 蓄力 0.55 + 预警 0.5 = 第 1.05 秒砍下
                put(tid, "cast_" + sk, [fr[i] for i in (0, 1, 2, 3, 4, 3, 2, 1)], meta, m)
                raise_ = [fr[0], fr[1]] + [(fr[2], fr[3], fr[4], fr[5])[i % 4] for i in range(14)]
                put(tid, "form_scythe", raise_ + fr[6:], meta, dict(m, fps=15, rel=-1))
            elif sk == "headlessTendrils":  # 引导 4 秒(head:535): 出手 → 触须循环 → 收
                put(tid, "cast_" + sk, fr[:5], meta, m)
                put(tid, "state_headlessTendrils", [fr[3], fr[4], fr[5], fr[4]], meta, dict(m, fps=8, rel=-1))
                put(tid, "form_headlessTendrils_end", fr[6:], meta, dict(m, fps=15, rel=-1))
            elif sk == "diceFlashStrike":   # 7~11 段连续突刺(dice:83): 扑出 → 贴地冲刺循环 → 收
                put(tid, "cast_" + sk, fr[:5], meta, m)
                put(tid, "state_diceDash", [fr[4], fr[5]], meta, dict(m, fps=12, rel=-1))
                put(tid, "form_diceDash_end", fr[6:], meta, dict(m, fps=15, rel=-1))
            elif sk == "starWave":         # 起波 +0.4 秒; 强化版第 2 秒另有彗星(star:527), 单独挥一下
                put(tid, "cast_" + sk, charge(fr, 4), meta, dict(m, cancel=11))
                put(tid, "form_comet", fr[3:], meta, dict(m, fps=15, rel=-1))
            elif sk == "crystalBarrier":    # 盾破 / 到期才砸地放水晶刺(M:6002)
                put(tid, "cast_" + sk, fr, meta, m)
                put(tid, "form_barrier_end", fr[6:], meta, dict(m, fps=15, rel=-1))
            elif sk == "diamondPowerball":   # 缩成球(释放)→ 持续滚动循环 → 舒展收招
                put(tid, "cast_" + sk, fr[:6], meta, dict(m, rel=5))
                put(tid, "state_diamondRoll", fr[5:13], meta, dict(m, fps=15, rel=-1))
                put(tid, "form_diamondRoll_end", fr[21:], meta, dict(m, fps=15, rel=-1))
            elif sk == "hidingShrink":     # 缩进壳(释放)→ 3 秒缩壳循环 → 探头
                put(tid, "cast_" + sk, fr[:6], meta, m)
                put(tid, "state_hidingShrink", bob(fr[5], m), meta, dict(m, fps=6, rel=-1))
                put(tid, "form_hidingShrink_end", fr[6:], meta, dict(m, fps=15, rel=-1))
            else:
                put(tid, "cast_" + sk, fr, meta, m)
        elif zh == "被动_霰弹":             # 海盗船第二形态: 技能本身换成霰弹(skill_forms), 走 cast
            put(tid, "cast_pirateShipShot", fr, meta, dict(m, rel=5))
        elif zh.startswith("被动_"):
            put(tid, "form_" + FORM[zh[3:]], fr, meta, m)
        else:
            raise SystemExit("没认出 " + zh)
    json.dump(meta, open(OUT + tid + "/seq.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
    print(tid, sorted(meta))


for t in sys.argv[1:] or list(SK):
    run(t)
