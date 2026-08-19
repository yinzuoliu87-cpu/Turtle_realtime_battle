# -*- coding: utf-8 -*-
"""逐只龟把【文案】和【实现代码】摆在一起, 供人逐条读。

★这不是自动判据 —— 前面那条 text_claim_audit 只能机检三类(周期/选靶/范围)。
  "这技能到底干什么、文案说全了没有"只能人读。这个脚本负责把材料备齐。
用法: python review.py <龟id> [<龟id> ...]
"""
import io, sys, json, re
sys.path.insert(0, 'tools')
import pet_code_scope as S
NL = chr(10)
src = S.load_src()
dm = S.dispatch_map(src)
rb = src.get('scripts/scenes/RealtimeBattle3DScene.gd', '')
d = json.load(io.open('data/pets.json', encoding='utf-8'))
pets = d if isinstance(d, list) else d['pets']
def clean(t):
    return re.sub(r'<[^>]*>', '', str(t or '')).replace(NL, ' ⏎ ')
out = []
for pid in sys.argv[1:]:
    for x in pets:
        if str(x.get('id')) != pid: continue
        out.append('#################### %s (%s) ####################' % (x.get('name'), pid))
        pa = x.get('passive') or {}
        out.append('--- 被动【%s】' % pa.get('name', ''))
        out.append('  文案: ' + clean(pa.get('brief'))[:400])
        blk = []
        lines = rb.split(NL)
        i = 0
        while i < len(lines):
            if ('u["id"] == "%s"' % pid) in lines[i]:
                base = len(lines[i]) - len(lines[i].lstrip())
                blk.append(lines[i]); j = i + 1
                while j < len(lines):
                    ln = lines[j]
                    if ln.strip() and (len(ln) - len(ln.lstrip())) <= base:
                        break
                    blk.append(ln); j += 1
                i = j
            else:
                i += 1
        out.append('  代码(主场景 id 分支, 前 1400 字):')
        out.append('    ' + NL.join(blk)[:1400].replace(NL, NL + '    '))
        for sk in (x.get('skillPool') or []):
            t = str(sk.get('type', ''))
            out.append('--- 技能【%s】type=%s' % (sk.get('name'), t))
            out.append('  文案: ' + clean(sk.get('brief'))[:400])
            fn = dm.get(t)
            if fn:
                _p, funcs, _c = S.func_scope(src, fn, depth=2)
                body = NL.join(b for _n, b in funcs)
                out.append('  代码 %s (前 1500 字):' % fn)
                out.append('    ' + body[:1500].replace(NL, NL + '    '))
            else:
                m = re.search(r'^\s*"%s":\s*\{[^}]*\}.*$' % re.escape(pid), rb, re.M)
                out.append('  代码(普攻表): ' + (m.group(0).strip() if m else '找不到'))
        out.append('')
io.open(r'C:\Users\Louis\Desktop\review.txt', 'w', encoding='utf-8-sig', newline=NL).write(NL.join(out))
print('lines %d' % len(out))
