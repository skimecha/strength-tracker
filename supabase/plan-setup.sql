-- ============================================================================
-- Plan targets — weekly working-set goal per muscle (one row per user).
-- Run once in the Supabase SQL editor.
-- ============================================================================

create table if not exists public.plan_targets (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  targets    jsonb not null default '{}'::jsonb,   -- { "Chest": 14, "Lats": 12, ... }
  updated_at timestamptz not null default now()
);

alter table public.plan_targets enable row level security;

drop policy if exists plan_targets_own on public.plan_targets;
create policy plan_targets_own on public.plan_targets
  for all to authenticated
  using      (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Auto-expose is OFF on this project, so new tables need explicit grants.
grant select, insert, update, delete on public.plan_targets to authenticated;

notify pgrst, 'reload schema';
