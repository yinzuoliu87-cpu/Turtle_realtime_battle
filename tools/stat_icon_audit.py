# -*- coding: utf-8 -*-
"""属性图标纪律 —— 2026-10-01 建。

由来: 用户 2026-09-30「属性图标我的建议是现在我们的所有属性图标全部重做, 要像素风,
风格简洁统一, 你看 lol 没这么花」。重做前实测旧素材: 14 张 32x32 里色数从 4 到 364,
同一套里并存两种做法(2 张 4 色像素图 + 12 张几百色渐变缩图)。

★本脚本守三件事, 都是那次重做暴露出来的:
  ① 每个属性 key 都得有图标 —— 重做时才发现属性有 19 种而图标只有 14 张, **缺 8 个**
     (护甲穿透/法术穿透/龟能上限/龟能充能/治疗与护盾/治疗强度/护盾强度/反伤)。
     是用户问「治疗强度和护盾强度呢」才查出来的, 不是我自己发现的。
  ② 色数上限 —— 旧素材 mr-icon 一张 364 色, 重做后全套最高 50 色。
     定在 80: 给后来者留余量, 但挡住"又贴一张高清缩图"。
  ③ 尺寸统一 + .import 齐全 —— 换了 png 不 import, Godot 用的还是旧缓存。

⚠ 不守的: 16px 下的**可读性**。那只能人眼看 —— 实测弓 / 翅膀 / 跑步的人在 16px 必糊,
   256 个像素格画不出细长分叉的形状。所以 aspd 最后用的是沙漏、dodge 用的是龙卷风。
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

ICON_DIR = 'assets/sprites/stats'
MAX_COLORS = 80          # 单张不重复 RGB 上限
SIZE = (32, 32)

# 属性 key(代码里的) → 图标文件名。值为空串 = 该属性【有意】不配图标。
KEY2ICON = {
    'hp': 'hp', 'atk': 'atk', 'def': 'def', 'mr': 'mr',
    'crit': 'crit', 'critDmg': 'crit-dmg',
    'armorPen': 'armorpen', 'magicPen': 'magicpen',
    '_maxEnergy': 'maxenergy', '_echargePct': 'echarge',
    '_aspdPct': 'aspd', '_mspdPct': 'move', '_rangeAdd': 'range',
    '_lifestealPct': 'lifesteal', 'dodgePct': 'dodge',
    'shieldHealPct': 'shieldheal', 'healAmp': 'healamp', 'shieldAmp': 'shieldamp',
    'reflectPct': 'reflect',
}

fails = []


def chk(name, bad):
    if bad:
        fails.append('%s: %s' % (name, bad if isinstance(bad, str) else ' / '.join(map(str, bad[:6]))))
        print('  [FAIL] %s' % name)
    else:
        print('  [ OK ] %s' % name)


def main():
    # ── ① 代码里用到的每个属性 key 都有图标 ──
    es = io.open('scripts/gamedata/equip_stats.gd', encoding='utf-8', errors='replace').read()
    used = set(re.findall(r'"(_?[a-zA-Z][a-zA-Z0-9_]*)" *:', es))
    used = set(k for k in used if not k.startswith('p2eq'))
    print('  [分母] equip_stats.gd 里用到 %d 个属性 key' % len(used))
    if not used:
        chk('★分母: 真的扫到属性 key(扫到 0 个就是正则烂了, 下面全是空检查)', '扫到 0 个')
        return
    missing = []
    for k in sorted(used):
        icon = KEY2ICON.get(k)
        if icon is None:
            missing.append('%s 没登记进 KEY2ICON(新属性要么配图标, 要么在表里显式留空)' % k)
        elif icon and not os.path.exists('%s/%s-icon.png' % (ICON_DIR, icon)):
            missing.append('%s 应有 %s-icon.png, 不在盘上' % (k, icon))
    chk('★每个属性 key 都有图标(2026-09-30 重做时查出缺 8 个, 就是没人守这条)', missing)

    # ── ②③ 每张图标: 色数 / 尺寸 / .import ──
    try:
        from PIL import Image
    except ImportError:
        print('  [skip] 没有 PIL, 跳过像素级检查')
        if not fails:
            print('')
            print('ALL OK — 属性图标纪律(本轮只查了 key 覆盖)')
        return
    pngs = sorted(f for f in os.listdir(ICON_DIR) if f.endswith('.png'))
    print('  [分母] 盘上 %d 张图标' % len(pngs))
    if not pngs:
        chk('★分母: 图标目录非空', '一张都没有')
        return
    too_many, wrong_size, no_import = [], [], []
    worst = ('', 0)
    for f in pngs:
        p = '%s/%s' % (ICON_DIR, f)
        im = Image.open(p).convert('RGBA')
        if im.size != SIZE:
            wrong_size.append('%s 是 %dx%d (应为 %dx%d)' % (f, im.size[0], im.size[1], SIZE[0], SIZE[1]))
        seen = set()
        for y in range(im.size[1]):
            for x in range(im.size[0]):
                px = im.getpixel((x, y))
                if px[3] > 8:
                    seen.add(px[:3])
        if len(seen) > worst[1]:
            worst = (f, len(seen))
        if len(seen) > MAX_COLORS:
            too_many.append('%s %d 色(上限 %d)' % (f, len(seen), MAX_COLORS))
        if not os.path.exists(p + '.import'):
            no_import.append(f)
    print('  [分母] 色数最高的一张: %s = %d 色(上限 %d)' % (worst[0], worst[1], MAX_COLORS))
    chk('★单张色数 ≤ %d(旧素材 mr-icon 曾 364 色)' % MAX_COLORS, too_many)
    chk('★尺寸统一 %dx%d' % SIZE, wrong_size)
    chk('★每张都有 .import(换了 png 不 import, Godot 用的还是旧缓存)', no_import)

    print('')
    if fails:
        for f in fails:
            print('  %s' % f)
        print('FAILED: %d 处' % len(fails))
        sys.exit(1)
    print('ALL OK — 属性图标纪律(key 覆盖 / 色数 / 尺寸 / import)')


main()
