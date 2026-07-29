# -*- coding: utf-8 -*-
"""S18: 第四轮技能平衡 + 龙蛋削弱 (2026-07-29)。只推内容真变了的东西。

推两批:
  ① 6 只龟的权威文档小节 → 云端「龟 · NN ·」元素   (闪电/财神/双头/幽灵/忍者/小龟)
  ② 龙蛋一件装备          → 云端「p2eq_024」元素

★幂等: 按前缀定位既有云端元素做 PATCH, 找不到【报错不新建】——
  新建会造出重复元素, 而重复元素比过期元素更难发现。
★所有输出写 tools/hp_s18_report.txt (控制台 GBK 会崩 emoji), 该文件的 mtime
  同时是 hp_staleness_check.py 判"云端是否落后"的基准。
"""
import sys, io, os, re, json
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from hacknplan_sync import HP

DOC = io.open('docs/design/28龟技能设计-权威.md', encoding='utf-8').read()
OUT = io.open('tools/hp_s18_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')

# 第四轮改动的 6 只(编号取自权威文档小节标题)
CHANGED = ['1. 小龟', '7. 忍者龟', '8. 双头龟', '9. 幽灵龟', '11. 财神龟', '19. 闪电龟']

secs = {}
for p in re.split(r'\n(?=## )', DOC):
    m = re.match(r'## (.+)', p.strip())
    if m:
        secs[m.group(1).strip()] = p.strip()

hp = HP()
kids = hp.children(556)
done = miss = 0

log('=== ① 6 只龟 ===')
for pref in CHANGED:
    body = None
    for k, v in secs.items():
        if k.startswith(pref):
            body = v
            break
    if body is None:
        log('X 本地无此章节:', pref); miss += 1; continue
    num = pref.split('.')[0].zfill(2)
    tgt = None
    for cname, el in kids.items():
        if cname.startswith("龟 · %s ·" % num):
            tgt = (cname, el); break
    if tgt is None:
        log('X 云端无对应元素(不新建):', pref); miss += 1; continue
    cname, el = tgt
    if len(body) > 8000:
        body = body[:7950] + "\n…(超长截断, 全文见本地)"
    hp._req("/designelements/%d" % el["designElementId"],
            {"name": cname, "description": body}, method="PATCH")
    log('OK %-12s -> [%d] (%d字)' % (pref, el["designElementId"], len(body)))
    done += 1

# ── ② 龙蛋 ──
log('')
log('=== ② 龙蛋(p2eq_024) ===')
eq = json.load(io.open('data/phase2-equipment.json', encoding='utf-8'))
eq = eq if isinstance(eq, list) else next(v for v in eq.values() if isinstance(v, list))
egg = [e for e in eq if e['id'] == 'p2eq_024']
if not egg:
    log('X 本地 json 里没有 p2eq_024'); miss += 1
else:
    e = egg[0]
    # 装备挂在 591 文件夹下(见 hp_s9_equip.py), 按 id 尾缀匹配而非名字
    ekids = hp.children(591)
    tgt = None
    for cname, el in ekids.items():
        if 'p2eq_024' in cname:
            tgt = (cname, el); break
    if tgt is None:
        log('X 云端无 p2eq_024 元素(不新建)'); miss += 1
    else:
        cname, el = tgt
        desc = ('**费用** %s ｜ **属性** %s\n\n%s\n\n'
                '_2026-07-29 第四轮削弱: 攻30/55/300→20/45/70 · 魔穿15/25/50→8/15/27 · '
                '喷火龙 50/120/1500+0.7/1.0/2.0×攻 → 45/80/120+1×攻(伤害与治疗同口径) · '
                '灼烧30/45/70→20/35/50。原 ★3 攻击力 300 是全表第三高、只输给两件 5 费装备。_'
                % (e.get('cost'), e.get('baseStats1'), e.get('effectDesc1')))
        hp._req("/designelements/%d" % el["designElementId"],
                {"name": cname, "description": desc}, method="PATCH")
        log('OK 龙蛋 -> [%d] (%d字)' % (el["designElementId"], len(desc)))
        done += 1

log('')
log('更新 %d, 失败 %d' % (done, miss))
OUT.close()
print('done: %d ok / %d miss  -> tools/hp_s18_report.txt' % (done, miss))
sys.exit(1 if miss else 0)
