# -*- coding: utf-8 -*-
"""cohort_shard.py — 把 `tests/_cohort.gd` 的队列模拟切成 N 个分片【并行】跑, 再合并快照。

════════════════════════════════════════════════════════════════════════
 ★由来 (方案书 docs/plans/20260902-800队AI重跑对手快照.md)
════════════════════════════════════════════════════════════════════════
用户 2026-09-02 要 **800 支队伍**重跑对手快照。标定实测(8 只 / 600 秒 / 16 场):
**单场墙钟 ≈ 37.5 秒** ⇒ 800 只单进程约 **7 天**。用户拍板走「多进程并行跑分片」。

★我提过本机 CPU 有确诊硬件故障(WHEA + 两次无转储关机, 见 CLAUDE.md §2), 用户仍选并行 ⇒
  执行, 但把**可续跑**做进来: 每片产物独立落盘, 哪片挂了只补那片, 不用整批重来。

════════════════════════════════════════════════════════════════════════
 ★两个必须一起做的事(少一件整批就废) —— 已在 _cohort.gd 侧实现
════════════════════════════════════════════════════════════════════════
① **每片种子不同**: 否则各片造出一模一样的机器人、打一模一样的场, 跑 N 片
   只是把同一份结果复制 N 遍。(`base_seed + shard * 1000003`)
② **ghost_id 带片号**: 原来是 `coh_<bot>_b<n>`, 而 bot 编号每片都从 0 开始 ⇒
   合并时必然撞 id。(memory [[fb-id-without-owner-dimension]]: 单机够用的 id 一接共享就塌)

合并这一步**会逐条查 id 唯一性**, 撞了就报错退出 —— 不是相信上面两条, 是**验证**它们。

跑法:
    python tools/cohort_shard.py --bots 800 --shards 16          # 跑 + 合并
    python tools/cohort_shard.py --bots 800 --shards 16 --resume # 只补缺的片
    python tools/cohort_shard.py --merge-only --shards 16        # 只合并已有产物
"""
import argparse
import io
import json
import os
import subprocess
import sys
import time

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "C:/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe")
OUT_DIR = os.path.join(ROOT, "tools", "autoplay")
SCENE = "res://tests/_cohort.tscn"


def shard_out(i):
    return os.path.join(OUT_DIR, "cohort-snapshots-s%d.json" % i)


def launch(i, bots_per_shard, max_rounds, seed):
    """起一个分片进程。★每片自己的 APPDATA —— Godot 在 Windows 从 %APPDATA% 解析 user://,
    共用会让 N 个进程抢同一个存档目录(门禁那边踩过, run-tests.sh 也是这么隔离的)。"""
    env = dict(os.environ)
    env.update({
        "SHIP": "1",
        "DL_AUTOFIGHT": "1",
        "TURTLE_SEED": str(seed),
        "COHORT_BOTS": str(bots_per_shard),
        "COHORT_MAX_ROUNDS": str(max_rounds),
        "COHORT_SHARD": str(i),
        "COHORT_OUT": "res://tools/autoplay",
        "APPDATA": os.path.join("C:\\tmp", "cohort_appdata_s%d" % i),
    })
    os.makedirs(env["APPDATA"], exist_ok=True)
    log = os.path.join(OUT_DIR, "shard-%d.log" % i)
    lf = io.open(log, "w", encoding="utf-8", errors="replace")
    p = subprocess.Popen(
        [GODOT, "--headless", "--audio-driver", "Dummy", "--path", ROOT, SCENE],
        cwd=ROOT, env=env, stdout=lf, stderr=subprocess.STDOUT)
    return p, lf, log


def merge(shards):
    """合并各片快照。

    ★产物**不是数组**, 是 `{"_note": str, "brackets": {"<档>": [快照…]}}` ——
      我第一版按数组写, 小批实测当场发现(合出来 2 条: 那是在数 dict 的两个键)。
      这种"我以为的格式"和"真实格式"的差, 只有真跑一遍才看得见。
    ★逐条查 ghost_id 唯一 —— 撞 id 是这套并行最可能的失败形态, 必须**验**不是信。
    """
    brackets = {}
    seen = {}
    dup = []
    missing = []
    note = ""
    for i in range(shards):
        f = shard_out(i)
        if not os.path.exists(f):
            missing.append(i)
            continue
        try:
            d = json.load(io.open(f, encoding="utf-8"))
        except Exception as e:
            print("  [FAIL] 片 %d 的产物读不出来: %s" % (i, e))
            return None, missing, dup
        if not isinstance(d, dict) or "brackets" not in d:
            print("  [FAIL] 片 %d 的产物结构不对(应是 {_note, brackets})" % i)
            return None, missing, dup
        note = note or str(d.get("_note", ""))
        n = 0
        for bk, arr in (d["brackets"] or {}).items():
            for s in (arr or []):
                gid = str(s.get("ghost_id", ""))
                if gid == "":
                    print("  [FAIL] 片 %d 档 %s 有快照没有 ghost_id" % (i, bk))
                    return None, missing, dup
                if gid in seen:
                    dup.append((gid, seen[gid], i))
                seen[gid] = i
                brackets.setdefault(str(bk), []).append(s)
                n += 1
        print("  片 %-2d → %5d 条 (%d 档)" % (i, n, len(d["brackets"] or {})))
    return {"_note": note, "brackets": brackets}, missing, dup

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bots", type=int, default=800)
    ap.add_argument("--shards", type=int, default=16)
    ap.add_argument("--max-rounds", type=int, default=120)
    ap.add_argument("--seed", type=int, default=20260902)
    ap.add_argument("--resume", action="store_true", help="只跑还没有产物的片")
    ap.add_argument("--merge-only", action="store_true")
    a = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    per = max(2, a.bots // a.shards)

    if not a.merge_only:
        todo = [i for i in range(a.shards)
                if not (a.resume and os.path.exists(shard_out(i)))]
        print("=== 分片并行 ===")
        print("  目标 %d 只 · %d 片 · 每片 %d 只 · 最多 %d 轮 · 基础种子 %d"
              % (a.bots, a.shards, per, a.max_rounds, a.seed))
        print("  本轮要跑 %d 片: %s" % (len(todo), todo if len(todo) < 40 else "…"))
        if not todo:
            print("  (都已有产物, 跳过)")
        procs = []
        for i in todo:
            p, lf, log = launch(i, per, a.max_rounds, a.seed + i * 1000003)
            procs.append((i, p, lf, log))
            print("  起片 %-2d pid=%d → %s" % (i, p.pid, os.path.basename(log)))
        t0 = time.time()
        bad = []
        for i, p, lf, log in procs:
            rc = p.wait()
            lf.close()
            ok = os.path.exists(shard_out(i))
            print("  片 %-2d 退出 rc=%d · 产物%s · 累计 %.0f 分钟"
                  % (i, rc, "有" if ok else "**无**", (time.time() - t0) / 60.0))
            if rc != 0 or not ok:
                bad.append(i)
        if bad:
            print("")
            print("  [注意] 这些片没跑成: %s" % bad)
            print("         补跑: python tools/cohort_shard.py --resume --shards %d --bots %d"
                  % (a.shards, a.bots))

    print("")
    print("=== 合并 ===")
    snaps, missing, dup = merge(a.shards)
    if snaps is None:
        return 1
    if missing:
        print("  [FAIL] 缺片: %s —— 合并出来的池子会少人, 先补跑再合" % missing)
        return 1
    if dup:
        print("  [FAIL] ★ghost_id 撞了 %d 条(分片没把片号带进 id?) 前 5 条:" % len(dup))
        for g, x, y in dup[:5]:
            print("     %s  (片%d 与 片%d)" % (g, x, y))
        return 1
    out = os.path.join(OUT_DIR, "cohort-snapshots.json")
    io.open(out, "w", encoding="utf-8").write(json.dumps(snaps, ensure_ascii=False, indent=1))
    tot = sum(len(v) for v in snaps["brackets"].values())
    print("  合计 %d 条 · %d 档 · id 全唯一 → %s" % (tot, len(snaps["brackets"]), out))
    print("")
    print("  下一步: python tools/cohort_to_seed.py        # 先 dry-run 看自检")
    print("          python tools/cohort_to_seed.py --write")
    return 0


if __name__ == "__main__":
    sys.exit(main())
