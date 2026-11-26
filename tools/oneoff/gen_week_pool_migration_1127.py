"""gen_week_pool_migration_1127.py —— 生成迁移 20261127_ranked_pick_week_pool(积分赛种子 / 机器人对手按本周羁绊池过滤; 方案书 20261124d U3)
装备 → 羁绊类型表直接从 data/p2eq-types.json 取, 16 个大羁绊 / 上线周常量从 scripts/gamedata/weekly_synergy.gd 读 ⇒ 不手抄。
迁移落地后是定稿(不再改); 以后装备 / 羁绊变了另出新迁移。重跑逐字节相同。
    python tools/oneoff/gen_week_pool_migration_1127.py
"""
import json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
NAME = "20261127_ranked_pick_week_pool"

gd = open(os.path.join(ROOT, "scripts/gamedata/weekly_synergy.gd"), encoding="utf-8").read()
ALL = re.findall(r'"([^"]+)"', re.search(r"const ALL: Array\[String\] = \[(.*?)\]", gd, re.S).group(1))
NEW = re.findall(r'"([^"]+)"', re.search(r"const LAUNCH_NEW: Array\[String\] = \[(.*?)\]", gd, re.S).group(1))
LAUNCH = int(re.search(r"const LAUNCH_WEEK := (\d+)", gd).group(1))
COUNT = int(re.search(r"const COUNT := (\d+)", gd).group(1))
assert len(ALL) == 16 and len(NEW) == 6 and COUNT == 10

types = json.load(open(os.path.join(ROOT, "data/p2eq-types.json"), encoding="utf-8"))
big = {}
for eid in sorted(types):
    v = types[eid]
    ts = v if isinstance(v, list) else [v]
    b = [t for t in ts if t in ALL]
    if b:
        big[eid] = b
MAP = json.dumps(big, ensure_ascii=False, separators=(",", ":"))


def arr(xs):
    return "array[" + ", ".join("'%s'" % x for x in xs) + "]::text[]"


SQL = """-- >>> BEGIN %(name)s >>>
-- ─────────────────────────────────────────────────────────────
-- 积分赛挑对手: 种子 / 机器人快照按「本周羁绊池」过滤（2026-11-27 · 方案书 docs/plans/20261124d-16羁绊每周轮换.md U3）
--   用户 11-24「垫底的种子对手，如果带着本周商店购不到装备…你得想办法处理一下」→ U3 交我处理: 只挑装备全在本周池里的种子;
--   一份都没有 ⇒ 机器人, 机器人里也优先挑装备全在本周池里的(没有才退回任意一份, 不让人匹配不到)。
--   用户 11-27「直接做就好了呀」⇒ 随 11-30 换版上(正式服迁移随周一换版, memory fb-release-migrations-no-extra-nod-1124)。
-- 本周池 = scripts/gamedata/weekly_synergy.gd 同一算法: 16 个大羁绊按 FNV-1a 32 位("周锚点|羁绊名" 的 UTF-8 字节)升序取前 10,
--   同键按名字码点(collate "C")比; 上线周 %(launch)d(2026-11-30)= 6 个新羁绊 + 老羁绊排序前 4。
--   一件装备只属于非大羁绊类型(小木斧 / 香火石 / 仪式)⇒ 永远可以出; 属于多个 ⇒ 有一个在本周就能出(同 WeeklySynergy.pool_ok)。
-- 快照里所有装备都是 {id, star}(已穿 equipped / 援军 reserve_pool / 小将) ⇒ 递归取全部 id 里以 p2eq_ 开头的。
-- 真人 / 陪练账号快照不过滤(他们这一周真打过、装备是自己背包里的, 可能是之前周买的)。
-- 改动: 新增 4 个函数(p2eq_big_types / fnv1a32 / weekly_synergy_of / snap_week_pool_ok); referee_ranked_pick 种子一支加过滤、
--   机器人一支排序加「本周池里的在前」, 其余逐字照 20261124b。不改表、不改签名、不改权限。重复执行安全。
-- 装备类型表由 tools/oneoff/gen_week_pool_migration_1127.py 从 data/p2eq-types.json 生成(%(n)d 件属于大羁绊)。
-- 回滚: 重新执行 schema.sql 里上一版 referee_ranked_pick(20261124b 段); 新增的 4 个函数留着无害。
-- ─────────────────────────────────────────────────────────────

create or replace function public.p2eq_big_types(p_id text) returns text[]
language sql immutable as $fn$
  select coalesce(array(select jsonb_array_elements_text(m -> p_id)), '{}'::text[])
    from (select '%(map)s'::jsonb as m) s
$fn$;
revoke all on function public.p2eq_big_types(text) from public, anon, authenticated;

create or replace function public.fnv1a32(p text) returns bigint
language plpgsql immutable as $fn$
declare h bigint := 2166136261; b bytea := convert_to(coalesce(p, ''), 'UTF8'); i int;
begin
  for i in 0 .. length(b) - 1 loop
    h := ((h # get_byte(b, i)) * 16777619) %% 4294967296;
  end loop;
  return h;
end $fn$;
revoke all on function public.fnv1a32(text) from public, anon, authenticated;

create or replace function public.weekly_synergy_of(p_week bigint) returns text[]
language plpgsql immutable as $fn$
declare allv text[] := %(all)s;
  newv text[] := %(new)s;
begin
  if p_week is null or p_week <= 0 then
    return allv;
  end if;
  if p_week = %(launch)d then
    return newv || array(select t from unnest(allv) t where not (t = any(newv))
                          order by public.fnv1a32(p_week::text || '|' || t), t collate "C" limit %(rest)d);
  end if;
  return array(select t from unnest(allv) t order by public.fnv1a32(p_week::text || '|' || t), t collate "C" limit %(count)d);
end $fn$;
revoke all on function public.weekly_synergy_of(bigint) from public, anon, authenticated;

create or replace function public.snap_week_pool_ok(p_snap jsonb, p_week bigint) returns boolean
language sql immutable as $fn$
  select not exists (
    select 1
      from jsonb_path_query(coalesce(p_snap, '{}'::jsonb), 'lax $.**.id') j(v)
     where jsonb_typeof(j.v) = 'string' and left(j.v #>> '{}', 5) = 'p2eq_'
       and cardinality(public.p2eq_big_types(j.v #>> '{}')) > 0
       and not (public.p2eq_big_types(j.v #>> '{}') && public.weekly_synergy_of(p_week)))
$fn$;
revoke all on function public.snap_week_pool_ok(jsonb, bigint) from public, anon, authenticated;

create or replace function public.referee_ranked_pick(p_uid uuid, p_week bigint, p_battles int, p_rules_ver int,
    p_ex text[])
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare c record; bp record; bk int; snap jsonb;
begin
  select * into c from (
    select format('acct:%%s:b%%s', g.account_id, g.battles) as opp, g.account_id as account, g.snapshot as snap, 'human' as pick
      from public.ghosts g
     where g.season_week = p_week and g.battles = p_battles and g.rules_ver = p_rules_ver
       and g.account_id <> p_uid and public.referee_ranked_ghost_ok(g.snapshot, p_battles)
    union all
    select format('seed:%%s:%%s:%%s', p.rules_ver, p.battles, p.variant), null::uuid, p.snapshot, 'seed'
      from public.ranked_pool p
     where p.rules_ver = p_rules_ver and p.kind = 'seed' and p.battles = p_battles
       and public.referee_lanes_ok(p.snapshot)
       and jsonb_typeof(p.snapshot -> 'season_total_battles') = 'number'
       and (p.snapshot ->> 'season_total_battles')::numeric = p_battles
       and public.snap_week_pool_ok(p.snapshot, p_week)   -- 20261127: 种子只挑装备全在本周池里的
  ) cand
  where not (cand.opp = any(coalesce(p_ex, '{}')))
  order by (cand.pick = 'seed'), random()   -- 20261124b: 真人 / 陪练账号在前, 种子只垫底(同一类里仍等概率)
  limit 1;
  if found then
    return jsonb_build_object('snap', c.snap - 'origin', 'opp', c.opp, 'pick', c.pick)
      || case when c.account is not null then jsonb_build_object('account', c.account) else '{}'::jsonb end;
  end if;
  select max(battles) into bk from public.ranked_pool where rules_ver = p_rules_ver and kind = 'bot';
  if bk is null then
    return null;
  end if;
  bk := least(greatest(coalesce(p_battles, 0), 0), bk);
  select p.* into bp from public.ranked_pool p
   where p.rules_ver = p_rules_ver and p.kind = 'bot' and p.battles = bk
   order by (format('bot:%%s:%%s:%%s', p.rules_ver, p.battles, p.variant) = any(coalesce(p_ex, '{}'))),
            (not public.snap_week_pool_ok(p.snapshot, p_week)),   -- 20261127: 本周池里的机器人在前(没有才退回任意一份)
            random()
   limit 1;
  if not found then
    return null;
  end if;
  snap := bp.snapshot - 'origin';
  if coalesce(p_battles, 0) > bk then
    snap := jsonb_set(snap, '{season_total_battles}', to_jsonb(p_battles));   -- 场次标签与玩家相同（用户 10-04「场次一定要相同」）
  end if;
  return jsonb_build_object('snap', snap, 'opp', format('bot:%%s:%%s:%%s', bp.rules_ver, bp.battles, bp.variant), 'pick', 'bot');
end $$;
revoke all on function public.referee_ranked_pick(uuid, bigint, int, int, text[]) from public, anon, authenticated;
-- <<< END %(name)s <<<
""" % {"name": NAME, "launch": LAUNCH, "n": len(big), "map": MAP.replace("'", "''"), "all": arr(ALL), "new": arr(NEW),
       "rest": COUNT - len(NEW), "count": COUNT}

p = os.path.join(ROOT, "server/supabase/migrations", NAME + ".sql")
open(p, "w", encoding="utf-8", newline="\n").write(SQL)
print("写入", p, len(SQL), "字节;", len(big), "件属于大羁绊")
