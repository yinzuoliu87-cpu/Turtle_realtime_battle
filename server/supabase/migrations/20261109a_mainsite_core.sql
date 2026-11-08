-- >>> BEGIN mainsite_core 20261109a >>>
-- ─────────────────────────────────────────────────────────────
-- 龟投账号绑定 + 拥有龟缓存 + 发件箱（2026-11-09 · 方案书 docs/plans/20261107-龟战主站对接.md §4.1 / §4.3 / §4.8；
--   网关与发件箱的原始设计 docs/plans/20261105c-主站对接偷袭.md §4.1 / §4.6 D38；主站接口 docs/specs/龟战主站整体方案.md §6）
--
-- 本文件做六件事：
--   ① mainsite_accounts：账号 ↔ 主站用户（主站对外编码 ID，如 GEACjjPJERy）。一个号最多绑一个主站用户，一个主站用户最多绑一个号。
--   ② mainsite_codes：App 登录码（5 分钟、一次性，带设备型号给主站确认页显示）。
--      mainsite_link_start / mainsite_link_info / mainsite_link_confirm / mainsite_link_poll —— 网关调（service_role）。
--   ③ mainsite_pets：主站 /player 返回的拥有龟缓存。mainsite_pets_put（网关调）/ mainsite_status（网关调）/ mainsite_me()（App 调）。
--   ④ mainsite_outbox：所有「我们调主站」的写请求先进这里，referee_poller.py 的 outbox_loop 发。
--      mainsite_outbox_put（其他 security definer 函数内部调）/ mainsite_outbox_claim / mainsite_outbox_mark（outbox_loop 调）。
--      发送顺序：按 id；同一 raidId 的 started / settle 一条道、同一 userId 的 defense / pet-level / unlinked 一条道，
--      道里前一条没完成（done_at 为空）后一条不发；settle 另外要等同 raidId 的 started 完成（不论谁的 id 小）。
--      重试（方案书 §4.8）：只对连不上、5xx、401 退避重试；HTTP 200 + ok:false 记下 last_status 后停（done_at 也写上 = 终态）。
--   ⑤ 换绑与删号：已绑在别的号上的主站用户来确认 ⇒ result = switched（网关给 App 签那个号的登录态）；
--      这个号原先绑着另一个主站用户 ⇒ 改绑（rebound），给旧的那个发 unlinked、清掉拥有龟缓存；
--      主站用户重新绑上时，他还没发出去的 unlinked 作废（superseded），免得晚到的解绑把新绑定冲掉。
--   ⑥ account_delete_self()：以 20261020b 版为底，删号前已绑定 ⇒ 写一条 unlinked 发件箱（没绑 ⇒ 不写）。其余一字不动。
--
-- ★表一律开 RLS、不建 policy、revoke 掉 anon / authenticated：客户端读不到也写不进，只经下面的函数。
--   App 只有 mainsite_me() 一个入口（authenticated）；其余全是 service_role（网关 / 裁判轮询器）。
-- ★本文件只建表 / 建函数 / 改写一个函数，不删任何已有数据。重复执行安全（沙盒里 schema.sql 末尾同段会先跑一遍）。
-- ★上线前跑 server/supabase/tests/20261109a_mainsite_core_check.sql（整段一个事务，结尾必回滚）。
-- ─────────────────────────────────────────────────────────────

-- ═══ ① 绑定 ═══
create table if not exists public.mainsite_accounts (
  account_id       uuid        primary key references public.accounts(account_id) on delete cascade,
  mainsite_user_id text        not null unique
                               check (mainsite_user_id ~ '^[0-9A-Za-z]{4,32}$' and mainsite_user_id !~ '^[0-9]+$'),
  is_bot           boolean     not null default false,
  linked_at        timestamptz not null default now(),
  pets_fetched_at  timestamptz            -- 上次成功从主站 /player 取到拥有龟的时刻（一只都没有时也记）
);
alter table public.mainsite_accounts enable row level security;
revoke all on public.mainsite_accounts from anon, authenticated, public;

-- ═══ ② 登录码 ═══
create table if not exists public.mainsite_codes (
  code             text        primary key check (code ~ '^[A-Za-z0-9_-]{4,64}$'),
  account_id       uuid        not null references auth.users(id) on delete cascade,
  device           text        not null default '' check (char_length(device) <= 128),
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null,
  mainsite_user_id text,
  confirmed_at     timestamptz,
  result           text        check (result in ('bound', 'same', 'switched', 'rebound')),
  target_account   uuid        references auth.users(id) on delete set null
);
create index if not exists mainsite_codes_account_idx on public.mainsite_codes (account_id, created_at desc);
alter table public.mainsite_codes enable row level security;
revoke all on public.mainsite_codes from anon, authenticated, public;

-- ═══ ③ 拥有龟缓存 ═══
create table if not exists public.mainsite_pets (
  account_id uuid        not null references public.mainsite_accounts(account_id) on delete cascade,
  pet_key    text        not null check (pet_key ~ '^[a-z0-9_]{1,32}$'),
  fetched_at timestamptz not null default now(),
  primary key (account_id, pet_key)
);
alter table public.mainsite_pets enable row level security;
revoke all on public.mainsite_pets from anon, authenticated, public;

-- ═══ ④ 发件箱 ═══
create table if not exists public.mainsite_outbox (
  id          bigserial   primary key,
  topic       text        not null check (topic in ('defense', 'pet-level', 'started', 'settle', 'unlinked')),
  idem_key    text        not null check (idem_key <> ''),
  body        jsonb       not null check (jsonb_typeof(body) = 'object'),
  attempts    int         not null default 0,
  next_at     timestamptz not null default now(),
  done_at     timestamptz,
  last_status text,
  reply       jsonb,
  created_at  timestamptz not null default now(),
  unique (topic, idem_key)
);
create index if not exists mainsite_outbox_open_idx on public.mainsite_outbox (id) where done_at is null;
alter table public.mainsite_outbox enable row level security;
revoke all on public.mainsite_outbox from anon, authenticated, public;

-- 一条发件属于哪条「道」（道内按 id 顺序、前一条完成才发后一条）。
create or replace function public.mainsite_outbox_lane(p_topic text, p_body jsonb) returns text
language sql immutable as $$
  select case when p_topic in ('started', 'settle') then 'raid:' || coalesce(p_body->>'raidId', '')
              else 'user:' || coalesce(p_body->>'userId', '') end
$$;
revoke all on function public.mainsite_outbox_lane(text, jsonb) from public, anon, authenticated;

-- 写一条发件。同 (topic, idem_key) 重复写 = 不动。
--   ★业务规矩在这里统一挡（调用方不用各自再判）：defense / pet-level 只在这个 userId 已绑定时写；
--     pet-level 只写主站 /player 返回过的龟（mainsite_pets 里有）、等级 1 ~ 10。不满足 ⇒ 静默不写。
--   ★调用写错（主题不认识 / 幂等键空 / 缺 raidId 或 userId）⇒ 抛异常（门禁里当场红，不悄悄吞掉）。
create or replace function public.mainsite_outbox_put(p_topic text, p_key text, p_body jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare lv text;
begin
  if p_topic is null or p_topic not in ('defense', 'pet-level', 'started', 'settle', 'unlinked') then
    raise exception 'mainsite_outbox_put: bad topic %', p_topic;
  end if;
  if coalesce(p_key, '') = '' or p_body is null or jsonb_typeof(p_body) <> 'object' then
    raise exception 'mainsite_outbox_put: empty key or body is not an object (topic %)', p_topic;
  end if;
  if p_topic in ('started', 'settle') and coalesce(p_body->>'raidId', '') = '' then
    raise exception 'mainsite_outbox_put: % without raidId', p_topic;
  end if;
  if p_topic in ('defense', 'pet-level', 'unlinked') and coalesce(p_body->>'userId', '') = '' then
    raise exception 'mainsite_outbox_put: % without userId', p_topic;
  end if;
  if p_topic in ('defense', 'pet-level')
     and not exists (select 1 from public.mainsite_accounts where mainsite_user_id = p_body->>'userId') then
    return;
  end if;
  if p_topic = 'pet-level' then
    lv := p_body->>'level';
    if lv is null or lv !~ '^[0-9]{1,3}$' or lv::int not between 1 and 10 then
      return;
    end if;
    if not exists (select 1 from public.mainsite_accounts a
                     join public.mainsite_pets p on p.account_id = a.account_id
                    where a.mainsite_user_id = p_body->>'userId' and p.pet_key = p_body->>'petKey') then
      return;
    end if;
  end if;
  insert into public.mainsite_outbox (topic, idem_key, body) values (p_topic, p_key, p_body)
    on conflict (topic, idem_key) do nothing;
end $$;
revoke all on function public.mainsite_outbox_put(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.mainsite_outbox_put(text, text, jsonb) to service_role;

-- 领一批该发的（outbox_loop 调）：没完成、到点、道里前面没有没完成的、settle 的 started 已完成。
--   ★settle 比 started 先写（id 更小）时 started 不被它挡（否则两条互等，谁也发不出去）。
--   领到的 next_at 推后 p_lease_sec 秒当租期（发送方中途挂了 ⇒ 租期过后重发；主站各接口按 raidId / userId 幂等）。
--   返回 jsonb 数组，按 id 升序。
create or replace function public.mainsite_outbox_claim(p_limit int default 20, p_lease_sec int default 120)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_out jsonb;
begin
  with c as (
    select o.id from public.mainsite_outbox o
     where o.done_at is null and o.next_at <= now()
       and not exists (select 1 from public.mainsite_outbox e
                        where e.done_at is null and e.id < o.id
                          and public.mainsite_outbox_lane(e.topic, e.body) = public.mainsite_outbox_lane(o.topic, o.body)
                          and not (o.topic = 'started' and e.topic = 'settle'))
       and not (o.topic = 'settle' and exists (select 1 from public.mainsite_outbox s
                        where s.topic = 'started' and s.done_at is null and s.body->>'raidId' = o.body->>'raidId'))
     order by o.id
     limit greatest(1, least(coalesce(p_limit, 20), 100))
     for update skip locked
  ), u as (
    update public.mainsite_outbox o
       set next_at = now() + make_interval(secs => greatest(10, coalesce(p_lease_sec, 120)))
      from c where o.id = c.id
    returning o.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'topic', u.topic, 'idem_key', u.idem_key,
                                               'body', u.body, 'attempts', u.attempts) order by u.id), '[]'::jsonb)
    into v_out from u;
  return v_out;
end $$;
revoke all on function public.mainsite_outbox_claim(int, int) from public, anon, authenticated;
grant execute on function public.mainsite_outbox_claim(int, int) to service_role;

-- 记一次发送结果（outbox_loop 调）。p_retry_sec 为空 ⇒ 终态（成功，或 HTTP 200 + ok:false）：done_at = now()；
--   否则（连不上 / 5xx / 401）attempts + 1、next_at = now() + p_retry_sec。回包整个存进 reply（started 的回包带新 expireAt）。
create or replace function public.mainsite_outbox_mark(p_id bigint, p_status text, p_reply jsonb, p_retry_sec int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.mainsite_outbox
     set attempts = attempts + 1,
         last_status = left(coalesce(p_status, ''), 300),
         reply = coalesce(p_reply, reply),
         done_at = case when p_retry_sec is null then now() else null end,
         next_at = case when p_retry_sec is null then next_at
                        else now() + make_interval(secs => greatest(1, least(p_retry_sec, 3600))) end
   where id = p_id and done_at is null;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n = 1, 'done', p_retry_sec is null);
end $$;
revoke all on function public.mainsite_outbox_mark(bigint, text, jsonb, int) from public, anon, authenticated;
grant execute on function public.mainsite_outbox_mark(bigint, text, jsonb, int) to service_role;

-- ═══ ② 登录码（网关调）═══
-- App 点「龟投账号登录」→ 网关生成随机码（Python secrets）→ 本函数登记。同一个号同时只有一个有效码（新码作废旧码）；
--   每号每小时最多 30 个（防刷）。码 5 分钟过期。
create or replace function public.mainsite_link_start(p_account uuid, p_code text, p_device text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_account is null or not exists (select 1 from auth.users where id = p_account) then
    return jsonb_build_object('ok', false, 'error', 'no_account');
  end if;
  if p_code is null or p_code !~ '^[A-Za-z0-9_-]{4,64}$' then
    return jsonb_build_object('ok', false, 'error', 'bad_code');
  end if;
  perform pg_advisory_xact_lock(hashtext('mainsite_link_start:' || p_account::text));
  delete from public.mainsite_codes where created_at < now() - interval '1 day';
  select count(*) into n from public.mainsite_codes where account_id = p_account and created_at > now() - interval '1 hour';
  if n >= 30 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  update public.mainsite_codes set expires_at = now()
   where account_id = p_account and confirmed_at is null and expires_at > now();
  insert into public.mainsite_codes (code, account_id, device, expires_at)
    values (p_code, p_account, left(btrim(coalesce(p_device, '')), 128), now() + interval '5 minutes')
    on conflict (code) do nothing;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'code_taken');
  end if;
  return jsonb_build_object('ok', true, 'code', p_code, 'expires_in', 300);
end $$;
revoke all on function public.mainsite_link_start(uuid, text, text) from public, anon, authenticated;
grant execute on function public.mainsite_link_start(uuid, text, text) to service_role;

-- 主站确认页查设备型号（主站 GET /mainsite/link/info）。码不对 / 过期 / 已用 ⇒ ok:false（主站一律当「登录码无效」）。
create or replace function public.mainsite_link_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d text;
begin
  select device into d from public.mainsite_codes
   where code = p_code and confirmed_at is null and expires_at > now();
  if not found then
    return jsonb_build_object('ok', false, 'error', 'bad_code');
  end if;
  return jsonb_build_object('ok', true, 'device', d);
end $$;
revoke all on function public.mainsite_link_info(text) from public, anon, authenticated;
grant execute on function public.mainsite_link_info(text) to service_role;

-- 主站确认登录（主站 POST /mainsite/link/confirm {code, user_id}）。
--   这个主站用户已绑在这个号上 ⇒ same；绑在别的号上 ⇒ switched（App 轮询时网关签那个号的登录态）；
--   还没绑 ⇒ 绑到这个号（bound）；这个号原先绑着另一个主站用户 ⇒ 改绑（rebound，旧的那个发 unlinked）。
--   ★一次性：同一个码只能确认一次；主站重试（同一个 user_id 再来一次）回同一个结果，换个 user_id ⇒ ok:false。
create or replace function public.mainsite_link_confirm(p_code text, p_user_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; tgt uuid; cur text; res text;
begin
  if p_user_id is null or p_user_id !~ '^[0-9A-Za-z]{4,32}$' or p_user_id ~ '^[0-9]+$' then
    return jsonb_build_object('ok', false, 'error', 'bad userId');
  end if;
  select * into c from public.mainsite_codes where code = p_code for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'bad_code');
  end if;
  if c.confirmed_at is not null then
    if c.mainsite_user_id = p_user_id then
      return jsonb_build_object('ok', true, 'result', c.result);
    end if;
    return jsonb_build_object('ok', false, 'error', 'code_used');
  end if;
  if c.expires_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'expired');
  end if;
  -- 同一个主站用户 / 同一个号的并发确认串行化
  perform pg_advisory_xact_lock(hashtext('mainsite_user:' || p_user_id));
  perform pg_advisory_xact_lock(hashtext('mainsite_account:' || c.account_id::text));
  select account_id into tgt from public.mainsite_accounts where mainsite_user_id = p_user_id;
  if tgt is not null and tgt = c.account_id then
    res := 'same';
  elsif tgt is not null then
    res := 'switched';
  else
    insert into public.accounts (account_id) values (c.account_id) on conflict (account_id) do nothing;
    select mainsite_user_id into cur from public.mainsite_accounts where account_id = c.account_id;
    if cur is not null then
      update public.mainsite_accounts set mainsite_user_id = p_user_id, linked_at = now(), pets_fetched_at = null
       where account_id = c.account_id;
      delete from public.mainsite_pets where account_id = c.account_id;
      perform public.mainsite_outbox_put('unlinked', 'rebind:' || c.account_id::text || ':' || cur || ':' || p_code,
                                         jsonb_build_object('userId', cur));
      res := 'rebound';
    else
      insert into public.mainsite_accounts (account_id, mainsite_user_id) values (c.account_id, p_user_id);
      res := 'bound';
    end if;
    tgt := c.account_id;
    -- 他刚又绑上了：之前删号留下的、还没发出去的 unlinked 作废
    update public.mainsite_outbox set done_at = now(), last_status = 'superseded'
     where topic = 'unlinked' and done_at is null and body->>'userId' = p_user_id;
  end if;
  update public.mainsite_codes
     set confirmed_at = now(), mainsite_user_id = p_user_id, result = res, target_account = tgt
   where code = p_code;
  return jsonb_build_object('ok', true, 'result', res);
end $$;
revoke all on function public.mainsite_link_confirm(text, text) from public, anon, authenticated;
grant execute on function public.mainsite_link_confirm(text, text) to service_role;

-- App 轮询（网关 POST /app/link/poll 调）：只有发起这个码的号能查。
--   status：pending（等确认）/ confirmed / expired（没确认就过了 5 分钟，或确认后又过了 5 分钟还没来取）。
--   switched = true 时带 target_account（网关拿它签登录态，不原样转给 App）。
create or replace function public.mainsite_link_poll(p_account uuid, p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  select * into c from public.mainsite_codes where code = p_code and account_id = p_account;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'bad_code');
  end if;
  if c.confirmed_at is null then
    return jsonb_build_object('ok', true, 'status', case when c.expires_at <= now() then 'expired' else 'pending' end,
                              'switched', false);
  end if;
  if c.confirmed_at <= now() - interval '5 minutes' then
    return jsonb_build_object('ok', true, 'status', 'expired', 'switched', false);
  end if;
  if c.result = 'switched' and c.target_account is null then
    return jsonb_build_object('ok', false, 'error', 'target_gone');
  end if;
  return jsonb_build_object('ok', true, 'status', 'confirmed', 'switched', c.result = 'switched', 'result', c.result,
                            'user_id', c.mainsite_user_id)
      || case when c.result = 'switched' then jsonb_build_object('target_account', c.target_account) else '{}'::jsonb end;
end $$;
revoke all on function public.mainsite_link_poll(uuid, text) from public, anon, authenticated;
grant execute on function public.mainsite_link_poll(uuid, text) to service_role;

-- ═══ ③ 拥有龟（网关 / App）═══
-- {ok, linked, user_id, owned: [pet_key…], fetched_at}。没绑 ⇒ linked:false、owned:[]。
create or replace function public.mainsite_status(p_account uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a record; ow jsonb;
begin
  select * into a from public.mainsite_accounts where account_id = p_account;
  if not found then
    return jsonb_build_object('ok', true, 'linked', false, 'user_id', null, 'owned', '[]'::jsonb, 'fetched_at', null);
  end if;
  select coalesce(jsonb_agg(pet_key order by pet_key), '[]'::jsonb) into ow from public.mainsite_pets where account_id = p_account;
  return jsonb_build_object('ok', true, 'linked', true, 'user_id', a.mainsite_user_id, 'owned', ow,
                            'fetched_at', a.pets_fetched_at);
end $$;
revoke all on function public.mainsite_status(uuid) from public, anon, authenticated;
grant execute on function public.mainsite_status(uuid) to service_role;

-- App 用：查自己（auth.uid()）。
create or replace function public.mainsite_me()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in', 'linked', false, 'user_id', null,
                              'owned', '[]'::jsonb, 'fetched_at', null);
  end if;
  return public.mainsite_status(uid);
end $$;
revoke all on function public.mainsite_me() from public;
revoke execute on function public.mainsite_me() from anon;
grant execute on function public.mainsite_me() to authenticated;

-- 网关刷新拥有龟（主站 /player 成功之后）：整份替换。p_user_id = 网关调 /player 时用的主站用户；
--   这期间改绑了（绑定的已不是他）⇒ 不写，回 relinked。不合格式的 pet_key 跳过。
create or replace function public.mainsite_pets_put(p_account uuid, p_user_id text, p_keys jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare keys text[];
begin
  if not exists (select 1 from public.mainsite_accounts where account_id = p_account) then
    return jsonb_build_object('ok', false, 'error', 'not_linked');
  end if;
  if not exists (select 1 from public.mainsite_accounts where account_id = p_account and mainsite_user_id = p_user_id) then
    return jsonb_build_object('ok', false, 'error', 'relinked');
  end if;
  if p_keys is null or jsonb_typeof(p_keys) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'bad_keys');
  end if;
  select coalesce(array_agg(distinct k), '{}') into keys
    from jsonb_array_elements_text(p_keys) k where k ~ '^[a-z0-9_]{1,32}$';
  delete from public.mainsite_pets where account_id = p_account and pet_key <> all(keys);
  insert into public.mainsite_pets (account_id, pet_key, fetched_at)
    select p_account, k, now() from unnest(keys) k
    on conflict (account_id, pet_key) do update set fetched_at = excluded.fetched_at;
  update public.mainsite_accounts set pets_fetched_at = now() where account_id = p_account;
  return public.mainsite_status(p_account);
end $$;
revoke all on function public.mainsite_pets_put(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.mainsite_pets_put(uuid, text, jsonb) to service_role;

-- ═══ ⑥ 删号（以 20261020b 版为底；只多「已绑定 ⇒ 写 unlinked 发件箱」一段，在删 auth.users 之前）═══
create or replace function public.account_delete_self() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  uid   uuid := auth.uid();
  tags  text[];
  ph    jsonb;
  n_m   int := 0; n_l int := 0; n_j int := 0; n_f int := 0; tmp_n int;
  ms_uid text;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  -- 我用过的玩家 ID：按账号算的那一个 + 我上传过的快照里实际带着的（老客户端曾按安装号算）
  select coalesce(array_agg(distinct t), '{}') into tags from (
    select public.player_tag_of(uid::text) as t
    union select snapshot->'profile'->>'tag' from public.ghosts where account_id = uid
    union select snapshot->'profile'->>'tag' from public.gauntlet_ghosts where account_id = uid
    union select left_snapshot->'profile'->>'tag' from public.matches where left_account = uid
    union select left_snapshot->'profile'->>'tag' from public.live_matches where account_id = uid
    union select snapshot->'profile'->>'tag' from public.finals_entrants where account_id = uid
    union select snapshot->'profile'->>'tag' from public.finals_pending where account_id = uid
    union select a_snapshot->'profile'->>'tag' from public.referee_jobs where a_account = uid
    union select b_snapshot->'profile'->>'tag' from public.referee_jobs where b_account = uid
  ) s where t is not null and t <> '';

  ph := jsonb_build_object('name', '已注销玩家', 'avatar', 'basic', 'id', 'deleted',
                           'tag', public.player_tag_of(gen_random_uuid()::text));

  update public.matches set left_snapshot = public.profile_scrub(left_snapshot, ph)
   where left_account = uid or left_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_m := n_m + tmp_n;
  update public.matches set right_snapshot = public.profile_scrub(right_snapshot, ph)
   where right_account = uid or right_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_m := n_m + tmp_n;

  update public.live_matches set left_snapshot = public.profile_scrub(left_snapshot, ph)
   where account_id <> uid and left_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_l := n_l + tmp_n;
  update public.live_matches set right_snapshot = public.profile_scrub(right_snapshot, ph)
   where account_id <> uid and right_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_l := n_l + tmp_n;

  -- 我自己还没算完的周六任务：作废（只有我一个人在等它的结果）
  update public.referee_jobs set status = 'failed', error = 'account_deleted', done_at = now(),
         claimed_by = null, claimed_at = null
   where kind = 'gauntlet' and a_account = uid and status in ('pending', 'claimed');
  update public.referee_jobs set a_snapshot = public.profile_scrub(a_snapshot, ph), meta = meta - 'account'
   where a_account = uid or a_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_j := n_j + tmp_n;
  update public.referee_jobs set b_snapshot = public.profile_scrub(b_snapshot, ph)
   where b_account = uid or b_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_j := n_j + tmp_n;

  update public.finals_entrants set name = ph->>'name', snapshot = public.profile_scrub(snapshot, ph)
   where account_id = uid;
  get diagnostics n_f = row_count;

  update public.referee_restream set requested_by = null where requested_by = uid;

  delete from public.nickname_reports
   where reporter = uid or reported_account = uid or reported_tag = any(tags);

  -- 2026-11-09a：绑过龟投账号 ⇒ 发件箱写 unlinked（主站解绑、停止推荐；主站账号和金库保留）。没绑 ⇒ 不写。
  --   mainsite_accounts / mainsite_pets 随下面删 auth.users 一路 cascade 掉。
  select mainsite_user_id into ms_uid from public.mainsite_accounts where account_id = uid;
  if ms_uid is not null then
    perform public.mainsite_outbox_put('unlinked', 'del:' || uid::text, jsonb_build_object('userId', ms_uid));
  end if;

  -- 其余表（accounts / ghosts / gauntlet_ghosts / saves / standings / finals_pending / finals_scout /
  --   live_matches 我自己的行 / gauntlet_records / client_errors / player_feedback / nickname_resets）随 cascade 删；
  --   matches.left/right_account、referee_jobs.a/b_account、finals_entrants.account_id 随 set null 断开。
  delete from auth.users where id = uid;

  return jsonb_build_object('ok', true, 'scrubbed',
    jsonb_build_object('matches', n_m, 'live', n_l, 'jobs', n_j, 'finals', n_f));
end $$;
revoke all on function public.account_delete_self() from public;
revoke execute on function public.account_delete_self() from anon;
grant execute on function public.account_delete_self() to authenticated;

-- 上线后回读（memory：`revoke from public` 收不掉 anon 的默认授权，必须逐个看）：
--   select p.proname, r.rolname, has_function_privilege(r.rolname, p.oid, 'execute')
--     from pg_proc p cross join (values ('anon'), ('authenticated'), ('service_role')) r(rolname)
--    where p.pronamespace = 'public'::regnamespace and p.proname like 'mainsite%';
--   期望：anon 全 false；authenticated 只有 mainsite_me true；service_role 除 mainsite_me / mainsite_outbox_lane 外全 true。
-- <<< END mainsite_core 20261109a <<<
