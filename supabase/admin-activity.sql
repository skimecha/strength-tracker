-- ============================================================================
-- admin_activity(days) — owner-only engagement metrics over a time window.
-- Returns COUNTS only (never which users), excludes the owner account, and is
-- gated on the owner UID like admin_metrics. Run once in the Supabase SQL editor.
--
-- Activity timestamps already exist in the data:
--   sessions.date, weight_log.date, food_log.ts  → Date.now() epoch-MS (bigint)
--   plan_targets.updated_at                      → timestamptz (bumped on save)
--   auth.users.last_sign_in_at / created_at      → timestamptz
-- ============================================================================

create or replace function public.admin_activity(p_days int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  owner constant uuid := '031a65ed-f52d-4a67-b271-47778e920c22';
  cutoff_ms bigint := (extract(epoch from now())::bigint - p_days * 86400) * 1000;
  cutoff_ts timestamptz := now() - make_interval(days => p_days);
  result jsonb;
begin
  if auth.uid() is null or auth.uid() <> owner then
    return null;  -- non-owners get nothing
  end if;

  with
  w as (select distinct user_id from public.sessions     where user_id <> owner and date >= cutoff_ms),
  n as (select distinct user_id from public.food_log      where user_id <> owner and ts   >= cutoff_ms),
  b as (select distinct user_id from public.weight_log    where user_id <> owner and date >= cutoff_ms),
  p as (select distinct user_id from public.plan_targets  where user_id <> owner and updated_at >= cutoff_ts),
  active as (
    select user_id from w union
    select user_id from n union
    select user_id from b union
    select user_id from p
  )
  select jsonb_build_object(
    'days',            p_days,
    'total_users',     (select count(*) from auth.users where id <> owner),
    'logged_in',       (select count(*) from auth.users where id <> owner and last_sign_in_at >= cutoff_ts),
    'new_signups',     (select count(*) from auth.users where id <> owner and created_at      >= cutoff_ts),
    'active_users',    (select count(*) from active),
    'workouts_users',  (select count(*) from w),
    'nutrition_users', (select count(*) from n),
    'weight_users',    (select count(*) from b),
    'plan_users',      (select count(*) from p),
    'workouts_logged', (select count(*) from public.sessions   where user_id <> owner and date >= cutoff_ms),
    'meals_logged',    (select count(*) from public.food_log    where user_id <> owner and ts   >= cutoff_ms),
    'weighins',        (select count(*) from public.weight_log  where user_id <> owner and date >= cutoff_ms)
  ) into result;

  return result;
end;
$$;

revoke all on function public.admin_activity(int) from public, anon;
grant execute on function public.admin_activity(int) to authenticated;

notify pgrst, 'reload schema';
