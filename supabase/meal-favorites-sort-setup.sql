-- meal_favorites — add a created_at so the Nutrition "Favorites" list can sort
-- by Recent. Run once in the Supabase SQL editor.
--
-- The client never writes this column (it relies on the default), so favorite
-- saving keeps working with or without this migration; running it just makes
-- "Recent" accurate across reloads. Existing rows get the migration time.

alter table public.meal_favorites add column if not exists created_at timestamptz not null default now();

notify pgrst, 'reload schema';
