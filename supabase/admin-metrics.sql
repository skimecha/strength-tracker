-- ============================================================================
-- admin_metrics — owner-only app stats (registered user count, etc.).
-- Run once in the Supabase SQL editor.
--
-- Security model: this is the ONLY guarantee that matters. The function runs
-- security definer (so it can read auth.users) but checks auth.uid() against
-- the owner UID on every call. Anyone who is not the owner — even with a valid
-- session, even calling the RPC directly — gets NULL back. No row, no count,
-- nothing. The client also hides the call behind isOwner(), but that is just
-- UX: the real lock lives here, server-side, and cannot be bypassed from the
-- browser because auth.uid() comes from the signed JWT.
-- ============================================================================

create or replace function public.admin_metrics()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Owner UID (matches OWNER_UID in index.html). To rotate the owner, change
  -- this value; nothing in the client can grant access on its own.
  admin_uid constant uuid := '031a65ed-f52d-4a67-b271-47778e920c22';
begin
  if auth.uid() is null or auth.uid() <> admin_uid then
    return null;  -- non-owners get nothing, no matter how they call this
  end if;

  return jsonb_build_object(
    'users',     (select count(*) from auth.users),
    'confirmed', (select count(*) from auth.users where email_confirmed_at is not null),
    'new_7d',    (select count(*) from auth.users where created_at >= now() - interval '7 days')
  );
end;
$$;

-- Execute is granted to PUBLIC by default for new functions; lock that down so
-- only authenticated sessions can even reach the (self-authorizing) function.
revoke all on function public.admin_metrics() from public, anon;
grant execute on function public.admin_metrics() to authenticated;

notify pgrst, 'reload schema';
