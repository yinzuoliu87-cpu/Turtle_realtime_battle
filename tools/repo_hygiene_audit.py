"""repo_hygiene_audit.py — 仓库文件卫生门禁（进 run-tests.sh）

守 2026-11-02 文件管理重整的成果不回潮（方案书 docs/plans/20261102-文件管理与发版流程重整.md F6）：
  ① 根目录被跟踪的文件只许是白名单里的那些 —— 新的零散文件（例：曾经提交过一个 0 字节的 `60`）红
  ② docs/ tools/ build/ 的 .gdignore 在位 —— 缺了 Godot 会把文档截图 / 工具产物当素材导入
     （重整前导入缓存 8456 条里只有 2854 条是 assets/，docs/ 一处就占 244 MB）
  ③ docs/ 与 tools/ 下不许跟踪 .import —— 有 .gdignore 后它们是没人读的死文件
  ④ docs/ 下单个被跟踪文件 > 2 MB 红；存量 12 个记在下方 BIG_DEBT，只减不增
  ⑤ 代码里不许再写根目录默认落点 "res://_…"（开发产物一律 res://.out/，见 scripts/util/dev_out.gd）
  ⑥ run-tests.sh 不许再把失败日志写到根目录 .gate-fail-*（落 .out/gate/）
最后打印 ALL OK；任何一条红就 FAILED 并非零退出。每条都打印分母（N=0 是空检查不是通过）。
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT_ALLOW = {
    ".gitignore", "CHANGELOG.md", "CLAUDE.md", "README.md", "build-web.sh", "build-win.sh",
    "export_presets.cfg", "fetch-ios.sh", "godot-quiet.sh", "icon.png", "icon.png.import",
    "icon.svg", "icon.svg.import", "project.godot", "run-duel.sh", "run-tests.sh", "run-trainer-ab.sh",
}
GDIGNORE = ["docs/.gdignore", "tools/.gdignore", "build/.gdignore"]
BIG_LIMIT = 2 * 1024 * 1024
## 2026-11-02 存量（> 2 MB）。只减不增：删掉或压小一个就从这里划掉一行；新增的大文件当场红。
BIG_DEBT = {
    "docs/plans/img-20261020-教程/教程v3-全程录屏.mp4",   # 33.6 MB
    "docs/plans/img-20261020-变脸龟/02-变脸切近战-锤击跳砸.gif",   # 9.4 MB
    "docs/plans/ref-tentacle-attack.png",   # 6.7 MB
    "docs/plans/ref/20261005-手游大厅/dota-underlords-main-menu.jpg",   # 3.6 MB
    "docs/plans/ref/sion-q/塞恩Q-命中前后全分辨率.png",   # 2.7 MB
    "docs/plans/ref-tentacle-idle.png",   # 2.6 MB
    "docs/plans/img-20261019-逐帧直播/00-总览-六类各一组-本机跑_左-播放_右.png",   # 2.4 MB
    "docs/plans/ref/20261006-云顶装备弹窗/3-tft手游-点羁绊弹小卡.png",   # 2.4 MB
    "docs/plans/img-20261020-变脸龟/04-变脸切远程-灵能冲击.gif",   # 2.3 MB
    "docs/plans/ref/20261006-云顶装备弹窗/2-tft手游-检视面板实机.png",   # 2.3 MB
    "docs/plans/img-20261020-变脸龟/02-变脸切近战-锤击跳砸.png",   # 2.2 MB
    "docs/plans/ref/20261005-手游大厅/league-of-legends-wild-rift-main-menu.png",   # 2.1 MB
}
CODE_DIRS = ["autoload", "scripts", "tests", "tools"]
ROOT_OUT_RE = re.compile(r'["\']res://_[A-Za-z0-9]')


def tracked(*paths):
    r = subprocess.run(["git", "-C", ROOT, "-c", "core.quotepath=off", "ls-files", "--"] + list(paths),
                       capture_output=True)
    return [p for p in r.stdout.decode("utf-8", "replace").splitlines() if p]


def main():
    fails = []
    allf = tracked()
    print("[分母] 被跟踪文件 %d 个" % len(allf))

    root_files = [p for p in allf if "/" not in p]
    extra = sorted(set(root_files) - ROOT_ALLOW)
    print("① 根目录被跟踪文件 %d 个（白名单 %d）" % (len(root_files), len(ROOT_ALLOW)))
    if extra:
        fails.append("① 根目录多出被跟踪的零散文件: %s —— 放进对应目录, 真要放根目录就加进 ROOT_ALLOW 并写理由" % extra)

    tset = set(allf)
    miss = [g for g in GDIGNORE if g not in tset]
    print("② .gdignore 应在 %d 处，缺 %d 处" % (len(GDIGNORE), len(miss)))
    if miss:
        fails.append("② 缺 .gdignore（且要被跟踪）: %s" % miss)

    imports = [p for p in allf if p.endswith(".import") and (p.startswith("docs/") or p.startswith("tools/"))]
    print("③ docs/ tools/ 下被跟踪的 .import %d 个" % len(imports))
    if imports:
        fails.append("③ docs/ 或 tools/ 下跟踪着 .import（前 5 个）: %s" % imports[:5])

    docs = [p for p in allf if p.startswith("docs/")]
    big = sorted(p for p in docs if os.path.exists(os.path.join(ROOT, p))
                 and os.path.getsize(os.path.join(ROOT, p)) > BIG_LIMIT)
    new_big = [p for p in big if p not in BIG_DEBT]
    print("④ docs/ 被跟踪 %d 个，> 2 MB 的 %d 个（台账 %d）" % (len(docs), len(big), len(BIG_DEBT)))
    if new_big:
        fails.append("④ docs/ 新增 > 2 MB 的文件: %s —— 截图转 jpg / 缩尺寸, 录屏放仓库外只留链接" % new_big)
    gone = sorted(BIG_DEBT - set(big))
    if gone:
        print("   台账里有 %d 个已不在或已压小，可从 BIG_DEBT 划掉: %s" % (len(gone), gone))

    code = [p for p in allf if p.split("/")[0] in CODE_DIRS and p.endswith((".gd", ".py"))
            and not p.endswith("repo_hygiene_audit.py")]
    hits = []
    for p in code:
        try:
            for i, line in enumerate(open(os.path.join(ROOT, p), encoding="utf-8", errors="replace"), 1):
                s = line.lstrip()
                if s.startswith("#"):
                    continue
                if ROOT_OUT_RE.search(line):
                    hits.append("%s:%d" % (p, i))
        except OSError:
            pass
    print("⑤ 扫 %d 个 .gd/.py，根目录默认落点 \"res://_…\" %d 处" % (len(code), len(hits)))
    if hits:
        fails.append("⑤ 又出现写往根目录的默认落点（改用 DevOut.path / res://.out/）: %s" % hits[:8])

    rt = open(os.path.join(ROOT, "run-tests.sh"), encoding="utf-8", errors="replace").read()
    bad_rt = [ln.strip() for ln in rt.splitlines() if ".gate-fail-" in ln and not ln.lstrip().startswith("#")]
    print("⑥ run-tests.sh 写根目录 .gate-fail-* 的行 %d 处" % len(bad_rt))
    if bad_rt:
        fails.append("⑥ run-tests.sh 又把失败日志写到根目录: %s" % bad_rt[:3])

    if fails:
        for f in fails:
            print("[FAIL] " + f)
        print("\nFAILED: %d 处" % len(fails))
        return 1
    print("\nALL OK — 仓库文件卫生通过（根目录白名单 / .gdignore / 无死 .import / 文档大文件只减不增 / 开发产物落 .out）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
