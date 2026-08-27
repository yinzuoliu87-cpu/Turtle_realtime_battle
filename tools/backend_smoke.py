# -*- coding: utf-8 -*-
"""对着【真的服务端】跑一遍 V2/V3 —— 部署完成后用它验收。

方案书 docs/plans/20260820-阵容上传后端.md 的 V2/V3 一直标着 ⏳「没服务器所以没验」。
本文件就是那两条的验收器: 有了 URL, 跑它, 绿了就能把 ⏳ 改成 ✅。

用法:
  python tools/backend_smoke.py https://xxx.service.tcloudbase.com

★它验的是【服务端真的按规则办事】, 不是"能连上":
  V2 = A 传上去 → B 拉下来能拿到同一份(需求原话「让别人打到我的阵容」)
  V3 = 四类伪造快照必须被【拒绝】, 而合法的必须被【接受】(分母)
  另加: schema 不匹配被拒 / 去重(同 ghost_id 不堆积) / bracket 越界被拒

★白名单直接读客户端的事实源, 不手抄 —— 与服务端那份由 tools/server_rule_sync.py 对账。
"""
import io
import json
import os
import sys
import urllib.error
import urllib.request

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

TIMEOUT = 15
fails = []
n_check = 0

## ★★本机地址【必须绕开系统代理】(2026-08-27 血泪):
##   这台机器上有 `HTTP_PROXY=http://127.0.0.1:18081`, 而**那个代理会改写 POST 的 body** ——
##   实测到达服务端的内容是【开头多了一个 CRLF CRLF、末尾被截掉 4 字节】,
##   于是 JSON 一律解析失败 ⇒ 服务端把**所有**快照(包括合法的)判成非法。
##   表现极具迷惑性: 六条"伪造被拒"全绿, 而它们全是恒真式 ——
##   **是第一条分母断言(合法的必须被接受)当场把它揪出来的**。
##   curl 与 urllib 都会读这两个环境变量, 所以两边现象一致, 一度让我以为是 Node 的问题;
##   裸 socket 直连(绕过代理)一次就通, 才定位到代理。
##   ⇒ 打本机就用无代理的 opener; 打真实云地址仍走系统代理(用户在国内, 可能需要它)。
_NOPROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def _open(req_or_url, base):
    from urllib.parse import urlparse
    host = urlparse(base).hostname or ''
    if host in ('127.0.0.1', 'localhost', '::1'):
        return _NOPROXY.open(req_or_url, timeout=TIMEOUT)
    return urllib.request.urlopen(req_or_url, timeout=TIMEOUT)


def post(base, path, obj):
    req = urllib.request.Request(
        base.rstrip('/') + path,
        data=json.dumps(obj, ensure_ascii=False).encode('utf-8'),
        headers={'Content-Type': 'application/json; charset=utf-8'},
        method='POST')
    try:
        with _open(req, base) as r:
            return r.status, json.loads(r.read().decode('utf-8') or '{}')
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8', 'replace')
        try:
            return e.code, json.loads(body or '{}')
        except Exception:
            return e.code, {'raw': body[:200]}
    except Exception as e:
        return 0, {'error': str(e)[:200]}


def get(base, path):
    try:
        with _open(base.rstrip('/') + path, base) as r:
            return r.status, json.loads(r.read().decode('utf-8') or '{}')
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8', 'replace')
        try:
            return e.code, json.loads(body or '{}')
        except Exception:
            return e.code, {'raw': body[:200]}
    except Exception as e:
        return 0, {'error': str(e)[:200]}


def ok(name, cond, detail=''):
    global n_check
    n_check += 1
    print(('  [PASS] ' if cond else '  [FAIL] ') + name + ('  ' + detail if detail else ''))
    if not cond:
        fails.append(name)


def load_whitelist():
    p = 'server/cloudbase/whitelist.json'
    d = json.loads(io.open(p, encoding='utf-8').read())
    return d['TURTLE_IDS'], d['EQUIP_IDS']


def good_snapshot(pid, eid, ghost_id, bracket=3):
    return {
        "schema_ver": 2,
        "ghost_id": ghost_id,
        "is_bot": False,
        "bracket": bracket,
        "profile": {"name": "玩家阵容", "avatar": pid, "id": ghost_id},
        "leaders": [pid],
        "lane_assign": {}, "minions": {}, "loadouts": {},
        "pet_levels": {pid: 5},
        "equipped": {pid: [{"id": eid, "star": 1}]},
        "season_total_battles": 12, "season_eggs_killed": 0,
        "chest_treasures_won": [], "chest_treasure_value": 0.0,
    }


def main():
    if len(sys.argv) < 2:
        print('用法: python tools/backend_smoke.py <服务端URL>')
        return 2
    base = sys.argv[1].strip()
    if not base.startswith('http'):
        print('URL 要带 http(s)://')
        return 2
    if not os.path.exists('server/cloudbase/whitelist.json'):
        print('缺 whitelist.json —— 先跑 python tools/gen_server_whitelist.py')
        return 2

    turtles, equips = load_whitelist()
    pid, eid = turtles[0], equips[0]
    ## 用一个**本次专属**的 bracket 与 id, 免得和真玩家数据搅在一起。
    ## bracket 8 是最高档, 真实玩家极少; ghost_id 带 __smoke__ 前缀好认。
    BR = 8
    GID = '__smoke__A'

    print('=== 阵容后端真机冒烟 · %s ===' % base)
    print('')

    # ── 分母 0: 服务端活着 ──────────────────────────────
    st, body = get(base, '/ghosts?bracket=%d&limit=1' % BR)
    ok('★分母: 服务端活着且 GET 能通(HTTP %s)' % st, st == 200, str(body)[:120])
    if st != 200:
        print('')
        print('连不上就别往下跑了 —— 后面全会是同一个原因。')
        return 1

    # ── V3: 合法的必须被【接受】(这是下面所有"拒绝"断言的分母) ──
    st, body = post(base, '/ghost', good_snapshot(pid, eid, GID, BR))
    ok('★★分母: 一份【合法】快照必须被接受(否则下面全是恒真式)', st == 200, 'HTTP %s %s' % (st, str(body)[:100]))

    # ── V3: 四类伪造 ────────────────────────────────────
    bad = [
        ('龟 id 不在白名单', dict(good_snapshot(pid, eid, GID + 'x', BR), leaders=['__不存在的龟__'])),
        ('装备 id 不在白名单', dict(good_snapshot(pid, eid, GID + 'y', BR),
                                 equipped={pid: [{'id': '__不存在的装备__', 'star': 1}]})),
        ('单只装备超上限(4 > 3)', dict(good_snapshot(pid, eid, GID + 'z', BR),
                                    equipped={pid: [{'id': eid, 'star': 1}] * 4})),
        ('等级 11 > 上限 10', dict(good_snapshot(pid, eid, GID + 'w', BR), pet_levels={pid: 11})),
        ('schema_ver 不匹配', dict(good_snapshot(pid, eid, GID + 'v', BR), schema_ver=1)),
        ('bracket 越界(99)', dict(good_snapshot(pid, eid, GID + 'u', BR), bracket=99)),
    ]
    for why, snap in bad:
        st, body = post(base, '/ghost', snap)
        ok('★★V3 %s → 服务端【拒绝】' % why, st >= 400,
           'HTTP %s %s' % (st, str(body.get('error', body))[:80]))

    # ── V2: A 传上去, B 拉下来能拿到 ─────────────────────
    st, body = get(base, '/ghosts?bracket=%d&limit=50' % BR)
    ok('★分母: GET 拿到了列表', st == 200 and isinstance(body.get('ghosts'), list),
       'HTTP %s' % st)
    ghosts = body.get('ghosts', []) if isinstance(body, dict) else []
    ids = [str(g.get('ghost_id', '')) for g in ghosts]
    ok('★★V2 B 端拉回的列表里【有 A 那一份】(需求原话)', GID in ids,
       '拉回 %d 份: %s' % (len(ids), str(ids[:6])))

    mine = next((g for g in ghosts if str(g.get('ghost_id', '')) == GID), None)
    ok('★★V2 拉回来的内容【和传上去的一致】(龟/装备/等级)',
       mine is not None
       and mine.get('leaders') == [pid]
       and str((mine.get('equipped') or {}).get(pid, [{}])[0].get('id', '')) == eid
       and int((mine.get('pet_levels') or {}).get(pid, 0)) == 5,
       str(mine)[:140] if mine else 'null')
    ## 服务端不许把本机的 origin 概念传出去 —— 它是"相对谁"的, 由客户端拉回时盖章。
    ok('★V2 服务端返回的快照【不带 origin】(那是客户端相对自己盖的章)',
       mine is not None and 'origin' not in mine,
       'origin=%s' % (str(mine.get('origin')) if mine else '-'))

    # ── 去重: 同 ghost_id 重传不该堆积 ──────────────────
    for _ in range(3):
        post(base, '/ghost', good_snapshot(pid, eid, GID, BR))
    st, body = get(base, '/ghosts?bracket=%d&limit=50' % BR)
    same = [g for g in body.get('ghosts', []) if str(g.get('ghost_id', '')) == GID]
    ok('★★同一个 ghost_id 重传 4 次, 池里仍只有 1 条(不堆积)', len(same) == 1,
       '实得 %d 条' % len(same))

    print('')
    print('  (共 %d 条检查)' % n_check)
    if n_check < 12:
        print('  [FAIL] ★分母: 只跑了 %d 条(<12) —— 有用例没跑到' % n_check)
        fails.append('分母过小')
    if fails:
        print('')
        print('FAILED: %d 条 —— %s' % (len(fails), '; '.join(fails[:4])))
        return 1
    print('')
    print('ALL PASS — 服务端按规则办事(V2 通 / V3 六类伪造全拒)')
    print('⇒ 可以把方案书 20260820 的 V2、V3-服务端 两条 ⏳ 改成 ✅ 了。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
