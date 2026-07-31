# -*- coding: utf-8 -*-
"""arena.json 的【构图与可玩性】审计 —— 进 run-tests.sh 门禁。

守两类东西:

A. 可玩性硬约束(改地图时最容易破的三条)
   ① 战场 ARENA 内不许有 void。单位每步都被 clamp 进 ARENA, 脚下是 void = 站在黑洞上。
   ② 两队站位格不许是 void/water。开局第一眼就在那儿, 站水里最扎眼。
   ③ 接战区(两条线真正绞杀的那块)不许有水。水亮度 98、淤泥 32 —— 深色龟压在高亮青上
      最难读, 而那块地方单位密度最高。★这正是改前 v0 的毛病: 亮青池子恰好铺满接战区。

B. 可重跑性
   ④ arena.json 必须与 tools/gen_arena_map.py 【重跑的结果逐格一致】。
      地图是脚本生成的; 一旦有人用 MAPEDIT 手刷一下就存盘, 生成器就与事实脱钩,
      下次想调构图只能对着 493 个数字手改。这条断言把"生成器是事实源"焊死。
      (顺带: MAPEDIT 的 save() 用 JSON.stringify 无缩进, 一存就把文件压成一整行。)

跑法: python tools/map_composition_audit.py
"""
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_arena_map as G                                    # noqa: E402

MAP = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   'data', 'maps', 'arena.json')

# 与 RealtimeBattle3DScene.ARENA = Rect2(70, 110, 1596, 728) 对齐
ARENA = (70.0, 110.0, 1666.0, 838.0)
SPAWN_DX = 420.0            # dual_lane_flow: _cx ± 420
SPAWN_STEP = 154.0          # battle_spawn._spawn_lane_side 的纵向间距
SPAWN_SLOTS = 4             # 每路实际 3 只(GameState 默认布阵: 2统领+1小将 / 1统领+2小将),
                            # 这里查 4 = 留一格余量。全都要落在实地上。
                            # ★别调成 6: 那会把 dy=±385 也算进来, 已经超出 ARENA 半高 364,
                            #   单位根本到不了那儿 = 拿到不了的格子当断言 = 过严的假红。

VOID, WATER = 4, 1


def cell_of(px, py, m):
    c = int((px - m['origin_x']) / m['tile'])
    r = int((py - m['origin_y']) / m['tile'])
    return r, c


def main():
    m = json.load(io.open(MAP, encoding='utf-8'))
    grid = m['grid']
    w, h, tile = m['w'], m['h'], m['tile']
    ox, oy = m['origin_x'], m['origin_y']
    fails = []
    print("=== arena.json 构图与可玩性审计 ===")
    print("  分母: %d×%d = %d 格; tile=%.1f origin=(%.1f,%.1f)" % (w, h, w * h, tile, ox, oy))

    if len(grid) != h or any(len(row) != w for row in grid):
        print("  [FAIL] grid 尺寸与 w/h 不符"); print("FAIL x1"); sys.exit(1)

    # ── ① 战场内不许有 void ──
    bad = []
    for r in range(h):
        for c in range(w):
            px, py = ox + (c + 0.5) * tile, oy + (r + 0.5) * tile
            if ARENA[0] <= px <= ARENA[2] and ARENA[1] <= py <= ARENA[3] and int(grid[r][c]) == VOID:
                bad.append((r, c))
    n_play = sum(1 for r in range(h) for c in range(w)
                 if ARENA[0] <= ox + (c + .5) * tile <= ARENA[2]
                 and ARENA[1] <= oy + (r + .5) * tile <= ARENA[3])
    print("  ① 战场内 void: %d 个 (战场共 %d 格)" % (len(bad), n_play))
    if n_play < 100:
        fails.append("★分母异常: 战场只覆盖 %d 格, 后面都是空检查" % n_play)
    if bad:
        fails.append("① 战场内有 %d 个 void(单位会被 clamp 到那儿, 脚下不能是黑洞): %s" % (len(bad), bad[:6]))

    # ── ② 两队站位格不许是 void/water ──
    cx, cy = (ARENA[0] + ARENA[2]) / 2.0, (ARENA[1] + ARENA[3]) / 2.0
    spawn_bad = []
    n_spawn = 0
    for sgn in (-1.0, 1.0):
        for i in range(SPAWN_SLOTS):
            py = cy + (i - (SPAWN_SLOTS - 1) / 2.0) * SPAWN_STEP
            r, c = cell_of(cx + sgn * SPAWN_DX, py, m)
            if not (0 <= r < h and 0 <= c < w):
                continue
            n_spawn += 1
            if int(grid[r][c]) in (VOID, WATER):
                spawn_bad.append((r, c, int(grid[r][c])))
    print("  ② 站位格 void/water: %d 个 (共查 %d 格)" % (len(spawn_bad), n_spawn))
    if n_spawn < 8:
        fails.append("★分母异常: 只查到 %d 个站位格" % n_spawn)
    if spawn_bad:
        fails.append("② 有 %d 个站位格是 void/water: %s" % (len(spawn_bad), spawn_bad))

    # ── ③ 接战区不许有水 ──
    cbad = []
    n_clash = 0
    for r in range(h):
        for c in range(w):
            dx = ox + (c + 0.5) * tile - cx
            dy = oy + (r + 0.5) * tile - cy
            if abs(dx) <= G.CLASH_DX and abs(dy) <= G.CLASH_DY:
                n_clash += 1
                if int(grid[r][c]) in (VOID, WATER):
                    cbad.append((r, c))
    print("  ③ 接战区(±%.0f×±%.0f)内 水/void: %d 个 (接战区共 %d 格)"
          % (G.CLASH_DX, G.CLASH_DY, len(cbad), n_clash))
    if n_clash < 12:
        fails.append("★分母异常: 接战区只有 %d 格" % n_clash)
    if cbad:
        fails.append("③ 接战区有 %d 格水/void(单位最密的地方不该跟立绘抢明度): %s" % (len(cbad), cbad[:6]))

    # ── ④ 与生成器重跑结果逐格一致 ──
    regen = G.build()
    diff = [(r, c) for r in range(h) for c in range(w) if int(grid[r][c]) != int(regen[r][c])]
    print("  ④ 与 tools/gen_arena_map.py 重跑结果的分歧: %d 格" % len(diff))
    if diff:
        fails.append("④ arena.json 与生成器【不一致】%d 格 —— 有人手刷过(MAPEDIT 存盘会覆盖)。"
                     "要么重跑生成器, 要么把改动写回生成器: %s" % (len(diff), diff[:8]))

    print("")
    if fails:
        for f in fails:
            print("  [FAIL] " + f)
        print("FAIL x%d" % len(fails))
        sys.exit(1)
    print("ALL OK — 地图构图与可玩性 (4 条)")


if __name__ == '__main__':
    main()
