-- >>> BEGIN econ_flag 20261106b >>>
-- ─────────────────────────────────────────────────────────────
-- 局外经济记账的总开关 econ_on（2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.6 · S3）
--   同 ranked_on 的做法：开关默认关 ⇒ 执行本段不改变任何现行行为。客户端见 referee_flags().econ_on 开着，
--   掷货 / 刷新 / 开糖果罐才向服务器要种子（econ_commit）、流水才往上传；关着 ⇒ 本机种子、不上传（与 0.22.8 一字不差）。
--   方案书 §4.6：在周一换周时打开（那一刻所有人清零，正好是重放起点）；内测服先开一整周对账（S5），正式服开要用户点头。
-- 本段：① referee_config 多一列 econ_on（默认 false）② referee_econ_on() ③ referee_flags() 多回 econ_on（其余五项原样）
-- ─────────────────────────────────────────────────────────────
alter table public.referee_config add column if not exists econ_on boolean not null default false;

create or replace function public.referee_econ_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select econ_on from public.referee_config where id = 1), false)
$$;
revoke all on function public.referee_econ_on() from public, anon, authenticated;

create or replace function public.referee_flags()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('finals_on', public.referee_finals_on(),
                            'gauntlet_on', public.referee_gauntlet_on(),
                            'stream_on', coalesce((select c.stream_on from public.referee_config c where c.id = 1), false),
                            'stream_version', coalesce((select c.stream_version from public.referee_config c where c.id = 1), ''),
                            'ranked_on', public.referee_ranked_on(),
                            'econ_on', public.referee_econ_on())
$$;
revoke all on function public.referee_flags() from public;
grant execute on function public.referee_flags() to anon, authenticated;
-- <<< END econ_flag 20261106b <<<
