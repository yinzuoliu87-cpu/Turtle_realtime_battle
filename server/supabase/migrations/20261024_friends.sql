-- >>> BEGIN friends 20261024 >>>
-- ─────────────────────────────────────────────────────────────
-- 好友 + 切磋（2026-10-24 · 方案书 docs/plans/20261023-好友切磋.md §4.1）
--   用户 2026-10-23「接下来新任务，好友系统，主要实现切磋 … 切磋是当前的背包阵容vs好友的最新背包阵容」
--   用户拍板：加好友 = 双方同意；好友上限 100；切磋不进战绩（切磋本身不碰服务端，见 scripts/systems/social/spar.gd）。
--   客户端：scripts/net/friends_net.gd（调下面这几个 RPC）· scripts/scenes/FriendsScene.gd（好友页）。
--
-- 本文件做四件事：
--   ① lineups：每人一行「最新背包阵容」+ 服务端算的玩家 ID（按 ID 找人只查这张表）
--      ★为什么另建表：ghosts 只在积分赛结算那一刻传、每周二清，没有「最新背包阵容」（方案书 §2.2）
--      ★为什么不在 accounts 上加 tag：开机就写 accounts 会让所有号都「有数据」，垃圾匿名号清理（purge_junk_anon_users）
--        就再也清不掉测试机造的号 —— lineups 只在玩家真的配过阵容 / 打开过好友页时才有
--   ② friendships：好友关系（a < b 一行；pending / accepted / declined）
--   ③ RPC：put_lineup / friend_lookup / friend_request / friend_respond / friend_remove / friend_list / friend_lineup
--   ④ 垃圾匿名号清理 / 昵称举报处理补上新表（删号不用改：两张表都随 auth.users on delete cascade）
--
-- ★两张表都开 RLS、不建 policy、revoke ⇒ 客户端直连读写一律被拒，只走 security definer 函数。
-- ★好友的阵容只对好友可读（friend_lineup 先验关系是 accepted）。按 ID 查人只回昵称 + 头像，不回阵容。
-- ★被拒的申请不删、记成 declined：同一个人 30 天内再申请 ⇒ 回「已申请」但什么都不发（防反复骚扰；对方看不到）。
--   对方之后主动来申请 ⇒ 照常成立。
-- ★本文件只建表 / 建函数 / 重定义两个函数，不删任何已有数据。重复执行安全。
-- ★上线前先跑 server/supabase/tests/20261024_friends_check.sql（整段一个事务，结尾一定抛异常 ⇒ 回滚）。
-- ─────────────────────────────────────────────────────────────

-- ═══ ① 最新阵容 ═══
create table if not exists public.lineups (
  account_id     uuid        primary key references auth.users(id) on delete cascade,
  tag            text        not null,                       -- player_tag_of(account_id)：服务端算，不信客户端
  name           text        not null default '' check (char_length(name) <= 40),
  snapshot       jsonb       not null default '{}'::jsonb,  -- Backend.build_ghost_snapshot() 的产物；{} = 还没配阵容
  rules_ver      int         not null default 0,
  client_version text        not null default '' check (char_length(client_version) <= 32),
  updated_at     timestamptz not null default now()
);
create index if not exists lineups_tag_idx on public.lineups (tag);
alter table public.lineups enable row level security;
revoke all on public.lineups from anon, authenticated, public;

-- ═══ ② 好友关系 ═══
create table if not exists public.friendships (
  a           uuid        not null references auth.users(id) on delete cascade,
  b           uuid        not null references auth.users(id) on delete cascade,
  requester   uuid        not null,
  status      text        not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at  timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (a, b),
  check (a < b),
  check (requester = a or requester = b)
);
create index if not exists friendships_b_idx on public.friendships (b);
alter table public.friendships enable row level security;
revoke all on public.friendships from anon, authenticated, public;

-- 一份快照的头像 = 第一只统领；老快照 / 空快照退回 profile.avatar；都没有 ⇒ ''。
create or replace function public.snapshot_lead(p_snap jsonb) returns text
language sql immutable as $$
  select coalesce(nullif(case when jsonb_typeof(p_snap -> 'leaders') = 'array' then p_snap -> 'leaders' ->> 0 end, ''),
                  nullif(p_snap -> 'profile' ->> 'avatar', ''), '')
$$;
revoke all on function public.snapshot_lead(jsonb) from public, anon, authenticated;

-- 一行好友 / 申请给客户端看的样子（对方那一侧）。
create or replace function public.friend_card(p_other uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'account', p_other,
    'tag', public.player_tag_of(p_other::text),
    'name', coalesce(l.name, ''),
    'lead', coalesce(public.snapshot_lead(l.snapshot), ''),
    'has_lineup', coalesce(l.snapshot ? 'leaders', false),
    'updated_at', l.updated_at)
  from (select 1) one left join public.lineups l on l.account_id = p_other
$$;
revoke all on function public.friend_card(uuid) from public, anon, authenticated;

-- ═══ ③ RPC ═══

-- 传我的最新阵容（离开背包 / 打开好友页 / 出战时；客户端只在阵容有变化时传）。
-- p_snapshot = {} 也收（还没配阵容的人也要能被按 ID 找到）。上限 64 KB（真实快照约 5~15 KB）。
-- 返回 {ok:true, tag} 或 {ok:false, reason: not_signed_in | bad_snapshot | too_big}。
create or replace function public.put_lineup(p_name text, p_snapshot jsonb, p_rules_ver int, p_client_version text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); tg text;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  if octet_length(p_snapshot::text) > 65536 then
    return jsonb_build_object('ok', false, 'reason', 'too_big');
  end if;
  tg := public.player_tag_of(uid::text);
  insert into public.lineups as t (account_id, tag, name, snapshot, rules_ver, client_version, updated_at)
    values (uid, tg, left(btrim(coalesce(p_name, '')), 40), p_snapshot, coalesce(p_rules_ver, 0),
            left(coalesce(p_client_version, ''), 32), now())
  on conflict (account_id) do update
    set tag = excluded.tag, name = excluded.name, snapshot = excluded.snapshot,
        rules_ver = excluded.rules_ver, client_version = excluded.client_version, updated_at = now();
  return jsonb_build_object('ok', true, 'tag', tg);
end $$;

-- 按玩家 ID 找人（玩家 ID 不唯一：1 万人约 0.1 对撞号 ⇒ 可能回多个，客户端让玩家按昵称挑）。最多 5 个，不含自己。
-- 返回 {ok:true, people:[friend_card…]} 或 {ok:false, reason: not_signed_in | bad_tag | self | not_found}。
create or replace function public.friend_lookup(p_tag text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); ppl jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_tag is null or p_tag !~ '^#[23456789BCDFGHJKMNPQRSTVWXYZ]{6}$' then
    return jsonb_build_object('ok', false, 'reason', 'bad_tag');
  end if;
  select coalesce(jsonb_agg(public.friend_card(x.account_id) order by x.updated_at desc), '[]'::jsonb) into ppl
    from (select account_id, updated_at from public.lineups
           where tag = p_tag and account_id <> uid order by updated_at desc limit 5) x;
  if jsonb_array_length(ppl) = 0 then
    return jsonb_build_object('ok', false,
      'reason', case when p_tag = public.player_tag_of(uid::text) then 'self' else 'not_found' end);
  end if;
  return jsonb_build_object('ok', true, 'people', ppl);
end $$;

-- 申请加好友（p_other 来自 friend_lookup 的 account）。对方已经申请过我 ⇒ 直接成为好友。
-- 返回 {ok:true, status: pending | accepted} 或
--   {ok:false, reason: not_signed_in | self | not_found | already | full | their_full | limit}。
create or replace function public.friend_request(p_other uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  lo uuid; hi uuid;
  fr public.friendships%rowtype;
  had boolean;
  n int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_other is null or p_other = uid then
    return jsonb_build_object('ok', false, 'reason', 'self');
  end if;
  if not exists (select 1 from public.lineups where account_id = p_other) then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  lo := least(uid, p_other); hi := greatest(uid, p_other);
  perform pg_advisory_xact_lock(hashtext('friend:' || lo::text || hi::text));
  select * into fr from public.friendships where a = lo and b = hi;
  had := found;                 -- ★下面的 select count(*) into 会把 found 重置成真, 先存下来
  if had and fr.status = 'accepted' then
    return jsonb_build_object('ok', false, 'reason', 'already');
  end if;
  if had and fr.requester = uid then
    return jsonb_build_object('ok', true, 'status', 'pending');   -- 已申请过（含被拒：对方看不到, 不再打扰）
  end if;
  -- 好友上限 100（双方各自数 accepted）
  select count(*) into n from public.friendships where (a = uid or b = uid) and status = 'accepted';
  if n >= 100 then
    return jsonb_build_object('ok', false, 'reason', 'full');
  end if;
  if had and fr.status = 'pending' then
    -- 对方已经申请过我 ⇒ 这次申请就是同意
    select count(*) into n from public.friendships where (a = p_other or b = p_other) and status = 'accepted';
    if n >= 100 then
      return jsonb_build_object('ok', false, 'reason', 'their_full');
    end if;
    update public.friendships set status = 'accepted', accepted_at = now() where a = lo and b = hi;
    return jsonb_build_object('ok', true, 'status', 'accepted');
  end if;
  -- 每人 24 小时最多发 30 个申请
  select count(*) into n from public.friendships where requester = uid and created_at > now() - interval '24 hours';
  if n >= 30 then
    return jsonb_build_object('ok', false, 'reason', 'limit');
  end if;
  if had then
    -- 走到这里 = 对方以前申请过我、被我拒了（fr.requester = 对方, declined），现在我主动来加 ⇒ 改成我发出的申请
    update public.friendships set requester = uid, status = 'pending', created_at = now(), accepted_at = null
     where a = lo and b = hi;
  else
    insert into public.friendships (a, b, requester) values (lo, hi, uid);
  end if;
  return jsonb_build_object('ok', true, 'status', 'pending');
end $$;

-- 回应别人发给我的申请：同意 ⇒ accepted；拒绝 ⇒ declined（对方看到的仍是「等待对方同意」）。
-- 返回 {ok:true, status: accepted | declined} 或 {ok:false, reason: not_signed_in | not_found | full | their_full}。
create or replace function public.friend_respond(p_other uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); lo uuid; hi uuid; n int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_other is null or p_other = uid then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  lo := least(uid, p_other); hi := greatest(uid, p_other);
  perform pg_advisory_xact_lock(hashtext('friend:' || lo::text || hi::text));
  if not exists (select 1 from public.friendships
                  where a = lo and b = hi and requester = p_other and status = 'pending') then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if not coalesce(p_accept, false) then
    update public.friendships set status = 'declined' where a = lo and b = hi;
    return jsonb_build_object('ok', true, 'status', 'declined');
  end if;
  select count(*) into n from public.friendships where (a = uid or b = uid) and status = 'accepted';
  if n >= 100 then
    return jsonb_build_object('ok', false, 'reason', 'full');
  end if;
  select count(*) into n from public.friendships where (a = p_other or b = p_other) and status = 'accepted';
  if n >= 100 then
    return jsonb_build_object('ok', false, 'reason', 'their_full');
  end if;
  update public.friendships set status = 'accepted', accepted_at = now() where a = lo and b = hi;
  return jsonb_build_object('ok', true, 'status', 'accepted');
end $$;

-- 删好友 / 撤回我发出的申请。拒绝过的那一行（对方发给我、我拒了）不删 —— 删了对方就能立刻再发。
-- 返回 {ok:true} 或 {ok:false, reason: not_signed_in | not_found}。
create or replace function public.friend_remove(p_other uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  delete from public.friendships
   where a = least(uid, p_other) and b = greatest(uid, p_other)
     and (status = 'accepted' or (requester = uid and status = 'pending'));
  get diagnostics n = row_count;
  if n = 0 then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- 好友页一次拿全：我的玩家 ID、好友、别人发给我的申请、我发出的申请（被拒的也照样显示「等待对方同意」）。
create or replace function public.friend_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); fr jsonb; inc jsonb; outg jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select coalesce(jsonb_agg(public.friend_card(case when f.a = uid then f.b else f.a end) order by f.accepted_at desc), '[]'::jsonb)
    into fr from public.friendships f where (f.a = uid or f.b = uid) and f.status = 'accepted';
  select coalesce(jsonb_agg(public.friend_card(f.requester) order by f.created_at desc), '[]'::jsonb)
    into inc from public.friendships f where (f.a = uid or f.b = uid) and f.status = 'pending' and f.requester <> uid;
  select coalesce(jsonb_agg(public.friend_card(case when f.a = uid then f.b else f.a end) order by f.created_at desc), '[]'::jsonb)
    into outg from public.friendships f where f.requester = uid and f.status in ('pending', 'declined');
  return jsonb_build_object('ok', true, 'tag', public.player_tag_of(uid::text),
    'friends', fr, 'incoming', inc, 'outgoing', outg, 'cap', 100);
end $$;

-- 切磋：取好友的最新阵容。★先验双方是好友（accepted）。
-- lineups 里还没有阵容（{}）⇒ 退回对方最新一行积分赛快照（ghosts）；都没有 ⇒ no_lineup。
-- 返回 {ok:true, name, tag, snapshot, rules_ver, client_version, updated_at, source: lineup | ghost}
--   或 {ok:false, reason: not_signed_in | not_friends | no_lineup}。
create or replace function public.friend_lineup(p_other uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); l public.lineups%rowtype; g record;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_other is null or not exists (select 1 from public.friendships
       where a = least(uid, p_other) and b = greatest(uid, p_other) and status = 'accepted') then
    return jsonb_build_object('ok', false, 'reason', 'not_friends');
  end if;
  select * into l from public.lineups where account_id = p_other;
  if found and l.snapshot ? 'leaders' then
    return jsonb_build_object('ok', true, 'source', 'lineup', 'name', l.name, 'tag', l.tag,
      'snapshot', l.snapshot, 'rules_ver', l.rules_ver, 'client_version', l.client_version, 'updated_at', l.updated_at);
  end if;
  select snapshot, rules_ver, client_version, uploaded_at into g from public.ghosts
   where account_id = p_other order by uploaded_at desc limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_lineup');
  end if;
  return jsonb_build_object('ok', true, 'source', 'ghost',
    'name', coalesce(nullif(l.name, ''), g.snapshot -> 'profile' ->> 'name', ''),
    'tag', public.player_tag_of(p_other::text),
    'snapshot', g.snapshot, 'rules_ver', g.rules_ver, 'client_version', g.client_version, 'updated_at', g.uploaded_at);
end $$;

revoke all on function public.put_lineup(text, jsonb, int, text) from public;
revoke all on function public.friend_lookup(text) from public;
revoke all on function public.friend_request(uuid) from public;
revoke all on function public.friend_respond(uuid, boolean) from public;
revoke all on function public.friend_remove(uuid) from public;
revoke all on function public.friend_list() from public;
revoke all on function public.friend_lineup(uuid) from public;
revoke execute on function public.put_lineup(text, jsonb, int, text) from anon;
revoke execute on function public.friend_lookup(text) from anon;
revoke execute on function public.friend_request(uuid) from anon;
revoke execute on function public.friend_respond(uuid, boolean) from anon;
revoke execute on function public.friend_remove(uuid) from anon;
revoke execute on function public.friend_list() from anon;
revoke execute on function public.friend_lineup(uuid) from anon;
grant execute on function public.put_lineup(text, jsonb, int, text) to authenticated;
grant execute on function public.friend_lookup(text) to authenticated;
grant execute on function public.friend_request(uuid) to authenticated;
grant execute on function public.friend_respond(uuid, boolean) to authenticated;
grant execute on function public.friend_remove(uuid) to authenticated;
grant execute on function public.friend_list() to authenticated;
grant execute on function public.friend_lineup(uuid) to authenticated;

-- ═══ ④ 补新表 ═══
-- 垃圾匿名号清理：有阵容行 / 有好友关系的号不算「没数据」（只打切磋、不打积分赛的人也是真人）。
create or replace function public.purge_junk_anon_users() returns integer
language plpgsql security definer set search_path = public, auth as $$
declare n integer;
begin
  delete from auth.users u
  where u.is_anonymous and coalesce(u.email, '') = ''
    and coalesce(u.last_sign_in_at, u.created_at) < now() - interval '14 days'
    and not exists (select 1 from public.ghosts x where x.account_id = u.id)
    and not exists (select 1 from public.gauntlet_ghosts x where x.account_id = u.id)
    and not exists (select 1 from public.saves x where x.account_id = u.id)
    and not exists (select 1 from public.standings x where x.account_id = u.id)
    and not exists (select 1 from public.matches x where x.left_account = u.id or x.right_account = u.id)
    and not exists (select 1 from public.finals_entrants x where x.account_id = u.id)
    and not exists (select 1 from public.finals_pending x where x.account_id = u.id)
    and not exists (select 1 from public.finals_scout x where x.account_id = u.id)
    and not exists (select 1 from public.accounts x where x.account_id = u.id)
    and not exists (select 1 from public.lineups x where x.account_id = u.id)
    and not exists (select 1 from public.friendships x where x.a = u.id or x.b = u.id);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.purge_junk_anon_users() from public, anon, authenticated;

-- 昵称举报处理：重置时阵容行里的名字也换成占位（否则好友列表 / 按 ID 查人还显示原名，直到对方下次传阵容）。
--   其余与 20261020b 逐字相同（只在 accounts 那一句之前插了 lineups 两句）。
create or replace function public.nickname_report_resolve(p_tag text, p_action text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  acc    uuid;
  names  text[];
  ph     text := '玩家' || substr(coalesce(p_tag, ''), 2);
  n      int := 0; tmp_n int;
begin
  if p_action not in ('reset', 'dismiss') then
    return jsonb_build_object('ok', false, 'reason', 'bad_action');
  end if;
  select coalesce(array_agg(distinct name_snapshot), '{}'),
         (array_agg(reported_account) filter (where reported_account is not null))[1]
    into names, acc
    from public.nickname_reports where reported_tag = p_tag and status = 'pending';
  if cardinality(names) = 0 then
    return jsonb_build_object('ok', false, 'reason', 'nothing_pending');
  end if;
  if acc is null then
    select account_id into acc from public.ghosts
     where snapshot->'profile'->>'tag' = p_tag order by uploaded_at desc limit 1;
  end if;
  if p_action = 'dismiss' or acc is null then
    update public.nickname_reports set status = 'dismissed', handled_at = now()
     where reported_tag = p_tag and status = 'pending';
    return jsonb_build_object('ok', true, 'action', 'dismiss',
      'reason', case when acc is null and p_action = 'reset' then 'no_account' end, 'names', to_jsonb(names));
  end if;
  insert into public.nickname_resets (account_id, banned_name)
    select acc, x from unnest(names) x on conflict do nothing;
  -- 服务端已存的名字换成占位（只换 profile.name 恰好是被举报的那几个的行；之后上传的是客户端换好的默认昵称）
  update public.ghosts set snapshot = jsonb_set(snapshot, '{profile,name}', to_jsonb(ph))
   where account_id = acc and snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.gauntlet_ghosts set snapshot = jsonb_set(snapshot, '{profile,name}', to_jsonb(ph))
   where account_id = acc and snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.matches set left_snapshot = jsonb_set(left_snapshot, '{profile,name}', to_jsonb(ph))
   where left_snapshot->'profile'->>'tag' = p_tag and left_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.matches set right_snapshot = jsonb_set(right_snapshot, '{profile,name}', to_jsonb(ph))
   where right_snapshot->'profile'->>'tag' = p_tag and right_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.live_matches set left_snapshot = jsonb_set(left_snapshot, '{profile,name}', to_jsonb(ph))
   where left_snapshot->'profile'->>'tag' = p_tag and left_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.live_matches set right_snapshot = jsonb_set(right_snapshot, '{profile,name}', to_jsonb(ph))
   where right_snapshot->'profile'->>'tag' = p_tag and right_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.referee_jobs set a_snapshot = jsonb_set(a_snapshot, '{profile,name}', to_jsonb(ph))
   where a_snapshot->'profile'->>'tag' = p_tag and a_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.referee_jobs set b_snapshot = jsonb_set(b_snapshot, '{profile,name}', to_jsonb(ph))
   where b_snapshot->'profile'->>'tag' = p_tag and b_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.finals_entrants set name = ph,
         snapshot = case when snapshot->'profile'->>'name' = any(names)
                         then jsonb_set(snapshot, '{profile,name}', to_jsonb(ph)) else snapshot end
   where account_id = acc and name = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.finals_pending set name = ph,
         snapshot = case when snapshot->'profile'->>'name' = any(names)
                         then jsonb_set(snapshot, '{profile,name}', to_jsonb(ph)) else snapshot end
   where account_id = acc and name = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.lineups set name = ph where account_id = acc and name = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.lineups set snapshot = jsonb_set(snapshot, '{profile,name}', to_jsonb(ph))
   where account_id = acc and snapshot->'profile'->>'name' = any(names);
  update public.accounts set display_name = ph where account_id = acc and display_name = any(names);
  update public.nickname_reports set status = 'reset', handled_at = now()
   where reported_tag = p_tag and status = 'pending';
  return jsonb_build_object('ok', true, 'action', 'reset', 'account', acc, 'names', to_jsonb(names), 'scrubbed', n);
end $$;
revoke all on function public.nickname_report_resolve(text, text) from public, anon, authenticated;
grant execute on function public.nickname_report_resolve(text, text) to service_role;

-- 上线后回读（memory：`revoke from public` 收不掉 anon 的默认授权，必须逐个看）：
--   select p.proname, r.rolname, has_function_privilege(r.rolname, p.oid, 'execute')
--     from pg_proc p cross join (values ('anon'), ('authenticated'), ('service_role')) r(rolname)
--    where p.pronamespace = 'public'::regnamespace
--      and p.proname in ('put_lineup', 'friend_lookup', 'friend_request', 'friend_respond', 'friend_remove',
--                        'friend_list', 'friend_lineup', 'friend_card', 'snapshot_lead');
--   期望：anon 全 false；authenticated 前七个 true、friend_card / snapshot_lead false。
-- <<< END friends 20261024 <<<
