"""clean.py — 清本机开发产物（默认只列，不删）

  python tools/clean.py                 列出每类有多少、多大（只读）
  python tools/clean.py --apply         执行：门禁旧日志 / 无源 .import 删掉；根目录旧截图挪进 .out/legacy/<日期>/（不删）
  python tools/clean.py --apply --purge-sims   另外删掉对局模拟产物（tools/autoplay、tools/duel*/ 里没跟踪的）

只动【被 .gitignore 忽略、没被跟踪】的文件（清单取自 git 自己：`git ls-files -o -i --exclude-standard`）。
不碰：build/（装机包）、.godot/（导入缓存，删了要全量重导入）、.claude/worktrees/（可能有没合的提交 —— 只报告）、
.git/info/exclude 里藏的参考图（用户的）。

由来（方案书 docs/plans/20261102-文件管理与发版流程重整.md F4）：2026-11-02 根目录攒了 718 个开发产物
（门禁失败日志 391 份、调试截图 325 个、_show/ 294 张），全被 .gitignore 藏着、`git status` 看不见、从来没人清。
现行落点是 /.out/（scripts/util/dev_out.gd），这个命令清的是旧落点留下的。
"""
import argparse
import datetime
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

NEVER = ("build/", ".godot/", ".claude/", ".git/")


def git(*args):
    r = subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True)
    return r.stdout.decode("utf-8", "replace")


def ignored_paths():
    out = git("-c", "core.quotepath=off", "ls-files", "-o", "-i", "--exclude-standard", "--directory")
    return [p for p in out.splitlines() if p and not p.startswith(NEVER)]


def size_of(rel):
    p = os.path.join(ROOT, rel)
    if os.path.isfile(p):
        return os.path.getsize(p)
    n = 0
    for d, _ds, fs in os.walk(p):
        for f in fs:
            try:
                n += os.path.getsize(os.path.join(d, f))
            except OSError:
                pass
    return n


def classify(paths):
    cats = {"gate": [], "orphan_import": [], "root_shots": [], "sims": [], "other": []}
    for rel in paths:
        top = rel.rstrip("/")
        base = os.path.basename(top)
        if "/" not in top and base.startswith(".gate-fail-"):
            cats["gate"].append(rel)
        elif top.endswith(".import") and not os.path.exists(os.path.join(ROOT, top[:-len(".import")])):
            cats["orphan_import"].append(rel)
        elif top.endswith(".translation") and top.startswith("tools/"):
            cats["orphan_import"].append(rel)   # 对局 CSV 被 Godot 当翻译表导入的产物; tools/ 有 .gdignore 后不会再生
        elif "/" not in top and (base.startswith("_") or base in ("Godot",)):
            cats["root_shots"].append(rel)
        elif top.startswith("tools/autoplay") or (top.startswith("tools/duel") and "/" in top):
            cats["sims"].append(rel)
        else:
            cats["other"].append(rel)
    return cats


def human(n):
    for u in ("B", "KB", "MB", "GB"):
        if n < 1024 or u == "GB":
            return "%.1f %s" % (n, u) if u != "B" else "%d B" % n
        n /= 1024.0


def worktree_report():
    out = git("worktree", "list", "--porcelain")
    rows, cur = [], {}
    for line in out.splitlines() + [""]:
        if not line:
            if cur.get("worktree") and os.path.normcase(os.path.abspath(cur["worktree"])) != os.path.normcase(ROOT):
                rows.append(cur)
            cur = {}
            continue
        k, _, v = line.partition(" ")
        cur[k] = v
    for w in rows:
        head = w.get("HEAD", "")
        ahead = git("rev-list", "--count", "origin/main.." + head).strip() if head else "?"
        print("  worktree %s  HEAD %s  比 origin/main 多 %s 个提交%s" % (
            w["worktree"], head[:8], ahead, "  ← 有没合的提交，别删" if ahead not in ("0", "") else ""))
    if not rows:
        print("  (没有别的 worktree)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--purge-sims", action="store_true")
    a = ap.parse_args()

    cats = classify(ignored_paths())
    label = {"gate": "门禁旧失败日志（根目录 .gate-fail-*，现落 .out/gate/）",
             "orphan_import": "无源 .import / tools 里的 .translation（纯缓存）",
             "root_shots": "根目录旧截图与实验台输出（_*、_show/、_vfxshots/、Godot/）",
             "sims": "对局模拟产物（tools/autoplay、tools/duel* 里没跟踪的）",
             "other": "其余被忽略的（不处理，只列）"}
    total = 0
    for k in ("gate", "orphan_import", "root_shots", "sims", "other"):
        n = sum(size_of(p) for p in cats[k])
        total += n
        print("[%s] %d 项 · %s — %s" % (k, len(cats[k]), human(n), label[k]))
        if k == "other":
            for p in cats[k][:15]:
                print("      " + p)
    print("合计 %s" % human(total))
    print("worktree：")
    worktree_report()

    if not a.apply:
        print("\n只列不删。执行加 --apply（截图只挪不删）；模拟产物另加 --purge-sims。")
        return 0

    for p in cats["gate"] + cats["orphan_import"]:
        full = os.path.join(ROOT, p.rstrip("/"))
        if os.path.isdir(full):
            shutil.rmtree(full, ignore_errors=True)
        elif os.path.exists(full):
            os.remove(full)
    legacy = os.path.join(ROOT, ".out", "legacy", datetime.date.today().strftime("%Y%m%d"))
    os.makedirs(legacy, exist_ok=True)
    moved = 0
    for p in cats["root_shots"]:
        src = os.path.join(ROOT, p.rstrip("/"))
        if not os.path.exists(src):
            continue
        if src.endswith(".import"):
            os.remove(src)          # 有源的 .import 跟着源走没有意义: 挪进点目录后 Godot 不再导入
            continue
        shutil.move(src, os.path.join(legacy, os.path.basename(src)))
        moved += 1
    if a.purge_sims:
        for p in cats["sims"]:
            full = os.path.join(ROOT, p.rstrip("/"))
            if os.path.isdir(full):
                shutil.rmtree(full, ignore_errors=True)
            elif os.path.exists(full):
                os.remove(full)
    left = classify(ignored_paths())
    print("\n已执行：删 %d 项日志 / 缓存，挪 %d 项截图到 %s%s" % (
        len(cats["gate"]) + len(cats["orphan_import"]), moved, os.path.relpath(legacy, ROOT),
        "，删模拟产物 %d 项" % len(cats["sims"]) if a.purge_sims else ""))
    print("剩余：gate %d · orphan_import %d · root_shots %d · sims %d" % (
        len(left["gate"]), len(left["orphan_import"]), len(left["root_shots"]), len(left["sims"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
