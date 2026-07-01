-- ============================================================================
-- admin_activity(days) — owner-only engagement metrics over a time window.
-- Returns COUNTS only (never which users), excludes the owner account, and is
-- gated on the owner UID like admin_metrics. Run once in the Supabase SQL editor.
-- Safe to re-run.
--
-- Activity timestamps already exist in the data:
--   sessions.date, weight_log.date, food_log.ts  → Date.now() epoch-MS (bigint)
--   plan_targets.updated_at                      → timestamptz (bumped on save)
--   auth.users.last_sign_in_at / created_at      → timestamptz
-- ============================================================================

-- AI Macros usage flag: the client sets this true on a saved food entry whose
-- macros came from AI Macros. Defaults false; existing rows count as non-AI.
alter table public.food_log add column if not exists ai boolean not null default false;

-- Internal helper: distinct user ids active since the given cutoffs (owner
-- excluded). "Active" = any of the four tracked activities.
create or replace function public._activity_active(cms bigint, cts timestamptz, p_owner uuid)
returns setof uuid
language sql
security definer
set search_path = public
as $$
  select user_id from public.sessions     where user_id <> p_owner and date >= cms
  union
  select user_id from public.food_log      where user_id <> p_owner and ts   >= cms
  union
  select user_id from public.weight_log    where user_id <> p_owner and date >= cms
  union
  select user_id from public.plan_targets  where user_id <> p_owner and updated_at >= cts
$$;
revoke all on function public._activity_active(bigint,timestamptz,uuid) from public, anon, authenticated;

create or replace function public.admin_activity(p_days int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  owner constant uuid := '031a65ed-f52d-4a67-b271-47778e920c22';
  cutoff_ms bigint      := (extract(epoch from now())::bigint - p_days * 86400) * 1000;
  cutoff_ts timestamptz := now() - make_interval(days => p_days);
  ms_1d  bigint      := (extract(epoch from now())::bigint - 86400)     * 1000;  -- for DAU
  ts_1d  timestamptz := now() - interval '1 day';
  ms_30d bigint      := (extract(epoch from now())::bigint - 30 * 86400) * 1000;  -- for MAU
  ts_30d timestamptz := now() - interval '30 days';
  result jsonb;
begin
  if auth.uid() is null or auth.uid() <> owner then
    return null;  -- non-owners get nothing
  end if;

  with
  w  as (select distinct user_id from public.sessions     where user_id <> owner and date >= cutoff_ms),
  n  as (select distinct user_id from public.food_log      where user_id <> owner and ts   >= cutoff_ms),
  b  as (select distinct user_id from public.weight_log    where user_id <> owner and date >= cutoff_ms),
  p  as (select distinct user_id from public.plan_targets  where user_id <> owner and updated_at >= cutoff_ts),
  ai as (select distinct user_id from public.food_log      where user_id <> owner and ai = true and ts >= cutoff_ms),
  active     as (select uid from public._activity_active(cutoff_ms, cutoff_ts, owner) as t(uid)),
  active_new as (select a.uid from active a join auth.users u on u.id = a.uid where u.created_at >= cutoff_ts)
  select jsonb_build_object(
    'days',             p_days,
    'total_users',      (select count(*) from auth.users where id <> owner),
    'logged_in',        (select count(*) from auth.users where id <> owner and last_sign_in_at >= cutoff_ts),
    'new_signups',      (select count(*) from auth.users where id <> owner and created_at      >= cutoff_ts),
    'active_users',     (select count(*) from active),
    'active_new',       (select count(*) from active_new),
    'active_returning', (select count(*) from active) - (select count(*) from active_new),
    'workouts_users',   (select count(*) from w),
    'nutrition_users',  (select count(*) from n),
    'weight_users',     (select count(*) from b),
    'plan_users',       (select count(*) from p),
    'ai_users',         (select count(*) from ai),
    'workouts_logged',  (select count(*) from public.sessions   where user_id <> owner and date >= cutoff_ms),
    'meals_logged',     (select count(*) from public.food_log    where user_id <> owner and ts   >= cutoff_ms),
    'weighins',         (select count(*) from public.weight_log  where user_id <> owner and date >= cutoff_ms),
    'dau',              (select count(*) from public._activity_active(ms_1d,  ts_1d,  owner)),
    'mau',              (select count(*) from public._activity_active(ms_30d, ts_30d, owner))
  ) into result;

  return result;
end;
$$;

revoke all on function public.admin_activity(int) from public, anon;
grant execute on function public.admin_activity(int) to authenticated;

notify pgrst, 'reload schema';
