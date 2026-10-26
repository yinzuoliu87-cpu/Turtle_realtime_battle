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
  STALE_MIN        到点后多久还没起就作废(默认 30)
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


def main() -> None:
    dry = '--dry' in sys.argv
    status = '--status' in sys.argv
    plan = load_json(SCHED, {})
    if not plan:
        print('没有时间表: %s(先跑 bot_schedule.py)' % SCHED)
        return
    state = load_json(STATE, {})
    now = now_utc()
    killed = 0 if (dry or status) else reap_overdue(state, now)
    running = [k for k, v in state.items() if isinstance(v, dict) and v.get('pid') and not v.get('killed') and alive(int(v['pid']))]
    started = skipped = 0
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
        if len(running) >= MAX_PAR:
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
        print('本轮: 起 %d · 作废 %d · 超时杀掉 %d · 在跑 %d / %d' % (started, skipped, killed, len(running), MAX_PAR))


if __name__ == '__main__':
    main()
