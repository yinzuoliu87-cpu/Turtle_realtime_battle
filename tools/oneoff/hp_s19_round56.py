# -*- coding: utf-8 -*-
"""S19: 补齐第五轮(0.17.5)+第六轮(0.17.6)龟平衡到云端 (2026-08-02)。

★为什么会漏: S18 同步的是【第四轮】(commit ab5a9a3)。之后权威文档又被
  第五轮(c32bc7f) 和第六轮(7875f75) 改过, 但【没人写对应的同步脚本】——
  云端因此落后了两轮。hp_staleness_check 一直在报, 只是没人补跑。
  → 教训: 改了权威文档就要同批写同步脚本, 不能等下次想起来。

★哪些龟要推是【算出来的, 不是手写清单】: 拿 S18 同步那一版(ab5a9a3)的权威文档
  和 HEAD 逐小节 diff, 内容真变了的才推。手写清单必漏(S18 自己就是手写的 6 只)。

★幂等: 按「龟 · NN ·」前缀定位既有云端元素做 PATCH, 找不到【报错不新建】——
  新建会造出重复元素, 而重复元素比过期元素更难发现。
★所有输出写 tools/hp_s19_report.txt (控制台 GBK 会崩 emoji), 该文件的 mtime
  同时是 hp_staleness_check.py 判"云端是否落后"的基准。
"""
import sys, io, os, re, subprocess
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from hacknplan_sync import HP

DOC_PATH = 'docs/design/28龟技能设计-权威.md'
BASELINE = 'ab5a9a3'          # S18 同步的那一版
OUT = io.open('tools/hp_s19_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')


def parse(text):
    """权威文档按 '## N. 名字' 切小节 → {编号: (名字, 全文)}"""
    out = {}
    for p in re.split(r'\n(?=## )', text):
        m = re.match(r'## (\d+)\.\s*([^\n(（]+)', p.strip())
        if m:
            out[m.group(1)] = (m.group(2).strip(), p.strip())
    return out


def at(rev):
    r = subprocess.run(['git', 'show', '%s:%s' % (rev, DOC_PATH)], capture_output=True)
    return r.stdout.decode('utf-8', 'ignore')


base = parse(at(BASELINE))
now = parse(io.open(DOC_PATH, encoding='utf-8').read())
changed = [k for k in sorted(now, key=lambda x: int(x)) if k not in base or base[k][1] != now[k][1]]

log('=== S19: 第五轮+第六轮补同步 ===')
log('基线 %s: %d 只 / 当前: %d 只 / 内容真变了: %d 只' % (BASELINE, len(base), len(now), len(changed)))
log('')
if not changed:
    log('无变化, 不推。')
    OUT.close()
    print('done (无变化)')
    raise SystemExit

hp = HP()
kids = hp.children(556)
done = miss = 0
for num in changed:
    name, body = now[num]
    nn = num.zfill(2)
    tgt = None
    for cname, el in kids.items():
        if cname.startswith("龟 · %s ·" % nn):
            tgt = (cname, el)
            break
    if tgt is None:
        log('X 云端无对应元素(不新建): %s. %s' % (num, name))
        miss += 1
        continue
    cname, el = tgt
    if len(body) > 8000:
        body = body[:7950] + "\n…(超长截断, 全文见本地)"
    hp._req("/designelements/%d" % el["designElementId"],
            {"name": cname, "description": body}, method="PATCH")
    log('OK %-3s %-10s -> [%d] (%d字)' % (num + '.', name, el["designElementId"], len(body)))
    done += 1

log('')
log('更新 %d / 缺失 %d' % (done, miss))

# ── 回读校验: 不验的话"推成功"只是"请求没报错"(见 CLAUDE.md: 产物才是判据) ──
kids2 = hp.children(556)
bad = []
for num in changed:
    nn = num.zfill(2)
    for cname, el in kids2.items():
        if cname.startswith("龟 · %s ·" % nn):
            desc = (el.get("description") or "")
            head = now[num][1][:40]
            if head[:20] not in desc:
                bad.append("%s 云端内容与本地对不上" % cname)
            break
log('回读校验: %s' % ('全部一致' if not bad else '; '.join(bad)))
OUT.close()
print('done')
