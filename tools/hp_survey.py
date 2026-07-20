# -*- coding: utf-8 -*-
"""只读: 拉 HacknPlan 全树, 输出结构与元素清单(不做任何写操作)。"""
import sys, io, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacknplan_sync import HP
OUT = io.open('tools/hp_survey_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')
hp = HP()
tree = hp._req("/designelements?parentId=0")
TYPE = {1:'Chapter',2:'World',3:'Zone',4:'Level',5:'Stage',6:'Location',7:'Menu',8:'Cutscene',9:'System',10:'Mechanic',11:'Character',12:'Object',13:'Folder'}
tot = [0]
def walk(els, d=0):
    for e in sorted(els, key=lambda x: x.get('name','')):
        tot[0] += 1
        dl = len(e.get('description') or '')
        log('%s- [%d] %s  (%s, desc %d字)' % ('  '*d, e.get('designElementId',0), e.get('name',''), TYPE.get(e.get('designElementTypeId'),'?'), dl))
        walk(e.get('children', []), d+1)
log('=== HacknPlan 项目 238168 全树 ===')
walk(tree)
log('\n总元素数: %d' % tot[0])
OUT.close()
print('done')
