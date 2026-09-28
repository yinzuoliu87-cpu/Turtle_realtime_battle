# -*- coding: utf-8 -*-
"""`--update` 重写台账之前的一道**提醒**(2026-09-28)。

════════════════════════════════════════════════════════════════════════
 ★由来: 一次真实的误操作, 差一步就把别人没做完的活焊进棘轮
════════════════════════════════════════════════════════════════════════
2026-09-28 补反向验证时, 两条棘轮台账各报了一条 `[已清]`:
  · `write_orphan`  : `[已清] dual_shop_visits 现在有人写真值了 —— --update 把它删掉`
  · `asset_borrow`  : `[已清] (a) vfx/boom-wave-anim.png —— 记得 --update 把它删掉`
照提示 `--update` 是**错的**。拿干净 HEAD 影子树一量就清楚: 两条在 HEAD 上都还在,
`[已清]` 全部来自**别的 agent 当时未提交的改动**(`dual_shop_visits` 被整段删了、
`boom-wave-anim` 少了一个引用点)。

★后果不是"多删一行台账", 而是**棘轮会吞掉一个真违规**:
  同一轮里另一个 agent 往 `phase2_types.gd` 加了第二张「类型→图标」表,
  `asset_borrow` 当场报了 12 条新的跨语义。那时候 `--update` 一跑,
  这 12 条会被写进台账当**存量**, 从此**再也不会红** —— 而"只减不增"的棘轮
  正是靠"新增当场红"活着的。一次手滑就把这条判据废掉一半。

★所以这里**只提醒、不拦**(与本仓对这一类的一贯口径一致):
  不 push 是铁律, 未提交状态常在且值钱(memory [[fb-never-git-checkout-to-cleanup]]),
  "工作区必须干净"会天天误报然后被无视。要拦的不是"有未提交改动",
  而是"**你知不知道自己正在把谁的未提交改动焊进来**"。

★★判据故意只看【被扫目录下有没有未提交改动】, 不去猜哪条台账差异由哪个文件引起 ——
  猜错方向会让人以为"其余几条是安全的"。给的是**去看一眼**的清单, 不是结论。
"""
import os
import subprocess
import sys


def warn_if_dirty(scan_dirs, root=None):
    """`--update` 前打一条提醒。→ True 表示确实有未提交改动(仅供调用方参考)。

    `scan_dirs` = 这个审计器扫的目录(台账只可能被这些目录里的改动影响)。
    """
    root = root or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    try:
        out = subprocess.run(["git", "status", "--porcelain", "--"] + list(scan_dirs),
                             cwd=root, capture_output=True, text=True, timeout=30)
        rows = [l for l in (out.stdout or "").splitlines() if l.strip()]
    except Exception as e:                      # 没有 git / 不是仓库 ⇒ 不打扰
        print("  [台账守卫] 查不了工作区状态(%s) —— 跳过提醒, 自己确认一下。" % e)
        return False
    if not rows:
        print("  [台账守卫] 被扫目录(%s)工作区干净 ⇒ 这次 --update 记的是**已提交的事实**。"
              % " ".join(scan_dirs))
        return False
    print("")
    print("  ★★[台账守卫] 被扫目录下有 %d 个文件**未提交**, 而 --update 会把它们此刻的样子"
          "焊进棘轮台账:" % len(rows))
    for r in rows[:20]:
        print("       %s" % r)
    if len(rows) > 20:
        print("       …… 还有 %d 个" % (len(rows) - 20))
    print("  ⇒ 先确认这些改动**是你自己的、并且会和台账同一次提交**。")
    print("    多 agent 并行时最容易踩的是这一下: 台账把**别人没做完的活**记成了存量,")
    print("    而棘轮是靠「新增当场红」活着的 —— 记成存量 = 那条判据从此对它闭眼。")
    print("    拿不准就**别 update**: 先 `git stash -u` 或等对方提交完再记。")
    print("")
    return True
