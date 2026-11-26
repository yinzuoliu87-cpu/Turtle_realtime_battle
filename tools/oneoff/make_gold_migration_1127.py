"""make_gold_migration_1127.py —— 由 20261125_ritual_marks.sql 派生 20261127b_gold_mask_stacks.sql(+ 同名 _check.sql), 并追加进 schema.sql

135 黄金面具层数「跨对局保留、只记在这一件上」(方案书 20261125c §5; 用户 11-27「直接做就好了呀」):
  ① 回包: 裁判结果单带 gold_new / gold_new_b = {"<龟 id>|<份号>": 这一局这件新涨的层数}(对象); referee_job_status / referee_finals_coins
     按视角回 gold_new。以 20261125 版为底逐字照抄, 每处 ritual_new 后面接一处 gold_new(对象, 不是数)。
  ② 封顶: econ_gold_sum(账号) = 这个号【全部周】已算完的周赛局里自己的 gold_new 合计(层数永久保留; 单件单局按 50 夹);
     触发器 econ_gold_stamp_on_claim 在任务变成 claimed 时(econ_on 开着)盖 a_gold / b_gold, 裁判(referee_job.gd gold_cap)给快照自报的封顶。
确定性: 纯文本替换, 重跑逐字节相同。行尾跟 schema.sql 检出的那一种(make_ritual_migration_1125 注)。

    python tools/oneoff/make_gold_migration_1127.py
"""
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MIG = os.path.join(ROOT, "server", "supabase", "migrations")
SRC = os.path.join(MIG, "20261125_ritual_marks.sql")
NAME = "20261127b_gold_mask_stacks"
DST = os.path.join(MIG, NAME + ".sql")
SCHEMA = os.path.join(ROOT, "server", "supabase", "schema.sql")
BEGIN = "-- >>> BEGIN gold_mask_stacks 20261127b >>>"
END = "-- <<< END gold_mask_stacks 20261127b <<<"

HEAD = BEGIN + """
-- ─────────────────────────────────────────────────────────────
-- 135 黄金面具层数跨对局保留、只记在这一件上（2026-11-27 · 方案书 docs/plans/20261125c-面具羁绊.md §5）
--   用户 11-26「合成…层数是保留下来的」; 11-27「直接做就好了呀」⇒ 随 11-30 换版上。
--   照仪式匕首【血契】（20261125_ritual_marks）做一遍, 不同处: 层数按件记 ⇒ 结果单是对象 {"<龟 id>|<份号>": 这一局新涨的层数};
--   层数永久保留(不随大轮清) ⇒ 封顶求和不限周。
--   ① 回包：referee_job_status / referee_finals_coins 按视角回 gold_new（A 取 gold_new、B 取 gold_new_b）；以 20261125 版为底逐字照抄，
--      只加标了 2026-11-27 的几行；结果单没这个键 / 不是对象 ⇒ 回包一个键都不多。
--   ② 记账封顶：econ_gold_sum(账号) = 全部周已算完的周赛局里这个号自己的 gold_new 合计（单件单局按 50 夹）；
--      触发器 econ_gold_stamp_on_claim 在任务变成 claimed 时（econ_on 开着）把 a_gold / b_gold 盖进 meta，
--      裁判（referee_job.gd gold_cap）把快照里黄金面具层数合计压到不超过它。
--   回滚：drop trigger econ_gold_stamp_on_claim on public.referee_jobs；两个回包函数重跑 20261125_ritual_marks。
-- ★重复执行安全（create or replace / drop trigger if exists）。
-- ─────────────────────────────────────────────────────────────
"""

TAIL = """create or replace function public.econ_gold_sum(p_uid uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(least(greatest(floor(v.val::numeric), 0), 50)), 0)
    from public.referee_jobs j
    cross join lateral (select case when j.a_account = p_uid then 'gold_new' else 'gold_new_b' end as k) t
    cross join lateral jsonb_each_text(case when jsonb_typeof(j.result -> t.k) = 'object' then j.result -> t.k else '{}'::jsonb end) v(key, val)
   where p_uid is not null and j.status = 'done' and j.result is not null
     and j.kind in ('ranked', 'gauntlet', 'finals')
     and (j.a_account = p_uid or (j.b_account = p_uid and (j.kind = 'finals' or j.meta ->> 'pair' = 'true')))
     and v.val ~ '^[0-9]+([.][0-9]+)?$'
$$;
revoke all on function public.econ_gold_sum(uuid) from public, anon, authenticated;

create or replace function public.econ_gold_stamp_on_claim() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.referee_econ_on() then
    new.meta := coalesce(new.meta, '{}'::jsonb) - 'a_gold' - 'b_gold';
    if new.a_account is not null then
      new.meta := new.meta || jsonb_build_object('a_gold', public.econ_gold_sum(new.a_account));
    end if;
    if new.b_account is not null then
      new.meta := new.meta || jsonb_build_object('b_gold', public.econ_gold_sum(new.b_account));
    end if;
  end if;
  return new;
end $$;
revoke all on function public.econ_gold_stamp_on_claim() from public, anon, authenticated;
drop trigger if exists econ_gold_stamp_on_claim on public.referee_jobs;
create trigger econ_gold_stamp_on_claim before update of status on public.referee_jobs
  for each row when (new.status = 'claimed') execute function public.econ_gold_stamp_on_claim();
"""


def rep(s, a, b, n=1):
    assert s.count(a) == n, (s.count(a), a[:80])
    return s.replace(a, b)


def build() -> str:
    s = io.open(SRC, encoding="utf-8", newline="").read().replace("\r\n", "\n")
    a = s.index("create or replace function public.referee_job_status")
    b = s.index("create or replace function public.econ_ritual_sum")
    body = s[a:b]
    body = rep(body,
        """      || case when j.status = 'done' and jsonb_typeof(j.result->'ritual_new_b') = 'number'
              then jsonb_build_object('ritual_new', j.result->'ritual_new_b') else '{}'::jsonb end;""",
        """      || case when j.status = 'done' and jsonb_typeof(j.result->'ritual_new_b') = 'number'
              then jsonb_build_object('ritual_new', j.result->'ritual_new_b') else '{}'::jsonb end
      -- ★2026-11-27 B 方黄金面具这一局每件新涨的层数
      || case when j.status = 'done' and jsonb_typeof(j.result->'gold_new_b') = 'object'
              then jsonb_build_object('gold_new', j.result->'gold_new_b') else '{}'::jsonb end;""")
    body = rep(body,
        """    || case when j.status = 'done' and jsonb_typeof(j.result->'ritual_new') = 'number'
            then jsonb_build_object('ritual_new', j.result->'ritual_new') else '{}'::jsonb end
""",
        """    || case when j.status = 'done' and jsonb_typeof(j.result->'ritual_new') = 'number'
            then jsonb_build_object('ritual_new', j.result->'ritual_new') else '{}'::jsonb end
    -- ★2026-11-27：这一局我方黄金面具每件新涨的层数
    || case when j.status = 'done' and jsonb_typeof(j.result->'gold_new') = 'object'
            then jsonb_build_object('gold_new', j.result->'gold_new') else '{}'::jsonb end
""")
    body = rep(body, "wn jsonb := null; bn jsonb := null; rn jsonb := null;", "wn jsonb := null; bn jsonb := null; rn jsonb := null; gn jsonb := null;")
    body = rep(body,
        """    rn := j.result->(case when j.a_account = uid then 'ritual_new' else 'ritual_new_b' end);
""",
        """    rn := j.result->(case when j.a_account = uid then 'ritual_new' else 'ritual_new_b' end);
    -- ★2026-11-27：A 取 gold_new、B 取 gold_new_b（同上）
    gn := j.result->(case when j.a_account = uid then 'gold_new' else 'gold_new_b' end);
""")
    body = rep(body,
        """    || case when jsonb_typeof(rn) = 'number' then jsonb_build_object('ritual_new', rn) else '{}'::jsonb end;""",
        """    || case when jsonb_typeof(rn) = 'number' then jsonb_build_object('ritual_new', rn) else '{}'::jsonb end
    || case when jsonb_typeof(gn) = 'object' then jsonb_build_object('gold_new', gn) else '{}'::jsonb end;""")
    assert body.count("gold_new") == 11, body.count("gold_new")
    return HEAD + body + TAIL + END + "\n"


def main():
    out = build()
    raw = io.open(SCHEMA, encoding="utf-8", newline="").read()
    eol = "\r\n" if "\r\n" in raw else "\n"
    io.open(DST, "w", encoding="utf-8", newline=eol).write(out)
    sc = raw.replace("\r\n", "\n")
    if BEGIN in sc:
        sc = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n", lambda m: out, sc, flags=re.S)
    else:
        sc = sc.rstrip("\n") + "\n\n" + out
    io.open(SCHEMA, "w", encoding="utf-8", newline=eol).write(sc)
    ## 20261127(本周池那份)当初按 LF 写的, 行尾跟 schema 对齐(sha256 按 LF 算, 账本不变)
    p27 = os.path.join(MIG, "20261127_ranked_pick_week_pool.sql")
    t27 = io.open(p27, encoding="utf-8", newline="").read().replace("\r\n", "\n")
    io.open(p27, "w", encoding="utf-8", newline=eol).write(t27)
    print("写 %s(%d 行)并同步进 schema.sql; 20261127 行尾对齐" % (os.path.basename(DST), out.count("\n")))


if __name__ == "__main__":
    main()
