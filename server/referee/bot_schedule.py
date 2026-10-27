# -*- coding: utf-8 -*-
"""bot_schedule.py — 常驻陪练号每周排班表(方案书 docs/plans/20261026d-服务器常驻陪练号.md)。

用户 2026-10-26:「去服务器安排机器人，每个时段都去分布，这样玩家才会以为真的对局」
            「规模你自己判断一下，号就跟真人一样」。

每周一跑一次, 产出本周时间表 JSON: 每个陪练号(= 一个真账号槽位 pNN)哪几个钟点上线、每次打几场。
真正拉起客户端的是 bot_runner.py(按表到点起无头客户端: SIM_DRIVER=1 SIM_SLOT=N SIM_ROUNDS=k SIM_QUIT_WHEN_DONE=1)。

★规模: N = clamp(TARGET − 上周真人活跃数, MIN, MAX) —— 真人越多陪练号越少(方案书 §4.2)。
★三类号: 休闲 30%(每周 4~8 场) / 常规 50%(9~14) / 认真 20%(打满 16)。
  其中 15% 是「冲得快的」: 周二一天打满 16 场(含凌晨) —— 积分赛严格同场次配对,
  不垫这一批的话, 周二晚打到第 10 场以上的真人只剩 0~2 份陪练快照可配(模型实测)。
★同场次覆盖按构造保证, 不靠随机(2026-10-27): 冲得快的里前 COVER_MIN(=3) 个是「垫底号」,
  积分赛全排在周二 COVER_DONE_H(=18) 点之前开打、同一个号两次上线至少隔一个钟点
  ⇒ 每次上线 ≤5 局, 20:00 前一定打完 ⇒ 周二 20:00 起第 1~16 场每档至少 3 份(任何种子、任何 N ≥ 3)。
  起因: 原来冲得快的也按整个周二随机撒, 20~23 点占 23% 的权重; 按真实种子(周一日期序号)扫 52 周,
  N=90 有 4 周、N=60 有 16 周、N=30 有 48 周在周二 20:00 某个高场次不足 3 份(10-26 这周第 14~16 场只有 2 份)。
  门禁 tools/bot_schedule_audit.py ⑤ 现在按真实种子扫 52 周 × N=30/60/90。
★日内曲线是**假设**(仓库里没有逐小时数据): 欧洲手游常见形状, 夜里低、午休小高峰、晚上 18~22 最高。
  上线后用真人数据每周校正 HOUR_W / DAY_W。
★周六闯关: 所有常规/认真号排 2 次上线(每次至多 3 场); 没晋级的号一进主菜单就被拦、自己退出, 不占多少机器。
★号跟真人完全一样: 这里只决定「什么时候上线、打几场」, 买装 / 布阵 / 对战全走客户端自己的逻辑。

用法:
    python server/referee/bot_schedule.py --week 2026-11-02 --real-last-week 12 --out schedule.json
    python server/referee/bot_schedule.py --week 2026-11-02 --bots 90 --summary     # 只打印每小时场数与同场次覆盖
"""
import argparse
import datetime as dt
import json
import random
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

TARGET = 100          # 「看起来有多少人在打」的目标(陪练号 + 真人)
MIN_BOTS = 30         # 真人再多也留这么多, 给高场次垫底
MAX_BOTS = 90
QUOTA = 16            # 积分赛每周场数上限(phase2_config.RANKED_QUOTA)
RANKED_CLOSE_H = 22   # 周五 22:50 封盘 ⇒ 周五最后一个可排的钟点是 22 点(且只排到 22:30 之前开始)
FAST_SHARE = 0.15
COVER_MIN = 3         # 垫底号个数 = 周二 20:00 起每个场次至少有的陪练快照份数
COVER_DONE_H = 18     # 垫底号的积分赛全在周二 0~17 点开打(给 20:00 留 2 小时打完)
## UTC 小时权重(欧洲手游, 假设)
HOUR_W = [1.2, 0.8, 0.5, 0.4, 0.4, 0.6, 1.2, 2.4, 3.2, 3.4, 3.6, 4.0,
          5.0, 5.0, 4.2, 4.2, 4.6, 5.8, 7.4, 8.2, 8.2, 7.4, 5.6, 3.0]
## 积分赛四天各占比: 周二开新周最热, 之后递减
DAY_W = {1: 0.31, 2: 0.25, 3: 0.23, 4: 0.21}      # 周二=1 … 周五=4(相对周一 00:00 的天数)
## 闯关赛(周六 00:00 ~ 周日 17:30)按 6 小时段的占比
GAUNTLET_W = [(5, 0, 8, 0.10), (5, 8, 18, 0.45), (5, 18, 24, 0.30), (6, 0, 17, 0.15)]


def bot_count(real_last_week: int) -> int:
    return max(MIN_BOTS, min(MAX_BOTS, TARGET - real_last_week))


def weekly_matches(rng: random.Random) -> tuple:
    r = rng.random()
    if r < 0.30:
        return 'casual', rng.randint(4, 8)
    if r < 0.80:
        return 'regular', rng.randint(9, 14)
    return 'hardcore', QUOTA


def ranked_hours() -> list:
    out = []
    for d in (1, 2, 3, 4):
        for h in range(24):
            if d == 4 and h > RANKED_CLOSE_H:
                continue
            out.append((d, h))
    return out


def anchor_hours(rng: random.Random, m: int) -> list:
    """垫底号的 m 次上线: 周二 0 ~ COVER_DONE_H-1 点里按 (HOUR_W + 2) 挑 m 个钟点, 两两至少隔一个钟点。
    隔开 ⇒ 同一个号两次上线相差 > 60 分钟: 不重叠(两个客户端抢同一份存档), 也不会同一分钟
    (bot_runner 的会话键是 周|号|时刻, 撞了第二次就被当成已起过、静默跳过 —— 那这个号就打不满 16)。
    m ≤ 6(每次 ≥3 局、只有最后一次可能更少); 每挑一个最多划掉 3 个钟点, 挑完 5 个还剩 ≥ 18−15 个 ⇒ 一定挑得出。"""
    pool = list(range(COVER_DONE_H))
    out = []
    for _ in range(m):
        h = rng.choices(pool, weights=[HOUR_W[x] + 2.0 for x in pool])[0]
        out.append(h)
        pool = [x for x in pool if abs(x - h) > 1]
    return sorted(out)


def build(week_monday: dt.datetime, n_bots: int, seed: int) -> dict:
    rng = random.Random(seed)
    hours = ranked_hours()
    w = [DAY_W[d] * HOUR_W[h] for d, h in hours]
    w_fast = [(HOUR_W[h] + 2.0) if d == 1 else 0.0 for d, h in hours]
    ## N ≥ 20 时就是 15%(规模下限 30 ⇒ 至少 4 个); 只有手动 --bots 给得很小时才补到 COVER_MIN 个
    n_fast = max(int(n_bots * FAST_SHARE), min(n_bots, COVER_MIN))
    bots = []
    for i in range(n_bots):
        slot = i + 1
        fast = i < n_fast
        kind, total = ('fast', QUOTA) if fast else weekly_matches(rng)
        sessions = []
        left = total
        if fast and i < COVER_MIN:
            ## 垫底号: 16 场全在周二 COVER_DONE_H 点前开打 ⇒ 周二 20:00 时第 1~16 场每档都有它一份(按构造, 不靠随机)
            chunks = []
            while left > 0:
                k = min(left, rng.randint(3, 5))
                chunks.append(k)
                left -= k
            for k, h in zip(chunks, anchor_hours(rng, len(chunks))):
                ts = week_monday + dt.timedelta(days=1, hours=h, minutes=rng.randint(0, 59))
                sessions.append({'at': ts.isoformat(), 'mode': 'ranked', 'rounds': k})
        while left > 0:
            k = min(left, rng.randint(3, 5) if fast else rng.randint(2, 4))
            d, h = rng.choices(hours, weights=(w_fast if fast else w))[0]
            minute = rng.randint(0, 29 if (d == 4 and h == RANKED_CLOSE_H) else 59)
            ts = week_monday + dt.timedelta(days=d, hours=h, minutes=minute)
            sessions.append({'at': ts.isoformat(), 'mode': 'ranked', 'rounds': k})
            left -= k
        ## 周六闯关: 常规 / 认真 / 冲得快的都排两次(没晋级的进主菜单就被拦、自己退出)
        if kind != 'casual':
            for _ in range(2):
                seg = rng.choices(GAUNTLET_W, weights=[g[3] for g in GAUNTLET_W])[0]
                d, h0, h1, _w = seg
                h = rng.randint(h0, h1 - 1)
                ts = week_monday + dt.timedelta(days=d, hours=h, minutes=rng.randint(0, 59))
                sessions.append({'at': ts.isoformat(), 'mode': 'gauntlet', 'rounds': 3})
        sessions.sort(key=lambda s: s['at'])
        bots.append({'slot': slot, 'kind': kind, 'ranked_total': total, 'sessions': sessions})
    return {'week': week_monday.date().isoformat(), 'seed': seed, 'bots': n_bots, 'plan': bots}


def summary(plan: dict) -> None:
    """每小时陪练场数 + 「真人在某时刻打第 k 场时, 本周已有多少份同场次陪练快照」(<3 记 *)。"""
    monday = dt.datetime.fromisoformat(plan['week'] + 'T00:00:00+00:00')
    per = {}
    plays = []          # (时刻, 打完的第几场)
    for b in plan['plan']:
        n = 0
        for s in b['sessions']:
            if s['mode'] != 'ranked':
                continue
            t = dt.datetime.fromisoformat(s['at'])
            key = ((t - monday).days, t.hour)
            per[key] = per.get(key, 0) + s['rounds']
            for _ in range(s['rounds']):
                plays.append((t, n))
                n += 1
    names = {1: '周二', 2: '周三', 3: '周四', 4: '周五'}
    total = sum(per.values())
    print('陪练号 %d 个 · 本周积分赛 %d 场(人均 %.1f)' % (plan['bots'], total, total / max(1, plan['bots'])))
    for d in (1, 2, 3, 4):
        row = [per.get((d, h), 0) for h in range(24)]
        print('%s 合计 %3d 场 | 每小时 %s' % (names[d], sum(row), ' '.join('%2d' % x for x in row)))
    print('同场次覆盖(真人打第 k 场时可配的陪练快照数, <3 记 *):')
    for d, h in [(1, 8), (1, 20), (2, 20), (3, 20), (4, 20)]:
        at = monday + dt.timedelta(days=d, hours=h)
        cnt = [0] * QUOTA
        for t, n in plays:
            if t <= at:
                cnt[n] += 1
        print('  %s %02d:00 | %s' % (names[d], h, ' '.join(('%2d*' if c < 3 else '%2d ') % c for c in cnt)))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--week', required=True, help='本周周一日期(UTC), 如 2026-11-02')
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--bots', type=int, help='直接指定陪练号数')
    g.add_argument('--real-last-week', type=int, help='上周真人活跃数 ⇒ 按 TARGET 算陪练号数')
    ap.add_argument('--seed', type=int, default=0, help='默认 = 周一日期的序号(每周不同、可复现)')
    ap.add_argument('--out', help='时间表 JSON 输出路径')
    ap.add_argument('--summary', action='store_true')
    a = ap.parse_args()
    day = dt.datetime.fromisoformat(a.week + 'T00:00:00+00:00')
    ## 给的不是周一 ⇒ 归到那一周的周一(周一 00:05 那次没跑上、周二补跑时也能出本周的表; 已过去的上线由 runner 作废)。
    monday = day - dt.timedelta(days=day.weekday())
    if monday != day:
        print('--week %s 是星期%d ⇒ 按本周周一 %s 排' % (a.week, day.weekday() + 1, monday.date().isoformat()))
    n = a.bots if a.bots is not None else bot_count(a.real_last_week)
    plan = build(monday, n, a.seed or monday.toordinal())
    if a.out:
        with open(a.out, 'w', encoding='utf-8') as f:
            json.dump(plan, f, ensure_ascii=False, indent=1)
        print('写出 %s(%d 个号, %d 次上线)' % (a.out, n, sum(len(b['sessions']) for b in plan['plan'])))
    if a.summary or not a.out:
        summary(plan)


if __name__ == '__main__':
    main()
