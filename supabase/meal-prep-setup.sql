-- ============================================================================
-- Meal Prep Mode (v2.33.0). Run once in the Supabase SQL editor. Safe to re-run.
--
-- One row per user holds the whole plan as jsonb:
--   data = { meals: [{id,name,components,slot,days}], overrides: {date:{slot:id|null}} }
-- Checked-off meals are ordinary food_log entries tagged via the new
-- food_log.meal column ({mealId,slot}), so deleting the entry un-checks the meal.
-- ============================================================================

create table if not exists public.meal_prep (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.meal_prep enable row level security;

drop policy if exists meal_prep_own on public.meal_prep;
create policy meal_prep_own on public.meal_prep
  for all to authenticated
  using      (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Auto-expose is OFF on this project, so grants are explicit (RLS still applies).
grant select, insert, update, delete on public.meal_prep to authenticated;
grant select, insert, update, delete on public.meal_prep to service_role;

-- Tag column for food_log entries created by a meal-prep check-off.
-- Until this exists the app falls back to a same-day name match for
-- checked state, and the tag update fails harmlessly.
alter table public.food_log add column if not exists meal jsonb;

notify pgrst, 'reload schema';
