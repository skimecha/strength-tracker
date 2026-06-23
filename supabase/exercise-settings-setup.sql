-- ============================================================================
-- exercise_settings — per-user, per-exercise flags. Currently holds the
-- "assisted" flag (machine-assisted moves where a LOWER weight is the better
-- lift, e.g. assisted pull-ups/dips). Run once in the Supabase SQL editor.
--
-- Keyed by exercise NAME so it works for both built-in and custom exercises.
-- Standard per-user RLS: a user can only see/modify their own rows.
-- ============================================================================

create table if not exists public.exercise_settings (
  user_id    uuid not null references auth.users(id) on delete cascade,
  exercise   text not null,
  assisted   boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, exercise)
);

alter table public.exercise_settings enable row level security;

drop policy if exists exercise_settings_owner on public.exercise_settings;
create policy exercise_settings_owner on public.exercise_settings
  for all to authenticated
  using      (auth.uid() = user_id)
  with check (auth.uid() = user_id);

notify pgrst, 'reload schema';
