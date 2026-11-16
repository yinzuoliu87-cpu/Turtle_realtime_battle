"""ARM 裁判机试验(2026-11-16 · 用户「按你的建议走吧」= 租一台 ARM 测一小时再谈换)。

裁判机现在是 Hetzner CPX32(x86, €42.59/月含税), 同规格 ARM CAX21 €10.49 不含税。能不能换只看两件事:
  ① 确定性: ARM 上重算正式服真实对局, 胜方 + 结果指纹(digest)与 x86 裁判当时算的逐局相同
  ② 速度: 最重的局边算边录流要够快(10-19 判据: ≥ 2.5 倍实时; CPX32 实测 2.2~2.4 倍)

11-16 结果(试验机 hel1 cax21 · Ampere Altra / Neoverse N1 · 官方 Godot_v4.6.3-stable_linux.arm64 = 同一提交 7d41c59c4):
  ① 正式服 0.23.3 真实对局 84 局(决赛 24 / 闯关 30 / 积分赛 30)重算: 胜方 + 指纹逐字相同 84 / 84(改坏一个结果单 ⇒ 报 NOT SAME)
  ② tests/probes/_probe_stream_s1.gd(最重那局, 7951 步, 两边同时各跑一个进程, 取两遍最快):
       x86 CPX32  不录 245 步/秒 = 4.1 倍实时 · 录流 117 = 2.0 倍
       ARM CAX21  不录 179 步/秒 = 3.0 倍实时 · 录流  89 = 1.5 倍(单核约慢 27%; 两边 digest 相同)
  ③ nbg1 / fsn1 当天 cax21 都没货(412), 只有 hel1 有 ⇒ 换机要换 IP(主 IP 只能在同机房内挪)
  用法流程: create → 裁判机临时钥匙 rsync /opt/turtle/v0.23.3 + referee/ 过去 → jobs → 试验机上 .out/arm_trial/run.sh
           (3 局并行 referee_poller.py --local)→ 拉回 res/ → compare → delete(并删裁判机上的临时钥匙)

子命令(本机跑; 令牌只从 ~/.config/turtle/hcloud_token 读, 不打印):
  create            建 cax21(nbg1, ubuntu-24.04, SSH 钥匙 turtle-referee), 等到 running, 打印 IP
  ip                打印试验机 IP
  delete            删试验机(按名字; 只删 labels.purpose=arm-trial 的)
  jobs OUT N_F N_G N_R   从正式服(只读)导出 0.23.3 已算完的 决赛 / 闯关 / 积分赛 各 N 局 → OUT(jsonl, 每行 {job, expect})
  compare JOBS RESDIR    逐局比对 RESDIR/<job_id>.json(referee_poller --local 的结果单)与 expect
"""
import json
import os
import sys
import time
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
NAME = "turtle-arm-trial"
VER = "0.23.3"
OP = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def hz(method, path, body=None):
    tok = open(os.path.expanduser("~/.config/turtle/hcloud_token"), encoding="utf-8").read().strip()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request("https://api.hetzner.cloud/v1" + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        with OP.open(req, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def find():
    st, b = hz("GET", "/servers?name=" + NAME)
    s = (b.get("servers") or [None])[0]
    return s


def create():
    if find():
        print("已存在:", find()["public_net"]["ipv4"]["ip"])
        return 0
    for loc in ("nbg1", "fsn1", "hel1"):            # 11-16 nbg1 没货(412 resource_unavailable)
        st, b = hz("POST", "/servers", {"name": NAME, "server_type": "cax21", "image": "ubuntu-24.04", "location": loc,
                                        "ssh_keys": ["turtle-referee"], "labels": {"purpose": "arm-trial"}})
        print(loc, st, "" if st in (200, 201) else json.dumps(b, ensure_ascii=False)[:200])
        if st in (200, 201):
            break
    if st not in (200, 201):
        return 1
    sid = b["server"]["id"]
    for _ in range(60):
        st, b = hz("GET", "/servers/%d" % sid)
        if b["server"]["status"] == "running":
            break
        time.sleep(3)
    s = b["server"]
    print("running", s["server_type"]["name"], s["server_type"]["architecture"], s["public_net"]["ipv4"]["ip"])
    return 0


def delete():
    s = find()
    if not s:
        print("没有试验机")
        return 0
    if (s.get("labels") or {}).get("purpose") != "arm-trial":
        print("名字对但标签不对, 不删:", s.get("labels"))
        return 1
    st, b = hz("DELETE", "/servers/%d" % s["id"])
    print("删除", s["name"], st)
    return 0 if st in (200, 201, 204) else 1


def jobs(out, nf, ng, nr):
    import sb_common as S
    rows = []
    for kind, n in (("finals", nf), ("gauntlet", ng), ("ranked", nr)):
        sql = ("select job_id, match_id, kind, meta, season_week, match_key, seed, client_version, level, a_snapshot, b_snapshot, "
               "result->>'winner' w, result->>'digest' d, result->>'steps' s from referee_jobs "
               "where status = 'done' and client_version = '%s' and kind = '%s' and result ? 'digest' "
               "order by job_id desc limit %d" % (VER, kind, int(n)))
        rows += S.query_ro(S.PROD_REF, sql)
    with open(out, "w", encoding="utf-8") as f:
        for r in rows:
            key = dict(r["meta"] or {})
            key.update({"week": r["season_week"], "match_key": r["match_key"]})
            job = {"v": 1, "job_id": r["job_id"], "match_id": r["match_id"], "mode": r["kind"], "key": key, "seed": r["seed"],
                   "client_version": r["client_version"], "level": r["level"], "a": r["a_snapshot"], "b": r["b_snapshot"]}
            f.write(json.dumps({"job": job, "expect": {"winner": r["w"], "digest": r["d"], "steps": r["s"]}}, ensure_ascii=False) + "\n")
    print("导出 %d 局 → %s" % (len(rows), out))
    return 0


def compare(jobs_path, resdir):
    same = diff = missing = 0
    bad = []
    for line in open(jobs_path, encoding="utf-8"):
        x = json.loads(line)
        jid, exp = x["job"]["job_id"], x["expect"]
        p = os.path.join(resdir, "%s.json" % jid)
        if not os.path.isfile(p):
            missing += 1
            bad.append((jid, x["job"]["mode"], "没有结果单"))
            continue
        r = json.load(open(p, encoding="utf-8"))
        if r.get("ok") and str(r.get("winner")) == str(exp["winner"]) and str(r.get("digest")) == str(exp["digest"]):
            same += 1
        else:
            diff += 1
            bad.append((jid, x["job"]["mode"], "ok=%s 胜方 %s/%s 指纹 %s/%s 步数 %s/%s" % (
                r.get("ok"), r.get("winner"), exp["winner"], str(r.get("digest"))[:12], str(exp["digest"])[:12], r.get("steps"), exp["steps"])))
    print("分母 %d 局: 逐字相同 %d · 不同 %d · 没跑出来 %d" % (same + diff + missing, same, diff, missing))
    for b in bad[:20]:
        print("  ", b)
    print("ALL SAME" if diff == 0 and missing == 0 and same > 0 else "NOT SAME")
    return 0 if diff == 0 and missing == 0 and same > 0 else 1


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        sys.exit(2)
    if a[0] == "create":
        sys.exit(create())
    if a[0] == "ip":
        s = find()
        print(s["public_net"]["ipv4"]["ip"] if s else "")
        sys.exit(0)
    if a[0] == "delete":
        sys.exit(delete())
    if a[0] == "jobs":
        sys.exit(jobs(a[1], a[2], a[3], a[4]))
    if a[0] == "compare":
        sys.exit(compare(a[1], a[2]))
    print(__doc__)
    sys.exit(2)
