# -*- coding: utf-8 -*-
"""⛔ 已被第四轮覆盖, 不要再跑 —— 跑了会报假 FAIL。

第三轮改动·显示面正向验证 (2026-07-28)。

★2026-07-29 第四轮平衡改掉了本脚本断言过的一批值(幽灵登场诅咒 4→2.5 秒、财神梭哈/骰子、忍者被动…),
  所以这里的期望值现在是【第三轮的历史留痕】, 不是当前事实。故意不更新 —— 更新就毁掉第三轮的记录了。
  第四轮的对应校验已进【常备门禁】: tests/verify_turtle_balance_r4.gd + tests/verify_lightning_buff.gd
  (常备门禁跟着 run-tests.sh 每次跑, 不会像一次性脚本这样烂掉)。

★查"三个显示面渲染出来的数 == 代码实际值", 不是查"旧值没了"。
  三个面(选龟被动chip / 选龟技能tooltip / 局内信息面板 / 图鉴)全部走 SkillText 渲染 data/pets.json,
  没有独立数据源 —— 所以校 pets.json + skill_energy 即等于校全部显示面。
★旧值断言必须【锚到具体那一句】: 幽灵死亡诅咒仍是 5 秒(只有登场改 4), 整段禁"5 秒诅咒"会误报。
"""
import io,sys,json,re
sys.stdout=io.TextIOWrapper(sys.stdout.buffer,encoding='utf-8')
d=json.load(io.open('data/pets.json',encoding='utf-8'))
P={x['id']:x for x in (d if isinstance(d,list) else d['pets'])}
def txt(o): return re.sub(r'<[^>]+>','',json.dumps(o,ensure_ascii=False))
C=[('angel',('skillPool',1),['2.5*ATK','当前输出最高的友军'],['1.2*ATK','最低血','生命值最低']),
   ('angel',('skillPool',3),['5 点龟能','1% 攻击力'],[]),
   ('ice',('skillPool',2),['2.5*ATK','眩晕'],['冻结 2.5秒','0.6*ATK']),
   ('gambler',('passive',),['6倍攻击速度'],['3.3倍']),
   ('gambler',('skillPool',1),['2*ATK','1*ATK'],['{N:ATK}','0.25*ATK']),
   ('gambler',('skillPool',2),[],['穿透']),
   ('fortune',('passive',),['70 点龟能','20%'],[]),
   ('fortune',('skillPool',2),['免疫控制','金盾'],['被眩晕或击飞时暂停']),
   ('dice',('passive',),['+70%'],['+50%']),
   ('dice',('skillPool',1),['1.5*ATK'],['1.2*ATK']),
   ('dice',('skillPool',3),['7~11','0.2*ATK'],['4 + 骰子点数','点数1~6']),
   ('dice',('skillPool',2),['50% 生命偷取'],[]),
   ('line',('passive',),['(0.5×攻击力)%'],[]),
   ('ghost',('passive',),['登场瞬间对全部敌人各施加 4 秒诅咒'],['登场瞬间对全部敌人各施加 5 秒诅咒']),
   ('ghost',('skillPool',0),['0.5*ATK','0.7*ATK'],['0.4*ATK','0.9*ATK']),
   ('ghost',('skillPool',2),['2*ATK'],['2.5*ATK']),
   ('cyber',('skillPool',0),['第一个敌人','50%'],[]),
   ('cyber',('skillPool',2),['4秒','锁龟能'],['5秒']),
   ('phoenix',('skillPool',0),['0.04×攻击力'],['0.07×攻击力']),
   ('phoenix',('skillPool',2),['0.5×攻击力'],['0.6×攻击力'])]
n=bad=0
for tid,path,must,mustnot in C:
    o=P[tid]
    for k in path: o=o[k]
    s=txt(o)
    for w in must:
        n+=1
        if w not in s: print('  X %-9s %-14s 缺 %r'%(tid,'.'.join(map(str,path)),w)); bad+=1
    for w in mustnot:
        n+=1
        if w in s: print('  X %-9s %-14s 残留 %r'%(tid,'.'.join(map(str,path)),w)); bad+=1
for tid,f,v in [('dice','hp',950),('dice','def',14),('dice','mr',12),('phoenix','atk',39)]:
    n+=1
    if P[tid][f]!=v: print('  X %s.%s = %s (应 %s)'%(tid,f,P[tid][f],v)); bad+=1
se=io.open('scripts/systems/skill_energy.gd',encoding='utf-8').read()
for k,v in [('diceAllIn',80),('diceFlashStrike',80),('diceFate',80),('ghostStorm',80)]:
    n+=1
    m=re.search(r'"%s":\s*([\d.]+)'%k, se)
    if not m or abs(float(m.group(1))-v)>0.01: print('  X 龟能 %s = %s (应 %s)'%(k,m.group(1) if m else '?',v)); bad+=1
print()
print('  分母 %d 条断言, 失败 %d'%(n,bad))
print('  ALL PASS' if bad==0 else '  有分歧')
sys.exit(1 if bad else 0)
