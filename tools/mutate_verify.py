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


def _git_diff(path):
    """这个文件相对 HEAD 的完整 diff 正文; git 跑不起来时返回 None(而不是空串 ——
    空串的含义是'干净', 拿不到结果不能冒充干净)。"""
    try:
        g = subprocess.run(["git", "diff", "--", path], capture_output=True, timeout=60)
        if g.returncode != 0:
            return None
        return g.stdout.decode("utf-8", "replace")
    except Exception:
        return None


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

    ## ★读也必须 newline="" —— 默认的通用换行模式会在**读的那一刻**
    ##   把 CRLF 翻译成 \n, 写回去就变成了 LF —— 而下面那句核对的两边
    ##   又被同样翻译一遍 ⇒ **它对行尾变化是瞎的**。
    ##   本仓库行尾是混的(equip_system.gd 是 CRLF、battle_hud.gd 是 LF),
    ##   一旦变异到 CRLF 文件就会把整份文件重写一遍而没人发现(2026-08-30 差点踩上)。
    orig = io.open(path, encoding="utf-8", newline="").read()
    ## ★★变异开始【前】先拍一张 git diff 快照当基准。
    ##   为什么不是"跑完之后问 git 这个文件干不干净": 被反向验证的文件通常
    ##   【本来就有本轮要交付的改动】, 那种问法必然报 FAIL ⇒ 变成人尽皆知的假警报,
    ##   而真的残留就藏在这条假警报里(2026-08-31 我就是这么把 0.015 放过去的:
    ##   它打印了 "git 说还有改动: 11 1", 我判成"这是预期改动"、于是漏了没还原的那一档)。
    ##   基准取"变异前的 diff"就同时管住两种情况: 干净文件 → 基准是空串;
    ##   带着预期改动的文件 → 基准是那些预期改动本身。**还原之后必须一模一样。**
    base_diff = _git_diff(path)
    n_bad = 0
    try:
        for name, old, new in muts:
            ## ★名称写成 "说明#2" ⇒ 改【第 2 处】出现。
            ##   由来(2026-09-01): GameState 的 reset_save 与 start_new_season 两段重置
            ##   代码**逐字相同**, 上下文往外扩十几行仍然一样(一个以 EOF 收口, 表达不出来)。
            ##   没有这个开关就只能手写临时脚本去改第二处 —— 而手写脚本正是
            ##   [[fb-restore-mutations-after-reverse-verify]] 那次没还原的来源。
            ##   ⇒ 宁可给工具加一个显式的序号, 也不要绕开工具。
            which = 1
            if "#" in name and name.rsplit("#", 1)[1].isdigit():
                which = int(name.rsplit("#", 1)[1])
            cnt = orig.count(old)
            if cnt < which or (which == 1 and cnt != 1):
                print("  [FAIL] 变异「%s」的旧串在原文里出现 %d 次(要第 %d 处; 不写 #N 时必须正好 1 次)"
                      % (name, cnt, which))
                n_bad += 1
                continue
            ## 定位到第 which 处再替换(前 which-1 处原样留着)
            head, tail = "", orig
            for _k in range(which - 1):
                i = tail.index(old) + len(old)
                head, tail = head + tail[:i], tail[i:]
            io.open(path, "w", encoding="utf-8", newline="").write(head + tail.replace(old, new, 1))
            fails, broke = run_scene(scene)
            print("▶ 变异: %s" % name)
            if broke:
                print("   ⚠ 编译/运行报错 —— 这次变异没隔离住断言: %s" % broke[0][:90])
                n_bad += 1
            elif not fails:
                print("   ✗✗ 一条都没红 —— 这条门禁是假的")
                n_bad += 1
            else:
                ## ★★印总数再印前 3 条 —— 只印前 3 条却不说总数 = **工具自己没有分母**。
                ##   2026-09-01 我因此差点把两条【真红了】的断言判成"没红"(它们排在第 4/第 5),
                ##   然后去"修"一条根本没坏的判据。截断必须自报截了多少。
                print("   共红 %d 条; 列前 3 条:" % len(fails))
                for f in fails[:3]:
                    print("   ✓ " + f[:112])
                if len(fails) > 3:
                    print("   … 另有 %d 条也红了(未列出)" % (len(fails) - 3))
    finally:
        ## ★★无论上面发生什么都写回, 然后【再读一遍逐字节核对】。
        ##   只写不核对正是 2026-08-29 那次翻车的形状(脚本还打印了"已还原")。
        io.open(path, "w", encoding="utf-8", newline="").write(orig)
        restored = (io.open(path, encoding="utf-8", newline="").read() == orig)
        if restored:
            print("")
            print("  [还原核对] %s 与变异前逐字节一致 (%d 字符)" % (path, len(orig)))
        else:
            print("")
            print("  [FAIL] ★★还原失败: 写回后与原文【不一致】—— 立刻手工检查 %s" % path)
        ## ★★第二只眼: 除了"我写回的字符串 == 我读到的", 还要问 **git**。
        ##   由来(2026-08-31, 同一个坑第四次): 上一轮反向验证之后
        ##   `HOTSPRING_PCT` 的第三档留在了 0.015(用户给的是 1.2%), 而本工具
        ##   照样打印了"逐字节一致" —— 因为它比的是【它自己读进来的 orig】,
        ##   orig 读进来时就已经脏了的话, 这个比对是【和脏的自己比】, 恒真。
        ##   git 是**独立的第二个来源**, 它不知道 orig 是什么。
        ##   ★但判据必须是"和变异前的 diff 一致", 不是"相对 HEAD 无改动" ——
        ##   后者对任何带着未提交改动的文件恒 FAIL, 于是没人再看它。
        ##   (同族 memory [[fb-verify-check-can-fail]] / [[fb-judge-must-fit-the-shape]]:
        ##    判据不能和自己比, 也不能宽一格造出人人忽略的假警报。)
        now_diff = _git_diff(path)
        if now_diff is None or base_diff is None:
            print("  [git 第二只眼] 跑不起来 —— 只剩逐字节核对这一只眼")
        elif now_diff == base_diff:
            print("  [git 第二只眼] %s 的 git diff 与变异前完全一致 ✓ (基准 %d 字符)"
                  % (path, len(base_diff)))
        else:
            print("  [FAIL] ★★git 说 %s 的改动与【变异前】不一样 —— 没还原干净!" % path)
            import difflib
            for ln in list(difflib.unified_diff(base_diff.splitlines(), now_diff.splitlines(),
                                                "变异前", "还原后", lineterm=""))[:14]:
                print("         " + ln)
            restored = False

    if not restored:
        return 1
    if n_bad:
        print("FAILED: %d 个变异没能证明门禁会红" % n_bad)
        return 1
    print("ALL OK — 每个变异都让门禁红了, 且产品代码已逐字节还原")
    return 0


if __name__ == "__main__":
    sys.exit(main())
