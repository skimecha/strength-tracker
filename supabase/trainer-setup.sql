-- ============================================================================
-- Phase 1: Trainer roles & trainer↔client links. Run once in the SQL editor.
-- Safe to re-run.
--
-- Model (see ROADMAP.md): clients are sovereign accounts; a trainer link is a
-- revocable grant, never ownership. Either side can sever it; severing only
-- flips status — no accounts or data are ever deleted. No data visibility is
-- granted in this phase (that's Phase 2).
-- ============================================================================

-- ── profiles: role ──────────────────────────────────────────────────────────
-- profiles(id, email) already exists (populated by redeem-invite / signup
-- trigger). Add a role and make sure every existing auth user has a row.
alter table public.profiles add column if not exists role text not null default 'user';

insert into public.profiles (id, email)
select u.id, u.email from auth.users u
on conflict (id) do nothing;

alter table public.profiles enable row level security;

-- Users may read their own profile (the app needs the role at login).
drop policy if exists profiles_own_read on public.profiles;
create policy profiles_own_read on public.profiles
  for select to authenticated using (auth.uid() = id);

grant select on public.profiles to authenticated;
grant select, insert, update, delete on public.profiles to service_role;

-- ── trainer_clients: the link table ────────────────────────────────────────
create table if not exists public.trainer_clients (
  trainer_id uuid not null references auth.users(id) on delete cascade,
  client_id  uuid not null references auth.users(id) on delete cascade,
  status     text not null default 'active',   -- 'active' | 'removed'
  -- Phase 2 visibility toggles (client-controlled). Created now so the schema
  -- is stable; NOT used for any access in Phase 1.
  share_workouts  boolean not null default true,
  share_nutrition boolean not null default false,
  share_weight    boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (trainer_id, client_id)
);

-- Trainer-facing display name for the client ("Trent"), set at invite time
-- from either flow (email field, or the invite code's label on redemption).
alter table public.trainer_clients add column if not exists client_label text;

alter table public.trainer_clients enable row level security;

-- Trainer: may read their own links and update them (remove a client).
drop policy if exists tc_trainer_read on public.trainer_clients;
create policy tc_trainer_read on public.trainer_clients
  for select to authenticated using (auth.uid() = trainer_id);

drop policy if exists tc_trainer_update on public.trainer_clients;
create policy tc_trainer_update on public.trainer_clients
  for update to authenticated
  using      (auth.uid() = trainer_id)
  with check (auth.uid() = trainer_id);

-- Client: may read their own links and update them (disconnect / visibility).
drop policy if exists tc_client_read on public.trainer_clients;
create policy tc_client_read on public.trainer_clients
  for select to authenticated using (auth.uid() = client_id);

drop policy if exists tc_client_update on public.trainer_clients;
create policy tc_client_update on public.trainer_clients
  for update to authenticated
  using      (auth.uid() = client_id)
  with check (auth.uid() = client_id);

-- No authenticated INSERT policy on purpose: links are created only by the
-- redeem-invite Edge Function (service role) when a client invite is redeemed.
grant select, update on public.trainer_clients to authenticated;
grant select, insert, update, delete on public.trainer_clients to service_role;

-- ── invite_codes: typed invites ────────────────────────────────────────────
-- invite_type: 'user' (default) | 'trainer' | 'client'
-- trainer_id: set on client invites — redemption auto-links to this trainer.
alter table public.invite_codes add column if not exists invite_type text not null default 'user';
alter table public.invite_codes add column if not exists trainer_id uuid references auth.users(id) on delete set null;

-- Trainers may create CLIENT invites of their own, and see only their own codes.
-- (The existing owner policy is untouched — the owner still sees/creates all.)
drop policy if exists invite_codes_trainer_read on public.invite_codes;
create policy invite_codes_trainer_read on public.invite_codes
  for select to authenticated using (created_by = auth.uid());

drop policy if exists invite_codes_trainer_insert on public.invite_codes;
create policy invite_codes_trainer_insert on public.invite_codes
  for insert to authenticated
  with check (
    created_by = auth.uid()
    and invite_type = 'client'
    and trainer_id = auth.uid()
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'trainer')
  );

-- ── trainer_list_clients(): client list with emails, without widening
--    profiles RLS. Only returns the CALLER's links. ─────────────────────────
drop function if exists public.trainer_list_clients();  -- return type changed (added label)
create or replace function public.trainer_list_clients()
returns table (client_id uuid, email text, label text, status text, linked_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select tc.client_id, p.email, tc.client_label, tc.status, tc.created_at
  from public.trainer_clients tc
  left join public.profiles p on p.id = tc.client_id
  where tc.trainer_id = auth.uid()
  order by tc.created_at desc
$$;
revoke all on function public.trainer_list_clients() from public, anon;
grant execute on function public.trainer_list_clients() to authenticated;

-- ── Owner: grant/revoke trainer status + list trainers (Admin area) ────────
create or replace function public.admin_set_trainer(p_email text, p_trainer boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  owner constant uuid := '031a65ed-f52d-4a67-b271-47778e920c22';
  uid uuid;
begin
  if auth.uid() is null or auth.uid() <> owner then return null; end if;
  select id into uid from auth.users where lower(email) = lower(trim(p_email));
  if uid is null then return jsonb_build_object('ok', false, 'error', 'No account with that email.'); end if;
  insert into public.profiles (id, email, role)
  values (uid, lower(trim(p_email)), case when p_trainer then 'trainer' else 'user' end)
  on conflict (id) do update set role = excluded.role;
  return jsonb_build_object('ok', true, 'email', lower(trim(p_email)), 'role', case when p_trainer then 'trainer' else 'user' end);
end;
$$;
revoke all on function public.admin_set_trainer(text, boolean) from public, anon;
grant execute on function public.admin_set_trainer(text, boolean) to authenticated;

create or replace function public.admin_list_trainers()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select case when auth.uid() = '031a65ed-f52d-4a67-b271-47778e920c22'
    then coalesce(jsonb_agg(t), '[]'::jsonb) else null end
  from (
    select p.email,
           (select count(*) from public.trainer_clients tc
             where tc.trainer_id = p.id and tc.status = 'active') as active_clients
    from public.profiles p where p.role = 'trainer' order by p.email
  ) t
$$;
revoke all on function public.admin_list_trainers() from public, anon;
grant execute on function public.admin_list_trainers() to authenticated;

notify pgrst, 'reload schema';
