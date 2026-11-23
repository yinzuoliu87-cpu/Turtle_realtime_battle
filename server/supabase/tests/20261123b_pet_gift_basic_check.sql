-- 20261123b 每个号永久拥有 basic —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261123b_pet_gift_basic
-- 判据：
--   G1 赠送名单 = {basic}，且在 28 只里
--   O1 ★绑了主站（stone / lava）⇒ basic, lava, stone（按名字排、去重）
--   O2 ★没绑主站 ⇒ 只有 basic；主站上本来就有 basic ⇒ 不重复
--   O3 没有账号（机器人池）⇒ 空（与改之前相同）
--   S1 ★领活盖章：a_owned / b_owned 都带 basic
--   L1 ★开算等级表：basic 按服务器等级（以前固定 1 级）
--   X1 ★发经验：basic 涨经验、升级
--   X2 ★升级通知主站：主站上真拥有的才推（a 的 stone 推、a 的 basic 不推；c 主站上有 basic ⇒ 推）—— 靠 mainsite_outbox_put 自己挡
--   X3 没绑主站的号 basic 升级 ⇒ 不推（本来就没有主站用户）
--   X4 限免龟（不在拥有里）照旧不发
--   P1 权限：pet_gift_ids / pet_owned 客户端调不了
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) values ('a'), ('b'), ('c'), ('d');
grant select on _u to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k text) returns uuid language sql as $$ select id from _u where k = p_k $$;
create or replace function pg_temp.snap(p_l text[]) returns jsonb language sql as $$
  select jsonb_build_object('leaders', to_jsonb(p_l), 'lane_assign', jsonb_build_object('top', to_jsonb(p_l[1:2]), 'bottom', to_jsonb(p_l[3:3]))) $$;
create or replace function pg_temp.lv(p_k text, p_pet text) returns int language sql as $$
  select level from public.pet_levels where account_id = pg_temp.u(p_k) and pet_key = p_pet $$;
create or replace function pg_temp.outbox_n(p_uid text, p_pet text) returns int language sql as $$
  select count(*)::int from public.mainsite_outbox where topic = 'pet-level' and body ->> 'petKey' = p_pet and body ->> 'userId' = p_uid $$;

insert into auth.users (id, aud, role, is_anonymous, created_at) select id, 'authenticated', 'authenticated', true, now() from _u;
insert into public.accounts (account_id) select id from _u;
-- a 绑定、主站拥有 stone / lava；b 绑定、主站拥有 bamboo；c 绑定、主站拥有 basic；d 没绑定
insert into public.mainsite_accounts (account_id, mainsite_user_id)
  values (pg_temp.u('a'), 'GiftTestA'), (pg_temp.u('b'), 'GiftTestB'), (pg_temp.u('c'), 'GiftTestC');
insert into public.mainsite_pets (account_id, pet_key, fetched_at)
  values (pg_temp.u('a'), 'stone', now()), (pg_temp.u('a'), 'lava', now()),
         (pg_temp.u('b'), 'bamboo', now()), (pg_temp.u('c'), 'basic', now());
-- 差 5 点到 2 级（70）：赢一局 +8 ⇒ 升 2 级
insert into public.pet_levels (account_id, pet_key, xp, level)
  values (pg_temp.u('a'), 'stone', 65, 1), (pg_temp.u('a'), 'basic', 65, 1), (pg_temp.u('c'), 'basic', 65, 1),
         (pg_temp.u('d'), 'basic', 300, 4);
insert into public.referee_versions (client_version, enabled) values ('tv-g', true) on conflict do nothing;

select pg_temp.ck('G1 赠送名单 = {basic}，且在 28 只里',
  public.pet_gift_ids() = array['basic'] and public.pet_gift_ids() <@ public.pet_all_ids(), public.pet_gift_ids()::text);
select pg_temp.ck('O1 ★绑了主站(stone/lava) ⇒ basic, lava, stone',
  public.pet_owned(pg_temp.u('a')) = array['basic', 'lava', 'stone'], public.pet_owned(pg_temp.u('a'))::text);
select pg_temp.ck('O2 ★没绑主站 ⇒ 只有 basic；主站上本来就有 basic ⇒ 不重复',
  public.pet_owned(pg_temp.u('d')) = array['basic'] and public.pet_owned(pg_temp.u('c')) = array['basic'],
  public.pet_owned(pg_temp.u('d'))::text || ' / ' || public.pet_owned(pg_temp.u('c'))::text);
select pg_temp.ck('O3 没有账号(机器人池) ⇒ 空', public.pet_owned(null) = '{}'::text[], public.pet_owned(null)::text);

-- S1：任务变成 claimed 那一句 update 触发盖章
do $$
declare jid bigint; m jsonb;
begin
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, meta)
    values ('ranked', 'gift:s1', 1795392000, 'tv-g', 4242, pg_temp.u('d'), pg_temp.u('b'),
            pg_temp.snap(array['basic', 'stone', 'lava']), pg_temp.snap(array['bamboo', 'basic', 'ice']), '{}')
    returning job_id into jid;
  update public.referee_jobs set status = 'claimed' where job_id = jid;
  select meta into m from public.referee_jobs where job_id = jid;
  perform pg_temp.ck('S1 ★领活盖章: a_owned = [basic](没绑), b_owned = [bamboo, basic]',
    m -> 'a_owned' = '["basic"]'::jsonb and m -> 'b_owned' = '["bamboo", "basic"]'::jsonb, m::text);
  perform pg_temp.ck('L1 ★开算等级表: d 的 basic = 4(服务器等级), stone / lava = 1(没拥有)',
    (m -> 'a_lv' ->> 'basic')::int = 4 and (m -> 'a_lv' ->> 'stone')::int = 1 and (m -> 'a_lv' ->> 'lava')::int = 1,
    (m -> 'a_lv')::text);
end $$;

-- X1 / X2 / X3 / X4
do $$
declare r jsonb; mid uuid := gen_random_uuid();
begin
  r := public.pet_xp_grant(mid, 'ranked', pg_temp.u('a'), pg_temp.snap(array['basic', 'stone', 'ice']),
                           '["basic", "lava", "stone"]', true);
  perform pg_temp.ck('X1 ★a 赢: basic / stone 都 +8 升 2 级, ice(限免)不发',
    pg_temp.lv('a', 'basic') = 2 and pg_temp.lv('a', 'stone') = 2 and pg_temp.lv('a', 'ice') is null
    and jsonb_array_length(r) = 2, r::text);
  perform pg_temp.ck('X2 ★升级通知主站: a 的 stone 推了, a 的 basic(赠送, 主站上没有)没推',
    pg_temp.outbox_n('GiftTestA', 'stone') = 1 and pg_temp.outbox_n('GiftTestA', 'basic') = 0,
    (select string_agg(body::text, ' ') from public.mainsite_outbox where topic = 'pet-level'));
  r := public.pet_xp_grant(gen_random_uuid(), 'ranked', pg_temp.u('c'), pg_temp.snap(array['basic', 'stone', 'ice']),
                           '["basic"]', true);
  perform pg_temp.ck('X2 ★c 主站上真有 basic ⇒ basic 升 2 级且推了',
    pg_temp.lv('c', 'basic') = 2 and pg_temp.outbox_n('GiftTestC', 'basic') = 1, r::text);
  update public.pet_levels set xp = 155 where account_id = pg_temp.u('d') and pet_key = 'basic';
  update public.pet_levels set level = 2 where account_id = pg_temp.u('d') and pet_key = 'basic';
  r := public.pet_xp_grant(gen_random_uuid(), 'ranked', pg_temp.u('d'), pg_temp.snap(array['basic', 'stone', 'ice']),
                           '["basic"]', true);
  perform pg_temp.ck('X3 没绑主站: basic 涨到 3 级, 主站一条都不推',
    pg_temp.lv('d', 'basic') = 3 and (select count(*) from public.mainsite_outbox where topic = 'pet-level' and body ->> 'petKey' = 'basic'
      and body ->> 'userId' not in ('GiftTestC')) = 0, r::text);
  perform pg_temp.ck('X4 开算时没盖 basic(旧任务) ⇒ basic 不发',
    jsonb_array_length(public.pet_xp_grant(gen_random_uuid(), 'ranked', pg_temp.u('d'), pg_temp.snap(array['basic', 'stone', 'ice']),
                                           '[]', true)) = 0);
end $$;

select pg_temp.ck('P1 权限: pet_gift_ids / pet_owned 客户端调不了',
  not has_function_privilege('authenticated', 'public.pet_gift_ids()', 'execute')
  and not has_function_privilege('anon', 'public.pet_gift_ids()', 'execute')
  and not has_function_privilege('authenticated', 'public.pet_owned(uuid)', 'execute'));

do $$
declare nf int; nt int; msg text; fmsg text;
begin
  select count(*) filter (where not pass), count(*) into nf, nt from _chk;
  select string_agg(format('[%s] %s %s', case when pass then 'PASS' else 'FAIL' end, name, info), E'\n' order by n) into msg from _chk;
  select string_agg(left(format('[FAIL] %s %s', name, info), 600), E'\n' order by n) into fmsg from _chk where not pass;
  raise notice '%', msg;
  if nf > 0 then
    raise exception 'FAIL % / % —— 已回滚%', nf, nt, E'\n' || fmsg || E'\n──── 全部 ────\n' || msg;
  end if;
  raise exception 'ALL PASS (% 条) —— 已回滚, 测试数据未留下', nt;
end $$;
rollback;
