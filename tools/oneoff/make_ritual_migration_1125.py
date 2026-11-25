"""make_ritual_migration_1125.py —— 由 20261119_bamboo_growth.sql 派生 20261125_ritual_marks.sql(+ 同名 _check.sql), 并追加进 schema.sql

做法: 两个回包函数(referee_job_status / referee_finals_coins)以竹叶龟那一版为底逐字照抄, 在每处 bamboo_new 后面加一处 ritual_new;
  封顶求和函数 / 领活触发器照竹叶龟那一对另起一对(econ_ritual_sum / econ_ritual_stamp_on_claim), 不动竹叶龟那一对。
确定性: 纯文本替换, 重跑逐字节相同。

    python tools/oneoff/make_ritual_migration_1125.py
"""
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MIG = os.path.join(ROOT, "server", "supabase", "migrations")
SRC = os.path.join(MIG, "20261119_bamboo_growth.sql")
DST = os.path.join(MIG, "20261125_ritual_marks.sql")
SCHEMA = os.path.join(ROOT, "server", "supabase", "schema.sql")

HEAD = """-- >>> BEGIN ritual_marks 20261125 >>>
-- ─────────────────────────────────────────────────────────────
-- 114 仪式匕首【血契】一大轮内跨场累积（2026-11-25 · 方案书 docs/plans/20261125-匕首羁绊.md §4.2c）
--   用户 11-24「仪式匕首可能要做一个专属的羁绊，就是类似于香火石一样…一个大轮去叠加」。
--   照竹叶龟【生长】（20261119_bamboo_growth）原样做一遍，口径是「这一局新刻了几道」（整数，增量）：
--   ① 回包：裁判结果单 0.23.7 起带 ritual_new / ritual_new_b（这一局双方各新刻了几道血契）；
--      referee_job_status / referee_finals_coins 回给客户端（按视角换好）。以 20261119 版为底逐字照抄，只加标了 2026-11-25 的几行；
--      结果单没这个键（老裁判）⇒ 回包一个键都不多。
--   ② 记账封顶：econ_ritual_sum(账号, 周) = 本周已算完的周赛局里这个号自己刻的合计（口径同 econ_bamboo_sum）；
--      触发器 econ_ritual_stamp_on_claim 在任务变成 claimed 时（econ_on 开着）把 a_ritual / b_ritual 盖进 meta，
--      裁判（referee_job.gd state_for · ritual_cap）给快照自报的封顶。
--   回滚：drop trigger econ_ritual_stamp_on_claim on public.referee_jobs；两个回包函数重跑 20261119_bamboo_growth。
-- ★重复执行安全（create or replace / drop trigger if exists）。
-- ─────────────────────────────────────────────────────────────
"""


def build() -> str:
    s = io.open(SRC, encoding="utf-8", newline="").read().replace("\r\n", "\n")
    a = s.index("create or replace function public.referee_job_status")
    b = s.index("create or replace function public.econ_bamboo_sum")
    body = s[a:b]
    ## ① 回包里每一处 bamboo_new 之后接一处 ritual_new(同形)
    body = body.replace(
        """      || case when j.status = 'done' and jsonb_typeof(j.result->'bamboo_new_b') = 'number'
              then jsonb_build_object('bamboo_new', j.result->'bamboo_new_b') else '{}'::jsonb end;""",
        """      || case when j.status = 'done' and jsonb_typeof(j.result->'bamboo_new_b') = 'number'
              then jsonb_build_object('bamboo_new', j.result->'bamboo_new_b') else '{}'::jsonb end
      -- ★2026-11-25 B 方仪式匕首这一局新刻的血契
      || case when j.status = 'done' and jsonb_typeof(j.result->'ritual_new_b') = 'number'
              then jsonb_build_object('ritual_new', j.result->'ritual_new_b') else '{}'::jsonb end;""")
    body = body.replace(
        """    || case when j.status = 'done' and jsonb_typeof(j.result->'bamboo_new') = 'number'
            then jsonb_build_object('bamboo_new', j.result->'bamboo_new') else '{}'::jsonb end
""",
        """    || case when j.status = 'done' and jsonb_typeof(j.result->'bamboo_new') = 'number'
            then jsonb_build_object('bamboo_new', j.result->'bamboo_new') else '{}'::jsonb end
    -- ★2026-11-25：这一局我方仪式匕首新刻的血契
    || case when j.status = 'done' and jsonb_typeof(j.result->'ritual_new') = 'number'
            then jsonb_build_object('ritual_new', j.result->'ritual_new') else '{}'::jsonb end
""")
    body = body.replace("wn jsonb := null; bn jsonb := null;", "wn jsonb := null; bn jsonb := null; rn jsonb := null;")
    body = body.replace(
        """    bn := j.result->(case when j.a_account = uid then 'bamboo_new' else 'bamboo_new_b' end);
""",
        """    bn := j.result->(case when j.a_account = uid then 'bamboo_new' else 'bamboo_new_b' end);
    -- ★2026-11-25：A 取 ritual_new、B 取 ritual_new_b（同上）
    rn := j.result->(case when j.a_account = uid then 'ritual_new' else 'ritual_new_b' end);
""")
    body = body.replace(
        """    || case when jsonb_typeof(bn) = 'number' then jsonb_build_object('bamboo_new', bn) else '{}'::jsonb end;""",
        """    || case when jsonb_typeof(bn) = 'number' then jsonb_build_object('bamboo_new', bn) else '{}'::jsonb end
    || case when jsonb_typeof(rn) = 'number' then jsonb_build_object('ritual_new', rn) else '{}'::jsonb end;""")
    assert body.count("ritual_new") == 11, body.count("ritual_new")
    ## ② 封顶求和 + 领活触发器(另起一对)
    tail = s[b:s.index("-- <<< END bamboo_growth")]
    tail = tail.replace("econ_bamboo_sum", "econ_ritual_sum").replace("econ_bamboo_stamp_on_claim", "econ_ritual_stamp_on_claim")
    tail = tail.replace("'bamboo_new_b'", "'ritual_new_b'").replace("'bamboo_new'", "'ritual_new'")
    tail = tail.replace("'a_bamboo'", "'a_ritual'").replace("'b_bamboo'", "'b_ritual'")
    ## 血契是整数道数、单局上限 150(RITUAL_CAP): 求和按整数夹
    tail = tail.replace("coalesce(round(sum(least(greatest((j.result ->> t.k)::numeric, 0), 100000)), 2), 0)",
                        "coalesce(sum(least(greatest(floor((j.result ->> t.k)::numeric), 0), 150)), 0)")
    assert "bamboo" not in tail, tail
    return HEAD + body + tail + "-- <<< END ritual_marks 20261125 <<<\n"


def main():
    out = build()
    ## ★行尾跟 schema.sql 检出的那一种(Windows autocrlf ⇒ CRLF; 入库统一 LF); 混了 verify_stream_referee_paths 会红(11-25 实测)
    raw = io.open(SCHEMA, encoding="utf-8", newline="").read()
    eol = "\r\n" if "\r\n" in raw else "\n"
    io.open(DST, "w", encoding="utf-8", newline=eol).write(out)
    sc = raw.replace("\r\n", "\n")
    if "-- >>> BEGIN ritual_marks 20261125 >>>" in sc:
        sc = re.sub(r"-- >>> BEGIN ritual_marks 20261125 >>>.*?-- <<< END ritual_marks 20261125 <<<\n", lambda m: out, sc, flags=re.S)
    else:
        sc = sc.rstrip("\n") + "\n\n" + out
    io.open(SCHEMA, "w", encoding="utf-8", newline=eol).write(sc)
    print("写 %s(%d 行)并同步进 schema.sql" % (os.path.basename(DST), out.count("\n")))


if __name__ == "__main__":
    main()
