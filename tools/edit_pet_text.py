# -*- coding: utf-8 -*-
"""edit_pet_text.py — 按【龟 id + 技能名 + 字段】精确改一段文案。**别再用字符串替换改数据。**

★由来(2026-08-20): 我用 `s.replace("（0.3×攻击力）层灼烧", "...")` 改 pets.json,
  那句话在文件里出现 **3 次, 分属凤凰龟和熔岩龟两只不同的龟** —— 一次替换把熔岩的文案
  指向了凤凰的常量。两个常量今天都是 0.3 所以渲染一样, **但凤凰的常量一改, 熔岩就跟着错**,
  而这正是我在根除的那类病。
  `str.replace` 不知道"这句话属于谁"; 它只认字符。⇒ 改结构化数据必须走结构。

用法:
  python tools/edit_pet_text.py <pet_id> <passive|技能名> <字段> <旧串> <新串>
  例: python tools/edit_pet_text.py lava passive desc "0.3×攻击力" "{C:LavaSystem.SLAM_BURN_COEF}×攻击力"

★只改**指名的那一处**; 旧串在该字段里出现不是恰好 1 次就报错退出, 不猜。
"""
import io, json, sys

sys.stdout.reconfigure(encoding='utf-8')

P = 'data/pets.json'


def main(argv):
    if len(argv) != 6:
        print(__doc__)
        return 2
    pid, where, field, old, new = argv[1:]
    raw = io.open(P, encoding='utf-8').read()
    d = json.loads(raw)
    pets = d['pets'] if isinstance(d, dict) and 'pets' in d else d

    target = None
    for p in pets:
        if str(p.get('id', '')) != pid:
            continue
        if where == 'passive':
            target = p.get('passive')
        else:
            for sk in (p.get('skills') or []):
                if str(sk.get('name', '')) == where:
                    target = sk
                    break
        break
    if target is None:
        print('[FAIL] 找不到 %s / %s' % (pid, where))
        return 1
    cur = str(target.get(field, ''))
    if cur == '':
        print('[FAIL] %s/%s 没有字段 %s' % (pid, where, field))
        return 1
    n = cur.count(old)
    if n != 1:
        print('[FAIL] 旧串在 %s/%s.%s 里出现 %d 次(要恰好 1 次) —— 不猜, 你自己缩小范围'
              % (pid, where, field, n))
        return 1

    # ★整段替换: 拿 json 编码后的原文在文件里定位, 保证只动这一段
    enc_old = json.dumps(cur, ensure_ascii=False)[1:-1]
    if raw.count(enc_old) != 1:
        print('[FAIL] 这段原文在文件里出现 %d 次 —— 说明有别的条目一字不差地重复了它, 手动处理'
              % raw.count(enc_old))
        return 1
    enc_new = json.dumps(cur.replace(old, new), ensure_ascii=False)[1:-1]
    io.open(P, 'w', encoding='utf-8', newline='\n').write(raw.replace(enc_old, enc_new, 1))
    json.load(io.open(P, encoding='utf-8'))          # 写盘后立刻验还能解析
    print('OK  %s/%s.%s  「%s」 → 「%s」' % (pid, where, field, old, new))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
