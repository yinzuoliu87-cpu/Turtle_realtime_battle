# -*- coding: utf-8 -*-
"""反向验证的安全外壳: 改坏 → 跑测试 → **保证还原并逐字节核对** (2026-08-29)。

★由来: 2026-08-29 又一次"改坏了没还原"。这次砍掉的是
    u["_b84_lock_until"] = battle._t + CROSS_T3 + BladeEqVfx.SLASH_LIFE
  末尾那一项。我的临时脚本**打印了"已还原"**, 但文件里还是坏的;
  我那轮只跑了 `git diff --numstat` 看行数、没看内容 ⇒ 一路带着它升版本号、
  跑全套门禁, 最后由三条不相干的红把它抖出来。

★为什么 `worktree_clean_check.py` 挡不住这一次(实测验过):
  那一行是**本次新增的行** —— HEAD 里根本没有它, 于是 diff 里没有 `-` 侧可配对,
  "尾巴被砍"那条判据无从比起。它只挡得住"改committed过的行"。

★所以真正的防线是【逐字节核对】, 而不是任何形状匹配。本工具保证:
  · 无论测试跑成什么样(甚至异常/超时), finally 一定写回原文
  · 写回后**再读一遍**与原文比对, 不一致就以非零码退出并大声喊
  · 顺带打印每个变异抓到了几条 [FAIL] —— 一条都没抓到就是【假门禁】

跑法:
  python tools/mutate_verify.py <产品文件> <测试场景.tscn> <名称> <旧串> <新串> [<名称> <旧串> <新串> ...]

例:
  python tools/mutate_verify.py scripts/systems/equip/eq_blade_batch.gd \\
      tests/verify_eq_blade_batch.tscn \\
      "不等动画" "CROSS_T3 + BladeEqVfx.SLASH_LIFE" "CROSS_T3"
"""
import io
import os
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

GODOT = os.environ.get("GODOT", "C:/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe")
FRAMES = os.environ.get("FRAMES", "4000")


def run_scene(scene):
    r = subprocess.run([GODOT, "--headless", "--path", ".", "res://" + scene.lstrip("./"),
                        "--quit-after", FRAMES],
                       capture_output=True, timeout=600,
                       env=dict(os.environ, TURTLE_BACKEND=" "))
    out = r.stdout.decode("utf-8", "replace")
    fails = [L.strip() for L in out.split("\n") if "[FAIL]" in L]
    broke = [L for L in out.split("\n") if "SCRIPT ERROR" in L or "Parse Error" in L]
    return fails, broke


def main():
    a = sys.argv[1:]
    if len(a) < 5 or (len(a) - 2) % 3 != 0:
        print(__doc__)
        return 2
    path, scene = a[0], a[1]
    muts = [(a[i], a[i + 1], a[i + 2]) for i in range(2, len(a), 3)]

    orig = io.open(path, encoding="utf-8").read()
    n_bad = 0
    try:
        for name, old, new in muts:
            cnt = orig.count(old)
            if cnt != 1:
                print("  [FAIL] 变异「%s」的旧串在原文里出现 %d 次(必须正好 1 次)" % (name, cnt))
                n_bad += 1
                continue
            io.open(path, "w", encoding="utf-8", newline="").write(orig.replace(old, new, 1))
            fails, broke = run_scene(scene)
            print("▶ 变异: %s" % name)
            if broke:
                print("   ⚠ 编译/运行报错 —— 这次变异没隔离住断言: %s" % broke[0][:90])
                n_bad += 1
            elif not fails:
                print("   ✗✗ 一条都没红 —— 这条门禁是假的")
                n_bad += 1
            else:
                for f in fails[:3]:
                    print("   ✓ " + f[:112])
    finally:
        ## ★★无论上面发生什么都写回, 然后【再读一遍逐字节核对】。
        ##   只写不核对正是 2026-08-29 那次翻车的形状(脚本还打印了"已还原")。
        io.open(path, "w", encoding="utf-8", newline="").write(orig)
        restored = (io.open(path, encoding="utf-8").read() == orig)
        if restored:
            print("")
            print("  [还原核对] %s 与变异前逐字节一致 (%d 字符)" % (path, len(orig)))
        else:
            print("")
            print("  [FAIL] ★★还原失败: 写回后与原文【不一致】—— 立刻手工检查 %s" % path)

    if not restored:
        return 1
    if n_bad:
        print("FAILED: %d 个变异没能证明门禁会红" % n_bad)
        return 1
    print("ALL OK — 每个变异都让门禁红了, 且产品代码已逐字节还原")
    return 0


if __name__ == "__main__":
    sys.exit(main())
