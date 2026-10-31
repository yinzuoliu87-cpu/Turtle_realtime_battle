#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gauntlet_bot_planner.py — 周末在线闯关赛(周六 00:00 ~ 周日 17:30 UTC)的陪练号调度器。
方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md §4.3。推演门禁 tools/gauntlet_planner_audit.py(拿本文件的 decide 推演整个周末)。

用户 10-27:「假如我在周六凌晨点击锁定，那我是不是能在十分钟或者二十分钟之内匹配到一个对手…掉到零杠一或者一杠零，
那我有人打吗？二杠零、零杠二、一杠一呢…三杠零、二杠一、一杠二…所有的情况」
「我们自己的号都是零杠零开局的…可能掉零杠二、零杠一，怎么去匹到呢？…到周日之后…三杠二这些号，他都还没晋级呢，那怎么处理他们呢？」
「周六周日我们讲究是在线啊」⇒ 陪练号周末**真的上线**: 和真人走同一个排队(锁阵容 → join → 每 2 秒 poll → 服务端按格子先来先配),
打完一局逛商店再排, 本文件只决定**拉哪个号上线、打几局**, 配对一律由服务端排队完成(真人对陪练号、陪练号对陪练号一样)。

格子 = 还没打完的战绩 (胜, 负): 4 胜晋级 / 3 负出局 / 最多 6 场 ⇒ 12 个格子
  (0,0) | (1,0) (0,1) | (2,0) (1,1) (0,2) | (3,0) (2,1) (1,2) | (3,1) (2,2) | (3,2)
一局在格子 P 打完: 赢的去 (w+1, l), 输的去 (w, l+1)。没人能回到浅格子 ⇒ 浅格子的号是整周末的「本钱」。

decide(state, now, rng) 是纯函数(门禁拿真函数推演), 每 10 秒一拍, 按优先级:
  A 真人在等: 某格子有在线真人、同格子没有在线的可配对手 ⇒ 拉一个正停在这个格子的空闲号上线(打 1 局)。
    并发满了就让出一个没在打的低优先级号(打完要退的 / 收尾 / 整段 / 补格子 / 搭档)。永远给真人留 HUMAN_RESERVE 个并发位。
  B 打到底的号(整段 / 收尾)在它的格子里没人可配 ⇒ 同格子在线的号, 或从同格子拉一个空闲号当对手(打 1 局);
    平时总量账有余量时可拉到这一格只剩 1 个, 没余量只拿多余的; 收尾且上一级补得上 / 已没有真人能走到这一格时可拉光。
  C 补格子: 先把「每格 ≥ 1」铺满, 0-0 的本钱够(补完还在本钱线以上)再补到 r(平时 R, 收尾 R_END)。
    缺口按「从哪个上一级格子打一局能补上」求最省的打法(fill_plan: 0-0 缺口最小 → 动用 0-0 最少 → 总局数最少),
    每局 = 同时拉两个同格子的空闲号上线互打; 补格子的号可连打(FILL_ROUNDS), 走到不缺号的格子、或送走就会掏空这一格时就下线停在那里
    (用户「上一级格子自己也要留够」)。先铺真人马上要到的格子(在等 / 正在打的真人的下一格; 开赛按最快的真人 4 分钟一局推)。
  D 整段打完(平时, 协调方 (g)(h)): 每个钟点安排几次「坐下来一口气打到 4 胜 / 3 负」(白天晚上多、深夜少), 挑「超过 R 个」的格子里
    离打完近的、最久没打的多余号; 受总量账约束(空闲号剩余步数 − 预计以后真人要用的步数)。赛况板白天就陆续有人晋级 / 出局。
  E 收尾(周日 12:00 起): 只给「收盘前还有真人能走到的格子」每格留 R_END 个, 其余上过榜的多余号成对打到底(深格子先)。
  收盘前 10 分钟(CLOSE_LOCKOUT_SEC)+ STARTUP_SEC 起不拉号(拉起来也赶不上); 17:20 起让在线没在打的号下线。
  一个号同一时刻只在一个客户端里(在线 / 在算 / 排队条目还有效的都不拉)。0-0 本钱线见 DEFAULTS 的 HUMAN_PRIOR_PER_H / ROOT_SAFETY。

兜底(不归本文件): 某格子的号用光、补也来不及时, 真人等满 180 秒(20261029b)由服务端在 poll 里兜底: 先同格子真人快照, 再机器人池(都只记真人一边)。
  ★2026-10-31(迁移 20261031, 方案书 docs/plans/20261031b-闯关赛开局铺号与早兜底.md): 本文件每拍把「没有陪练号能来」的真人报给服务端
  (gauntlet_planner_mark, 顺带当心跳) —— 陪练号版本与他不同 / 这一格和上一级都没有跟他没交过手的号; 服务端让他们进队满 1 分钟就兜底。
  调度器报过到、心跳却断了 60 秒, 服务端也一样处理。开赛头一小时(OPENING_SEC)给真人留的并发位借给补格子。

输入 state = 服务端 gauntlet_service_state(迁移 server/supabase/migrations/20261027_gauntlet_online_queue.sql, normalize 换成 epoch 秒)
  加本机的进程表 / 记忆:
  close_at / now  收盘(周日 17:30)/ 服务端此刻(app_now, 内测服彩排会拨钟)的 epoch 秒
  waiting   [{account_id, gw, gl, waited_sec, seen_sec, is_bot, opponents}]   心跳有效的排队条目(真人和陪练号都在)
  playing   [{account_id, gw, gl, is_bot, ...}]                               已配上、还在算的局的两边
  bots      [{account_id, gw, gl, in_job, waiting, busy, finished, promoted, last_played_at, opponents}]
            ★「在打」看 in_job(服务端的 busy = 在算 或 在排队); last_played_at = 最近一局结果写回的 epoch 秒(没打过 = None);
            opponents = 本周交过手的人(两个方向)
  running   {account_id: {since, rounds, purpose, g0}}   本机拉起、还活着的陪练客户端(g0 = 拉起时已打场数)
  external_running  同机别的陪练客户端数(bot_runner 积分赛那批还没退的)
  memory    {session_starts: [epoch...], humans: {账号: 第一次看到}}   本机记忆(remember 维护)
输出 [(op, account_id, rounds, purpose, why)]: op = 'launch'(拉上线、打 rounds 局) / 'stop'(让它下线)。

常驻服务(本文件 main): 每 TICK_SEC 秒一拍, 只在周六 00:00 ~ 周日 17:30 干活, 其余时间睡; 服务端 gauntlet_on 关着不动。
  启动时(和每小时)把陪练号账号 id 写进 bot_accounts(读各号存档的 account_id, 用 bot_runner.read_save)。
  拉号用 bot_runner.launch(同一套: 无头 Godot + sim_driver, 每号自己的 user://), 额外传周末参数(见 weekend_env)。
环境变量: SUPABASE_URL / SUPABASE_SERVICE_KEY(/etc/turtle-referee/env), GODOT_BIN / BOT_GAME_DIR(= 正式服当前发布版, 配对要求同版本)/
  BOT_ROOT / TURTLE_* / BOT_JEMALLOC(/etc/turtle-referee/env-bots-prod), MAX_PAR_WEEKEND(周末同时在线上限, 默认 6),
  PLANNER_R / PLANNER_R_END / PLANNER_ROOT_SAFETY, PLANNER_STATE(进程表 / 记忆, 默认 $BOT_ROOT/gauntlet_planner.json),
  PLANNER_ALWAYS=1(内测服彩排: 不按本机钟睡) / PLANNER_WEEK(彩排拨钟到别的周时给那周周一的 epoch), TICK_SEC。
★只用标准库(与 referee_poller.py / bot_runner.py 同一个约定)。★客户端拿不到 SUPABASE_SERVICE_KEY(bot_runner.launch 去掉)。
用法:
  python3 gauntlet_bot_planner.py            # 常驻(systemd 用这个)
  python3 gauntlet_bot_planner.py --once     # 只跑一拍
  python3 gauntlet_bot_planner.py --dry      # 只跑一拍、只打印会拉谁(不拉、不写)
  python3 gauntlet_bot_planner.py --status   # 打印 12 个格子的空闲号 / 在线 / 在打
"""
import argparse
import json
import math
import os
import random
import sys
import time
import urllib.error
import urllib.request

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

## ═══════════════ 赛程(= scripts/gamedata/phase2_config.gd 同名常量; 推演门禁从 gd 读出来对账) ═══════════════
GAUNTLET_WINS_IN = 4
GAUNTLET_LOSSES_OUT = 3
GAUNTLET_QUOTA = 6
GAUNTLET_CLOSE_MIN_UTC = 17 * 60 + 30     # 周日 17:30 收盘(UTC 分钟)
CLOSE_LOCKOUT_SEC = 600                   # 收盘前 10 分钟不开新局


def is_live(w: int, l: int) -> bool:
    """还没打完的战绩(能再排一局)。"""
    return 0 <= w < GAUNTLET_WINS_IN and 0 <= l < GAUNTLET_LOSSES_OUT and w + l < GAUNTLET_QUOTA


## 格子按深度(已打场数)从浅到深、同深度胜场多的在前。从规则推出来, 不手写。
CELLS = tuple(sorted(((w, l) for w in range(GAUNTLET_WINS_IN) for l in range(GAUNTLET_LOSSES_OUT) if is_live(w, l)),
                     key=lambda c: (c[0] + c[1], -c[0])))
CELLSET = frozenset(CELLS)
ROOT = (0, 0)
LAYERS = tuple(tuple(c for c in CELLS if c[0] + c[1] == d) for d in range(max(w + l for w, l in CELLS) + 1))


def parents(c: tuple) -> list:
    """打一局能把号送进 c 的上一级格子: (w, l-1) 输一局 / (w-1, l) 赢一局。"""
    return [p for p in ((c[0], c[1] - 1), (c[0] - 1, c[1])) if p in CELLSET]


def steps_left(w: int, l: int) -> int:
    """在 (w, l) 的号最多还能打几场(总量账的「剩余步数」)。"""
    if not is_live(w, l):
        return 0
    return min(GAUNTLET_QUOTA - w - l, (GAUNTLET_WINS_IN - w) + (GAUNTLET_LOSSES_OUT - l) - 1)


## ═══════════════ 参数 ═══════════════
DEFAULTS = {
    'R': 2,                  # 平时每格候场空闲号(0-0 本钱够时补到 R; 不够时只保「每格 ≥1」)
    'R_END': 2,              # 收尾阶段「还可能有真人走到的格子」每格留几个(推演: 1 个时两个真人同时到一格就有一个走兜底; 2 个不增加收盘没打完的数)
    'TICK_SEC': 10,
    'MAX_PAR': 6,            # 周末同时在线的陪练客户端上限(env MAX_PAR_WEEKEND; 8GB 机器 × 每个 0.75GB, 留内存给裁判)
    'HUMAN_RESERVE': 1,      # 永远给「真人在等」留的并发位
    'ONLINE_SEC': 15,        # 排队条目多久没心跳算离开(= 服务端过期线)
    'LOCKOUT_SEC': CLOSE_LOCKOUT_SEC,
    'STARTUP_SEC': 60,       # 拉起到进排队的上限(Godot 启动 + 登录 + 主菜单 + 选龟 + 入队, 估 40~60 秒)
    'ENDGAME_SEC': 5.5 * 3600,   # 收盘前多久进收尾(17:30 − 5.5h = 周日 12:00)
    'SESSION_ROUNDS': GAUNTLET_QUOTA,   # 整段 / 收尾: 打到 4 胜 / 3 负为止
    'FILL_ROUNDS': 5,        # 补格子的号一次上线最多连打几局(到了不缺号的格子就让它下线停在那)
    'SESSION_SHARE': 0.6,    # 平时「整段打完」的总次数目标 = 晋级号数 × 这个比例(每个钟点至少 1 次; 没有余量的那拍跳过)
    'HUMAN_PRIOR_PER_H': 0.25,   # 0-0 是整周末的本钱(没有格子能补进 0-0, 每个新来的真人第 1 局要用掉一个):
                                 # 本钱线 = 预计以后还会来的真人数 = max(这个先验, 本周已来真人的速率(开赛 3 小时起算)) × 离收盘的小时数 × ROOT_SAFETY + R_END + 1。
                                 # 先验 0.25/h ≈ 一个周末 10 个晋级真人; 来得多时 3 小时内速率就顶上来。
                                 # 补到 R(第二档)和「整段打完」都不许动本钱线以下; 「每格 ≥1」(第一档)不受限
    'ROOT_SAFETY': 1.5,      # 本钱线的保险系数(env PLANNER_ROOT_SAFETY)。推演: 每个晋级真人实际要花 0-0 的号 3~4 个(补「多赢一场」的格子会把另一个号
                             # 送去输的那边)。调到 3.5: 10~15 个晋级真人时兜底约减半, 但 57 个号时周六上午补不到每格 2 个、「整段打完」凑不齐对手,
                             # 09:00 前赛况板上没有陪练号晋级。1.5 = 先保赛况板白天有人晋级 / 出局(协调方要求的断言)
    'HUMAN_GAMES_PER_RUN': 4.6,  # 总量账: 一个真人一整段平均打几局(4 胜 / 3 负 / 6 场, 胜率五五开)
    'HUMAN_STEP_COST': 2.0,      # 真人每打一局, 陪练号要花掉几「步」(陪它打的那一步 + 之后补格子的分摊)
    'FAST_STEP_SEC': 240,    # 最快的真人一局(排队 + 裁判 + 看直播 + 逛店)约 4 分钟 ⇒ 开赛第 t 分钟最深能到 t/4 场
    'FILL_STEP_SEC': 120,    # 补格子的号往下走一格约 2 分钟(连打: 裁判 + 结算 + 稍停)
    'SCARCE_ROOT_KEEP': 2,   # 号不够铺满每格 ≥1 时(cover_plan)0-0 至少留几个。12 个号时留 1 / 留 2 都是最多 9 格, 留 3 只剩 8 格
    'OPENING_SEC': 3600,     # 开赛头多久把真人位借给补格子(decide 里 free 那一段有实测); 0 = 不借
    'OPENING_MAX_PAR': None, # 开赛头 OPENING_SEC 的并发上限(env MAX_PAR_OPENING); None = 与 MAX_PAR 相同
}
SESSIONISH = ('session', 'end')     # 打到底的号: 不算格子里的候场号
## 每次上线等不到对手多久自己下线(客户端 SIM_QUEUE_GIVEUP_SEC)。按用途给: 为真人拉的号等真人, 别的号等搭档。
GIVEUP_SEC = {'serve': 120, 'partner': 240, 'fill': 180, 'session': 300, 'end': 300}
## 每局之间逛商店多久(客户端 SIM_SHOP_MIN_SEC / SIM_SHOP_MAX_SEC)。整段 / 收尾像真人(用户原稿「坐下来 20~30 分钟打完」);
## 补格子的号连打时只稍停(开赛要跑在最快的真人前面)。只打 1 局的(serve / partner)用不到。
SHOP_SEC = {'fill': (10, 40), 'session': (60, 240), 'end': (60, 240), 'serve': (60, 240), 'partner': (60, 240)}
## 「整段打完」坐下的时刻: UTC 每个钟点的权重(玩家只在欧洲 ⇒ UTC ≈ 英国时间; 白天晚上多、深夜少, 每个钟点至少 1 次)。
HOUR_WEIGHTS = (2, 1, 1, 1, 1, 1, 1, 2, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 4, 3)
PURPOSE_RANK = {'exit': -1, 'end': 0, 'session': 1, 'serve': 2, 'fill': 3, 'partner': 4}   # 让位的先后(小的先让; 被真人认领的不让)


def shop_sec(purpose: str) -> tuple:
    return SHOP_SEC.get(purpose, (60, 240))


def saturday_of(close_at: float) -> float:
    """收盘时刻(周日 17:30) ⇒ 本周闯关开赛(周六 00:00 UTC)。"""
    day0 = close_at - (close_at % 86400)
    return day0 - 86400


def week_anchor(t: float) -> int:
    """周一 00:00 UTC 的 epoch 秒(= 服务端 date_trunc('week') = season_week)。"""
    day0 = int(t) - int(t) % 86400
    wd = (int(t) // 86400 + 3) % 7          # 1970-01-01 是周四 ⇒ +3 让周一 = 0
    return day0 - wd * 86400


def close_of_week(week: int) -> float:
    return float(week + 6 * 86400 + GAUNTLET_CLOSE_MIN_UTC * 60)


## ═══════════════ 补格子: 最省的打法 ═══════════════

_PLAN_CACHE = {}


def fill_plan(have: dict, r: int) -> tuple:
    """fill_plan_raw 的记忆化外壳(同样的输入每拍都一样的时候不重算; 输入按 0.5 取整, 结果一样)。"""
    key = (r,) + tuple(round(2.0 * have.get(c, 0.0)) for c in CELLS)
    if key not in _PLAN_CACHE:
        if len(_PLAN_CACHE) > 20000:
            _PLAN_CACHE.clear()
        _PLAN_CACHE[key] = fill_plan_raw({c: key[1 + i] / 2.0 for i, c in enumerate(CELLS)}, r)
    short, xs = _PLAN_CACHE[key]
    return short, dict(xs)


def fill_plan_raw(have: dict, r: int) -> tuple:
    """每格要 ≥ r 个空闲号; have[c] = 现有空闲 + 已在路上的(浮点, 一局两边各 0.5 计)。
    返回 (0-0 缺口, {格子: 要在这一格打几局})。一局在 P 打 = P 出两个号、两个下一格各进一个。
    从最深一层往上逐层定: 每层只枚举「同时喂两个孩子」的那几格, 其余取最小; 按层记忆化。
    目标(字典序): 0-0 缺口最小 → 动用 0-0 的号最少(本钱) → 总局数最少。"""
    memo = {}

    def need(c, x):
        return max(0, int(math.ceil(r + 2 * x - have.get(c, 0.0) - 1e-9)))

    def solve(d, needs):
        key = (d, needs)
        if key in memo:
            return memo[key]
        kids = dict(zip(LAYERS[d], needs))
        ps = LAYERS[d - 1]
        best = [None]

        def dfs(j, got, xs):
            if j == len(ps):
                for c, n in kids.items():
                    if got.get(c, 0) < n:
                        return
                if d - 1 == 0:
                    raw = r + 2 * xs[ROOT] - have.get(ROOT, 0.0)
                    sub = ((max(0, int(math.ceil(raw - 1e-9))), xs[ROOT], 0), {})
                else:
                    sub = solve(d - 1, tuple(need(p, xs[p]) for p in ps))
                cost = (sub[0][0], sub[0][1], sub[0][2] + sum(xs.values()))
                if best[0] is None or cost < best[0][0]:
                    best[0] = (cost, {**sub[1], **xs})
                return
            p = ps[j]
            wc, lc = (p[0] + 1, p[1]), (p[0], p[1] + 1)
            lo = max(0, kids.get(wc, 0) - got.get(wc, 0))
            hi = lo
            if lc in kids:
                rest = max(0, kids[lc] - got.get(lc, 0))
                if (p[0] - 1, p[1] + 1) in CELLSET:      # lc 还有另一个上一级可以分担
                    hi = max(lo, rest)
                else:
                    lo = max(lo, rest)
                    hi = lo
            for x in range(lo, hi + 1):
                g2 = dict(got)
                g2[wc] = g2.get(wc, 0) + x
                g2[lc] = g2.get(lc, 0) + x
                dfs(j + 1, g2, {**xs, p: x})

        dfs(0, {}, {})
        memo[key] = best[0]
        return best[0]

    deep = len(LAYERS) - 1
    cost, xs = solve(deep, tuple(need(c, 0) for c in LAYERS[deep]))
    return cost[0], {c: xs.get(c, 0) for c in CELLS}


## ═══════════════ 号不够铺满每格 ≥1 时: 铺到能铺的最多格 ═══════════════
## 2026-10-27 内测服彩排(12 个号, 只开调度器): 原来照 fill_plan 的「每格 ≥1」打法走, 但号不够时那份打法要从 0-0 支出不存在的号,
##   执行时又规定「送走两个之后这一格自己还留得住 1 个」⇒ 每格只剩 ≤2 个时一局也开不了, 铺到 7 格就停了(17:47 ~ 17:56 一个号都没拉)。
## ★12 个号同时铺满 12 格在数学上做不到: 每局固定从一格拿走 2 个、往两个下一格各送 1 个; 要有号停在 3-2 就得在 3-1 或 2-2 打一局,
##   这两格的每一局都会送走一个打完(4 胜 / 3 负)的号。逐层穷举: 12 个号最多同时铺 9 格(0-0 留 1 或 2 个都是 9 格), 铺满 12 格最少要 23 个号。
## ⇒ 号不够时(fill_plan 的 0-0 缺口 > 0)改用本函数: 现有的号(含在算的那局送下来的)怎么打能让最多的格子 ≥1;
##   0-0 至少留 SCARCE_ROOT_KEEP 个(用户「上一级格子自己也要留够」/ 协调方「不能把 0-0 的本钱一次花光」: 0-0 没有格子能补回来);
##   别的格子按打法可以送空(送空一格、两个下一格各多 1 个 = 多铺一格, 号不够时这是唯一多铺的办法)。
## 目标(字典序): 铺到的格子数 → 浅格子优先(真人都从 0-0 往下走, 浅格子先有人来) → 少动 0-0 → 少打局。

_COVER_CACHE = {}


def cover_plan(cnt: dict, keep_root: int, want=None) -> dict:
    """cnt[格子] = 现有的号(整数); want = 要算进「铺到」的格子(收尾时收盘前没真人能走到的不算, 默认全部)。
    返回 {格子: 在这一格打几局}。逐层(浅 → 深)枚举每格打几局, 按层记忆化。"""
    want = frozenset(CELLS if want is None else want)
    key = (keep_root, tuple(int(cnt.get(c, 0)) for c in CELLS), tuple(sorted(want)))
    if key in _COVER_CACHE:
        return dict(_COVER_CACHE[key])
    if len(_COVER_CACHE) > 20000:
        _COVER_CACHE.clear()
    base = {c: int(cnt.get(c, 0)) for c in CELLS}
    memo = {}

    def go(d, counts):
        mk = (d, counts)
        if mk in memo:
            return memo[mk]
        cells = LAYERS[d]
        ranges = [range(0, max(0, n - (keep_root if c == ROOT else 0)) // 2 + 1) for c, n in zip(cells, counts)]
        best = None

        def rec(i, xs):
            nonlocal best
            if i < len(cells):
                for x in ranges[i]:
                    rec(i + 1, xs + (x,))
                return
            inflow = {}
            cov = wt = 0
            for c, n, x in zip(cells, counts, xs):
                if c in want and n - 2 * x >= 1:
                    cov += 1
                    wt += len(LAYERS) - d
                for q in ((c[0] + 1, c[1]), (c[0], c[1] + 1)):
                    if q in CELLSET:
                        inflow[q] = inflow.get(q, 0) + x
            if d + 1 < len(LAYERS):
                sc, plan = go(d + 1, tuple(base[q] + inflow.get(q, 0) for q in LAYERS[d + 1]))
            else:
                sc, plan = (0, 0, 0, 0), ()
            root_used = 2 * xs[0] if d == 0 else 0
            tot = (cov + sc[0], wt + sc[1], sc[2] - root_used, sc[3] - sum(xs))
            if best is None or tot > best[0]:
                best = (tot, tuple((c, x) for c, x in zip(cells, xs) if x) + plan)
        rec(0, ())
        memo[mk] = best
        return best

    _sc, plan = go(0, (base[ROOT],))
    out = {c: 0 for c in CELLS}
    out.update(dict(plan))
    _COVER_CACHE[key] = out
    return dict(out)


def covered_after(cnt: dict, xs: dict) -> int:
    """cnt 的号按 xs 的打法打完之后, 有几格 ≥1(打完 4 胜 / 3 负的离场)。"""
    left = {c: int(cnt.get(c, 0)) for c in CELLS}
    for c in CELLS:
        x = int(xs.get(c, 0))
        left[c] -= 2 * x
        for q in ((c[0] + 1, c[1]), (c[0], c[1] + 1)):
            if q in left:
                left[q] += x
    return sum(1 for v in left.values() if v >= 1)


_FULL_MIN = {}


def full_cover_min(keep_root: int) -> int:
    """全部号都在 0-0、0-0 留 keep_root 个时, 至少要几个号才能同时铺满 12 格(留 1 = 23, 留 2 = 24)。"""
    if keep_root not in _FULL_MIN:
        _FULL_MIN[keep_root] = next(n for n in range(len(CELLS), 200)
                                    if covered_after({ROOT: n}, cover_plan({ROOT: n}, keep_root)) == len(CELLS))
    return _FULL_MIN[keep_root]


## ═══════════════ 决策(纯函数) ═══════════════

def _seed01(*parts) -> float:
    """按字符串做种子的 [0,1) 稳定随机数(同一输入每拍一样, 不抖)。"""
    h = 2166136261
    for ch in '|'.join(str(p) for p in parts):
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h / 4294967296.0


def sit_slots(hour_start: float, sat0: float, end_t: float, n_promoted: int, cfg: dict) -> list:
    """这个钟点「整段打完」坐下的时刻表(epoch 秒, 升序)。每个钟点至少 1 次, 其余按 HOUR_WEIGHTS 摊。"""
    if hour_start < sat0 or hour_start >= end_t:
        return []
    hours = [sat0 + 3600 * i for i in range(int((end_t - sat0) // 3600))]
    wsum = sum(HOUR_WEIGHTS[int(h // 3600) % 24] for h in hours) or 1
    k_total = cfg['SESSION_SHARE'] * n_promoted
    w = HOUR_WEIGHTS[int(hour_start // 3600) % 24]
    n = max(1, int(round(k_total * w / wsum)))
    return [hour_start + 3600.0 * (i + 0.15 + 0.7 * _seed01('sit', int(hour_start), i)) / n for i in range(n)]


def in_job(b: dict) -> bool:
    """在算的局里(服务端 in_job; 服务端的 busy = 在算 或 在排队, 不能当「在打」用)。没有 in_job 字段的旧形状退回 busy。"""
    return bool(b.get('in_job', b.get('busy')))


def decide(state: dict, now: float, rng: random.Random, cfg: dict = None, trace: list = None) -> list:
    """一拍的决定。trace(可选)收集「这拍为什么没做某件事」, 门禁 / --dry 打印用, 不影响结果。"""
    c = dict(DEFAULTS)
    c.update(cfg or {})
    note = trace.append if trace is not None else (lambda _m: None)
    close = float(state['close_at'])
    sat0 = saturday_of(close)
    lockout = close - c['LOCKOUT_SEC']
    running = state.get('running') or {}
    bots = {b['account_id']: b for b in state.get('bots') or []}
    cmds = []
    if now < sat0:
        return cmds
    if now >= lockout:
        for bid in sorted(running):
            if not in_job(bots.get(bid, {})):
                cmds.append(('stop', bid, 0, 'stop', 'e 收盘前 10 分钟: 在线没在打的号下线'))
        return cmds
    no_launch = now >= lockout - c['STARTUP_SEC']
    endgame_t = close - c['ENDGAME_SEC']
    endgame = now >= endgame_t
    r_top = c['R_END'] if endgame else c['R']
    mem = state.get('memory') or {}
    seen = (mem.get('humans') or {}).values()
    hours_in = max(3.0, (now - sat0) / 3600.0)
    rate = max(c['HUMAN_PRIOR_PER_H'], sum(1 for t in seen if t >= sat0) / hours_in)
    root_reserve = int(math.ceil(c['ROOT_SAFETY'] * rate * max(0.0, lockout - now) / 3600.0)) + c['R_END'] + 1

    ## ── 分类 ──
    opp = {bid: set(b.get('opponents') or ()) for bid, b in bots.items()}

    def met(a, b):
        return b in opp.get(a, ()) or a in opp.get(b, ())

    cell_of, games = {}, {}
    for bid, b in bots.items():
        gw, gl = int(b.get('gw', 0) or 0), int(b.get('gl', 0) or 0)
        games[bid] = gw + gl
        if b.get('promoted', True) and not b.get('finished') and (gw, gl) in CELLSET:
            cell_of[bid] = (gw, gl)

    def purpose(bid):
        return running[bid].get('purpose', 'fill')

    def rounds_left(bid):
        rr = running[bid]
        return int(rr.get('rounds', 1)) - (games.get(bid, 0) - int(rr.get('g0', games.get(bid, 0))))

    queued = {w['account_id'] for w in state.get('waiting') or [] if float(w.get('seen_sec', 0) or 0) <= c['ONLINE_SEC']}
    parked = {cc: [] for cc in CELLS}        # 空闲、不在线、排队里也没有它的有效条目: 可拉
    online = {cc: [] for cc in CELLS}        # 在线、没在打、还要打: 会在这一格排队
    exiting = {cc: 0 for cc in CELLS}        # 在线但打完了(马上下线 ⇒ 停在这一格)
    moving = {cc: 0 for cc in CELLS}         # 在这一格打完这局 / 下一局就成候场号的(各 0.5 进两个下一格)
    for bid, cc in cell_of.items():
        b = bots[bid]
        if bid in running:
            left = rounds_left(bid)
            if in_job(b):
                if purpose(bid) not in SESSIONISH or left <= 1:
                    moving[cc] += 1
            elif left <= 0:
                exiting[cc] += 1
            else:
                online[cc].append(bid)
        elif in_job(b) or bid in queued:           # 刚下线的号 15 秒内排队条目还有效、可能被配上 ⇒ 当作在打
            moving[cc] += 1
        else:
            parked[cc].append(bid)
    for cc in CELLS:
        parked[cc].sort(key=lambda x: (bots[x].get('last_played_at') or -1.0, x))   # 最久没打的在前(没打过的最前)

    humans = {cc: [] for cc in CELLS}
    for wt in state.get('waiting') or []:
        aid = wt['account_id']
        if aid in bots or wt.get('is_bot') or float(wt.get('seen_sec', 0) or 0) > c['ONLINE_SEC']:
            continue
        cc = (int(wt.get('gw', 0) or 0), int(wt.get('gl', 0) or 0))
        if cc in CELLSET:
            humans[cc].append(wt)
            opp.setdefault(aid, set()).update(wt.get('opponents') or ())

    ## ★2026-10-31 开赛头一小时(OPENING_SEC): 给真人留的那个并发位也借给补格子(nonserve_free), 真人来了 A 照样让位 / 等下一个空位。
    ##   正式服 10-31 实测: 周末并发 4 扣掉真人位只剩 3 个 ⇒ 同时只起得了 1 对补格子号, 头一小时 4 个位平均只用了 2 个;
    ##   最快的真人 00:00 开打, 第 4~6 场(3-0 / 2-1 / 1-2 / 3-1 / 2-2 / 3-2)多半赶上格子还空着。推演 108 个号 × 6 个种子 × 35 条路线:
    ##   并发 4 兜底 312 → 209 / 1134 步、并发 6 85 → 43(方案书 20261031b §2)。
    ##   OPENING_MAX_PAR(env MAX_PAR_OPENING, 默认不设 = MAX_PAR): 头一小时另给一个并发上限 —— 要用户点头才设(同机内存余量)。
    ##   号结构上不够铺满 12 格(cover_plan 那一支, < full_cover_min 个晋级号)时不借: 那时卡在号数不在并发, 推演 ⑫(12 个号)借了反而少铺一格。
    opening = now < sat0 + c['OPENING_SEC'] and \
        sum(1 for b in bots.values() if b.get('promoted', True)) >= full_cover_min(c['SCARCE_ROOT_KEEP'])
    par = int(c.get('OPENING_MAX_PAR') or c['MAX_PAR']) if opening else c['MAX_PAR']
    free = par - len(running) - int(state.get('external_running', 0) or 0)
    claimed, taken, stopped = set(), set(), set()

    def avail(cc):
        return [x for x in parked[cc] if x not in taken]

    def take(cc, pred=None):
        for x in parked[cc]:
            if x not in taken and (pred is None or pred(x)):
                return x
        return None

    def launch(bid, rounds, purp, why):
        nonlocal free
        cmds.append(('launch', bid, rounds, purp, why))
        taken.add(bid)
        free -= 1

    def stop(bid, why):
        """★2026-10-31: 一拍里同一个号只停一次 —— 原来 A 让位停掉的号, C 还会把它当在线的补格子号再停一次
        (free 多加 1 ⇒ 多拉一个、超并发上限; 推演借位之后 N=80 开赛那段量出来的)。各段挑「在线号」时也跳过已停的(stopped)。
        ★不记 claimed: 停掉的号会停在这一格候场, C 算「这一格有几个」时要算上它(记成 claimed 推演量出 0-0 本钱 2 小时被补格子花光)。"""
        nonlocal free
        if bid in stopped:
            return
        cmds.append(('stop', bid, 0, 'stop', why))
        stopped.add(bid)
        free += 1

    def nonserve_free():
        return free - (0 if opening else c['HUMAN_RESERVE'])

    def preempt():
        cand = []
        for bid, rr in running.items():
            if bid in claimed or bid in stopped or in_job(bots.get(bid, {})):
                continue
            p = rr.get('purpose', 'fill')
            rank = PURPOSE_RANK['exit'] if (bid not in cell_of or rounds_left(bid) <= 0) else PURPOSE_RANK.get(p, 3)
            cand.append((rank, -float(rr.get('since', 0)), bid))
        return min(cand)[2] if cand else None

    def plays_here(bid, cc):
        """这个号要在 cc 打下一局: 打完是候场号的(不是打到底的), 算进 cc 的「在路上」。"""
        claimed.add(bid)
        if bid not in running or purpose(bid) not in SESSIONISH:
            moving[cc] += 1

    ## ── A 真人在等 ⇒ 同格子在线的号 / 拉一个停在这一格的号 ──
    ## ★2026-10-31 每个没着落的真人还要判「确定没有陪练号能来」(no_bot, 函数末尾报给服务端 ⇒ 进队满 1 分钟就兜底, 迁移 20261031):
    ##   ① 版本不同: 服务端只配同版本, 而陪练号一律跑 BOT_GAME_DIR 那一版(state['bot_version']) ——
    ##      正式服 10-31 周六 00:02 ~ 00:48 测试号 7 局全等满 180 秒就是这个(陪练号 0.22.5、真人 0.22.6)
    ##   ② 这一格没有跟他没交过手的空闲号、在线号, 上一级也没有正要送下来的(在打 / 在线还要打 / 这拍刚拉的)—— 在函数末尾判(C 拉的也算)
    bot_ver = str(state.get('bot_version') or '')
    no_bot = {}                                    # 真人 → 为什么
    unserved = []                                  # (真人, 格子): 这一格没有可拉的号, 末尾再看上一级有没有在路上的

    def same_ver(a, b):
        va, vb = str(a.get('client_version') or ''), str(b.get('client_version') or '')
        return not va or not vb or va == vb

    for cc in sorted(CELLS, key=lambda x: -max([float(h.get('waited_sec', 0) or 0) for h in humans[x]] or [-1])):
        hs = sorted(humans[cc], key=lambda h: -float(h.get('waited_sec', 0) or 0))
        paired = set()
        for i, h in enumerate(hs):                 # 同格子两个在线真人: 服务端排队会配上, 不用拉号
            if h['account_id'] in paired:
                continue
            for h2 in hs[i + 1:]:
                if h2['account_id'] not in paired and not met(h['account_id'], h2['account_id']) and same_ver(h, h2):
                    paired.update((h['account_id'], h2['account_id']))
                    break
        for h in hs:
            hid = h['account_id']
            if hid in paired:
                continue
            hv = str(h.get('client_version') or '')
            if bot_ver and hv and hv != bot_ver:
                no_bot[hid] = '%d-%d 真人 %s ≠ 陪练号 %s(服务端只配同版本)' % (cc[0], cc[1], hv, bot_ver)
                continue
            ob = next((x for x in online[cc] if x not in claimed and x not in stopped and not met(x, hid)), None)
            if ob is not None:
                plays_here(ob, cc)
                continue
            if no_launch:
                continue
            cand = take(cc, lambda x: not met(x, hid))
            if cand is None:
                note('A %d-%d 有真人在等但这一格没有空闲号(C 优先补; 等到上限服务端兜底)' % cc)
                unserved.append((hid, cc))
                continue
            if free <= 0:
                victim = preempt()
                if victim is None:
                    note('A %d-%d 并发满了且都在打, 等一个打完' % cc)
                    continue
                stop(victim, 'A 让位给 %d-%d 在等的真人' % cc)
            plays_here(cand, cc)
            launch(cand, 1, 'serve', 'A %d-%d 有真人等了 %d 秒、同格子没人在线' % (cc[0], cc[1], int(float(h.get('waited_sec', 0) or 0))))

    ## 收尾时哪些格子还可能有真人来: 现在才开始的真人能打到的深度 + 正在打的真人往下还能走到的格子(用户「每格只留最少的号给最后来的真人」)
    k_new = int(max(0.0, lockout - now) // c['FAST_STEP_SEC'])
    live_h = [(int(x.get('gw', 0) or 0), int(x.get('gl', 0) or 0)) for x in list(state.get('waiting') or []) + list(state.get('playing') or [])
              if x.get('account_id') not in bots and not x.get('is_bot')]

    def reachable(cc):
        if not endgame or cc[0] + cc[1] <= k_new:
            return True
        return any(cc[0] >= h[0] and cc[1] >= h[1] and (cc[0] + cc[1]) - (h[0] + h[1]) <= k_new + 1 for h in live_h)

    ## 总量账: 空闲号还剩的步数 − 预计以后的真人要用掉的步数(+ 12 格各留 r 个的底)= 能花在「整段打完」上的余量
    steps_idle = sum(steps_left(*cc) for bid, cc in cell_of.items() if not in_job(bots[bid]))
    human_need = rate * max(0.0, lockout - now) / 3600.0 * c['HUMAN_GAMES_PER_RUN'] * c['HUMAN_STEP_COST'] + len(CELLS) * r_top * 2
    spare_steps = steps_idle - human_need

    ## ── B 打到底的号(整段 / 收尾)在它的格子里没人可配 ⇒ 同格子在线的号 / 拉一个空闲号当对手 ──
    def refillable(cc):
        return any(len(avail(p)) >= r_top + 2 for p in parents(cc))

    for cc in CELLS:
        for x in online[cc]:
            if x in claimed or x in stopped or purpose(x) not in SESSIONISH:
                continue
            mate = next((y for y in online[cc] if y != x and y not in claimed and y not in stopped and not met(x, y)), None)
            if mate is not None:
                claimed.add(x)
                plays_here(mate, cc)
                continue
            if no_launch or nonserve_free() <= 0:
                continue
            ## 收尾且上一级能补 ⇒ 可以拿光; 总量账有余量 ⇒ 留 1 个; 否则只拿多余的(不让打到底的号把格子拉空、引出补格子)
            keep = 0 if (endgame and (refillable(cc) or not reachable(cc))) else (1 if spare_steps > 0 else r_top)
            if len(avail(cc)) - 1 < keep:
                note('B %d-%d 打到底的号没人可配, 这一格没有多余的号(等真人 / 到点自己下线)' % cc)
                continue
            cand = take(cc, lambda y: not met(x, y))
            if cand is None:
                continue
            claimed.add(x)
            plays_here(cand, cc)
            launch(cand, 1, 'partner', 'B %d-%d 打到底的号(%s)没人可配' % (cc[0], cc[1], purpose(x)))

    ## ── C 补格子: 先「每格 ≥1」, 0-0 本钱够再补到 r ──
    have, have0 = {}, {}
    for cc in CELLS:
        chain = sum(1 for x in online[cc] if x not in claimed and purpose(x) not in SESSIONISH)
        have0[cc] = have[cc] = len(avail(cc)) + exiting[cc] + chain + 0.5 * sum(moving[p] for p in parents(cc))
        if not reachable(cc):
            have[cc] = max(have[cc], float(r_top))     # 收盘前已经没有真人能走到 ⇒ 不补
    level = 1
    _short, xs = fill_plan(have, 1)
    ## 号不够铺满「每格 ≥1」(0-0 缺口 > 0), 而且是结构上不够 —— 本周全部晋级号加起来都铺不满 12 格(< full_cover_min, 0-0 留 2 时 = 24 个):
    ##   改按 cover_plan 铺到能铺的最多格(0-0 留 SCARCE_ROOT_KEEP 个, 别的格子按打法可以送空)。
    ##   原来照「每格 ≥1」的打法走、执行时又要求上一级留得住 1 个 ⇒ 号少时一局都开不了(彩排 12 个号铺到 7 格就停)。
    ##   ★号多(≥ 24 个晋级号)时周日号用掉一部分也会缺, 那时照旧不送空上一级: 推演(N=80 周日 16:30 穷举)送空浅格子兜底 0 → 8 步,
    ##     真人都从浅格子往下走, 为多铺一个深格子送空一个浅格子不划算。
    n_promoted = sum(1 for b in bots.values() if b.get('promoted', True))
    scarce = _short > 0 and n_promoted < full_cover_min(c['SCARCE_ROOT_KEEP'])
    if scarce:
        xs = cover_plan({cc: int(math.floor(have0[cc] + 1e-9)) for cc in CELLS}, c['SCARCE_ROOT_KEEP'],
                        [cc for cc in CELLS if reachable(cc)])
        note('C 号不够铺满每格 ≥1(0-0 缺 %d 个): 按能铺的最多格打, 0-0 留 %d 个' % (_short, c['SCARCE_ROOT_KEEP']))

    def keep_at(cc):
        """在 cc 打一局之后这一格至少还得留几个: 平时 level 个(上一级格子自己也要留够); 号不够时按 cover_plan 的打法, 只有 0-0 留本钱。"""
        if not scarce:
            return level
        return c['SCARCE_ROOT_KEEP'] if cc == ROOT else 0

    if not scarce and not any(xs.values()) and r_top > 1 and have[ROOT] - r_top < root_reserve:
        note('C 不补到 %d: 0-0 只有 %.0f 个, 本钱线 %d' % (r_top, have[ROOT], root_reserve))
    elif not scarce and not any(xs.values()) and r_top > 1:
        short2, xs2 = fill_plan(have, r_top)
        left_root = have[ROOT] - r_top - 2 * xs2[ROOT]
        if short2 == 0 and left_root >= root_reserve:
            level, xs = r_top, xs2
        elif any(xs2.values()):
            note('C 不补到 %d: 0-0 补完只剩 %.0f < 本钱线 %d' % (r_top, left_root, root_reserve))
    ## 在线的补格子号(连打的): 这一格还要往下送、而且送走两个之后这一格自己还留得住 level 个, 才接着打;
    ## 否则下线停在这里候场(用户「上一级格子自己也要留够」—— 连打的号路过一格时不许把它掏空)
    present = {cc: len(avail(cc)) + exiting[cc] + sum(1 for x in online[cc] if x not in claimed and purpose(x) not in SESSIONISH)
               for cc in CELLS}
    for cc in CELLS:
        ch = [x for x in online[cc] if x not in claimed and x not in stopped and purpose(x) not in SESSIONISH]
        for i, a in enumerate(ch):
            if a in claimed or xs.get(cc, 0) <= 0 or present[cc] - 2 < keep_at(cc):
                continue
            b = next((y for y in ch[i + 1:] if y not in claimed and not met(a, y)), None)
            if b is not None:
                plays_here(a, cc)
                plays_here(b, cc)
                xs[cc] -= 1
                present[cc] -= 2
        for a in ch:
            if a in claimed:
                continue
            if xs.get(cc, 0) > 0 and present[cc] - 2 >= keep_at(cc) and not no_launch and nonserve_free() > 0:
                cand = take(cc, lambda y: not met(a, y))
                if cand is not None:
                    plays_here(a, cc)
                    plays_here(cand, cc)
                    launch(cand, c['FILL_ROUNDS'], 'fill', 'C %d-%d 补格子的号缺对手' % cc)
                    xs[cc] -= 1
                    present[cc] -= 2
                    continue
            if purpose(a) == 'fill':
                stop(a, 'C %d-%d 这一格不用再往下送(或送走就空了), 补格子的号下线停在这里候场' % cc)
    ## 先铺真人马上要到的格子: 每格「最早可能有真人来」的时刻(在等 / 刚打完一局的真人的下一格 / 开赛以来最快的真人)
    eta = {cc: min(now + 1800.0, max(now, sat0 + (cc[0] + cc[1]) * c['FAST_STEP_SEC'])) for cc in CELLS}
    for cc in CELLS:
        if humans[cc]:
            eta[cc] = now
    for pl in state.get('playing') or []:
        if pl.get('is_bot') or pl.get('account_id') in bots:
            continue
        pc0 = (int(pl.get('gw', 0) or 0), int(pl.get('gl', 0) or 0))
        for q in ((pc0[0] + 1, pc0[1]), (pc0[0], pc0[1] + 1)):
            if q in CELLSET:
                eta[q] = min(eta[q], now + 60.0)
    for cc in CELLS:
        if humans[cc]:
            for q in ((cc[0] + 1, cc[1]), (cc[0], cc[1] + 1)):
                if q in CELLSET:
                    eta[q] = min(eta[q], now + 120.0)

    def urgency(pc):
        best = now + 86400.0
        for q in CELLS:
            if q[0] >= pc[0] and q[1] >= pc[1] and q != pc and have[q] < level:
                best = min(best, eta[q] - (q[0] + q[1] - pc[0] - pc[1]) * c['FILL_STEP_SEC'])
        return (best, pc[0] + pc[1])

    if not no_launch:
        for pc in sorted((q for q in CELLS if xs.get(q, 0) > 0), key=urgency):
            while xs.get(pc, 0) > 0 and nonserve_free() >= 2:
                av = avail(pc)
                if present[pc] - 2 < keep_at(pc):
                    break
                pair = None
                for i, a in enumerate(av):
                    b = next((y for y in av[i + 1:] if not met(a, y)), None)
                    if b is not None:
                        pair = (a, b)
                        break
                if pair is None:
                    break
                why = 'C 补格子(每格 ≥%d): 在 %d-%d 打一局, 送进 %s' % (level, pc[0], pc[1],
                      ' / '.join('%d-%d' % q for q in ((pc[0] + 1, pc[1]), (pc[0], pc[1] + 1)) if q in CELLSET) or '终局')
                for y in pair:
                    plays_here(y, pc)
                    launch(y, c['FILL_ROUNDS'], 'fill', why)
                xs[pc] -= 1
                present[pc] -= 2

    ## ── D 整段打完(平时; n_promoted 见 C 段开头) ──
    if not endgame and not no_launch:
        h0 = now - (now % 3600)
        due = sum(1 for t in sit_slots(h0, sat0, endgame_t, n_promoted, c) if t <= now)
        done = sum(1 for t in mem.get('session_starts', []) if t >= h0)
        if done < due:
            pick, why = None, ''
            if nonserve_free() >= 2:
                ## 只拿「超过 R 个」那几格里多出来的; 离打完近的先(赛况板早点出现晋级 / 出局), 同样近的挑最久没打的
                surplus = [(steps_left(*cc), bots[x].get('last_played_at') or 0.0, x) for cc in CELLS if cc != ROOT
                           for x in avail(cc) if len(avail(cc)) >= r_top + 1 and 2 * steps_left(*cc) <= spare_steps]
                if spare_steps <= 0:
                    note('D 这个钟点该坐下第 %d 个, 但总量账没余量(空闲步数 %d ≤ 预计真人要用 %.0f)' % (done + 1, steps_idle, human_need))
                elif surplus:
                    pick = min(surplus)[2]
                    why = 'D 整段打完: 多余候场号 %d-%d(还差 %d 场打完)' % (cell_of[pick] + (steps_left(*cell_of[pick]),))
                else:
                    av = avail(ROOT)
                    keep_root = level + 2 * xs.get(ROOT, 0) + root_reserve
                    if len(av) - 1 >= keep_root and 2 * steps_left(*ROOT) <= spare_steps:
                        pick = av[0]
                        why = 'D 整段打完: 0-0 的余量(本钱留 %d 个)' % keep_root
                    else:
                        note('D 这个钟点该坐下第 %d 个, 但没有多余候场号、0-0 只有 %d 个(本钱线 %d)' % (done + 1, len(av), keep_root))
            else:
                note('D 这个钟点该坐下第 %d 个, 并发不够' % (done + 1))
            if pick is not None:
                launch(pick, c['SESSION_ROUNDS'], 'session', why)

    ## ── E 收尾: 上过榜的多余候场号成对打到底, 每格留 R_END(深格子先) ──
    if endgame and not no_launch:
        for cc in reversed(CELLS):
            if cc == ROOT:
                continue
            keep = c['R_END'] if reachable(cc) else 0
            while nonserve_free() >= 2:
                av = avail(cc)
                spare = len(av) - keep
                if spare <= 0 or len(av) < 2 or (spare == 1 and keep > 0 and not refillable(cc)):
                    break
                a = av[0]
                b = next((y for y in av[1:] if not met(a, y)), None)
                if b is None:
                    break
                for y in (a, b):
                    claimed.add(y)
                    launch(y, c['SESSION_ROUNDS'], 'end', 'E 收尾: %d-%d 多出来的候场号成对打到底%s' % (cc + ('' if keep else '(收盘前已没有真人能走到这一格)',)))

    ## ── 没有陪练号能来的真人(见 A 段开头 ②): 上一级格子里有没交过手、正要在那里打一局的号 ⇒ 还可能送下来, 不判 ──
    for hid, cc in unserved:
        coming = [x for x, pc in cell_of.items() if pc in parents(cc) and not met(x, hid)
                  and (in_job(bots[x]) or x in taken or x in queued or (x in running and rounds_left(x) > 0))]
        if not coming:
            no_bot[hid] = '%d-%d 这一格和上一级都没有跟他没交过手的号' % cc
    for hid in sorted(no_bot):
        cmds.append(('nobot', hid, 0, 'nobot', no_bot[hid]))
    return cmds


def remember(memory: dict, cmds: list, now: float, state: dict = None) -> dict:
    """本机记忆(纯函数), IO 层与推演门禁用同一个:
    session_starts 「整段打完」开始时刻(D 的每小时计数); humans 在 0-0 排过队的真人 → 第一次看到的时刻(算 0-0 本钱线的来人速率)。只留 48 小时。"""
    memory = memory or {}
    starts = [t for t in memory.get('session_starts', []) if t >= now - 48 * 3600]
    starts += [now for op, _b, _r, p, _w in cmds if op == 'launch' and p == 'session']
    humans = {k: v for k, v in (memory.get('humans') or {}).items() if v >= now - 48 * 3600}
    if state:
        bot_ids = {b['account_id'] for b in state.get('bots') or []}
        for w in list(state.get('waiting') or []) + list(state.get('playing') or []):
            if w['account_id'] not in bot_ids and not w.get('is_bot') and int(w.get('gw', 0) or 0) == 0 and int(w.get('gl', 0) or 0) == 0:
                humans.setdefault(w['account_id'], now)
    return {'session_starts': starts, 'humans': humans}


def weekend_env(rounds: int, purpose: str, cell: tuple) -> dict:
    """拉号时给客户端的周末参数(sim_driver 周末在线闯关; 客户端那条线实现)。"""
    return {
        'SIM_GAUNTLET_ONLINE': '1',                       # 走在线排队(join / poll), 不走旧的快照对局
        'SIM_ROUNDS': str(rounds),                        # 这次上线最多打几局(打到 4 胜 / 3 负也停)
        'SIM_QUIT_WHEN_DONE': '1',
        'SIM_QUEUE_GIVEUP_SEC': str(GIVEUP_SEC.get(purpose, 300)),   # 排队等不到对手多久下线
        'SIM_SHOP_MIN_SEC': str(shop_sec(purpose)[0]), 'SIM_SHOP_MAX_SEC': str(shop_sec(purpose)[1]),   # 两局之间逛商店
        'SIM_EXPECT_CELL': '%d-%d' % cell,                # 拉号时调度器看到的战绩; 对不上就别排(存档 / 服务端不同步)
        'SIM_SKIP_WATCH': '1',                            # 不坐着看完直播(并发位只花在排队和对局上)
    }


## ═══════════════ IO 层(薄) ═══════════════

def log(msg: str) -> None:
    print('%s %s' % (time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), msg), flush=True)


def _req(path: str, body, headers: dict = None, timeout: float = 20.0):
    url = os.environ.get('SUPABASE_URL', '').rstrip('/') + path
    key = os.environ.get('SUPABASE_SERVICE_KEY', '')
    h = {'apikey': key, 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json', 'Accept': 'application/json'}
    h.update(headers or {})
    req = urllib.request.Request(url, data=json.dumps(body, ensure_ascii=False).encode('utf-8'), method='POST', headers=h)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
    return json.loads(raw) if raw else None


def rpc(fn: str, body: dict):
    return _req('/rest/v1/rpc/' + fn, body)


def _ts(v):
    """服务端时间 ⇒ epoch 秒(数字 / ISO 字符串 / None)。"""
    if v is None or v == '':
        return None
    if isinstance(v, (int, float)):
        return float(v)
    import datetime as dt
    s = str(v).replace('Z', '+00:00')
    d = dt.datetime.fromisoformat(s)
    if d.tzinfo is None:
        d = d.replace(tzinfo=dt.timezone.utc)
    return d.timestamp()


def normalize(st: dict, week: int) -> dict:
    """服务端 gauntlet_service_state(迁移 20261027_gauntlet_online_queue.sql)⇒ decide 的输入。时间一律 epoch 秒。"""
    out = {'close_at': float(st['close_ts']) if st.get('close_ts') is not None else (_ts(st.get('close_at')) or close_of_week(week)),
           'now': float(st['now_ts']) if st.get('now_ts') is not None else None,
           'waiting': [], 'bots': [], 'playing': list(st.get('playing') or [])}
    for w in st.get('waiting') or []:
        out['waiting'].append(dict(w, waited_sec=float(w.get('waited_sec', 0) or 0), seen_sec=float(w.get('seen_sec', 0) or 0)))
    for b in st.get('bots') or []:
        out['bots'].append(dict(b, last_played_at=_ts(b.get('last_played_at'))))
    return out


def _bot_runner():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import bot_runner
    return bot_runner


def bot_slots(br) -> dict:
    """账号 id → 号(pNN)。读每个号自己的存档(bot_runner.read_save)。"""
    out = {}
    root = br.ROOT
    if not os.path.isdir(root):
        return out
    for name in sorted(os.listdir(root)):
        if len(name) >= 2 and name[0] == 'p' and name[1:].isdigit():
            aid = str(br.read_save(int(name[1:])).get('account_id', '') or '')
            if aid:
                out[aid] = int(name[1:])
    return out


def sync_bot_accounts(ids: list) -> None:
    """陪练号名单写进 bot_accounts(幂等: 已有的跳过)。"""
    if ids:
        _req('/rest/v1/bot_accounts', [{'account_id': i} for i in ids],
             headers={'Prefer': 'resolution=ignore-duplicates,return=minimal'})


def _reap_children() -> None:
    """常驻进程是陪练客户端的父进程: 退了的子进程不收尸就一直是僵尸, os.kill(pid, 0) 会把它当活着、占死并发位。"""
    if not hasattr(os, 'WNOHANG'):
        return
    while True:
        try:
            pid, _st = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return
        if pid == 0:
            return


def stop_client(br, run: dict, bid: str) -> int:
    """让本机拉起的一个陪练客户端下线: 杀整棵进程树(bot_runner.kill_tree), 从进程表里拿掉。返回杀了几个进程。
    ★2026-10-27 内测服彩排: 原来按包装脚本的进程组 killpg 只杀掉包装脚本 —— 包装脚本里的 `timeout` 另开了进程组,
      godot 照样把剩下的局打完(p07 17:41:28 被「停」, 17:41:56 又进了队、等满 180 秒才走), 调度器却以为它下线了。"""
    v = run.pop(bid, None)
    if not v or not v.get('pid'):
        return 0
    return br.kill_tree(int(v['pid']))


def external_running(br) -> int:
    """bot_runner 积分赛那批还活着的客户端(周五晚的长会话可能跨进周六)。"""
    st = br.load_json(br.QUEUE_STATE, {})
    n = 0
    for wk in st.values():
        for ph in (wk.values() if isinstance(wk, dict) else []):
            for v in (ph.values() if isinstance(ph, dict) else []):
                if isinstance(v, dict) and v.get('pid') and not v.get('killed') and br.alive(int(v['pid'])):
                    n += 1
    return n


def cfg_from_env() -> dict:
    c = {'MAX_PAR': int(os.environ.get('MAX_PAR_WEEKEND', str(DEFAULTS['MAX_PAR'])))}
    if os.environ.get('PLANNER_R'):
        c['R'] = int(os.environ['PLANNER_R'])
    if os.environ.get('PLANNER_R_END'):
        c['R_END'] = int(os.environ['PLANNER_R_END'])
    if os.environ.get('PLANNER_ROOT_SAFETY'):
        c['ROOT_SAFETY'] = float(os.environ['PLANNER_ROOT_SAFETY'])
    if os.environ.get('TICK_SEC'):
        c['TICK_SEC'] = int(os.environ['TICK_SEC'])
    if os.environ.get('PLANNER_OPENING_SEC'):
        c['OPENING_SEC'] = int(os.environ['PLANNER_OPENING_SEC'])
    if os.environ.get('MAX_PAR_OPENING'):
        c['OPENING_MAX_PAR'] = int(os.environ['MAX_PAR_OPENING'])
    return c


def one_tick(br, ps: dict, cfg: dict, rng: random.Random, dry: bool, status: bool) -> None:
    week = int(os.environ.get('PLANNER_WEEK', '') or week_anchor(time.time()))   # 内测服彩排拨钟到别的周时手动给周一 epoch
    raw = rpc('gauntlet_service_state', {'p_week': week}) or {}
    if not raw.get('ok', True) or not raw.get('gauntlet_on', True):
        log('闯关赛开关没开(gauntlet_on=false)或服务端拒绝: %s' % json.dumps(raw, ensure_ascii=False)[:200])
        return
    st = normalize(raw, week)
    now = st['now'] or time.time()                      # 用服务端的钟(内测服彩排会拨钟 app_now)
    _reap_children()
    run = {k: v for k, v in (ps.get('running') or {}).items() if br.alive(int(v.get('pid', 0) or 0))}
    for k, v in list(run.items()):                       # 卡住的客户端: 局数 × 10 分钟 + 10 分钟还没退 ⇒ 杀(本机钟)
        if time.time() - float(v.get('wall', v['since'])) > int(v.get('rounds', 1)) * 600 + 600:
            stop_client(br, run, k)
            log('超时杀掉 %s(%s)' % (k, v.get('purpose')))
    st['running'] = run
    st['memory'] = ps.get('memory') or {}
    st['external_running'] = external_running(br)
    st['bot_version'] = game_version(br.GAME)
    if status:
        cnt = {cc: [0, 0, 0] for cc in CELLS}
        for b in st['bots']:
            cc = (int(b.get('gw', 0) or 0), int(b.get('gl', 0) or 0))
            if cc in cnt and b.get('promoted', True) and not b.get('finished'):
                k = 2 if in_job(b) else (1 if (b['account_id'] in run or b.get('waiting')) else 0)
                cnt[cc][k] += 1
        print('格子  空闲 / 在线 / 在打')
        for cc in CELLS:
            print('%d-%d   %d / %d / %d' % (cc[0], cc[1], *cnt[cc]))
        print('在等的真人 %d · 本机在线 %d · 积分赛遗留 %d · 上限 %d' % (
            len([w for w in st['waiting'] if w['account_id'] not in {b['account_id'] for b in st['bots']}]),
            len(run), st['external_running'], cfg.get('MAX_PAR', DEFAULTS['MAX_PAR'])))
        return
    cmds = decide(st, now, rng, cfg)
    nobot = [x for x in cmds if x[0] == 'nobot']
    cmds = [x for x in cmds if x[0] != 'nobot']
    report_no_bot(week, nobot, st['bot_version'], dry)
    if not br.GAME and not dry:
        cmds = [x for x in cmds if x[0] != 'launch']
        log('BOT_GAME_DIR 没设(应 = 正式服当前发布版的工程, 配对要求客户端版本相同), 这拍不拉号')
    slots = bot_slots(br) if any(op == 'launch' for op, *_ in cmds) else {}
    bots = {b['account_id']: b for b in st['bots']}
    done = []
    for op, bid, rounds, purpose, why in cmds:
        if dry:
            print('会%s %s %s %d 局 —— %s' % ('拉' if op == 'launch' else '停', bid, purpose, rounds, why))
            continue
        if op == 'stop':
            if bid in run:
                stop_client(br, run, bid)
                done.append((op, bid, rounds, purpose, why))
                log('停 %s —— %s' % (bid, why))
            continue
        if bid not in slots:
            log('WARN 账号 %s 在本机找不到存档(号目录), 跳过' % bid)
            continue
        b = bots.get(bid, {})
        cell = (int(b.get('gw', 0) or 0), int(b.get('gl', 0) or 0))
        pid = launch_bot(br, slots[bid], rounds, purpose, cell)
        run[bid] = {'pid': pid, 'since': now, 'wall': time.time(), 'rounds': rounds, 'purpose': purpose,
                    'g0': cell[0] + cell[1], 'slot': slots[bid]}
        done.append((op, bid, rounds, purpose, why))
        log('拉 p%02d %s %d-%d %s %d 局 pid=%d —— %s' % (slots[bid], bid[:8], cell[0], cell[1], purpose, rounds, pid, why))
    if not dry:
        ps['running'] = run
        ps['memory'] = remember(ps.get('memory') or {}, done, now, st)


_VER_RE = None
_MARK_MISSING = [False]


def game_version(game_dir: str):
    """陪练号工程(BOT_GAME_DIR)的 project.godot 里的 config/version; 读不到 = None(decide 就不按版本判)。"""
    global _VER_RE
    if not game_dir:
        return None
    if _VER_RE is None:
        import re
        _VER_RE = re.compile(r'^\s*config/version\s*=\s*"([^"]+)"', re.M)
    try:
        with open(os.path.join(game_dir, 'project.godot'), encoding='utf-8') as f:
            m = _VER_RE.search(f.read())
        return m.group(1) if m else None
    except OSError:
        return None


def report_no_bot(week: int, nobot: list, bot_version, dry: bool) -> None:
    """每拍报一次(迁移 20261031 gauntlet_planner_mark): 写调度器心跳 + 「没有陪练号能来」的真人名单(空 = 全清)。
    服务端据此让名单里的真人进队满 1 分钟就兜底; 心跳断了 60 秒也一样(只在报过到之后)。
    服务端还没上这份迁移(404)⇒ 只记一行日志, 不影响拉号(行为与以前相同)。"""
    if dry:
        for _op, hid, _r, _p, why in nobot:
            print('会报 没有陪练号能来 %s —— %s' % (hid, why))
        return
    try:
        rpc('gauntlet_planner_mark', {'p_week': week, 'p_no_bot': [x[1] for x in nobot], 'p_bot_version': bot_version})
        for _op, hid, _r, _p, why in nobot:
            log('没有陪练号能来 %s —— %s' % (hid[:8], why))
    except urllib.error.HTTPError as e:
        if e.code == 404 and not _MARK_MISSING[0]:
            log('服务端没有 gauntlet_planner_mark(迁移 20261031 还没上), 照旧等 180 秒兜底')
            _MARK_MISSING[0] = True
        elif e.code != 404:
            log('报「没有陪练号能来」出错: HTTP %s %s' % (e.code, e.reason))


def launch_bot(br, slot: int, rounds: int, purpose: str, cell: tuple) -> int:
    """bot_runner.launch 同一套拉法 + 周末参数; 服务端密钥不传给客户端。"""
    return br.launch(slot, rounds, extra_env=weekend_env(rounds, purpose, cell))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--once', action='store_true')
    ap.add_argument('--dry', action='store_true')
    ap.add_argument('--status', action='store_true')
    a = ap.parse_args()
    if not os.environ.get('SUPABASE_URL') or not os.environ.get('SUPABASE_SERVICE_KEY'):
        log('SUPABASE_URL / SUPABASE_SERVICE_KEY 没设')
        return 2
    br = _bot_runner()
    cfg = cfg_from_env()
    state_path = os.environ.get('PLANNER_STATE', os.path.join(br.ROOT, 'gauntlet_planner.json'))
    rng = random.Random()
    always = os.environ.get('PLANNER_ALWAYS', '') == '1'   # 内测服彩排(服务端拨钟 / gauntlet_any_day): 不按本机钟睡
    synced_at = 0.0
    while True:
        now = time.time()
        if now - synced_at > 3600 and not (a.dry or a.status):      # 启动时(和每小时)写陪练号名单, 不管是不是周末
            try:
                ids = sorted(bot_slots(br))
                sync_bot_accounts(ids)
                log('bot_accounts 已写 %d 个号' % len(ids))
                synced_at = now
            except (urllib.error.URLError, OSError, ValueError) as e:
                log('写 bot_accounts 出错: %r' % (e,))
        week = week_anchor(now)
        close = close_of_week(week)
        sat0 = saturday_of(close)
        if not (a.once or a.dry or a.status or always) and not (sat0 - 60 <= now < close):
            time.sleep(min(600.0, max(10.0, sat0 - 60 - now)) if now < sat0 else 600.0)
            continue
        try:
            ps = br.load_json(state_path, {})
            one_tick(br, ps, cfg, rng, a.dry, a.status)
            if not (a.dry or a.status):
                tmp = state_path + '.tmp'
                with open(tmp, 'w', encoding='utf-8') as f:
                    json.dump(ps, f, ensure_ascii=False)
                os.replace(tmp, state_path)
        except urllib.error.HTTPError as e:
            log('HTTP %s %s(服务端没部署 gauntlet_service_state / bot_accounts?)' % (e.code, e.reason))
        except (urllib.error.URLError, OSError, ValueError) as e:
            log('出错: %r' % (e,))
        if a.once or a.dry or a.status:
            return 0
        time.sleep(cfg.get('TICK_SEC', DEFAULTS['TICK_SEC']))


if __name__ == '__main__':
    sys.exit(main())
