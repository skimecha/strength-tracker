-- ============================================================================
-- Body measurements (v2.41.0). Run once in the Supabase SQL editor. Safe to re-run.
--
-- One row per check-in: data = {site: inches}, e.g. {"waist":33,"shoulders":49.5}.
-- Inches are canonical; the app converts to cm for display only.
-- ============================================================================

create table if not exists public.body_measurements (id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade, date bigint not null, data jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());

create index if not exists body_measurements_user_date on public.body_measurements (user_id, date);

alter table public.body_measurements enable row level security;

drop policy if exists body_measurements_own on public.body_measurements;
create policy body_measurements_own on public.body_measurements for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update, delete on public.body_measurements to authenticated;
grant select, insert, update, delete on public.body_measurements to service_role;

notify pgrst, 'reload schema';
