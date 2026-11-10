-- ============================================================================
-- Machine photos (v2.37.0). Run once in the Supabase SQL editor. Safe to re-run.
--
-- One photo per (user, exercise, machine number 1-3), so the Machine toggle
-- on the set screen can be matched visually to a real machine. The client
-- downscales to ~640px JPEG before upload, so `data` (a data: URL) runs
-- tens of KB per row and rows exist only where the user created them.
-- ============================================================================

create table if not exists public.machine_photos (
  user_id    uuid not null references auth.users(id) on delete cascade,
  exercise   text not null,
  machine    int  not null check (machine between 1 and 3),
  data       text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, exercise, machine)
);

alter table public.machine_photos enable row level security;

drop policy if exists machine_photos_own on public.machine_photos;
create policy machine_photos_own on public.machine_photos
  for all to authenticated
  using      (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Auto-expose is OFF on this project, so grants are explicit (RLS still applies).
grant select, insert, update, delete on public.machine_photos to authenticated;
grant select, insert, update, delete on public.machine_photos to service_role;

notify pgrst, 'reload schema';
