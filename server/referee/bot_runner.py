# -*- coding: utf-8 -*-
"""bot_runner.py — 按本周排班表到点拉起陪练号(方案书 docs/plans/20261026d-服务器常驻陪练号.md)。

由 systemd 定时器每 5 分钟跑一次(turtle-bot-runner*.timer), 每次:
  ① 读本周时间表(bot_schedule.py 产出, BOT_SCHEDULE 指定路径);
  ② 找出「到点了、还没起过、没过期(晚于 STALE_MIN 分钟就跳过, 不补打)」的上线;
  ③ 同时在跑的陪练客户端不超过 MAX_PAR 个(裁判机还要裁判, 不能抢光 CPU);
  ④ 起一个无头客户端: SIM_DRIVER=1 SIM_SLOT=N SIM_ROUNDS=k SIM_QUIT_WHEN_DONE=1 —— 打完自己退出。
★号跟真人完全一样(用户 10-26「号就跟真人一样」): 客户端走玩家的全部入口(买装 / 布阵 / 对战 / 上传),
  这里只决定「什么时候上线、打几场」。每个号的存档在自己的目录(XDG_DATA_HOME = <BOT_ROOT>/pNN), 跨周保留。
★只用标准库(与 referee_poller.py 同一个约定)。

环境变量(放在 /etc/turtle-referee/env-bots*):
  GODOT_BIN        无头 Godot(与客户端同一个引擎版本)
  BOT_GAME_DIR     陪练号跑的那一版工程(必须 = 玩家手机上的发布版, memory「模拟号必须跑发布版代码」)
  BOT_ROOT         每个号的存档根目录
  BOT_SCHEDULE     本周时间表 JSON
  MAX_PAR          同时在跑的陪练客户端上限(默认 2)
  MAX_PAR_WEEKEND  UTC 周六 / 周日的上限(默认 = MAX_PAR)。周末正式服裁判要算闯关 / 决赛, 内存留给它(10-27 彩排实测)
  STALE_MIN        到点后多久还没起就作废(默认 30)
  BOT_MODE         schedule(默认: 按 BOT_SCHEDULE 时间表) / queue(轮流打到底, 不要时间表; 正式服 10-27 起)
  BOT_COUNT        queue 模式的号数(不设 = bot_schedule.bot_count(REAL_LAST_WEEK))
  PER_HOUR         queue 模式积分赛每小时最多新开几个号(不设 = ceil(号数 / 88), 铺满周二~周五)
  PER_HOUR_GAUNTLET  queue 模式闯关赛每小时几场(不设 = ceil(晋级号还可能打的场数 / 离收盘小时数), 每拍重算)
  GAUNTLET_GAP_H   queue 模式同一个号两次闯关上线至少隔几小时(默认 2)
  TURTLE_BACKEND / TURTLE_SUPABASE 等后端配置原样传给客户端(内测服 / 正式服各一份 env)
用法:
  python3 bot_runner.py            # 定时器调用: 起该起的, 打印做了什么
  python3 bot_runner.py --dry      # 只打印会起哪些
  python3 bot_runner.py --status   # 本周已起 / 待起 / 作废 计数
"""
import datetime as dt
import json
import os
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

GODOT = os.environ.get('GODOT_BIN', '/opt/godot/godot')
GAME = os.environ.get('BOT_GAME_DIR', '')
ROOT = os.environ.get('BOT_ROOT', '/var/lib/turtle-bots')
SCHED = os.environ.get('BOT_SCHEDULE', os.path.join(ROOT, 'schedule.json'))
MAX_PAR = int(os.environ.get('MAX_PAR', '2'))
MAX_PAR_WEEKEND = int(os.environ.get('MAX_PAR_WEEKEND', str(MAX_PAR)))


def par_limit(now: dt.datetime) -> int:
    """这一拍的并发上限: UTC 周六 / 周日用 MAX_PAR_WEEKEND, 其余 MAX_PAR。"""
    return MAX_PAR_WEEKEND if now.weekday() >= 5 else MAX_PAR
STALE_MIN = int(os.environ.get('STALE_MIN', '30'))
## 一次上线最多跑多久: 每局给 MIN_PER_ROUND 分钟 + 余量。超时 ⇒ 整个进程组杀掉、记 killed。
##   ★没有这条, 卡住的客户端永远不退、占死并发位(例: 0.22.1 把整个周日当决赛日, 驱动在决赛日不收工)。
MIN_PER_ROUND = int(os.environ.get('MIN_PER_ROUND', '8'))
SLACK_MIN = int(os.environ.get('SLACK_MIN', '10'))
## 陪练客户端让着裁判: 以最低优先级起(正式服裁判 Nice=5)。
CHILD_NICE = int(os.environ.get('CHILD_NICE', '19'))
STATE = os.path.join(ROOT, 'launched.json')       # {会话键: {pid, at, rounds}}


def now_utc() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def load_json(p: str, default):
    try:
        with open(p, encoding='utf-8') as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def session_key(week: str, slot: int, at: str) -> str:
    return '%s|p%02d|%s' % (week, slot, at)


def due_sessions(plan: dict, now: dt.datetime) -> list:
    out = []
    for b in plan.get('plan', []):
        for s in b['sessions']:
            t = dt.datetime.fromisoformat(s['at'])
            if t <= now:
                out.append((t, b['slot'], s))
    out.sort(key=lambda x: x[0])
    return out


def launch(slot: int, rounds: int) -> int:
    d = os.path.join(ROOT, 'p%02d' % slot)
    os.makedirs(d, exist_ok=True)
    env = dict(os.environ)
    env.update({
        'XDG_DATA_HOME': d, 'APPDATA': d,          # user:// 落在这个号自己的目录(Linux 认 XDG, 两个都设见 CLAUDE.md §2)
        'SHIP': '1', 'QUIET': '1',
        'SIM_AUTOPILOT': '1', 'SIM_DRIVER': '1',
        'SIM_SLOT': str(slot), 'SIM_ROUNDS': str(rounds),
        'SIM_QUIT_WHEN_DONE': '1', 'SIM_TOUR': '0',
        'SIM_SHOT_DIR': os.path.join(d, 'shots'),
    })
    log = open(os.path.join(d, 'last.log'), 'w', encoding='utf-8')
    kw = {}
    if os.name == 'posix':
        kw['preexec_fn'] = lambda: os.nice(CHILD_NICE)
    p = subprocess.Popen([GODOT, '--headless', '--audio-driver', 'Dummy', '--path', GAME,
                          '--', '--sim-slot=%02d' % slot, '--sim-root=turtle-bots'],
                         env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True, **kw)
    return p.pid


def reap_overdue(state: dict, now: dt.datetime) -> int:
    """跑超时的上线整组杀掉(start_new_session ⇒ pid 就是进程组号)。返回杀了几个。"""
    n = 0
    for k, v in state.items():
        if not (isinstance(v, dict) and v.get('pid') and not v.get('killed')):
            continue
        pid = int(v['pid'])
        if not alive(pid):
            continue
        started = dt.datetime.fromisoformat(v['at'])
        limit = dt.timedelta(minutes=int(v.get('rounds', 3)) * MIN_PER_ROUND + SLACK_MIN)
        if now - started > limit:
            try:
                if os.name == 'posix':
                    os.killpg(pid, 9)
                else:
                    os.kill(pid, 9)
            except OSError:
                pass
            v['killed'] = now.isoformat()
            n += 1
            print('超时杀掉 %s(跑了 %d 分钟)' % (k, int((now - started).total_seconds() // 60)))
    return n


## ═══════════════ 轮流打到底(BOT_MODE=queue, 2026-10-27 用户) ═══════════════
## 用户 10-27:「你为啥要排班呢？…凌晨可以打，每个小时都可以打呀，就打到底就好了呀，所有的命都打完了。」
##   ⇒ 不要时间表: 积分赛开着的时候(周二 00:00 ~ 周五 22:30 UTC)一直保持几个号在打, 每个号一上线就打到底
##     (SIM_ROUNDS=16: 打满 16 场或命输光 ⇒ 主菜单被拦 ⇒ 自己退出), 退了换下一个; 每个号每周一次。
##   每小时最多新开 PER_HOUR 个号(默认 = ceil(号数 / 88)), 让一周的号铺满周二~周五, 不在头两天打完。
## 周末(用户 10-27「只有在周五晋级的这个机器人号，你周六才可以去使用…每个小时你看多少个号去打，你得安排好呀」):
##   赛程(phase2_config): 积分赛 11 胜(PROMOTE_WINS)才晋级; 闯关赛 周六 00:00 ~ 周日 17:30, 4 胜晋级 / 3 负出局 / 最多 6 场。
##   服务端挑对手(schema.sql referee_gauntlet_pick): 先找【同战绩】真人快照、30 分钟内刚打过的优先, 没有才用机器人池。
##   ⇒ ① 只起本周 11 胜以上的号(读它自己的存档); ② 每次上线只打 1 场(SIM_ROUNDS=1), 同一个号两次上线至少隔 GAUNTLET_GAP_H 小时;
##     ③ 每小时开几场 = ceil(晋级号还可能打的场数之和 / 离收盘还剩的小时数), 每拍重算 ⇒ 周末每个小时都有号刚打过、各种战绩都有,
##     收盘前打完。没晋级的号周末一个都不起。
## 号数 = bot_schedule.bot_count(上周真人)(与排班模式同一个公式, 不另抄一份)。
BOT_MODE = os.environ.get('BOT_MODE', 'schedule')
QUEUE_STATE = os.path.join(ROOT, 'queue.json')     # {周一日期: {阶段: {pNN: {pid, at, rounds, killed?}}}}
RANKED_ROUNDS = 16
GAUNTLET_ROUNDS = 1           # 周末每次上线打 1 场, 打完下线过一阵再来(见上)
PROMOTE_WINS = 11             # = phase2_config.PROMOTE_WINS(RANKED_QUOTA 16 − (HEARTS_MAX 6 − 1))
GAUNTLET_WINS_IN, GAUNTLET_LOSSES_OUT, GAUNTLET_QUOTA = 4, 3, 6     # = phase2_config 同名常量
GAUNTLET_GAP_H = float(os.environ.get('GAUNTLET_GAP_H', '2'))
RANKED_SPAN_H = 88            # 周二 00:00 ~ 周五 22:30 约 94.5 小时, 留余量按 88 小时铺


def queue_phase(now: dt.datetime) -> str:
    """'ranked' / 'gauntlet' / ''(这一刻不起号: 周一休赛、周五 22:30 后、周日 17:20 后决赛日由服务器代打)。"""
    wd, hm = now.weekday(), now.hour * 60 + now.minute
    if 1 <= wd <= 3 or (wd == 4 and hm < 22 * 60 + 30):
        return 'ranked'
    if wd == 5 or (wd == 6 and hm < 17 * 60 + 20):
        return 'gauntlet'
    return ''


def week_key(now: dt.datetime) -> str:
    return (now - dt.timedelta(days=now.weekday())).date().isoformat()


def queue_bot_count() -> int:
    if os.environ.get('BOT_COUNT', '').strip():
        return int(os.environ['BOT_COUNT'])
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import bot_schedule
    return bot_schedule.bot_count(int(os.environ.get('REAL_LAST_WEEK', '0') or 0))


def per_hour_limit(n_bots: int) -> int:
    """积分赛每小时最多新开几个号: 按 RANKED_SPAN_H 铺满周二~周五。"""
    v = os.environ.get('PER_HOUR', '').strip()
    return int(v) if v else max(1, -(-n_bots // RANKED_SPAN_H))


def week_anchor_ts(now: dt.datetime) -> int:
    return int((now - dt.timedelta(days=now.weekday())).replace(hour=0, minute=0, second=0, microsecond=0).timestamp())


def gauntlet_close(now: dt.datetime) -> dt.datetime:
    """本周不再起闯关号的时刻: 周日 17:20(17:30 收盘, 留 10 分钟打完)。"""
    mon = now - dt.timedelta(days=now.weekday())
    return mon.replace(hour=17, minute=20, second=0, microsecond=0) + dt.timedelta(days=6)


def read_save(slot: int) -> dict:
    """这个号自己的存档(user:// = <BOT_ROOT>/pNN, Godot 再套 godot/app_userdata/<项目名>/)。读不到 = {}。"""
    d = os.path.join(ROOT, 'p%02d' % slot)
    for root, _dirs, files in os.walk(d):
        if 'savegame.json' in files and os.sep + 'app_userdata' + os.sep in root + os.sep:
            return load_json(os.path.join(root, 'savegame.json'), {})
    return {}


def gauntlet_left(sv: dict, anchor: int) -> int:
    """这个号本周闯关赛还可能打几场: 没晋级(或存档不是本周的) = 0; 晋级了 = min(配额剩余, 到 4 胜或 3 负最多还要几场)。"""
    if int(sv.get('week_anchor_ts', 0) or 0) != anchor or int(sv.get('season_wins', 0) or 0) < PROMOTE_WINS:
        return 0
    gw, gl = int(sv.get('gauntlet_wins', 0) or 0), int(sv.get('gauntlet_losses', 0) or 0)
    if gw >= GAUNTLET_WINS_IN or gl >= GAUNTLET_LOSSES_OUT or gw + gl >= GAUNTLET_QUOTA:
        return 0
    return min(GAUNTLET_QUOTA - gw - gl, (GAUNTLET_WINS_IN - gw) + (GAUNTLET_LOSSES_OUT - gl) - 1)


def gauntlet_per_hour(left_total: int, now: dt.datetime) -> int:
    hours = max(1.0, (gauntlet_close(now) - now).total_seconds() / 3600.0)
    v = os.environ.get('PER_HOUR_GAUNTLET', '').strip()
    return int(v) if v else (max(1, -(-left_total // int(hours))) if left_total > 0 else 0)


def queue_tick(state: dict, now: dt.datetime, n_bots: int, par: int, per_hour: int, launch_fn, alive_fn, save_fn=read_save) -> list:
    """一拍: 返回这一拍起了哪些号([(slot, rounds)]), 并就地更新 state。
    纯逻辑(launch_fn / alive_fn / save_fn 注入, 门禁用假的)。积分赛用 per_hour; 闯关赛每小时几场自己按剩余场数算(per_hour 不用)。"""
    phase = queue_phase(now)
    if not phase:
        return []
    wk = state.setdefault(week_key(now), {})
    done = wk.setdefault(phase, {})
    running = [v for ph in wk.values() for v in ph.values() if v.get('pid') and not v.get('killed') and alive_fn(int(v['pid']))]
    running_keys = {k for ph in wk.values() for k, v in ph.items() if v.get('pid') and not v.get('killed') and alive_fn(int(v['pid']))}
    hour0 = now.replace(minute=0, second=0, microsecond=0)
    out = []
    if phase == 'ranked':
        this_hour = sum(1 for v in done.values() if dt.datetime.fromisoformat(v['at']) >= hour0)
        for slot in range(1, n_bots + 1):
            if len(running) + len(out) >= par or this_hour + len(out) >= per_hour:
                break
            key = 'p%02d' % slot
            if key in done:
                continue
            pid = launch_fn(slot, RANKED_ROUNDS)
            done[key] = {'pid': pid, 'at': now.isoformat(), 'rounds': RANKED_ROUNDS}
            out.append((slot, RANKED_ROUNDS))
        return out
    ## 闯关赛: 只起晋级且还没打完的号; 每次 1 场; 同一号两次上线隔 GAUNTLET_GAP_H; 每小时场数按剩余量摊到收盘前
    if now >= gauntlet_close(now):
        return []
    anchor = week_anchor_ts(now)
    left = {}
    for slot in range(1, n_bots + 1):
        n = gauntlet_left(save_fn(slot), anchor)
        if n > 0:
            left[slot] = n
    ph = gauntlet_per_hour(sum(left.values()), now)
    this_hour = sum(1 for v in done.values() for t in v.get('ats', [v['at']]) if dt.datetime.fromisoformat(t) >= hour0)
    gap = dt.timedelta(hours=GAUNTLET_GAP_H)
    cand = []
    for slot in left:
        key = 'p%02d' % slot
        last = done.get(key, {}).get('at')
        if key in running_keys or (last and now - dt.datetime.fromisoformat(last) < gap):
            continue
        cand.append((last or '', slot))
    cand.sort()                                       # 最久没打的先上(从没打过的 '' 排最前)
    for _last, slot in cand:
        if len(running) + len(out) >= par or this_hour + len(out) >= ph:
            break
        key = 'p%02d' % slot
        pid = launch_fn(slot, GAUNTLET_ROUNDS)
        v = done.setdefault(key, {'ats': []})
        v.update({'pid': pid, 'at': now.isoformat(), 'rounds': GAUNTLET_ROUNDS})
        v.pop('killed', None)
        v.setdefault('ats', []).append(now.isoformat())
        out.append((slot, GAUNTLET_ROUNDS))
    return out


def queue_main(dry: bool, status: bool) -> None:
    state = load_json(QUEUE_STATE, {})
    now = now_utc()
    n_bots, par = queue_bot_count(), par_limit(now)
    phase = queue_phase(now)
    per_hour = per_hour_limit(n_bots)
    wk = state.get(week_key(now), {})
    killed = 0
    if not (dry or status):
        flat = {'%s|%s' % (ph, k): v for ph, d in wk.items() for k, v in d.items()}
        killed = reap_overdue(flat, now)
    if status:
        d = wk.get('ranked', {})
        run = sum(1 for v in d.values() if v.get('pid') and not v.get('killed') and alive(int(v['pid'])))
        print('本周 %s 积分赛: 号 %d · 已上线 %d · 在跑 %d · 超时杀掉 %d · 还没轮到 %d' % (
            week_key(now), n_bots, len(d), run, sum(1 for v in d.values() if v.get('killed')), max(0, n_bots - len(d))))
        anchor = week_anchor_ts(now)
        left = {s: gauntlet_left(read_save(s), anchor) for s in range(1, n_bots + 1)}
        promoted = [s for s in range(1, n_bots + 1) if int(read_save(s).get('season_wins', 0) or 0) >= PROMOTE_WINS
                    and int(read_save(s).get('week_anchor_ts', 0) or 0) == anchor]
        g = wk.get('gauntlet', {})
        print('本周 %s 闯关赛: 晋级 %d 个号 · 还没打完 %d 个 · 还可能打 %d 场 · 已上线 %d 次' % (
            week_key(now), len(promoted), sum(1 for v in left.values() if v > 0), sum(left.values()),
            sum(len(v.get('ats', [])) for v in g.values())))
        print('现在阶段: %s · 同时上限 %d · 积分赛每小时最多新开 %d · 闯关赛每小时 %d 场' % (
            phase or '不起号', par, per_hour, gauntlet_per_hour(sum(left.values()), now) if phase == 'gauntlet' else 0))
        return
    if dry:
        fake = json.loads(json.dumps(state))
        for slot, r in queue_tick(fake, now, n_bots, par, per_hour, lambda s, r: 0, alive):
            print('会起 p%02d %s %d 局' % (slot, phase, r))
        return
    if not GAME:
        print('BOT_GAME_DIR 没设, 不起')
        return
    started = queue_tick(state, now, n_bots, par, per_hour, launch, alive)
    for slot, r in started:
        print('起 p%02d %s %d 局 pid=%s' % (slot, phase, r, state[week_key(now)][phase]['p%02d' % slot]['pid']))
    os.makedirs(ROOT, exist_ok=True)
    with open(QUEUE_STATE, 'w', encoding='utf-8') as f:
        json.dump(state, f, ensure_ascii=False)
    print('本轮(%s): 起 %d · 超时杀掉 %d · 同时上限 %d · 每小时上限 %d' % (phase or '不起号', len(started), killed, par, per_hour))


def main() -> None:
    dry = '--dry' in sys.argv
    status = '--status' in sys.argv
    if BOT_MODE == 'queue':
        queue_main(dry, status)
        return
    plan = load_json(SCHED, {})
    if not plan:
        print('没有时间表: %s(先跑 bot_schedule.py)' % SCHED)
        return
    state = load_json(STATE, {})
    now = now_utc()
    killed = 0 if (dry or status) else reap_overdue(state, now)
    running = [k for k, v in state.items() if isinstance(v, dict) and v.get('pid') and not v.get('killed') and alive(int(v['pid']))]
    started = skipped = 0
    par = par_limit(now)
    for t, slot, s in due_sessions(plan, now):
        key = session_key(plan['week'], slot, s['at'])
        if key in state:
            continue
        if now - t > dt.timedelta(minutes=STALE_MIN):
            state[key] = {'stale': True}
            skipped += 1
            continue
        if status:
            continue
        if len(running) >= par:
            break                                      # 下一轮(5 分钟后)再起; 超过 STALE_MIN 就作废, 不堆积
        if dry:
            print('会起 p%02d %s %s 局(%s)' % (slot, s['mode'], s['rounds'], s['at']))
            continue
        if not GAME:
            print('BOT_GAME_DIR 没设, 不起')
            return
        pid = launch(slot, int(s['rounds']))
        state[key] = {'pid': pid, 'at': now.isoformat(), 'rounds': int(s['rounds'])}
        running.append(key)
        started += 1
        print('起 p%02d %s %s 局 pid=%d' % (slot, s['mode'], s['rounds'], pid))
    if status:
        total = sum(len(b['sessions']) for b in plan.get('plan', []))
        done = sum(1 for v in state.values() if isinstance(v, dict) and v.get('pid'))
        stale = sum(1 for v in state.values() if isinstance(v, dict) and v.get('stale'))
        n_killed = sum(1 for v in state.values() if isinstance(v, dict) and v.get('killed'))
        print('本周 %s: 共 %d 次上线 · 已起 %d · 作废 %d · 超时杀掉 %d · 在跑 %d' % (plan.get('week'), total, done, stale, n_killed, len(running)))
        return
    if not dry:
        os.makedirs(ROOT, exist_ok=True)
        with open(STATE, 'w', encoding='utf-8') as f:
            json.dump(state, f, ensure_ascii=False)
        print('本轮: 起 %d · 作废 %d · 超时杀掉 %d · 在跑 %d / %d' % (started, skipped, killed, len(running), par))


if __name__ == '__main__':
    main()
