# -*- coding: utf-8 -*-
"""tools/econ_beta_smoke.py —— 局外经济记账全链路实测（2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md）。

本机真客户端（tests/probes/_econ_beta_e2e.tscn，TURTLE_SERVER=beta）↔ 内测服真数据库 ↔ 轮询器原函数 handle_econ + 真 Godot（--econ-replay）。
★只动内测服；不碰裁判机、不碰正式服。这个脚本当一回轮询器（rpc 换成 Management API 跑 SQL，因为本机没有 service_role 密钥）。

做的事：匿名注册一个号 → 记一场服务器账（ranked_records）→ 登记客户端版本 + 开 econ_on → 起客户端 → 一边轮询重放 → 客户端跑完四段判定。
★收尾一定还原（finally）：删这个号（流水 / 重放结果 / 账本随外键一起没）、任务、版本登记、econ_on 回到原值，并回读确认。
用法：python tools/econ_beta_smoke.py          退出码 0 = 全过（打印 ALL OK）
"""
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb_common as S  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT_BIN", r"C:\Users\Louis\Desktop\Godot_v4.6.3-stable_win64.exe")
REF = S.BETA_REF
URL = S.URLS[REF]
KEY = S.PUBLISHABLE[REF]


def q(sql):
    return S.query(REF, sql)


def load_poller():
    spec = importlib.util.spec_from_file_location("referee_poller", os.path.join(ROOT, "server", "referee", "referee_poller.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)

    def rpc(fn, body, timeout=20.0):
        if fn == "econ_replay_claim":
            return q("select public.econ_replay_claim(%d) as r" % int(body.get("p_limit", 20)))[0]["r"]
        if fn == "referee_flags":
            return q("select public.referee_flags() as r")[0]["r"]
        if fn == "econ_replay_done":
            return q("select public.econ_replay_done($j$%s$j$::jsonb) as r" % json.dumps(body["p_items"], ensure_ascii=False))[0]["r"]
        raise RuntimeError("实测不该调 " + fn)

    m.rpc = rpc
    m.econ_project = lambda versions: ROOT
    os.environ["GODOT_BIN"] = GODOT
    return m


def main():
    ver = re.search(r'config/version="([^"]+)"', open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()).group(1)
    rules = int(re.search(r"const RULES_VER := (\d+)", open(os.path.join(ROOT, "scripts", "gamedata", "phase2_config.gd"), encoding="utf-8").read()).group(1))
    cfg0 = q("select econ_on from public.referee_config where id = 1")[0]["econ_on"]
    had = q("select count(*)::int as n from public.referee_versions where client_version = '%s'" % ver)[0]["n"]
    wk = q("select public.econ_week_now() as w")[0]["w"]
    print("内测服 %s · 客户端 %s · 规则版本 %d · 本周 %s · econ_on 原值 %s · 版本行原有 %d" % (REF, ver, rules, wk, cfg0, had))

    r = urllib.request.Request(URL + "/auth/v1/signup", method="POST", data=b"{}", headers={"apikey": KEY, "Content-Type": "application/json"})
    with S.OPENER.open(r, timeout=30) as resp:
        body = resp.read().decode()
    uid = json.loads(body)["user"]["id"]
    assert re.fullmatch(r"[0-9a-f-]{36}", uid)
    print("测试号", uid)

    tmp = tempfile.mkdtemp(prefix="econ_e2e_")
    auth = os.path.join(tmp, "auth.json")
    with open(auth, "w", encoding="utf-8") as f:
        f.write(body)
    ud = os.path.join(tmp, "user")
    os.makedirs(ud)
    log_path = os.path.join(ROOT, ".out", "econ_beta_e2e.log")
    rc = 1
    stop = threading.Event()
    stats = {"rounds": 0, "accounts": 0, "sec": []}
    try:
        q("insert into public.ranked_records (season_week, account_id, battles, wins, hearts, eggs, used, coins) "
          "values (%s, '%s', 1, 1, 6, 1, 1, 20)" % (wk, uid))
        q("insert into public.referee_versions (client_version, enabled, rules_ver) values ('%s', true, %d) "
          "on conflict (client_version) do nothing" % (ver, rules))
        q("update public.referee_config set econ_on = true where id = 1")
        m = load_poller()
        wd = os.path.join(tmp, "poller")

        def poller():
            while not stop.is_set():
                jobs = m.claim_econ()
                if jobs:
                    t0 = time.time()
                    n = m.handle_econ(jobs, {ver: ROOT}, wd)
                    stats["rounds"] += 1
                    stats["accounts"] += n
                    stats["sec"].append(round(time.time() - t0, 2))
                    print("  重放一批: %d 个号 %.1f 秒, 不合法 %s" % (n, time.time() - t0,
                          [x.get("why") for x in (q("select why from public.econ_state where account_id = '%s' and bad_at >= 0" % uid))]), flush=True)
                stop.wait(0.5)

        th = threading.Thread(target=poller, daemon=True)
        th.start()
        env = dict(os.environ, TURTLE_SERVER="beta", E2E_AUTH=auth, APPDATA=ud, XDG_DATA_HOME=ud)
        env.pop("TURTLE_SUPABASE", None)
        env.pop("TURTLE_BACKEND", None)
        with open(log_path, "w", encoding="utf-8") as lf:
            p = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", ROOT, "res://tests/probes/_econ_beta_e2e.tscn",
                                "--quit-after", "2000000"], stdout=lf, stderr=subprocess.STDOUT, env=env, timeout=420)
        log = open(log_path, encoding="utf-8", errors="replace").read()
        for line in log.splitlines():
            if "[PASS]" in line or "[FAIL]" in line or "SCRIPT ERROR" in line or "ALL PASS" in line or "FAILED" in line:
                print(line[:220])
        rc = 0 if p.returncode == 0 and "ALL PASS" in log and "SCRIPT ERROR" not in log else 1
        print("服务器上这个号的流水 %s 条 · 重放结果 %s" % (
            q("select count(*)::int as n from public.econ_ops where account_id = '%s'" % uid)[0]["n"],
            json.dumps(q("select seen, upto, bad_at, why, dirty from public.econ_state where account_id = '%s'" % uid), ensure_ascii=False)))
        print("重放 %d 批 / %d 个号次 · 每批秒数 %s" % (stats["rounds"], stats["accounts"], stats["sec"]))
    finally:
        stop.set()
        q("delete from public.referee_jobs where a_account = '%s'" % uid)
        q("delete from auth.users where id = '%s'" % uid)
        q("update public.referee_config set econ_on = %s where id = 1" % ("true" if cfg0 else "false"))
        if not had:
            q("delete from public.referee_versions where client_version = '%s'" % ver)
        left = q("select (select count(*)::int from auth.users where id = '%s') u, (select count(*)::int from public.econ_ops where account_id = '%s') o, "
                 "(select count(*)::int from public.econ_state where account_id = '%s') s, (select count(*)::int from public.ranked_records where account_id = '%s') r, "
                 "(select econ_on from public.referee_config where id = 1) e, "
                 "(select count(*)::int from public.referee_versions where client_version = '%s') v" % (uid, uid, uid, uid, ver))[0]
        print("收尾回读:", json.dumps(left, ensure_ascii=False))
        shutil.rmtree(tmp, ignore_errors=True)
    print("ALL OK — 真客户端 ↔ 内测服真数据库 ↔ 真重放" if rc == 0 else "FAIL")
    return rc


if __name__ == "__main__":
    sys.exit(main())
