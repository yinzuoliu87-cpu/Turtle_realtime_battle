# -*- coding: utf-8 -*-
"""只读抽验: 云端某装备描述 vs 本地。"""
import sys, io, os, json, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacknplan_sync import HP
OUT=io.open('tools/hp_verify1.txt','w',encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a)+'\n')
hp=HP(); kids=hp.children(591)
for tid in ['p2eq_020','p2eq_039','p2eq_059']:
    el=[v for k,v in kids.items() if tid in k]
    if not el: log('云端无',tid); continue
    e=hp._req('/designelements/%d'%el[0]['designElementId'])
    log('=== %s ==='%tid); log(e.get('description','')[:420]); log('')
OUT.close(); print('ok')
