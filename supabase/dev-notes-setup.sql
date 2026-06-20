-- ============================================================================
-- dev_notes — owner-authored release notes / dev updates, shown on the More
-- page for every signed-in user. Run once in the Supabase SQL editor.
--
-- Security model (mirrors admin_metrics): any signed-in user can READ notes,
-- but only the owner can INSERT/UPDATE/DELETE. Enforced server-side by RLS
-- against the owner UID, so the write controls in the Admin area cannot be
-- abused even if the client gate is bypassed.
-- ============================================================================

create table if not exists public.dev_notes (
  id          uuid primary key default gen_random_uuid(),
  note_date   text not null,                       -- display date, e.g. '6/20/2026'
  title       text not null,
  body        text not null,                        -- HTML (owner-authored)
  created_at  timestamptz not null default now()    -- primary ordering, newest first
);

alter table public.dev_notes enable row level security;

-- Read: any authenticated user (the app requires login to view anything).
drop policy if exists dev_notes_read on public.dev_notes;
create policy dev_notes_read on public.dev_notes
  for select to authenticated using (true);

-- Write: owner only.
drop policy if exists dev_notes_owner_write on public.dev_notes;
create policy dev_notes_owner_write on public.dev_notes
  for all to authenticated
  using      (auth.uid() = '031a65ed-f52d-4a67-b271-47778e920c22')
  with check (auth.uid() = '031a65ed-f52d-4a67-b271-47778e920c22');

-- Seed the four notes that previously lived hardcoded in index.html. Runs only
-- when the table is empty, so it is safe to re-run this whole file.
insert into public.dev_notes (note_date, title, body, created_at)
select v.note_date, v.title, v.body, v.created_at
from (values
  ('6/19/2026', 'Strength goals',
   $b$Building on the volume planning, I added a Training Goal toggle to the Plan tab: Hypertrophy, Strength, or Off. Hypertrophy is the volume-first view we already had. Strength works differently — since strength is driven more by heavy load than by total volume, this mode only counts your heavy sets (6 reps or fewer) toward each muscle's weekly target, and the "too much" thresholds come down accordingly. You set separate targets for each goal, so switching between them shows the right numbers. Off turns the whole volume system back off for a clean, simple log. Just note: the hypertrophy set ranges are well supported by research, but the strength thresholds are more of a sensible guideline than settled science — take those as a starting point.<div style="margin-top:8px">Citations:</div><div style="margin-top:2px">• <a href="https://pubmed.ncbi.nlm.nih.gov/28834797/" target="_blank" rel="noopener" style="color:var(--accent);text-decoration:none">Schoenfeld et al. (2017) — high- vs low-load &amp; strength</a></div><div style="margin-top:2px">• <a href="https://pubmed.ncbi.nlm.nih.gov/30153194/" target="_blank" rel="noopener" style="color:var(--accent);text-decoration:none">Schoenfeld et al. (2019) — volume drives hypertrophy, not strength</a></div>$b$,
   timestamptz '2026-06-19 22:00:00+00'),
  ('6/19/2026', 'Volume planning',
   $b$Tonight I reorganized the History area and added a Volume tab, which got me thinking about using volume as the primary way to plan workouts. The research shows hypertrophy is well driven by training a muscle close to failure a certain number of times each week. Volume here means the number of working sets you perform on a muscle in a given window — and if each of those sets is taken to within two to three reps of failure, then watching your weekly volume per muscle is a great guide for what to prioritize. (You don't need to grind to absolute failure, though — the research suggests stopping a couple reps short works nearly as well.) If it's Friday and you've only hit half your triceps target, the move is to prioritize triceps that day, rest them Saturday, and finish the volume Sunday.<div style="margin-top:8px">Citations:</div><div style="margin-top:2px">• <a href="https://pubmed.ncbi.nlm.nih.gov/27433992/" target="_blank" rel="noopener" style="color:var(--accent);text-decoration:none">Schoenfeld, Ogborn &amp; Krieger (2017) — weekly volume &amp; muscle mass</a></div><div style="margin-top:2px">• <a href="https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9935748/" target="_blank" rel="noopener" style="color:var(--accent);text-decoration:none">Refalo et al. (2023) — proximity-to-failure &amp; hypertrophy</a></div>$b$,
   timestamptz '2026-06-19 21:00:00+00'),
  ('6/19/2026', 'AI Macros',
   $b$Added a new AI Macros button to fill the search gap. It calls on Claude Haiku to make a best guess at the macros. The next level up would be to make that call web-enabled, which would improve the ability to call on branded products but at a significant increase to token use. This version should do well with staple food and in testing so far it has been so close with branded foods I've tried that it's well within acceptable for tracking daily macros. Please feel free to let me know if you think it's not hitting the mark, though.$b$,
   timestamptz '2026-06-19 20:00:00+00'),
  ('6/18/2026', 'Nutrition update',
   $b$I have removed the search function from the nutrition area. The search pulled from a USDA database and I found the results very unclean and difficult to work with. Searching for "Chicken wings" would pull up 50 results from a myriad of chicken wing brands, and the experience was just... kluged. For now, the original experience is in place. You just name the food and input the macro information manually. I'll continue to work on alternatives. In the meantime, I find it easy to enter a new food and run a quick google search for "[food name] nutrition" and that returns solid results.$b$,
   timestamptz '2026-06-18 20:00:00+00')
) as v(note_date, title, body, created_at)
where not exists (select 1 from public.dev_notes);

notify pgrst, 'reload schema';
