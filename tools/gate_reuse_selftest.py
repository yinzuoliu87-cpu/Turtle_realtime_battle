"""gate_reuse_selftest.py —— 「只改文档 ⇒ 复用上次全绿」的口径自测（2026-11-04，用户「改」；方案书 docs/plans/20261104-门禁提速.md）。

在临时目录建一个迷你 git 仓库，用真的 tools/gate_input_key.py 算 key，逐种改动看 key 变不变：
  不变(可复用)：只改 docs/ 下没被点名的文档 / 只改根目录没被点名的 .md
  变(跑全套)  ：改被 Godot 侧 res:// 点名的文档 / 改 CHANGELOG(被点名) / 改测试代码(注释也算) / 改 tools/*.py /
                新加未跟踪文件 / 删文件 / 点名的是目录前缀时改该目录下的文档 / 换 Godot 可执行文件
不碰真仓库（门禁里与测试池并行跑也安全）。打印分母（跑了几种情况）。全对打 ALL OK。
"""
import os, shutil, subprocess, sys, tempfile

sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
KEY_TOOL = os.path.join(HERE, "gate_input_key.py")

FILES = {
    "project.godot": "config/name=\"t\"\n",
    "CHANGELOG.md": "# 0.0.1\n",
    "CLAUDE.md": "# rules\n",
    "docs/plans/p.md": "# plan\n",
    "docs/ref.md": "# read by a test\n",
    "docs/lib/a.md": "# under a named prefix\n",
    "tests/verify_x.gd": 'extends Node\nconst C := "res://CHANGELOG.md"\nconst D := "res://docs/ref.md"\nconst L := "res://docs/lib/" + "a.md"\n',
    "scripts/s.gd": "extends Node\n",
    "tools/t.py": "print('x')\n",
}


def sh(root, *args):
    subprocess.run(["git", "-C", root, *args], capture_output=True, check=True)


def key(root, godot):
    env = dict(os.environ, GATE_KEY_ROOT=root, GODOT=godot)
    p = subprocess.run([sys.executable, KEY_TOOL], env=env, capture_output=True, check=True)
    return p.stdout.decode().splitlines()[0].strip()


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="gate_reuse_")
    root = os.path.join(tmp, "repo")
    os.makedirs(root)
    godot = os.path.join(tmp, "godot.exe")
    open(godot, "wb").write(b"v1")
    try:
        for rel, body in FILES.items():
            os.makedirs(os.path.dirname(os.path.join(root, rel)) or root, exist_ok=True)
            open(os.path.join(root, rel), "w", encoding="utf-8", newline="\n").write(body)
        sh(root, "init", "-q")
        sh(root, "-c", "core.autocrlf=false", "add", "-A")
        sh(root, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "base")
        base = key(root, godot)
        cases = []

        def check(tag, want_same, do, undo):
            do()
            got = key(root, godot)
            undo()
            ok = (got == base) == want_same
            cases.append(ok)
            print("  %s %-40s 期望 %s" % ("PASS" if ok else "FAIL", tag, "可复用(key 不变)" if want_same else "跑全套(key 变)"))

        def edit(rel, extra="\n# probe\n"):
            p = os.path.join(root, rel)
            orig = open(p, "rb").read()
            return (lambda: open(p, "ab").write(extra.encode())), (lambda: open(p, "wb").write(orig))

        for tag, rel, same in [("只改方案书 docs/plans/p.md", "docs/plans/p.md", True),
                               ("只改根目录 CLAUDE.md(没被点名)", "CLAUDE.md", True),
                               ("改被测试点名的 docs/ref.md", "docs/ref.md", False),
                               ("改 CHANGELOG.md(被点名)", "CHANGELOG.md", False),
                               ("改点名目录前缀下的 docs/lib/a.md", "docs/lib/a.md", False),
                               ("改测试代码(注释也算)", "tests/verify_x.gd", False),
                               ("改 tools/t.py", "tools/t.py", False),
                               ("改 scripts/s.gd", "scripts/s.gd", False)]:
            d, u = edit(rel)
            check(tag, same, d, u)
        newf = os.path.join(root, "scripts", "new.gd")
        check("新加未跟踪文件", False, lambda: open(newf, "w").write("x"), lambda: os.remove(newf))
        delf = os.path.join(root, "scripts", "s.gd")
        keep = open(delf, "rb").read()
        check("删掉一个跟踪文件", False, lambda: os.remove(delf), lambda: open(delf, "wb").write(keep))
        g_st = os.stat(godot)

        def godot_back():
            open(godot, "wb").write(b"v1")
            os.utime(godot, (g_st.st_atime, g_st.st_mtime))   # key 含可执行文件的修改时间 ⇒ 还原要连时间一起还原
        check("换 Godot 可执行文件", False, lambda: open(godot, "wb").write(b"v2-longer"), godot_back)
        again = key(root, godot)
        cases.append(again == base)
        print("  %s %-40s 期望 key 回到基线" % ("PASS" if again == base else "FAIL", "全部还原后"))
        n_ok = sum(cases)
        print("分母: %d 种情况, 通过 %d" % (len(cases), n_ok))
        if n_ok == len(cases) and len(cases) >= 12:
            print("ALL OK —— 只改没被点名的文档才复用, 其余任何改动都跑全套")
            return 0
        print("FAILED")
        return 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
