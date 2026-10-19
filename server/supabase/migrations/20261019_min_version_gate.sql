-- >>> min_version_gate 20261019 >>>
-- 2026-10-19 强制最低版本(用户「需要强制最低版本」· 方案书 docs/plans/20261019-服务器裁判.md §4)
--
-- ★★未执行。上生产前先在内测服跑一遍并回读(见文末「上线步骤」)。
--
-- 三件事:
--   ① 服务端版本闸: 每个 PostgREST 请求(表的读写 + 全部 RPC)先过 pre-request 钩子
--      `check_client_version()`: 请求头 `X-Client-Version`(客户端 supabase.gd `_headers` 每条都带)
--      低于 `service_status.min_client_version` ⇒ 拒, HTTP 426, message = 'update_required'。
--      ★为什么用钩子而不是给每个 RPC 加 `p_client_version` 参数:
--        快照/录像/直播是**直接写表**(REST insert/upsert), 拉对手是**直接 GET 表** —— 那些请求没有参数位;
--        而 RPC 加参数要改签名(旧签名留着 = 旧包照调不误, 删掉 = 改一处漏一处)。
--        请求头是唯一跟着**每一个**请求走的位置, 一个函数管全部入口, 新加的 RPC 也自动在闸后面。
--      ★缺头 / 看不懂 ⇒ 按 0.0.0 算 ⇒ 只要最低版本 > 0.0.0 就拒。
--        ⇒ 0.19.571 及更早的包(不带这个头)在运维抬高最低版本的那一刻起全部被拒;
--          最低版本保持默认 '0.0.0' 时谁都不拒 —— 本迁移可以提前上, 不影响在跑的内测。
--      白名单(旧包也放行): 读 service_status(旧包要读到最低版本才知道该更新) /
--        report_client_error / submit_feedback(诊断)。service_role(裁判机 / 运维)不过闸。
--   ② 行级兜底: ghosts / gauntlet_ghosts 的写策略再加一条「行里的 client_version 不低于最低版本」
--      —— 钩子万一没配上(见风险), 旧包上传的快照照样进不了池子;
--      也挡住「新包把旧版本打出来的排队快照补传上来」(客户端 ghost_uploader 也会按版本销单)。
--   ③ 战斗规则版本 `rules_ver`: ghosts / gauntlet_ghosts 加一列, 客户端上传时写
--      `phase2_config.RULES_VER`, 拉对手只拉 `rules_ver = 本机值`(opponents_query / gauntlet_query)。
--      ★旧数据: 已有的行一律是默认值 0 ⇒ 新客户端(RULES_VER = 1)**永远拉不到**。
--        这是有意的: 那些快照是旧规则下打出来的, 在新规则下算不出同一局。
--        两张表都按 season_week 分周(周一清), 新版本在周一维护期上线时, 新的一周本来就从空池子开始。
--        不回填: 没有办法事后证明某一行是在哪套规则下打的(client_version 列能近似, 但规则版本与客户端版本不是一一对应)。
--      ★客户端在 0.19.571 及更早不写这一列 ⇒ 它们上传的行也是 0 ⇒ 新旧两代池子天然隔开。
--
-- ★发版流程加一步(方案书 §4): 这一版改了任何会改变对局结果的东西 ⇒ 客户端 RULES_VER +1,
--   并在新包上架后执行:
--     update public.service_status set min_client_version = '<新版本>', updated_at = now() where id = 1;

-- ── 版本串 → 整数数组(补齐 4 段; 看不懂 ⇒ null) ──
create or replace function public.semver_arr(v text)
returns int[]
language plpgsql immutable as $$
declare
  s text := btrim(coalesce(v, ''));
  a int[];
begin
  if s !~ '^[0-9]{1,6}(\.[0-9]{1,6}){0,3}$' then
    return null;
  end if;
  a := string_to_array(s, '.')::int[];
  while coalesce(array_length(a, 1), 0) < 4 loop
    a := a || 0;
  end loop;
  return a;
end $$;

-- ── 这个版本够不够(低于最低版本 ⇒ false; 缺 / 看不懂 ⇒ 按 0.0.0 算) ──
-- ★最低版本本身看不懂(运维填错)⇒ 放行 —— 填错一个字不该把所有人关在门外。
create or replace function public.client_version_ok(v text)
returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  m int[];
begin
  select public.semver_arr(min_client_version) into m from public.service_status where id = 1;
  if m is null then
    return true;
  end if;
  return coalesce(public.semver_arr(v), array[0, 0, 0, 0]) >= m;
end $$;
revoke all on function public.client_version_ok(text) from public;
grant execute on function public.client_version_ok(text) to anon, authenticated, service_role;

-- ── 请求头里的客户端版本(PostgREST 把请求头放在 request.headers, 键一律小写) ──
create or replace function public.request_client_version()
returns text
language sql stable as $$
  select nullif(current_setting('request.headers', true), '')::json ->> 'x-client-version'
$$;
grant execute on function public.request_client_version() to anon, authenticated, service_role;

-- ── ① pre-request 钩子 ──
create or replace function public.check_client_version()
returns void
language plpgsql stable security definer set search_path = public as $$
declare
  p text := coalesce(current_setting('request.path', true), '');
  role_claim text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role', '');
  cv text := public.request_client_version();
begin
  if role_claim = 'service_role' then
    return;
  end if;
  if p ~ '/(service_status|rpc/report_client_error|rpc/submit_feedback)/?$' then
    return;
  end if;
  if not public.client_version_ok(cv) then
    raise sqlstate 'PT426' using
      message = 'update_required',
      detail = format('client %s is below min_client_version', coalesce(cv, '(none)'));
  end if;
end $$;
revoke all on function public.check_client_version() from public;
grant execute on function public.check_client_version() to anon, authenticated, service_role;

-- 挂上钩子(PostgREST 读 authenticator 角色上的 pgrst.* 配置), 然后让它重读配置。
alter role authenticator set pgrst.db_pre_request = 'public.check_client_version';
notify pgrst, 'reload config';

-- ── ③ 战斗规则版本列 ──
alter table public.ghosts add column if not exists rules_ver int not null default 0;
alter table public.gauntlet_ghosts add column if not exists rules_ver int not null default 0;
-- 拉对手的过滤多了一维: 积分赛 (周, 场次, 规则) / 周六 (周, 标签, 规则), 都按上传时刻倒序。
create index if not exists ghosts_match_rv_idx
  on public.ghosts (season_week, battles, rules_ver, uploaded_at desc);
create index if not exists gauntlet_match_rv_idx
  on public.gauntlet_ghosts (season_week, gw, gl, rules_ver, uploaded_at desc);

-- ── ② 行级兜底: 写快照的行版本不低于最低版本 ──
drop policy if exists ghosts_write_own on public.ghosts;
create policy ghosts_write_own on public.ghosts
  for insert with check (account_id = auth.uid() and public.client_version_ok(client_version));

drop policy if exists ghosts_update_own on public.ghosts;
create policy ghosts_update_own on public.ghosts
  for update using (account_id = auth.uid())
  with check (account_id = auth.uid() and public.client_version_ok(client_version));

drop policy if exists gauntlet_write_own on public.gauntlet_ghosts;
create policy gauntlet_write_own on public.gauntlet_ghosts
  for insert with check (account_id = auth.uid() and public.client_version_ok(client_version));

drop policy if exists gauntlet_update_own on public.gauntlet_ghosts;
create policy gauntlet_update_own on public.gauntlet_ghosts
  for update using (account_id = auth.uid())
  with check (account_id = auth.uid() and public.client_version_ok(client_version));

-- 上线步骤(内测服先走一遍, 回读每一条):
--   1. 执行本文件。回读: select public.semver_arr('0.19.10') > public.semver_arr('0.19.9');  -- 应为 true
--   2. 最低版本仍是 0.0.0 时: 0.19.571 的包照常能拉对手 / 传快照(谁都不拒)。
--   3. update service_status set min_client_version = '0.19.999' ⇒
--      不带头的 curl GET /rest/v1/ghosts 回 426 {"message":"update_required"};
--      GET /rest/v1/service_status 照常 200; 带 `X-Client-Version: 0.19.999` 的 GET 200。
--      ⚠ 若 GET ghosts 仍 200: 钩子没生效(见风险 R-钩子), 此时只有②行级兜底在挡写, 读不挡。
--   4. 改回最低版本。
-- 风险:
--   R-钩子: Supabase 托管的 PostgREST 是否接受 `alter role authenticator set pgrst.db_pre_request`
--     本仓从没实测过(官方文档有 pre-request 的说明, 但托管实例的角色权限没验)。不接受 ⇒ 换成在每个 RPC 开头
--     `if not public.client_version_ok(public.request_client_version()) then return ...update_required` + 表的读策略加同一条。
--   R-网页包: 浏览器跨域时自定义头要过网关的 CORS 预检; Supabase 网关目前放行任意请求头, 但没在网页包上实测。
-- <<< END min_version_gate 20261019 <<<
