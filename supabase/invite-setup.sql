-- ============================================================================
-- Invite-only registration — schema setup
-- Run once in the Supabase SQL editor.
-- ============================================================================

-- Invite codes. Only the owner can create/read these from the client (RLS below).
-- The redeem-invite Edge Function uses the service-role key and bypasses RLS.
create table if not exists public.invite_codes (
  code        text primary key,
  label       text,
  max_uses    int  not null default 1,
  used_count  int  not null default 0,
  expires_at  timestamptz,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- One row per successful signup, for tracking who used what.
create table if not exists public.invite_redemptions (
  id          bigint generated always as identity primary key,
  code        text references public.invite_codes(code) on delete set null,
  user_id     uuid references auth.users(id) on delete cascade,
  email       text,
  redeemed_at timestamptz not null default now()
);

alter table public.invite_codes       enable row level security;
alter table public.invite_redemptions enable row level security;

-- Only the owner (Matt) may create / view / manage invite codes from the app.
-- Hardcoded UUID so an invited user can't mint their own codes and reopen the door.
drop policy if exists invite_codes_owner_all on public.invite_codes;
create policy invite_codes_owner_all on public.invite_codes
  for all to authenticated
  using      (auth.uid() = '031a65ed-f52d-4a67-b271-47778e920c22')
  with check (auth.uid() = '031a65ed-f52d-4a67-b271-47778e920c22');

drop policy if exists invite_redemptions_owner_read on public.invite_redemptions;
create policy invite_redemptions_owner_read on public.invite_redemptions
  for select to authenticated
  using (auth.uid() = '031a65ed-f52d-4a67-b271-47778e920c22');

-- Auto-expose is OFF on this project, so new tables need explicit grants.
grant select, insert, update, delete on public.invite_codes       to authenticated;
grant select                         on public.invite_redemptions to authenticated;

notify pgrst, 'reload schema';
