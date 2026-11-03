"""rules_fingerprint.py —— 对局规则指纹的金标（tests/golden/rules_fingerprint.json）刷新 / 核对。

  python tools/rules_fingerprint.py            # 核对: 跑一遍, 与金标比（门禁里的 verify_rules_fingerprint 做的是同一件事）
  python tools/rules_fingerprint.py --update   # 刷新金标

门禁 tests/verify_rules_fingerprint.gd（方案书 docs/plans/20261102-文件管理与发版流程重整.md R1, Issue #4）:
对局结果变了而 RULES_VER 没升 ⇒ 红。本工具负责「什么时候许刷新金标」:
  · 某一局「场景定义摘要」没变而结果摘要变了 = 规则变了 ⇒ 当前 RULES_VER 必须大于上个 v* tag 的
    （改了结果就当场升, `tools/release.py bump --rules changed` 发版时看到已经升过不会再 +1）, 否则拒绝写
  · 只是场景表新增 / 改了某一局（定义摘要不在旧金标里）⇒ 不要求升
  · 跑出来有任何 FAIL（覆盖分母缺一样、同进程重跑不一致…）⇒ 拒绝写
Godot 路径取 $GODOT, 默认同 run-tests.sh；存档隔离在 .out/u_rules_fp（不碰真存档, 不连服务器）。
"""
import json, os, re, subprocess, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GOLDEN = os.path.join(ROOT, "tests", "golden", "rules_fingerprint.json")
GODOT = os.environ.get("GODOT") or r"C:\Users\Louis\Desktop\Godot_v4.6.3-stable_win64.exe"
F_PHASE2 = "scripts/gamedata/phase2_config.gd"
RV_RE = re.compile(r"(?m)^const RULES_VER := (\d+)\r?$")


def git(*args):
    return subprocess.run(["git", "-c", "core.quotepath=off"] + list(args), cwd=ROOT, capture_output=True,
                          text=True, encoding="utf-8", errors="replace")


def last_tag_rules_ver():
    tag = git("describe", "--tags", "--match", "v*", "--abbrev=0").stdout.strip()
    if not tag:
        return None, None
    ms = RV_RE.findall(git("show", "%s:%s" % (tag, F_PHASE2)).stdout)
    return tag, (int(ms[0]) if len(ms) == 1 else None)


def run_print():
    u = os.path.join(ROOT, ".out", "u_rules_fp")
    os.makedirs(u, exist_ok=True)
    env = {**os.environ, "APPDATA": u, "XDG_DATA_HOME": u, "TURTLE_SUPABASE": " ", "TURTLE_BACKEND": " ", "RULES_FP_PRINT": "1"}
    env.pop("RULES_FP_ONLY", None)
    env.pop("RULES_FP_DUMP", None)
    p = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", ROOT,
                        "res://tests/verify_rules_fingerprint.tscn", "--quit-after", "12000"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=900)
    out = p.stdout + p.stderr
    log = os.path.join(ROOT, ".out", "rules_fingerprint.log")
    open(log, "w", encoding="utf-8").write(out)
    js = [l[len("RULES_FP_JSON="):] for l in out.splitlines() if l.startswith("RULES_FP_JSON=")]
    fails = [l.strip() for l in out.splitlines() if "[FAIL]" in l]
    if p.returncode != 0 or len(js) != 1 or fails or "PRINT OK" not in out:   # 打印模式收尾打 PRINT OK（不打 ALL PASS, 免得被当成门禁通过）
        for l in fails[:20]:
            print("  " + l)
        raise SystemExit("✗ 跑出来不干净（退出码 %d / 指纹行 %d / FAIL %d / PRINT OK %s）—— 日志 %s"
                         % (p.returncode, len(js), len(fails), "PRINT OK" in out, log))
    return json.loads(js[0])


def main():
    update = "--update" in sys.argv[1:]
    cur = run_print()
    rv = int(cur["rules_ver"])
    old = json.load(open(GOLDEN, encoding="utf-8")) if os.path.exists(GOLDEN) else None
    print("当前: 总指纹 %s · %d 局 · RULES_VER %d" % (cur["fingerprint"][:16], cur["cases"], rv))
    if old is None:
        print("金标: 没有（%s）" % os.path.relpath(GOLDEN, ROOT))
        changed, added = [], [pc["tag"] for pc in cur["per_case"]]
    else:
        print("金标: 总指纹 %s · %d 局 · RULES_VER %d" % (old["fingerprint"][:16], old["cases"], old["rules_ver"]))
        prev = {pc["def"]: pc["hash"] for pc in old.get("per_case", [])}
        changed = [pc["tag"] for pc in cur["per_case"] if pc["def"] in prev and prev[pc["def"]] != pc["hash"]]
        added = [pc["tag"] for pc in cur["per_case"] if pc["def"] not in prev]
    same = old is not None and old["fingerprint"] == cur["fingerprint"] and int(old["rules_ver"]) == rv
    print("结果变了的局（定义没变）: %s" % (changed or "无"))
    print("场景表新增 / 改过的局: %s" % (added or "无"))
    if not update:
        print("\nALL OK —— 与金标一致" if same else "\nFAILED —— 与金标不一致（要刷新: --update）")
        return 0 if same else 1
    if same:
        print("\n金标已是最新, 不写。ALL OK")
        return 0
    if changed:
        tag, base = last_tag_rules_ver()
        if base is None:
            raise SystemExit("✗ 结果变了, 但读不出上个 v* tag（%s）的 RULES_VER —— 不写" % tag)
        if rv <= base:
            raise SystemExit("✗ %d 局结果变了而 RULES_VER = %d 不大于上个 tag %s 的 %d —— 先把 %s 的 RULES_VER +1"
                             "（上方加一行带日期的注释写清改了什么）, 再 --update" % (len(changed), rv, tag, base, F_PHASE2))
        print("结果变了, RULES_VER %d > 上个 tag %s 的 %d ⇒ 许刷新" % (rv, tag, base))
    os.makedirs(os.path.dirname(GOLDEN), exist_ok=True)
    body = {"fingerprint": cur["fingerprint"], "rules_ver": rv, "cases": cur["cases"], "per_case": cur["per_case"],
            "_note": "verify_rules_fingerprint 的金标；只用 python tools/rules_fingerprint.py --update 写（它核对 RULES_VER）"}
    with open(GOLDEN, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(body, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    print("\n已写 %s。ALL OK" % os.path.relpath(GOLDEN, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
