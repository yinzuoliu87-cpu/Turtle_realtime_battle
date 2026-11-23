-- >>> BEGIN pet_gift_basic 20261123b >>>
-- ─────────────────────────────────────────────────────────────
-- 每个号永久拥有 basic（小龟）（2026-11-23 · 随 0.23.6）
--   Tom 11-20 运营安排第 7 条；用户 11-22 拍板「新玩家一进游戏永久送一只 basic（+ 每周 7 只限免）」。
--   做法：服务器的「拥有」= 主站拥有（mainsite_pets）∪ 赠送（pet_gift_ids() = basic）。只改 pet_owned 一处，
--     用它的三处自然跟着走：
--     ① 领活盖章 pet_stamp_on_claim 的 a_owned / b_owned 带上 basic ⇒ 裁判 RefereeJob.pets_allowed 放行（旧版裁判代码也一样）；
--        WeeklyFree 跳过已拥有的 ⇒ 限免 7 只另外选，不会再抽到 basic。
--     ② 开算等级表 pet_lv_table：basic 按服务器等级（以前固定 1 级）。
--     ③ 发经验 pet_xp_grant：basic 跟别的拥有龟一样涨经验 / 升级。
--   升级通知主站（mainsite_outbox 'pet-level'）照旧只发主站上真拥有的龟 —— mainsite_outbox_put 自己按 mainsite_pets 挡
--     （20261109a），赠送的 basic 主站那边这个号没有就不推，这里不用改。
--   mainsite_status / mainsite_me / pet_levels_me 回的 owned 不变（= 主站真拥有），客户端自己并上赠送（WeeklyFree.GIFT）。
--   没有账号（p_account 为 null，服务器机器人池）⇒ 仍是空（与改之前相同，裁判不查）。陪练号（bot_accounts）是正常账号 ⇒ 也有 basic。
-- 回滚：重新执行 20261109b_pet_levels.sql 里 ③ pet_owned 那一段；drop function public.pet_gift_ids()。
-- ★不改表。重复执行安全。
-- ─────────────────────────────────────────────────────────────

-- 赠送的龟（= WeeklyFree.GIFT；门禁 verify_weekly_free 逐只比）
create or replace function public.pet_gift_ids() returns text[]
language sql immutable as $$
  select array['basic']
$$;
revoke all on function public.pet_gift_ids() from public, anon, authenticated;

-- ③ 拥有 = 主站拥有 ∪ 赠送（只认 28 只、去重、按名字排）
create or replace function public.pet_owned(p_account uuid) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare own text[];
begin
  if p_account is null then
    return '{}';
  end if;
  begin
    select coalesce(array_agg(distinct p.pet_key order by p.pet_key), '{}') into own
      from public.mainsite_pets p
     where p.account_id = p_account and p.pet_key = any(public.pet_all_ids());
  exception when undefined_table then
    own := '{}';                       -- 20261109a 还没上 ⇒ 谁都没绑定
  end;
  select coalesce(array_agg(distinct k order by k), '{}') into own
    from unnest(coalesce(own, '{}') || public.pet_gift_ids()) k
   where k = any(public.pet_all_ids());
  return own;
end $$;
revoke all on function public.pet_owned(uuid) from public, anon, authenticated;

-- <<< END pet_gift_basic 20261123b <<<
