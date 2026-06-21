-- ============================================================================
-- macro_cache — shared, self-improving cache of nutrition macros for the
-- AI Macros feature. Run once in the Supabase SQL editor.
--
-- How it works:
--   * Keyed on a normalized food name + unit class + clarification.
--   * Stores macros per CANONICAL unit (per gram for weight, per ml for volume,
--     per item for counts), so ANY quantity of the same food is a cache hit and
--     is just scaled — not a fresh AI call.
--   * Populated only from USER-ACCEPTED values (what the user actually saved,
--     after any edits), via an incremental running mean so the stored value
--     converges to consensus and a single bad entry barely moves it.
--
-- Security: this table is written/read ONLY by the ai-macros Edge Function using
-- the service-role key (which bypasses RLS). RLS is enabled with no policies and
-- grants are revoked from anon/authenticated, so the browser can neither read
-- nor write it — no cache poisoning, no exposure of who entered what.
-- ============================================================================

create table if not exists public.macro_cache (
  food_key   text not null,                 -- normalized food name
  unit_class text not null,                 -- 'wt' | 'vol' | 'ct:units' | 'ct:slice' | …
  clar_key   text not null default '',      -- normalized clarification (may be '')
  cal_per    double precision not null,     -- calories per 1 canonical unit (g / ml / item)
  pro_per    double precision not null,     -- protein  (g) per canonical unit
  carb_per   double precision not null,     -- carbs    (g) per canonical unit
  fat_per    double precision not null,     -- fat      (g) per canonical unit
  samples    integer not null default 1,    -- how many accepted entries fed the mean
  basis      text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (food_key, unit_class, clar_key)
);

alter table public.macro_cache enable row level security;
-- No policies on purpose: only the service role (Edge Function) may touch it.
revoke all on public.macro_cache from anon, authenticated;

-- Atomic upsert that folds a new accepted sample into the running mean. Doing
-- this in one statement avoids read-modify-write races between concurrent saves.
create or replace function public.macro_cache_record(
  p_food_key text, p_unit_class text, p_clar_key text,
  p_cal double precision, p_pro double precision, p_carb double precision, p_fat double precision,
  p_basis text
) returns void
language sql
security definer
set search_path = public
as $$
  insert into public.macro_cache as mc
    (food_key, unit_class, clar_key, cal_per, pro_per, carb_per, fat_per, samples, basis, updated_at)
  values
    (p_food_key, p_unit_class, p_clar_key, p_cal, p_pro, p_carb, p_fat, 1, coalesce(p_basis,''), now())
  on conflict (food_key, unit_class, clar_key) do update set
    cal_per  = mc.cal_per  + (excluded.cal_per  - mc.cal_per ) / (mc.samples + 1),
    pro_per  = mc.pro_per  + (excluded.pro_per  - mc.pro_per ) / (mc.samples + 1),
    carb_per = mc.carb_per + (excluded.carb_per - mc.carb_per) / (mc.samples + 1),
    fat_per  = mc.fat_per  + (excluded.fat_per  - mc.fat_per ) / (mc.samples + 1),
    samples  = mc.samples + 1,
    basis    = coalesce(excluded.basis, mc.basis),
    updated_at = now();
$$;

revoke all on function public.macro_cache_record(text,text,text,double precision,double precision,double precision,double precision,text) from public, anon, authenticated;
grant execute on function public.macro_cache_record(text,text,text,double precision,double precision,double precision,double precision,text) to service_role;

notify pgrst, 'reload schema';
