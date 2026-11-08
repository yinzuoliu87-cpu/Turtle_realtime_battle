-- 20261109a 龟投账号绑定 + 拥有龟缓存 + 发件箱 —— 上线前验证（整段一个事务，结尾必回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261109a_mainsite_core（PGlite：schema.sql → 迁移 → 本文件）
--   · 内测服 / 正式服：sb_migrate.py 的 --rehearse 在回滚事务里跑（★本文件最后一句一定抛异常 ⇒ 整个事务回滚，造的号一个不留）
-- ★一个事务里 now() 不动：「过期 / 到点」一律直接改行里的时刻来造，不靠等。
-- 判据：
--   G  权限：anon / authenticated 执行不了任何 service 函数、读不到四张表；authenticated 只有 mainsite_me
--   L1~L13 登录码：登记 / 格式 / 新码作废旧码 / 设备型号 / 绑定 / 重放同结果 / 换 user_id 被拒 / 过期 / 已绑别的号 ⇒ switched /
--          同号 ⇒ same / 改绑 ⇒ rebound + 旧的发 unlinked / 坏 userId / 别人的码查不到 / 确认后 5 分钟 / 每小时 30 个
--   P1~P5 拥有龟：没绑 / 改绑中 / 整份替换 / 坏 key 跳过 / 一只都没有也记 fetched_at；mainsite_me 形状
--   O1~O9 发件箱：坏主题抛异常 / 同键不重复 / 没绑不写 defense / pet-level 只写拥有的龟且 1~10 级 /
--          领活顺序（道内按 id、settle 等 started）/ 租期 / 5xx 重试 / ok:false 终态 / settle 先写也等 started
--   D1~D4 删号：已绑 ⇒ 一条 unlinked（userId = 主站 ID）、绑定与缓存随 cascade 没了；没绑 ⇒ 不写；
--          他又绑上了 ⇒ 没发出去的 unlinked 作废（superseded）
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
-- 抛异常的调用 ⇒ 返回异常文本（不抛 ⇒ 返回 null）
create or replace function pg_temp.err_of(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlerrm;
end $$;

create temp table _ids as
  select gen_random_uuid() as a, gen_random_uuid() as b, gen_random_uuid() as c, gen_random_uuid() as d,
         gen_random_uuid() as e;
grant select on _ids to public;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select a, 'authenticated', 'authenticated', true, now() from _ids
  union all select b, 'authenticated', 'authenticated', true, now() from _ids
  union all select c, 'authenticated', 'authenticated', false, now() from _ids
  union all select d, 'authenticated', 'authenticated', true, now() from _ids
  union all select e, 'authenticated', 'authenticated', true, now() from _ids;

-- ── G 权限 ──
select pg_temp.ck('G anon 不能 mainsite_me', not has_function_privilege('anon', 'public.mainsite_me()', 'execute'));
select pg_temp.ck('G authenticated 能 mainsite_me', has_function_privilege('authenticated', 'public.mainsite_me()', 'execute'));
select pg_temp.ck('G anon / authenticated 不能执行任何 service 函数',
  not exists (select 1 from pg_proc p cross join (values ('anon'), ('authenticated')) r(rolname)
               where p.pronamespace = 'public'::regnamespace and p.proname like 'mainsite%' and p.proname <> 'mainsite_me'
                 and has_function_privilege(r.rolname, p.oid, 'execute')),
  (select string_agg(p.proname || '/' || r.rolname, ',') from pg_proc p cross join (values ('anon'), ('authenticated')) r(rolname)
    where p.pronamespace = 'public'::regnamespace and p.proname like 'mainsite%' and p.proname <> 'mainsite_me'
      and has_function_privilege(r.rolname, p.oid, 'execute')));
select pg_temp.ck('G 分母: service 函数 9 个，service_role 都能执行',
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mainsite%'
      and p.proname not in ('mainsite_me', 'mainsite_outbox_lane') and has_function_privilege('service_role', p.oid, 'execute')) = 9,
  (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mainsite%'));
select pg_temp.ck('G authenticated 读不到四张表',
  not has_table_privilege('authenticated', 'public.mainsite_accounts', 'select')
  and not has_table_privilege('authenticated', 'public.mainsite_codes', 'select')
  and not has_table_privilege('authenticated', 'public.mainsite_pets', 'select')
  and not has_table_privilege('authenticated', 'public.mainsite_outbox', 'select')
  and not has_table_privilege('anon', 'public.mainsite_outbox', 'insert'));
select pg_temp.ck('G 四张表都开了 RLS',
  (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relrowsecurity
      and relname in ('mainsite_accounts', 'mainsite_codes', 'mainsite_pets', 'mainsite_outbox')) = 4);

-- ── L 登录码 ──
create temp table _r as select 1 as k, public.mainsite_link_start((select a from _ids), 'codeA1_xxxxxxxxxxxx', 'iPhone 15') as r;
select pg_temp.ck('L1 登记成功、5 分钟', (select r->>'ok' = 'true' and (r->>'expires_in')::int = 300 and r->>'code' = 'codeA1_xxxxxxxxxxxx' from _r where k = 1),
  (select r::text from _r where k = 1));
select pg_temp.ck('L1 过期时刻 = 现在 + 5 分钟', (select expires_at = now() + interval '5 minutes' from public.mainsite_codes where code = 'codeA1_xxxxxxxxxxxx'));
select pg_temp.ck('L1 坏格式的码 ⇒ bad_code',
  public.mainsite_link_start((select a from _ids), 'a b', 'x')->>'error' = 'bad_code'
  and public.mainsite_link_start((select a from _ids), 'abc', 'x')->>'error' = 'bad_code'
  and public.mainsite_link_start((select a from _ids), repeat('a', 65), 'x')->>'error' = 'bad_code');
select pg_temp.ck('L1 不存在的号 ⇒ no_account', public.mainsite_link_start(gen_random_uuid(), 'codeZZZZ', 'x')->>'error' = 'no_account');
select pg_temp.ck('L1 码撞了 ⇒ code_taken', public.mainsite_link_start((select b from _ids), 'codeA1_xxxxxxxxxxxx', 'x')->>'error' = 'code_taken');
select pg_temp.ck('L3 设备型号', public.mainsite_link_info('codeA1_xxxxxxxxxxxx') = '{"ok": true, "device": "iPhone 15"}'::jsonb,
  public.mainsite_link_info('codeA1_xxxxxxxxxxxx')::text);
select pg_temp.ck('L3 不存在的码 ⇒ ok:false', (public.mainsite_link_info('nope_nope')->>'ok')::boolean = false);
insert into _r select 2, public.mainsite_link_start((select e from _ids), 'codeE_long', repeat('设', 200));
select pg_temp.ck('L1 设备型号超 128 字截断', (select (r->>'ok')::boolean from _r where k = 2)
  and (select char_length(device) from public.mainsite_codes where code = 'codeE_long') = 128,
  (select char_length(device)::text from public.mainsite_codes where code = 'codeE_long'));
-- L2 新码作废旧码
select public.mainsite_link_start((select a from _ids), 'codeA2_yyyyyyyyyyyy', 'iPhone 15');
select pg_temp.ck('L2 新码作废旧码（旧码 info ⇒ ok:false，新码 ok）',
  (public.mainsite_link_info('codeA1_xxxxxxxxxxxx')->>'ok')::boolean = false
  and (public.mainsite_link_info('codeA2_yyyyyyyyyyyy')->>'ok')::boolean);
select pg_temp.ck('L2 旧码轮询 ⇒ expired', public.mainsite_link_poll((select a from _ids), 'codeA1_xxxxxxxxxxxx')->>'status' = 'expired');
select pg_temp.ck('L6 旧码确认 ⇒ expired', public.mainsite_link_confirm('codeA1_xxxxxxxxxxxx', 'GEACjjPJERy')->>'error' = 'expired');
select pg_temp.ck('L2 新码轮询 ⇒ pending', public.mainsite_link_poll((select a from _ids), 'codeA2_yyyyyyyyyyyy')
  = '{"ok": true, "status": "pending", "switched": false}'::jsonb);
select pg_temp.ck('L11 别的号查这个码 ⇒ bad_code', public.mainsite_link_poll((select b from _ids), 'codeA2_yyyyyyyyyyyy')->>'error' = 'bad_code');
-- L10 坏 userId
select pg_temp.ck('L10 纯数字 / 太短 / 带符号的 userId ⇒ bad userId',
  public.mainsite_link_confirm('codeA2_yyyyyyyyyyyy', '12345678')->>'error' = 'bad userId'
  and public.mainsite_link_confirm('codeA2_yyyyyyyyyyyy', 'abc')->>'error' = 'bad userId'
  and public.mainsite_link_confirm('codeA2_yyyyyyyyyyyy', 'GEAC-jjPJ')->>'error' = 'bad userId'
  and public.mainsite_link_confirm('codeA2_yyyyyyyyyyyy', null)->>'error' = 'bad userId');
select pg_temp.ck('L10 坏 userId 不消耗这个码', (public.mainsite_link_info('codeA2_yyyyyyyyyyyy')->>'ok')::boolean);
-- L4 绑定（A 是匿名号、没有 accounts 行）
select pg_temp.ck('L4 前提: A 没有 accounts 行', not exists (select 1 from public.accounts where account_id = (select a from _ids)));
insert into _r select 4, public.mainsite_link_confirm('codeA2_yyyyyyyyyyyy', 'GEACjjPJERy');
select pg_temp.ck('L4 确认 ⇒ ok / bound', (select r = '{"ok": true, "result": "bound"}'::jsonb from _r where k = 4), (select r::text from _r where k = 4));
select pg_temp.ck('L4 绑定行在、accounts 行补上了',
  (select mainsite_user_id from public.mainsite_accounts where account_id = (select a from _ids)) = 'GEACjjPJERy'
  and exists (select 1 from public.accounts where account_id = (select a from _ids)));
select pg_temp.ck('L4 轮询 ⇒ confirmed / switched:false / 不带 target_account',
  (select r->>'status' = 'confirmed' and r->>'switched' = 'false' and r->>'result' = 'bound' and not (r ? 'target_account')
     from (select public.mainsite_link_poll((select a from _ids), 'codeA2_yyyyyyyyyyyy') as r) x),
  public.mainsite_link_poll((select a from _ids), 'codeA2_yyyyyyyyyyyy')::text);
select pg_temp.ck('L4 确认后 info ⇒ ok:false（一次性）', (public.mainsite_link_info('codeA2_yyyyyyyyyyyy')->>'ok')::boolean = false);
-- L5 重放
select pg_temp.ck('L5 主站重试同一个确认 ⇒ 同一个结果', public.mainsite_link_confirm('codeA2_yyyyyyyyyyyy', 'GEACjjPJERy')
  = (select r from _r where k = 4));
insert into _r select 5, public.mainsite_link_confirm('codeA2_yyyyyyyyyyyy', 'HxyzOtherU1');
select pg_temp.ck('L5 换个 user_id 再确认 ⇒ code_used，绑定不变',
  (select r->>'error' = 'code_used' from _r where k = 5)
  and (select count(*) from public.mainsite_accounts where account_id = (select a from _ids) and mainsite_user_id = 'GEACjjPJERy') = 1
  and not exists (select 1 from public.mainsite_accounts where mainsite_user_id = 'HxyzOtherU1'));
-- L12 确认后过了 5 分钟
update public.mainsite_codes set confirmed_at = now() - interval '5 minutes' where code = 'codeA2_yyyyyyyyyyyy';
select pg_temp.ck('L12 确认后 5 分钟还没来取 ⇒ expired', public.mainsite_link_poll((select a from _ids), 'codeA2_yyyyyyyyyyyy')->>'status' = 'expired');
-- L6 没确认就过期
select public.mainsite_link_start((select b from _ids), 'codeB1_zzzzzzzzzzzz', 'Pixel 8');
update public.mainsite_codes set expires_at = now() where code = 'codeB1_zzzzzzzzzzzz';
select pg_temp.ck('L6 过期的码: info ok:false / 确认 expired / 轮询 expired',
  (public.mainsite_link_info('codeB1_zzzzzzzzzzzz')->>'ok')::boolean = false
  and public.mainsite_link_confirm('codeB1_zzzzzzzzzzzz', 'GEACjjPJERy')->>'error' = 'expired'
  and public.mainsite_link_poll((select b from _ids), 'codeB1_zzzzzzzzzzzz')->>'status' = 'expired');
-- L7 已绑在 A 上的主站用户在 B 上确认 ⇒ switched
select public.mainsite_link_start((select b from _ids), 'codeB2_wwwwwwwwwwww', 'Pixel 8');
insert into _r select 7, public.mainsite_link_confirm('codeB2_wwwwwwwwwwww', 'GEACjjPJERy');
select pg_temp.ck('L7 确认 ⇒ ok / switched', (select r = '{"ok": true, "result": "switched"}'::jsonb from _r where k = 7), (select r::text from _r where k = 7));
select pg_temp.ck('L7 轮询 ⇒ switched:true + target_account = A',
  (select r->>'switched' = 'true' and r->>'status' = 'confirmed' and (r->>'target_account')::uuid = (select a from _ids)
     from (select public.mainsite_link_poll((select b from _ids), 'codeB2_wwwwwwwwwwww') as r) x));
select pg_temp.ck('L7 绑定不动（还在 A，B 没绑）',
  (select account_id from public.mainsite_accounts where mainsite_user_id = 'GEACjjPJERy') = (select a from _ids)
  and not exists (select 1 from public.mainsite_accounts where account_id = (select b from _ids)));
-- L8 同号再确认 ⇒ same
select public.mainsite_link_start((select a from _ids), 'codeA3_vvvvvvvvvvvv', 'iPhone 15');
select pg_temp.ck('L8 已绑在这个号上 ⇒ same', public.mainsite_link_confirm('codeA3_vvvvvvvvvvvv', 'GEACjjPJERy')->>'result' = 'same');
-- L13 每小时 30 个
do $$ declare i int; begin
  for i in 1..30 loop perform public.mainsite_link_start((select d from _ids), 'rate_' || i || '_xxxx', 'x'); end loop;
end $$;
select pg_temp.ck('L13 一小时第 31 个 ⇒ rate_limited', public.mainsite_link_start((select d from _ids), 'rate_31_xxxx', 'x')->>'error' = 'rate_limited');
select pg_temp.ck('L13 前 30 个里只有最后一个有效', (select count(*) from public.mainsite_codes where account_id = (select d from _ids) and expires_at > now()) = 1);

-- ── P 拥有龟 ──
select pg_temp.ck('P1 没绑 ⇒ not_linked', public.mainsite_pets_put((select b from _ids), 'GEACjjPJERy', '["basic"]')->>'error' = 'not_linked');
-- ★调用与回读分两句：同一句里的子查询看不见函数刚写的行（语句快照），合在一句里「没写」恒真
insert into _r select 20, public.mainsite_pets_put((select a from _ids), 'HxyzOtherU1', '["basic"]');
select pg_temp.ck('P2 主站用户对不上（中途改绑）⇒ relinked、不写',
  (select r->>'error' = 'relinked' from _r where k = 20)
  and not exists (select 1 from public.mainsite_pets where account_id = (select a from _ids)));
select pg_temp.ck('P5 绑了没取过 ⇒ owned 空、fetched_at 空', public.mainsite_status((select a from _ids))
  = jsonb_build_object('ok', true, 'linked', true, 'user_id', 'GEACjjPJERy', 'owned', '[]'::jsonb, 'fetched_at', null));
insert into _r select 30, public.mainsite_pets_put((select a from _ids), 'GEACjjPJERy', '["stone", "basic", "Bad-Key", "basic", "lava"]');
select pg_temp.ck('P3 写入：去重、坏 key 跳过、按字母序', (select r->'owned' = '["basic", "lava", "stone"]'::jsonb and r->>'fetched_at' is not null from _r where k = 30),
  (select r::text from _r where k = 30));
select public.mainsite_pets_put((select a from _ids), 'GEACjjPJERy', '["basic", "ice"]');
select pg_temp.ck('P3 整份替换：没了的删、新的加', (select array_agg(pet_key order by pet_key) from public.mainsite_pets where account_id = (select a from _ids))
  = array['basic', 'ice']);
select pg_temp.ck('P4 坏参数 ⇒ bad_keys', public.mainsite_pets_put((select a from _ids), 'GEACjjPJERy', '{"a": 1}')->>'error' = 'bad_keys');
select pg_temp.as_user((select a from _ids));
create temp table _me as select public.mainsite_me() as r;
select pg_temp.as_user(null);
select pg_temp.ck('P5 mainsite_me 形状 {ok, linked, user_id, owned, fetched_at}',
  (select r->>'linked' = 'true' and r->>'user_id' = 'GEACjjPJERy' and r->'owned' = '["basic", "ice"]'::jsonb and r ? 'fetched_at'
     from _me), (select r::text from _me));
select pg_temp.as_user((select b from _ids));
select pg_temp.ck('P5 mainsite_me 没绑 ⇒ linked:false、owned 空', public.mainsite_me()->>'linked' = 'false' and public.mainsite_me()->'owned' = '[]'::jsonb);
select pg_temp.as_user(null);
select pg_temp.ck('P5 mainsite_me 没登录 ⇒ not_signed_in', public.mainsite_me()->>'reason' = 'not_signed_in');

-- ── O 发件箱 ──
select pg_temp.ck('O1 坏主题 ⇒ 抛异常', pg_temp.err_of($q$select public.mainsite_outbox_put('exp', 'k1', '{"userId": "GEACjjPJERy"}')$q$) like '%bad topic%');
select pg_temp.ck('O1 空幂等键 ⇒ 抛异常', pg_temp.err_of($q$select public.mainsite_outbox_put('started', '', '{"raidId": 1}')$q$) is not null);
select pg_temp.ck('O1 settle 缺 raidId ⇒ 抛异常', pg_temp.err_of($q$select public.mainsite_outbox_put('settle', 'k', '{"result": "void"}')$q$) like '%without raidId%');
select pg_temp.ck('O1 unlinked 缺 userId ⇒ 抛异常', pg_temp.err_of($q$select public.mainsite_outbox_put('unlinked', 'k', '{}')$q$) like '%without userId%');
select public.mainsite_outbox_put('defense', 'def:nobody:1', '{"userId": "NotLinked01", "hasDefense": true, "rating": 3, "device": ""}');
select pg_temp.ck('O3 没绑的 userId ⇒ defense 不写', not exists (select 1 from public.mainsite_outbox where idem_key = 'def:nobody:1'));
select public.mainsite_outbox_put('pet-level', 'pl:x1', '{"userId": "GEACjjPJERy", "petKey": "lava", "level": 4}');
select public.mainsite_outbox_put('pet-level', 'pl:x2', '{"userId": "GEACjjPJERy", "petKey": "ice", "level": 11}');
select public.mainsite_outbox_put('pet-level', 'pl:x3', '{"userId": "GEACjjPJERy", "petKey": "ice", "level": 0}');
select pg_temp.ck('O4 pet-level: 主站没返回过的龟 / 11 级 / 0 级 ⇒ 都不写',
  not exists (select 1 from public.mainsite_outbox where idem_key in ('pl:x1', 'pl:x2', 'pl:x3')));
-- 造一批：① started 7 ② settle 7 ③ pet-level U ④ defense U ⑤ settle 8（没有 started）⑥ settle 9 ⑦ started 9（settle 先写）
select public.mainsite_outbox_put('started', 'st:7', '{"raidId": 7}');
select public.mainsite_outbox_put('settle', 'se:7', '{"raidId": 7, "result": "attacker", "matchId": "m7"}');
select public.mainsite_outbox_put('pet-level', 'pl:u1', '{"userId": "GEACjjPJERy", "petKey": "ice", "level": 3}');
select public.mainsite_outbox_put('defense', 'def:u1', '{"userId": "GEACjjPJERy", "hasDefense": true, "rating": 5, "device": "iPhone 15"}');
select public.mainsite_outbox_put('settle', 'se:8', '{"raidId": 8, "result": "void", "matchId": ""}');
select public.mainsite_outbox_put('settle', 'se:9', '{"raidId": 9, "result": "defender", "matchId": "m9"}');
select public.mainsite_outbox_put('started', 'st:9', '{"raidId": 9}');
select public.mainsite_outbox_put('started', 'st:7', '{"raidId": 7, "dup": true}');
select pg_temp.ck('O2 同 (topic, idem_key) 重复写 ⇒ 不动（一行、内容是第一次的）',
  (select count(*) from public.mainsite_outbox where idem_key = 'st:7') = 1
  and (select not (body ? 'dup') from public.mainsite_outbox where idem_key = 'st:7'));
select pg_temp.ck('O4 拥有的龟、3 级 ⇒ 写', exists (select 1 from public.mainsite_outbox where idem_key = 'pl:u1'));
create temp table _ob as select topic || ':' || idem_key as tk, id from public.mainsite_outbox;
create temp table _c1 as select public.mainsite_outbox_claim(20, 120) as r;
create temp table _c1k as select x->>'idem_key' as k, (x->>'id')::bigint as id from _c1, jsonb_array_elements(r) x;
select pg_temp.ck('O5 第一批 = started 7 / pet-level U / settle 8 / started 9（settle 7 等 started、defense U 等 pet-level、settle 9 等 started）',
  (select array_agg(k order by id) from _c1k) = array['st:7', 'pl:u1', 'se:8', 'st:9'],
  (select string_agg(k, ',' order by id) from _c1k));
select pg_temp.ck('O5 回包按 id 升序、带 body', (select r->0->'body' = '{"raidId": 7}'::jsonb and (r->0->>'id')::bigint < (r->1->>'id')::bigint from _c1));
create temp table _c2 as select public.mainsite_outbox_claim(20, 120) as r;
select pg_temp.ck('O6 租期内再领 ⇒ 一条都没有', (select r = '[]'::jsonb from _c2), (select r::text from _c2));
-- O7 started 7 遇到 5xx ⇒ 退避重试
select public.mainsite_outbox_mark((select id from _c1k where k = 'st:7'), 'http_503', null, 30);
select pg_temp.ck('O7 5xx ⇒ attempts 1、没完成、next_at 推后 30 秒',
  (select attempts = 1 and done_at is null and next_at = now() + interval '30 seconds' and last_status = 'http_503'
     from public.mainsite_outbox where idem_key = 'st:7'));
update public.mainsite_outbox set next_at = now() - interval '1 second' where done_at is null;
create temp table _c3 as select public.mainsite_outbox_claim(20, 120) as r;
select pg_temp.ck('O7 到点再领：started 7 重来，settle 7 仍不发',
  (select array_agg(x->>'idem_key' order by (x->>'id')::bigint) from _c3, jsonb_array_elements(r) x) = array['st:7', 'pl:u1', 'se:8', 'st:9'],
  (select r::text from _c3));
-- O8 started 7 成功（回包带 expireAt）、pet-level U 收到 ok:false ⇒ 终态
select public.mainsite_outbox_mark((select id from _c1k where k = 'st:7'), 'ok', '{"ok": true, "expireAt": 1800000000000}', null);
select public.mainsite_outbox_mark((select id from _c1k where k = 'pl:u1'), 'ok_false: pet not owned', '{"ok": false, "error": "pet not owned"}', null);
select pg_temp.ck('O8 成功 ⇒ done_at、回包整个存下（started 的 expireAt）',
  (select done_at is not null and reply->>'expireAt' = '1800000000000' and attempts = 2 from public.mainsite_outbox where idem_key = 'st:7'));
select pg_temp.ck('O8 ok:false ⇒ 终态（done_at、last_status 记原因、不再领）',
  (select done_at is not null and last_status like 'ok_false%' and reply->>'error' = 'pet not owned' from public.mainsite_outbox where idem_key = 'pl:u1'));
insert into _r select 50, public.mainsite_outbox_mark((select id from _c1k where k = 'st:7'), 'x', null, 5);
select pg_temp.ck('O8 已完成的再记一次 ⇒ ok:false、不动', (select r->>'ok' = 'false' from _r where k = 50)
  and (select attempts = 2 and done_at is not null and last_status = 'ok' from public.mainsite_outbox where idem_key = 'st:7'));
update public.mainsite_outbox set next_at = now() - interval '1 second' where done_at is null;
create temp table _c4 as select public.mainsite_outbox_claim(20, 120) as r;
select pg_temp.ck('O5 started 7 完成后 settle 7 才发；pet-level U 终态后 defense U 才发；settle 9 仍等 started 9',
  (select array_agg(x->>'idem_key' order by (x->>'id')::bigint) from _c4, jsonb_array_elements(r) x) = array['se:7', 'def:u1', 'se:8', 'st:9'],
  (select r::text from _c4));
select public.mainsite_outbox_mark((select id from _ob where tk = 'started:st:9'), 'ok', '{"ok": true}', null);
update public.mainsite_outbox set next_at = now() - interval '1 second' where done_at is null;
select pg_temp.ck('O9 settle 先写（id 更小）也等 started：started 9 完成后才出现',
  (select bool_or(x->>'idem_key' = 'se:9') from jsonb_array_elements(public.mainsite_outbox_claim(20, 120)) x));
update public.mainsite_outbox set next_at = now() - interval '1 second' where done_at is null;
select pg_temp.ck('O5 p_limit = 1 ⇒ 恰好领 1 条', jsonb_array_length((select public.mainsite_outbox_claim(1, 120))) = 1);

-- ── D 删号 ──
-- A（已绑 GEACjjPJERy、有拥有龟）删号；E（没绑）删号
select pg_temp.as_user((select a from _ids));
create temp table _da as select public.account_delete_self() as r;
select pg_temp.as_user((select e from _ids));
create temp table _de as select public.account_delete_self() as r;
select pg_temp.as_user(null);
select pg_temp.ck('D1 删号回 ok', (select (r->>'ok')::boolean from _da) and (select (r->>'ok')::boolean from _de), (select r::text from _da));
select pg_temp.ck('D1 已绑 ⇒ 一条 unlinked，body = {userId: 主站 ID}',
  (select count(*) from public.mainsite_outbox where topic = 'unlinked' and idem_key = 'del:' || (select a from _ids)::text
      and body = '{"userId": "GEACjjPJERy"}'::jsonb and done_at is null) = 1);
select pg_temp.ck('D2 没绑 ⇒ 不写', not exists (select 1 from public.mainsite_outbox where idem_key = 'del:' || (select e from _ids)::text));
select pg_temp.ck('D3 绑定行与拥有龟缓存随 cascade 没了',
  not exists (select 1 from public.mainsite_accounts where account_id = (select a from _ids))
  and not exists (select 1 from public.mainsite_pets where account_id = (select a from _ids)));
-- D4 他又在 C 上绑回来 ⇒ 没发出去的 unlinked 作废；C 原先绑着 HxyzOtherU1 ⇒ 改绑，旧的发 unlinked
insert into public.accounts (account_id) select c from _ids;
insert into public.mainsite_accounts (account_id, mainsite_user_id) select c, 'HxyzOtherU1' from _ids;
select public.mainsite_pets_put((select c from _ids), 'HxyzOtherU1', '["basic"]');
select public.mainsite_link_start((select c from _ids), 'codeC1_uuuuuuuuuuuu', 'iPad');
insert into _r select 40, public.mainsite_link_confirm('codeC1_uuuuuuuuuuuu', 'GEACjjPJERy');
select pg_temp.ck('L9 C 原先绑着别的主站用户 ⇒ rebound', (select r->>'result' = 'rebound' from _r where k = 40), (select r::text from _r where k = 40));
select pg_temp.ck('L9 改绑后 C ↔ GEACjjPJERy、旧缓存清掉',
  (select mainsite_user_id from public.mainsite_accounts where account_id = (select c from _ids)) = 'GEACjjPJERy'
  and not exists (select 1 from public.mainsite_pets where account_id = (select c from _ids))
  and (select pets_fetched_at is null from public.mainsite_accounts where account_id = (select c from _ids)));
select pg_temp.ck('L9 旧的主站用户 HxyzOtherU1 收到一条 unlinked',
  (select count(*) from public.mainsite_outbox where topic = 'unlinked' and body = '{"userId": "HxyzOtherU1"}'::jsonb and done_at is null) = 1);
select pg_temp.ck('D4 GEACjjPJERy 删号时那条 unlinked 作废（superseded）',
  (select done_at is not null and last_status = 'superseded' from public.mainsite_outbox
    where idem_key = 'del:' || (select a from _ids)::text));

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
