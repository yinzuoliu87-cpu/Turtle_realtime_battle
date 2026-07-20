# -*- coding: utf-8 -*-
"""只读: 看 591 装备文件夹下的元素名与一个样例描述。"""
import sys, io, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacknplan_sync import HP
OUT = io.open('tools/hp_peek.txt','w',encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a)+'\n')
hp = HP()
kids = hp.children(591)
log('591 子元素数: %d' % len(kids))
for k in sorted(kids.keys()): log('  ', k)
import re
one = [v for k,v in kids.items() if 'p2eq_020' in k]
if one:
    e = hp._req('/designelements/%d' % one[0]['designElementId'])
    log('\n=== 样例(哑铃 p2eq_020) 云端描述 ===')
    log(e.get('description',''))
OUT.close(); print('ok')
