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
                   ★queue 模式周六 / 周日一个号都不起: 闯关赛改在线瑞士轮(方案书 20261027b), 陪练号由
                   gauntlet_bot_planner.py(常驻)按格子拉上线, 它调本文件的 launch。
  BOT_JEMALLOC     设成 1 ⇒ 陪练客户端用 jemalloc(LD_PRELOAD): glibc 不把释放的内存还给系统, 一个号常驻约 0.75GB,
                   换 jemalloc 后中位约 0.36GB(10-27 内存调查)。默认关。只作用于本文件拉起的客户端, 裁判不受影响。
  BOT_JEMALLOC_LIB libjemalloc.so.2 的路径(默认 /usr/lib/x86_64-linux-gnu/libjemalloc.so.2; 文件不在就不设、打一行警告)
  BOT_MALLOC_CONF  jemalloc 参数(默认 = 内存调查实验 sweep_lx.sh 用的 background_thread:true,dirty_decay_ms:2000,muzzy_decay_ms:0)
  TURTLE_BACKEND / TURTLE_SUPABASE 等后端配置原样传给客户端(内测服 / 正式服各一份 env; SUPABASE_SERVICE_KEY 不传)
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
import time

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


JEMALLOC_LIB_DEFAULT = '/usr/lib/x86_64-linux-gnu/libjemalloc.so.2'
MALLOC_CONF_DEFAULT = 'background_thread:true,dirty_decay_ms:2000,muzzy_decay_ms:0'


def alloc_env() -> dict:
    """BOT_JEMALLOC=1 时给陪练客户端的 LD_PRELOAD / MALLOC_CONF(每次拉号时读环境; 默认关 = 空)。"""
    if os.environ.get('BOT_JEMALLOC', '').strip().lower() not in ('1', 'true', 'yes', 'on'):
        return {}
    lib = os.environ.get('BOT_JEMALLOC_LIB', '').strip() or JEMALLOC_LIB_DEFAULT
    if not os.path.isfile(lib):
        print('WARN BOT_JEMALLOC=1 但 %s 不存在, 这次照旧用 glibc' % lib)
        return {}
    return {'LD_PRELOAD': lib, 'MALLOC_CONF': os.environ.get('BOT_MALLOC_CONF', '').strip() or MALLOC_CONF_DEFAULT}


def launch(slot: int, rounds: int, extra_env: dict = None) -> int:
    """extra_env: 额外的客户端参数(周末调度器 gauntlet_bot_planner.py 用; 积分赛不传)。"""
    d = os.path.join(ROOT, 'p%02d' % slot)
    os.makedirs(d, exist_ok=True)
    env = dict(os.environ)
    env.pop('SUPABASE_SERVICE_KEY', None)          # 服务端密钥不给客户端(周末调度器的环境里有它)
    env.update({
        'XDG_DATA_HOME': d, 'APPDATA': d,          # user:// 落在这个号自己的目录(Linux 认 XDG, 两个都设见 CLAUDE.md §2)
        'SHIP': '1', 'QUIET': '1',
        'SIM_AUTOPILOT': '1', 'SIM_DRIVER': '1',
        'SIM_SLOT': str(slot), 'SIM_ROUNDS': str(rounds),
        'SIM_QUIT_WHEN_DONE': '1', 'SIM_TOUR': '0',
        'SIM_SHOT_DIR': os.path.join(d, 'shots'),
    })
    env.update(alloc_env())
    env.update(extra_env or {})
    log = open(os.path.join(d, 'last.log'), 'w', encoding='utf-8')
    kw = {}
    if os.name == 'posix':
        kw['preexec_fn'] = lambda: os.nice(CHILD_NICE)
    p = subprocess.Popen([GODOT, '--headless', '--audio-driver', 'Dummy', '--path', GAME,
                          '--', '--sim-slot=%02d' % slot, '--sim-root=turtle-bots'],
                         env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True, **kw)
    return p.pid


## ═══════════════ 杀一次上线(整棵进程树) ═══════════════
## ★2026-10-27 内测服彩排实测: 原来 `os.killpg(包装脚本 pid, 9)` 杀不掉 godot。
##   launch 用 start_new_session ⇒ 包装脚本(GODOT_BIN = godot-bot.sh)是会话首进程、进程组号 = 它的 pid;
##   但包装脚本里的 GNU `timeout` 会自己 setpgid 另开一个进程组(没带 --foreground 时), godot 在 timeout 那一组里 ⇒
##   killpg 只杀掉包装脚本, timeout + godot 照样把剩下的局打完(实测: 杀完 10 秒后 timeout / godot 都还在,
##   sessions.log 也没记这一次 —— 记那一行的包装脚本先死了)。
##   ⇒ 按「会话」杀: 会话号 = 包装脚本的 pid(start_new_session), 里面不管分了几个进程组都在同一个会话里。
##   先杀会话里除包装脚本以外的全部进程(timeout / godot), 包装脚本的 `timeout` 立刻返回 137 ⇒ 它照常把这次上线记进
##   sessions.log 再退出; KILL_GRACE_SEC 秒后会话里还有活的(包括包装脚本)⇒ 整会话再杀一遍。
KILL_GRACE_SEC = 5.0


def _proc_stat(pid: int):
    """/proc/<pid>/stat ⇒ (状态, 父进程, 进程组, 会话); 读不到 = None。
    进程名(第 2 列)可能带空格 / 括号 ⇒ 从最后一个 ')' 之后切。"""
    try:
        with open('/proc/%d/stat' % pid, 'rb') as f:
            raw = f.read().decode('utf-8', 'replace')
    except OSError:
        return None
    return parse_stat(raw)


def parse_stat(raw: str):
    """纯函数(门禁拿造出来的行量它): '/proc/<pid>/stat' 的一行 ⇒ (状态, 父进程, 进程组, 会话); 认不出 = None。"""
    i = raw.rfind(')')
    rest = raw[i + 2:].split() if i >= 0 else []
    if len(rest) < 4:
        return None
    try:
        return rest[0], int(rest[1]), int(rest[2]), int(rest[3])
    except ValueError:
        return None


def session_procs(sid: int) -> list:
    """会话 sid 里还活着的进程(僵尸不算)。没有 /proc(Windows 开发机)= []。"""
    out = []
    if not os.path.isdir('/proc'):
        return out
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        st = _proc_stat(int(name))
        if st is not None and st[3] == sid and not st[0].startswith('Z'):
            out.append(int(name))
    return out


def _sigkill(pid: int) -> bool:
    try:
        os.kill(pid, 9)
        return True
    except OSError:
        return False


def _reap(pid: int) -> None:
    """pid 是本进程的子进程(调度器拉起的)⇒ 收尸, 免得僵尸让 alive() 一直当它活着。不是子进程 ⇒ 什么都不做。"""
    if hasattr(os, 'WNOHANG'):
        try:
            os.waitpid(pid, os.WNOHANG)
        except (ChildProcessError, OSError):
            pass


def kill_tree(pid: int, grace: float = None) -> int:
    """杀掉 launch 拉起的这一次上线(pid = 包装脚本 = 会话首进程)的整棵进程树。返回杀了几个进程。
    调度器「停」和 reap_overdue 超时杀都走这一个。"""
    grace = KILL_GRACE_SEC if grace is None else grace
    if os.name != 'posix' or not os.path.isdir('/proc'):
        return 1 if _sigkill(pid) else 0
    members = session_procs(pid)
    others = [p for p in members if p != pid]
    n = sum(1 for p in others if _sigkill(p))
    if not others:                                   # 没有包装脚本(GODOT_BIN 直接是 godot): 杀它自己
        n += 1 if (pid in members and _sigkill(pid)) else 0
    deadline = time.time() + grace
    while time.time() < deadline:
        _reap(pid)
        if not session_procs(pid):
            return n
        time.sleep(0.1)
    for p in session_procs(pid):                     # 过了宽限还有活的 ⇒ 整会话(含包装脚本)再杀一遍
        n += 1 if _sigkill(p) else 0
    _reap(pid)
    return n


def reap_overdue(state: dict, now: dt.datetime) -> int:
    """跑超时的上线杀掉整棵进程树(kill_tree: 按会话杀, godot 在 timeout 另开的进程组里也杀得到)。返回杀了几个上线。"""
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
            kill_tree(pid)
            v['killed'] = now.isoformat()
            n += 1
            print('超时杀掉 %s(跑了 %d 分钟)' % (k, int((now - started).total_seconds() // 60)))
    return n


## ═══════════════ 轮流打到底(BOT_MODE=queue, 2026-10-27 用户) ═══════════════
## 用户 10-27:「你为啥要排班呢？…凌晨可以打，每个小时都可以打呀，就打到底就好了呀，所有的命都打完了。」
##   ⇒ 不要时间表: 积分赛开着的时候(周二 00:00 ~ 周五 22:30 UTC)一直保持几个号在打, 每个号一上线就打到底
##     (SIM_ROUNDS=16: 打满 16 场或命输光 ⇒ 主菜单被拦 ⇒ 自己退出), 退了换下一个; 每个号每周一次。
##   每小时最多新开 PER_HOUR 个号(默认 = ceil(号数 / 88)), 让一周的号铺满周二~周五, 不在头两天打完。
## 周末(用户 10-27「周六周日我们讲究是在线啊」): 闯关赛改在线瑞士轮(方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md),
##   陪练号和真人走同一个排队、按格子先来先配; 拉哪个号上线由常驻的 gauntlet_bot_planner.py 按 12 个战绩格子决定
##   (它调本文件的 launch)。⇒ 本文件 queue 模式周六 / 周日一个号都不起(以前的「晋级号每次上线打 1 场」作废)。
## 号数 = bot_schedule.bot_count(上周真人)(与排班模式同一个公式, 不另抄一份)。
BOT_MODE = os.environ.get('BOT_MODE', 'schedule')
QUEUE_STATE = os.path.join(ROOT, 'queue.json')     # {周一日期: {阶段: {pNN: {pid, at, rounds, killed?}}}}
RANKED_ROUNDS = 16
PROMOTE_WINS = 11             # = phase2_config.PROMOTE_WINS(RANKED_QUOTA 16 − (HEARTS_MAX 6 − 1))
GAUNTLET_WINS_IN, GAUNTLET_LOSSES_OUT, GAUNTLET_QUOTA = 4, 3, 6     # = phase2_config 同名常量
RANKED_SPAN_H = 88            # 周二 00:00 ~ 周五 22:30 约 94.5 小时, 留余量按 88 小时铺


def queue_phase(now: dt.datetime) -> str:
    """'ranked' / 'gauntlet'(周末: 本文件不起号, 由 gauntlet_bot_planner.py 拉) / ''(周一休赛、周五 22:30 后、周日 17:20 后)。"""
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


def read_save(slot: int) -> dict:
    """这个号自己的存档(user:// = <BOT_ROOT>/pNN, Godot 再套 godot/app_userdata/<项目名>/)。读不到 = {}。"""
    d = os.path.join(ROOT, 'p%02d' % slot)
    for root, _dirs, files in os.walk(d):
        if 'savegame.json' in files and os.sep + 'app_userdata' + os.sep in root + os.sep:
            return load_json(os.path.join(root, 'savegame.json'), {})
    return {}


def gauntlet_left(sv: dict, anchor: int) -> int:
    """这个号本周闯关赛还可能打几场(--status 的总量账): 没晋级(或存档不是本周的) = 0; 晋级了 = min(配额剩余, 到 4 胜或 3 负最多还要几场)。"""
    if int(sv.get('week_anchor_ts', 0) or 0) != anchor or int(sv.get('season_wins', 0) or 0) < PROMOTE_WINS:
        return 0
    gw, gl = int(sv.get('gauntlet_wins', 0) or 0), int(sv.get('gauntlet_losses', 0) or 0)
    if gw >= GAUNTLET_WINS_IN or gl >= GAUNTLET_LOSSES_OUT or gw + gl >= GAUNTLET_QUOTA:
        return 0
    return min(GAUNTLET_QUOTA - gw - gl, (GAUNTLET_WINS_IN - gw) + (GAUNTLET_LOSSES_OUT - gl) - 1)


def queue_tick(state: dict, now: dt.datetime, n_bots: int, par: int, per_hour: int, launch_fn, alive_fn, save_fn=read_save) -> list:
    """一拍: 返回这一拍起了哪些号([(slot, rounds)]), 并就地更新 state。
    纯逻辑(launch_fn / alive_fn / save_fn 注入, 门禁用假的)。只管积分赛(per_hour); 周末一个都不起(见上)。"""
    phase = queue_phase(now)
    if not phase:
        return []
    if phase == 'gauntlet':
        return []                                     # 周末: 在线瑞士轮, 由 gauntlet_bot_planner.py 按格子拉号
    wk = state.setdefault(week_key(now), {})
    done = wk.setdefault(phase, {})
    running = [v for ph in wk.values() for v in ph.values() if v.get('pid') and not v.get('killed') and alive_fn(int(v['pid']))]
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
    return out                                        # (到不了: 周末上面已返回)


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
        print('本周 %s 闯关赛: 晋级 %d 个号 · 还没打完 %d 个 · 还可能打 %d 场(周末由 gauntlet_bot_planner.py 按格子拉号, 本文件不起)' % (
            week_key(now), len(promoted), sum(1 for v in left.values() if v > 0), sum(left.values())))
        print('现在阶段: %s · 同时上限 %d · 积分赛每小时最多新开 %d' % (
            '周末(本文件不起号)' if phase == 'gauntlet' else (phase or '不起号'), par, per_hour))
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
