-- ----------------------------------------------------------------------------
-- app_settings.workout_calorie_rate — how much energy a logged workout claims
--
-- Copied from the reference app, which solved this more simply than any of the
-- alternatives considered: a FLAT RATE PER HOUR that the user picks, rather
-- than a MET table, a bodyweight calculation, or reading Active Energy back out
-- of HealthKit. `Settings accessed from profile page/` shows the screen —
-- None / Low / Medium / High / Very High, at 0 / 150 / 200 / 250 / 300 kcal per
-- hour, with Medium selected by default.
--
-- **Why a user-chosen rate is not the fabricated number this project keeps
-- refusing to write.** The objection to writing `0`, or to inventing a MET
-- estimate, is that the app would be presenting a figure it did not measure as
-- though it had. A rate the user selects is the opposite: it is the user
-- saying "count my lifting at roughly this", and the screen says exactly what
-- it does. `none` stays a first-class option and is what the app did before
-- this column existed.
--
-- An enum rather than `text`, unlike `theme` / `language` / `previous_set_
-- behavior` next to it. Those are text because their case lists are genuinely
-- undecided; this one is decided — five cases, taken from a shipped screen —
-- and docs/05-database.md's rule is that a settled list gets an enum so the
-- column rejects a value the client should never send.
--
-- ORDERING, and it is the same gate as `20260818160000`: this migration must be
-- applied and verified remote BEFORE a client that sends the column runs
-- against the project. `app_settings` is FIRST in the push order, so PostgREST
-- rejecting an unknown column would abort the entire sync run — pull included —
-- exactly as the missing grant did on 2026-08-19. The client change is a
-- separate commit with `supabase migration list` as the gate between them.
-- ----------------------------------------------------------------------------

create type public.workout_calorie_rate as enum (
  'none', 'low', 'medium', 'high', 'veryHigh'
);

-- `veryHigh` is camelCase to match the Swift raw value character for character,
-- which is the whole reason docs/05-database.md insisted the enums agree: the
-- client encodes its Swift enum directly and there is no mapping table between
-- the two spellings to get wrong.

alter table public.app_settings
  add column workout_calorie_rate public.workout_calorie_rate not null default 'medium';

-- `medium` matches the reference app's default. A column added to a table that
-- already has a row needs a default anyway, and defaulting to `none` would mean
-- the setting silently did nothing until found — the failure this project has
-- already shipped twice (the hardcoded rest timer, the unread unit settings).
