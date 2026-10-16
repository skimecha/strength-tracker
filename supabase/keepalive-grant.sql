-- Keep-alive grant — run once in the Supabase SQL editor (after restoring
-- the project from the 2026-10-16 pause).
--
-- Lets the keep-alive GitHub Action perform a real anonymous SELECT, which is
-- what Supabase's database-centric inactivity heuristic counts. Zero data
-- exposure: dev_notes RLS has no anon policy, so anon receives 200 + [] —
-- but the query genuinely executes in Postgres.

grant select on public.dev_notes to anon;

notify pgrst, 'reload schema';
