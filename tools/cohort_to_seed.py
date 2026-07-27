# -*- coding: utf-8 -*-
"""cohort_to_seed.py — 把【队列模拟产出的真实机器人快照】转成 data/ghost_seed.json。

用户 2026-07-27:
  「我的想法是怎么把真实的机器数据去转化为快照, 比如真的打到第十把, 角色队伍里有的装备是什么,
    把这个作为快照存入」
  「现在的快照都是比如强制全部2星什么的, 没有1,2,3费等混搭, 其实是很假的」

输入: tools/autoplay/cohort-snapshots.json  (tests/_cohort.gd 产出; 每场开打前存双方状态)
输出: data/ghost_seed.json

【不合成、不配平、不拟合】—— 原样搬运机器人当时的真实家当。混搭是"背包历史"的自然结果:
早期买的便宜货攒够 9 件合成了 ★3, 后期买的贵货还是 ★1 → 必然出现"便宜的星高、贵的星低"。
这正是旧池造不出来的东西(旧池每档只有 3-4 种固定 (费,星) 组合)。

选取规则:
  · 每档最多 PER_BRACKET 条; 优先挑【来自不同机器人】的, 保证龟阵容/技能/策略都散开
  · 同一只机器人在同一档最多留 SAME_BOT_CAP 条(它在一档里会打好几场, 家当差别不大)
  · 档0 必须全裸(用户锚点) —— 不是靠过滤, 而是核对: 档0 现在严格 = 人生第一把, 本来就该是裸的;
    真出现带装备的就报错退出, 说明上游 bracket_for_battles 或快照时机又错了

自检(与门禁 tests/verify_bracket_gear.gd 同口径, 不过关就不写):
  ① 档0 队长+小将都 0 件
  ② 每龟件数 ≤ equip_slots_for_battles(battles_for_bracket(档))
  ③ 单件均强度逐档单调递增
  ④ 每档条数 ≥ MIN_PER_BRACKET (太少 = 池子里总撞同几支)

跑法:
    python tools/cohort_to_seed.py                 # dry-run, 只打对照表
    python tools/cohort_to_seed.py --write         # 真写(会先跑一遍自检, 不过关拒写)
"""
import argparse
import collections
import io
import json
import os
import random
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SNAP_PATH = os.path.join(ROOT, "tools", "autoplay", "cohort-snapshots.json")
SEED_PATH = os.path.join(ROOT, "data", "ghost_seed.json")
EQUIP_PATH = os.path.join(ROOT, "data", "phase2-equipment.json")

PER_BRACKET = 20        # 每档留多少条(现役种子池每档 12~20)
SAME_BOT_CAP = 2        # 同一只机器人在同一档最多留几条
MIN_PER_BRACKET = 6     # 低于这个数就警告(候选不足 = 多样性不够)

K = {1: 0.85, 2: 0.90, 3: 1.00, 4: 1.15, 5: 1.30}


def strength(cost, star):
    return cost * (1.8 ** (star - 1)) * K.get(cost, 1.0)


def battles_for_bracket(b):
    """backend.gd:battles_for_bracket 的镜像 (2026-07-27 断点 -1 后)。"""
    return {0: 0, 1: 2, 2: 4, 3: 7, 4: 11, 5: 16, 6: 21, 7: 27}.get(b, 33)


def bracket_for_battles(n):
    """backend.gd:bracket_for_battles 的镜像 (2026-07-27「微调B」后: 档7=22场 / 档8=28场)。"""
    for lim, b in ((0, 0), (2, 1), (4, 2), (7, 3), (11, 4), (16, 5), (21, 6), (27, 7)):
        if n <= lim:
            return b
    return 8


UNIT_EQUIP_CAP = 3      # phase2_config.gd 镜像: 单只(统领/小将)装备上限


def team_equip_cap(level):
    """phase2_config.gd 镜像: 全队 6 只合计上限 = (等级-1)*2 → Lv1..10 = 0,2,...,18"""
    return max(0, (min(max(level, 1), 10) - 1) * 2)


def bracket_of(sn):
    """★按【新断点】从 season_total_battles 重算档位 —— 快照里的 bracket 字段可能是旧断点下写的。
    队列跑到一半改断点时不必重跑: 档位只是从场次派生的标签, 原始数据没变。"""
    return bracket_for_battles(int(sn.get("season_total_battles", 0)))


def items_of(sn):
    """快照里全部装备件 (队长 + 小将)。"""
    out = []
    for _pid, arr in (sn.get("equipped") or {}).items():
        out.extend(arr)
    for _lk, arr in (sn.get("minions") or {}).items():
        for m in arr:
            out.extend(m.get("equips") or [])
    return out


def profile(teams, by_cost):
    tot = 0.0
    n = 0
    combos = set()
    costs = collections.Counter()
    stars = collections.Counter()
    for t in teams:
        for it in items_of(t):
            c = by_cost.get(it["id"], 1)
            s = int(it.get("star", 1))
            tot += strength(c, s)
            n += 1
            combos.add((c, s))
            costs[c] += 1
            stars[s] += 1
    return {
        "teams": len(teams), "items": n,
        "team_strength": tot / max(1, len(teams)),
        "per_item": tot / max(1, n),
        "combos": len(combos), "costs": dict(sorted(costs.items())), "stars": dict(sorted(stars.items())),
    }


# ── 玩家昵称素材 (用户 2026-07-27:「就用现实生活玩家会怎么命名, 这样就不会重队名」) ──
# 旧池那套「忍者队·3档」是【按阵容+档位】起的, 一看就是系统生成的, 而且同档必然撞名。
# 真玩家起的是【自己的网名】, 与阵容无关 → 天然不重名, 也更像在跟真人对战。
_NICK_SOLO = [
    "小明", "阿强", "老王", "大壮", "阿宝", "小鱼干", "团子", "布丁", "可乐", "汤圆",
    "咸鱼", "阿飞", "老李", "豆豆", "麻薯", "泡芙", "小七", "阿杰", "糖糖", "西瓜",
    "Kevin", "Lucky", "Ace", "Nova", "Leo", "Max", "Ryan", "Zoe", "Echo", "Vito",
]
_NICK_ADJ = ["孤独的", "沉默的", "快乐的", "迷路的", "退休的", "打盹的", "认真的", "佛系", "无敌", "低调"]
_NICK_NOUN = ["老龟", "小龟", "旅人", "渔夫", "船长", "海风", "浪花", "月亮", "北极星", "潜水员"]
_NICK_VERB = ["干饭", "摸鱼", "躺平", "熬夜", "养生", "划水", "早睡", "加班", "追剧", "遛龟"]
_NICK_ROLE = ["第一名", "冠军", "达人", "选手", "小能手", "爱好者", "专业户", "本人"]
_NICK_SYM = ["丶", "★", "彡", "_", "·"]
_NICK_TAIL = ["", "", "", "", "666", "233", "007", "88", "1998", "呀", "啦", "酱"]


def make_namer():
    """玩家昵称生成器 —— 生成【像真人自己起的】网名, 与阵容/档位无关。

    ★这是玩家在匹配界面真会看到的字。机器人内部名"机器人07"直接上线会很出戏。
    五种真实网名套路混用, 全局去重(不是按档去重 —— 真玩家同名的概率本来就极低):
      ① 直接昵称        小明 / Kevin / 咸鱼
      ② 形容词+名词      孤独的老龟 / 退休的船长
      ③ 动词+角色        干饭第一名 / 摸鱼达人
      ④ 符号+词          丶北极星 / ★浪花
      ⑤ 任意 + 数字尾     小七666 / 潜水员233
    用 ghost_id 播种 → 同一条快照每次生成同一个名字(可复现)。
    """
    used = set()

    def gen(rng):
        t = rng.randrange(5)
        if t == 0:
            base = rng.choice(_NICK_SOLO)
        elif t == 1:
            base = rng.choice(_NICK_ADJ) + rng.choice(_NICK_NOUN)
        elif t == 2:
            base = rng.choice(_NICK_VERB) + rng.choice(_NICK_ROLE)
        elif t == 3:
            base = rng.choice(_NICK_SYM) + rng.choice(_NICK_SOLO + _NICK_NOUN)
        else:
            base = rng.choice(_NICK_SOLO + _NICK_NOUN)
        return base + rng.choice(_NICK_TAIL)

    def name_for(sn, _b):
        rng = random.Random(str(sn.get("ghost_id", "")))
        for _try in range(200):
            cand = gen(rng)
            if cand not in used:
                used.add(cand)
                return cand
        cand = "%s%d" % (gen(rng), len(used))      # 兜底: 素材撞完了才挂序号
        used.add(cand)
        return cand
    return name_for


def select(cands):
    """每档挑一批: 先按"每只机器人各出一条"轮转, 保证阵容散开; 不够再放宽到 SAME_BOT_CAP。"""
    by_bot = collections.OrderedDict()
    for sn in cands:
        by_bot.setdefault(sn.get("_bot_key") or (sn.get("profile") or {}).get("id", "?"), []).append(sn)
    picked = []
    for rnd in range(SAME_BOT_CAP):
        for _bot, lst in by_bot.items():
            if rnd < len(lst) and len(picked) < PER_BRACKET:
                picked.append(lst[rnd])
        if len(picked) >= PER_BRACKET:
            break
    return picked


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--snapshots", nargs="*", default=None,
                    help="一个或多个 cohort-snapshots.json; 不给则自动搜 tools/autoplay/**/cohort-snapshots.json")
    args = ap.parse_args()

    # ★支持合并多个队列(5 并行跑出 5 份)。不给路径就自动全搜, 免得漏掉某一份还不自知。
    paths = args.snapshots
    if not paths:
        base = os.path.join(ROOT, "tools", "autoplay")
        paths = []
        for dirpath, _dirs, files in os.walk(base):
            if os.path.basename(dirpath).startswith("_"):
                continue          # ★跳过 _oldrules 之类的归档目录: 旧规则数据混进来会污染整池
            if "cohort-snapshots.json" in files:
                paths.append(os.path.join(dirpath, "cohort-snapshots.json"))
        paths.sort()
    if not paths:
        print("★一份快照都没找到 —— 先跑 tests/_cohort.gd")
        return 1

    raw = {"brackets": {}}
    seen_ids = set()
    for pth in paths:
        if not os.path.exists(pth):
            print("★找不到 %s" % pth)
            return 1
        one = json.load(open(pth, encoding="utf-8"))
        cnt = 0
        # ghost_id 形如 coh_<botid>_b<场次>, 跨队列会重名 → 用【来源目录】做前缀隔离,
        # 否则 5 份合并后 pool_add 的去重会把不同队列的同名快照互相顶掉。
        tag = os.path.basename(os.path.dirname(pth))
        for bk, lst in (one.get("brackets") or {}).items():
            for sn in lst:
                # ★必须以 seed_ 开头: Backend._ensure_seeded 靠这个前缀识别种子 ——
                #   ①判断池里有没有种子 ②升 SEED_VER 时清旧种子(玩家真 ghost 保留)。
                #   不带前缀会导致每次读池重复并入, 且将来永远清不掉(被当成玩家 ghost 累积)。
                gid = "seed_%s_%s" % (tag, sn.get("ghost_id", ""))
                if gid in seen_ids:
                    continue
                seen_ids.add(gid)
                sn["ghost_id"] = gid
                # ★_bot_key = 跨队列唯一的【机器人】标识(不是快照标识)。
                #   select() 的"每只机器人先各出一条"轮转按它分组; 若拿逐条唯一的 id 分组,
                #   轮转就退化成"顺序取前20条", 同一只机器人会霸占一整档。
                sn["_bot_key"] = "%s/%s" % (tag, (sn.get("profile") or {}).get("id", "?"))
                raw["brackets"].setdefault(bk, []).append(sn)
                cnt += 1
        print("  载入 %-52s %5d 条" % (os.path.relpath(pth, ROOT), cnt))
    eqs = json.load(open(EQUIP_PATH, encoding="utf-8"))
    by_cost = {str(e["id"]): int(e.get("cost", 1)) for e in eqs}
    old = json.load(open(SEED_PATH, encoding="utf-8"))

    print("=== 候选快照(队列产出) ===")
    total = 0
    for bk in sorted(raw.get("brackets", {}), key=int):
        total += len(raw["brackets"][bk])
    print("  共 %d 条, 覆盖档 %s" % (total, ",".join(sorted(raw.get("brackets", {}), key=int))))
    if total == 0:
        print("★分母为 0 —— 队列没产出任何快照, 停。")
        return 1

    # ★按【当前】断点重新分桶 —— 快照文件里的 bracket 键是跑的时候那套断点写的。
    #   2026-07-27 队列跑到一半用户改了断点(微调B: 档7=22场/档8=28场), 不必重跑:
    #   档位只是从 season_total_battles 派生的标签, 原始数据没变。
    rebucket = collections.defaultdict(list)
    for bk in raw["brackets"]:
        for sn in raw["brackets"][bk]:
            nb = bracket_of(sn)
            # ★同时改写 bracket【字段】—— 不只是换桶键。Backend.pool_add 是按这个字段分桶的,
            #   字段留着旧断点的值会让快照在运行时落进错档(实测重分桶后有 80 条字段与桶键不符)。
            sn["bracket"] = nb
            rebucket[str(nb)].append(sn)
    moved = sum(1 for bk in raw["brackets"] for sn in raw["brackets"][bk] if str(bracket_of(sn)) != str(bk))
    print("  按当前断点重新分桶: %d/%d 条改了档位" % (moved, total))
    print("  重分桶后各档候选: %s" % {k: len(v) for k, v in sorted(rebucket.items(), key=lambda x: int(x[0]))})

    namer = make_namer()
    new_brackets = {}
    for bk in sorted(rebucket, key=int):
        picked = select(rebucket[bk])
        for sn in picked:
            sn.setdefault("profile", {})["name"] = namer(sn, int(bk))   # 机器人07 → 像真人的网名
            sn["profile"]["avatar"] = str((sn.get("leaders") or ["basic"])[0])
        new_brackets[bk] = picked

    # ── 对照表 ──
    print()
    print("档  旧池                                          新池(队列真实快照)")
    print("    队数 队均强度 单件均 组合数 费用分布            队数 队均强度 单件均 组合数 费用分布")
    for b in range(0, 9):
        bk = str(b)
        o = profile(old.get("brackets", {}).get(bk, []), by_cost)
        n = profile(new_brackets.get(bk, []), by_cost)
        print("%2d  %4d %8.1f %6.2f %6d %-18s  %4d %8.1f %6.2f %6d %-18s" % (
            b, o["teams"], o["team_strength"], o["per_item"], o["combos"], str(o["costs"]),
            n["teams"], n["team_strength"], n["per_item"], n["combos"], str(n["costs"])))

    # ── 自检 ──
    print()
    print("=== 自检 (与 verify_bracket_gear 同口径; 不过关拒写) ===")
    fail = 0

    t0 = new_brackets.get("0", [])
    t0_items = sum(len(items_of(t)) for t in t0)
    ok = (t0_items == 0)
    print("  %s ①档0 完全无装备: %d 支队 / %d 件 (必须 0)" % ("✔" if ok else "★", len(t0), t0_items))
    if not ok:
        fail += 1
        print("     → 档0 出现装备说明上游错了(bracket_for_battles 或快照时机), 不要在这里过滤掩盖")

    # ② 装备容量统一规则(2026-07-27): 单只≤UNIT_EQUIP_CAP 且 全队合计≤team_equip_cap(该快照赛季等级)
    bad_cap = []
    for bk, teams in new_brackets.items():
        for t in teams:
            lv = int(t.get("season_level", 0)) or (2 + int(bk))
            tcap = team_equip_cap(lv)
            used = 0
            for pid, arr in (t.get("equipped") or {}).items():
                used += len(arr)
                if len(arr) > UNIT_EQUIP_CAP:
                    bad_cap.append("档%s %s %d件>单只上限%d" % (bk, pid, len(arr), UNIT_EQUIP_CAP))
            for _lk, marr in (t.get("minions") or {}).items():
                for m in marr:
                    e = m.get("equips") or []
                    used += len(e)
                    if len(e) > UNIT_EQUIP_CAP:
                        bad_cap.append("档%s 小将 %d件>单只上限%d" % (bk, len(e), UNIT_EQUIP_CAP))
            if used > tcap:
                bad_cap.append("档%s 全队 %d件>上限%d (Lv%d)" % (bk, used, tcap, lv))
    print("  %s ②装备容量(单只≤%d 且 全队≤team_equip_cap): %d 处违规" % (
        "✔" if not bad_cap else "★", UNIT_EQUIP_CAP, len(bad_cap)))
    if bad_cap:
        fail += 1
        print("     " + "; ".join(bad_cap[:4]))

    prev = 0.0
    mono_bad = []
    for b in range(0, 9):
        p = profile(new_brackets.get(str(b), []), by_cost)
        if p["per_item"] > 0:
            if p["per_item"] <= prev:
                mono_bad.append(b)
            prev = p["per_item"]
    print("  %s ③单件均强度逐档单调递增: %s" % ("✔" if not mono_bad else "★",
                                        "通过" if not mono_bad else "档 %s 未高于上一档" % mono_bad))
    if mono_bad:
        fail += 1

    thin = [b for b in range(0, 9) if 0 < len(new_brackets.get(str(b), [])) < MIN_PER_BRACKET]
    empty = [b for b in range(0, 9) if not new_brackets.get(str(b))]
    if empty:
        print("  ★④档 %s 一条快照都没有 —— 没有机器人活到那么远。" % empty)
        print("     这不是工具的问题, 是【现行规则下那几档没有人】。要么砍档位, 要么改命数/淘汰规则。")
        print("     绝不用推测数据填充(那就退回旧池那种「造出来的假快照」了)。")
    if thin:
        print("  ⚠ 档 %s 候选不足 %d 条 —— 池子里会总撞同几支, 建议加机器人数或轮数再跑。" % (thin, MIN_PER_BRACKET))

    # ⑤ 排行榜字段: 用户 2026-07-27「排行榜先不管」→ 保持 0, 但【明写出来】不静默降级
    eggs = [int(t.get("season_eggs_killed", 0)) for teams in new_brackets.values() for t in teams]
    if eggs and max(eggs) == 0:
        print("  ⚠ ⑤season_eggs_killed 全为 0 (旧池是 1~27) —— 排行榜会变成一排 0。")
        print("     用户 2026-07-27 明确「排行榜先不管」→ 本次不折算。这是【已知待办】, 不是遗漏。")

    # 队名抽样(玩家真会看到的字)
    print()
    print("  队名抽样:")
    for b in range(0, 9):
        ns = [t.get("profile", {}).get("name", "?") for t in new_brackets.get(str(b), [])][:5]
        if ns:
            print("    档%d: %s" % (b, " / ".join(ns)))

    if fail:
        print()
        print("★自检未过 (%d 项) —— 拒绝写入。" % fail)
        return 1

    if not args.write:
        print()
        print("(dry-run — 加 --write 才真写 data/ghost_seed.json)")
        return 0

    for teams in new_brackets.values():          # 清掉只在转化期用的内部字段, 别写进正式数据
        for t in teams:
            t.pop("_bot_key", None)
    # 保留旧池里【玩家真 ghost 以外】的结构约定: 直接整体替换 brackets
    out = {
        "_note": (
            "ghost 种子池 v6 (2026-07-27) —— 【队列模拟产出的真实玩家快照】, 非人工配平。"
            "%d 只机器人从 0 场 8 命起步互相打, 输光即淘汰; 每场开打前存下双方当时的真实家当。"
            "装备的费用/星级混搭是背包历史的自然结果(早期便宜货合成★3, 后期贵货还是★1), "
            "不是按目标强度反推的。档0 = 人生第一把(双方全裸)。"
            "生成: tools/cohort_to_seed.py; 原料: tools/autoplay/cohort-snapshots.json。"
        ) % len(set(t.get("profile", {}).get("id", "") for teams in new_brackets.values() for t in teams)),
        "brackets": new_brackets,
    }
    json.dump(out, open(SEED_PATH, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print()
    print("已写入 %s" % SEED_PATH)
    print("★下一步必做:")
    print("   1) scripts/net/backend.gd 的 SEED_VER +1 (否则老存档不并入新种子)")
    print("   2) tests/verify_ghost_seed.gd 里硬编码的 146 支队期望值要改成 %d"
          % sum(len(v) for v in new_brackets.values()))
    print("   3) bash run-tests.sh 全套")
    return 0


if __name__ == "__main__":
    sys.exit(main())
