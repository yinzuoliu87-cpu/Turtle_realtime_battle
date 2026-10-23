-- 20261024 好友 + 切磋 —— 上线前验证（整段一个事务，结尾必回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261024_friends（PGlite：schema.sql → 迁移 → 本文件）
--   · 内测服 / 生产：sb_migrate.py beta|prod --rehearse（回滚事务里「迁移 + 本文件」）
--     ★本文件**最后一句一定抛异常**（全过也抛 'ALL PASS'）⇒ 整个事务回滚，造的测试账号与行一个都不留。
-- 判据（每条都配对照组）：
--   L1~L4 put_lineup：玩家 ID 由服务端算（客户端传什么都不信）/ 覆盖写一行 / 坏快照 / 超 64 KB / 没登录
--   K1~K4 friend_lookup：按 ID 找到人（只回名片不回阵容）/ 找自己 = self / 找不到 / 坏 ID
--   Q1~Q8 申请 / 同意 / 互相申请自动成 / 拒绝后不再打扰 / 拒过的人反过来申请照常成 / 删好友 / 撤回申请 / 每日上限
--   P1~P3 friend_lineup：非好友被拒（含申请中）/ 好友拿到阵容 / 没阵容退回积分赛快照 / 都没有 = no_lineup
--   C1 好友上限 100（我满 / 对方满）
--   S1~S3 权限：表直连读写被拒（RLS + revoke）/ anon 没有执行权 / 内部函数客户端调不了
--   D1~D3 删号级联、垃圾匿名号清理不误删有阵容 / 有好友的号、昵称举报重置连阵容行里的名字一起换
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _ids as
  select gen_random_uuid() as a, gen_random_uuid() as b, gen_random_uuid() as c, gen_random_uuid() as d,
         gen_random_uuid() as e, gen_random_uuid() as f, gen_random_uuid() as j1, gen_random_uuid() as j2;
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _ids to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
-- 以 p_uid 的身份调一次，结果记进 _r（name → 回包）。
create temp table _r (k text primary key, r jsonb);
grant all on _r to public;
create or replace function pg_temp.call(p_key text, p_uid uuid, p_sql text) returns jsonb language plpgsql as $$
declare res jsonb;
begin
  perform pg_temp.as_user(p_uid);
  execute 'select ' || p_sql into res;
  perform pg_temp.as_user(null);
  insert into _r values (p_key, res) on conflict (k) do update set r = excluded.r;
  return res;
end $$;
create or replace function pg_temp.r(p_key text) returns jsonb language sql as $$ select r from _r where k = p_key $$;

insert into auth.users (id, aud, role, is_anonymous, created_at)
  select x, 'authenticated', 'authenticated', true, now()
    from _ids, unnest(array[a, b, c, d, e, f]) x;

-- ── L put_lineup ──
select pg_temp.call('la', (select a from _ids),
  'public.put_lineup(''阿甲'', ''{"leaders":["ninja","stone","basic"],"profile":{"name":"阿甲","tag":"#ZZZZZZ"}}''::jsonb, 1, ''0.21.11'')');
select pg_temp.ck('L1 put_lineup 成功、回的玩家 ID = 服务端按账号算的',
  (pg_temp.r('la')->>'ok')::boolean and pg_temp.r('la')->>'tag' = public.player_tag_of((select a from _ids)::text),
  pg_temp.r('la')::text);
select pg_temp.ck('L1 表里的 tag 不是客户端快照里写的那个（#ZZZZZZ 不算数）',
  (select tag from public.lineups where account_id = (select a from _ids)) = public.player_tag_of((select a from _ids)::text));
select pg_temp.call('la2', (select a from _ids),
  'public.put_lineup(''阿甲改名'', ''{"leaders":["lava","stone","basic"]}''::jsonb, 1, ''0.21.11'')');
select pg_temp.ck('L2 再传一次 = 覆盖同一行（不新增）',
  (select count(*) from public.lineups where account_id = (select a from _ids)) = 1
  and (select name from public.lineups where account_id = (select a from _ids)) = '阿甲改名'
  and (select snapshot->'leaders'->>0 from public.lineups where account_id = (select a from _ids)) = 'lava');
select pg_temp.call('lbad', (select a from _ids), 'public.put_lineup(''x'', ''[1,2]''::jsonb, 1, '''')');
select pg_temp.call('lbig', (select a from _ids),
  'public.put_lineup(''x'', jsonb_build_object(''pad'', repeat(''x'', 70000)), 1, '''')');
select pg_temp.call('lnone', null, 'public.put_lineup(''x'', ''{}''::jsonb, 1, '''')');
select pg_temp.ck('L3 坏快照 / 超 64 KB 被拒，表里还是上一份',
  pg_temp.r('lbad')->>'reason' = 'bad_snapshot' and pg_temp.r('lbig')->>'reason' = 'too_big'
  and (select snapshot->'leaders'->>0 from public.lineups where account_id = (select a from _ids)) = 'lava',
  pg_temp.r('lbad')::text || pg_temp.r('lbig')::text);
select pg_temp.ck('L4 没登录 ⇒ not_signed_in', pg_temp.r('lnone')->>'reason' = 'not_signed_in');
-- B / C / D / E / F 也传（B 传空快照：还没配阵容的人也要能被找到）
select pg_temp.call('lb', (select b from _ids), 'public.put_lineup(''阿乙'', ''{}''::jsonb, 1, ''0.21.11'')');
select pg_temp.call('lc', (select c from _ids), 'public.put_lineup(''阿丙'', ''{"leaders":["ice"]}''::jsonb, 1, ''0.21.11'')');
select pg_temp.call('ld', (select d from _ids), 'public.put_lineup(''阿丁'', ''{"leaders":["ice"]}''::jsonb, 1, ''0.21.11'')');
select pg_temp.call('le', (select e from _ids), 'public.put_lineup(''阿戊'', ''{"leaders":["ice"]}''::jsonb, 1, ''0.21.11'')');
select pg_temp.call('lf', (select f from _ids), 'public.put_lineup(''阿己'', ''{"leaders":["ice"]}''::jsonb, 1, ''0.21.11'')');

-- ── K friend_lookup ──
select pg_temp.call('ka', (select b from _ids),
  format('public.friend_lookup(%L)', public.player_tag_of((select a from _ids)::text)));
select pg_temp.ck('K1 按 ID 找到人：账号 / 昵称 / 头像（第一只统领）对，不带阵容',
  (pg_temp.r('ka')->>'ok')::boolean
  and pg_temp.r('ka')->'people'->0->>'account' = (select a from _ids)::text
  and pg_temp.r('ka')->'people'->0->>'name' = '阿甲改名'
  and pg_temp.r('ka')->'people'->0->>'lead' = 'lava'
  and not (pg_temp.r('ka')->'people'->0 ? 'snapshot'),
  pg_temp.r('ka')::text);
select pg_temp.call('kself', (select a from _ids),
  format('public.friend_lookup(%L)', public.player_tag_of((select a from _ids)::text)));
select pg_temp.call('kno', (select a from _ids), 'public.friend_lookup(''#222222'')');
select pg_temp.call('kbad', (select a from _ids), 'public.friend_lookup(''#abc'')');
select pg_temp.ck('K2 找自己 = self；K3 找不到 = not_found；K4 坏 ID = bad_tag',
  pg_temp.r('kself')->>'reason' = 'self' and pg_temp.r('kno')->>'reason' = 'not_found'
  and pg_temp.r('kbad')->>'reason' = 'bad_tag',
  pg_temp.r('kself')::text || pg_temp.r('kno')::text || pg_temp.r('kbad')::text);

-- ── Q 申请 / 同意 ──
select pg_temp.call('p0', (select b from _ids), format('public.friend_lineup(%L::uuid)', (select a from _ids)));
select pg_temp.call('q1', (select b from _ids), format('public.friend_request(%L::uuid)', (select a from _ids)));
select pg_temp.call('q1b', (select b from _ids), format('public.friend_request(%L::uuid)', (select a from _ids)));
select pg_temp.ck('Q1 B 申请加 A ⇒ pending；再按一次不新增行',
  pg_temp.r('q1')->>'status' = 'pending' and pg_temp.r('q1b')->>'status' = 'pending'
  and (select count(*) from public.friendships) = 1, pg_temp.r('q1')::text);
select pg_temp.call('p1', (select b from _ids), format('public.friend_lineup(%L::uuid)', (select a from _ids)));
select pg_temp.ck('P1 还不是好友（没申请 / 申请中）⇒ 读不到阵容',
  pg_temp.r('p0')->>'reason' = 'not_friends' and pg_temp.r('p1')->>'reason' = 'not_friends');
select pg_temp.call('lsa', (select a from _ids), 'public.friend_list()');
select pg_temp.call('lsb', (select b from _ids), 'public.friend_list()');
select pg_temp.ck('Q2 A 的「好友申请」里有 B、B 的「已发出」里有 A，双方好友列表都空',
  jsonb_array_length(pg_temp.r('lsa')->'incoming') = 1
  and pg_temp.r('lsa')->'incoming'->0->>'account' = (select b from _ids)::text
  and jsonb_array_length(pg_temp.r('lsb')->'outgoing') = 1
  and jsonb_array_length(pg_temp.r('lsa')->'friends') = 0 and jsonb_array_length(pg_temp.r('lsb')->'friends') = 0
  and pg_temp.r('lsa')->>'tag' = public.player_tag_of((select a from _ids)::text),
  pg_temp.r('lsa')::text);
select pg_temp.call('qwrong', (select b from _ids), format('public.friend_respond(%L::uuid, true)', (select a from _ids)));
select pg_temp.ck('Q3 申请人自己不能替对方同意', pg_temp.r('qwrong')->>'reason' = 'not_found');
select pg_temp.call('q3', (select a from _ids), format('public.friend_respond(%L::uuid, true)', (select b from _ids)));
select pg_temp.call('lsa2', (select a from _ids), 'public.friend_list()');
select pg_temp.call('lsb2', (select b from _ids), 'public.friend_list()');
select pg_temp.ck('Q3 A 同意 ⇒ 双方好友列表都有对方，申请清空',
  pg_temp.r('q3')->>'status' = 'accepted'
  and pg_temp.r('lsa2')->'friends'->0->>'account' = (select b from _ids)::text
  and pg_temp.r('lsb2')->'friends'->0->>'account' = (select a from _ids)::text
  and jsonb_array_length(pg_temp.r('lsa2')->'incoming') = 0 and jsonb_array_length(pg_temp.r('lsb2')->'outgoing') = 0,
  pg_temp.r('lsa2')::text);
select pg_temp.call('qal', (select b from _ids), format('public.friend_request(%L::uuid)', (select a from _ids)));
select pg_temp.ck('Q3 已经是好友再申请 = already', pg_temp.r('qal')->>'reason' = 'already');

-- ── P 切磋取阵容 ──
select pg_temp.call('p2', (select b from _ids), format('public.friend_lineup(%L::uuid)', (select a from _ids)));
select pg_temp.ck('P2 好友拿到对方最新阵容（lineup）',
  (pg_temp.r('p2')->>'ok')::boolean and pg_temp.r('p2')->>'source' = 'lineup'
  and pg_temp.r('p2')->'snapshot'->'leaders'->>0 = 'lava' and pg_temp.r('p2')->>'rules_ver' = '1',
  pg_temp.r('p2')::text);
select pg_temp.call('p3none', (select a from _ids), format('public.friend_lineup(%L::uuid)', (select b from _ids)));
insert into public.ghosts (account_id, season_week, battles, snapshot, client_version, rules_ver)
  select b, 4102444800, 3, '{"leaders":["phoenix"],"profile":{"name":"阿乙快照"}}'::jsonb, '0.21.10', 1 from _ids;
select pg_temp.call('p3', (select a from _ids), format('public.friend_lineup(%L::uuid)', (select b from _ids)));
select pg_temp.ck('P3 对方没配阵容、也没打过积分赛 ⇒ no_lineup；打过 ⇒ 退回最新积分赛快照',
  pg_temp.r('p3none')->>'reason' = 'no_lineup'
  and pg_temp.r('p3')->>'source' = 'ghost' and pg_temp.r('p3')->'snapshot'->'leaders'->>0 = 'phoenix'
  and pg_temp.r('p3')->>'name' = '阿乙',
  pg_temp.r('p3none')::text || pg_temp.r('p3')::text);

-- ── Q 互相申请 / 拒绝 / 删除 / 撤回 ──
select pg_temp.call('q4a', (select c from _ids), format('public.friend_request(%L::uuid)', (select a from _ids)));
select pg_temp.call('q4b', (select a from _ids), format('public.friend_request(%L::uuid)', (select c from _ids)));
select pg_temp.ck('Q4 C 申请 A、A 也申请 C ⇒ 直接成为好友',
  pg_temp.r('q4a')->>'status' = 'pending' and pg_temp.r('q4b')->>'status' = 'accepted');
select pg_temp.call('q5a', (select d from _ids), format('public.friend_request(%L::uuid)', (select a from _ids)));
select pg_temp.call('q5b', (select a from _ids), format('public.friend_respond(%L::uuid, false)', (select d from _ids)));
select pg_temp.call('q5c', (select d from _ids), format('public.friend_request(%L::uuid)', (select a from _ids)));
select pg_temp.call('lsa5', (select a from _ids), 'public.friend_list()');
select pg_temp.call('lsd5', (select d from _ids), 'public.friend_list()');
select pg_temp.ck('Q5 A 拒绝 D ⇒ D 再申请回「已申请」但 A 那边什么都看不到；D 那边仍显示「等待」',
  pg_temp.r('q5b')->>'status' = 'declined' and pg_temp.r('q5c')->>'status' = 'pending'
  and jsonb_array_length(pg_temp.r('lsa5')->'incoming') = 0
  and jsonb_array_length(pg_temp.r('lsd5')->'outgoing') = 1,
  pg_temp.r('lsa5')::text);
select pg_temp.call('q6', (select a from _ids), format('public.friend_request(%L::uuid)', (select d from _ids)));
select pg_temp.call('lsd6', (select d from _ids), 'public.friend_list()');
select pg_temp.ck('Q6 拒过 D 的 A 反过来申请 D ⇒ 变成 A 发出的申请，D 收得到',
  pg_temp.r('q6')->>'status' = 'pending'
  and pg_temp.r('lsd6')->'incoming'->0->>'account' = (select a from _ids)::text,
  pg_temp.r('lsd6')::text);
select pg_temp.call('q7', (select a from _ids), format('public.friend_remove(%L::uuid)', (select d from _ids)));
select pg_temp.call('q7b', (select a from _ids), format('public.friend_remove(%L::uuid)', (select b from _ids)));
select pg_temp.call('p7', (select b from _ids), format('public.friend_lineup(%L::uuid)', (select a from _ids)));
select pg_temp.ck('Q7 撤回申请 / 删好友 ⇒ 行没了；删了之后读不到阵容',
  (pg_temp.r('q7')->>'ok')::boolean and (pg_temp.r('q7b')->>'ok')::boolean
  and not exists (select 1 from public.friendships f, _ids i
                   where (f.a, f.b) in ((least(i.a, i.d), greatest(i.a, i.d)), (least(i.a, i.b), greatest(i.a, i.b))))
  and pg_temp.r('p7')->>'reason' = 'not_friends');
-- 对照：C 与 A 的好友关系没被删掉
select pg_temp.ck('Q7 对照：A 与 C 仍是好友',
  exists (select 1 from public.friendships f, _ids i where f.a = least(i.a, i.c) and f.b = greatest(i.a, i.c) and f.status = 'accepted'));
select pg_temp.call('q7c', (select a from _ids), format('public.friend_remove(%L::uuid)', (select f from _ids)));
select pg_temp.ck('Q7 删一个本来就不是好友的 = not_found', pg_temp.r('q7c')->>'reason' = 'not_found');

-- ── Q8 每日上限 30 ──
insert into auth.users (id, aud, role, is_anonymous)
  select gen_random_uuid(), 'authenticated', 'authenticated', true from generate_series(1, 31);
insert into public.lineups (account_id, tag, name)
  select u.id, public.player_tag_of(u.id::text), 'x' from auth.users u
   where not exists (select 1 from public.lineups l where l.account_id = u.id);
do $$
declare uid uuid := (select e from _ids); t uuid; i int := 0; res jsonb;
begin
  for t in select l.account_id from public.lineups l, _ids where l.name = 'x' order by l.account_id limit 31 loop
    perform pg_temp.as_user(uid);
    res := public.friend_request(t);
    i := i + 1;
    perform pg_temp.ck(format('Q8 第 %s 个申请', i),
      case when i <= 30 then res->>'status' = 'pending' else res->>'reason' = 'limit' end, res::text);
  end loop;
  perform pg_temp.as_user(null);
end $$;

-- ── C1 好友上限 100 ──
insert into auth.users (id, aud, role, is_anonymous)
  select gen_random_uuid(), 'authenticated', 'authenticated', true from generate_series(1, 100);
create temp table _many as
  select u.id from auth.users u
   where not exists (select 1 from public.lineups l where l.account_id = u.id)
     and u.id not in (select x from _ids, unnest(array[a, b, c, d, e, f, j1, j2]) x)
   limit 100;
insert into public.friendships (a, b, requester, status, accepted_at)
  select least(m.id, i.f), greatest(m.id, i.f), m.id, 'accepted', now() from _many m, _ids i;   -- 申请人是对方: 不占 F 的每日申请额度
select pg_temp.call('c1', (select f from _ids), format('public.friend_request(%L::uuid)', (select c from _ids)));
select pg_temp.call('c1b', (select c from _ids), format('public.friend_request(%L::uuid)', (select f from _ids)));
select pg_temp.call('c1c', (select f from _ids), format('public.friend_respond(%L::uuid, true)', (select c from _ids)));
select pg_temp.ck('C1 满 100 个好友：自己申请 = full；别人申请我能发出、我同意时 = full；对方满 = their_full',
  pg_temp.r('c1')->>'reason' = 'full' and pg_temp.r('c1b')->>'status' = 'pending'
  and pg_temp.r('c1c')->>'reason' = 'full',
  pg_temp.r('c1')::text || pg_temp.r('c1b')::text || pg_temp.r('c1c')::text);
select pg_temp.call('c1d', (select d from _ids), format('public.friend_request(%L::uuid)', (select f from _ids)));
select pg_temp.call('c1e', (select f from _ids), format('public.friend_request(%L::uuid)', (select d from _ids)));
select pg_temp.ck('C1 满员的 F 反过来申请 D（等于同意 D 的申请）= full',
  pg_temp.r('c1d')->>'status' = 'pending' and pg_temp.r('c1e')->>'reason' = 'full',
  pg_temp.r('c1d')::text || pg_temp.r('c1e')::text);
do $$
declare res jsonb;
begin
  perform pg_temp.as_user((select d from _ids));
  -- D 与 F 那一行改成「F 发给 D 的申请」⇒ D 去同意一个已满 100 的人
  insert into public.friendships (a, b, requester) select least(d, f), greatest(d, f), f from _ids
    on conflict (a, b) do update set requester = excluded.requester, status = 'pending';
  res := public.friend_respond((select f from _ids), true);
  perform pg_temp.as_user(null);
  perform pg_temp.ck('C1 我同意一个已满 100 的人的申请 = their_full', res->>'reason' = 'their_full', res::text);
end $$;

-- ── S 权限 ──
select pg_temp.ck('S1 客户端角色对两张表没有任何直连权限（只走函数）',
  not has_table_privilege('authenticated', 'public.lineups', 'select')
  and not has_table_privilege('authenticated', 'public.lineups', 'insert')
  and not has_table_privilege('authenticated', 'public.friendships', 'select')
  and not has_table_privilege('authenticated', 'public.friendships', 'update')
  and not has_table_privilege('anon', 'public.lineups', 'select'));
select pg_temp.ck('S1 两张表开了 RLS',
  (select bool_and(relrowsecurity) from pg_class where oid in ('public.lineups'::regclass, 'public.friendships'::regclass)));
select pg_temp.ck('S2 anon 对七个 RPC 都没有执行权；authenticated 都有',
  (select bool_and(not has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('authenticated', p.oid, 'execute'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace
      and p.proname in ('put_lineup', 'friend_lookup', 'friend_request', 'friend_respond', 'friend_remove', 'friend_list', 'friend_lineup'))
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
      and p.proname in ('put_lineup', 'friend_lookup', 'friend_request', 'friend_respond', 'friend_remove', 'friend_list', 'friend_lineup')) = 7);
select pg_temp.ck('S3 内部函数（friend_card / snapshot_lead）客户端调不了',
  (select bool_and(not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('friend_card', 'snapshot_lead')));

-- ── D 删号 / 清理 / 举报 ──
select pg_temp.ck('D1 对照：删号之前 C 有阵容行、有好友关系',
  exists (select 1 from public.lineups where account_id = (select c from _ids))
  and exists (select 1 from public.friendships f, _ids i where f.a = i.c or f.b = i.c));
select pg_temp.as_user((select c from _ids));
select public.account_delete_self();
select pg_temp.as_user(null);
select pg_temp.ck('D1 删号 ⇒ 阵容行、好友关系随账号级联删掉；A 的阵容行还在',
  not exists (select 1 from public.lineups where account_id = (select c from _ids))
  and not exists (select 1 from public.friendships f, _ids i where f.a = i.c or f.b = i.c)
  and exists (select 1 from public.lineups where account_id = (select a from _ids)));
-- J1：匿名、20 天没登录、只有阵容行 ⇒ 不删；J2：同样但什么都没有 ⇒ 删（对照）
insert into auth.users (id, aud, role, is_anonymous, created_at, last_sign_in_at)
  select j1, 'authenticated', 'authenticated', true, now() - interval '20 days', now() - interval '20 days' from _ids
  union all select j2, 'authenticated', 'authenticated', true, now() - interval '20 days', now() - interval '20 days' from _ids;
insert into public.lineups (account_id, tag, name) select j1, public.player_tag_of(j1::text), '只打切磋' from _ids;
select public.purge_junk_anon_users();
select pg_temp.ck('D2 垃圾匿名号清理：只有阵容行的号不删，什么都没有的照删（对照）',
  exists (select 1 from auth.users where id = (select j1 from _ids))
  and not exists (select 1 from auth.users where id = (select j2 from _ids)));
-- D3 昵称举报重置
insert into public.nickname_reports (reporter, reported_tag, reported_account, name_snapshot)
  select b, public.player_tag_of(a::text), a, '阿甲改名' from _ids;
select public.nickname_report_resolve(public.player_tag_of((select a from _ids)::text), 'reset');
select pg_temp.ck('D3 昵称举报重置 ⇒ 阵容行里的名字换成占位；别人的名字不动（对照）',
  (select name from public.lineups where account_id = (select a from _ids)) = '玩家' || substr(public.player_tag_of((select a from _ids)::text), 2)
  and (select name from public.lineups where account_id = (select d from _ids)) = '阿丁',
  (select name from public.lineups where account_id = (select a from _ids)));

-- ── 结论：一定抛异常 ⇒ 整个事务回滚 ──
do $$
declare nf int; nt int; msg text;
begin
  select count(*) filter (where not pass), count(*) into nf, nt from _chk;
  select string_agg(format('[%s] %s %s', case when pass then 'PASS' else 'FAIL' end, name, info), E'\n' order by n) into msg from _chk;
  raise notice '%', msg;
  if nf > 0 then
    raise exception 'FAIL % / % —— 已回滚%', nf, nt, E'\n' || msg;
  end if;
  raise exception 'ALL PASS (% 条) —— 已回滚, 测试数据未留下', nt;
end $$;
rollback;
