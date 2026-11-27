"""gen_week_pool_incense_1127.py —— 生成迁移 20261127c_week_pool_incense(香火石 / 小木斧不参与每周轮换: 服务器那份同步游戏代码)
接在 20261127_ranked_pick_week_pool 之后: 只重定义 p2eq_big_types —— 带「斧头 / 香火」类型的件(小木斧 / 香火石)不进表 ⇒ 永远可以出。
方案书 docs/plans/20261124d-16羁绊每周轮换.md R4「小木斧、香火石不算大羁绊，不参与轮换」(用户 11-24); 11-27 自查: 香火石 = 遗物 + 香火,
初版按「有大羁绊类型就轮换」把它跟着遗物轮换了(游戏代码 WeeklySynergy.ALWAYS_TYPES 同日改)。
装备类型表从 data/p2eq-types.json 取, 16 个大羁绊 / ALWAYS_TYPES 从 scripts/gamedata/weekly_synergy.gd 读 ⇒ 不手抄。重跑逐字节相同。
    python tools/oneoff/gen_week_pool_incense_1127.py
"""
import json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
NAME = "20261127c_week_pool_incense"

gd = open(os.path.join(ROOT, "scripts/gamedata/weekly_synergy.gd"), encoding="utf-8").read()
ALL = re.findall(r'"([^"]+)"', re.search(r"const ALL: Array\[String\] = \[(.*?)\]", gd, re.S).group(1))
ALWAYS = re.findall(r'"([^"]+)"', re.search(r"const ALWAYS_TYPES: Array\[String\] = \[(.*?)\]", gd, re.S).group(1))
assert len(ALL) == 16 and ALWAYS == ["斧头", "香火"], (ALL, ALWAYS)

types = json.load(open(os.path.join(ROOT, "data/p2eq-types.json"), encoding="utf-8"))
big = {}
skipped = []
for eid in sorted(types):
    v = types[eid]
    ts = v if isinstance(v, list) else [v]
    if any(t in ALWAYS for t in ts):
        skipped.append(eid)
        continue
    b = [t for t in ts if t in ALL]
    if b:
        big[eid] = b
assert "p2eq_093" in skipped and "p2eq_093" not in big
MAP = json.dumps(big, ensure_ascii=False, separators=(",", ":"))

SQL = """-- >>> BEGIN %(name)s >>>
-- ─────────────────────────────────────────────────────────────
-- 香火石 / 小木斧不参与每周轮换（2026-11-27 · 方案书 docs/plans/20261124d-16羁绊每周轮换.md R4）
--   用户 11-24「小木斧，还有香火石，这个其实都不应该…不用管，这个不属于大羁绊」⇒ R4「不参与轮换」。
--   20261127_ranked_pick_week_pool 的 p2eq_big_types 按「有大羁绊类型就轮换」生成, 香火石(遗物 + 香火)被当成遗物件
--   ⇒ 没抽到遗物的周, 带香火石的种子快照被挑对手的过滤刷掉。游戏代码同日改(WeeklySynergy.ALWAYS_TYPES = 斧头 / 香火)。
--   用户 11-27 问「这些小木斧和香火…特殊羁绊有正确的实施吗」时自查出来; 随 11-30 换版上(memory fb-release-migrations-no-extra-nod-1124)。
-- 改动: 只重定义 p2eq_big_types —— 带「斧头 / 香火」的件(%(skipped)s)不进表 ⇒ snap_week_pool_ok 永远放行它们。
--   其余函数(fnv1a32 / weekly_synergy_of / snap_week_pool_ok / referee_ranked_pick)不动。
-- 装备类型表由 tools/oneoff/gen_week_pool_incense_1127.py 从 data/p2eq-types.json 生成(%(n)d 件属于大羁绊且参与轮换)。
-- 前置: 20261127_ranked_pick_week_pool。回滚: 重新执行 schema.sql 里 20261127_ranked_pick_week_pool 段的 p2eq_big_types。
-- ─────────────────────────────────────────────────────────────

create or replace function public.p2eq_big_types(p_id text) returns text[]
language sql immutable as $fn$
  select coalesce(array(select jsonb_array_elements_text(m -> p_id)), '{}'::text[])
    from (select '%(map)s'::jsonb as m) s
$fn$;
revoke all on function public.p2eq_big_types(text) from public, anon, authenticated;
-- <<< END %(name)s <<<
""" % {"name": NAME, "skipped": " / ".join(skipped), "n": len(big), "map": MAP}

p = os.path.join(ROOT, "server/supabase/migrations/%s.sql" % NAME)
open(p, "w", encoding="utf-8", newline="\n").write(SQL)
## schema.sql: 同一段接在最后(全量建库按顺序执行时也是这个结果); 已有就原地替换 ⇒ 重跑逐字节相同
sp = os.path.join(ROOT, "server/supabase/schema.sql")
s = open(sp, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in s else "\n"
s = s.replace("\r\n", "\n")
blk = SQL.rstrip("\n") + "\n"
m = re.search(r"-- >>> BEGIN %s >>>\n.*?-- <<< END %s <<<\n" % (NAME, NAME), s, re.S)
if m:
    s = s[:m.start()] + blk + s[m.end():]
else:
    s = s.rstrip("\n") + "\n\n" + blk
open(sp, "w", encoding="utf-8", newline="").write(s.replace("\n", nl))
print("ok", p, "skipped", skipped, "big", len(big))
