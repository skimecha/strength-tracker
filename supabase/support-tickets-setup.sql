-- ============================================================================
-- support_messages — lock down + extend the existing table so the owner-only
-- Support Tickets page can read and triage user-submitted messages.
-- Run once in the Supabase SQL editor.
--
-- The table already exists (the More-page support form inserts into it). This
-- script does NOT recreate it; it (a) guarantees the columns the Admin page
-- needs, and (b) RESETS the row-level security policies to a known-good set.
--
-- Security: support messages contain other users' emails + free text (PII).
-- Read/update/delete are restricted to the owner UID server-side; any
-- authenticated user may still INSERT (so the support form keeps working) but
-- can never read anyone's messages, including their own.
-- ============================================================================

-- Columns the Admin page relies on (no-ops if they already exist).
alter table public.support_messages add column if not exists created_at timestamptz not null default now();
alter table public.support_messages add column if not exists resolved   boolean     not null default false;

alter table public.support_messages enable row level security;

-- Drop EVERY existing policy on the table, then recreate exactly the ones we
-- want. This removes any permissive/leaky policy that may have been created by
-- hand when the table was first set up.
do $$
declare p record;
begin
  for p in select policyname from pg_policies
           where schemaname='public' and tablename='support_messages' loop
    execute format('drop policy if exists %I on public.support_messages', p.policyname);
  end loop;
end$$;

-- Anyone signed in may submit a ticket (insert only — they cannot read it back).
create policy support_messages_insert on public.support_messages
  for insert to authenticated with check (true);

-- Owner-only read.
create policy support_messages_owner_read on public.support_messages
  for select to authenticated
  using (auth.uid() = '031a65ed-f52d-4a67-b271-47778e920c22');

-- Owner-only triage (mark resolved / reopen).
create policy support_messages_owner_update on public.support_messages
  for update to authenticated
  using      (auth.uid() = '031a65ed-f52d-4a67-b271-47778e920c22')
  with check (auth.uid() = '031a65ed-f52d-4a67-b271-47778e920c22');

-- Owner-only delete.
create policy support_messages_owner_delete on public.support_messages
  for delete to authenticated
  using (auth.uid() = '031a65ed-f52d-4a67-b271-47778e920c22');

notify pgrst, 'reload schema';

-- Sanity check — after running, this should list ONLY the four policies above:
--   select policyname, cmd from pg_policies
--   where schemaname='public' and tablename='support_messages' order by policyname;
