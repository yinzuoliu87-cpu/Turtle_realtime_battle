# -*- coding: utf-8 -*-
"""edit_equip_text.py — 按【装备 id 或名字 + 字段】精确改一段装备文案。

★与 tools/edit_pet_text.py 同源同理由(2026-08-20): 用 `str.replace` 改 json,
  同一句话可能分属好几件装备, 一次替换会改到别人头上。`str.replace` 不知道
  "这句话属于谁", 它只认字符。⇒ 改结构化数据必须走结构。

用法:
  python tools/edit_equip_text.py <装备id或中文名> <字段> <旧串> <新串>
  例: python tools/edit_equip_text.py p2eq_077 effectDesc1 "降为 5 点。" "降为 5 点。\n受到的治疗封顶 1 点。"

★只改指名的那一件; 旧串在该字段里出现不是恰好 1 次就报错退出, 不猜。
"""
import io
import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

P = 'data/phase2-equipment.json'


def main(argv):
    if len(argv) != 5:
        print(__doc__)
        return 2
    key, field, old, new = argv[1:]
    raw = io.open(P, encoding='utf-8').read()
    d = json.loads(raw)
    eqs = d['equipment'] if isinstance(d, dict) and 'equipment' in d else d

    hits = [e for e in eqs if str(e.get('id', '')) == key or str(e.get('name', '')) == key]
    if len(hits) != 1:
        print('[FAIL] 「%s」匹配到 %d 件(要恰好 1 件)' % (key, len(hits)))
        return 1
    t = hits[0]
    cur = str(t.get(field, ''))
    if cur == '':
        print('[FAIL] %s 没有字段 %s (有的字段: %s)'
              % (key, field, ', '.join(k for k in t.keys() if 'esc' in k or 'rief' in k)))
        return 1
    n = cur.count(old)
    if n != 1:
        print('[FAIL] 旧串在 %s.%s 里出现 %d 次(要恰好 1 次) —— 不猜, 你自己缩小范围' % (key, field, n))
        return 1

    enc_old = json.dumps(cur, ensure_ascii=False)[1:-1]
    if raw.count(enc_old) != 1:
        print('[FAIL] 这段原文在文件里出现 %d 次 —— 有别的条目一字不差地重复了它, 手动处理'
              % raw.count(enc_old))
        return 1
    enc_new = json.dumps(cur.replace(old, new), ensure_ascii=False)[1:-1]
    io.open(P, 'w', encoding='utf-8', newline='\n').write(raw.replace(enc_old, enc_new, 1))
    json.load(io.open(P, encoding='utf-8'))          # 写盘后立刻验还能解析
    print('OK  %s(%s).%s  「%s」 → 「%s」' % (t.get('name', '?'), t.get('id', '?'), field, old, new))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
