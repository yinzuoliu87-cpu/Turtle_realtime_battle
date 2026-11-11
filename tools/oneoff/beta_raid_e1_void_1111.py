"""内测服配合主站联调(2026-11-11 晚, 已在 Telegram 与 Tom 约好时间; 只动内测服 turtle-beta 与裁判机上的内测轮询器)。
  19:15 ~ 19:25 UTC  E1: referee_config.raid_on = false(主站建任务收到 raid_off), 到点改回原值
  19:30 ~ 19:45 UTC  开算后作废: 停 turtle-referee-beta 与它的高峰停起定时器 ⇒ 新偷袭停在 queued;
                     19:30 之后排进来的第一场 ⇒ public.raid_void(id, 'manual_test_void') ⇒ 发件箱 settle void;
                     19:45 恢复定时器与轮询器, 其余排队的照常算。
★finally 里一律恢复开关与服务(中途出错 / 被打断也不会把内测服留在关着的状态)。
"""
import datetime as dt
import os
import subprocess
import sys
import time

sys.path.insert(0, "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/tools")
import sb_common as S  # noqa: E402

REF = S.BETA_REF
assert REF != S.PROD_REF
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-i", os.path.expanduser("~/.ssh/turtle_referee"), "root@49.13.166.188"]
DAY = dt.datetime(2026, 11, 11, tzinfo=dt.timezone.utc)
T_E1_ON = DAY.replace(hour=19, minute=15)
T_E1_OFF = DAY.replace(hour=19, minute=25)
T_V_ON = DAY.replace(hour=19, minute=30)
T_V_OFF = DAY.replace(hour=19, minute=45)


def log(*a):
    print(dt.datetime.now(dt.timezone.utc).strftime("%H:%M:%S"), *a, flush=True)


def wait_until(t):
    while dt.datetime.now(dt.timezone.utc) < t:
        time.sleep(min(15.0, max(0.5, (t - dt.datetime.now(dt.timezone.utc)).total_seconds())))


def ro(sql):
    return S.query_ro(REF, sql)


def rw(sql):
    return S.query(REF, sql)


def ssh(cmd):
    r = subprocess.run(SSH + [cmd], capture_output=True, text=True, timeout=40)
    return (r.stdout + r.stderr).strip()


def raid_on():
    return ro("select raid_on from public.referee_config where id = 1")[0]["raid_on"]


def main():
    log("开始; 当前 raid_on =", raid_on(), "· 轮询器:", ssh("systemctl is-active turtle-referee-beta turtle-referee-beta-peak.timer").replace("\n", " "))
    # ── E1 ──
    wait_until(T_E1_ON)
    orig = raid_on()
    try:
        rw("update public.referee_config set raid_on = false where id = 1")
        log("E1 开始: raid_on", orig, "→", raid_on())
        wait_until(T_E1_OFF)
    finally:
        rw("update public.referee_config set raid_on = %s where id = 1" % ("true" if orig else "false"))
        log("E1 结束: raid_on 恢复为", raid_on())
    # ── 开算后作废 ──
    wait_until(T_V_ON)
    voided = None
    try:
        log("作废窗口开始: 停定时器与轮询器 ⇒", ssh("systemctl stop turtle-referee-beta-peak.timer turtle-referee-beta; systemctl is-active turtle-referee-beta turtle-referee-beta-peak.timer").replace("\n", " "))
        start_iso = T_V_ON.strftime("%Y-%m-%d %H:%M:%S+00")
        while dt.datetime.now(dt.timezone.utc) < T_V_OFF and voided is None:
            rows = ro("select id, raid_id, status from public.raid_jobs where created_at >= '%s' order by created_at limit 1" % start_iso)
            if rows:
                r = rows[0]
                log("窗口里第一场:", r)
                if r["status"] == "queued":
                    rw("select public.raid_void(%d, 'manual_test_void')" % int(r["id"]))
                    voided = int(r["id"])
                    log("已作废 job", voided, "⇒", ro("select status, result, reason from public.raid_jobs where id = %d" % voided))
                else:
                    log("它不是 queued(", r["status"], ") —— 不动")
                    voided = -1
            else:
                time.sleep(5)
        if voided is None:
            log("作废窗口里没有新偷袭")
        wait_until(T_V_OFF)
    finally:
        log("作废窗口结束: 恢复轮询器与定时器 ⇒", ssh("systemctl start turtle-referee-beta turtle-referee-beta-peak.timer; systemctl is-active turtle-referee-beta turtle-referee-beta-peak.timer").replace("\n", " "))
    if voided and voided > 0:
        time.sleep(90)
        rr = ro("select raid_id from public.raid_jobs where id = %d" % voided)
        if rr:
            ob = ro("select topic, last_status, body::text as body from public.mainsite_outbox where body->>'raidId' = '%s' order by id" % str(rr[0]["raid_id"]))
            log("作废那场的发件箱:", ob)
    log("其余窗口内的偷袭:", ro("select id, raid_id, status, result from public.raid_jobs where created_at >= '%s' order by created_at" % T_E1_ON.strftime("%Y-%m-%d %H:%M:%S+00")))
    log("结束; raid_on =", raid_on())


if __name__ == "__main__":
    main()
