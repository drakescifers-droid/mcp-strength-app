-- ============================================================================
-- 0005 — workout_exercises gains sticky_note and default_rest_seconds
--
-- The per-exercise menu is identical in a template and in a live workout, so
-- the two tables have to be able to hold the same answers. `template_exercises`
-- already had both of these; `workout_exercises` did not, which would have
-- meant two of the eight menu items being greyed out mid-workout — the
-- identical menu failing to be identical.
--
-- ## Why now, on a table that already exists
--
-- Because it is free right now and will not be later. The account holds no
-- training data, nothing has ever synced, and there are no other devices to
-- migrate. The same two columns added after Phase 2 ships are an ALTER against
-- rows the user cares about, on a table every client reads.
--
-- This is the argument `04-status.md` makes about the Program schema —
-- "additive-by-construction only helps if the columns exist before there are
-- users" — applied on purpose rather than discovered late.
--
-- ## Deliberately NOT NULL with a default
--
-- `default_rest_seconds` mirrors the SwiftData side, where the property is
-- non-optional with a declaration default of 90. A nullable column here would
-- let a row arrive with no default rest and force every reader to invent one,
-- which is how two clients end up inventing different ones.
--
-- `sticky_note` IS nullable: absent is a real and common state for a note, and
-- an empty string would be a different, worse way of saying the same thing.
-- ============================================================================

alter table public.workout_exercises
  add column sticky_note text,
  add column default_rest_seconds integer not null default 90;

alter table public.workout_exercises
  add constraint workout_exercises_rest_nonneg check (default_rest_seconds >= 0);

comment on column public.workout_exercises.sticky_note is
  'A note pinned while logging. Mirrors template_exercises.sticky_note so the '
  'per-exercise menu can be identical in both places.';

comment on column public.workout_exercises.default_rest_seconds is
  'Rest that new sets inherit. Per-set workout_sets.rest_seconds still '
  'overrides it. Mirrors template_exercises.default_rest_seconds.';
