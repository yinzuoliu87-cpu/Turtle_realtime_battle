-- >>> BEGIN account_delete_and_reports 20261020b >>>
-- ─────────────────────────────────────────────────────────────
-- 应用内删除账号 + 昵称举报（2026-10-20 · 方案书 docs/plans/20261020-AppStore上架.md §4.2 / D8）
--   上架硬要求：App Store 审核指南 5.1.1(v)「支持建号就必须能在 App 内删号」（游客号同样适用）；
--   1.2「用户生成内容」要有举报 + 屏蔽。屏蔽（拉黑）只存在玩家本机，服务端不参与。
--   客户端：设置 → 账号 →「删除账号」（scripts/net/account_delete.gd · scripts/scenes/settings/account_delete_dialog.gd）；
--           排行榜 / 赛况板 / 对阵图 / 对局顶栏 → 玩家菜单「举报昵称」（scripts/net/report_net.gd · scripts/scenes/social/player_menu.gd）。
--
-- 本文件做五件事：
--   ① player_tag_of(text)：玩家 ID（#XXXXXX）的服务端算法，与客户端 phase2_config.player_tag 逐位相同
--   ② finals_entrants.account_id 改成 on delete set null：周日组里有人删号，那个种子位与快照保留（匿名），
--      别人的对阵图 / 代打 / 录像不坏（原来是 cascade：删号会在组里挖掉一个种子）
--   ③ account_delete_self()：只删调用者本人（auth.uid()），先把留在别人可见处的昵称 / 头像 / 玩家 ID 抹成占位，
--      再删 auth.users（其余表靠 on delete cascade / set null）
--   ④ nickname_reports + report_nickname()：举报一条昵称（同一人对同一玩家 ID 24 小时一次，每人每天最多 20 条）
--   ⑤ 管理侧：视图 nickname_reports_pending（待处理，只读）+ nickname_report_resolve()（重置为默认昵称 / 驳回）
--      + nickname_resets + my_nickname_reset()（客户端开机查一次，自己的昵称被重置过就换回默认昵称）
--
-- ★本文件只建表 / 建函数 / 改一条外键，不删任何已有数据。重复执行安全。
-- ★上生产前先跑 server/supabase/tests/20261020b_account_delete_and_reports_check.sql（整段在一个事务里，结尾 rollback）。
-- ─────────────────────────────────────────────────────────────

-- ═══ ① 玩家 ID ═══
-- 客户端（phase2_config.gd player_tag）：sha256("turtle-id:" + 身份串) 取前 12 位十六进制 → 48 位整数 →
--   连除 28 取 6 位（低位在右），字母表 23456789BCDFGHJKMNPQRSTVWXYZ，前面加 #。身份串 = account_id（小写带横线的 uuid）。
-- 门禁 tests/verify_account_delete.gd 用客户端算出的几组号与本函数的写法逐字对账（测试脚本里也逐条比）。
create or replace function public.player_tag_of(p_identity text) returns text
language plpgsql immutable set search_path = public as $$
declare h text; v bigint; alpha text := '23456789BCDFGHJKMNPQRSTVWXYZ'; o text := ''; i int;
begin
  if p_identity is null or p_identity = '' then
    return '';
  end if;
  h := encode(sha256(convert_to('turtle-id:' || p_identity, 'UTF8')), 'hex');
  v := ('x' || substr(h, 1, 12))::bit(48)::bigint;
  for i in 1..6 loop
    o := substr(alpha, (v % 28)::int + 1, 1) || o;
    v := v / 28;
  end loop;
  return '#' || o;
end $$;
revoke all on function public.player_tag_of(text) from public, anon, authenticated;

-- 一份快照里的 profile 换成占位（快照没有 profile 就原样返回）。
create or replace function public.profile_scrub(p_snap jsonb, p_profile jsonb) returns jsonb
language sql immutable as $$
  select case when jsonb_typeof(p_snap) = 'object' and jsonb_typeof(p_snap->'profile') = 'object'
              then jsonb_set(p_snap, '{profile}', (p_snap->'profile') || p_profile)
              else p_snap end
$$;
revoke all on function public.profile_scrub(jsonb, jsonb) from public, anon, authenticated;

-- ═══ ② finals_entrants：删号不挖掉种子位 ═══
alter table public.finals_entrants alter column account_id drop not null;
do $$
declare c text;
begin
  for c in
    select con.conname from pg_constraint con
      join pg_attribute a on a.attrelid = con.conrelid and a.attnum = any(con.conkey)
     where con.conrelid = 'public.finals_entrants'::regclass and con.contype = 'f' and a.attname = 'account_id'
  loop
    execute format('alter table public.finals_entrants drop constraint %I', c);
  end loop;
end $$;
alter table public.finals_entrants
  add constraint finals_entrants_account_id_fkey
  foreign key (account_id) references auth.users(id) on delete set null;

-- ═══ ④ 举报表（③ 要删它的行，所以先建）═══
create table if not exists public.nickname_reports (
  report_id        bigint      generated always as identity primary key,
  reporter         uuid        not null references auth.users(id) on delete cascade,
  reported_tag     text        not null check (reported_tag ~ '^#[23456789BCDFGHJKMNPQRSTVWXYZ]{6}$'),
  reported_account uuid        references auth.users(id) on delete cascade,   -- 服务端按玩家 ID 反查；null = 查不到（机器人 / 已删号）
  name_snapshot    text        not null check (char_length(name_snapshot) between 1 and 40),
  context          text        not null default '' check (char_length(context) <= 24),
  status           text        not null default 'pending' check (status in ('pending', 'reset', 'dismissed')),
  created_at       timestamptz not null default now(),
  handled_at       timestamptz
);
create index if not exists nickname_reports_dedupe_idx on public.nickname_reports (reporter, reported_tag, created_at desc);
create index if not exists nickname_reports_pending_idx on public.nickname_reports (status, created_at) where status = 'pending';
alter table public.nickname_reports enable row level security;
-- 不建任何 policy ⇒ 客户端直连读写一律被拒；只经下面的 security definer 函数。
revoke all on public.nickname_reports from anon, authenticated, public;

-- 被重置过的昵称（管理员处理举报时写）。客户端开机经 my_nickname_reset() 查自己的。
create table if not exists public.nickname_resets (
  account_id   uuid        not null references auth.users(id) on delete cascade,
  banned_name  text        not null,
  created_at   timestamptz not null default now(),
  primary key (account_id, banned_name)
);
alter table public.nickname_resets enable row level security;
revoke all on public.nickname_resets from anon, authenticated, public;

-- ═══ ③ 删除账号 ═══
-- ★只删 auth.uid() 本人：函数不收任何参数，没有「删别人」的写法。
-- ★别人看得见的地方先抹名字再删号：
--   · matches（录像行）：自己那一侧（left_account = 我）+ 任一侧快照里玩家 ID 是我的（我当别人对手的那些场）
--   · live_matches 别人的直播行里我当对手的那一侧（我自己的行随 cascade 删掉）
--   · referee_jobs 双方快照（a_account / b_account = 我，或快照里玩家 ID 是我）；我自己还没算的周六任务直接作废
--   · finals_entrants 名字 + 快照（行保留，account_id 随 ② 变 null）
--   · referee_restream.requested_by
--   · nickname_reports 里与我有关的举报（我举报的 / 举报我的）
-- ★占位：名字「已注销玩家」，头像 basic，id deleted，玩家 ID 换成一串随机号（同一次删号的各行一致，
--   赛况板按玩家 ID 归并成一个人；与原号无关，反推不回去）。
-- ★录像本体（matches.replay，客户端二进制）里记着对手的快照，SQL 改不了 —— 它随 purge_old_matches 每周一清空；
--   隐私政策 §1.9 写明了这一条。
create or replace function public.account_delete_self() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  uid   uuid := auth.uid();
  tags  text[];
  ph    jsonb;
  n_m   int := 0; n_l int := 0; n_j int := 0; n_f int := 0; tmp_n int;
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

-- ═══ ④ 举报一条昵称 ═══
-- p_tag：被举报者的玩家 ID（屏幕上那串 #XXXXXX）；p_name：举报时看到的昵称（存快照，对方之后改名也查得到）；
-- p_context：在哪一屏举报的（leaderboard / gauntlet_board / bracket / battle），只做统计。
-- 返回 {ok:true} 或 {ok:false, reason: not_signed_in | bad_tag | bad_name | self | duplicate | limit}。
create or replace function public.report_nickname(p_tag text, p_name text, p_context text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid  uuid := auth.uid();
  nm   text := left(btrim(coalesce(p_name, '')), 40);
  ctx  text := coalesce(p_context, '');
  acc  uuid;
  n    int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_tag is null or p_tag !~ '^#[23456789BCDFGHJKMNPQRSTVWXYZ]{6}$' then
    return jsonb_build_object('ok', false, 'reason', 'bad_tag');
  end if;
  if nm = '' then
    return jsonb_build_object('ok', false, 'reason', 'bad_name');
  end if;
  if ctx not in ('leaderboard', 'gauntlet_board', 'bracket', 'battle') then
    ctx := '';
  end if;
  -- 同一人对同一玩家 ID 并发两次：串行化，第二次看得见第一次
  perform pg_advisory_xact_lock(hashtext(uid::text || p_tag));
  if exists (select 1 from public.nickname_reports
              where reporter = uid and reported_tag = p_tag and created_at > now() - interval '24 hours') then
    return jsonb_build_object('ok', false, 'reason', 'duplicate');
  end if;
  select count(*) into n from public.nickname_reports
   where reporter = uid and created_at > now() - interval '24 hours';
  if n >= 20 then
    return jsonb_build_object('ok', false, 'reason', 'limit');
  end if;
  -- 玩家 ID → 账号：在快照池里找最近一份带这个号的（机器人 / 已删号 ⇒ null，举报照收）
  select account_id into acc from public.ghosts
   where snapshot->'profile'->>'tag' = p_tag order by uploaded_at desc limit 1;
  if acc is null then
    select account_id into acc from public.gauntlet_ghosts
     where snapshot->'profile'->>'tag' = p_tag order by uploaded_at desc limit 1;
  end if;
  if acc = uid or p_tag = public.player_tag_of(uid::text) then
    return jsonb_build_object('ok', false, 'reason', 'self');
  end if;
  insert into public.nickname_reports (reporter, reported_tag, reported_account, name_snapshot, context)
    values (uid, p_tag, acc, nm, ctx);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.report_nickname(text, text, text) from public;
revoke execute on function public.report_nickname(text, text, text) from anon;
grant execute on function public.report_nickname(text, text, text) to authenticated;

-- ═══ ⑤ 管理侧 ═══
-- 待处理举报：按「玩家 ID + 账号」归并，举报人数多的排前面。只读；只有 service_role / SQL 编辑器看得到。
-- 用法（Supabase SQL 编辑器）：select * from public.nickname_reports_pending;
create or replace view public.nickname_reports_pending with (security_invoker = true) as
  select r.reported_tag,
         r.reported_account,
         (array_agg(r.name_snapshot order by r.created_at desc))[1] as latest_name,
         array_agg(distinct r.name_snapshot) as names,
         count(*)::int as reports,
         count(distinct r.reporter)::int as reporters,
         array_agg(distinct r.context) as contexts,
         min(r.created_at) as first_at,
         max(r.created_at) as last_at
    from public.nickname_reports r
   where r.status = 'pending'
   group by r.reported_tag, r.reported_account
   order by count(distinct r.reporter) desc, max(r.created_at) desc;
revoke all on public.nickname_reports_pending from public, anon, authenticated;
grant select on public.nickname_reports_pending to service_role;

-- 处理一个玩家 ID 的全部待处理举报。
--   p_action = 'reset'   ⇒ 记进 nickname_resets（客户端下次开机把这个名字换回默认昵称），
--                          并把服务端已存的这些名字换成占位「玩家 + 玩家 ID」（排行榜 / 赛况板 / 对阵图立刻不再显示原名）
--   p_action = 'dismiss' ⇒ 只标记已处理，不动昵称
-- 返回 {ok, account, names, scrubbed}。查不到账号（机器人 / 已删号）时 reset 退化成 dismiss（reason = no_account）。
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
  update public.accounts set display_name = ph where account_id = acc and display_name = any(names);
  update public.nickname_reports set status = 'reset', handled_at = now()
   where reported_tag = p_tag and status = 'pending';
  return jsonb_build_object('ok', true, 'action', 'reset', 'account', acc, 'names', to_jsonb(names), 'scrubbed', n);
end $$;
revoke all on function public.nickname_report_resolve(text, text) from public, anon, authenticated;
grant execute on function public.nickname_report_resolve(text, text) to service_role;

-- 客户端开机查一次：我有没有被重置过的昵称。返回 {ok:true, names:[...]}（没有 ⇒ 空数组）。只读。
create or replace function public.my_nickname_reset() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); ns jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select coalesce(jsonb_agg(banned_name order by created_at), '[]'::jsonb) into ns
    from public.nickname_resets where account_id = uid;
  return jsonb_build_object('ok', true, 'names', ns);
end $$;
revoke all on function public.my_nickname_reset() from public;
revoke execute on function public.my_nickname_reset() from anon;
grant execute on function public.my_nickname_reset() to authenticated;

-- 上线后回读（memory：`revoke from public` 收不掉 anon 的默认授权，必须逐个看）：
--   select p.proname, r.rolname, has_function_privilege(r.rolname, p.oid, 'execute')
--     from pg_proc p cross join (values ('anon'), ('authenticated'), ('service_role')) r(rolname)
--    where p.pronamespace = 'public'::regnamespace
--      and p.proname in ('account_delete_self', 'report_nickname', 'my_nickname_reset', 'nickname_report_resolve',
--                        'player_tag_of', 'profile_scrub');
--   期望：anon 全 false；authenticated 只有前三个 true；service_role 有 nickname_report_resolve。
-- <<< END account_delete_and_reports 20261020b <<<
