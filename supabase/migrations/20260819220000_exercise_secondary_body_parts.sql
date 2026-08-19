-- ----------------------------------------------------------------------------
-- exercises.secondary_body_parts
--
-- `body_part` is one value, and some real movements genuinely train two —
-- Deadlift is filed under Back but also loads the legs. Drake asked
-- directly: should Deadlift be able to show up under both, and the answer
-- is yes, as a real feature rather than a spreadsheet workaround.
--
-- `body_part` STAYS the single PRIMARY value; this is what it does not
-- capture. Deadlift is `body_part: 'back', secondary_body_parts: ['legs']`,
-- never `['back', 'legs']` with no primary — every reader (the library
-- filter pills, the matcher's body-part hint, the MCP tools) still has one
-- unambiguous "main" answer plus a set of others.
--
-- `body_part[]`, matching the existing `text[] not null default '{}'`
-- shape of `aliases` on this same table — an empty array, not null, so
-- every reader can iterate it without a null check.
--
-- ORDERING: apply and verify remote BEFORE a client build that sends this
-- column runs against the project. `exercises` is second in the sync push
-- order (right after `app_settings`), so PostgREST rejecting an unknown
-- column on this table aborts the whole run, pull included — the exact
-- failure mode `20260819180000` and `20260818160000` already document.
-- The dangling state is safe either way: the column defaults to `'{}'`,
-- which is exactly what every existing row means today (no secondaries).
-- ----------------------------------------------------------------------------

alter table public.exercises
  add column secondary_body_parts public.body_part[] not null default '{}';

-- Deadlift trains legs too. The one row that motivated this column, applied
-- by id (never by name — `01-data-model.md`'s seeded-IDs contract) so a
-- name correction elsewhere can never silently retarget this update.
update public.exercises
set secondary_body_parts = array['legs']::public.body_part[]
where id = 'ccd9e6e1-38a5-46d0-bc1b-eca51aed41bc';
